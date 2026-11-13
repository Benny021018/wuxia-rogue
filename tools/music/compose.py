"""天魔劫配樂：主題曲與第一張地圖（綠林山寨）的程式化樂譜。

設計見 docs/music/README.md。這裡只放「樂譜」：動機、和聲進行、段落、聲部配置。
渲染在 render.py，分析與樂譜輸出在 analyze.py。

    python3 tools/music/compose.py      # 輸出 docs/music/*.mid
"""
from pathlib import Path
import random
from theory import Chord, parse_prog, parse_melody, chord_at, voice, bass_note, guide_line, humanize, midi

ROOT = Path(__file__).resolve().parents[2]

# ------------------------------------------------------------------ 動機（A 羽調式：A C D E G）
# 英雄動機 x：主音 → 小三度 → 純四度（6. 1 2），「起」的姿態；y：3 5 3 2 的迴旋。
HERO_1 = "A4:1.5 C5:.5 D5:2 | E5:1 G5:.5 E5:.5 D5:2 | C5:1 D5:.5 C5:.5 A4:1 G4:1 | A4:4"
HERO_2 = "A4:1.5 C5:.5 D5:2 | E5:1 G5:.5 A5:.5 G5:1 E5:1 | D5:1.5 E5:.5 D5:1 B4:1 | E5:4"
# 天魔動機：主音 → 小二度（Bb，弗里幾亞色彩）→ 三全音下落到 E，再回主音。
DEMON = "A2:2 Bb2:1 E2:1 | A2:4 | A2:2 Bb2:1 E2:1 | A2:2 r:2"
# 序奏版：前四下吹完停一拍再吹後四下
DEMON_INTRO = "A2:2 Bb2:1 E2:1 | A2:3 r:1 | A2:2 Bb2:1 E2:1 | A2:2 r:2"
# 副歌：轉到關係大調色彩（F G Em Am），長音往上攀到 C6，再以 A 大三和弦收（光明感）。
SOAR = "A5:3 G5:1 | E5:2 D5:2 | E5:1 G5:1 A5:1 B5:1 | C6:3 A5:1 | A5:1 G5:1 E5:1 G5:1 | D5:3 E5:.5 D5:.5 | D5:2 E5:2 | A5:4"


class Track:
    def __init__(self, name, kind, program=0, pan=0.0, gain=1.0, verb=0.25, expr=None):
        self.name, self.kind, self.program = name, kind, program
        self.pan, self.gain, self.verb, self.expr = pan, gain, verb, expr
        self.notes = []        # [起拍, 拍長, 音高 or 鼓名, 力度, 圓滑]
        self.auto = []         # [(拍, 倍率)] 音量自動化

    def add(self, notes):
        self.notes.extend([list(n) + ([False] if len(n) == 4 else []) for n in notes])


class Song:
    def __init__(self, sid, title, bpm, prog_text):
        self.id, self.title, self.bpm = sid, title, bpm
        self.prog = parse_prog(prog_text)
        self.bars = len(self.prog)
        self.tracks = {}
        self.sections = []     # (名稱, 起始小節, 小節數)
        self.loop_bar = 0
        self.key = "a"
        self.dyn = []          # [(小節, dB)] 整首的力度曲線（段落之間線性漸變）

    def t(self, name, *a, **k):
        if name not in self.tracks:
            self.tracks[name] = Track(name, *a, **k)
        return self.tracks[name]

    def sec(self, name, bars):
        start = sum(b for _, _, b in self.sections)
        self.sections.append((name, start, bars))
        return start

    def chords(self, bar0, bar1):
        """[(拍, 長度, Chord)]，涵蓋 bar0..bar1-1。"""
        out = []
        for b in range(bar0, bar1):
            items = self.prog[b]
            for k, (pos, c) in enumerate(items):
                end = items[k + 1][0] if k + 1 < len(items) else 4
                out.append((b * 4 + pos, end - pos, c))
        return out


# ------------------------------------------------------------------ 共用寫法
def mel(track, text, bar, vel=90, shift=0):
    track.add(parse_melody(text, bar * 4, vel, shift))


def grace(notes, every=2, up=2, seed=1):
    """笛子的倚音：在長音前加一個上方鄰音（0.08 拍）。"""
    rng = random.Random(seed)
    out = []
    for i, n in enumerate(notes):
        if n[1] >= 1.0 and i % every == 0 and rng.random() < 0.7:
            g = 0.08
            out.append([n[0], g, n[2] + up, n[3] - 15, False])
            out.append([n[0] + g, n[1] - g, n[2], n[3], n[4]])
        else:
            out.append(n)
    return out


def pad(song, track, bar0, bar1, n, lo, hi, center, vel, prev=None, art=1.0):
    """依聲部進行排和弦長音；回傳 (拍, Chord, voicing) 給分析用。"""
    log = []
    for beat, dur, c in song.chords(bar0, bar1):
        v = voice(c, prev, n, lo, hi, center)
        for m in v:
            track.add([[beat, dur * art, m, vel]])
        log.append((beat, c, v))
        prev = v
    return log


def bassline(song, track, bar0, bar1, lo, hi, vel, rhythm=None, prev=None):
    """低音：每個和弦取根音（或 slash 低音），rhythm 為 None 時是全長音。"""
    for beat, dur, c in song.chords(bar0, bar1):
        b = bass_note(c, prev, lo, hi)
        prev = b
        if rhythm is None:
            track.add([[beat, dur, b, vel]])
        else:
            for pos, d, off, v in rhythm:
                if pos < dur:
                    track.add([[beat + pos, d, b + off, int(vel * v)]])
    return prev


def arp(song, track, bar0, bar1, low, pattern, step, vel, dur=None, accent=(0,)):
    for beat, d, c in song.chords(bar0, bar1):
        lad = c.ladder(low, max(pattern) + 1)
        k = 0
        while k * step < d - 1e-9:
            idx = pattern[k % len(pattern)]
            v = vel + (10 if k % len(pattern) in accent else 0)
            track.add([[beat + k * step, dur or step * 1.6, lad[idx], v]])
            k += 1


def drums(track, bar, pattern, vel=1.0):
    """pattern：{鼓名: [(16 分音符位置, 力度)]}"""
    for name, hits in pattern.items():
        for pos, v in hits:
            track.add([[bar * 4 + pos / 4, 0.25, name, int(127 * v * vel)]])


def roll(track, beat0, beats, name, v0, v1, rate=6):
    """滾奏：rate 次／拍，力度由 v0 漸變到 v1。"""
    n = int(beats * rate)
    for i in range(n):
        v = v0 + (v1 - v0) * i / max(1, n - 1)
        track.add([[beat0 + i / rate, 1.0 / rate, name, int(127 * v)]])


def timpani_roll(track, beat0, beats, note, v0, v1):
    n = int(beats * 8)
    for i in range(n):
        track.add([[beat0 + i / 8, 0.2, note, int(v0 + (v1 - v0) * i / max(1, n - 1))]])


# ================================================================== 天魔序奏（前 4 小節，Am Bb/A Am Bb/A）
def intro_v0(s, I):
    """原版：低銅管奏天魔動機，弦樂顫弓。"""
    mel(s.tracks["trombones"], DEMON_INTRO, I, 78, 12)
    mel(s.tracks["tuba"], DEMON_INTRO, I, 72)
    mel(s.tracks["contrabass"], DEMON_INTRO, I, 70, 12)
    drums(s.tracks["drums"], I, {"gong": [(0, .85)], "taiko_lo": [(0, .9)]})
    drums(s.tracks["drums"], I + 2, {"taiko_lo": [(0, .7)]})
    log = pad(s, s.tracks["tremolo"], I, I + 4, 3, 52, 70, 60, 50)
    # 停頓：第 4 小節後兩拍全部收掉，只留殘響，再由第 5 小節的鑼聲重新開始
    for n in s.tracks["tremolo"].notes:
        if (I + 3) * 4 <= n[0] < (I + 4) * 4:
            n[1] = min(n[1], 2.0)
    return log


def intro_v1(s, I):
    """魔音：尺八在空曠的低音持續上獨白，A 上方的 Eb（減五度）與 Bb（小二度）是魔性；
    心跳般的大太鼓、遠處的合唱空五度。"""
    sh = s.t("shakuhachi", "gm", 77, pan=0.10, gain=0.95, verb=0.45, expr="shaku")
    mel(sh, "r:1 E5:2.5 Eb5:.5 | D5:1.5 C5:.5 Bb4:2 | A4:1 C5:1 Eb5:2 | D5:1 Bb4:1 A4:2", I, 82)
    for k in range(4):
        s.tracks["contrabass"].add([[(I + k) * 4, 4, midi("A1"), 64]])
        s.tracks["cello"].add([[(I + k) * 4, 4, midi("A2"), 50]])
    s.tracks["choir"].add([[I * 4 + 2, 14, midi("A3"), 40], [I * 4 + 2, 14, midi("E4"), 38]])
    for k in range(4):
        drums(s.tracks["drums"], I + k, {"taiko_lo": [(0, .75), (3, .45)]})       # 心跳：咚—咚
    drums(s.tracks["drums"], I, {"gong": [(0, .7)]})
    return []


def intro_v2(s, I):
    """壓境：低音弦樂頓弓的固定音型把天魔動機藏在節奏裡（A A A Bb｜A A E A），
    太鼓一小節比一小節密，法國號短促重音，合唱在第 3 小節湧上來；第 5 小節突然收掉讓二胡出來。"""
    lo = s.t("low_strings", "gm", 48, pan=-0.10, gain=0.85, verb=0.25)
    pat = "A2:.5 A2:.5 A2:.5 Bb2:.5 A2:.5 A2:.5 E2:.5 A2:.5"
    for k in range(4):
        v = 64 + 10 * k
        for n in parse_melody(pat, (I + k) * 4, v):
            n[1] = .38
            lo.add([n])
            s.tracks["contrabass"].add([[n[0], .38, n[2] - 12, v - 6]])
    hits = [("A3 C4 E4", 0), ("A3 C4 E4", 1.5), ("Bb3 D4 F4", 4), ("Bb3 D4 F4", 5.5),
            ("A3 C4 E4", 8), ("A3 C4 E4", 9.5), ("Bb3 D4 F4", 12), ("Bb3 D4 F4", 13.5), ("Bb3 D4 F4", 15)]
    for ch, pos in hits:
        for m in ch.split():
            s.tracks["horns"].add([[I * 4 + pos, .45, midi(m), 70 + int(pos * 2)]])
    for m in ("A3", "E4", "A4"):
        s.tracks["choir"].add([[(I + 2) * 4, 8, midi(m), 62]])
    dr = s.tracks["drums"]
    drums(dr, I, {"taiko_lo": [(0, .7), (8, .6)]})
    drums(dr, I + 1, {"taiko_lo": [(0, .75), (8, .65)], "drum": [(4, .4), (12, .45)]})
    drums(dr, I + 2, {"taiko": [(0, .8), (3, .55), (6, .65), (8, .8), (11, .55), (14, .6)], "taiko_lo": [(0, .8)],
                      "drum": [(4, .5), (12, .55)]})
    drums(dr, I + 3, {"taiko": [(0, .85), (3, .6), (6, .7), (8, .85), (11, .6)], "taiko_lo": [(0, .85), (8, .7)],
                      "drum": [(4, .55)]})
    roll(dr, (I + 3) * 4 + 3, 1, "drum", .4, .95, rate=8)
    drums(dr, I, {"gong": [(0, .55)]})
    return []


def intro_v3(s, I):
    """血月：合唱低聲吟唱（A C Bb A｜E D C Bb），古箏在高處撥下減和弦的碎音，
    顫弓弦樂與鑼聲鋪底，像祭壇上的儀式。"""
    mel(s.tracks["choir"], "A3:2 C4:2 | Bb3:3 A3:1 | E4:2 D4:1 C4:1 | Bb3:4", I, 70)
    mel(s.tracks["choir"], "E3:2 E3:2 | F3:3 E3:1 | A3:2 G3:1 E3:1 | D3:4", I, 58)
    z = s.tracks["guzheng"]
    for k in range(4):
        b = (I + k) * 4 + 2
        notes = ["A5", "Eb5", "C5", "A4"] if k % 2 == 0 else ["Bb5", "F5", "D5", "Bb4"]
        for j, m in enumerate(notes):
            z.add([[b + j * .25, 1.5, midi(m), 52 - j * 5]])
    for k in range(4):
        s.tracks["tremolo"].add([[(I + k) * 4, 4, midi("A2"), 52], [(I + k) * 4, 4, midi("E3"), 48]])
        s.tracks["contrabass"].add([[(I + k) * 4, 4, midi("A1"), 58]])
    dr = s.tracks["drums"]
    drums(dr, I, {"gong": [(0, .6)]})
    drums(dr, I + 2, {"gong": [(0, .45)], "taiko_lo": [(0, .55)]})
    return []


INTROS = {"v0": intro_v0, "v1": intro_v1, "v2": intro_v2, "v3": intro_v3}


# ================================================================== 主題曲
def theme(intro: str = "v0") -> Song:
    s = Song("theme", "天魔劫・主題曲", 80,
             "Am Bb/A Am Bb/A Am F G Esus4,E "         # 序：天魔動機 → 英雄動機的影子
             "Am F G Am Am F G E "                       # A：二胡獨奏主題
             "Am F G Am Am F G E "                       # A'：笛子＋弦樂、副旋律、太鼓
             "F G Em Am F G Asus4 A "                    # B：關係大調的攀升
             "Am Bb/A Am Bb/A Gm Bb Dm E,F# "            # 橋：天魔動機正面衝突，轉調準備
             "Bm G A Bm Bm G A F# "                      # 高潮：上移全音，全奏主題
             "Bm G Em F#sus4,F# Bmadd9 Bmadd9")          # 尾聲
    s.key = "a"
    s.sec_keys = {"高潮": "b", "尾聲": "b"}
    I = s.sec("序", 8); A = s.sec("A 主題", 8); A2 = s.sec("A' 展開", 8); B = s.sec("B 攀升", 8)
    BR = s.sec("橋 天魔", 8); C = s.sec("高潮", 8); O = s.sec("尾聲", 6)

    erhu = s.t("erhu", "gm", 110, pan=-0.12, gain=1.05, verb=0.32, expr="erhu")
    dizi = s.t("dizi", "gm", 73, pan=0.18, gain=0.95, verb=0.34, expr="dizi")
    zheng = s.t("guzheng", "gm", 107, pan=0.30, gain=0.85, verb=0.30)
    vln = s.t("violins", "gm", 49, pan=-0.30, gain=1.45, verb=0.38)
    strings = s.t("strings_pad", "gm", 49, pan=0.05, gain=0.62, verb=0.42)
    trem = s.t("tremolo", "gm", 44, pan=0.20, gain=0.55, verb=0.40)
    cello = s.t("cello", "gm", 42, pan=-0.20, gain=0.80, verb=0.30)
    cb = s.t("contrabass", "gm", 43, pan=0.10, gain=0.85, verb=0.22)
    horn = s.t("horns", "gm", 60, pan=0.25, gain=1.0, verb=0.36)
    bone = s.t("trombones", "gm", 57, pan=-0.05, gain=0.75, verb=0.30)
    tuba = s.t("tuba", "gm", 58, pan=0.0, gain=0.70, verb=0.25)
    choir = s.t("choir", "gm", 52, pan=0.0, gain=0.85, verb=0.45)
    timp = s.t("timpani", "gm", 47, pan=0.0, gain=0.75, verb=0.30)
    dr = s.t("drums", "drum", pan=0.0, gain=1.0, verb=0.22)
    log = {}

    # ---- 序：天魔動機（長號＋大號＋低音提琴），弦樂顫弓持續音；後半二胡遠遠吹出英雄動機的頭
    log["序"] = INTROS[intro](s, I)
    pad(s, strings, I + 4, I + 8, 4, 50, 72, 61, 46)
    bassline(s, cb, I + 4, I + 8, 33, 45, 62)
    mel(erhu, "r:2 A4:1.5 C5:.5 | D5:4 | r:2 E5:1 G5:1 | E5:2 D5:2", I + 4, 72)
    arp(s, zheng, I + 4, I + 8, 45, [0, 2, 3, 4], 1.0, 50)
    drums(dr, I + 4, {"gong": [(0, .6)], "taiko_lo": [(0, .75)]})
    timpani_roll(timp, (I + 7) * 4, 4, midi("E2"), 40, 95)

    # ---- A：二胡獨奏，古箏琶音，大提琴長音
    mel(erhu, HERO_1, A, 88); mel(erhu, HERO_2, A + 4, 90)
    arp(s, zheng, A, A + 8, 45, [0, 2, 3, 4, 5, 4, 3, 2], 0.5, 58, accent=(0, 4))
    log["A"] = pad(s, strings, A, A + 8, 4, 50, 72, 61, 44)
    bassline(s, cello, A, A + 8, 36, 52, 58)
    bassline(s, cb, A, A + 8, 28, 43, 55)

    # ---- A'：笛子高八度＋小提琴原八度，大提琴副旋律反向，太鼓半拍感
    m1 = grace(parse_melody(HERO_1 + " | " + HERO_2, A2 * 4, 92, 12))
    dizi.add(m1)
    mel(vln, HERO_1, A2, 74); mel(vln, HERO_2, A2 + 4, 76)
    arp(s, zheng, A2, A2 + 8, 45, [0, 2, 3, 4, 5, 4, 3, 2], 0.5, 52, accent=(0, 4))
    log["A'"] = pad(s, strings, A2, A2 + 8, 4, 50, 72, 61, 58)
    contour = [+1, +1, -1, -1, +1, +1, -1, +1]           # 主旋律每小節大致走向
    for k, m in enumerate(guide_line(s.prog[A2:A2 + 8], 48, 64, midi("E3"), contour)):
        cello.add([[(A2 + k) * 4, 4, m, 72]])
    bassline(s, cb, A2, A2 + 8, 28, 43, 70)
    for b in range(A2, A2 + 8):
        drums(dr, b, {"taiko": [(0, .8), (8, .65)], "taiko_lo": [(0, .55)] if b % 2 == 0 else []})
    drums(dr, A2 + 3, {"drum": [(12, .35), (13, .4), (14, .45), (15, .5)]})
    drums(dr, A2 + 7, {"drum": [(8 + i, .3 + .04 * i) for i in range(8)]})
    timpani_roll(timp, (A2 + 7) * 4 + 2, 2, midi("E2"), 50, 105)

    # ---- B：小提琴＋法國號唱副歌，合唱墊底，太鼓八分音符推進
    mel(vln, SOAR, B, 92)
    mel(horn, SOAR, B, 78, -12)
    log["B"] = pad(s, strings, B, B + 8, 4, 50, 72, 62, 66)
    pad(s, choir, B, B + 8, 3, 57, 74, 65, 58)
    for k, m in enumerate(guide_line(s.prog[B:B + 8], 48, 64, midi("A3"), [-1, -1, +1, +1, -1, -1, +1, +1])):
        cello.add([[(B + k) * 4, 4, m, 76]])
    bassline(s, cb, B, B + 8, 28, 43, 80, rhythm=[(0, 1.5, 0, 1.0), (1.5, .5, 0, .7), (2, 2, 0, .9)])
    for b in range(B, B + 8):
        drums(dr, b, {"taiko": [(0, .85), (6, .6), (8, .8)], "drum": [(4, .55), (12, .6)],
                      "rim": [(2, .3), (6, .25), (10, .3), (14, .25)]})
    drums(dr, B, {"cym": [(0, .7)]})
    drums(dr, B + 4, {"cym": [(0, .55)]})
    drums(dr, B + 7, {"drum": [(8 + i, .35 + .05 * i) for i in range(8)]})

    # ---- 橋：天魔動機由法國號正面奏出，長號大號壓低音，弦樂顫弓，太鼓重拍
    mel(horn, "A3:2 Bb3:1 E3:1 | A3:4 | A3:2 Bb3:1 E3:1 | Bb3:2 D4:1 F4:1 | G3:2 Bb3:1 D4:1 | F4:2 D4:2 | D4:2 F4:1 A4:1 | G#4:2 A#4:2", BR, 96)
    mel(bone, DEMON, BR, 92, 12)
    mel(tuba, DEMON, BR, 88)
    bassline(s, bone, BR + 4, BR + 8, 40, 52, 86)
    bassline(s, tuba, BR + 4, BR + 8, 28, 43, 82)
    log["橋"] = pad(s, trem, BR, BR + 8, 4, 55, 76, 66, 74)
    bassline(s, cb, BR, BR + 8, 28, 43, 84, rhythm=[(i * .5, .4, 0, 1.0 if i % 2 == 0 else .75) for i in range(8)])
    drums(dr, BR, {"gong": [(0, .9)]})
    for b in range(BR, BR + 8):
        drums(dr, b, {"taiko_lo": [(0, .95), (3, .7), (6, .8), (8, .9), (11, .7), (14, .75)],
                      "drum": [(4, .6), (12, .65)]})
    roll(dr, (BR + 7) * 4, 4, "drum", .3, .9, rate=8)
    timpani_roll(timp, (BR + 7) * 4, 4, midi("F#2"), 60, 118)
    drums(dr, BR + 7, {"cym": [(12, .5)]})

    # ---- 高潮：B 小調全奏主題（二胡＋小提琴原八度、笛子高八度、合唱、號角副旋律）
    mel(erhu, HERO_1, C, 104, 2); mel(erhu, HERO_2, C + 4, 106, 2)
    mel(vln, HERO_1, C, 96, 2); mel(vln, HERO_2, C + 4, 98, 2)
    dizi.add(grace(parse_melody(HERO_1 + " | " + HERO_2, C * 4, 100, 14), seed=3))
    log["高潮"] = pad(s, strings, C, C + 8, 4, 52, 74, 64, 80)
    pad(s, choir, C, C + 8, 3, 59, 76, 67, 74)
    pad(s, horn, C, C + 8, 3, 50, 67, 58, 74)
    for k, m in enumerate(guide_line(s.prog[C:C + 8], 50, 66, midi("D3"), contour)):
        cello.add([[(C + k) * 4, 2, m, 86], [(C + k) * 4 + 2, 2, m, 80]])
    bassline(s, cb, C, C + 8, 30, 45, 92, rhythm=[(i * .5, .45, 0, 1.0 if i % 2 == 0 else .8) for i in range(8)])
    bassline(s, tuba, C, C + 8, 30, 45, 70)
    arp(s, zheng, C, C + 8, 47, [0, 2, 3, 4, 5, 6, 5, 4, 3, 2, 3, 4, 5, 4, 3, 2], 0.25, 50)
    for b in range(C, C + 8):
        drums(dr, b, {"taiko": [(0, .95), (6, .7), (8, .9), (10, .6)], "taiko_lo": [(0, .8), (8, .6)],
                      "drum": [(4, .7), (12, .75), (15, .4)], "rim": [(2, .35), (6, .3), (10, .35), (14, .3)]})
    drums(dr, C, {"gong": [(0, .95)], "cym": [(0, .9)]})
    drums(dr, C + 4, {"cym": [(0, .75)]})
    for b in (C, C + 4):
        timp.add([[b * 4, 1, midi("F#2"), 112]])
    roll(dr, (C + 7) * 4 + 2, 2, "drum", .4, .85, rate=8)

    # ---- 尾聲：二胡獨奏收在 B，古箏散音，鑼聲
    mel(erhu, "B4:1.5 D5:.5 E5:2 | F#5:1 A5:.5 F#5:.5 E5:2 | D5:1.5 E5:.5 D5:1 B4:1 | C#5:4 | B4:4 | r:4", O, 80)
    log["尾聲"] = pad(s, strings, O, O + 6, 4, 50, 72, 61, 52)
    bassline(s, cb, O, O + 6, 30, 45, 58)
    arp(s, zheng, O, O + 4, 47, [0, 2, 3, 4], 1.0, 46)
    zheng.add([[(O + 4) * 4 + i * .12, 3, m, 60 - i * 3] for i, m in enumerate(Chord("Bmadd9").ladder(47, 8))])
    drums(dr, O, {"gong": [(0, .8)]})
    drums(dr, O + 4, {"gong": [(0, .55)], "taiko_lo": [(0, .6)]})
    strings.auto = [((O + 3) * 4, 1.0), ((O + 6) * 4, 0.0)]
    # 力度曲線：序與 A 收著，A' 漸強，B／橋撐住，高潮最大，尾聲回落
    s.dyn = [(I, -7), (A, -6), (A + 7, -5), (A2, -3), (B, -1), (BR, -1), (BR + 7, 1), (C, 2.5), (O, -3), (O + 6, -6)]

    for tr in s.tracks.values():
        tr.notes = humanize(tr.notes, hash(tr.name) % 1000, 5)
    s.log = log
    return s


# ================================================================== 綠林山寨
def greenwood() -> Song:
    s = Song("greenwood", "綠林山寨", 132,
             "Em Em C,D Em "                              # 序：太鼓＋琵琶
             "Em C D Em Em C D Bm "                       # A：笛子（英雄動機 x 移到 E：E G A）
             "Em C D Em Em C D Bm "                       # A'：二胡＋笛子對位
             "C D Bm Em Am Bm C D "                       # B：二胡主奏、琵琶應答
             "Em F/E Em F/E C F Bsus4 B "                 # 橋：天魔動機（E F E B）
             "Em C D Em Em C D Bm")                       # A''：全奏，回到 A 循環
    s.key = "e"
    I = s.sec("序", 4); A = s.sec("A 山道", 8); A2 = s.sec("A' 寨門", 8); B = s.sec("B 校場", 8)
    BR = s.sec("橋 黑風", 8); A3 = s.sec("A'' 聚義廳", 8)
    s.loop_bar = A

    MEL_A = "E5:1.5 G5:.5 A5:1 B5:1 | G5:.5 A5:.5 G5:.5 E5:.5 D5:2 | D5:1 E5:.5 D5:.5 B4:1 A4:1 | E5:3 r:1 | " \
            "E5:1.5 G5:.5 A5:1 D6:1 | B5:.5 A5:.5 G5:.5 A5:.5 E5:2 | D5:1 E5:1 G5:1 A5:1 | B5:4"
    MEL_B = "G5:.5 G5:.5 E5:1 G5:1 A5:1 | A5:3 r:1 | B5:.5 A5:.5 G5:.5 E5:.5 D5:1 B4:1 | E5:3 r:1 | " \
            "A5:1 B5:1 A5:1 G5:1 | F#5:1 B5:1 D6:1 B5:1 | G5:1 E5:1 G5:1 A5:1 | A5:2 B5:1 D6:1"
    # 琵琶應答（填在 B 段旋律的休止）
    ANSWER = "B4:.25 D5:.25 E5:.25 G5:.25"

    dizi = s.t("dizi", "gm", 73, pan=0.15, gain=0.95, verb=0.26, expr="dizi")
    erhu = s.t("erhu", "gm", 110, pan=-0.15, gain=1.0, verb=0.26, expr="erhu")
    pipa = s.t("pipa", "gm", 106, pan=0.32, gain=0.72, verb=0.18)
    zheng = s.t("guzheng", "gm", 107, pan=-0.32, gain=0.70, verb=0.25)
    spic = s.t("low_strings", "gm", 48, pan=-0.10, gain=0.75, verb=0.18)
    strings = s.t("strings_pad", "gm", 49, pan=0.08, gain=0.50, verb=0.34)
    vln = s.t("violins", "gm", 49, pan=-0.28, gain=0.70, verb=0.30)
    horn = s.t("horns", "gm", 60, pan=0.22, gain=0.62, verb=0.30)
    bone = s.t("trombones", "gm", 57, pan=-0.05, gain=0.72, verb=0.24)
    tuba = s.t("tuba", "gm", 58, pan=0.0, gain=0.70, verb=0.2)
    trem = s.t("tremolo", "gm", 44, pan=0.2, gain=0.5, verb=0.32)
    cb = s.t("contrabass", "gm", 43, pan=0.0, gain=0.80, verb=0.16)
    timp = s.t("timpani", "gm", 47, pan=0.0, gain=0.7, verb=0.24)
    dr = s.t("drums", "drum", pan=0.0, gain=1.0, verb=0.16)
    log = {}

    groove = {"taiko": [(0, .85), (6, .6), (8, .8)], "taiko_lo": [], "drum": [(4, .55), (12, .6)],
              "rim": [(2, .28), (6, .22), (10, .28), (14, .22)]}
    busy = {"taiko": [(0, .9), (6, .65), (8, .85), (14, .55)], "drum": [(4, .6), (7, .25), (12, .65), (15, .3)],
            "rim": [(2, .3), (6, .25), (10, .3), (14, .25)]}

    def ostinato(bar0, bar1, vel, sixteenth=False):
        for beat, d, c in s.chords(bar0, bar1):
            lad = c.ladder(52, 5)
            pat = [0, 3, 2, 3, 4, 3, 2, 3]
            step = .25 if sixteenth else .5
            k = 0
            while k * step < d - 1e-9:
                pipa.add([[beat + k * step, step * 1.4, lad[pat[k % 8]], vel + (12 if k % 4 == 0 else 0)]])
                k += 1

    def spiccato(bar0, bar1, vel):
        for beat, d, c in s.chords(bar0, bar1):
            r = 40 + (c.bass - 40) % 12
            pat = [0, 0, 7, 0, 0, 7, 12, 7]
            for k in range(int(d * 2)):
                spic.add([[beat + k * .5, .32, r + pat[k % 8], vel + (14 if k % 2 == 0 else 0)]])

    # ---- 序
    for b in range(I, I + 4):
        drums(dr, b, groove if b >= I + 2 else {"taiko": [(0, .9), (6, .6), (8, .85)], "taiko_lo": [(0, .8)]})
    ostinato(I + 2, I + 4, 60)
    spiccato(I + 2, I + 4, 64)
    zheng.add([[(I + 3) * 4 + 2 + i * .07, 1.5, m, 50 + i * 4] for i, m in enumerate(Chord("Em").ladder(52, 10))])
    roll(dr, (I + 3) * 4 + 3, 1, "drum", .3, .7, rate=8)

    # ---- A：笛子主奏
    dizi.add(grace(parse_melody(MEL_A, A * 4, 94), seed=5))
    ostinato(A, A + 8, 56)
    spiccato(A, A + 8, 62)
    log["A"] = pad(s, strings, A, A + 8, 4, 52, 72, 62, 44)
    bassline(s, cb, A, A + 8, 28, 43, 74, rhythm=[(0, 1, 0, 1.0), (1.5, .5, 0, .7), (2, 1, 0, .9), (3.5, .5, 0, .7)])
    for b in range(A, A + 8):
        drums(dr, b, groove)
    drums(dr, A, {"cym": [(0, .6)], "taiko_lo": [(0, .8)]})
    drums(dr, A + 7, {"drum": [(12, .4), (13, .45), (14, .5), (15, .55)]})

    # ---- A'：二胡唱主題，笛子吹高音副旋律（守在和弦三度／延伸音）
    erhu.add(parse_melody(MEL_A, A2 * 4, 92))
    contour = [+1, -1, -1, 0, +1, -1, +1, +1]
    for k, m in enumerate(guide_line(s.prog[A2:A2 + 8], 76, 88, midi("B5"), contour)):
        dizi.add([[(A2 + k) * 4, 2, m, 72], [(A2 + k) * 4 + 2, 2, m, 66]])
    ostinato(A2, A2 + 8, 58)
    spiccato(A2, A2 + 8, 66)
    log["A'"] = pad(s, strings, A2, A2 + 8, 4, 52, 72, 62, 54)
    pad(s, horn, A2 + 4, A2 + 8, 3, 50, 67, 58, 56)
    bassline(s, cb, A2, A2 + 8, 28, 43, 78, rhythm=[(0, 1, 0, 1.0), (1.5, .5, 0, .7), (2, 1, 0, .9), (3.5, .5, 0, .7)])
    for b in range(A2, A2 + 8):
        drums(dr, b, groove)
    drums(dr, A2, {"cym": [(0, .55)]})
    roll(dr, (A2 + 7) * 4 + 2, 2, "drum", .3, .8, rate=8)

    # ---- B：二胡主奏，琵琶十六分音符＋應答，鼓更密
    erhu.add(parse_melody(MEL_B, B * 4, 96))
    for rest_bar in (B + 1, B + 3):
        pipa.add(parse_melody(ANSWER, rest_bar * 4 + 3, 84))
    ostinato(B, B + 8, 50, sixteenth=True)
    spiccato(B, B + 8, 70)
    log["B"] = pad(s, strings, B, B + 8, 4, 52, 74, 63, 64)
    pad(s, horn, B, B + 8, 3, 50, 67, 58, 64)
    bassline(s, cb, B, B + 8, 28, 43, 82, rhythm=[(i * .5, .4, 0, 1.0 if i % 2 == 0 else .75) for i in range(8)])
    for b in range(B, B + 8):
        drums(dr, b, busy)
    drums(dr, B, {"cym": [(0, .75)], "taiko_lo": [(0, .9)]})
    drums(dr, B + 4, {"cym": [(0, .6)]})
    roll(dr, (B + 7) * 4, 4, "drum", .3, .85, rate=8)
    timpani_roll(timp, (B + 7) * 4, 4, midi("E2"), 50, 110)

    # ---- 橋：鼓轉半拍、天魔動機（E F E B）在低銅管，二胡長音哭腔
    DEMON_E = "E2:2 F2:1 B1:1 | E2:4 | E2:2 F2:1 B1:1 | E2:2 F2:2 | C2:4 | F2:4 | B1:4 | B1:4"
    mel(tuba, DEMON_E, BR, 92)
    mel(bone, DEMON_E, BR, 88, 12)
    mel(cb, DEMON_E, BR, 86, 12)
    erhu.add(parse_melody("B5:4 | C6:4 | B5:4 | C6:2 B5:2 | G5:4 | A5:4 | B5:2 E5:2 | D#6:2 B5:2", BR * 4, 90))
    log["橋"] = pad(s, trem, BR, BR + 8, 4, 55, 76, 66, 70)
    pad(s, horn, BR + 4, BR + 8, 3, 50, 67, 58, 78)
    drums(dr, BR, {"gong": [(0, .9)]})
    for b in range(BR, BR + 8):
        drums(dr, b, {"taiko_lo": [(0, .95), (8, .8)], "taiko": [(3, .6), (11, .6), (14, .5)], "drum": [(12, .6)]})
    drums(dr, BR + 7, {"drum": [(8 + i, .35 + .06 * i) for i in range(8)], "cym": [(12, .45)]})
    timpani_roll(timp, (BR + 6) * 4, 8, midi("B2"), 50, 115)

    # ---- A''：全奏（笛子＋二胡低八度＋小提琴），號角長音，回到 A 循環
    dizi.add(grace(parse_melody(MEL_A, A3 * 4, 100), seed=7))
    erhu.add(parse_melody(MEL_A, A3 * 4, 92))
    vln.add(parse_melody(MEL_A, A3 * 4, 80, -12))
    ostinato(A3, A3 + 8, 60)
    spiccato(A3, A3 + 8, 72)
    log["A''"] = pad(s, strings, A3, A3 + 8, 4, 52, 74, 63, 70)
    pad(s, horn, A3, A3 + 8, 3, 50, 67, 58, 72)
    bassline(s, cb, A3, A3 + 8, 28, 43, 86, rhythm=[(i * .5, .4, 0, 1.0 if i % 2 == 0 else .75) for i in range(8)])
    bassline(s, tuba, A3, A3 + 8, 28, 43, 62)
    for b in range(A3, A3 + 8):
        drums(dr, b, busy)
    drums(dr, A3, {"cym": [(0, .85)], "gong": [(0, .5)], "taiko_lo": [(0, .95)]})
    drums(dr, A3 + 4, {"cym": [(0, .6)]})
    drums(dr, A3 + 7, {"drum": [(8 + i, .35 + .05 * i) for i in range(8)]})

    s.dyn = [(I, -3), (A, -1), (A2, -0.5), (B, 0), (BR, 0), (A3, 0.5), (A3 + 8, 0.5)]
    for tr in s.tracks.values():
        tr.notes = humanize(tr.notes, hash(tr.name) % 1000, 5)
    s.log = log
    return s


SONGS = {"theme": theme, "greenwood": greenwood}

# ------------------------------------------------------------------ MIDI
GM_DRUM = {"taiko": 47, "taiko_lo": 41, "drum": 38, "rim": 76, "cym": 49, "gong": 52}


def write_midi(song: Song, path: Path) -> None:
    import mido
    tpb = 480
    mf = mido.MidiFile(ticks_per_beat=tpb, charset="utf-8")
    meta = mido.MidiTrack()
    meta.append(mido.MetaMessage("track_name", name=song.title, time=0))
    meta.append(mido.MetaMessage("set_tempo", tempo=mido.bpm2tempo(song.bpm), time=0))
    meta.append(mido.MetaMessage("time_signature", numerator=4, denominator=4, time=0))
    t = 0
    for name, start, bars in song.sections:
        meta.append(mido.MetaMessage("marker", text=name, time=start * 4 * tpb - t))
        t = start * 4 * tpb
    mf.tracks.append(meta)
    ch = 0
    for tr in song.tracks.values():
        trk = mido.MidiTrack()
        trk.append(mido.MetaMessage("track_name", name=tr.name, time=0))
        c = 9 if tr.kind == "drum" else ch
        if tr.kind != "drum":
            trk.append(mido.Message("program_change", channel=c, program=tr.program, time=0))
            ch += 1
            if ch == 9:
                ch = 10
        ev = []
        for st, du, p, v, _ in tr.notes:
            key = GM_DRUM[p] if tr.kind == "drum" else p
            ev.append((int(st * tpb), 1, key, v))
            ev.append((int((st + du) * tpb), 0, key, 0))
        ev.sort(key=lambda e: (e[0], e[1]))
        last = 0
        for tick, on, key, v in ev:
            trk.append(mido.Message("note_on" if on else "note_off", channel=c, note=key, velocity=v, time=tick - last))
            last = tick
        mf.tracks.append(trk)
    mf.save(path)


if __name__ == "__main__":
    out = ROOT / "docs" / "music"
    out.mkdir(parents=True, exist_ok=True)
    for sid, fn in SONGS.items():
        song = fn()
        write_midi(song, out / f"{sid}.mid")
        dur = song.bars * 4 * 60 / song.bpm
        print(f"{song.title}: {song.bars} 小節、{len(song.tracks)} 軌、{dur:.0f} 秒 → docs/music/{sid}.mid")
