"""檢查經脈連線與穴位是否都落在招式剪影內。
用法：python3 tools/check_meridian_paths.py [--sheet out.png]
穴位位置：acupoints.csv 的 fx、fy；via＝從上一穴走到這一穴途中的轉折點（"x,y;x,y"，佔圖比例）。"""
import csv, os, sys
from PIL import Image, ImageDraw
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load():
    rows = list(csv.DictReader(open(os.path.join(ROOT, "data/acupoints.csv"), encoding="utf-8")))
    out = {}
    for r in rows:
        out.setdefault(r["meridian_id"], []).append(r)
    for v in out.values():
        v.sort(key=lambda r: int(r["depth"]))
    return out


def polyline(pts):
    """整條經脈的折線（含轉折點），回傳 [(x, y, 起點穴位名)]。"""
    line = []
    for i, r in enumerate(pts):
        if i and r.get("via"):
            for part in r["via"].split(";"):
                x, y = part.split(",")
                line.append((float(x), float(y), None))
        line.append((float(r["fx"]), float(r["fy"]), r["name_zh"]))
    return line


def main():
    bad = 0
    mer = load()
    sheet = Image.new("RGB", (4 * 640, 2 * 640), "white") if "--sheet" in sys.argv else None
    for k, (mid, pts) in enumerate(mer.items()):
        im = Image.open(os.path.join(ROOT, f"assets/ui/meridian/{mid}.webp")).convert("RGBA")
        W = im.size[0]
        alpha = im.getchannel("A")
        inside = lambda x, y: alpha.getpixel((min(W - 1, max(0, int(x * W))), min(W - 1, max(0, int(y * W))))) > 128
        line = polyline(pts)
        last = None
        for i in range(len(line) - 1):
            (x0, y0, n0), (x1, y1, n1) = line[i], line[i + 1]
            last = n0 or last
            out = sum(1 for t in range(41) if not inside(x0 + (x1 - x0) * t / 40, y0 + (y1 - y0) * t / 40))
            if out > 4:   # 容許穿過剪影內部的白色描線（例如拳頭的輪廓）
                bad += 1
                print(f"{mid}: {last} → {n1 or '轉折點'} 有 {out*100//41}% 在身體外")
        for r in pts:
            if not inside(float(r["fx"]), float(r["fy"])):
                bad += 1
                print(f"{mid}: 穴位 {r['name_zh']} 在身體外")
        if sheet:
            bg = Image.new("RGB", im.size, "white"); bg.paste(im, mask=alpha); bg = bg.resize((640, 640)); d = ImageDraw.Draw(bg)
            d.line([(x * 640, y * 640) for x, y, _ in line], fill=(0, 200, 210), width=3)
            for j, r in enumerate(pts):
                x, y = float(r["fx"]) * 640, float(r["fy"]) * 640
                d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(255, 70, 20), outline="white"); d.text((x + 7, y - 6), str(j + 1), fill=(255, 0, 0))
            sheet.paste(bg, ((k % 4) * 640, (k // 4) * 640))
    if sheet:
        sheet.save(sys.argv[sys.argv.index("--sheet") + 1])
    print("OK" if not bad else f"{bad} 處有問題")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
