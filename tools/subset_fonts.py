"""把介面字型裁成遊戲實際用到的字（assets/fonts/）。

來源：Noto Serif CJK TC Black（標題、按鈕）、Noto Sans CJK TC Bold（內文）。
字集：data/ 與 scripts/ 內出現的所有字元，加上 ASCII 與常用全形標點。
新增介面文字或 CSV 內容後重跑一次；缺字時 Godot 會退回系統字型。

用法：python3 tools/subset_fonts.py [字型資料夾]
需要 fontTools（pip install fonttools）。
"""
import glob
import os
import sys

from fontTools import subset
from fontTools.ttLib import TTCollection

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else "/usr/share/fonts/opentype/noto"
OUT = os.path.join(ROOT, "assets", "fonts")
FONTS = [("NotoSerifCJK-Black.ttc", "NotoSerifTC-Black.otf"), ("NotoSansCJK-Bold.ttc", "NotoSansTC-Bold.otf")]
EXTRA = "".join(chr(c) for c in range(0x20, 0x7F)) + "，。、；：？！「」『』（）《》〈〉・…—─～＋－×÷％／｜◆◇●○▲△■□★☆→←↑↓　０１２３４５６７８９"


def charset() -> str:
    chars = set(EXTRA)
    files = glob.glob(os.path.join(ROOT, "data", "*.csv")) + glob.glob(os.path.join(ROOT, "data", "*.json"))
    files += glob.glob(os.path.join(ROOT, "scripts", "**", "*.gd"), recursive=True)
    for f in files:
        with open(f, encoding="utf-8") as fh:
            chars.update(fh.read())
    return "".join(sorted(c for c in chars if c.isprintable()))


def tc_font(path):
    for font in TTCollection(path).fonts:
        names = [n.toUnicode() for n in font["name"].names if n.nameID in (1, 4)]
        if any(" TC" in n for n in names):
            return font
    raise SystemExit("找不到 TC 字型：" + path)


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    text = charset()
    for src, dst in FONTS:
        font = tc_font(os.path.join(SRC, src))
        opts = subset.Options()
        opts.layout_features = ["*"]
        opts.name_IDs = ["*"]
        opts.notdef_outline = True
        sub = subset.Subsetter(opts)
        sub.populate(text=text)
        sub.subset(font)
        path = os.path.join(OUT, dst)
        font.save(path)
        print(f"{dst}: {len(text)} 字，{os.path.getsize(path) // 1024} KB")


if __name__ == "__main__":
    main()
