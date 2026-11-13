"""把 compose.py 的樂譜渲染成遊戲用的 OGG。

- 旋律與管弦：GeneralUser GS 音色庫（tinysoundfont）；二胡有滑音與遲起的揉弦，笛子有輕揉弦
- 打擊樂（太鼓、締太鼓、梆子、鈸、鑼）：numpy 自己合成，每一擊微調音高避免機械感
- 殘響：合成的立體聲脈衝響應（高頻衰減較快），各軌依比例送入
- 母帶：高通 → 壓縮 → 響度正規化（pyloudnorm）→ 限幅器（pedalboard）
- 地圖曲把結尾殘響折回循環起點，循環時不會斷尾

音色庫不放進 repo（32 MB）。下載 https://github.com/mrbumpy409/GeneralUser-GS 後
設定 MUSIC_SF2=路徑，或放在 ~/sf/GeneralUser-GS.sf2。

    python3 tools/music/render.py [theme|greenwood|duel] [--preview 輸出資料夾]
"""
import json, os, subprocess, sys
from pathlib import Path
import numpy as np
from scipy import signal
from compose import SONGS, ROOT

SR = 44100
BLOCK = 128
SF2 = os.environ.get("MUSIC_SF2", str(Path.home() / "sf" / "GeneralUser-GS.sf2"))
if not Path(SF2).exists() and Path("/home/claude/sf/GeneralUser-GS.sf2").exists():
    SF2 = "/home/claude/sf/GeneralUser-GS.sf2"
OUT = ROOT / "assets" / "audio" / "music"
TARGET_LUFS = -16.0
CEILING_DB = -1.2
GM_BOOST = 10 ** (17 / 20)      # 音色庫輸出偏小，先拉到跟合成打擊樂同一個量級
DRUM_BUS = 1.1
# 音色校正（dB）：各音色在 GeneralUser GS 裡的取樣音量差很多，這裡拉齊
TRIM = {73: -8.0, 72: -9.0, 47: -8.0, 58: -2.0, 110: 0.0, 42: -7.0}
RNG = np.random.default_rng(20261113)


# ------------------------------------------------------------------ 管弦（音色庫）
EXPR = {   # 揉弦深度（半音）、頻率、延遲（秒）、滑音時間（秒）、最大滑音音程
    "erhu": dict(depth=0.30, rate=5.6, delay=0.16, ramp=0.30, glide=0.075, max_slide=7),
    "dizi": dict(depth=0.14, rate=5.0, delay=0.22, ramp=0.35, glide=0.0, max_slide=0),
    "shaku": dict(depth=0.22, rate=4.4, delay=0.35, ramp=0.5, glide=0.12, max_slide=3),
}


def render_gm(track, spb, total):
    import tinysoundfont
    syn = tinysoundfont.Synth(samplerate=SR, gain=-3.0)
    sf = syn.sfload(SF2)
    syn.program_select(0, sf, 0, track.program)
    syn.pitchbend_range(0, 12)
    ex = EXPR.get(track.expr)
    notes = sorted(track.notes, key=lambda n: (n[0], n[2]))
    if ex:   # 單音樂器：下一音開始時前一音結束
        for a, b in zip(notes, notes[1:]):
            if b[0] < a[0] + a[1]:
                a[1] = max(0.05, b[0] - a[0])
    ev = []
    prev = None
    for st, du, p, v, _ in notes:
        on = int(st * spb * SR)
        off = int((st + du) * spb * SR)
        slide = 0.0
        if ex and ex["glide"] and prev is not None:
            gap = st - (prev[0] + prev[1])
            if gap < 0.06 and 0 < abs(prev[2] - p) <= ex["max_slide"] and prev[1] >= 0.4:
                slide = float(prev[2] - p)
        ev.append((on, 1, p, v, slide))
        ev.append((max(on + 64, off), 0, p, 0, 0.0))
        prev = (st, du, p)
    ev.sort(key=lambda e: (e[0], e[1]))
    buf = np.zeros((total, 2), np.float32)
    k = 0
    cur_on, cur_slide = -1, 0.0
    for i in range(0, total, BLOCK):
        while k < len(ev) and ev[k][0] < i + BLOCK:
            s, on, p, v, sl = ev[k]
            if on:
                syn.noteon(0, p, v)
                cur_on, cur_slide = s, sl
            else:
                syn.noteoff(0, p)
            k += 1
        if ex and cur_on >= 0:
            t = (i - cur_on) / SR
            bend = 0.0
            if cur_slide and ex["glide"] and t < ex["glide"]:
                bend += cur_slide * (1 - t / ex["glide"]) ** 2
            amt = min(1.0, max(0.0, (t - ex["delay"]) / ex["ramp"]))
            bend += ex["depth"] * amt * np.sin(2 * np.pi * ex["rate"] * t)
            syn.pitchbend(0, int(np.clip(8192 + bend / 12 * 8191, 0, 16383)))
        n = min(BLOCK, total - i)
        buf[i:i + n] = np.frombuffer(syn.generate(n), np.float32).reshape(-1, 2)
    return buf


# ------------------------------------------------------------------ 打擊樂（合成）
def _env(t, k):
    return np.exp(-t * k)


def _lp(x, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, "low", fs=SR, output="sos"), x)


def _hp(x, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, "high", fs=SR, output="sos"), x)


def _bp(x, lo, hi):
    return signal.sosfilt(signal.butter(2, [lo, hi], "band", fs=SR, output="sos"), x)


def _taiko(base, decay, dur):
    t = np.arange(int(dur * SR)) / SR
    f = base * (1 + 0.55 * np.exp(-t * 28))
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * _env(t, decay) + 0.45 * np.sin(1.59 * ph) * _env(t, decay * 1.8)
    n = RNG.standard_normal(len(t))
    skin = _lp(n, 1400) * _env(t, 55) * 0.9 + _hp(n, 3000) * _env(t, 120) * 0.12
    x = body + skin
    return x / np.abs(x).max()


def _shime():
    t = np.arange(int(0.35 * SR)) / SR
    f = 210 * (1 + 0.25 * np.exp(-t * 45))
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * _env(t, 16)
    snap = _bp(RNG.standard_normal(len(t)), 900, 5000) * _env(t, 32) * 0.7
    x = tone + snap
    return x / np.abs(x).max()


def _rim():
    t = np.arange(int(0.15 * SR)) / SR
    x = (np.sin(2 * np.pi * 1180 * t) + 0.6 * np.sin(2 * np.pi * 1730 * t) + 0.3 * np.sin(2 * np.pi * 2510 * t)) * _env(t, 48)
    x[:40] += RNG.standard_normal(40) * np.linspace(1, 0, 40) * 0.6
    return x / np.abs(x).max()


def _cym():
    t = np.arange(int(3.0 * SR)) / SR
    n = _hp(RNG.standard_normal(len(t)), 3800, 4)
    ring = sum(np.sign(np.sin(2 * np.pi * f * t)) for f in (427, 613, 845, 1129)) * 0.05
    x = (n + _hp(ring, 2500)) * _env(t, 1.5) * (1 - np.exp(-t * 400))
    return x / np.abs(x).max()


def _gong():
    t = np.arange(int(7.0 * SR)) / SR
    base = 88.0
    x = np.zeros_like(t)
    for r, a, d in [(1, 1, .45), (1.47, .7, .6), (2.09, .55, .8), (2.56, .4, .9), (3.18, .35, 1.1),
                    (3.92, .25, 1.4), (4.41, .2, 1.6), (5.23, .14, 2.0), (6.11, .1, 2.4)]:
        f = base * r * (1 - 0.012 * (1 - np.exp(-t * 1.5)))         # 鑼聲微微下滑
        x += a * np.sin(2 * np.pi * np.cumsum(f) / SR + RNG.uniform(0, 6.28)) * _env(t, d)
    bloom = _lp(RNG.standard_normal(len(t)), 600) * (t / 0.7) * np.exp(1 - t / 0.7) * 0.25
    hit = _lp(RNG.standard_normal(len(t)), 2500) * _env(t, 30) * 0.5
    x = (x + bloom + hit) * (1 - np.exp(-t * 60))
    return x / np.abs(x).max()


DRUM_SRC = None
DRUM_MIX = {   # 名稱: (音量, 聲像)
    "taiko": (0.95, -0.10), "taiko_lo": (1.0, 0.0), "drum": (0.55, 0.18),
    "rim": (0.30, 0.38), "cym": (0.32, -0.32), "gong": (0.65, 0.05),
}


def render_drums(track, spb, total):
    global DRUM_SRC
    if DRUM_SRC is None:
        DRUM_SRC = {"taiko": _taiko(68, 6.0, 1.0), "taiko_lo": _taiko(46, 3.6, 1.6), "drum": _shime(),
                    "rim": _rim(), "cym": _cym(), "gong": _gong()}
    buf = np.zeros((total, 2), np.float32)
    for st, du, nm, v, _ in track.notes:
        src = DRUM_SRC[nm]
        ratio = 1 + RNG.uniform(-0.025, 0.025)                    # 每一擊音高微調
        idx = np.arange(0, len(src) - 1, ratio)
        x = np.interp(idx, np.arange(len(src)), src)
        if nm in ("taiko", "taiko_lo", "drum"):                    # 越大力越亮
            x = x * (0.6 + 0.4 * (v / 127)) + _hp(x, 900) * 0.25 * (v / 127) ** 2
        g, pan = DRUM_MIX[nm]
        amp = g * (v / 127) ** 1.6
        s0 = int(st * spb * SR)
        n = min(len(x), total - s0)
        if n <= 0:
            continue
        l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
        buf[s0:s0 + n, 0] += x[:n] * amp * l * 1.41
        buf[s0:s0 + n, 1] += x[:n] * amp * r * 1.41
    return buf


# ------------------------------------------------------------------ 殘響與母帶
def impulse(rt60, length):
    t = np.arange(int(length * SR)) / SR
    ir = np.zeros((len(t), 2))
    for c in range(2):
        n = RNG.standard_normal(len(t))
        low = _lp(n, 2500) * np.exp(-6.9 * t / rt60)
        high = _hp(n, 2500) * np.exp(-6.9 * t / (rt60 * 0.45))
        ir[:, c] = low + 0.5 * high
    pre = int(0.018 * SR)
    ir = np.vstack([np.zeros((pre, 2)), ir])
    for d, g in [(0.011, .5), (0.019, .35), (0.027, .3), (0.041, .22)]:      # 早期反射
        k = int(d * SR)
        ir[k, 0] += g
        ir[k + 37, 1] += g
    ir *= 0.5 / np.sqrt((ir ** 2).sum(axis=0).mean())
    return ir


def apply_auto(buf, auto, spb):
    if not auto:
        return buf
    xs = [0.0] + [b * spb * SR for b, _ in auto]
    ys = [auto[0][1]] + [g for _, g in auto]
    env = np.interp(np.arange(len(buf)), xs, ys).astype(np.float32)
    return buf * env[:, None]


def master(mix):
    import pyloudnorm as pyln
    from pedalboard import Pedalboard, Compressor, Limiter, HighpassFilter
    pre = Pedalboard([HighpassFilter(28), Compressor(threshold_db=-16, ratio=1.8, attack_ms=30, release_ms=250)])
    x = pre(mix.T.astype(np.float32), SR).T
    meter = pyln.Meter(SR)
    lufs = meter.integrated_loudness(x)
    x = x * 10 ** ((TARGET_LUFS - lufs) / 20)
    # JUCE 的 Limiter 會把門檻補償回 0 dBFS，所以處理完再乘回門檻值，峰值就停在 CEILING_DB
    x = Pedalboard([Limiter(threshold_db=CEILING_DB, release_ms=120)])(x.T.astype(np.float32), SR).T
    x = np.clip(x * 10 ** (CEILING_DB / 20), -0.98, 0.98)
    over = meter.integrated_loudness(x) - TARGET_LUFS
    if over > 0:                                   # 限幅器的補償偏多時，整體再降回目標響度
        x = x * 10 ** (-over / 20)
    return x, meter.integrated_loudness(x)


def render(song):
    spb = 60 / song.bpm
    body = song.bars * 4 * spb
    tail = 4.0
    total = int((body + tail) * SR)
    rt = 2.6 if song.id == "theme" else 1.7
    dry = np.zeros((total, 2), np.float32)
    send = np.zeros((total, 2), np.float32)
    stems = {}
    for tr in song.tracks.values():
        if not tr.notes:
            continue
        buf = render_drums(tr, spb, total) if tr.kind == "drum" else render_gm(tr, spb, total)
        buf = apply_auto(buf, tr.auto, spb)
        buf *= DRUM_BUS if tr.kind == "drum" else GM_BOOST * 10 ** (TRIM.get(tr.program, 0.0) / 20)
        if tr.kind != "drum":
            l, r = np.cos((tr.pan + 1) * np.pi / 4) * 1.41, np.sin((tr.pan + 1) * np.pi / 4) * 1.41
            buf = buf * np.array([l, r], np.float32)
        buf *= tr.gain
        stems[tr.name] = float(np.sqrt((buf ** 2).mean()))
        dry += buf
        send += buf * tr.verb
        print(f"  {tr.name:12s} 音符 {len(tr.notes):4d}  RMS {20 * np.log10(stems[tr.name] + 1e-9):6.1f} dB", flush=True)
    ir = impulse(rt, rt * 1.3)
    wet = np.stack([signal.oaconvolve(send[:, c], ir[:, c])[:total] for c in range(2)], axis=1)
    mix = dry + wet.astype(np.float32)
    if song.dyn:
        xs = [b * 4 * spb * SR for b, _ in song.dyn]
        env = 10 ** (np.interp(np.arange(total), xs, [d for _, d in song.dyn]) / 20)
        mix *= env[:, None].astype(np.float32)
    loop_start = song.loop_bar * 4 * spb
    if song.id != "theme":                     # 循環曲：結尾之後的聲音折回循環起點
        end = int(body * SR)
        rest = mix[end:]
        ls = int(loop_start * SR)
        mix = mix[:end].copy()
        mix[ls:ls + len(rest)] += rest
    else:
        fade = int(tail * SR)
        mix[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 2
    out, lufs = master(mix)
    return out, dict(lufs=round(float(lufs), 1), peak_db=round(float(20 * np.log10(np.abs(out).max())), 2),
                     seconds=round(len(out) / SR, 2), loop_offset=round(loop_start, 4),
                     clipped=int((np.abs(out) >= 0.999).sum()))


def bands(x):
    """低／中／高頻能量比例（檢查混音平衡用）。"""
    m = x.mean(axis=1)
    f, p = signal.welch(m, SR, nperseg=8192)
    tot = p.sum()
    return {k: round(float(p[(f >= a) & (f < b)].sum() / tot), 3)
            for k, (a, b) in {"低 <200Hz": (0, 200), "中 200–2k": (200, 2000), "高 >2k": (2000, 22050)}.items()}


def write(x, path: Path, fmt="ogg"):
    import wave
    tmp = path.with_suffix(".tmp.wav")
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(str(tmp), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    codec = ["-c:a", "libvorbis", "-q:a", "5"] if fmt == "ogg" else ["-c:a", "libmp3lame", "-b:a", "192k"]
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(tmp), *codec, str(path)], check=True)
    tmp.unlink()


if __name__ == "__main__":
    args = sys.argv[1:]
    preview = None
    if "--preview" in args:
        i = args.index("--preview")
        preview = Path(args[i + 1])
        del args[i:i + 2]
    ids = args or list(SONGS)
    OUT.mkdir(parents=True, exist_ok=True)
    stats = {}
    for sid in ids:
        song = SONGS[sid]()
        print(f"{song.title}：渲染 {len(song.tracks)} 軌", flush=True)
        x, st = render(song)
        st["bands"] = bands(x)
        stats[sid] = st
        write(x, OUT / f"{sid}.ogg")
        if preview:
            preview.mkdir(parents=True, exist_ok=True)
            write(x, preview / f"{sid}.mp3", "mp3")
        print(f"  → {st}", flush=True)
    import csv
    mpath = ROOT / "data" / "music.csv"
    rows = list(csv.DictReader(mpath.open(encoding="utf-8")))
    for r in rows:
        sid = Path(r["file"]).stem
        if sid in stats:
            r["loop_offset_s"] = f'{stats[sid]["loop_offset"]:g}'
    with mpath.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()), lineterminator="\n")
        w.writeheader(); w.writerows(rows)
    path = ROOT / "docs" / "music" / "render_stats.json"
    old = json.loads(path.read_text()) if path.exists() else {}
    old.update(stats)
    path.write_text(json.dumps(old, ensure_ascii=False, indent=1), encoding="utf-8")
