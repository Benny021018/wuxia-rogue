"""樂理工具：音名、和弦符號、旋律字串、聲部進行。

單位一律是「拍」（四分音符 = 1）。音高用 MIDI 編號（A4 = 69）。
"""
from itertools import combinations
import random

NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

# 和弦性質 → 根音起算的半音
QUALITY = {
    "": (0, 4, 7),
    "m": (0, 3, 7),
    "5": (0, 7),
    "sus4": (0, 5, 7),
    "sus2": (0, 2, 7),
    "dim": (0, 3, 6),
    "7": (0, 4, 7, 10),
    "m7": (0, 3, 7, 10),
    "maj7": (0, 4, 7, 11),
    "add9": (0, 4, 7, 14),
    "madd9": (0, 3, 7, 14),
    "madd11": (0, 3, 7, 17),
}


def pc(name: str) -> int:
    """音名（不含八度）→ 0..11。"""
    v = NAMES[name[0]]
    for ch in name[1:]:
        v += 1 if ch == "#" else -1 if ch == "b" else 0
    return v % 12


def midi(note: str) -> int:
    """'A4'、'Bb2'、'F#5' → MIDI 編號。"""
    i = 1
    while i < len(note) and note[i] in "#b":
        i += 1
    return 12 * (int(note[i:]) + 1) + pc(note[:i])


def name(m: int) -> str:
    return ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"][m % 12] + str(m // 12 - 1)


class Chord:
    """和弦符號，例如 Am、Bb/A、Esus4、F#、Bm(add9) 寫成 Bmadd9。"""

    def __init__(self, sym: str):
        self.sym = sym
        main, _, bass = sym.partition("/")
        i = 1
        while i < len(main) and main[i] in "#b":
            i += 1
        self.root = pc(main[:i])
        q = main[i:]
        if q not in QUALITY:
            raise ValueError(f"未知的和弦性質：{sym}")
        self.ivs = QUALITY[q]
        self.bass = pc(bass) if bass else self.root
        self.pcs = sorted({(self.root + x) % 12 for x in self.ivs})

    def transpose(self, n: int) -> "Chord":
        c = Chord.__new__(Chord)
        c.sym, c.root, c.ivs = self.sym, (self.root + n) % 12, self.ivs
        c.bass = (self.bass + n) % 12
        c.pcs = sorted({(c.root + x) % 12 for x in c.ivs})
        return c

    def ladder(self, low: int, n: int) -> list:
        """從 >= low 的低音（slash 低音）開始，往上排 n 個和弦音。"""
        b = low + (self.bass - low) % 12
        out = [b]
        m = b + 1
        while len(out) < n:
            if m % 12 in self.pcs:
                out.append(m)
            m += 1
        return out


def parse_prog(text: str) -> list:
    """'Am F G Am | Esus4,E ...' → 每小節一個列表 [(拍位, Chord)]，逗號表示一小節內兩個和弦（各半）。"""
    bars = []
    for tok in text.split():
        if tok == "|":
            continue
        parts = tok.split(",")
        step = 4 / len(parts)
        bars.append([(k * step, Chord(p)) for k, p in enumerate(parts)])
    return bars


def chord_at(bars: list, beat: float) -> Chord:
    bar = bars[int(beat // 4)]
    pos = beat % 4
    cur = bar[0][1]
    for b, c in bar:
        if pos >= b - 1e-9:
            cur = c
    return cur


def parse_melody(text: str, start: float = 0.0, vel: int = 90, shift: int = 0) -> list:
    """'A4:1.5 C5:.5 D5:2 | r:4' → [(起拍, 拍長, 音高, 力度)]。
    音名後加 '~' 表示圓滑連到下一音（給二胡滑音用）。"""
    out, t = [], start
    for tok in text.split():
        if tok == "|":
            continue
        n, d = tok.split(":")
        d = float(d)
        slur = n.endswith("~")
        n = n.rstrip("~")
        if n != "r":
            out.append([t, d, midi(n) + shift, vel, slur])
        t += d
    return out


def length(text: str) -> float:
    return sum(float(tok.split(":")[1]) for tok in text.split() if tok != "|")


# ------------------------------------------------------------------ 聲部進行
def voice(chord: Chord, prev, n: int, lo: int, hi: int, center: int, span: int = 16):
    """在 [lo, hi] 內挑 n 個和弦音，涵蓋全部和弦音級，
    以「各聲部移動距離總和」最小為準（第一個和弦則靠近 center）。"""
    pool = [m for m in range(lo, hi + 1) if m % 12 in chord.pcs]
    need = set(chord.pcs) if n >= len(chord.pcs) else set()
    best, best_cost = None, 1e9
    for combo in combinations(pool, n):
        if combo[-1] - combo[0] > span:
            continue
        if need and {m % 12 for m in combo} != need:
            continue
        if any(b - a < 2 for a, b in zip(combo, combo[1:])):   # 避免小二度擠在一起
            continue
        if prev is None:
            cost = abs(sum(combo) / n - center)
        else:
            cost = sum(abs(a - b) for a, b in zip(combo, prev)) + 0.15 * abs(sum(combo) / n - center)
            cost += 30 * parallels(prev, combo)
        if cost < best_cost:
            best, best_cost = combo, cost
    if best is None:
        raise ValueError(f"排不出聲部：{chord.sym}")
    return list(best)


def parallels(v0, v1) -> int:
    """兩個聲部排列之間的平行五度／八度數（同向移動且音程類別不變）。"""
    n = 0
    for i in range(len(v0)):
        for j in range(i + 1, len(v0)):
            a0, a1 = (v0[j] - v0[i]) % 12, (v1[j] - v1[i]) % 12
            if a0 == a1 and a0 in (0, 7) and (v1[i] - v0[i]) * (v1[j] - v0[j]) > 0:
                n += 1
    return n


def bass_note(chord: Chord, prev, lo: int, hi: int) -> int:
    opts = [m for m in range(lo, hi + 1) if m % 12 == chord.bass]
    if prev is None:
        return opts[len(opts) // 2]
    return min(opts, key=lambda m: abs(m - prev))


def guide_line(bars: list, lo: int, hi: int, start_note: int, against=None) -> list:
    """副旋律：每個和弦取最靠近前一音的三度／五度／延伸音，盡量級進，
    並跟主旋律（against：每小節的平均音高變化）反向。回傳每個和弦一個音。"""
    out, prev = [], start_note
    k = 0
    for bar in bars:
        for _, c in bar:
            cands = [m for m in range(lo, hi + 1) if m % 12 in c.pcs and m % 12 != c.root]
            if not cands:
                cands = [m for m in range(lo, hi + 1) if m % 12 in c.pcs]
            def cost(m):
                d = m - prev
                pen = abs(d) + (3 if d == 0 else 0)
                if against is not None and k < len(against) and against[k] * d > 0:
                    pen += 2          # 和主旋律同向就加罰分
                return pen
            prev = min(cands, key=cost)
            out.append(prev)
            k += 1
    return out


def humanize(notes: list, seed: int, vel_jit: int = 6, time_jit: float = 0.0) -> list:
    rng = random.Random(seed)
    out = []
    for n in notes:
        n = list(n)
        n[3] = max(1, min(127, n[3] + rng.randint(-vel_jit, vel_jit)))
        if time_jit:
            n[0] = max(0.0, n[0] + rng.uniform(-time_jit, time_jit))
        out.append(n)
    return out
