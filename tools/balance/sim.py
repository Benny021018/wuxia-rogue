"""《天魔劫》整局數值模擬：戰力成長、清場時間、銀兩去向、掉落。

錨點：舊數值專案已把「舊規則」（雙持、武器分品質、只有悟道碑）校準到 stage_report.csv 的
P50 清場時間 ≈ 目標壓力曲線。這裡以同一套戰力點模型重現舊規則的戰力成長，
再換成新規則（單武器、武器同質、詞條掉落、鐵匠、商人），以「新舊戰力比」推算新規則下的清場時間：

    清場時間_新(區) = 目標秒數(區) × 有效DPS_舊參考(區) ÷ 有效DPS_新(區)

戰力點模型（沿用 gacha_config／combat_config／stat_values 的定義）：
    有效DPS = Σ 出手武器的有效DPS × (1 + 15% × (淬煉-1)) + 10 × (武學點 × 0.7 + 輸出詞條點)
    武學點(Lv) = 稀有度預算 × (1 + 0.8×(Lv-1) + [Lv≥3]×1 + [Lv≥5]×2)

用法：
    python3 tools/balance/sim.py                 # 新舊規則比較報表
    python3 tools/balance/sim.py --runs 4000     # 跑更多局
    python3 tools/balance/sim.py --csv out.csv   # 每區統計輸出成 CSV
新規則參數全部讀 data/*.csv；舊規則讀 git HEAD 的 CSV（改版前），找不到時退回內建值。
"""
import argparse
import csv
import io
import math
import os
import random
import statistics
import subprocess
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, "data")
FEATURED = ["W001", "W007", "W301"]
REST_STOPS_DEFAULT = {4, 9, 14, 19}
OFFENSE_STATS = {"dmg_pct", "atk_speed_pct", "crit_rate_pct", "crit_dmg_pct", "area_pct"}


# ------------------------------------------------------------------ 讀資料
def _read(name, rev=None):
    if rev:
        try:
            text = subprocess.run(["git", "-C", ROOT, "show", f"{rev}:data/{name}.csv"], capture_output=True, check=True, text=True).stdout
            return list(csv.DictReader(io.StringIO(text)))
        except subprocess.CalledProcessError:
            return None
    with open(os.path.join(DATA, name + ".csv"), encoding="utf-8") as f:
        return list(csv.DictReader(f))


def _kv(rows):
    return {r["key"]: r["value"] for r in rows}


class Data:
    def __init__(self, rev=None):
        self.rev = rev
        self.gacha = _kv(_read("gacha_config", rev) or _read("gacha_config"))
        self.combat = _kv(_read("combat_config"))
        shop = _read("shop_config")
        self.shop = _kv(shop) if shop else {}
        self.rarity = {r["rarity"]: r for r in (_read("rarity", rev) or _read("rarity"))}
        self.order = ["common", "rare", "epic", "legendary"]
        self.weapons = {r["weapon_id"]: r for r in (_read("weapons", rev) or _read("weapons"))}
        self.martial = {r["martial_id"]: r for r in _read("martial_arts")}
        self.stages = {int(r["stage"]): r for r in _read("stages", rev) or _read("stages")}
        self.report = {int(r["stage"]): r for r in _read("stage_report")}
        self.stat_points = {r["stat_id"]: float(r["per_point"]) for r in _read("stat_values")}
        aff = _read("weapon_affixes")
        self.affixes = {r["affix_id"]: r for r in aff} if aff else {}
        self.minions = {s: int(r["minions"]) for s, r in self.report.items()}
        self.elites = {s: len([e for e in r["elites"].split("|") if e]) for s, r in self.report.items()}
        self.bosses = {s: 1 if r["boss"] else 0 for s, r in self.report.items()}
        self.gold = {s: float(r["gold"]) for s, r in self.report.items()}
        self.target = {s: float(r["target_s"]) for s, r in self.report.items()}
        self.p50_old = {s: float(r["clear_p50_s"]) for s, r in self.report.items()}

    def g(self, key):
        return float(self.gacha[key])

    def c(self, key):
        return float(self.combat.get(key, self.shop.get(key, 0)))

    def s(self, key, default=0.0):
        return float(self.shop.get(key, default))

    def weights(self, key):
        return [float(x) for x in self.shop.get(key, "").split("|") if x]

    def eff_dps(self, wid):
        w = self.weapons[wid]
        rt = w["range_type"]
        k = float(w["hits"]) / float(w["interval_s"]) * float(w["avg_targets"]) * self.g("uptime_" + rt) * self.g("hit_rate_" + rt)
        return float(w["dmg"]) * k

    def martial_points(self, mid, lv):
        if lv <= 0:
            return 0.0
        r = self.martial[mid]
        rr = self.rarity[r["rarity"]]
        b = float(rr["power_budget"])
        return b * (1 + float(rr["levelup_ratio"]) * (lv - 1) + (float(rr["lv3_ratio"]) if lv >= 3 else 0) + (float(rr["lv5_ratio"]) if lv >= 5 else 0))

    def affix_points(self, a):
        row = self.affixes[a[0]]
        return a[1] / self.stat_points[row["stat_id"]]


# ------------------------------------------------------------------ 一局
class Run:
    def __init__(self, d: Data, rules: str, rng: random.Random, start_wid="W001"):
        self.d, self.rules, self.rng = d, rules, rng
        self.new = rules == "new"
        self.weapons = [{"id": start_wid, "lv": 1, "aff": [], "ref": 0}, None]
        self.martial = {}
        self.gold = 0.0
        self.since_leg = 0
        self.stage = 1
        self.log = defaultdict(float)      # 花費去向、掉落數等
        self.stock = []

    # ---- 戰力
    def weapon_value(self, w):
        if w is None:
            return 0.0
        base = self.d.eff_dps(w["id"]) * (1 + self.d.g("weapon_levelup_pct") / 100 * (w["lv"] - 1))
        if w["lv"] >= int(self.d.g("max_level")):
            base += 10 * float(self.d.weapons[w["id"]].get("awaken_power") or 0)
        aff = sum(self.d.affix_points(a) for a in w["aff"] if self.d.affixes[a[0]]["stat_id"] in OFFENSE_STATS)
        return base + 10 * aff

    def martial_dps(self):
        return 10 * self.d.c("offense_share") * sum(self.d.martial_points(m, lv) for m, lv in self.martial.items())

    def dps(self):
        if self.new:
            w = max(self.weapon_value(x) for x in self.weapons)   # 手上拿最好的那把
        else:
            w = sum(self.weapon_value(x) for x in self.weapons)   # 舊規則：雙持同時出招
        return w + self.martial_dps()

    def parts(self):
        wv = max(self.weapon_value(x) for x in self.weapons) if self.new else sum(self.weapon_value(x) for x in self.weapons)
        best = max(self.weapons, key=lambda x: self.weapon_value(x))
        aff = 10 * sum(self.d.affix_points(a) for a in (best["aff"] if best else []) if self.d.affixes[a[0]]["stat_id"] in OFFENSE_STATS) if self.new else 0
        return {"weapon": wv - aff, "affix": aff, "martial": self.martial_dps()}

    def gold_mult(self):
        held = max(self.weapons, key=lambda x: self.weapon_value(x))
        g = sum(a[1] for a in held["aff"] if self.d.affixes[a[0]]["stat_id"] == "gold_gain_pct") if held else 0
        for m, lv in self.martial.items():
            r = self.d.martial[m]
            if r["stat_id"] == "gold_gain_pct":
                g += float(r["lv1_value"]) + float(r["per_level"]) * (lv - 1)
        return 1 + g / 100

    # ---- 悟道碑
    def rarity_weights(self, pity=True):
        out = [float(self.d.rarity[r]["weight"]) for r in self.d.order]
        if pity and self.since_leg >= self.d.g("soft_pity_start"):
            out[3] += self.d.g("soft_pity_step") * (self.since_leg - self.d.g("soft_pity_start") + 1)
        return out

    def _pool(self, rar, kind, seen):
        items, w = [], []
        if kind == "W":
            for wid in FEATURED:
                row = self.d.weapons[wid]
                lv = max([x["lv"] for x in self.weapons if x and x["id"] == wid] or [0])
                if row["rarity"] != rar or wid in seen or lv >= 5:
                    continue
                if lv and self.new and self.d.s("shrine_weapon_upgrade", 1) < 0.5:
                    continue
                items.append(wid)
                w.append(self.d.g("owned_upgrade_weight_mult") if lv else 1.0)
        else:
            full = len(self.martial) >= int(self.d.g("martial_slots"))
            for mid, row in self.d.martial.items():
                lv = self.martial.get(mid, 0)
                if row["rarity"] != rar or mid in seen or lv >= 5 or (full and lv == 0):
                    continue
                items.append(mid)
                w.append(self.d.g("owned_upgrade_weight_mult") if lv else 1.0)
        return items, w

    def roll(self, kind_mix=True, pity=True, n=3):
        seen, cands = set(), []
        tries = 0
        while len(cands) < n and tries < 60:
            tries += 1
            rw = self.rarity_weights(pity)
            rar = self.rng.choices(self.d.order, rw)[0]
            if pity and not cands and self.since_leg >= self.d.g("hard_pity") - 1:
                if self._pool("legendary", "M", seen)[0] or self._pool("legendary", "W", seen)[0]:
                    rar = "legendary"
            kind = "W" if kind_mix and self.rng.random() < self.d.g("weapon_pool_ratio") else "M"
            items, w = self._pool(rar, kind, seen)
            if not items:
                kind = "M" if kind == "W" else "W"
                items, w = self._pool(rar, kind, seen)
            if not items:
                continue
            x = self.rng.choices(items, w)[0]
            seen.add(x)
            cands.append((kind, x, rar))
        if pity:
            self.since_leg = 0 if any(c[2] == "legendary" for c in cands) else self.since_leg + 1
        return cands

    def gain(self, cand):
        kind, x, _ = cand
        before = self.dps()
        if kind == "M":
            lv = self.martial.get(x, 0)
            if lv >= 5:
                return 0.0
            after = before + 10 * self.d.c("offense_share") * (self.d.martial_points(x, lv + 1) - self.d.martial_points(x, lv))
            return after - before
        owned = [w for w in self.weapons if w and w["id"] == x]
        saved = [dict(w) if w else None for w in self.weapons]
        if owned:
            owned[0]["lv"] += 1
        else:
            item = {"id": x, "lv": 1, "aff": self.roll_affixes(x, self.affix_count("shrine")) if self.new else [], "ref": 0}
            slot = 1 if self.weapons[1] is None else min((0, 1), key=lambda i: self.weapon_value(self.weapons[i]))
            if self.new:
                self.inherit(item, max(self.weapons, key=lambda w: self.weapon_value(w)))
            self.weapons[slot] = item
        after = self.dps()
        self.weapons = saved
        return after - before

    def apply(self, cand):
        kind, x, _ = cand
        if kind == "M":
            self.martial[x] = self.martial.get(x, 0) + 1
            return
        owned = [w for w in self.weapons if w and w["id"] == x]
        if owned:
            owned[0]["lv"] += 1
        else:
            item = {"id": x, "lv": 1, "aff": self.roll_affixes(x, self.affix_count("shrine")) if self.new else [], "ref": 0}
            slot = 1 if self.weapons[1] is None else min((0, 1), key=lambda i: self.weapon_value(self.weapons[i]))
            if self.new:
                self.inherit(item, max(self.weapons, key=lambda w: self.weapon_value(w)))
            self.weapons[slot] = item

    def draw_cost(self, n_this_stage):
        return self.d.g("base_cost") * (1 + self.d.g("cost_growth_k")) ** n_this_stage * (1 + self.d.c("draw_cost_stage_growth")) ** (self.stage - 1)

    # ---- 詞條與掉落（新規則）
    def affix_count(self, src):
        w = self.d.weights("affix_weights_" + src)
        return self.rng.choices(range(1, len(w) + 1), w)[0] if w else 0

    def affix_tier(self, row):
        return 1 + float(row.get("tier_growth") or 0) * (self.stage - 1) if self.new else 1.0

    def roll_affixes(self, wid, n):
        rt = self.d.weapons[wid]["range_type"]
        pool = [(k, float(r["weight"])) for k, r in self.d.affixes.items()
                if not (r["range_type"] == "melee" and rt == "ranged" or r["range_type"] == "ranged" and rt == "melee")]
        out = []
        for _ in range(min(n, len(pool))):
            k = self.rng.choices([p[0] for p in pool], [p[1] for p in pool])[0]
            pool = [p for p in pool if p[0] != k]
            r = self.d.affixes[k]
            out.append((k, self.rng.uniform(float(r["min"]), float(r["max"])) * self.affix_tier(r)))
        return out

    def drops(self, stage):
        out = []
        luck = 1.0
        for rank, n in (("minion", self.d.minions[stage]), ("elite", self.d.elites[stage]), ("boss", self.d.bosses[stage])):
            p = min(1.0, self.d.s("drop_chance_" + rank) * luck)
            for _ in range(n):
                if self.rng.random() < p:
                    out.append({"id": self.rng.choice(FEATURED), "lv": 1, "aff": self.roll_affixes(self.rng.choice(FEATURED), 0), "ref": 0, "src": rank})
        for item in out:   # 詞條數依來源
            item["aff"] = self.roll_affixes(item["id"], self.affix_count(item.pop("src")))
        return out

    def inherit(self, item, old):
        if old is not None:
            item["lv"] = max(item["lv"], old["lv"] - int(self.d.s("inherit_lv_loss", 99)))

    def consider_drop(self, item):
        self.log["drops"] += 1
        cur = max((0, 1), key=lambda i: self.weapon_value(self.weapons[i]))
        self.inherit(item, self.weapons[cur])
        if self.weapons[1] is None:
            self.weapons[1] = item
            self.log["drops_taken"] += 1
        elif self.weapon_value(item) > self.weapon_value(self.weapons[cur]) * (1 + self.d.s("sim_swap_margin", 0.0)):
            self.weapons[cur] = item
            self.log["drops_taken"] += 1

    # ---- 鐵匠與商人（新規則）
    def price_mult(self):
        return (1 + self.d.s("price_stage_growth")) ** (self.stage - 1)

    def upgrade_cost(self, w):
        if w is None or w["lv"] >= 5:
            return None
        return self.d.s("upgrade_cost_base") * (1 + self.d.s("upgrade_cost_growth")) ** (w["lv"] - 1) * self.price_mult()

    def reforge_cost(self, w):
        if w is None or not w["aff"]:
            return None
        return self.d.s("reforge_cost_base") * (1 + self.d.s("reforge_cost_growth")) ** w["ref"] * self.price_mult()

    def expected_affix_value(self, w, samples=24):
        vals = []
        for _ in range(samples):
            vals.append(10 * sum(self.d.affix_points(a) for a in self.roll_affixes(w["id"], len(w["aff"])) if self.d.affixes[a[0]]["stat_id"] in OFFENSE_STATS))
        return statistics.mean(vals)

    def martial_price(self, mid):
        return float(self.d.rarity[self.d.martial[mid]["rarity"]]["martial_price"]) * self.price_mult()

    def restock(self):
        self.stock = []
        seen = set()
        tries = 0
        while len(self.stock) < int(self.d.s("merchant_slots", 4)) and tries < 60:
            tries += 1
            rar = self.rng.choices(self.d.order, self.rarity_weights(pity=False))[0]
            items, w = self._pool(rar, "M", seen)
            if not items:
                continue
            x = self.rng.choices(items, w)[0]
            seen.add(x)
            self.stock.append(x)

    # ---- 一區結算後的花錢策略：每次選「每兩銀子換到最多有效DPS」的選項
    def shop(self, rest_stop):
        n_draws = 0
        if rest_stop and self.new:
            self.restock()
        while True:
            options = []
            c = self.draw_cost(n_draws)
            if self.gold >= c:
                est = statistics.mean(max([self.gain(x) for x in self.roll(pity=False)] or [0]) for _ in range(4))
                options.append((est / c, "draw", c, None))
            if rest_stop and self.new:
                for i, w in enumerate(self.weapons):
                    uc = self.upgrade_cost(w)
                    if uc is not None and self.gold >= uc:
                        held = self.weapon_value(w) >= max(self.weapon_value(x) for x in self.weapons)
                        g = self.d.eff_dps(w["id"]) * self.d.g("weapon_levelup_pct") / 100 if held else 0.0
                        options.append((g / uc, "upgrade", uc, i))
                    rc = self.reforge_cost(w)
                    if rc is not None and self.gold >= rc:
                        cur = 10 * sum(self.d.affix_points(a) for a in w["aff"] if self.d.affixes[a[0]]["stat_id"] in OFFENSE_STATS)
                        g = max(0.0, self.expected_affix_value(w) - cur)
                        options.append((g / rc, "reforge", rc, i))
                for j, mid in enumerate(self.stock):
                    if mid is None:
                        continue
                    p = self.martial_price(mid)
                    lv = self.martial.get(mid, 0)
                    if self.gold >= p and lv < 5 and (lv > 0 or len(self.martial) < int(self.d.g("martial_slots"))):
                        g = 10 * self.d.c("offense_share") * (self.d.martial_points(mid, lv + 1) - self.d.martial_points(mid, lv))
                        options.append((g / p, "merchant", p, j))
            options = [o for o in options if o[0] > 0]
            if not options:
                break
            _, kind, cost, arg = max(options, key=lambda o: o[0])
            self.gold -= cost
            self.log["spend_" + kind] += cost
            self.log["n_" + kind] += 1
            if kind == "draw":
                n_draws += 1
                cands = self.roll()
                best = max(cands, key=self.gain) if cands else None
                if best and self.gain(best) > 0:
                    self.apply(best)
            elif kind == "upgrade":
                self.weapons[arg]["lv"] += 1
            elif kind == "reforge":
                w = self.weapons[arg]
                w["aff"] = self.roll_affixes(w["id"], len(w["aff"]))
                w["ref"] += 1
            elif kind == "merchant":
                mid = self.stock[arg]
                self.martial[mid] = self.martial.get(mid, 0) + 1
                self.stock[arg] = None

    def play(self):
        rest = {s for s, r in self.d.stages.items() if r.get("rest_stop") == "1"} or REST_STOPS_DEFAULT
        out = []
        for s in range(1, 21):
            self.stage = s
            dps_in = self.dps()
            if self.new:
                for item in self.drops(s):
                    self.consider_drop(item)
            self.gold += self.d.gold[s] * self.gold_mult()
            self.log["gold_in"] += self.d.gold[s] * self.gold_mult()
            out.append({"stage": s, "dps": dps_in, **self.parts()})
            self.shop(rest_stop=self.new and s in rest)
        self.log["gold_end"] = self.gold
        return out


# ------------------------------------------------------------------ 彙整
def simulate(d, rules, runs, seed=7, start=None):
    rng = random.Random(seed)
    curves, logs = defaultdict(list), []
    parts = defaultdict(lambda: defaultdict(list))
    for i in range(runs):
        r = Run(d, rules, rng, start_wid=start or FEATURED[i % len(FEATURED)])
        for row in r.play():
            curves[row["stage"]].append(row["dps"])
            for k in ("weapon", "affix", "martial"):
                parts[row["stage"]][k].append(row[k])
        logs.append(r.log)
    return curves, logs, parts


def pct(xs, q):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(q * len(xs)))]


def report(args):
    old_d, new_d = Data(rev=args.old_rev), Data()
    for kv in args.set or []:
        k, v = kv.split("=", 1)
        if k == "weapon_scale":
            for r in new_d.weapons.values():
                r["dmg"] = str(float(r["dmg"]) * float(v))
        elif k == "affix_scale":
            for r in new_d.affixes.values():
                r["min"], r["max"] = str(float(r["min"]) * float(v)), str(float(r["max"]) * float(v))
        elif k.startswith("rarity."):
            _, rar, col = k.split(".")
            new_d.rarity[rar][col] = v
        elif k in new_d.gacha:
            new_d.gacha[k] = v
        else:
            new_d.shop[k] = v
    old, _, _ = simulate(old_d, "old", args.runs)
    new, logs, parts = simulate(new_d, "new", args.runs)
    rows = []
    print(f"{'區':>2} {'目標s':>5} {'舊DPS':>6} {'新P10':>6} {'新P50':>6} {'新P90':>6} {'新/舊':>5} {'清場P50':>7} {'P90慢':>6}")
    for s in range(1, 21):
        ref = statistics.median(old[s])
        t = new_d.target[s]
        p10, p50, p90 = pct(new[s], 0.1), pct(new[s], 0.5), pct(new[s], 0.9)
        clear50 = t * ref / p50
        clear_slow = t * ref / p10
        rows.append({"stage": s, "target_s": t, "old_dps": round(ref, 1), "new_p10": round(p10, 1), "new_p50": round(p50, 1), "new_p90": round(p90, 1),
                     "ratio": round(p50 / ref, 3), "clear_p50_s": round(clear50, 1), "clear_slow_p10_s": round(clear_slow, 1),
                     "share_weapon": round(statistics.mean(parts[s]["weapon"]) / statistics.mean(new[s]), 3),
                     "share_affix": round(statistics.mean(parts[s]["affix"]) / statistics.mean(new[s]), 3),
                     "share_martial": round(statistics.mean(parts[s]["martial"]) / statistics.mean(new[s]), 3)})
        print(f"{s:>2} {t:>5.0f} {ref:>6.0f} {p10:>6.0f} {p50:>6.0f} {p90:>6.0f} {p50/ref:>5.2f} {clear50:>7.1f} {clear_slow:>6.1f}")
    tot = defaultdict(float)
    for lg in logs:
        for k, v in lg.items():
            tot[k] += v / len(logs)
    spend = sum(v for k, v in tot.items() if k.startswith("spend_"))
    print("\n每局平均：銀兩收入 %.0f，花費 %.0f" % (tot["gold_in"], spend))
    for k in ("draw", "upgrade", "reforge", "merchant"):
        print("  %-8s %5.0f 銀兩 (%4.1f%%)  %5.1f 次" % (k, tot["spend_" + k], 100 * tot["spend_" + k] / max(spend, 1), tot["n_" + k]))
    print("  掉落 %.1f 把，換上手 %.1f 把；終局剩餘 %.0f" % (tot["drops"], tot["drops_taken"], tot["gold_end"]))
    print("  輸出占比(第10/20區)：", {k: (rows[9]["share_" + k], rows[19]["share_" + k]) for k in ("weapon", "affix", "martial")})
    if args.csv:
        with open(args.csv, "w", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
    return rows, tot


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=1500)
    ap.add_argument("--csv")
    ap.add_argument("--old-rev", default="440139b", help="舊規則（雙持、武器分品質）所在的 commit")
    ap.add_argument("--set", action="append", help="試算用覆寫，例如 --set drop_chance_minion=0.01 --set rarity.rare.martial_price=60")
    report(ap.parse_args())
