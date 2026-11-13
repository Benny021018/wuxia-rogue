"""天魔劫音效產生器：全部用程式合成（numpy），旋律性提示音用 GeneralUser GS 音色庫。

每個音效一個函式，回傳一個或多個變體（同一動作輪流播放不同變體，避免機械感）。
輸出 assets/audio/sfx/<id>_<n>.wav（44.1 kHz、單聲道、16 bit，峰值 −1 dBFS），
並更新 data/sfx.csv 的變體數量（音量、音高隨機、聲部上限等欄位保留手調值）。

    python3 tools/sfx/make_sfx.py            # 全部
    python3 tools/sfx/make_sfx.py hit_low    # 只做指定的
"""
import csv, sys, wave
from pathlib import Path
import numpy as np
from scipy import signal

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "music"))
import render as music_render          # 共用太鼓、鑼、音色庫路徑

SR = 44100
OUT = ROOT / "assets" / "audio" / "sfx"
CSV = ROOT / "data" / "sfx.csv"


# ------------------------------------------------------------------ 基本元件
def T(d):
    return np.arange(int(d * SR)) / SR


def rng(seed):
    return np.random.default_rng(seed)


def noise(d, seed=0):
    return rng(seed).standard_normal(int(d * SR))


def lp(x, hz, o=2):
    return signal.sosfilt(signal.butter(o, min(hz, SR / 2 - 100), "low", fs=SR, output="sos"), x)


def hp(x, hz, o=2):
    return signal.sosfilt(signal.butter(o, hz, "high", fs=SR, output="sos"), x)


def bp(x, lo, hi, o=2):
    return signal.sosfilt(signal.butter(o, [lo, min(hi, SR / 2 - 100)], "band", fs=SR, output="sos"), x)


def reso(x, hz, q):
    b, a = signal.iirpeak(hz, q, fs=SR)
    return signal.lfilter(b, a, x)


def svf_band(x, fc, q=1.0):
    """隨時間變化中心頻率的帶通（狀態變數濾波器，逐樣本）。fc 是陣列。"""
    y = np.zeros_like(x)
    low = band = 0.0
    damp = 1.0 / q
    for i in range(len(x)):
        f = 2 * np.sin(np.pi * min(fc[i], SR / 6) / SR)
        high = x[i] - low - damp * band
        band += f * high
        low += f * band
        y[i] = band
    return y


def curve(n, pts):
    """pts = [(相對位置 0..1, 值)] 線性插值成長度 n 的陣列。"""
    xs, ys = zip(*pts)
    return np.interp(np.linspace(0, 1, n), xs, ys)


def env_ar(n, attack, decay_k):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-np.maximum(t - attack, 0) * decay_k)


def sweep_sine(d, f0, f1, k=None):
    t = T(d)
    f = f1 + (f0 - f1) * (np.exp(-t * k) if k else (1 - t / d))
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def partials(d, base, ratios, decays, amps=None, seed=0):
    t = T(d)
    r = rng(seed)
    amps = amps or [1.0 / (i + 1) for i in range(len(ratios))]
    return sum(a * np.sin(2 * np.pi * base * q * t + r.uniform(0, 6.28)) * np.exp(-t * k)
               for q, k, a in zip(ratios, decays, amps))


def pad_to(x, d):
    n = int(d * SR)
    return np.pad(x, (0, max(0, n - len(x))))[:n]


def mix(*parts):
    n = max(len(p) for p in parts)
    return sum(np.pad(p, (0, n - len(p))) for p in parts)


def at(x, sec, d):
    """把 x 放在第 sec 秒（總長 d）。"""
    out = np.zeros(int(d * SR))
    s = int(sec * SR)
    n = min(len(x), len(out) - s)
    out[s:s + n] = x[:n]
    return out


def ks_pluck(d, hz, seed=0, bright=0.5):
    """Karplus-Strong 撥弦。"""
    n = int(d * SR)
    p = int(SR / hz)
    buf = rng(seed).uniform(-1, 1, p)
    buf = lp(buf, 2000 + 8000 * bright)
    out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % p]
        buf[i % p] = 0.5 * (buf[i % p] + buf[(i + 1) % p]) * 0.996
    return out


def drive(x, k=2.0):
    return np.tanh(x * k) / np.tanh(k)


def fade_out(x, sec=0.02):
    n = min(len(x), int(sec * SR))
    x = x.copy()
    x[-n:] *= np.linspace(1, 0, n)
    return x


# ------------------------------------------------------------------ 音色庫（旋律性提示音）
_SYN = None


def sf(notes, d, gain=0.0):
    """notes = [(秒, 長度, program, 音高, 力度)]，回傳單聲道。"""
    import tinysoundfont
    syn = tinysoundfont.Synth(samplerate=SR, gain=gain)
    sfid = syn.sfload(music_render.SF2)
    progs = {}
    for _, _, p, _, _ in notes:
        if p not in progs:
            ch = len(progs) if len(progs) < 9 else len(progs) + 1
            progs[p] = ch
            syn.program_select(ch, sfid, 0, p)
    ev = []
    for s, du, p, m, v in notes:
        ev.append((int(s * SR), 1, progs[p], m, v))
        ev.append((int((s + du) * SR), 0, progs[p], m, 0))
    ev.sort(key=lambda e: (e[0], e[1]))
    n = int(d * SR)
    out = np.zeros((n, 2), np.float32)
    pos = 0
    for s, on, ch, m, v in ev + [(n, 0, 0, 0, 0)]:
        s = min(s, n)
        if s > pos:
            out[pos:s] = np.frombuffer(syn.generate(s - pos), np.float32).reshape(-1, 2)
            pos = s
        if s >= n:
            break
        if on:
            syn.noteon(ch, m, v)
        else:
            syn.noteoff(ch, m)
    return out.mean(axis=1).astype(np.float64)


def M(name):
    from theory import midi
    return midi(name)


# ================================================================== 戰鬥：揮擊
def swing_light():
    out = []
    for k in range(3):
        d = 0.26 + 0.03 * k
        n = int(d * SR)
        c = curve(n, [(0, 700), (0.38, 2600 + 500 * k), (1, 1100)])
        x = svf_band(noise(d, 10 + k), c, 1.4)
        e = curve(n, [(0, 0), (0.30, 1), (0.55, 0.45), (1, 0)]) ** 1.5
        zip_ = sweep_sine(d, 500, 1500 + 200 * k) * 0.05 * e
        out.append(x * e + zip_)
    return out


def swing_heavy():
    out = []
    for k in range(2):
        d = 0.48
        n = int(d * SR)
        c = curve(n, [(0, 260), (0.45, 1100 + 150 * k), (1, 380)])
        x = svf_band(noise(d, 20 + k), c, 0.9)
        e = curve(n, [(0, 0), (0.40, 1), (0.7, 0.35), (1, 0)]) ** 1.3
        rumble = lp(noise(d, 30 + k), 160) * 0.8 * e
        out.append(x * e + rumble)
    return out


def swing_thrust():
    d = 0.18
    n = int(d * SR)
    x = svf_band(noise(d, 40), curve(n, [(0, 1500), (0.3, 4200), (1, 2000)]), 1.6)
    return [x * curve(n, [(0, 0), (0.18, 1), (1, 0)]) ** 2]


def bow_draw():
    d = 0.85
    t = T(d)
    r = rng(50)
    x = np.zeros_like(t)
    s = 0.02
    while s < d - 0.03:
        k = int(s * SR)
        x[k] += r.uniform(0.5, 1.0)
        s += 0.034 - 0.022 * (s / d) + r.uniform(-0.004, 0.004)        # 越拉越緊，聲音越密
    creak = reso(x, 720, 9) * 1.2 + reso(x, 1850, 12) * 0.6
    friction = lp(noise(d, 51), 1800) * curve(len(t), [(0, 0.05), (1, 0.35)])
    return [(creak + friction) * curve(len(t), [(0, 0), (0.05, 1), (0.92, 1), (1, 0)])]


def bow_release():
    d = 0.55
    tw = ks_pluck(d, 98, 60, 0.7) * 0.9
    snap = hp(noise(0.03, 61), 3000) * np.linspace(1, 0, int(0.03 * SR)) ** 2
    whoosh = swing_thrust()[0] * 0.5
    return [mix(tw, snap * 0.8, at(whoosh, 0.01, 0.3))]


def arrow_impact():
    d = 0.3
    t = T(d)
    body = sweep_sine(d, 190, 85, 30) * np.exp(-t * 22)
    crack = bp(noise(d, 70), 500, 2500) * np.exp(-t * 60)
    wood = reso(np.r_[1.0, np.zeros(len(t) - 1)], 1250, 6) * 8
    return [body + crack * 0.8 + wood * np.exp(-t * 30)]


# ================================================================== 戰鬥：命中（分層）
def hit_low():
    out = []
    for k in range(2):
        d = 0.32
        t = T(d)
        body = drive(sweep_sine(d, 92 - 8 * k, 42, 18) * np.exp(-t * 13), 2.2)
        click = lp(noise(d, 80 + k), 1100) * np.exp(-t * 90) * 0.7
        out.append(body + click)
    return out


def hit_mid_flesh():
    out = []
    for k in range(3):
        d = 0.16
        t = T(d)
        r = rng(90 + k)
        grains = (r.random(len(t)) < 0.06) * r.uniform(-1, 1, len(t))       # 碎裂的顆粒感
        crunch = bp(noise(d, 95 + k) * 0.6 + grains * 3, 600, 2800, 4) * np.exp(-t * 32)
        slap = bp(noise(d, 99 + k), 1200, 4000) * np.exp(-t * 75) * 0.3
        body = np.sin(2 * np.pi * (210 + 25 * k) * t) * np.exp(-t * 35) * 0.5
        out.append(crunch + slap + body)
    return out


def hit_mid_metal():
    out = []
    for k in range(2):
        d = 0.65
        ring = partials(d, 520 + 60 * k, [1, 2.76, 5.40, 8.93, 13.3], [7, 10, 14, 20, 28], [1, .7, .5, .35, .2], 110 + k)
        att = bp(noise(d, 112 + k), 1500, 8000) * np.exp(-T(d) * 70)
        out.append(ring * 0.8 + att)
    return out


def hit_high():
    out = []
    for k in range(2):
        d = 0.2
        t = T(d)
        air = hp(noise(d, 120 + k), 5000) * np.exp(-t * 20)
        shing = np.sin(2 * np.pi * (3200 + 300 * k) * t) * np.exp(-t * 28) * 0.25
        out.append(air + shing)
    return out


def crit_sting():
    d = 0.8
    t = T(d)
    ring = partials(d, 1450, [1, 1.5, 2.0, 2.76, 4.1], [4, 5, 6, 8, 11], [1, .6, .5, .35, .2], 130)
    sparkle = hp(noise(d, 131), 6000) * np.exp(-t * 9) * 0.3
    return [ring * np.minimum(1, t / 0.004) + sparkle]


def kill_boom():
    d = 0.8
    t = T(d)
    boom = drive(sweep_sine(d, 70, 30, 7) * np.exp(-t * 5), 2.5)
    crack = bp(noise(d, 140), 1000, 6000) * np.exp(-t * 38) * 0.7
    rumble = lp(noise(d, 141), 220) * np.exp(-t * 4) * 1.2
    return [boom + crack + rumble]


# ================================================================== 玩家動作
def dash():
    d = 0.32
    n = int(d * SR)
    x = svf_band(noise(d, 150), curve(n, [(0, 500), (0.35, 2600), (1, 800)]), 1.1)
    return [x * curve(n, [(0, 0), (0.25, 1), (1, 0)]) ** 1.4]


def jump():
    d = 0.16
    t = T(d)
    return [bp(noise(d, 160), 900, 3000) * curve(len(t), [(0, 0), (0.3, 1), (1, 0)])]


def land():
    d = 0.22
    t = T(d)
    thud = sweep_sine(d, 120, 60, 25) * np.exp(-t * 24)
    dirt = lp(noise(d, 170), 600) * np.exp(-t * 28)
    return [thud + dirt * 0.8]


def footstep():
    out = []
    for k in range(4):
        d = 0.16
        t = T(d)
        r = rng(180 + k)
        dirt = lp(noise(d, 180 + k), 650 + 80 * k) * np.exp(-t * 34)
        grit = hp((r.random(len(t)) < 0.05) * r.uniform(-1, 1, len(t)), 2200) * np.exp(-t * 40) * 0.4
        thump = np.sin(2 * np.pi * (85 + 6 * k) * t) * np.exp(-t * 40) * 0.6
        out.append(dirt + grit + thump)
    return out


def player_hurt():
    out = []
    for k in range(2):
        d = 0.38
        t = T(d)
        punch = drive(sweep_sine(d, 125 - 10 * k, 55, 20) * np.exp(-t * 16), 2.0)
        crunch = bp(noise(d, 190 + k), 300, 1600) * np.exp(-t * 26) * 0.7
        out.append(punch + crunch)
    return out


def heartbeat():
    d = 0.75
    beat = lambda: np.sin(2 * np.pi * 55 * T(0.25)) * np.exp(-T(0.25) * 14)
    return [mix(at(beat(), 0, d), at(beat() * 0.7, 0.27, d))]


def player_death():
    d = 1.8
    t = T(d)
    boom = kill_boom()[0]
    fall = sweep_sine(d, 300, 40) * np.exp(-t * 1.6) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * t)) * 0.5
    return [mix(at(boom, 0, d), fall, lp(noise(d, 200), 300) * np.exp(-t * 2) * 0.6)]


def heal():
    return [sf([(0, .6, 8, M("E6"), 70), (.06, .6, 8, M("A6"), 64), (.12, .7, 8, M("C#7"), 58)], 1.1)]


def weapon_switch():
    d = 0.38
    n = int(d * SR)
    slide = svf_band(noise(d, 210), curve(n, [(0, 2500), (1, 6500)]), 2.0) * curve(n, [(0, 0), (0.2, 1), (0.8, .6), (1, 0)])
    ring = partials(d, 2300, [1, 1.47, 2.1], [6, 9, 12], [1, .5, .3], 211) * np.minimum(1, T(d) / 0.25) * 0.25
    return [slide + ring]


def qi_burst():
    d = 0.42
    n = int(d * SR)
    t = T(d)
    air = svf_band(noise(d, 220), curve(n, [(0, 1000), (0.5, 4200), (1, 2000)]), 1.3)
    tone = np.sin(2 * np.pi * np.cumsum(curve(n, [(0, 420), (1, 1250)]) * (1 + 0.01 * np.sin(2 * np.pi * 9 * t))) / SR) * 0.25
    return [(air + tone) * curve(n, [(0, 0), (0.15, 1), (1, 0)])]


# ================================================================== 敵人
def enemy_windup():
    d = 0.5
    t = T(d)
    return [partials(d, 2900, [1, 1.5, 2.0, 2.9], [8, 10, 13, 16], [1, .6, .4, .25], 230) * np.minimum(1, t / 0.003)
            + hp(noise(d, 231), 7000) * np.exp(-t * 25) * 0.2]


def glass_shatter():
    d = 0.75
    t = T(d)
    r = rng(240)
    x = hp(noise(d, 241), 2000) * np.exp(-t * 12) * 0.6
    for i in range(40):
        s = r.exponential(0.07)
        if s < d - 0.1:
            x += at(partials(0.12, r.uniform(2000, 7000), [1, 2.3], [45, 60], [1, .4], 242 + i) * r.uniform(.2, .6), s, d)
    return [x]


def poison_hiss():
    d = 1.1
    t = T(d)
    r = rng(250)
    hiss = hp(noise(d, 251), 2500) * curve(len(t), [(0, 0), (0.06, 1), (0.6, .6), (1, 0)])
    bub = np.zeros_like(t)
    for i in range(14):
        s = r.uniform(0.05, d - 0.15)
        bub += at(np.sin(2 * np.pi * r.uniform(180, 480) * T(0.06)) * np.exp(-T(0.06) * 50), s, d) * 0.5
    return [hiss * 0.7 + bub]


def chant():
    d = 1.7
    n = int(d * SR)
    t = T(d)
    saw = sum(np.sin(2 * np.pi * 110 * h * t) / h for h in range(1, 14)) + 0.6 * sum(np.sin(2 * np.pi * 165 * h * t) / h for h in range(1, 10))
    vowel = svf_band(saw, curve(n, [(0, 380), (0.5, 900), (1, 450)]), 4.0)
    trem = 0.75 + 0.25 * np.sin(2 * np.pi * 6 * t)
    whisper = bp(noise(d, 260)[::-1], 1500, 5000) * 0.2
    return [(vowel * trem + whisper) * curve(n, [(0, 0), (0.25, 1), (0.8, 1), (1, 0)])]


def horn():
    d = 1.9
    n = int(d * SR)
    t = T(d)
    semis = curve(n, [(0, -2), (0.08, 0), (1, -0.4)])
    f = 98 * 2 ** (semis / 12) * (1 + 0.006 * np.sin(2 * np.pi * 4.6 * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    saw = sum(np.sin(h * ph) / h for h in range(1, 30))
    bright = curve(n, [(0, 300), (0.15, 1600), (0.8, 1100), (1, 400)])
    x = svf_band(saw, bright, 0.7)
    return [drive(x * curve(n, [(0, 0), (0.06, 1), (0.85, .9), (1, 0)]), 1.5)]


def roar():
    d = 1.5
    n = int(d * SR)
    t = T(d)
    r = rng(270)
    f = curve(n, [(0, 95), (0.3, 80), (1, 55)]) * (1 + 0.05 * r.standard_normal(n).cumsum() / np.sqrt(np.arange(1, n + 1)))
    src = sum(np.sin(2 * np.pi * np.cumsum(f * h) / SR) / h for h in range(1, 20))
    src = src * (0.7 + 0.3 * np.sin(2 * np.pi * 31 * t)) + noise(d, 271) * 0.6
    x = reso(src, 320, 3) + reso(src, 820, 4) * 0.8 + reso(src, 2300, 6) * 0.3
    return [drive(x * curve(n, [(0, 0), (0.1, 1), (0.7, .8), (1, 0)]), 2.0)]


def aoe_warn():
    d = 1.3
    n = int(d * SR)
    t = T(d)
    f = curve(n, [(0, 200), (1, 520)])
    rate = curve(n, [(0, 4), (1, 14)])
    trem = 0.6 + 0.4 * np.sin(2 * np.pi * np.cumsum(rate) / SR)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * trem
    riser = hp(noise(d, 280), 3000) * curve(n, [(0, 0), (1, 0.15)])
    return [(tone + riser) * curve(n, [(0, 0), (0.1, .7), (1, 1)])]


def aoe_boom():
    d = 1.5
    n = int(d * SR)
    t = T(d)
    blast = noise(d, 290)
    out = np.zeros(n)
    cut = curve(n, [(0, 5000), (0.4, 600), (1, 180)])
    for i in range(0, n, 2048):              # 分段低通，截止頻率由高到低
        out[i:i + 2048] = lp(blast[i:i + 2048], cut[i])
    boom = drive(sweep_sine(d, 72, 32, 6) * np.exp(-t * 4.5), 2.5)
    return [out * np.exp(-t * 3.5) * 1.3 + boom]


def enemy_death():
    d = 0.6
    t = T(d)
    thud = lambda s: sweep_sine(0.25, 110, 55, 25) * np.exp(-T(0.25) * 22) * s
    cloth = bp(noise(d, 300), 800, 3000) * np.exp(-t * 14) * 0.4
    return [mix(at(thud(1.0), 0, d), at(thud(0.6), 0.13, d), cloth)]


def assassin_reveal():
    d = 0.38
    n = int(d * SR)
    swell = bp(noise(0.22, 310), 800, 5000) * np.linspace(0, 1, int(0.22 * SR)) ** 2
    burst = bp(noise(0.16, 311), 500, 2500) * np.exp(-T(0.16) * 30)
    return [mix(at(swell, 0, d), at(burst, 0.21, d))]


def boss_appear():
    d = 3.0
    taiko = music_render._taiko(46, 3.6, 1.6)
    gong = music_render._gong()[: int(d * SR)]
    brass = sf([(0, 2.2, 61, M("A1"), 120), (0, 2.2, 61, M("E2"), 115), (0, 2.2, 61, M("A2"), 115),
                (0, 2.2, 57, M("A2"), 110), (0.0, 2.4, 52, M("A3"), 90), (0.0, 2.4, 52, M("E4"), 85)], d, 4.0)
    return [mix(at(taiko, 0, d) * 1.2, at(gong, 0, d) * 0.6, brass * 2.0)]


# ================================================================== 世界
def zone_lock():
    d = 2.2
    n = int(d * SR)
    t = T(d)
    gong = music_render._gong()[:n] * 0.9
    hum = (np.sin(2 * np.pi * 110 * t) + 0.6 * np.sin(2 * np.pi * 165 * t) + 0.3 * np.sin(2 * np.pi * 220 * t)) \
        * curve(n, [(0, 0), (0.3, .6), (0.8, .5), (1, 0)]) * 0.5
    crackle = hp((rng(320).random(n) < 0.01) * 1.0, 3000) * curve(n, [(0, 0), (0.2, 1), (1, 0)]) * 0.2
    return [gong + hum + crackle]


def zone_clear():
    d = 2.4
    gong = music_render._gong()
    bright = np.interp(np.arange(0, len(gong) - 1, 1.45), np.arange(len(gong)), gong)[: int(d * SR)]
    chime = sf([(0.05, 1.2, 9, M("A5"), 90), (0.13, 1.2, 9, M("C6"), 86), (0.21, 1.2, 9, M("E6"), 84), (0.29, 1.6, 9, M("A6"), 92)], d)
    return [mix(bright * 0.6, chime * 2.5)]


def gate_open():
    d = 1.5
    n = int(d * SR)
    t = T(d)
    r = rng(330)
    rumble = lp(noise(d, 331), 130) * (0.7 + 0.3 * np.abs(np.sin(2 * np.pi * 7 * t + r.uniform(0, 1))))
    scrape = bp(noise(d, 332), 280, 900) * (0.5 + 0.5 * (r.random(n) < 0.3)) * 0.4
    return [(rumble * 1.6 + scrape) * curve(n, [(0, 0), (0.1, 1), (0.8, .8), (1, 0)])]


def shrine_appear():
    d = 1.6
    notes = [(i * 0.07, 1.2, 46, M(m), 70 + i * 3) for i, m in enumerate(["A4", "C5", "D5", "E5", "G5", "A5", "C6"])]
    air = hp(noise(d, 340), 4000) * curve(int(d * SR), [(0, 0), (0.4, .06), (1, 0)])
    return [sf(notes, d) * 2.2 + air]


def coin():
    out = []
    for k in range(2):
        d = 0.32
        a = partials(0.3, 2600 + 300 * k, [1, 2.7, 4.1, 5.4], [18, 24, 30, 36], [1, .6, .4, .3], 350 + k)
        b = partials(0.3, 3100 - 200 * k, [1, 2.7, 4.1], [20, 26, 32], [1, .5, .3], 360 + k)
        out.append(mix(at(a, 0, d), at(b * 0.7, 0.045, d)))
    return out


def loot_drop():
    d = 0.45
    t = T(d)
    clank = partials(d, 900, [1, 2.3, 3.9, 5.6], [10, 14, 18, 24], [1, .6, .4, .3], 370)
    return [clank * 0.7 + pad_to(land()[0], d) * 0.6]


def pickup():
    d = 0.3
    return [mix(pad_to(jump()[0], d) * 0.7, at(coin()[0] * 0.5, 0.05, d))]


def victory():
    d = 3.2
    n = [(0, .5, 61, M("D4"), 100), (0, .5, 61, M("F#4"), 96), (0, .5, 61, M("A4"), 96),
         (.5, .5, 61, M("E4"), 104), (.5, .5, 61, M("G#4"), 100), (.5, .5, 61, M("B4"), 100),
         (1.0, 2.0, 61, M("E4"), 110), (1.0, 2.0, 61, M("A4"), 110), (1.0, 2.0, 61, M("C#5"), 110),
         (1.0, 2.0, 49, M("A3"), 90), (1.0, 2.0, 49, M("E4"), 90), (1.0, 2.0, 9, M("A6"), 90), (0, 3, 43, M("A1"), 90)]
    return [sf(n, d, 3.0)]


def defeat():
    d = 3.4
    n = [(0, 1.0, 49, M("E4"), 90), (0, 1.0, 49, M("C4"), 85), (1.0, 1.0, 49, M("D4"), 88), (1.0, 1.0, 49, M("Bb3"), 84),
         (2.0, 1.4, 49, M("C4"), 86), (2.0, 1.4, 49, M("A3"), 82), (0, 3.4, 42, M("A2"), 80), (0, 3.4, 43, M("A1"), 85)]
    gong = music_render._gong()[: int(d * SR)] * 0.5
    return [mix(sf(n, d, 3.0) * 1.6, at(gong, 2.0, d))]


# ================================================================== 介面
def ui_hover():
    d = 0.06
    t = T(d)
    return [np.sin(2 * np.pi * 2300 * t) * np.exp(-t * 110) + hp(noise(d, 400), 4000) * np.exp(-t * 300) * 0.3]


def ui_click():
    d = 0.13
    t = T(d)
    imp = np.r_[1.0, np.zeros(len(t) - 1)]
    return [(reso(imp, 1100, 7) + reso(imp, 1650, 9) * 0.6) * 12 * np.exp(-t * 40)]


def ui_open():
    d = 0.24
    n = int(d * SR)
    return [svf_band(noise(d, 410), curve(n, [(0, 1800), (1, 5200)]), 1.2) * curve(n, [(0, 0), (0.3, 1), (1, 0)])]


def ui_close():
    d = 0.2
    n = int(d * SR)
    return [svf_band(noise(d, 420), curve(n, [(0, 4200), (1, 1400)]), 1.2) * curve(n, [(0, 0), (0.2, 1), (1, 0)])]


def ui_error():
    d = 0.24
    t = T(d)
    sq = np.sign(np.sin(2 * np.pi * 110 * t))
    gate = ((t < 0.08) | ((t > 0.12) & (t < 0.2))).astype(float)
    return [lp(sq, 1200) * gate * 0.6]


def purchase():
    d = 0.6
    r = rng(430)
    x = np.zeros(int(d * SR))
    for i in range(6):
        c = coin()[i % 2] * r.uniform(.4, .8)
        x += at(c, r.uniform(0, 0.25), d)
    return [x + pad_to(ui_click()[0], d) * 0.5]


def forge():
    out = []
    for k in range(2):
        d = 1.1
        t = T(d)
        ring = partials(d, 1100 + 80 * k, [1, 2.4, 4.2, 6.1, 8.3], [4, 6, 8, 11, 15], [1, .7, .5, .35, .2], 440 + k)
        hammer = sweep_sine(d, 160, 80, 30) * np.exp(-t * 30)
        out.append(ring * 0.8 + hammer * 0.7 + hp(noise(d, 445 + k), 3000) * np.exp(-t * 60) * 0.5)
    return out


def reforge():
    d = 1.4
    t = T(d)
    sizzle = hp(noise(d, 450), 3500) * curve(len(t), [(0, 0), (0.1, .8), (1, 0)]) * (0.7 + 0.3 * (rng(451).random(len(t)) < .5))
    return [mix(forge()[0], at(sizzle * 0.6, 0.2, d))]


def shop_refresh():
    d = 0.3
    x = np.zeros(int(d * SR))
    for i in range(8):
        x += at(bp(noise(0.03, 460 + i), 2000, 6000) * np.exp(-T(0.03) * 80), i * 0.03, d)
    return [x]


def wheel_tick():
    d = 0.05
    t = T(d)
    imp = np.r_[1.0, np.zeros(len(t) - 1)]
    return [reso(imp, 900, 6) * 10 * np.exp(-t * 80)]


def wheel_stop():
    d = 0.28
    t = T(d)
    return [sweep_sine(d, 180, 120, 30) * np.exp(-t * 26) + pad_to(ui_click()[0], d) * 0.6]


def wheel_sense():
    return [sf([(0, .7, 107, M("E5"), 95), (0.1, .8, 107, M("A5"), 100)], 1.0)]


def wheel_resonance():
    n = [(i * 0.07, 1.0, 107, M(m), 96) for i, m in enumerate(["A4", "C5", "D5", "E5", "G5", "A5"])]
    n += [(0.45, 1.2, 9, M("A6"), 85), (0.45, 1.2, 9, M("E6"), 80)]
    return [sf(n, 1.6)]


def wheel_bagua():
    d = 2.6
    n = [(0, .4, 61, M("A4"), 110), (0, .4, 61, M("E4"), 105), (.35, 1.8, 61, M("A4"), 118), (.35, 1.8, 61, M("C#5"), 115),
         (.35, 1.8, 61, M("E5"), 115), (.35, 1.8, 9, M("A6"), 100), (.35, 1.8, 9, M("E6"), 95), (0, 2.4, 52, M("A3"), 90)]
    gong = music_render._gong()[: int(d * SR)] * 0.45
    return [mix(sf(n, d, 3.0) * 1.4, at(gong, 0.35, d))]


def wheel_dunwu():
    d = 2.0
    n = [(i * 0.055, .9, 8, M(m), 80 + i * 2) for i, m in enumerate(["A5", "C6", "D6", "E6", "G6", "A6", "C7", "D7", "E7"])]
    shimmer = hp(noise(d, 470), 5000) * curve(int(d * SR), [(0, 0), (0.3, .5), (1, 0)])
    return [sf(n, d) * 2.4 + shimmer * 0.12]


def card_reveal():
    d = 0.14
    t = T(d)
    return [bp(noise(d, 480), 1800, 6000) * np.exp(-t * 45) + lp(noise(d, 481), 400) * np.exp(-t * 60) * 0.6]


def card_pick():
    return [mix(sf([(0, .8, 107, M("A5"), 100), (0.05, .8, 107, M("E6"), 90)], 0.9) * 1.5, pad_to(ui_click()[0], 0.9) * 0.5)]


def legend_sting():
    d = 2.0
    n = [(0, 1.2, 55, M("A3"), 120), (0, 1.2, 55, M("E4"), 115), (0.05, 1.6, 9, M("A6"), 100), (0.1, 1.6, 9, M("E7"), 90)]
    gong = music_render._gong()[: int(d * SR)] * 0.35
    return [mix(sf(n, d, 3.0) * 1.6, gong)]


def acu_success():
    d = 1.0
    t = T(d)
    glide = np.sin(2 * np.pi * np.cumsum(curve(len(t), [(0, 660), (0.15, 990), (1, 990)])) / SR) * np.exp(-t * 4) * 0.4
    return [mix(glide, sf([(0.08, .8, 107, M("E6"), 100)], d) * 1.8, pad_to(qi_burst()[0], d) * 0.6)]


def acu_fail():
    d = 0.6
    t = T(d)
    thud = sweep_sine(d, 140, 60, 20) * np.exp(-t * 14)
    r = rng(490)
    crumble = np.zeros_like(t)
    for i in range(18):
        crumble += at(lp(noise(0.03, 491 + i), 900) * np.exp(-T(0.03) * 90), r.uniform(0.04, 0.4), d) * r.uniform(.2, .6)
    return [thud + crumble]


def meridian_full():
    n = [(i * 0.09, 1.4, 8, M(m), 90) for i, m in enumerate(["A4", "E5", "B5", "C#6", "E6"])]
    return [sf(n, 1.8) * 1.8]


def realm_break():
    d = 3.4
    gong = music_render._gong()[: int(d * SR)]
    taiko = music_render._taiko(46, 3.6, 1.6)
    n = [(0.0, 3.0, 52, M("A3"), 100), (0.0, 3.0, 52, M("E4"), 95), (0.0, 3.0, 52, M("C#5"), 95),
         (0.0, 2.6, 61, M("A2"), 105), (0.0, 2.6, 61, M("E3"), 100), (0.2, 2.4, 9, M("A6"), 90), (0.3, 2.2, 9, M("E7"), 80)]
    return [mix(gong * 0.7, at(taiko, 0, d), sf(n, d, 3.0) * 1.8)]


def chime_up():
    n = [(i * 0.06, .8, 107, M(m), 92) for i, m in enumerate(["E5", "G5", "A5", "C6"])]
    return [sf(n, 1.1) * 1.6]


SOUNDS = {k: v for k, v in list(globals().items()) if callable(v) and not k.startswith("_") and k not in {
    "T", "rng", "noise", "lp", "hp", "bp", "reso", "svf_band", "curve", "env_ar", "sweep_sine", "partials", "pad_to",
    "mix", "at", "ks_pluck", "drive", "fade_out", "sf", "M", "Path"} and v.__module__ == __name__ and v.__code__.co_argcount == 0}


def write_wav(x, path):
    x = x - np.mean(x)
    x = fade_out(x, 0.015)
    pk = np.abs(x).max()
    if pk > 0:
        x = x / pk * 10 ** (-1 / 20)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def main(only):
    OUT.mkdir(parents=True, exist_ok=True)
    rows = {}
    if CSV.exists():
        rows = {r["id"]: r for r in csv.DictReader(CSV.open(encoding="utf-8"))}
    report = []
    for sid, fn in SOUNDS.items():
        if only and sid not in only:
            continue
        vars_ = fn()
        for old in OUT.glob(f"{sid}_*.wav"):
            old.unlink()
        for i, x in enumerate(vars_):
            write_wav(np.asarray(x, float), OUT / f"{sid}_{i + 1}.wav")
        if sid in rows:
            rows[sid]["variants"] = str(len(vars_))
        report.append(f"{sid:16s} ×{len(vars_)}  {len(vars_[0]) / SR:.2f}s")
    print("\n".join(report))
    if rows:
        fields = list(next(iter(rows.values())).keys())
        with CSV.open("w", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
            w.writeheader(); w.writerows(rows.values())
    missing = [k for k in SOUNDS if k not in rows]
    if missing:
        print("data/sfx.csv 缺少：", missing)


if __name__ == "__main__":
    main(set(sys.argv[1:]))
