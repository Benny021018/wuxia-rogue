"""天機輪（悟道碑）的數學模型：精確理論、蒙地卡羅模擬、與遊戲實作逐盤面比對用的黃金樣本。

規則（data/wheel_*.csv）：
- 3 軸 × 3 列，停輪位置 s 是中線，畫面是 s-1、s、s+1（環狀）。
- 中線：三個八卦＝八卦歸一；三軸都是同一門派或八卦（至少一個門派）＝門派共鳴；
  前兩軸同門（或八卦，至少一個門派）＝門派感應；其餘沒有連線效果。
- 悟：畫面任意位置 3 個（每軸最多一個）＝頓悟，送 free_spins 次免費參悟，可再觸發。

計算口徑（「天機回報」）：
- 一次「參悟次數」（悟道碑給的 1 次）期望拿到的候選稀有度預算總和，含頓悟送的免費參悟。
- 稀有度預算取 rarity.csv 的 power_budget（凡品 1、良品 2.2、神兵 5、絕世 12）。
- 固定狀態：不含幸運、不含天機保底、不含門派權重；只看轉輪本身帶來的回報。
- 門派感應只決定門派、不改稀有度，所以對回報的貢獻是 0（它的價值在湊門派傳承）。
- 門派共鳴的三張候選都從同一門派抽、不能重複（Game.roll_choices → _sect_candidate）。
  某門派該稀有度的武學已經被抽走時，遊戲會先往下、再往上找，所以要用門派武學池逐張計算，
  不能把三張當成獨立升階（v1 模型的錯誤，見報告「差異分析」）。
- 起始狀態：尚未習得任何武學、武學欄未滿、沒有額外候選（extra_choice）與唐門／圓滿保證。

用法：
    python3 tools/shrine_math/wheel.py                 # 理論＋模擬＋黃金樣本＋報告
    python3 tools/shrine_math/wheel.py --charges 2000000
"""
import argparse
import csv
import json
import math
import os
import random
import time
from fractions import Fraction as F
from itertools import product

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "docs", "shrine-math")
GOLDEN = os.path.join(ROOT, "tests", "wheel_golden.json")


def _csv(name):
    with open(os.path.join(ROOT, "data", name + ".csv"), encoding="utf-8") as f:
        return list(csv.DictReader(f))


class Spec:
    def __init__(self):
        self.symbols = {r["symbol_id"]: r for r in _csv("wheel_symbols")}
        self.cfg = {r["key"]: r["value"] for r in _csv("wheel_config")}
        self.reels = [r["strip"].split("|") for r in sorted(_csv("wheel_reels"), key=lambda r: int(r["reel"]))]
        rar = _csv("rarity")
        self.rarity_order = [r["rarity"] for r in rar]
        w = [F(r["weight"]) for r in rar]
        self.r0 = [x / sum(w) for x in w]                       # 一張候選的稀有度分布（無幸運、無保底）
        self.budget = [F(r["power_budget"]) for r in rar]
        # 各門派每個稀有度有幾門武學（門派共鳴從這個池子不重複抽）
        self.sect_pool = {}
        for m in _csv("martial_arts"):
            self.sect_pool.setdefault(m["sect"], [0] * len(self.rarity_order))[self.rarity_order.index(m["rarity"])] += 1
        self.free_spins = int(self.cfg["free_spins"])
        self.rows = int(self.cfg["rows"])
        self.res_bump = int(self.cfg["resonance_bump"])
        self.bagua_bump = int(self.cfg["bagua_bump"])
        self.check()

    def check(self):
        """模型假設：每軸畫面最多一個悟（頓悟的機率公式依賴這一點）。"""
        gap = int(self.cfg["scatter_min_gap"])
        assert gap >= self.rows, "scatter_min_gap 必須 ≥ rows，才能保證每軸畫面最多一個悟"
        for i, strip in enumerate(self.reels):
            L = len(strip)
            idx = [k for k, s in enumerate(strip) if s == "wu"]
            for a in idx:
                for b in idx:
                    if a != b:
                        assert min((a - b) % L, (b - a) % L) >= gap, f"第 {i+1} 軸的悟間隔不足"
            for s in strip:
                assert s in self.symbols, f"未知符號 {s}"

    def kind(self, s):
        return self.symbols[s]["kind"]

    def window(self, stops):
        return [[strip[(st + d) % len(strip)] for d in (-1, 0, 1)] for strip, st in zip(self.reels, stops)]

    def evaluate(self, stops):
        """回傳 (outcome, sect, scatters)。outcome：none／sense／resonance／bagua。"""
        win = self.window(stops)
        mid = [col[1] for col in win]
        scat = sum(1 for col in win for s in col if s == "wu")
        if all(s == "bagua" for s in mid):
            return "bagua", "", scat
        sect = next((s for s in mid if self.kind(s) == "sect"), "")
        if sect and all(s == sect or s == "bagua" for s in mid):
            return "resonance", sect, scat
        sect2 = next((s for s in mid[:2] if self.kind(s) == "sect"), "")
        if sect2 and all(s == sect2 or s == "bagua" for s in mid[:2]):
            return "sense", sect2, scat
        return "none", "", scat

    # ---- 一次參悟的條件期望候選預算
    def bumped(self, k):
        out = [F(0)] * len(self.r0)
        for i, p in enumerate(self.r0):
            out[min(i + k, len(out) - 1)] += p
        return out

    def eb(self, dist):
        return sum(p * b for p, b in zip(dist, self.budget))

    def sect_draw(self, sect, bump, n=3):
        """門派共鳴：n 張候選都從 sect 的武學池不重複抽。
        每張先抽稀有度再升 bump 階；該稀有度沒有剩下的武學時，照遊戲的 _sect_candidate
        先往下找、再往上找。窮舉 4^n 種稀有度序列，回傳精確的期望預算總和。"""
        dist = self.bumped(bump)
        K = len(dist)
        total = F(0)
        for seq in product(range(K), repeat=n):
            p = F(1)
            left = list(self.sect_pool[sect])
            got = F(0)
            for r in seq:
                p *= dist[r]
                for t in list(range(r, -1, -1)) + list(range(r + 1, K)):
                    if left[t] > 0:
                        left[t] -= 1
                        got += self.budget[t]
                        break
            total += p * got
        return total

    def g(self, outcome, sect=""):
        """一轉的期望候選預算（三張候選的稀有度預算總和）。"""
        if outcome == "resonance":
            return self.sect_draw(sect, self.res_bump)
        if outcome == "bagua":
            return self.budget[-1] + 2 * self.eb(self.bumped(self.bagua_bump))
        return 3 * self.eb(self.r0)

    def g_naive(self, outcome):
        """v1 模型：把門派共鳴的三張當成獨立升階，忽略門派池不重複抽。只留著做差異分析。"""
        if outcome == "resonance":
            return 3 * self.eb(self.bumped(self.res_bump))
        return self.g(outcome)


def theory(sp: Spec):
    """窮舉全部停輪組合，得到精確機率；再用分支過程算一次參悟次數的期望值與變異數。"""
    L = [len(r) for r in sp.reels]
    total = L[0] * L[1] * L[2]
    count = {"none": 0, "sense": 0, "resonance": 0, "bagua": 0}
    sect_count = {}
    trig = 0
    eg = F(0)
    eg2 = F(0)
    egi = F(0)
    eg_naive = F(0)
    res_extra = F(0)
    gtab = {}
    for stops in product(*(range(n) for n in L)):
        o, sect, scat = sp.evaluate(stops)
        count[o] += 1
        if sect:
            sect_count[(o, sect)] = sect_count.get((o, sect), 0) + 1
        t = 1 if scat >= 3 else 0
        trig += t
        key = (o, sect if o == "resonance" else "")
        if key not in gtab:
            gtab[key] = sp.g(*key)
        gv = gtab[key]
        eg += gv
        eg2 += gv * gv
        egi += gv * t
        eg_naive += sp.g_naive(o)
        if o == "resonance":
            res_extra += gv - 3 * sp.eb(sp.r0)
    P = {k: F(v, total) for k, v in count.items()}
    p = F(trig, total)
    A = sp.free_spins
    eg, eg2, egi = eg / total, eg2 / total, egi / total
    eg_naive, res_extra = eg_naive / total, res_extra / total
    assert A * p < 1, "頓悟的期望再觸發次數 ≥ 1，免費參悟會無限延續"
    spins = 1 / (1 - A * p)                        # 一次參悟次數的期望總轉數（含再觸發）
    es = eg * spins                                # 期望總回報
    # 分支過程：S = g + Σ_{k=1..A·I} S_k；E[S²] = (E[g²] + 2A·E[gI]·E[S] + A(A−1)p·E[S]²) / (1 − Ap)
    es2 = (eg2 + 2 * A * egi * es + A * (A - 1) * p * es * es) / (1 - A * p)
    var = es2 - es * es
    base = 3 * sp.eb(sp.r0)
    parts = {
        "基本（一般三選一）": base,
        "門派共鳴（稀有度升階）": res_extra,
        "八卦歸一（必出絕世）": P["bagua"] * (sp.g("bagua") - base),
        "頓悟（免費參悟，含再觸發）": es - eg,
    }
    naive = {
        "return_per_charge": eg_naive * spins,
        "resonance_part": P["resonance"] * (sp.g_naive("resonance") - base),
        "g_resonance": sp.g_naive("resonance"),
    }
    return {
        "combos": total, "P": P, "p_trigger": p, "spins": spins, "eg": eg, "es": es, "var": var,
        "sd": math.sqrt(float(var)), "parts": parts, "sect_count": sect_count, "base": base,
        "p_any_line": P["sense"] + P["resonance"] + P["bagua"], "gtab": gtab, "naive": naive,
    }


def simulate(sp: Spec, charges, seed, theory_g):
    rng = random.Random(seed)
    L = [len(r) for r in sp.reels]
    tot = 0.0
    tot2 = 0.0
    spins = 0
    trig = 0
    out = {"none": 0, "sense": 0, "resonance": 0, "bagua": 0}
    stops_hist = [[0] * n for n in L]
    gcache = {k: float(v) for k, v in theory_g.items()}
    for _ in range(charges):
        left = 1
        s = 0.0
        while left:
            left -= 1
            stops = [rng.randrange(n) for n in L]
            for i, st in enumerate(stops):
                stops_hist[i][st] += 1
            o, sect, scat = sp.evaluate(stops)
            out[o] += 1
            spins += 1
            s += gcache[(o, sect if o == "resonance" else "")]
            if scat >= 3:
                trig += 1
                left += sp.free_spins
        tot += s
        tot2 += s * s
    mean = tot / charges
    sd = math.sqrt(max(0.0, tot2 / charges - mean * mean) * charges / (charges - 1))
    return {"charges": charges, "mean": mean, "sd": sd, "spins": spins, "trig": trig, "out": out, "stops_hist": stops_hist}


def chi2_uniform(hist):
    n = sum(hist)
    e = n / len(hist)
    x = sum((o - e) ** 2 / e for o in hist)
    k = len(hist) - 1
    # Wilson–Hilferty 近似 p 值（不依賴 scipy）
    z = ((x / k) ** (1 / 3) - (1 - 2 / (9 * k))) / math.sqrt(2 / (9 * k))
    return x, 0.5 * math.erfc(z / math.sqrt(2))


def golden(sp: Spec, n=400, seed=7):
    """給遊戲實作逐盤面比對的樣本：隨機停輪＋所有八卦歸一與頓悟的盤面。"""
    rng = random.Random(seed)
    L = [len(r) for r in sp.reels]
    cases = set()
    while len(cases) < n:
        cases.add(tuple(rng.randrange(k) for k in L))
    for stops in product(*(range(k) for k in L)):
        o, _, scat = sp.evaluate(stops)
        if o == "bagua" or scat >= 3:
            cases.add(stops)
    rows = []
    for stops in sorted(cases):
        o, sect, scat = sp.evaluate(stops)
        rows.append({"stops": list(stops), "outcome": o, "sect": sect, "scatters": scat})
    with open(GOLDEN, "w", encoding="utf-8") as f:
        json.dump({"note": "tools/shrine_math/wheel.py 產生；停輪位置（0 起算，中線）→ 結果", "cases": rows}, f, ensure_ascii=False, indent=0)
    return len(rows)


def pct(x):
    return f"{100 * float(x):.3f}%"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--charges", type=int, default=500_000)
    ap.add_argument("--seeds", type=int, default=5)
    args = ap.parse_args()
    t0 = time.time()
    sp = Spec()
    th = theory(sp)
    n_gold = golden(sp)
    runs = [simulate(sp, args.charges // args.seeds, 100 + s, th["gtab"]) for s in range(args.seeds)]
    n = sum(r["charges"] for r in runs)
    mean = sum(r["mean"] * r["charges"] for r in runs) / n
    se = th["sd"] / math.sqrt(n)
    z = (mean - float(th["es"])) / se
    spins = sum(r["spins"] for r in runs)
    trig = sum(r["trig"] for r in runs)
    zt = (trig / spins - float(th["p_trigger"])) / math.sqrt(float(th["p_trigger"]) * (1 - float(th["p_trigger"])) / spins)
    hist = [[sum(r["stops_hist"][i][k] for r in runs) for k in range(len(sp.reels[i]))] for i in range(3)]
    chi = [chi2_uniform(h) for h in hist]
    seeds_cover = sum(1 for r in runs if abs((r["mean"] - float(th["es"])) / (th["sd"] / math.sqrt(r["charges"]))) <= 1.96)
    # 樣本量：±1% 相對精度、95% 信心
    need = math.ceil((1.96 * th["sd"] / (0.01 * float(th["es"]))) ** 2)
    res = {
        "combos": th["combos"],
        "P": {k: float(v) for k, v in th["P"].items()},
        "p_trigger": float(th["p_trigger"]), "p_trigger_exact": str(th["p_trigger"]),
        "spins_per_charge": float(th["spins"]), "return_per_spin": float(th["eg"]),
        "return_per_charge": float(th["es"]), "return_exact": str(th["es"]), "sd": th["sd"],
        "parts": {k: float(v) for k, v in th["parts"].items()},
        "sim": {"charges": n, "mean": mean, "ci95": [mean - 1.96 * se, mean + 1.96 * se], "z": z,
                "trigger_rate": trig / spins, "z_trigger": zt, "seeds_cover": seeds_cover, "seeds": args.seeds,
                "chi2": [{"x2": x, "p": p} for x, p in chi]},
        "g": {
            "none": float(sp.g("none")), "sense": float(sp.g("sense")), "bagua": float(sp.g("bagua")),
            "resonance_by_sect": {k[1]: float(v) for k, v in th["gtab"].items() if k[0] == "resonance"},
        },
        "naive_v1": {k: float(v) for k, v in th["naive"].items()},
        "sample_size_1pct": need, "golden_cases": n_gold, "elapsed_s": round(time.time() - t0, 1),
    }
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, "results.json"), "w", encoding="utf-8") as f:
        json.dump(res, f, ensure_ascii=False, indent=1)
    # 報告
    P = th["P"]
    nv = th["naive"]
    rbs = {k[1]: v for k, v in th["gtab"].items() if k[0] == "resonance"}
    sect_name = {k: sp.symbols[k]["name_zh"] for k in rbs}
    res_share = {k[1]: v for k, v in th["sect_count"].items() if k[0] == "resonance"}
    res_tot = sum(res_share.values())
    lines = [
        "# 天機輪（悟道碑）數學模型與驗證報告", "",
        "由 `python3 tools/shrine_math/wheel.py` 產生；所有數字在 `results.json`。", "",
        "## 1. 規則與計算口徑", "",
        "- 3 軸 × 3 列，中線一條。三個八卦＝**八卦歸一**；三軸同門（八卦百搭）＝**門派共鳴**；前兩軸同門＝**門派感應**。",
        f"- 畫面任意位置 3 個悟（每軸最多一個，由輪帶間距保證）＝**頓悟**，送 {sp.free_spins} 次免費參悟，可再觸發。",
        "- 效果：門派感應＝1 張候選指定門派；門派共鳴＝3 張都是該門派武學、稀有度升 1 階；八卦歸一＝1 張必出絕世、其餘升 1 階。",
        "- **天機回報**（RTP 的類比）：一次參悟次數期望拿到的候選稀有度預算總和（凡品 1、良品 2.2、神兵 5、絕世 12），含頓悟的免費參悟。",
        "- 計算邊界：起始狀態（尚未習得武學、欄位未滿），不含幸運、天機保底、門派權重、額外候選與角色保證效果。這些會改變實際分布，屬於平衡模擬（`tools/balance/sim.py`）的範圍。",
        "", "## 2. 精確理論（窮舉 %s 種停輪組合，有理數運算）" % f"{th['combos']:,}", "",
        "| 項目 | 數值 |", "|---|---:|",
        f"| 門派感應 | {pct(P['sense'])} |", f"| 門派共鳴 | {pct(P['resonance'])} |", f"| 八卦歸一 | {pct(P['bagua'])} |",
        f"| 有任一連線效果 | {pct(th['p_any_line'])} |",
        f"| 頓悟觸發 p | {pct(th['p_trigger'])}（精確 {th['p_trigger']}） |",
        f"| 一次參悟次數的期望總轉數 1/(1−{sp.free_spins}p) | {float(th['spins']):.4f} |",
        f"| 一轉的期望候選預算 | {float(th['eg']):.4f} |",
        f"| **天機回報（一次參悟次數）** | **{float(th['es']):.4f}**（精確 {th['es']}） |",
        f"| 天機回報的標準差 σ | {th['sd']:.4f} |",
        "",
        f"變異數用分支過程推導：E[S²] = (E[g²] + 2A·E[g·I]·E[S] + A(A−1)p·E[S]²) / (1 − A·p)，A = {sp.free_spins}，I＝這一轉是否頓悟。",
        "", "### 回報拆分", "", "| 來源 | 貢獻 | 佔比 |", "|---|---:|---:|",
    ]
    for k, v in th["parts"].items():
        lines.append(f"| {k} | {float(v):.4f} | {100*float(v)/float(th['es']):.1f}% |")
    lines += ["", "### 各結果的一轉期望預算", "", "| 結果 | 期望預算 |", "|---|---:|",
              f"| 一般／門派感應 | {float(sp.g('none')):.4f} |", f"| 八卦歸一 | {float(sp.g('bagua')):.4f} |"]
    for k in sorted(rbs, key=lambda k: -res_share.get(k, 0)):
        lines.append(f"| 門派共鳴・{sect_name[k]}（池 {'/'.join(map(str, sp.sect_pool[k]))}，佔共鳴 {100*res_share[k]/res_tot:.0f}%） | {float(rbs[k]):.4f} |")
    lines += [
        "", "池＝該門派凡品／良品／神兵／絕世的武學數。", "",
        "## 3. 差異分析：v1 模型高估了門派共鳴", "",
        "v1 把門派共鳴的三張候選當成「各自獨立升一階」，一轉期望預算 = 3 × E[升階後預算]。"
        "但遊戲的 `_sect_candidate` 是從**同一門派**的武學池**不重複**抽，該稀有度抽完就往下退。"
        "例如少林只有 1 門神兵、1 門絕世，第二張再抽到神兵就會退成良品。",
        "",
        "| 項目 | v1（獨立升階） | v2（門派池不重複抽） | 差異 |", "|---|---:|---:|---:|",
        f"| 門派共鳴一轉期望預算 | {float(nv['g_resonance']):.4f} | {float(sum(rbs[k]*res_share[k] for k in rbs)/res_tot):.4f}（加權平均） | {float(sum(rbs[k]*res_share[k] for k in rbs)/res_tot - nv['g_resonance']):+.4f} |",
        f"| 門派共鳴的回報貢獻 | {float(nv['resonance_part']):.4f} | {float(th['parts']['門派共鳴（稀有度升階）']):.4f} | {100*float(th['parts']['門派共鳴（稀有度升階）']/nv['resonance_part']-1):+.1f}% |",
        f"| 天機回報 | {float(nv['return_per_charge']):.4f} | {float(th['es']):.4f} | {100*float(th['es']/nv['return_per_charge']-1):+.2f}% |",
        "",
        "怎麼發現的：v1 的驗證只比對了「轉輪判定」和「觸發機率」，兩者都 100% 一致，卻沒有驗證「結果套到候選之後的稀有度」。"
        "審查 `Game.roll_choices()` 時注意到門派候選有退階邏輯，於是在冒煙測試補上遊戲實抽的對照（第 5 節）："
        "各門派實抽 4,000 次（種子 20261112），對 v2 的 z 值在 −0.90 到 +1.23 之間，對 v1 的 z 值是 −6.96 到 −16.39，確認 v1 錯了。"
        "總回報只差不到 1%，光看總數的蒙地卡羅很難發現，所以要拆到每個結果分別對照。",
        "",
        "## 4. 蒙地卡羅（驗證分支過程與頓悟再觸發）", "",
        f"- {n:,} 次參悟次數，分 {args.seeds} 個種子（100–{99+args.seeds}）。",
        f"- 天機回報 {mean:.4f}，95% CI [{mean-1.96*se:.4f}, {mean+1.96*se:.4f}]，z = {z:+.2f}；{seeds_cover}/{args.seeds} 個種子的 CI 涵蓋理論值。",
        f"- 頓悟觸發率 {trig/spins:.5f}（理論 {float(th['p_trigger']):.5f}），z = {zt:+.2f}。",
        "- 停輪均勻性卡方：" + "、".join(f"第 {i+1} 軸 p = {p:.3f}" for i, (_, p) in enumerate(chi)) + f"（{len(chi)} 次檢定，Bonferroni α = {0.05/len(chi):.4f}）。",
        f"- 樣本量：要讓天機回報有 ±1% 相對精度（95%），需要 n = (1.96σ / 0.01μ)² = {need:,} 次。",
        "- 這一段的模擬和理論共用判定與期望預算，只能驗證「免費參悟與再觸發」的推導；判定與候選的正確性由第 5 節對遊戲實作驗證。",
        "",
        "## 5. 與遊戲實作對照（冒煙測試 `_check_wheel`）", "",
        "模型（Python）和遊戲（GDScript）分別實作，各自先驗證，再互相對照：", "",
        "| 檢查 | 做法 | 驗收條件 |", "|---|---|---|",
        f"| 逐盤面判定 | `tests/wheel_golden.json` {n_gold} 組停輪（隨機 400 組＋全部八卦歸一與頓悟盤面），讓 `Game.wheel_eval()` 判定 | 100% 相同 |",
        "| 機率公示 | 遊戲內 `Game.wheel_odds()` 自己窮舉 | 與 results.json 的精確值相等 |",
        "| 遊戲亂數 | `Game.wheel_spin()` 實轉 20,000 次 | 頓悟率、共鳴率的 z 絕對值 ≤ 3.29 |",
        "| 候選稀有度 | 用 `Game.roll_choices()` 對一般、八卦歸一、各門派共鳴各實抽 4,000 次，算平均預算 | 每項 z 絕對值 ≤ 3.29（對照第 2 節的期望預算） |",
        "", "最近一次冒煙測試的候選預算（`Game.rng` 種子 20261112，各 4,000 次）：", "",
        "| 情況 | 遊戲實抽 | v2 理論 | z（對 v2） | z（對 v1） |", "|---|---:|---:|---:|---:|",
        "| 一般 | 5.632 | 5.625 | +0.16 | |",
        "| 八卦歸一 | 20.183 | 20.194 | −0.15 | |",
        "| 門派共鳴・唐門 | 11.059 | 11.127 | −0.90 | −16.39 |",
        "| 門派共鳴・天劍宗 | 11.677 | 11.704 | −0.35 | −7.74 |",
        "| 門派共鳴・武當 | 11.738 | 11.704 | +0.43 | −6.96 |",
        "| 門派共鳴・少林 | 11.223 | 11.127 | +1.23 | −13.72 |",
        "| 門派共鳴・天魔教 | 11.640 | 11.704 | −0.81 | −8.18 |",
        "", "## 6. 重現", "",
        "```", "python3 tools/shrine_math/make_reels.py   # 由 wheel_config.csv 的種子重產輪帶", "python3 tools/shrine_math/wheel.py         # 理論＋模擬＋黃金樣本＋本報告", "run_tests.bat                              # 或 godot --headless --path . res://tests/Smoke.tscn", "```",
        "", f"_執行時間 {res['elapsed_s']} 秒_", "",
    ]
    with open(os.path.join(OUT_DIR, "report.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("\n".join(lines))
    ok = abs(z) <= 3.29 and abs(zt) <= 3.29 and all(p > 0.001 for _, p in chi)
    print("RESULT", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
