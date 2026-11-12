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

    def g(self, outcome):
        if outcome == "resonance":
            return 3 * self.eb(self.bumped(self.res_bump))
        if outcome == "bagua":
            return self.budget[-1] + 2 * self.eb(self.bumped(self.bagua_bump))
        return 3 * self.eb(self.r0)


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
    for stops in product(*(range(n) for n in L)):
        o, sect, scat = sp.evaluate(stops)
        count[o] += 1
        if sect:
            sect_count[(o, sect)] = sect_count.get((o, sect), 0) + 1
        t = 1 if scat >= 3 else 0
        trig += t
        gv = sp.g(o)
        eg += gv
        eg2 += gv * gv
        egi += gv * t
    P = {k: F(v, total) for k, v in count.items()}
    p = F(trig, total)
    A = sp.free_spins
    eg, eg2, egi = eg / total, eg2 / total, egi / total
    assert A * p < 1, "頓悟的期望再觸發次數 ≥ 1，免費參悟會無限延續"
    spins = 1 / (1 - A * p)                        # 一次參悟次數的期望總轉數（含再觸發）
    es = eg * spins                                # 期望總回報
    # 分支過程：S = g + Σ_{k=1..A·I} S_k；E[S²] = (E[g²] + 2A·E[gI]·E[S] + A(A−1)p·E[S]²) / (1 − Ap)
    es2 = (eg2 + 2 * A * egi * es + A * (A - 1) * p * es * es) / (1 - A * p)
    var = es2 - es * es
    base = 3 * sp.eb(sp.r0)
    parts = {
        "基本（一般三選一）": base,
        "門派共鳴（稀有度升階）": P["resonance"] * (sp.g("resonance") - base),
        "八卦歸一（必出絕世）": P["bagua"] * (sp.g("bagua") - base),
        "頓悟（免費參悟，含再觸發）": es - eg,
    }
    return {
        "combos": total, "P": P, "p_trigger": p, "spins": spins, "eg": eg, "es": es, "var": var,
        "sd": math.sqrt(float(var)), "parts": parts, "sect_count": sect_count, "base": base,
        "p_any_line": P["sense"] + P["resonance"] + P["bagua"],
    }


def simulate(sp: Spec, charges, seed):
    rng = random.Random(seed)
    L = [len(r) for r in sp.reels]
    tot = 0.0
    tot2 = 0.0
    spins = 0
    trig = 0
    out = {"none": 0, "sense": 0, "resonance": 0, "bagua": 0}
    stops_hist = [[0] * n for n in L]
    gcache = {o: float(sp.g(o)) for o in out}
    for _ in range(charges):
        left = 1
        s = 0.0
        while left:
            left -= 1
            stops = [rng.randrange(n) for n in L]
            for i, st in enumerate(stops):
                stops_hist[i][st] += 1
            o, _, scat = sp.evaluate(stops)
            out[o] += 1
            spins += 1
            s += gcache[o]
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
    ap.add_argument("--charges", type=int, default=1_000_000)
    ap.add_argument("--seeds", type=int, default=5)
    args = ap.parse_args()
    t0 = time.time()
    sp = Spec()
    th = theory(sp)
    n_gold = golden(sp)
    runs = [simulate(sp, args.charges // args.seeds, 100 + s) for s in range(args.seeds)]
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
        "sample_size_1pct": need, "golden_cases": n_gold, "elapsed_s": round(time.time() - t0, 1),
    }
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, "results.json"), "w", encoding="utf-8") as f:
        json.dump(res, f, ensure_ascii=False, indent=1)
    # 報告
    P = th["P"]
    lines = [
        "# 天機輪（悟道碑）數學模型與驗證報告", "",
        "由 `python3 tools/shrine_math/wheel.py` 產生；所有數字在 `results.json`。", "",
        "## 1. 規則與計算口徑", "",
        "- 3 軸 × 3 列，中線一條。三個八卦＝**八卦歸一**；三軸同門（八卦百搭）＝**門派共鳴**；前兩軸同門＝**門派感應**。",
        f"- 畫面任意位置 3 個悟（每軸最多一個）＝**頓悟**，送 {sp.free_spins} 次免費參悟，可再觸發。",
        "- 天機回報：一次參悟次數期望拿到的候選稀有度預算總和（凡品 1、良品 2.2、神兵 5、絕世 12），含頓悟的免費參悟；不含幸運、天機保底與門派權重。",
        "", "## 2. 精確理論（窮舉 %s 種停輪組合）" % f"{th['combos']:,}", "",
        "| 項目 | 數值 |", "|---|---:|",
        f"| 門派感應 | {pct(P['sense'])} |", f"| 門派共鳴 | {pct(P['resonance'])} |", f"| 八卦歸一 | {pct(P['bagua'])} |",
        f"| 有任一連線效果 | {pct(th['p_any_line'])} |",
        f"| 頓悟觸發 p | {pct(th['p_trigger'])}（精確 {th['p_trigger']}） |",
        f"| 一次參悟次數的期望總轉數 1/(1−{sp.free_spins}p) | {float(th['spins']):.4f} |",
        f"| 一轉的期望候選預算 | {float(th['eg']):.4f} |",
        f"| **天機回報（一次參悟次數）** | **{float(th['es']):.4f}**（精確 {th['es']}） |",
        f"| 天機回報的標準差 σ | {th['sd']:.4f} |",
        "", "### 回報拆分", "", "| 來源 | 貢獻 | 佔比 |", "|---|---:|---:|",
    ]
    for k, v in th["parts"].items():
        lines.append(f"| {k} | {float(v):.4f} | {100*float(v)/float(th['es']):.1f}% |")
    lines += [
        "", "## 3. 蒙地卡羅驗證", "",
        f"- {n:,} 次參悟次數，分 {args.seeds} 個種子（100–{99+args.seeds}）。",
        f"- 天機回報 {mean:.4f}，95% CI [{mean-1.96*se:.4f}, {mean+1.96*se:.4f}]，z = {z:+.2f}；{seeds_cover}/{args.seeds} 個種子的 CI 涵蓋理論值。",
        f"- 頓悟觸發率 {trig/spins:.5f}（理論 {float(th['p_trigger']):.5f}），z = {zt:+.2f}。",
        "- 停輪均勻性卡方：" + "、".join(f"第 {i+1} 軸 p = {p:.3f}" for i, (_, p) in enumerate(chi)),
        f"- 樣本量：要讓天機回報有 ±1% 相對精度（95%），需要 n = (1.96σ / 0.01μ)² = {need:,} 次。",
        "", "## 4. 與遊戲實作對照", "",
        f"- `tests/wheel_golden.json`：{n_gold} 組停輪位置（隨機 400 組＋全部八卦歸一與頓悟盤面）與正確結果。",
        "- 冒煙測試讓 GDScript 的 `Game.wheel_eval()` 逐盤面判定，必須 100% 一致；另外讓遊戲的亂數實際轉 20,000 次，頓悟觸發率與門派共鳴率要落在理論的 99.9% 區間內。",
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
