"""產生天機輪的輪帶（data/wheel_reels.csv）。
每軸的符號數量寫在 COUNTS；用固定種子洗牌，並保證「悟」在環狀輪帶上至少間隔 scatter_min_gap 格。
用法：python3 tools/shrine_math/make_reels.py"""
import csv, os, random

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SECTS = ["tianjian", "tianmo", "tangmen", "shaolin", "wudang"]
# 每軸：門派各 3、八卦、悟、雲。第三軸八卦較少，讓八卦歸一更稀有
COUNTS = [
    dict(**{s: 3 for s in SECTS}, bagua=2, wu=2, cloud=1),
    dict(**{s: 3 for s in SECTS}, bagua=2, wu=2, cloud=1),
    dict(**{s: 3 for s in SECTS}, bagua=1, wu=2, cloud=2),
]


def cfg():
    return {r["key"]: r["value"] for r in csv.DictReader(open(os.path.join(ROOT, "data/wheel_config.csv"), encoding="utf-8"))}


def ok(strip, gap):
    idx = [i for i, s in enumerate(strip) if s == "wu"]
    L = len(strip)
    return all(min((b - a) % L, (a - b) % L) >= gap for a in idx for b in idx if a != b)


def make():
    c = cfg()
    rng = random.Random(int(c["strip_seed"]))
    gap = int(c["scatter_min_gap"])
    rows = []
    for i, counts in enumerate(COUNTS):
        strip = [s for s, n in counts.items() for _ in range(n)]
        while True:
            rng.shuffle(strip)
            if ok(strip, gap) and all(strip[k] != strip[(k + 1) % len(strip)] for k in range(len(strip))):
                break
        rows.append({"reel": i + 1, "length": len(strip), "strip": "|".join(strip)})
    with open(os.path.join(ROOT, "data/wheel_reels.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["reel", "length", "strip"], lineterminator="\n")
        w.writeheader()
        w.writerows(rows)
    print("wrote data/wheel_reels.csv", [r["length"] for r in rows])


if __name__ == "__main__":
    make()
