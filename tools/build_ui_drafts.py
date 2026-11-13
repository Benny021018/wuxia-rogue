"""產生武俠介面 SVG 初稿（docs/ui-drafts/）。

視覺基準：《奈米魔神》條漫的語彙——墨黑底、血紅與橘紅、電光青的背光、
旁白黑框、奈米系統白框（缺角括弧）、狀聲詞手寫字、集中線、血點與火星。
只取語彙，不複製該作的角色與標題字。

用法：python3 tools/build_ui_drafts.py
需要 Pillow（轉換立繪與背景成內嵌圖）。
"""
import base64
import json
import io
import math
import os
import random

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "ui-drafts")
W, H = 1600, 900

# ---------------------------------------------------------------- 配色
INK = "#0b0a0d"        # 墨黑
INK2 = "#16131a"       # 次墨（帶紫）
VIOLET = "#2a1d36"     # 髮影紫
BLOOD = "#b3121c"      # 血紅
EMBER = "#ff4a17"      # 橘紅（標題、強調）
TEAL = "#16c6cc"       # 電光青
TEAL_D = "#0b5f66"
BONE = "#f3ede4"       # 骨白
GOLD = "#f2cf3a"       # 冷黃（極少量）
GREY = "#8d8790"
RARITY = {             # 建議稀有度色（色相沿用 rarity.csv，明度改配黑底）
    "common": ("凡品", "#a9a4ac"),
    "rare": ("良品", "#27b8d6"),
    "epic": ("神兵", "#9a5cf0"),
    "legendary": ("絕世", "#ff8a1e"),
}

SERIF = "'Noto Serif CJK TC','Noto Serif TC','Source Han Serif TC','PMingLiU',serif"
SANS = "'Noto Sans CJK TC','Noto Sans TC','Microsoft JhengHei','PingFang TC',sans-serif"


# ---------------------------------------------------------------- 內嵌圖
def _img(path, fmt="JPEG", size=None, crop=None, quality=76):
    im = Image.open(os.path.join(ROOT, path))
    im = im.convert("RGBA" if fmt == "PNG" else "RGB")
    if crop:
        im = im.crop(crop)
    if size:
        im = im.resize(size, Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, fmt, quality=quality) if fmt == "JPEG" else im.save(buf, fmt, optimize=True)
    mime = "image/jpeg" if fmt == "JPEG" else "image/png"
    return f"data:{mime};base64," + base64.b64encode(buf.getvalue()).decode()


_cache = {}


def asset(key):
    if key not in _cache:
        _cache[key] = {
            "pass": lambda: _img("assets/ui/greenwood_pass.webp"),
            "scene": lambda: _img("docs/previews/greenwood-smart.jpg", crop=(0, 0, 480, 270), size=(1600, 900), quality=70),
            "nangong": lambda: _img("assets/portraits/nangong.webp"),
            "han": lambda: _img("assets/portraits/han.webp"),
            "tang": lambda: _img("assets/portraits/tang.webp"),
            "weapon": lambda: _img("assets/ui/weapon.webp", "PNG", (180, 180)),
            "manual": lambda: _img("assets/ui/manual.webp", "PNG", (180, 180)),
        }[key]()
    return _cache[key]


# ---------------------------------------------------------------- 共用定義
DEFS = f"""
<defs>
  <!-- 乾筆邊緣：字與筆觸的毛邊 -->
  <filter id="rough" x="-10%" y="-20%" width="120%" height="140%">
    <feTurbulence type="fractalNoise" baseFrequency="0.035" numOctaves="2" seed="7" result="n"/>
    <feDisplacementMap in="SourceGraphic" in2="n" scale="7" xChannelSelector="R" yChannelSelector="G"/>
  </filter>
  <!-- 乾筆飛白：橫向斷絲 -->
  <filter id="dry" x="-10%" y="-20%" width="120%" height="140%">
    <feTurbulence type="fractalNoise" baseFrequency="0.006 0.22" numOctaves="2" seed="11" result="s"/>
    <feColorMatrix in="s" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 -2.6 1.75" result="m"/>
    <feTurbulence type="fractalNoise" baseFrequency="0.04" numOctaves="2" seed="4" result="n"/>
    <feDisplacementMap in="SourceGraphic" in2="n" scale="6" result="d"/>
    <feComposite in="d" in2="m" operator="in"/>
  </filter>
  <!-- 青光、血光 -->
  <filter id="glowTeal" x="-50%" y="-50%" width="200%" height="200%">
    <feGaussianBlur stdDeviation="10" result="b"/>
    <feFlood flood-color="{TEAL}" flood-opacity=".85"/><feComposite in2="b" operator="in" result="g"/>
    <feMerge><feMergeNode in="g"/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
  <filter id="glowRed" x="-50%" y="-50%" width="200%" height="200%">
    <feGaussianBlur stdDeviation="9" result="b"/>
    <feFlood flood-color="{EMBER}" flood-opacity=".8"/><feComposite in2="b" operator="in" result="g"/>
    <feMerge><feMergeNode in="g"/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
  <filter id="soft"><feGaussianBlur stdDeviation="2"/></filter>
  <!-- 紙紋／網點 -->
  <filter id="grain" x="0" y="0" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency=".9" numOctaves="2" seed="2"/>
    <feColorMatrix type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 0 .07 0"/>
  </filter>
  <pattern id="tone" width="7" height="7" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
    <circle cx="3.5" cy="3.5" r="1.2" fill="#000" opacity=".55"/>
  </pattern>
  <pattern id="hatch" width="10" height="10" patternUnits="userSpaceOnUse" patternTransform="rotate(-30)">
    <rect width="10" height="3" fill="#fff" opacity=".06"/>
  </pattern>
  <!-- 電光青背光、血色暗角 -->
  <radialGradient id="tealBloom" cx="50%" cy="45%" r="60%">
    <stop offset="0" stop-color="{TEAL}" stop-opacity=".95"/>
    <stop offset=".45" stop-color="{TEAL_D}" stop-opacity=".75"/>
    <stop offset="1" stop-color="{INK}" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="vignette" cx="50%" cy="50%" r="75%">
    <stop offset=".55" stop-color="#000" stop-opacity="0"/>
    <stop offset="1" stop-color="#000" stop-opacity=".85"/>
  </radialGradient>
  <linearGradient id="bloodFill" x1="0" x2="1">
    <stop offset="0" stop-color="#6e0a10"/><stop offset=".7" stop-color="{BLOOD}"/><stop offset="1" stop-color="{EMBER}"/>
  </linearGradient>
  <linearGradient id="tealFill" x1="0" x2="1">
    <stop offset="0" stop-color="{TEAL_D}"/><stop offset="1" stop-color="{TEAL}"/>
  </linearGradient>
  <linearGradient id="blade" x1="0" x2="1">
    <stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset=".45" stop-color="#fff"/>
    <stop offset=".55" stop-color="#d9f7f8"/><stop offset="1" stop-color="#fff" stop-opacity="0"/>
  </linearGradient>
  <!-- 青色雙色調（把背景圖壓成墨＋青） -->
  <filter id="duoTeal">
    <feColorMatrix type="matrix" values=".25 .45 .1 0 0  .25 .45 .1 0 0  .25 .45 .1 0 0  0 0 0 1 0" result="g"/>
    <feComponentTransfer in="g">
      <feFuncR type="table" tableValues="0.02 0.05 0.35 0.9"/>
      <feFuncG type="table" tableValues="0.02 0.25 0.7 0.98"/>
      <feFuncB type="table" tableValues="0.03 0.28 0.72 0.98"/>
    </feComponentTransfer>
  </filter>
  <filter id="duoInk">
    <feColorMatrix type="matrix" values=".25 .45 .1 0 0  .25 .45 .1 0 0  .25 .45 .1 0 0  0 0 0 1 0" result="g"/>
    <feComponentTransfer in="g">
      <feFuncR type="table" tableValues="0.02 0.1 0.45"/>
      <feFuncG type="table" tableValues="0.02 0.09 0.4"/>
      <feFuncB type="table" tableValues="0.03 0.12 0.45"/>
    </feComponentTransfer>
  </filter>
</defs>
"""


def doc(body, title, bg=INK):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
            f'viewBox="0 0 {W} {H}" width="{W}" height="{H}">\n<title>{title}</title>\n{DEFS}\n'
            f'<rect width="{W}" height="{H}" fill="{bg}"/>\n{body}\n'
            f'<rect width="{W}" height="{H}" filter="url(#grain)" pointer-events="none"/>\n</svg>\n')


def esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def text(x, y, s, size=20, fill=BONE, font=SANS, weight=400, anchor="start", extra=""):
    return (f'<text x="{x}" y="{y}" font-family="{font}" font-size="{size}" font-weight="{weight}" '
            f'fill="{fill}" text-anchor="{anchor}" {extra}>{esc(s)}</text>')


def lines(x, y, rows, size=18, gap=1.55, **kw):
    return "\n".join(text(x, y + i * size * gap, r, size, **kw) for i, r in enumerate(rows))


# ---------------------------------------------------------------- 元件
def narration(x, y, w, h, rows=(), size=20, fill=INK, align="middle", font=SERIF, color=BONE, weight=700):
    """旁白框：實心墨黑＋內縮白線（條漫旁白）。"""
    s = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" stroke="{BONE}" stroke-width="3"/>',
         f'<rect x="{x+6}" y="{y+6}" width="{w-12}" height="{h-12}" fill="none" stroke="{BONE}" stroke-width="1" opacity=".55"/>']
    if rows:
        tx = x + w / 2 if align == "middle" else x + 22
        ty = y + h / 2 - (len(rows) - 1) * size * 0.78 + size * 0.36
        s.append(lines(tx, ty, rows, size, 1.56, fill=color, font=font, weight=weight, anchor=align))
    return "\n".join(s)


def system_box(x, y, w, h, rows=(), size=18, tag=None, dark=False, accent=TEAL, align="start"):
    """奈米系統框：白底粗黑邊、四角缺角＋外括弧（系統訊息、說明、提示）。"""
    c = 10
    fill, ink = (INK2, BONE) if dark else ("#fbf8f3", INK)
    border = accent if dark else INK
    p = (f"M{x+c},{y} H{x+w-c} L{x+w},{y+c} V{y+h-c} L{x+w-c},{y+h} H{x+c} L{x},{y+h-c} V{y+c} Z")
    s = [f'<path d="{p}" fill="{fill}" stroke="{border}" stroke-width="3.5"/>']
    b = 14
    for (cx, cy, dx, dy) in [(x - 5, y - 5, 1, 1), (x + w + 5, y - 5, -1, 1), (x - 5, y + h + 5, 1, -1), (x + w + 5, y + h + 5, -1, -1)]:
        s.append(f'<path d="M{cx},{cy+dy*b} V{cy} H{cx+dx*b}" fill="none" stroke="{accent}" stroke-width="3"/>')
    oy = 0
    if tag:
        s.append(f'<rect x="{x+14}" y="{y-13}" width="{len(tag)*size*0.95+18}" height="{size+8}" fill="{accent if dark else INK}"/>')
        s.append(text(x + 23, y - 13 + size * 0.98, tag, size * 0.82, INK if dark else accent, SANS, 900))
        oy = 6
    if rows:
        tx = x + 20 if align == "start" else x + w / 2
        ty = y + (h - (len(rows) - 1) * size * 1.5) / 2 + size * 0.36 + oy * 0.5
        s.append(lines(tx, ty, rows, size, 1.5, fill=ink, font=SANS, weight=700, anchor=align))
    return "\n".join(s)


def slant(x, y, w, h, k=18, fill=INK, stroke=BONE, sw=3, extra=""):
    """斜切面板：左下、右上斜切（刀切分格）。"""
    p = f"M{x+k},{y} H{x+w} L{x+w-k},{y+h} H{x} Z"
    return f'<path d="{p}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" {extra}/>'


def button(x, y, w, h, label, state="normal", size=26, key=None):
    """按鈕：normal 墨底白框、hover 血紅底＋青括弧、disabled 灰。"""
    s = []
    if state == "hover":
        s.append(f'<g filter="url(#glowRed)">{slant(x, y, w, h, 16, BLOOD, BONE, 3)}</g>')
        s.append(f'<path d="M{x-12},{y+h*0.25} V{y-8} H{x+30}" fill="none" stroke="{TEAL}" stroke-width="3"/>')
        s.append(f'<path d="M{x+w+12},{y+h*0.75} V{y+h+8} H{x+w-30}" fill="none" stroke="{TEAL}" stroke-width="3"/>')
        col = BONE
    elif state == "disabled":
        s.append(slant(x, y, w, h, 16, "#1b1a1d", "#4a474d", 2))
        col = "#5d5a60"
    else:
        s.append(slant(x, y, w, h, 16, INK, BONE, 3))
        s.append(f'<path d="M{x+16+6},{y+6} H{x+w-6}" stroke="{BONE}" stroke-width="1" opacity=".4"/>')
        col = BONE
    s.append(text(x + w / 2, y + h / 2 + size * 0.36, label, size, col, SERIF, 900, "middle"))
    if key:
        s.append(f'<rect x="{x+w-46}" y="{y+h-20}" width="34" height="16" fill="{TEAL if state!="disabled" else "#333"}"/>')
        s.append(text(x + w - 29, y + h - 7, key, 12, INK, SANS, 900, "middle"))
    return "\n".join(s)


def brush_title(x, y, s, size, fill=EMBER, stroke=INK, sw=10, anchor="middle", rotate=0, glow=None, outline_white=False):
    """狀聲詞／標題字：粗襯線＋乾筆毛邊＋黑描邊（＋可選白外框）。"""
    tr = f'transform="rotate({rotate} {x} {y})"' if rotate else ""
    g = f'filter="url(#{glow})"' if glow else ""
    t = esc(s)
    base = f'x="{x}" y="{y}" font-family="{SERIF}" font-size="{size}" font-weight="900" text-anchor="{anchor}"'
    out = [f'<g {tr} {g}><g filter="url(#rough)">']
    if outline_white:
        out.append(f'<text {base} fill="none" stroke="{BONE}" stroke-width="{sw+10}" stroke-linejoin="round">{t}</text>')
    out.append(f'<text {base} fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round">{t}</text>')
    out.append(f'<text {base} fill="{fill}">{t}</text>')
    out.append('</g></g>')
    return "\n".join(out)


def burst(cx, cy, rx, ry, n=22, jag=0.22, fill=BONE, stroke=INK, sw=5, seed=1):
    """吶喊泡泡：鋸齒爆框。"""
    r = random.Random(seed)
    pts = []
    for i in range(n * 2):
        a = math.pi * 2 * i / (n * 2)
        k = 1.0 if i % 2 == 0 else 1 - jag * (0.7 + 0.6 * r.random())
        pts.append(f"{cx+math.cos(a)*rx*k:.1f},{cy+math.sin(a)*ry*k:.1f}")
    return f'<polygon points="{" ".join(pts)}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="miter"/>'


def speed_lines(cx, cy, r0, r1, n=90, color=BONE, opacity=0.5, seed=3, width=6):
    """集中線。"""
    r = random.Random(seed)
    s = []
    for _ in range(n):
        a = r.random() * math.pi * 2
        w = r.uniform(0.004, 0.012) * width / 6
        rr = r.uniform(r0, r0 * 1.5)
        p = [(cx + math.cos(a - w) * r1, cy + math.sin(a - w) * r1),
             (cx + math.cos(a + w) * r1, cy + math.sin(a + w) * r1),
             (cx + math.cos(a) * rr, cy + math.sin(a) * rr)]
        s.append(f'<polygon points="{" ".join(f"{u:.1f},{v:.1f}" for u, v in p)}"/>')
    return f'<g fill="{color}" opacity="{opacity}">' + "".join(s) + "</g>"


def splatter(cx, cy, spread, n=40, color=BLOOD, seed=5, big=10):
    """血點／墨點。"""
    r = random.Random(seed)
    s = []
    for _ in range(n):
        a = r.random() * math.pi * 2
        d = abs(r.gauss(0, spread))
        rad = max(0.8, big * math.exp(-d / spread * 1.6) * r.uniform(0.3, 1))
        s.append(f'<circle cx="{cx+math.cos(a)*d:.1f}" cy="{cy+math.sin(a)*d:.1f}" r="{rad:.1f}"/>')
    return f'<g fill="{color}">' + "".join(s) + "</g>"


def embers(x0, y0, x1, y1, n=50, seed=9, color=EMBER):
    """火星／灰燼。"""
    r = random.Random(seed)
    s = []
    for _ in range(n):
        x, y = r.uniform(x0, x1), r.uniform(y0, y1)
        l = r.uniform(2, 7)
        s.append(f'<rect x="{x:.0f}" y="{y:.0f}" width="{l:.1f}" height="{l*0.45:.1f}" transform="rotate({r.uniform(-60,60):.0f} {x:.0f} {y:.0f})" opacity="{r.uniform(.4,1):.2f}"/>')
    return f'<g fill="{color}" filter="url(#glowRed)">' + "".join(s) + "</g>"


def slash(x0, y0, x1, y1, w=26, glow=True):
    """刀光：白刃橫切，外帶青光。"""
    ang = math.degrees(math.atan2(y1 - y0, x1 - x0))
    ln = math.hypot(x1 - x0, y1 - y0)
    f = 'filter="url(#glowTeal)"' if glow else ""
    return (f'<g transform="translate({x0} {y0}) rotate({ang:.2f})" {f}>'
            f'<path d="M0,0 Q{ln*0.5},{-w} {ln},0 Q{ln*0.5},{-w*0.35} 0,0 Z" fill="#fff"/>'
            f'<path d="M{ln*0.08},{-2} Q{ln*0.5},{-w*0.6} {ln*0.92},{-2}" stroke="#d6fbff" stroke-width="1.5" fill="none"/></g>')


def bar(x, y, w, h, frac, fill="url(#bloodFill)", segs=0, label=None, cut=12, back="#1b1418"):
    """粗黑邊斜尾條（生命、首領）。"""
    p = f"M{x},{y} H{x+w} L{x+w-cut},{y+h} H{x} Z"
    fw = max(0, (w - cut) * frac)
    s = [f'<path d="{p}" fill="{back}" stroke="{INK}" stroke-width="7" stroke-linejoin="round"/>',
         f'<clipPath id="c{x}_{y}"><path d="{p}"/></clipPath>',
         f'<g clip-path="url(#c{x}_{y})"><rect x="{x}" y="{y}" width="{fw+cut*(1-(y+h-y)/h)}" height="{h}" fill="{fill}"/>'
         f'<path d="M{x+fw},{y} l{cut},0 l{-cut},{h} z" fill="{fill}"/>'
         f'<rect x="{x}" y="{y}" width="{w}" height="{h*0.32}" fill="#fff" opacity=".12"/>'
         f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="url(#hatch)"/></g>',
         f'<path d="{p}" fill="none" stroke="{BONE}" stroke-width="2"/>']
    for i in range(1, segs):
        sx = x + (w - cut) * i / segs
        s.append(f'<path d="M{sx+cut*0.7},{y} l{-cut*0.7},{h}" stroke="{INK}" stroke-width="2.5"/>')
    if label:
        s.append(text(x + 14, y + h / 2 + 7, label, 19, BONE, SANS, 900, extra=f'stroke="{INK}" stroke-width="4" paint-order="stroke"'))
    return "\n".join(s)


def portrait(key, x, y, w, h, clip_path=None, filt=None, cid=None):
    cid = cid or f"p{key}{x}{y}"
    cp = clip_path or f"M{x},{y} h{w} v{h} h{-w} z"
    f = f'filter="url(#{filt})"' if filt else ""
    return (f'<clipPath id="{cid}"><path d="{cp}"/></clipPath>'
            f'<image href="{asset(key)}" x="{x}" y="{y}" width="{w}" height="{h}" preserveAspectRatio="xMidYMin slice" clip-path="url(#{cid})" {f}/>')


def seal(x, y, s, size=34, color=BLOOD, rotate=-4):
    """朱印（稀有度、標記）。"""
    n = len(s)
    w = size * (1.25 if n <= 2 else 0.95 * n + 0.3)
    return (f'<g transform="rotate({rotate} {x} {y})"><g filter="url(#rough)">'
            f'<rect x="{x-w/2}" y="{y-size*0.7}" width="{w}" height="{size*1.4}" fill="{color}"/></g>'
            f'<rect x="{x-w/2+4}" y="{y-size*0.7+4}" width="{w-8}" height="{size*1.4-8}" fill="none" stroke="{BONE}" stroke-width="1.5" opacity=".8"/>'
            + text(x, y + size * 0.36, s, size, BONE, SERIF, 900, "middle") + "</g>")


def pips(x, y, n, total=5, size=14, on=EMBER, marks=(3, 5)):
    """武學等級刻點；小成（3）、圓滿（5）為菱形。"""
    s = []
    for i in range(total):
        cx = x + i * (size + 8)
        lv = i + 1
        col = on if lv <= n else "#2e2a31"
        if lv in marks:
            s.append(f'<rect x="{cx-size*0.55}" y="{y-size*0.55}" width="{size*1.1}" height="{size*1.1}" transform="rotate(45 {cx} {y})" fill="{col}" stroke="{BONE if lv<=n else "#555"}" stroke-width="1.5"/>')
        else:
            s.append(f'<rect x="{cx-size*0.4}" y="{y-size*0.4}" width="{size*0.8}" height="{size*0.8}" fill="{col}"/>')
    return "".join(s)


def crosshair(cx, cy):
    s = []
    for dx, dy in [(-1, -1), (1, -1), (-1, 1), (1, 1)]:
        s.append(f'<path d="M{cx+dx*14},{cy+dy*5} V{cy+dy*14} H{cx+dx*5}" fill="none" stroke="{BONE}" stroke-width="2.5"/>')
    s.append(f'<circle cx="{cx}" cy="{cy}" r="2.5" fill="{TEAL}"/>')
    return f'<g filter="url(#glowTeal)" opacity=".9">{"".join(s)}</g>'


def note(x, y, rows):
    """稿面註記（給美術／實作看的，不是遊戲介面）。"""
    s = [f'<g opacity=".95"><rect x="{x}" y="{y}" width="{max(len(r) for r in rows)*13+24}" height="{len(rows)*20+16}" fill="#ffe94d"/>']
    s.append(lines(x + 12, y + 23, rows, 13, 1.54, fill=INK, font=SANS, weight=700))
    s.append("</g>")
    return "\n".join(s)


def callout(x0, y0, x1, y1):
    return f'<path d="M{x0},{y0} L{x1},{y1}" stroke="#ffe94d" stroke-width="2" stroke-dasharray="5 4"/><circle cx="{x1}" cy="{y1}" r="4" fill="#ffe94d"/>'


# ================================================================ 畫面
def s00_style():
    b = []
    b.append(text(60, 82, "天魔劫・介面風格稿", 44, BONE, SERIF, 900))
    b.append(text(60, 118, "基準：韓式武俠條漫語彙——墨黑底、血紅／橘紅、電光青背光、旁白黑框、系統白框、狀聲詞、集中線", 18, GREY, SANS, 500))
    # 色票
    sw = [(INK, "墨黑", "底色"), (VIOLET, "髮影紫", "陰影"), (BLOOD, "血紅", "生命／敵"), (EMBER, "橘紅", "標題／強調"),
          (TEAL, "電光青", "系統／修為"), (BONE, "骨白", "文字／框線"), (GOLD, "冷黃", "極少量點睛")]
    for i, (c, n, u) in enumerate(sw):
        x = 60 + i * 112
        b.append(f'<rect x="{x}" y="150" width="96" height="96" fill="{c}" stroke="{BONE}" stroke-width="2"/>')
        b.append(text(x, 272, n, 17, BONE, SANS, 700))
        b.append(text(x, 292, c, 12, GREY, SANS, 500))
        b.append(text(x, 310, u, 12, GREY, SANS, 500))
    # 稀有度
    b.append(text(880, 170, "稀有度（色相沿用 rarity.csv，明度改配黑底）", 16, GREY, SANS, 700))
    for i, (k, (n, c)) in enumerate(RARITY.items()):
        b.append(seal(940 + i * 150, 222, n, 30, c, -3 + i * 2))
        b.append(text(940 + i * 150, 290, c, 12, GREY, SANS, 500, "middle"))
    # 字
    b.append(brush_title(60, 420, "鎖陣", 110, EMBER, INK, 12, "start", -4, outline_white=True))
    b.append(text(60, 462, "標題／狀聲詞：極粗襯線＋乾筆毛邊＋黑描邊（＋白外框），可傾斜；突破類用青光", 15, GREY, SANS, 700))
    b.append(brush_title(330, 430, "破陣", 76, BONE, INK, 9, "start", 3))
    b.append(brush_title(520, 430, "突破", 76, TEAL, INK, 9, "start", -3, glow="glowTeal"))
    # 旁白框
    b.append(narration(60, 492, 420, 110, ["十年前，天魔神教血洗中原。", "如今天魔復活。"], 22))
    b.append(text(60, 615, "旁白框：區域名、劇情、結算句（襯線）", 15, GREY, SANS, 700))
    # 系統框
    b.append(system_box(530, 488, 380, 96, ["修為 +12　精進至 三流・第三重", "銀兩 +18"], 18, tag="系統"))
    b.append(text(530, 615, "系統框：數值、提示、說明（黑體）", 15, GREY, SANS, 700))
    b.append(system_box(950, 488, 300, 96, ["按 E 參悟", "悟道碑浮現"], 18, dark=True, tag="提示"))
    b.append(text(950, 615, "暗版系統框：戰鬥中不擋畫面", 15, GREY, SANS, 700))
    # 按鈕
    b.append(text(60, 668, "按鈕狀態", 16, GREY, SANS, 700))
    b.append(button(60, 690, 260, 62, "踏上江湖"))
    b.append(button(360, 690, 260, 62, "踏上江湖", "hover"))
    b.append(button(660, 690, 260, 62, "再悟（60）", "disabled"))
    b.append(text(60, 780, "一般", 14, GREY, SANS)); b.append(text(360, 780, "游標／焦點：血紅底＋青括弧", 14, GREY, SANS)); b.append(text(660, 780, "停用", 14, GREY, SANS))
    # 條
    b.append(text(980, 668, "生命／修為／首領條", 16, GREY, SANS, 700))
    b.append(bar(980, 690, 520, 34, 0.68, label="98 / 144"))
    b.append(bar(980, 740, 520, 12, 0.4, "url(#tealFill)", segs=10, cut=6))
    b.append(bar(980, 772, 520, 22, 0.82, "url(#bloodFill)", segs=4, cut=10))
    b.append(text(980, 822, "等級刻點：", 15, GREY, SANS, 700)); b.append(pips(1070, 817, 3))
    b.append(text(1210, 822, "◆＝小成／圓滿", 14, GREY, SANS))
    # 效果
    b.append(f'<g transform="translate(1370 380)">{burst(0, 0, 150, 92, 20, 0.28, BONE, INK, 5, 3)}</g>')
    b.append(brush_title(1370, 405, "斬！", 72, BLOOD, INK, 9, "middle", -6))
    b.append(text(1370, 312, "吶喊泡泡：橫幅、首領登場", 15, GREY, SANS, 700, "middle"))
    b.append(crosshair(1500, 860))
    b.append(text(1480, 865, "準星", 14, GREY, SANS, 700, "end"))
    return doc("\n".join(b), "00 風格稿")


def s01_menu():
    b = []
    b.append(f'<image href="{asset("pass")}" x="-40" y="0" width="1680" height="940" preserveAspectRatio="xMidYMid slice" filter="url(#duoInk)"/>')
    b.append(f'<rect width="{W}" height="{H}" fill="{INK}" opacity=".35"/>')
    b.append(f'<ellipse cx="560" cy="360" rx="560" ry="330" fill="url(#tealBloom)" opacity=".75"/>')
    b.append(speed_lines(560, 360, 230, 1100, 110, INK, 0.55, 3, 8))
    b.append(f'<rect width="{W}" height="{H}" fill="url(#vignette)"/>')
    # 刀光斜切畫面
    b.append(slash(-60, 690, 1680, 170, 34))
    b.append(splatter(800, 330, 70, 70, BLOOD, 5, 12))
    # 標題
    b.append(brush_title(560, 400, "天魔劫", 220, EMBER, INK, 16, "middle", -3, outline_white=True))
    b.append(narration(200, 500, 720, 120, ["十年前，天魔神教血洗中原。如今天魔復活，", "綠林、暗月樓、屍門盡成爪牙。", "一路殺上天魔神教總壇，了結這場劫數。"], 21))
    # 選單
    b.append(slant(1060, 360, 470, 420, 30, INK, BONE, 3, 'opacity=".82"'))
    b.append(button(1100, 400, 380, 78, "踏上江湖", "normal", 34))
    b.append(button(1100, 496, 380, 60, "操作說明", "normal", 28))
    b.append(button(1100, 572, 380, 60, "設定", "normal", 28))
    b.append(button(1100, 648, 380, 60, "離開遊戲", "normal", 28))
    b.append(text(1290, 735, "滑鼠點選　Enter 確認", 16, GREY, SANS, 700, "middle"))
    b.append(embers(0, 600, 1600, 900, 70, 9))
    b.append(text(1570, 880, "武俠 Roguelike・灰盒原型", 14, GREY, SANS, 500, "end"))
    b.append(note(30, 800, ["稿註：標題獨立不加印章與副標；類型資訊縮到右下角小字。"]))
    return doc("\n".join(b), "01 主選單")


# ---------------------------------------------------------------- 讀資料（稿面文字沿用 CSV）
import csv


def _csv(name, key=None):
    with open(os.path.join(ROOT, "data", name + ".csv"), encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    return {r[key]: r for r in rows} if key else rows


def wrap(s, n):
    out, cur = [], ""
    for ch in s:
        cur += ch
        if len(cur) >= n and ch not in "，。、；：）」%" and not ch.isdigit():
            out.append(cur)
            cur = ""
    if cur:
        out.append(cur)
    return out


def num(v):
    v = float(v)
    return str(int(v)) if v == int(v) else f"{v:g}"


def martial_value(m, lv):
    return num(float(m["lv1_value"]) + float(m["per_level"]) * (lv - 1))


def s02_select():
    chars = _csv("characters", "char_id")
    sects = _csv("sects", "sect_id")
    passives = _csv("character_passives")
    realms = _csv("character_realms")
    b = []
    b.append(f'<rect width="{W}" height="{H}" fill="{INK}"/>')
    b.append(speed_lines(800, 450, 380, 1100, 80, VIOLET, 0.8, 21, 9))
    b.append(brush_title(800, 92, "選擇角色", 70, BONE, INK, 9, "middle", -2))
    order = ["nangong", "han", "tang"]
    sel = "nangong"
    k = 46
    for i, cid in enumerate(order):
        c = chars[cid]
        x, y, w, h = 92 + i * 486, 150, 450, 660
        on = cid == sel
        outline = f"M{x+k},{y} H{x+w} L{x+w-k},{y+h} H{x} Z"
        if on:
            b.append(f'<path d="{outline}" fill="{BLOOD}" filter="url(#glowRed)" transform="translate(0 0)"/>')
            b.append(f'<clipPath id="bl{cid}"><path d="{outline}"/></clipPath>')
            b.append(f'<g clip-path="url(#bl{cid})"><rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{INK}"/>'
                     f'<ellipse cx="{x+w/2}" cy="{y+170}" rx="300" ry="260" fill="url(#tealBloom)"/></g>')
        else:
            b.append(f'<path d="{outline}" fill="{INK2}"/>')
        # 立繪：上 360px，斜切下緣
        ph = 318
        clip = f"M{x+k},{y} H{x+w} L{x+w-k*ph/h},{y+ph-30} L{x},{y+ph+10} V{y+ph} L{x+k*(1-ph/h)},{y+ph} Z"
        clip = f"M{x+k},{y} H{x+w} L{x+w-k*(ph-30)/h},{y+ph-30} L{x+k*(h-ph-10)/h - k + k},{y+ph+10} Z"
        top = f"M{x+k},{y} H{x+w} L{x+w-k*(ph-34)/h},{y+ph-34} L{x+k-k*(ph+8)/h},{y+ph+8} Z"
        b.append(portrait(cid, x - 10, y, w + 20, ph + 40, top, None if on else "duoInk", f"pc{cid}"))
        if not on:
            b.append(f'<path d="{top}" fill="{INK}" opacity=".45"/>')
        b.append(f'<path d="M{x+w-k*(ph-34)/h},{y+ph-34} L{x+k-k*(ph+8)/h},{y+ph+8}" stroke="{BONE if on else GREY}" stroke-width="5"/>')
        # 名字（壓在立繪下緣）
        b.append(brush_title(x + 40, y + ph + 12, c["name_zh"], 66, BONE if on else "#b9b3bb", INK, 10, "start", -3))
        sect = sects[c["origin_sect"]]["name_zh"]
        b.append(seal(x + w - 92, y + ph - 6, sect, 22, BLOOD if on else "#4a2a2e", 4))
        ty = y + ph + 50
        b.append(text(x + 40, ty, f'{c["title"]}', 21, EMBER if on else GREY, SERIF, 900))
        for j, row in enumerate(wrap(c["bio"], 22)):
            b.append(text(x + 40, ty + 30 + j * 24, row, 16, "#c9c2cb" if on else "#6f6a72", SANS, 500))
        sy = ty + 82
        b.append(system_box(x + 34, sy, w - 100, 40, [f'生命 {c["hp"]}　移速 {c["move_speed"]} m/s'], 17, dark=not on, accent=TEAL if on else "#3b4a4c"))
        py = sy + 72
        for p in [p for p in passives if p["char_id"] == cid]:
            t = p["effect_template"].replace("{v}", num(p["lv1_value"]))
            b.append(f'<rect x="{x+30}" y="{py-16}" width="44" height="22" fill="{EMBER if on else "#3a2a26"}"/>')
            b.append(text(x + 52, py + 1, "被動", 14, INK if on else GREY, SANS, 900, "middle"))
            row = f'{p["name_zh"]}：{t}'
            for j, r in enumerate(wrap(row, 23)[:2]):
                b.append(text(x + 82, py + j * 21, r, 15.5, BONE if on else "#7d7880", SANS, 700))
            py += 21 * min(2, len(wrap(row, 23))) + 9
        for r in [r for r in realms if r["char_id"] == cid]:
            b.append(text(x + 30 - (py - y - ph) * 0.0, py, f'◆ {r["realm_zh"]}・{r["name_zh"]}', 14.5, TEAL if on else "#3e5b5d", SANS, 900))
            py += 22
        if on:
            b.append(button(x + 60, y + h + 18, 300, 58, "選定此人", "normal", 26))
    b.append(button(1330, 836, 200, 50, "返回", "normal", 22))
    b.append(note(1270, 20, ["稿註：選中者全彩＋青背光＋血紅外光；", "未選者壓成墨色雙色調。境界效果收合，", "游標停留時展開成系統框。"]))
    return doc("\n".join(b), "02 角色選擇")


def weapon_icon(x, y, kind, s=1.0, color=BONE):
    """武器剪影（HUD 小圖示）。"""
    if kind == "tachi":
        return (f'<g transform="translate({x} {y}) scale({s}) rotate(-28)" fill="{color}">'
                f'<path d="M-46,4 Q0,-6 50,-14 L54,-12 Q4,0 -44,8 Z"/><rect x="-60" y="2" width="16" height="6"/>'
                f'<rect x="-46" y="-2" width="4" height="16"/></g>')
    if kind == "bow":
        return (f'<g transform="translate({x} {y}) scale({s})" fill="none" stroke="{color}" stroke-width="5">'
                f'<path d="M-8,-44 Q34,0 -8,44"/><path d="M-8,-44 L-8,44" stroke-width="1.5"/>'
                f'<path d="M-30,0 H34" stroke-width="2.5"/><path d="M34,0 l-8,-5 m8,5 l-8,5" stroke-width="2.5"/></g>')
    return (f'<g transform="translate({x} {y}) scale({s}) rotate(-35)" fill="{color}">'
            f'<path d="M-40,-7 H52 L60,0 L52,7 H-40 Z"/><rect x="-48" y="-14" width="8" height="28"/><rect x="-66" y="-4" width="18" height="8"/></g>')


def coin(x, y, r=12):
    return (f'<circle cx="{x}" cy="{y}" r="{r}" fill="{GOLD}" stroke="{INK}" stroke-width="3"/>'
            f'<rect x="{x-r*0.32}" y="{y-r*0.32}" width="{r*0.64}" height="{r*0.64}" fill="{INK}"/>')


def s03_hud():
    b = []
    b.append(f'<image href="{asset("scene")}" x="0" y="0" width="{W}" height="{H}" preserveAspectRatio="xMidYMid slice"/>')
    b.append(f'<rect width="{W}" height="{H}" fill="url(#vignette)" opacity=".8"/>')
    # 傷害數字
    b.append(brush_title(470, 420, "128", 46, BONE, INK, 8, "middle", -6))
    b.append(brush_title(1240, 420, "312", 74, EMBER, INK, 10, "middle", 5, outline_white=True))
    b.append(text(1236, 350, "暴擊", 22, INK, SERIF, 900, "middle", f'stroke="{BONE}" stroke-width="6" paint-order="stroke"'))
    b.append(text(1060, 470, "格", 30, TEAL, SERIF, 900, "middle", f'stroke="{INK}" stroke-width="6" paint-order="stroke" filter="url(#glowTeal)"'))
    b.append(crosshair(800, 450))
    # 上方：首領
    b.append(brush_title(800, 66, "黑風寨主", 44, BONE, INK, 8, "middle", 0))
    b.append(seal(622, 50, "首領", 20, BLOOD, -6))
    b.append(bar(450, 82, 700, 24, 0.72, segs=4, cut=12))
    b.append(text(800, 132, "迴旋斬蓄力中──", 17, EMBER, SANS, 900, "middle", f'stroke="{INK}" stroke-width="4" paint-order="stroke"'))
    # 中央橫幅（鎖陣）
    b.append(f'<g opacity=".97">{burst(800, 248, 210, 88, 22, 0.3, BONE, INK, 6, 8)}</g>')
    b.append(brush_title(800, 282, "鎖　陣", 92, BLOOD, INK, 11, "middle", -4))
    b.append(narration(620, 340, 360, 44, ["殺光敵人方可破陣"], 18))
    # 左上：訊息
    msgs = [("精進", "三流・第四重　生命回復 20%", 1.0), ("銀兩", "+18", .8), ("習得", "鷹爪功 熟練（Lv2）", .55)]
    for i, (tag, m, op) in enumerate(msgs):
        b.append(f'<g opacity="{op}">{system_box(30, 36 + i * 68, 330, 46, [m], 16, tag=tag, dark=True)}</g>')
    # 右上：區域、敵數、武學
    b.append(narration(1190, 26, 380, 64, ["綠林山寨・第 2 區　箭樓"], 21))
    b.append(slant(1352, 102, 218, 40, 12, BLOOD, BONE, 2))
    b.append(text(1458, 129, "剩餘敵人 7", 19, BONE, SANS, 900, "middle"))
    b.append(text(1570, 172, "武學 3 / 8", 15, GREY, SANS, 900, "end", f'stroke="{INK}" stroke-width="4" paint-order="stroke"'))
    chips = [("鷹爪功", 2, False), ("快刀訣", 1, False), ("金鐘罩", 3, True)]
    for i, (n, lv, brk) in enumerate(chips):
        cy = 186 + i * 34
        b.append(f'<rect x="{1406}" y="{cy}" width="164" height="28" fill="{INK}" opacity=".85" stroke="{EMBER if brk else "#55505a"}" stroke-width="2"/>')
        b.append(text(1416, cy + 20, n, 15, BONE, SANS, 900))
        b.append(pips(1488, cy + 14, lv, 5, 9))
    # 左下：角色
    b.append(f'<path d="M24,734 H540 L516,880 H24 Z" fill="{INK}" opacity=".78"/>')
    pclip = "M40,742 H176 L158,868 H40 Z"
    b.append(portrait("nangong", 30, 736, 150, 150, pclip, cid="hudp"))
    b.append(f'<path d="{pclip}" fill="none" stroke="{BONE}" stroke-width="4"/>')
    b.append(text(196, 772, "南宮逸", 26, BONE, SERIF, 900))
    b.append(f'<rect x="290" y="752" width="128" height="26" fill="{TEAL}"/>')
    b.append(text(354, 771, "三流・第三重", 15, INK, SANS, 900, "middle"))
    b.append(bar(192, 790, 360, 34, 0.68, label="98 / 144", cut=14))
    b.append(f'<path d="M192,786 H{192+360*0.25} " stroke="{GOLD}" stroke-width="5"/>')
    b.append(bar(192, 834, 340, 10, 0.45, "url(#tealFill)", segs=10, cut=6))
    b.append(coin(206, 866, 10))
    b.append(text(224, 872, "銀兩 236", 18, GOLD, SANS, 900, extra=f'stroke="{INK}" stroke-width="4" paint-order="stroke"'))
    b.append(f'<rect x="322" y="856" width="122" height="22" fill="{EMBER}"/>')
    b.append(text(383, 872, "免費參悟 ×1", 14, INK, SANS, 900, "middle"))
    # 右下：雙武器
    for i, (key, name, lv, kind, rar) in enumerate([("主武器", "太刀", 2, "tachi", "common"), ("副武器", "竹弓", 1, "bow", "common")]):
        x, y = 1110 + i * 240, 770
        col = RARITY[rar][1]
        b.append(slant(x, y, 226, 104, 18, INK, col if i == 0 else "#55505a", 3, 'opacity=".9"'))
        b.append(weapon_icon(x + 74, y + 44, kind, 0.95, BONE))
        b.append(f'<rect x="{x+18}" y="{y-12}" width="64" height="24" fill="{BONE if i==0 else GREY}"/>')
        b.append(text(x + 50, y + 6, key, 14, INK, SANS, 900, "middle"))
        b.append(text(x + 210, y + 84, name, 20, BONE, SERIF, 900, "end"))
        b.append(text(x + 210, y + 32, f"淬煉+{lv}", 15, EMBER if lv else GREY, SANS, 900, "end"))
        b.append(pips(x + 132, y + 50, lv, 5, 8, EMBER, (5,)))
    b.append(f'<rect x="1110" y="752" width="226" height="6" fill="{TEAL}" filter="url(#glowTeal)"/>')
    b.append(text(1576, 892, "Q／滾輪 切換主副武器", 14, GREY, SANS, 700, "end", f'stroke="{INK}" stroke-width="4" paint-order="stroke"'))
    # 下方提示
    b.append(system_box(640, 650, 320, 48, ["［E］參悟　悟道碑已浮現"], 18, dark=True, align="middle"))
    b.append(note(30, 230, ["稿註：鎖陣橫幅、首領條、提示同時出現僅為示意；", "實際依事件淡入淡出。傷害數字：一般白、暴擊橘紅＋白框、", "格擋青色。同時只拿一把武器，上緣青線＝手上那把。"]))
    return doc("\n".join(b), "03 戰鬥 HUD")


def s04_shrine():
    weapons = _csv("weapons", "weapon_id")
    martial = _csv("martial_arts", "martial_id")
    sects = _csv("sects", "sect_id")
    b = []
    b.append(f'<rect width="{W}" height="{H}" fill="{INK}"/>')
    b.append(f'<ellipse cx="800" cy="470" rx="820" ry="460" fill="url(#tealBloom)" opacity=".35"/>')
    b.append(speed_lines(800, 470, 420, 1200, 120, "#000", 0.6, 31, 8))
    b.append(brush_title(800, 76, "悟道碑・參悟", 64, BONE, INK, 9, "middle", -1))
    b.append(narration(470, 98, 660, 48, ["參悟費用 15 銀兩　｜　持有 236 銀兩　｜　免費參悟 ×1"], 18))
    # 天機條
    b.append(text(560, 176, "天機", 18, TEAL, SERIF, 900, "end"))
    b.append(bar(572, 160, 420, 18, 14 / 20, "url(#tealFill)", segs=20, cut=8))
    b.append(f'<path d="M{572+412*12/20},156 v28" stroke="{EMBER}" stroke-width="3"/>')
    b.append(text(1004, 176, "14 / 20 未遇絕世　幸運 0.20", 15, GREY, SANS, 900))
    b.append(text(564, 205, "▲ 第 12 次起天機漸顯，第 20 次必出絕世", 13, EMBER, SANS, 700, "start"))
    W001, W301, M007 = weapons["W001"], weapons["W301"], martial["M007"]
    cards = [
        dict(rar="common", kind="武器・刀・近戰", title=W001["name_zh"], icon="weapon", level="淬煉 +2 → +3",
             body=[W001["pattern_desc"], f'傷害 {W001["dmg"]} × {W001["hits"]} 段', f'間隔 {W001["interval_s"]} 秒　射程 {W001["range_m"]} m'],
             extra="器靈覺醒（+5）：" + W001["awaken_desc"], btns=[("領悟", "normal")]),
        dict(rar="legendary", kind="武器・巨劍・近戰", title=W301["name_zh"], icon="weapon", level="新武器",
             body=[W301["pattern_desc"], f'傷害 {W301["dmg"]} × {W301["hits"]} 段', f'間隔 {W301["interval_s"]} 秒　射程 {W301["range_m"]} m'],
             extra="器靈覺醒（+5）：" + W301["awaken_desc"], btns=[("替換主武器：太刀", "hover"), ("替換副武器：竹弓", "normal")]),
        dict(rar=M007["rarity"], kind=f'武學・{sects[M007["sect"]]["name_zh"]}・{M007["school"]}', title=M007["name_zh"], icon="manual",
             level="熟練 → 小成 ◆",
             body=[M007["effect_template"].replace("{v}", martial_value(M007, 3)), "（目前 " + M007["effect_template"].replace("{v}", martial_value(M007, 2)) + "）"],
             extra="小成：" + M007["lv3_desc"], btns=[("領悟", "normal")], pips=2),
    ]
    for i, c in sorted(enumerate(cards), key=lambda t: t[1]["rar"] != "legendary"):  # 絕世先畫，集中線壓在兩側卡片下
        legend = c["rar"] == "legendary"
        cw, ch = (420, 560) if legend else (390, 520)
        x = [130, 590, 1080][i] if not legend else 590
        x = {0: 140, 1: 590, 2: 1070}[i]
        y = 236 if legend else 262
        name, col = RARITY[c["rar"]]
        k = 28
        outline = f"M{x},{y} H{x+cw-k} L{x+cw},{y+k} V{y+ch} H{x+k} L{x},{y+ch-k} Z"
        if legend:
            b.append(f'<clipPath id="slc"><rect x="0" y="232" width="{W}" height="{H-232}"/></clipPath>')
            b.append(f'<g clip-path="url(#slc)">{speed_lines(x + cw / 2, y + 260, 260, 560, 60, col, 0.45, 41, 9)}</g>')
            b.append(f'<path d="{outline}" fill="{col}" filter="url(#glowRed)"/>')
        b.append(f'<path d="{outline}" fill="#0f0d12" stroke="{col}" stroke-width="{6 if legend else 4}"/>')
        # 上方色帶
        b.append(f'<clipPath id="cc{i}"><path d="{outline}"/></clipPath>')
        b.append(f'<g clip-path="url(#cc{i})"><path d="M{x},{y} H{x+cw} V{y+46} L{x},{y+86} Z" fill="{col}" opacity=".95"/>'
                 f'<path d="M{x},{y} H{x+cw} V{y+46} L{x},{y+86} Z" fill="url(#tone)" opacity=".5"/></g>')
        b.append(text(x + 22, y + 32, c["kind"], 16, INK, SANS, 900))
        b.append(seal(x + cw - 64, y + 72, name, 26 if not legend else 32, BLOOD if not legend else INK, 5))
        # 圖示
        b.append(f'<rect x="{x+22}" y="{y+100}" width="112" height="112" fill="{INK}" stroke="{BONE}" stroke-width="2"/>')
        b.append(f'<image href="{asset(c["icon"])}" x="{x+24}" y="{y+102}" width="108" height="108"/>')
        b.append(brush_title(x + 150, y + 168, c["title"], 46 if len(c["title"]) <= 4 else 40, BONE, INK, 8, "start", -2))
        b.append(text(x + 152, y + 204, c["level"], 19, EMBER, SANS, 900))
        if c.get("pips"):
            b.append(pips(x + 300, y + 198, c["pips"], 5, 10))
        b.append(system_box(x + 22, y + 236, cw - 44, 112, c["body"], 17))
        for j, r in enumerate(wrap(c["extra"], 21)[:3]):
            b.append(text(x + 24, y + 384 + j * 22, r, 15, TEAL, SANS, 700))
        by = y + ch - 24 - 58 * len(c["btns"])
        for j, (lab, st) in enumerate(c["btns"]):
            b.append(button(x + 30, by + j * 58, cw - 60, 48, lab, st, 20 if len(lab) > 4 else 24))
    if True:
        b.append(embers(540, 220, 1060, 860, 40, 13, RARITY["legendary"][1]))
    b.append(button(470, 836, 200, 50, "參悟", "disabled", 22))
    b.append(button(700, 836, 200, 50, "再悟（8）", "normal", 22))
    b.append(button(930, 836, 200, 50, "離開悟道碑", "normal", 20))
    b.append(text(1580, 890, "已習得的武學再次出現會升級；同門派武學越多，越容易參悟到該門派", 13, GREY, SANS, 700, "end"))
    b.append(note(20, 20, ["稿註：圖示暫用現有 weapon／manual 圖，", "之後每把武器、每本秘笈各自出圖。"]))
    return doc("\n".join(b), "04 悟道碑・參悟")


SECT_COL = {"tianjian": "#6fd8e0", "tianmo": "#e2343c", "tangmen": "#9a5cf0", "shaolin": "#e0a43a", "wudang": "#cfd6dc", "sanxue": GREY}
LV_NAME = ["", "入門", "熟練", "小成", "大成", "圓滿"]


def _dim_scene(b, op=0.8):
    b.append(f'<image href="{asset("scene")}" x="0" y="0" width="{W}" height="{H}" preserveAspectRatio="xMidYMid slice" filter="url(#duoInk)"/>')
    b.append(f'<rect width="{W}" height="{H}" fill="{INK}" opacity="{op}"/>')


def s05_panel():
    martial = _csv("martial_arts", "martial_id")
    sects = _csv("sects", "sect_id")
    bonds = _csv("sect_bonds")
    b = []
    _dim_scene(b, 0.86)
    b.append(brush_title(800, 82, "武學與門派傳承", 62, BONE, INK, 9, "middle", -1))
    # 左：角色
    x, y, w, h = 40, 130, 380, 680
    b.append(slant(x, y, w, h, 24, INK, BONE, 3))
    pclip = f"M{x+40},{y+20} H{x+w-20} L{x+w-36},{y+190} H{x+22} Z"
    b.append(portrait("han", x + 10, y + 10, w - 20, 300, pclip, cid="pp"))
    b.append(f'<path d="{pclip}" fill="none" stroke="{BONE}" stroke-width="3"/>')
    b.append(brush_title(x + 34, y + 238, "韓天狼", 44, BONE, INK, 8, "start", -2))
    b.append(f'<rect x="{x+226}" y="{y+208}" width="128" height="28" fill="{TEAL}"/>')
    b.append(text(x + 290, y + 228, "一流・第二重", 15, INK, SANS, 900, "middle"))
    stats = ["生命　188", "暴擊率　33%", "暴擊傷害　150%", "傷害　+10", "吸血　+7.5", "移動速度　+12", "閃避　+10"]
    b.append(system_box(x + 30, y + 262, w - 70, 240, stats, 17, tag="屬性"))
    b.append(text(x + 30, y + 548, "武器", 16, GREY, SANS, 900))
    for i, (hand, n, lv, rar) in enumerate([("主武器", "巨劍", 1, "legendary"), ("副武器", "竹弓", 1, "common")]):
        yy = y + 566 + i * 50
        col = RARITY[rar][1]
        b.append(slant(x + 26, yy, w - 66, 40, 12, INK2, col, 2))
        b.append(text(x + 46, yy + 27, hand, 14, TEAL if i == 0 else GREY, SANS, 900))
        b.append(text(x + 110, yy + 28, n, 19, col, SERIF, 900))
        b.append(text(x + w - 56, yy + 27, f"淬煉+{lv}", 15, EMBER if lv else GREY, SANS, 900, "end"))
    # 中：武學
    x, y, w, h = 450, 130, 620, 680
    b.append(slant(x, y, w, h, 24, INK, BONE, 3))
    b.append(text(x + 40, y + 46, "武學", 26, BONE, SERIF, 900))
    b.append(text(x + 106, y + 46, "5 / 8", 22, EMBER, SANS, 900))
    b.append(text(x + w - 40, y + 46, "◆ 小成、圓滿解鎖特效", 14, GREY, SANS, 700, "end"))
    owned = [("M007", 2), ("M006", 1), ("M002", 3), ("M001", 2), ("M003", 5)]
    for i in range(8):
        yy = y + 70 + i * 74
        if i >= len(owned):
            b.append(f'<path d="M{x+44},{yy} H{x+w-30} L{x+w-42},{yy+60} H{x+32} Z" fill="none" stroke="#3a363e" stroke-width="2" stroke-dasharray="8 6"/>')
            b.append(text(x + w / 2, yy + 37, "空", 18, "#4a464e", SERIF, 900, "middle"))
            continue
        mid, lv = owned[i]
        m = martial[mid]
        sc = SECT_COL[m["sect"]]
        brk = lv >= 3
        b.append(f'<path d="M{x+44},{yy} H{x+w-30} L{x+w-42},{yy+60} H{x+32} Z" fill="{INK2}" stroke="{EMBER if brk else "#4b4650"}" stroke-width="{3 if brk else 2}" {"filter=\'url(#glowRed)\'" if lv == 5 else ""}/>')
        b.append(f'<rect x="{x+48}" y="{yy+8}" width="44" height="44" fill="{sc}"/>')
        b.append(text(x + 70, yy + 40, sects[m["sect"]]["name_zh"][0], 26, INK, SERIF, 900, "middle"))
        b.append(text(x + 108, yy + 28, m["name_zh"], 22, RARITY[m["rarity"]][1] if m["rarity"] != "common" else BONE, SERIF, 900))
        b.append(f'<rect x="{x+108}" y="{yy+36}" width="46" height="20" fill="{EMBER if brk else "#3b363f"}"/>')
        b.append(text(x + 131, yy + 51, LV_NAME[lv], 13, INK if brk else BONE, SANS, 900, "middle"))
        eff = m["effect_template"].replace("{v}", martial_value(m, lv))
        if lv >= 3:
            eff += "　◆" + (m["lv5_desc"] if lv == 5 else m["lv3_desc"])
        b.append(text(x + 164, yy + 51, eff[:30] + ("…" if len(eff) > 30 else ""), 14, "#c9c2cb", SANS, 700))
        b.append(pips(x + w - 150, yy + 22, lv, 5, 12))
    # 右：門派
    x, y, w, h = 1100, 130, 460, 680
    b.append(slant(x, y, w, h, 24, INK, BONE, 3))
    b.append(text(x + 40, y + 46, "門派傳承", 26, BONE, SERIF, 900))
    counts = {"tianjian": 2, "tianmo": 1, "shaolin": 1, "wudang": 1, "tangmen": 0}
    for i, sid in enumerate(["tianjian", "tianmo", "tangmen", "shaolin", "wudang"]):
        yy = y + 78 + i * 118
        sc = SECT_COL[sid]
        n = counts[sid]
        tiers = [r for r in bonds if r["sect_id"] == sid]
        b.append(f'<rect x="{x+34}" y="{yy}" width="6" height="96" fill="{sc}"/>')
        b.append(text(x + 52, yy + 24, sects[sid]["name_zh"], 21, sc if n >= 2 else BONE, SERIF, 900))
        b.append(text(x + 52 + len(sects[sid]["name_zh"]) * 22 + 8, yy + 23, f"{n} 門　{sects[sid]['style']}", 14, GREY, SANS, 700))
        # 節點
        nx0, nx1, ny = x + 70, x + w - 70, yy + 52
        b.append(f'<path d="M{nx0},{ny} H{nx1}" stroke="#3b363f" stroke-width="4"/>')
        reach = [0, 2, 4, 5]
        frac = min(1.0, n / 5)
        b.append(f'<path d="M{nx0},{ny} H{nx0+(nx1-nx0)*frac}" stroke="{sc}" stroke-width="4"/>')
        for j, t in enumerate(tiers):
            req = int(t["count_required"])
            cx = nx0 + (nx1 - nx0) * req / 5
            on = n >= req
            b.append(f'<rect x="{cx-11}" y="{ny-11}" width="22" height="22" transform="rotate(45 {cx} {ny})" fill="{sc if on else INK}" stroke="{sc if on else "#55505a"}" stroke-width="3" {"filter=\'url(#glowTeal)\'" if on else ""}/>')
            ly = ny - 20 if req == 5 else ny + 32
            b.append(text(cx, ly, f'{req}・{t["name_zh"]}', 13, BONE if on else "#6f6a72", SANS, 900, "middle"))
        nxt = next((t for t in tiers if n < int(t["count_required"])), None)
        cur = [t for t in tiers if n >= int(t["count_required"])]
        msg = ("已啟：" + cur[-1]["effect_desc"]) if cur else ("下一階：" + nxt["effect_desc"]) if nxt else ""
        b.append(text(x + 52, yy + 108, msg[:27] + ("…" if len(msg) > 27 else ""), 13, TEAL if cur else GREY, SANS, 700))
    b.append(button(700, 836, 200, 50, "關閉（Tab）", "normal", 20))
    b.append(note(1180, 20, ["稿註：武學列滑鼠停留時，右側展開系統框", "顯示 Lv1–5 全部數值與小成／圓滿全文。"]))
    return doc("\n".join(b), "05 武學與門派")


def s06_pause():
    b = []
    _dim_scene(b, 0.62)
    b.append(speed_lines(420, 450, 330, 1200, 90, INK, 0.7, 51, 10))
    b.append(slash(-40, 900, 900, -40, 20))
    b.append(brush_title(420, 360, "暫停", 150, BONE, INK, 14, "middle", -5, outline_white=False))
    b.append(narration(170, 410, 500, 110, ["南宮逸　一流・第二重", "第 7 區　銀兩 236　已參悟 21 次"], 21))
    b.append(slant(900, 250, 520, 420, 30, INK, BONE, 3, 'opacity=".9"'))
    b.append(button(960, 300, 400, 72, "繼續", "hover", 32))
    b.append(button(960, 404, 400, 64, "武學與門派", "normal", 26))
    b.append(button(960, 500, 400, 64, "操作說明", "normal", 26))
    b.append(button(960, 596, 400, 54, "放棄本局", "normal", 22))
    b.append(text(1160, 700, "Esc 繼續", 16, GREY, SANS, 700, "middle"))
    b.append(note(30, 820, ["稿註：「放棄本局」按下後跳確認系統框（白框、紅字「確定放棄？」）。"]))
    return doc("\n".join(b), "06 暫停")


def s07_result():
    stages = _csv("stages", "stage")
    b = []
    b.append(f'<rect width="{W}" height="{H}" fill="{INK}"/>')
    b.append(f'<ellipse cx="800" cy="250" rx="760" ry="300" fill="{BLOOD}" opacity=".22" filter="url(#soft)"/>')
    b.append(speed_lines(800, 250, 260, 1200, 100, BLOOD, 0.35, 61, 8))
    b.append(splatter(560, 210, 120, 140, BLOOD, 17, 18))
    b.append(splatter(1120, 300, 80, 70, BLOOD, 19, 12))
    b.append(slash(1700, 90, -100, 430, 22, False))
    b.append(seal(460, 108, "敗北", 34, BLOOD, -8))
    b.append(brush_title(800, 300, "道消身殞", 170, BLOOD, INK, 16, "middle", -2, outline_white=True))
    st = stages["13"]["area_zh"]
    b.append(narration(430, 360, 740, 64, [f"殞落於 屍門鬼谷・第 13 區　{st}"], 24))
    cells = [("角色", "南宮逸"), ("境界", "一流・第五重"), ("擊殺", "214"), ("參悟", "33 次"), ("時間", "24 分 08 秒"),
             ("武器", "太刀+3、竹弓+1"), ("精進武學", "鷹爪功 Lv4、快刀訣 Lv3"), ("門派傳承", "天劍宗 第1階")]
    for i, (k, v) in enumerate(cells):
        if i < 5:
            xx, yy, ww = 150 + i * 262, 470, 238
        else:
            xx, yy, ww = [150, 520, 990][i - 5], 590, [340, 440, 460][i - 5]
        b.append(system_box(xx, yy, ww, 86, [v], 22, tag=k, align="middle"))
    b.append(button(650, 740, 300, 64, "回到主選單", "hover", 28))
    # 通關版示意
    b.append(f'<g transform="translate(1250 720)"><rect x="0" y="0" width="320" height="150" fill="{INK2}" stroke="{TEAL}" stroke-width="2"/>'
             f'<ellipse cx="160" cy="70" rx="160" ry="60" fill="url(#tealBloom)" opacity=".7"/>'
             + brush_title(160, 92, "天魔伏誅", 52, BONE, INK, 7, "middle", -2, glow="glowTeal")
             + text(160, 136, "通關版：血紅換電光青＋白刃", 13, BONE, SANS, 700, "middle") + "</g>")
    return doc("\n".join(b), "07 結算")


# ---------------------------------------------------------------- 掉落、鐵匠、商人
ICON_KIND = {"刀": "tachi", "弓": "bow", "巨劍": "sword"}
RANGE_ZH = {"melee": "近戰", "mid": "中距離", "ranged": "遠程"}


def affix_line(aid, v):
    row = _csv("weapon_affixes", "affix_id")[aid]
    return f'{row["name_zh"]}　{row["template"].replace("{v}", num(v))}'


def weapon_stats(w, lv=1):
    dmg = float(w["dmg"]) * (1 + 0.15 * (lv - 1))
    return [w["pattern_desc"], f'傷害 {num(round(dmg))} × {w["hits"]} 段', f'間隔 {w["interval_s"]} 秒　射程 {w["range_m"]} m']


def weapon_badge(x, y, size, kind, frame=BONE):
    return (f'<rect x="{x}" y="{y}" width="{size}" height="{size}" fill="{INK}" stroke="{frame}" stroke-width="2"/>'
            + speed_lines(x + size / 2, y + size / 2, size * 0.3, size * 0.75, 24, VIOLET, 0.9, 7, 6).replace("<g ", f'<g clip-path="url(#bc{x}{y})" ')
            + f'<clipPath id="bc{x}{y}"><rect x="{x}" y="{y}" width="{size}" height="{size}"/></clipPath>'
            + weapon_icon(x + size / 2, y + size / 2, kind, size / 110, BONE))


def s08_start_weapon():
    weapons = _csv("weapons", "weapon_id")
    b = []
    b.append(f'<rect width="{W}" height="{H}" fill="{INK}"/>')
    b.append(speed_lines(800, 470, 420, 1200, 90, VIOLET, 0.8, 23, 9))
    b.append(brush_title(800, 92, "選擇起手兵器", 64, BONE, INK, 9, "middle", -2))
    b.append(text(800, 130, "起手兵器沒有詞條；打怪掉落的兵器才有。之後可以到鐵匠處強化", 16, GREY, SANS, 700, "middle"))
    # 角色
    clip = "M40,30 H176 L158,150 H40 Z"
    b.append(portrait("nangong", 30, 24, 150, 130, clip, cid="swp"))
    b.append(f'<path d="{clip}" fill="none" stroke="{BONE}" stroke-width="3"/>')
    b.append(text(196, 78, "南宮逸", 30, BONE, SERIF, 900))
    b.append(text(196, 108, "名門天才・天劍宗", 16, EMBER, SERIF, 900))
    for i, wid in enumerate(["W001", "W007", "W301"]):
        w = weapons[wid]
        on = i == 0
        name, col = RARITY[w["rarity"]]
        x, y, cw, ch = 130 + i * 470, 180, 400, 560
        k = 28
        outline = f"M{x},{y} H{x+cw-k} L{x+cw},{y+k} V{y+ch} H{x+k} L{x},{y+ch-k} Z"
        if on:
            b.append(f'<path d="{outline}" fill="{BLOOD}" filter="url(#glowRed)"/>')
        b.append(f'<path d="{outline}" fill="{INK2 if not on else "#0f0d12"}" stroke="{BLOOD if on else "#3a363e"}" stroke-width="{4 if on else 3}"/>')
        b.append(f'<ellipse cx="{x+cw/2}" cy="{y+170}" rx="200" ry="150" fill="url(#tealBloom)" opacity="{.6 if on else .18}"/>')
        b.append(weapon_badge(x + 90, y + 40, 220, ICON_KIND[w["class"]], BONE if on else GREY))
        b.append(seal(x + cw - 60, y + 54, w["class"], 24, BLOOD if on else "#4a2a2e", 6))
        b.append(brush_title(x + cw / 2, y + 334, w["name_zh"], 50, BONE if on else "#b9b3bb", INK, 8, "middle", -2))
        b.append(text(x + cw / 2, y + 368, f'{w["class"]}・{RANGE_ZH[w["range_type"]]}', 18, EMBER if on else GREY, SERIF, 900, "middle"))
        b.append(system_box(x + 30, y + 392, cw - 60, 96, weapon_stats(w), 16, dark=not on, accent=TEAL if on else "#3b4a4c"))
        if on:
            b.append(button(x + 50, y + ch + 20, cw - 100, 58, "持此兵器入江湖", "normal", 26))
    b.append(button(1330, 836, 200, 50, "返回", "normal", 22))
    b.append(note(1210, 24, ["稿註：兵器不分品質，差別只在打法；", "可選的起手兵器由 weapons.csv 的 starter 欄決定。"]))
    return doc("\n".join(b), "08 起手兵器")


def s09_drop():
    weapons = _csv("weapons", "weapon_id")
    b = []
    b.append(f'<image href="{asset("scene")}" x="0" y="0" width="{W}" height="{H}" preserveAspectRatio="xMidYMid slice"/>')
    b.append(f'<rect width="{W}" height="{H}" fill="url(#vignette)" opacity=".8"/>')
    # 地上的掉落（光柱＋名牌）
    col = RARITY["common"][1]
    b.append(f'<rect x="792" y="250" width="16" height="230" fill="{TEAL}" opacity=".35" filter="url(#glowTeal)"/>')
    b.append(f'<g transform="rotate(-24 800 470)">{weapon_icon(800, 470, "bow", 0.9, BONE)}</g>')
    b.append(text(800, 236, "竹弓　詞條 3", 22, BONE, SERIF, 900, "middle", f'stroke="{INK}" stroke-width="6" paint-order="stroke"'))
    b.append(crosshair(800, 450))
    # 比較面板
    drop = [("A02", 8), ("A11", 12), ("A05", 2.4)]
    held = [("A01", 9)]
    px, py = 380, 540
    b.append(slant(px, py, 840, 196, 24, INK, BONE, 3, 'opacity=".94"'))
    for j, (title, wid, lv, affs, tag, hi) in enumerate([("地上", "W007", 1, drop, "撿起", True), ("手上・主武器", "W001", 3, held, "換下", False)]):
        w = weapons[wid]
        x = px + 40 + j * 400
        b.append(f'<rect x="{x}" y="{py+18}" width="{len(title)*16+20}" height="26" fill="{TEAL if hi else GREY}"/>')
        b.append(text(x + 10, py + 37, title, 16, INK, SANS, 900))
        b.append(text(x, py + 82, w["name_zh"], 30, BONE, SERIF, 900))
        b.append(text(x + len(w["name_zh"]) * 31 + 12, py + 80, f'淬煉+{lv}　{w["class"]}・{RANGE_ZH[w["range_type"]]}', 15, EMBER if lv > 1 else GREY, SANS, 900))
        for k, (aid, v) in enumerate(affs):
            b.append(text(x + 2, py + 116 + k * 26, "◆ " + affix_line(aid, v), 17, TEAL if hi else "#c9c2cb", SANS, 700))
        if not affs:
            b.append(text(x + 2, py + 116, "（沒有詞條）", 17, GREY, SANS, 700))
    b.append(f'<path d="M{px+410},{py+20} L{px+398},{py+176}" stroke="{GREY}" stroke-width="2"/>')
    b.append(text(px + 404, py + 104, "⇄", 30, BONE, SANS, 900, "middle"))
    b.append(system_box(530, 752, 540, 48, ["［E］撿起竹弓，換下手上的太刀"], 18, dark=True, align="middle"))
    b.append(text(800, 830, "換下的兵器會掉在原地，可以再撿回來；副武器格空著時直接放進副武器", 15, BONE, SANS, 700, "middle", f'stroke="{INK}" stroke-width="4" paint-order="stroke"'))
    # 角落 HUD（簡）
    b.append(narration(1190, 26, 380, 64, ["綠林山寨・第 4 區　聚義廳前"], 21))
    b.append(note(30, 30, ["稿註：靠近掉落兵器才出現這個比較面板，", "離開就收起。詞條較好的一方用青色標出。"]))
    return doc("\n".join(b), "09 掉落比較")


def _shop_frame(b, title_text, coin_text):
    b.append(f'<rect width="{W}" height="{H}" fill="{INK}"/>')
    b.append(f'<ellipse cx="800" cy="470" rx="820" ry="460" fill="url(#tealBloom)" opacity=".22"/>')
    b.append(speed_lines(800, 470, 420, 1200, 110, "#000", 0.6, 37, 8))
    b.append(brush_title(800, 82, title_text, 64, BONE, INK, 9, "middle", -1))
    b.append(narration(560, 106, 480, 48, [coin_text], 18))


def s10_smith():
    weapons = _csv("weapons", "weapon_id")
    b = []
    _shop_frame(b, "鐵匠・強化與重鑄", "持有 236 銀兩")
    b.append(f'<g transform="translate(1440 130)">{burst(0, 0, 90, 60, 16, 0.3, BONE, INK, 4, 11)}</g>')
    b.append(brush_title(1440, 146, "鏘！", 44, BLOOD, INK, 7, "middle", -8))
    slots = [("主武器", "W001", 3, [("A01", 9), ("A03", 12)], 0, True), ("副武器", "W007", 1, [], 0, False)]
    for i, (slot, wid, lv, affs, reforges, active) in enumerate(slots):
        w = weapons[wid]
        name, col = RARITY[w["rarity"]]
        x, y, cw, ch = 170 + i * 660, 190, 600, 600
        k = 28
        outline = f"M{x},{y} H{x+cw-k} L{x+cw},{y+k} V{y+ch} H{x+k} L{x},{y+ch-k} Z"
        b.append(f'<path d="{outline}" fill="#0f0d12" stroke="{BONE}" stroke-width="3"/>')
        b.append(f'<rect x="{x+22}" y="{y-12}" width="{len(slot + ("・手上" if active else ""))*16+28}" height="26" fill="{TEAL if active else GREY}"/>')
        b.append(text(x + 36, y + 7, slot + ("・手上" if active else ""), 15, INK, SANS, 900))
        b.append(weapon_badge(x + 30, y + 40, 150, ICON_KIND[w["class"]]))
        b.append(brush_title(x + 206, y + 106, w["name_zh"], 48, BONE, INK, 8, "start", -2))
        b.append(seal(x + cw - 64, y + 70, w["class"], 22, BLOOD, 5))
        b.append(text(x + 208, y + 146, f'{w["class"]}・{RANGE_ZH[w["range_type"]]}', 17, GREY, SERIF, 900))
        b.append(pips(x + 216, y + 178, lv, 5, 12, EMBER, (5,)))
        b.append(text(x + 330, y + 184, f"淬煉 +{lv}", 18, EMBER, SANS, 900))
        # 強化
        d0 = round(float(w["dmg"]) * (1 + 0.15 * (lv - 1)))
        d1 = round(float(w["dmg"]) * (1 + 0.15 * lv))
        b.append(system_box(x + 30, y + 224, cw - 60, 92, [f"淬煉 +{lv} → +{lv+1}", f"每段傷害 {d0} → {d1}"], 18, tag="強化"))
        b.append(button(x + 330, y + 334, 240, 52, "強化（52 銀兩）", "hover" if active else "normal", 20))
        # 詞條
        b.append(text(x + 32, y + 426, "詞條", 18, TEAL, SERIF, 900))
        if affs:
            for j, (aid, v) in enumerate(affs):
                b.append(text(x + 34, y + 458 + j * 28, "◆ " + affix_line(aid, v), 18, BONE, SANS, 700))
            b.append(button(x + 330, y + 520, 240, 52, "重鑄詞條（15 銀兩）", "normal", 19))
            b.append(text(x + 34, y + 568, "詞條數不變，全部重新抽；重鑄越多次越貴", 13, GREY, SANS, 700))
        else:
            b.append(text(x + 34, y + 458, "起手兵器沒有詞條，無法重鑄", 17, GREY, SANS, 700))
            b.append(button(x + 330, y + 520, 240, 52, "重鑄詞條", "disabled", 19))
    b.append(button(700, 836, 200, 50, "離開", "normal", 22))
    b.append(note(20, 20, ["稿註：強化價格隨淬煉等級與區域成長；", "器靈覺醒（+5）後強化按鈕改為「已覺醒」。"]))
    return doc("\n".join(b), "10 鐵匠")


def s11_merchant():
    martial = _csv("martial_arts", "martial_id")
    sects = _csv("sects", "sect_id")
    b = []
    _shop_frame(b, "商人・武學", "持有 236 銀兩　｜　武學 3 / 8")
    stock = [("M006", 1, False, 28), ("M002", 0, False, 28), ("M104", 0, True, 55), ("M205", 0, False, 110)]
    for i, (mid, lv, sold, price) in enumerate(stock):
        m = martial[mid]
        name, col = RARITY[m["rarity"]]
        sc = SECT_COL[m["sect"]]
        x, y, cw, ch = 80 + i * 370, 200, 330, 540
        k = 24
        outline = f"M{x},{y} H{x+cw-k} L{x+cw},{y+k} V{y+ch} H{x+k} L{x},{y+ch-k} Z"
        b.append(f'<g opacity="{.45 if sold else 1}">')
        b.append(f'<path d="{outline}" fill="#0f0d12" stroke="{col}" stroke-width="3"/>')
        b.append(f'<path d="M{x},{y} H{x+cw-k} L{x+cw},{y+k} V{y+40} L{x},{y+72} Z" fill="{col}" opacity=".95"/>')
        b.append(text(x + 18, y + 28, f'武學・{sects[m["sect"]]["name_zh"]}・{m["school"]}', 15, INK, SANS, 900))
        b.append(seal(x + cw - 50, y + 64, name, 20, BLOOD if m["rarity"] != "legendary" else INK, 5))
        b.append(f'<rect x="{x+20}" y="{y+90}" width="64" height="64" fill="{sc}"/>')
        b.append(text(x + 52, y + 135, sects[m["sect"]]["name_zh"][0], 36, INK, SERIF, 900, "middle"))
        b.append(brush_title(x + 98, y + 138, m["name_zh"], 36 if len(m["name_zh"]) <= 4 else 30, BONE, INK, 7, "start", -2))
        lvtxt = "新習得・入門" if lv == 0 else f'{["", "入門", "熟練", "小成", "大成", "圓滿"][lv]} → {["", "入門", "熟練", "小成", "大成", "圓滿"][lv+1]}'
        b.append(text(x + 22, y + 192, lvtxt, 17, EMBER, SANS, 900))
        b.append(pips(x + 190, y + 186, lv, 5, 9))
        eff = m["effect_template"].replace("{v}", martial_value(m, lv + 1))
        b.append(system_box(x + 20, y + 214, cw - 40, 90, wrap(eff, 17)[:2], 16))
        for j, r in enumerate(wrap("小成：" + m["lv3_desc"], 17)[:3]):
            b.append(text(x + 22, y + 336 + j * 22, r, 14, TEAL, SANS, 700))
        b.append("</g>")
        if sold:
            b.append(seal(x + cw / 2, y + 300, "已售出", 40, BLOOD, -12))
        else:
            b.append(button(x + 30, y + ch - 76, cw - 60, 52, f"購買（{price} 銀兩）", "hover" if i == 0 else "normal", 20))
    b.append(button(580, 836, 220, 50, "重新上架（8）", "normal", 20))
    b.append(button(820, 836, 200, 50, "離開", "normal", 22))
    b.append(text(1580, 890, "已習得的武學再買會升級；武學格滿時只上架已習得的武學", 13, GREY, SANS, 700, "end"))
    b.append(note(20, 20, ["稿註：每到休息區重新上架 4 門；", "價格依稀有度與區域成長，CSV 可調。"]))
    return doc("\n".join(b), "11 商人")


SECT_COL = {"tianjian": "#6fd8e0", "tianmo": "#e2343c", "tangmen": "#9a5cf0", "shaolin": "#e0a43a", "wudang": "#cfd6dc", "sanxue": GREY}


# ---------------------------------------------------------------- 經脈衝穴
STAT_ZH = None
AIM_RED = "#f0222e"   # 弓的散射圈


def _stat_text(stat, v):
    global STAT_ZH
    if STAT_ZH is None:
        STAT_ZH = {k: r["name_zh"] for k, r in _csv("stat_values", "stat_id").items()}
    v = float(v)
    vs = f"{v:.2f}".rstrip("0").rstrip(".")
    return f"{STAT_ZH[stat]}+{vs}{'%' if stat.endswith('_pct') else ''}"


# 人形輪廓（300×640 框，左半邊；右半邊鏡射）。自繪的站姿人形，仿明堂圖正背面並列的排法。
_BODY_L = [(150, 8), (126, 16), (116, 50), (126, 84), (136, 98), (134, 112), (92, 124), (74, 150), (62, 230), (48, 300),
           (36, 356), (44, 380), (58, 360), (72, 300), (88, 228), (100, 176), (106, 230), (110, 276), (98, 340), (100, 420),
           (106, 486), (104, 540), (112, 600), (92, 628), (132, 630), (132, 600), (138, 540), (136, 486), (144, 420), (150, 360)]


def body_figure(ox, oy, back=False):
    pts = _BODY_L + [(300 - x, y) for x, y in reversed(_BODY_L[1:-1])]
    n = len(pts)
    mid = lambda p, q: ((p[0] + q[0]) / 2, (p[1] + q[1]) / 2)
    m0 = mid(pts[-1], pts[0])
    d = f"M{ox+m0[0]:.1f},{oy+m0[1]:.1f}"
    for i in range(n):
        c, m = pts[i], mid(pts[i], pts[(i + 1) % n])
        d += f" Q{ox+c[0]:.1f},{oy+c[1]:.1f} {ox+m[0]:.1f},{oy+m[1]:.1f}"
    o = [f'<path d="{d} Z" fill="#17141b" stroke="{BONE}" stroke-width="2.5" opacity=".95" filter="url(#rough)"/>']
    ink = f'fill="none" stroke="{BONE}" stroke-width="1.3" opacity=".32"'
    if back:   # 脊柱、肩胛、髮髻
        o.append(f'<path d="M{ox+150},{oy+112} V{oy+346}" {ink} stroke-dasharray="3 6"/>')
        o.append(f'<path d="M{ox+118},{oy+150} q14,26 4,54 M{ox+182},{oy+150} q-14,26 -4,54" {ink}/>')
        o.append(f'<ellipse cx="{ox+150}" cy="{oy+12}" rx="13" ry="9" fill="#17141b" stroke="{BONE}" stroke-width="2"/>')
    else:      # 鎖骨、胸、臍、五官
        o.append(f'<path d="M{ox+112},{oy+136} q20,10 36,2 M{ox+188},{oy+136} q-20,10 -36,2" {ink}/>')
        o.append(f'<path d="M{ox+112},{oy+196} q18,14 34,0 M{ox+188},{oy+196} q-18,14 -34,0" {ink}/>')
        o.append(f'<circle cx="{ox+150}" cy="{oy+276}" r="3" {ink}/>')
        o.append(f'<path d="M{ox+134},{oy+46} h10 M{ox+156},{oy+46} h10 M{ox+144},{oy+70} h12" {ink}/>')
    return "\n".join(o)


def _meridian_tabs(b, mer, opened, sel):
    # 下：八脈選擇
    for i, mid_ in enumerate(mer):
        n = opened.get(mid_, 0)
        x = 30 + i * 101
        on = mid_ == sel
        b.append(slant(x, 846, 96, 40, 10, BLOOD if on else INK, BONE if on else ("#2a8f93" if n >= 4 else "#55505a"), 3 if on else 2))
        b.append(text(x + 40, 872, mer[mid_]["name_zh"], 16, BONE if (on or n) else GREY, SERIF, 900, "middle"))
        b.append(text(x + 80, 871, f"{n}/4", 12, TEAL if n >= 4 else GREY, SANS, 900, "middle"))


SIL_DEFS = (f'<defs><filter id="silRim" x="-5%" y="-5%" width="110%" height="110%"><feMorphology in="SourceAlpha" operator="dilate" radius="2.2" result="d"/>'
            f'<feFlood flood-color="{BONE}"/><feComposite in2="d" operator="in" result="rim"/><feMerge><feMergeNode in="rim"/><feMergeNode in="SourceGraphic"/></feMerge></filter>'
            '<filter id="silBone"><feColorMatrix type="matrix" values="0 0 0 0 .95  0 0 0 0 .93  0 0 0 0 .89  0 0 0 1 0"/></filter>'
            '<filter id="silGrey"><feColorMatrix type="matrix" values="0 0 0 0 .47  0 0 0 0 .45  0 0 0 0 .48  0 0 0 1 0"/></filter></defs>')


def pose_image(mid_, x, y, size, mode="silRim"):
    key = "mer_" + mid_
    if key not in _cache:
        _cache[key] = _img(f"assets/ui/meridian/{mid_}.webp", "PNG", (640, 640))
    return f'<image href="{_cache[key]}" x="{x}" y="{y}" width="{size}" height="{size}" filter="url(#{mode})"/>'


def meridian_points(mid_):
    rows = [r for r in _csv("acupoints") if r["meridian_id"] == mid_]
    return sorted(rows, key=lambda r: int(r["depth"]))


def point_layout(pts, ox, oy, size):
    """回傳（穴位座標, 每個穴位前面的轉折點）。"""
    P = [(ox + float(r["fx"]) * size, oy + float(r["fy"]) * size) for r in pts]
    V = [[(ox + float(v.split(",")[0]) * size, oy + float(v.split(",")[1]) * size) for v in r.get("via", "").split(";") if v] for r in pts]
    return P, V


def ink_disc(cx, cy, r, uid):
    o = [f'<defs><radialGradient id="disc{uid}" cx="42%" cy="38%" r="75%"><stop offset="0" stop-color="#3a9ea5"/><stop offset=".6" stop-color="#175a61"/><stop offset="1" stop-color="#0b2a2f"/></radialGradient></defs>']
    o.append(f'<circle cx="{cx}" cy="{cy}" r="{r*1.25}" fill="url(#tealBloom)" opacity=".35"/>')
    o.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#disc{uid})"/>')
    o.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="#050406" stroke-width="{r*0.12:.0f}" filter="url(#dry)"/>')
    return "".join(o)


def star_nodes(P, n, sel_idx, fails_k=0, sc=1.0, labels=None, vias=None):
    """穴位星圖：已通＝青色亮點與亮線；下一穴＝橘點＋準框；未通＝白色小點細線；最後一穴是大珠。"""
    o = []
    N = len(P)
    for i in range(N - 1):
        seg = [P[i]] + (vias[i + 1] if vias else []) + [P[i + 1]]
        lit = i + 1 < n
        o.append(f'<path d="M{" L".join(f"{x:.1f},{y:.1f}" for x, y in seg)}" fill="none" stroke-linejoin="round" stroke="{TEAL if lit else BONE}" stroke-width="{(3.5 if lit else 1.5)*sc}" opacity="{1 if lit else .6}" {"filter=\'url(#glowTeal)\'" if lit else ""}/>')
    for i, (x, y) in enumerate(P):
        on, nxt, big = i < n, i == n, i == N - 1
        r = (13 if big else 8) * sc
        if on:
            o.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="{TEAL}" stroke="{BONE}" stroke-width="{2*sc}" filter="url(#glowTeal)"/>')
            o.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r*0.38:.1f}" fill="{BONE}"/>')
        else:
            o.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="{INK}" stroke="{EMBER if nxt else BONE}" stroke-width="{(3 if nxt else 1.8)*sc}" {"filter=\'url(#glowRed)\'" if nxt else ""}/>')
            o.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r*0.36:.1f}" fill="{EMBER if nxt else BONE}"/>')
        if i == sel_idx:
            R = r + 12 * sc
            o.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{R}" fill="none" stroke="{BONE}" stroke-width="{2*sc}"/>')
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                o.append(f'<rect x="{x+dx*R-4*sc:.1f}" y="{y+dy*R-4*sc:.1f}" width="{8*sc}" height="{8*sc}" fill="{BONE}" transform="rotate(45 {x+dx*R:.1f} {y+dy*R:.1f})"/>')
    if labels:
        for i, (x, y) in enumerate(P):
            on, nxt = i < n, i == n
            side = 1 if i % 2 == 0 else -1
            lab = labels[i] + (f" ×{fails_k}" if (nxt and fails_k) else "")
            off = 30 if i == sel_idx else 16
            o.append(text(x + side * off, y + 5, lab, 15, TEAL if on else (EMBER if nxt else BONE), SERIF, 900, "start" if side > 0 else "end",
                          f'stroke="{INK}" stroke-width="5" paint-order="stroke" opacity="{1 if (on or nxt) else .8}"'))
    return "".join(o)


_DEMO_OPEN = {"ren": 9, "du": 4, "chong": 2, "yangwei": 5, "yinwei": 1}


def s12c_meridian_pose():
    mer = _csv("meridians", "meridian_id")
    cfg = {r["key"]: r["value"] for r in _csv("meridian_config")}
    levels = _csv("character_levels")
    opened = _DEMO_OPEN
    sel = "du"
    pts = meridian_points(sel)
    N = len(pts)
    n = opened.get(sel, 0)
    fails = {f"{sel}{n+1}": 2}
    total = sum(opened.values())
    all_n = len(_csv("acupoints"))
    # 境界＝全通的經脈數（data/realms.csv）
    full = sum(1 for k, v in opened.items() if v >= len(meridian_points(k)))
    realm = _csv("realms")[full]["name_zh"]
    left = min((len(meridian_points(k)) - opened.get(k, 0) for k in mer if opened.get(k, 0) < len(meridian_points(k))), default=0)
    to_next = left
    cost = round(float(cfg["cost_a"]) * (total + 1) ** float(cfg["cost_exp"]) + float(cfg["cost_b"]))
    m = mer[sel]
    b = [SIL_DEFS]
    _dim_scene(b, 0.92)
    b.append(text(40, 62, "經脈", 44, BONE, SERIF, 900, extra=f'stroke="{INK}" stroke-width="8" paint-order="stroke"'))
    b.append(f'<rect x="150" y="34" width="150" height="30" fill="{TEAL}"/>')
    b.append(text(225, 56, realm, 17, INK, SANS, 900, "middle"))
    b.append(text(316, 56, f"已通 {total} / {all_n} 穴　最近一條經脈再通 {to_next} 穴突破", 16, GREY, SANS, 900))
    b.append(f'<rect x="40" y="96" width="1520" height="700" fill="{INK2}" stroke="{BONE}" stroke-width="3"/>')
    b.append(f'<rect x="48" y="104" width="1504" height="684" fill="none" stroke="{BONE}" stroke-width="1" opacity=".4"/>')
    b.append(slant(620, 74, 360, 46, 16, INK, BONE, 3))
    b.append(text(800, 106, "經脈圖", 26, BONE, SERIF, 900, "middle"))
    # 左上：這條脈
    b.append(f'<rect x="92" y="130" width="76" height="76" transform="rotate(45 130 168)" fill="{INK}" stroke="{TEAL}" stroke-width="3"/>')
    b.append(pose_image(sel, 88, 126, 84, "silBone"))
    b.append(brush_title(130, 262, m["name_zh"], 34, EMBER, INK, 7, "middle", -2))
    b.append(text(130, 290, m["alias_zh"], 15, TEAL, SANS, 900, "middle"))
    b.append(text(130, 314, m["pose_zh"], 15, GREY, SERIF, 900, "middle"))
    # 中：墨圓、招式剪影、穴位星圖
    size, ox, oy = 600, 290, 112
    b.append(ink_disc(ox + size / 2, oy + size / 2 + 10, 262, "c"))
    b.append(pose_image(sel, ox, oy, size))
    P, V = point_layout(pts, ox, oy, size)
    b.append(star_nodes(P, n, n, fails.get(f"{sel}{n+1}", 0), 1.0, [r["name_zh"] for r in pts], V))
    for x, dr in ((236, 1), (944, -1)):
        b.append(f'<path d="M{x+dr*14},{424} L{x-dr*14},{460} L{x+dr*14},{496} L{x+dr*4},{460} Z" fill="{BONE}" stroke="{INK}" stroke-width="3"/>')
    b.append(text(236, 526, "A", 14, GREY, SANS, 900, "middle"))
    b.append(text(944, 526, "D", 14, GREY, SANS, 900, "middle"))
    b.append(button(470, 728, 220, 50, "返回（K）", "normal", 22))
    b.append(text(720, 760, "真氣", 20, BONE, SERIF, 900))
    b.append(f'<circle cx="784" cy="753" r="11" fill="{TEAL}" stroke="{BONE}" stroke-width="2" filter="url(#glowTeal)"/>')
    b.append(text(804, 761, "1,284", 22, TEAL, SANS, 900))
    # 右：衝擊穴位
    x, y, w, h = 1050, 124, 480, 644
    a = pts[n]
    k = fails.get(a["point_id"], 0)
    base = float(a["base_chance"])
    ch = min(1.0, base + float(cfg["chance_step"]) * k)
    b.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{INK}" stroke="#55505a" stroke-width="2"/>')
    b.append(f'<rect x="{x}" y="{y}" width="{w}" height="50" fill="#221d27"/>')
    b.append(text(x + w / 2, y + 34, "衝擊穴位", 24, BONE, SERIF, 900, "middle"))
    b.append(brush_title(x + 40, y + 122, a["name_zh"], 50, BONE, INK, 8, "start", -2))
    b.append(text(x + w - 40, y + 116, f"{m['name_zh']}・第 {n+1} 穴", 16, GREY, SANS, 900, "end"))
    b.append(f'<path d="M{x+40},{y+146} H{x+w-40}" stroke="#3b363f" stroke-width="2"/>')
    b.append(text(x + 40, y + 190, _stat_text(a["stat_id"], a["value"]).replace("+", "　+"), 24, TEAL, SANS, 900))
    b.append(text(x + 40, y + 250, "成功率", 17, GREY, SANS, 900))
    b.append(text(x + w - 40, y + 252, f"{int(round(ch*100))}%", 30, EMBER, SANS, 900, "end"))
    bx, bw = x + 40, w - 80
    b.append(f'<rect x="{bx}" y="{y+266}" width="{bw}" height="16" fill="#1b1418" stroke="{BONE}" stroke-width="1.5"/>')
    b.append(f'<rect x="{bx}" y="{y+266}" width="{bw*base:.0f}" height="16" fill="{TEAL}"/>')
    b.append(f'<rect x="{bx+bw*base:.0f}" y="{y+266}" width="{bw*(ch-base):.0f}" height="16" fill="{EMBER}"/>')
    b.append(text(x + 40, y + 310, f"基礎 {int(round(base*100))}%　＋　已衝擊 {k} 次 ×{int(float(cfg['chance_step'])*100)}%", 15, GREY, SANS, 700))
    b.append(text(x + 40, y + 334, "失敗會耗去真氣，但下次更容易打通", 15, GREY, SANS, 700))
    b.append(system_box(x + 40, y + 376, w - 80, 86, [f"{m['special_name']}　" + m['special_desc'].replace("{a}", m['special_a']).replace("{b}", m['special_b']), "全通一條經脈＝突破一個境界"], 16, tag=f"{m['name_zh']}全通", dark=True))
    b.append(text(x + w / 2, y + h - 136, f"{m['name_zh']}：{n} / {N}", 22, BONE, SERIF, 900, "middle"))
    b.append(pips(x + w / 2 - N * 11, y + h - 118, n, N, 12, TEAL, ()))
    b.append(button(x + 110, y + h - 96, 260, 54, "衝　擊", "hover", 26, "空白"))
    b.append(text(x + w / 2, y + h - 16, f"消耗真氣　{cost}", 18, BONE, SANS, 900, "middle"))
    # 下：八脈（各自的招式）
    for i, mid_ in enumerate(mer):
        nn = opened.get(mid_, 0)
        NN = len(meridian_points(mid_))
        cx = 150 + i * 186
        on = mid_ == sel
        b.append(slant(cx - 84, 812, 172, 74, 14, "#231019" if on else INK, EMBER if on else ("#2a8f93" if nn >= NN else "#55505a"), 3 if on else 2))
        b.append(pose_image(mid_, cx - 76, 815, 68, "silBone" if (on or nn) else "silGrey"))
        b.append(text(cx + 32, 846, mer[mid_]["name_zh"], 18, BONE if (on or nn) else GREY, SERIF, 900, "middle"))
        b.append(text(cx + 32, 870, f"{nn} / {NN}", 13, TEAL if nn >= NN else GREY, SANS, 900, "middle"))
    b.append(note(1180, 14, ["稿註：一脈一頁、一脈一式；A／D 或點下方切換。", "青亮點＝已通，橘點＋準框＝正要衝的穴，大珠＝該脈最後一穴。"]))
    return doc("\n".join(b), "12c 奇經八脈・一脈一式")


def s12d_meridian_poses():
    mer = _csv("meridians", "meridian_id")
    opened = _DEMO_OPEN
    b = [SIL_DEFS, f'<rect width="{W}" height="{H}" fill="{INK2}"/>']
    b.append(brush_title(800, 56, "八脈八式", 46, BONE, INK, 8, "middle", -1))
    for i, mid_ in enumerate(mer):
        cx, cy = 200 + (i % 4) * 400, 272 + (i // 4) * 412
        size = 340
        ox, oy = cx - size / 2, cy - size / 2
        pts = meridian_points(mid_)
        b.append(ink_disc(cx, cy + 6, 150, f"d{i}"))
        b.append(pose_image(mid_, ox, oy, size))
        P, V = point_layout(pts, ox, oy, size)
        b.append(star_nodes(P, opened.get(mid_, 0), -1, 0, 0.6, None, V))
        b.append(brush_title(cx - 180, cy - 160, mer[mid_]["name_zh"], 28, EMBER, INK, 6, "start", -2))
        b.append(text(cx + 184, cy - 164, f'{mer[mid_]["pose_zh"]}・{len(pts)} 穴', 16, BONE, SERIF, 900, "end"))
        b.append(text(cx, cy + 186, "　".join(r["name_zh"] for r in pts), 12.5, GREY, SERIF, 700, "middle"))
    return doc("\n".join(b), "12d 八脈八式")


def reticle(cx, cy, r, full=False):
    """弓的準星：只有一個紅圈，圈的大小＝箭的散射範圍；縮到最小＝滿蓄力。"""
    return f'<circle cx="{cx}" cy="{cy}" r="{r:.1f}" fill="none" stroke="{AIM_RED}" stroke-width="{3.5 if full else 2.5}" filter="url(#glowRed)"/>'


def spread_px(draw, aim, fov):
    cfg = {r["key"]: float(r["value"]) for r in _csv("combat_config") if r["key"].startswith("bow_")}
    deg = cfg["bow_spread_max_deg"] + (cfg["bow_spread_min_deg"] - cfg["bow_spread_max_deg"]) * draw
    if aim:
        deg *= cfg["bow_aim_spread_mult"]
    return math.tan(math.radians(deg)) / math.tan(math.radians(fov / 2)) * H / 2


def s13_bow_aim():
    b = []
    b.append(f'<image href="{asset("scene")}" x="-400" y="-225" width="{W*1.5}" height="{H*1.5}" preserveAspectRatio="xMidYMid slice"/>')
    b.append('<defs><radialGradient id="scope" cx="50%" cy="50%" r="60%"><stop offset=".45" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".9"/></radialGradient></defs>')
    b.append(f'<rect width="{W}" height="{H}" fill="url(#scope)"/>')
    b.append(f'<ellipse cx="800" cy="450" rx="1050" ry="760" fill="none" stroke="#000" stroke-width="760" opacity=".72"/>')
    b.append(f'<path d="M1010,900 Q1080,640 1000,440" fill="none" stroke="#5a3b28" stroke-width="16" stroke-linecap="round"/>')
    b.append(f'<path d="M1000,440 L950,690 L1010,900" fill="none" stroke="#eadbb9" stroke-width="2"/>')
    b.append(f'<path d="M950,690 L812,470" stroke="#d8c7a0" stroke-width="5"/>')
    b.append(f'<path d="M812,470 l-14,-6 l4,14 z" fill="{BONE}"/>')
    b.append(reticle(800, 450, spread_px(0.55, True, 48)))
    b.append(system_box(560, 760, 480, 46, ["右鍵 瞄準　｜　按住左鍵 拉弓・放開 射出"], 17, dark=True, align="middle"))
    b.append(f'<path d="M24,734 H540 L516,880 H24 Z" fill="{INK}" opacity=".78"/>')
    pclip = "M40,742 H176 L158,868 H40 Z"
    b.append(portrait("tang", 30, 736, 150, 150, pclip, cid="hudp2"))
    b.append(f'<path d="{pclip}" fill="none" stroke="{BONE}" stroke-width="4"/>')
    b.append(text(196, 772, "唐七", 26, BONE, SERIF, 900))
    b.append(f'<rect x="270" y="752" width="128" height="26" fill="{TEAL}"/>')
    b.append(text(334, 771, "一流・第三重", 15, INK, SANS, 900, "middle"))
    b.append(bar(192, 790, 360, 34, 0.81, label="117 / 144", cut=14))
    b.append(bar(192, 834, 340, 10, 1.0, "url(#tealFill)", segs=10, cut=6))
    b.append(text(530, 772, "真氣 284／262", 14, TEAL, SANS, 900, "end", f'stroke="{INK}" stroke-width="4" paint-order="stroke"'))
    b.append(coin(206, 866, 10))
    b.append(text(224, 872, "銀兩 236", 18, GOLD, SANS, 900, extra=f'stroke="{INK}" stroke-width="4" paint-order="stroke"'))
    b.append(f'<rect x="322" y="856" width="118" height="22" fill="{EMBER}"/>')
    b.append(text(381, 872, "可衝穴（K）", 14, INK, SANS, 900, "middle"))
    for i, (key, name, lv, kind) in enumerate([("主武器", "竹弓", 2, "bow"), ("副武器", "太刀", 1, "tachi")]):
        x, y = 1110 + i * 240, 770
        b.append(slant(x, y, 226, 104, 18, INK, BONE if i == 0 else "#55505a", 3, 'opacity=".9"'))
        b.append(weapon_icon(x + 74, y + 44, kind, 0.95, BONE))
        b.append(f'<rect x="{x+18}" y="{y-12}" width="64" height="24" fill="{BONE if i==0 else GREY}"/>')
        b.append(text(x + 50, y + 6, key, 14, INK, SANS, 900, "middle"))
        b.append(text(x + 210, y + 84, name, 20, BONE, SERIF, 900, "end"))
        b.append(text(x + 210, y + 32, f"淬煉+{lv}", 15, EMBER, SANS, 900, "end"))
    b.append(f'<rect x="1110" y="752" width="226" height="6" fill="{TEAL}" filter="url(#glowTeal)"/>')
    # 右上：紅圈三種狀態（實際大小）
    x0, y0 = 1150, 40
    b.append(slant(x0, y0, 420, 190, 18, INK, BONE, 2, 'opacity=".92"'))
    for i, (lab, d) in enumerate([("未拉弓", 0.0), ("拉弓一半", 0.5), ("滿弓", 1.0)]):
        cx = x0 + 86 + i * 128
        b.append(reticle(cx, y0 + 84, spread_px(d, True, 48), d >= 1))
        b.append(text(cx, y0 + 168, lab, 15, BONE, SANS, 900, "middle"))
    b.append(note(30, 40, ["稿註：準星只有一個紅圈，圈的範圍＝箭會落在的散射範圍；", "按住左鍵拉弓，紅圈逐漸收小，縮到最小＝滿蓄力（幾乎指哪射哪）。",
                           "右鍵瞄準：視角 80°→48°、散射減半、移動減速 40%。", "不瞄準也能拉弓射（腰射），紅圈在畫面上差不多大，但實際散射是兩倍。"]))
    return doc("\n".join(b), "13 弓・拉弓與瞄準")


# ---------------------------------------------------------------- 天機輪（悟道碑）
WHEEL_SECT_GLYPH = {"tianjian": "劍", "tianmo": "魔", "tangmen": "唐", "shaolin": "禪", "wudang": "太"}


def wheel_tile(x, y, w, h, sym, dim=False, hot=False):
    """轉輪上的一格符號。"""
    o = []
    op = .35 if dim else 1
    if sym in WHEEL_SECT_GLYPH:
        col = SECT_COL[sym]
        o.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{INK}" stroke="{col}" stroke-width="{4 if hot else 2.5}" opacity="{op}"/>')
        o.append(f'<rect x="{x+10}" y="{y+10}" width="{w-20}" height="{h-20}" fill="{col}" opacity="{.18*op:.2f}"/>')
        o.append(text(x + w / 2, y + h / 2 + h * .21, WHEEL_SECT_GLYPH[sym], h * .6, col, SERIF, 900, "middle", f'opacity="{op}"'))
    elif sym == "bagua":
        o.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{TEAL_D}" stroke="{TEAL}" stroke-width="{4 if hot else 3}" opacity="{op}" {"filter=\'url(#glowTeal)\'" if hot else ""}/>')
        cx, cy, r = x + w / 2, y + h / 2, h * .36
        pts = " ".join(f"{cx+math.cos(math.radians(22.5+45*i))*r:.1f},{cy+math.sin(math.radians(22.5+45*i))*r:.1f}" for i in range(8))
        o.append(f'<polygon points="{pts}" fill="none" stroke="{BONE}" stroke-width="2" opacity="{.6*op:.2f}"/>')
        o.append(text(cx, cy + h * .18, "卦", h * .5, BONE, SERIF, 900, "middle", f'opacity="{op}"'))
    elif sym == "wu":
        o.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#2a0f0a" stroke="{EMBER}" stroke-width="{4 if hot else 3}" opacity="{op}" {"filter=\'url(#glowRed)\'" if hot else ""}/>')
        o.append(brush_title(x + w / 2, y + h / 2 + h * .22, "悟", h * .6, EMBER, INK, max(3, h * .06), "middle", -4))
    else:
        o.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#141217" stroke="#3b363f" stroke-width="2" opacity="{op}"/>')
        o.append(text(x + w / 2, y + h / 2 + h * .16, "雲", h * .44, "#4d4853", SERIF, 900, "middle"))
    return "\n".join(o)


def s14_tianji_wheel():
    reels = [r["strip"].split("|") for r in _csv("wheel_reels")]
    res = json.load(open(os.path.join(ROOT, "docs/shrine-math/results.json"), encoding="utf-8"))
    P = res["P"]
    # 示意：中線 唐門、八卦、唐門 → 門派共鳴；第一軸上方一個悟
    win = [["wu", "tangmen", "cloud"], ["shaolin", "bagua", "tianjian"], ["wudang", "tangmen", "tianmo"]]
    b = []
    _dim_scene(b, 0.9)
    b.append(f'<circle cx="800" cy="430" r="430" fill="url(#tealBloom)" opacity=".35"/>')
    b.append(brush_title(800, 82, "悟道碑・天機輪", 62, BONE, INK, 9, "middle", -1))
    b.append(narration(470, 102, 660, 46, ["可參悟 2 次（含頓悟 0）　｜　持有 236 銀兩"], 18))
    # 石碑
    x0, y0, w0, h0 = 500, 176, 600, 470
    b.append(f'<path d="M{x0+30},{y0} H{x0+w0-30} L{x0+w0},{y0+30} V{y0+h0} H{x0} V{y0+30} Z" fill="#1a171d" stroke="{BONE}" stroke-width="4"/>')
    b.append(f'<path d="M{x0+18},{y0+12} H{x0+w0-18}" stroke="{BONE}" stroke-width="1" opacity=".4"/>')
    b.append(text(800, y0 + 38, "天　機　輪", 22, GREY, SERIF, 900, "middle"))
    tw, th, gap = 150, 112, 22
    rx0 = 800 - (3 * tw + 2 * gap) / 2
    ry0 = y0 + 62
    for i in range(3):
        rx = rx0 + i * (tw + gap)
        b.append(f'<rect x="{rx-6}" y="{ry0-6}" width="{tw+12}" height="{3*th+12}" fill="{INK}" stroke="#55505a" stroke-width="2"/>')
        for j in range(3):
            sym = win[i][j]
            hot = j == 1 and sym in ("tangmen", "bagua")
            b.append(wheel_tile(rx, ry0 + j * th + 4, tw, th - 8, sym, dim=(j != 1 and sym != "wu"), hot=hot or sym == "wu"))
    # 中線
    ly = ry0 + th * 1.5
    b.append(f'<rect x="{rx0-30}" y="{ly-th/2}" width="{3*tw+2*gap+60}" height="{th}" fill="none" stroke="{BLOOD}" stroke-width="4" filter="url(#glowRed)"/>')
    for sx, d in ((rx0 - 44, 1), (rx0 + 3 * tw + 2 * gap + 44, -1)):
        b.append(f'<path d="M{sx-d*16},{ly-18} L{sx+d*10},{ly} L{sx-d*16},{ly+18} Z" fill="{BLOOD}"/>')
    b.append(text(rx0 - 44, ly - 30, "中線", 15, BLOOD, SANS, 900, "middle"))
    # 結果
    b.append(f'<g>{burst(800, 700, 270, 56, 22, 0.25, BONE, INK, 5, 6)}</g>')
    b.append(brush_title(800, 716, "門派共鳴・唐門", 46, BLOOD, INK, 8, "middle", -2))
    b.append(text(800, 776, "三張候選皆出唐門武學，稀有度升一階", 18, BONE, SANS, 900, "middle", f'stroke="{INK}" stroke-width="5" paint-order="stroke"'))
    # 左：輪譜＋機率公示
    x, y, w, h = 40, 176, 420, 560
    b.append(slant(x, y, w, h, 22, INK, BONE, 3))
    b.append(text(x + 34, y + 44, "天機輪譜", 26, BONE, SERIF, 900))
    b.append(text(x + w - 30, y + 44, "每轉機率", 15, GREY, SANS, 900, "end"))
    rows = [(["tangmen", "tangmen", "bagua"], "門派共鳴", "三張候選皆出該門派，稀有度升一階", P["resonance"]),
            (["shaolin", "bagua", "cloud"], "門派感應", "前兩軸同門：一張候選保證是該門派", P["sense"]),
            (["bagua", "bagua", "bagua"], "八卦歸一", "一張必出絕世，其餘稀有度升一階", P["bagua"]),
            (["wu", "wu", "wu"], "頓悟", "任意位置 3 個悟：免費參悟 +3，可再觸發", res["p_trigger"])]
    for i, (syms, name, desc, pr) in enumerate(rows):
        yy = y + 74 + i * 112
        for k, sym in enumerate(syms):
            b.append(wheel_tile(x + 30 + k * 46, yy, 42, 40, sym))
        b.append(text(x + 186, yy + 26, name, 22, EMBER if name in ("八卦歸一", "頓悟") else BONE, SERIF, 900))
        b.append(text(x + w - 30, yy + 26, f"{pr*100:.2f}%", 20, TEAL, SANS, 900, "end"))
        b.append(text(x + 30, yy + 70, desc, 15, "#c9c2cb", SANS, 700))
    b.append(text(x + 30, y + h - 52, f"每次參悟平均轉 {res['spins_per_charge']:.3f} 次（含頓悟）", 14, GREY, SANS, 700))
    b.append(text(x + 30, y + h - 28, "八卦百搭任何門派；悟每軸最多出現一個", 14, GREY, SANS, 700))
    # 右：天機、頓悟
    x, y, w, h = 1140, 176, 420, 560
    b.append(slant(x, y, w, h, 22, INK, BONE, 3))
    b.append(text(x + 34, y + 44, "天機", 26, BONE, SERIF, 900))
    b.append(bar(x + 34, y + 70, w - 80, 16, 13 / 20, "url(#tealFill)", segs=20, cut=6))
    b.append(text(x + 34, y + 116, "13 / 20 未遇絕世　第 20 次必出", 15, GREY, SANS, 700))
    b.append(text(x + 34, y + 176, "頓悟", 26, EMBER, SERIF, 900))
    for k in range(3):
        b.append(wheel_tile(x + 34 + k * 64, y + 196, 56, 52, "wu", dim=k > 0))
    b.append(text(x + 34, y + 280, "剩餘免費參悟　1", 18, BONE, SANS, 900))
    b.append(text(x + 34, y + 340, "本次參悟", 20, BONE, SERIF, 900))
    log = [("第 1 轉", "頓悟　＋3"), ("第 2 轉", "門派感應・少林"), ("第 3 轉", "門派共鳴・唐門")]
    for i, (a, c) in enumerate(log):
        b.append(text(x + 34, y + 376 + i * 30, a, 15, GREY, SANS, 700))
        b.append(text(x + 120, y + 376 + i * 30, c, 16, TEAL if i == 2 else BONE, SANS, 900))
    b.append(button(470, 822, 220, 54, "參悟・轉輪", "hover", 22, "空白"))
    b.append(button(714, 822, 210, 54, "重轉（4 兩）", "normal", 20))
    b.append(button(948, 822, 200, 54, "離開悟道碑", "normal", 20))
    b.append(note(1200, 20, ["稿註：轉輪停下後顯示結果，0.8 秒後換成三選一卡片（沿用 04 稿）；", "左側機率由遊戲啟動時窮舉輪帶算出，與 tools/shrine_math 一致。"]))
    return doc("\n".join(b), "14 悟道碑・天機輪")


def slider_row(x, y, w, label, frac, value, hover=False):
    """設定頁的一列：左字、中間滑桿（斜切條＋菱形握把）、右數值。"""
    s = [text(x, y + 24, label, 24, EMBER if hover else BONE, SERIF, 900)]
    bx, bw = x + 200, w - 330
    s.append(bar(bx, y + 6, bw, 22, frac, "url(#tealFill)" if hover else "url(#bloodFill)", segs=10, cut=8))
    kx = bx + (bw - 8) * frac
    s.append(f'<path d="M{kx},{y-4} l12,21 l-12,21 l-12,-21 z" fill="{BONE}" stroke="{INK}" stroke-width="3"/>')
    s.append(text(x + w - 10, y + 26, value, 22, TEAL if hover else BONE, SANS, 900, "end"))
    return "\n".join(s)


def toggle_row(x, y, w, label, on):
    s = [text(x, y + 24, label, 24, BONE, SERIF, 900)]
    for i, (t, sel) in enumerate((("開", on), ("關", not on))):
        bx = x + 200 + i * 110
        s.append(slant(bx, y, 96, 38, 10, BLOOD if sel else INK, BONE, 2))
        s.append(text(bx + 48, y + 27, t, 20, BONE if sel else GREY, SERIF, 900, "middle"))
    return "\n".join(s)


def s15_settings():
    b = []
    _dim_scene(b, 0.7)
    b.append(speed_lines(330, 450, 300, 1200, 80, INK, 0.7, 61, 9))
    b.append(brush_title(330, 330, "設定", 150, BONE, INK, 14, "middle", -5))
    b.append(narration(110, 400, 440, 120, ["音量即時生效，", "設定會自動保存。"], 22))
    x, y, w = 640, 110, 880
    b.append(slant(x, y, w, 690, 30, INK, BONE, 3, 'opacity=".93"'))
    b.append(text(x + 50, y + 56, "聲音", 18, TEAL, SANS, 900))
    rows = [("主音量", 1.0, "100%"), ("音樂", 0.3, "30%"), ("音效", 0.5, "50%")]
    for i, (lab, fr, val) in enumerate(rows):
        b.append(slider_row(x + 60, y + 80 + i * 64, w - 120, lab, fr, val, hover=i == 1))
    b.append(text(x + 50, y + 300, "操作與畫面", 18, TEAL, SANS, 900))
    b.append(slider_row(x + 60, y + 324, w - 120, "滑鼠靈敏度", (1.0 - 0.3) / 2.2, "1.00×"))
    b.append(slider_row(x + 60, y + 388, w - 120, "畫面震動", 1.0, "100%"))
    b.append(toggle_row(x + 60, y + 452, w - 120, "頓幀", True))
    b.append(toggle_row(x + 60, y + 506, w - 120, "傷害跳字", True))
    b.append(toggle_row(x + 60, y + 560, w - 120, "全螢幕", False))
    b.append(button(x + w - 520, y + 620, 220, 54, "恢復預設", "normal", 22))
    b.append(button(x + w - 280, y + 620, 220, 54, "返回", "hover", 24, "Esc"))
    b.append(note(30, 820, ["稿註：主選單與暫停選單都有「設定」按鈕；滑桿可拖曳、滾輪或 ← → 微調，", "音樂預設 30%、音效預設 50%，數值與範圍讀 data/settings_config.csv。"]))
    return doc("\n".join(b), "15 設定")


def build(only=None):
    os.makedirs(OUT, exist_ok=True)
    screens = {k: v for k, v in globals().items() if k.startswith("s") and k[1:3].isdigit()}
    for name, fn in sorted(screens.items()):
        if only and name not in only:
            continue
        slug = {"s00": "00-style", "s01": "01-main-menu", "s02": "02-character-select", "s03": "03-hud",
                "s04": "04-shrine", "s05": "05-martial-panel", "s06": "06-pause", "s07": "07-result",
                "s08": "08-start-weapon", "s09": "09-drop-compare", "s10": "10-smith", "s11": "11-merchant", "s12c": "12c-meridian-pose", "s12d": "12d-meridian-poses", "s13": "13-bow-aim", "s14": "14-tianji-wheel", "s15": "15-settings"}[name.split("_")[0]]
        path = os.path.join(OUT, slug + ".svg")
        with open(path, "w", encoding="utf-8") as f:
            f.write(fn())
        print("wrote", os.path.relpath(path, ROOT), os.path.getsize(path) // 1024, "KB")


if __name__ == "__main__":
    import sys
    build(sys.argv[1:] or None)
