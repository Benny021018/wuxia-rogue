"""用 music21 檢查樂譜並輸出樂譜檔。

- 和聲：每個和弦標羅馬數字級數
- 聲部：和弦墊底的各聲部有沒有平行五度／八度、聲部交錯
- 旋律：強拍音落在和弦音或五聲音階延伸音的比例
- 音域：每件樂器有沒有超出常用音域
- 輸出 docs/music/<曲>.musicxml（旋律聲部＋和弦符號，可用 MuseScore 開啟）

    python3 tools/music/analyze.py
"""
from pathlib import Path
from music21 import stream, note, chord, key, roman, harmony, metadata, meter, tempo, instrument
from compose import SONGS, ROOT
from theory import name

RANGES = {   # 常用音域（MIDI）
    "erhu": (62, 93), "dizi": (67, 98), "violins": (55, 100), "cello": (36, 76), "contrabass": (28, 60),
    "horns": (41, 77), "trombones": (40, 72), "tuba": (28, 58), "choir": (48, 81), "guzheng": (38, 93),
    "pipa": (45, 93), "strings_pad": (40, 96), "tremolo": (40, 96), "low_strings": (28, 72), "timpani": (40, 57),
}
MELODIC = ["erhu", "dizi", "violins", "horns", "cello"]
PENTA = {"a": [9, 0, 2, 4, 7], "e": [4, 7, 9, 11, 2]}
CS_FIX = {"madd9": "m add 9", "madd11": "m add 11", "add9": " add 9"}


def chord_symbol(sym: str):
    main, _, bass = sym.partition("/")
    for k, v in CS_FIX.items():
        if main.endswith(k):
            main = main[: -len(k)] + v
    fig = main + ("/" + bass if bass else "")
    try:
        return harmony.ChordSymbol(fig.replace("b", "-") if len(main) > 1 and main[1] == "b" else fig)
    except Exception:
        return harmony.ChordSymbol(main.split()[0])


def roman_of(c, k):
    bass = 48 + c.bass
    ch = chord.Chord(sorted({bass} | {bass + (p - c.bass) % 12 for p in c.pcs}))
    try:
        return roman.romanNumeralFromChord(ch, k).figure
    except Exception:
        return "?"


def check_voices(log):
    issues = []
    for sec, rows in log.items():
        for (b0, c0, v0), (b1, c1, v1) in zip(rows, rows[1:]):
            n = len(v0)
            for i in range(n):
                for j in range(i + 1, n):
                    a0, a1 = (v0[j] - v0[i]) % 12, (v1[j] - v1[i]) % 12
                    moved = v0[i] != v1[i] and v0[j] != v1[j]
                    same_dir = (v1[i] - v0[i]) * (v1[j] - v0[j]) > 0
                    if moved and same_dir and a0 == a1 and a0 in (0, 7):
                        issues.append(f"{sec} 第 {int(b1 // 4) + 1} 小節 {c0.sym}→{c1.sym}：聲部 {i + 1}/{j + 1} 平行{'八度' if a0 == 0 else '五度'}")
            if any(x >= y for x, y in zip(v1, v1[1:])):
                issues.append(f"{sec} 第 {int(b1 // 4) + 1} 小節：聲部交錯")
    return issues


def melody_fit(song, track):
    strong = fit = 0
    for st, du, p, v, _ in song.tracks[track].notes:
        if du < 0.2 or abs(st - round(st)) > 1e-6 or int(round(st)) % 2:
            continue
        c = song_chord(song, st)
        strong += 1
        if p % 12 in c.pcs or p % 12 in PENTA[song.key]:
            fit += 1
    return fit, strong


def song_chord(song, beat):
    from theory import chord_at
    return chord_at(song.prog, beat)


def to_score(song) -> stream.Score:
    sc = stream.Score()
    sc.insert(0, metadata.Metadata(title=song.title, composer="天魔劫"))
    cpart = stream.Part(id="chords")
    cpart.partName = "和弦"
    for beat, dur, c in song.chords(0, song.bars):
        cs = chord_symbol(c.sym)
        cs.writeAsChord = False
        cpart.insert(beat, cs)
    for tname in MELODIC:
        tr = song.tracks.get(tname)
        if not tr or not tr.notes:
            continue
        p = stream.Part(id=tname)
        p.partName = tname
        p.insert(0, instrument.Instrument(instrumentName=tname))
        notes = sorted(tr.notes, key=lambda n: n[0])
        merged = []
        for n in notes:
            if merged and n[0] < merged[-1][0] + merged[-1][1] - 1e-6:
                if merged[-1][1] < 0.2:           # 倚音：併進主音
                    g = merged.pop()
                    n = [g[0], n[1] + (n[0] - g[0]), n[2], n[3], n[4]]
                else:
                    continue                       # 同時發聲（例如和弦）只留最上面那個
            merged.append(n)
        for st, du, pch, v, _ in merged:
            q = round(du * 4) / 4 or 0.25
            nn = note.Note(pch, quarterLength=q)
            p.insert(round(st * 4) / 4, nn)
        sc.append(p)
    sc.insert(0, cpart)
    for p in sc.parts:
        p.insert(0, meter.TimeSignature("4/4"))
        p.insert(0, key.Key(song.key))
    sc.parts[0].insert(0, tempo.MetronomeMark(number=song.bpm))
    return sc


def main():
    out = ROOT / "docs" / "music"
    lines = ["# 配樂分析（tools/music/analyze.py 產生）", ""]
    total_issues = 0
    for sid, fn in SONGS.items():
        s = fn()
        k = key.Key(s.key)
        lines += [f"## {s.title}（{k.tonic.name} 小調／羽調式，♩={s.bpm}）", ""]
        lines += ["| 段落 | 小節 | 和弦 | 級數 |", "|---|---|---|---|"]
        for nm, st, bars in s.sections:
            syms = [c.sym for _, _, c in s.chords(st, st + bars)]
            sk = key.Key(getattr(s, "sec_keys", {}).get(nm, s.key))
            rns = [roman_of(c, sk) for _, _, c in s.chords(st, st + bars)]
            if sk.tonic.name != k.tonic.name:
                nm = f"{nm}（{sk.tonic.name} 小調）"
            lines.append(f"| {nm} | {st + 1}–{st + bars} | {' '.join(syms)} | {' '.join(rns)} |")
        lines.append("")
        issues = check_voices(s.log)
        total_issues += len(issues)
        lines.append(f"- 和弦墊底聲部檢查：{sum(len(r) for r in s.log.values())} 個和弦，"
                     f"{'沒有平行五八度或聲部交錯' if not issues else str(len(issues)) + ' 個問題'}")
        lines += [f"  - {x}" for x in issues]
        for tname in ("erhu", "dizi", "violins"):
            if tname in s.tracks and s.tracks[tname].notes:
                f, n = melody_fit(s, tname)
                if n:
                    lines.append(f"- {tname} 強拍音落在和弦音或五聲音階：{f}/{n}（{f / n:.0%}）")
        rng = []
        for tname, tr in s.tracks.items():
            if tr.kind == "drum" or tname not in RANGES or not tr.notes:
                continue
            lo, hi = min(n[2] for n in tr.notes), max(n[2] for n in tr.notes)
            ok = RANGES[tname][0] <= lo and hi <= RANGES[tname][1]
            rng.append(f"{tname} {name(lo)}–{name(hi)}{'' if ok else ' ⚠超出'}")
            if not ok:
                total_issues += 1
        lines.append("- 音域：" + "、".join(rng))
        lines.append("")
        sc = to_score(s)
        sc.write("musicxml", fp=str(out / f"{sid}.musicxml"))
        print(f"{s.title}: 聲部問題 {len(issues)}，樂譜 → docs/music/{sid}.musicxml")
    (out / "analysis.md").write_text("\n".join(lines), encoding="utf-8")
    print("\n".join(lines))
    return total_issues


if __name__ == "__main__":
    raise SystemExit(1 if main() else 0)
