class_name UIKit
## 介面共用：條漫風配色、字型、主題與元件工廠（見 docs/ui-drafts/）

const INK := Color("#0b0a0d")       # 墨黑：底色
const INK2 := Color("#16131a")      # 次墨：面板
const VIOLET := Color("#2a1d36")    # 髮影紫：陰影、集中線
const BLOOD := Color("#b3121c")     # 血紅：生命、敵方、按鈕焦點
const EMBER := Color("#ff4a17")     # 橘紅：標題、強調、暴擊
const TEAL := Color("#16c6cc")      # 電光青：系統、修為、突破
const TEAL_D := Color("#0b5f66")
const BONE := Color("#f3ede4")      # 骨白：文字、框線
const GOLD := Color("#f2cf3a")      # 冷黃：銀兩
const GREY := Color("#8d8790")      # 次要文字
const PAPER := Color("#fbf8f3")     # 系統框底
const DIM := Color("#4a464e")       # 停用、空格
# 舊名稱（相容其他腳本）
const VERM := BLOOD
const JADE := TEAL
const MUTED := GREY

const SECT_COLORS := {"tianjian": Color("#6fd8e0"), "tianmo": Color("#e2343c"), "tangmen": Color("#9a5cf0"),
	"shaolin": Color("#e0a43a"), "wudang": Color("#cfd6dc"), "sanxue": Color("#8d8790")}
const LV_NAMES := ["", "入門", "熟練", "小成", "大成", "圓滿"]
const BASE := Vector2(1600, 900)    # 設計稿尺寸

static var _theme: Theme
## 只有用鍵盤／手把操作時才顯示焦點高亮；滑鼠操作時按鈕只在游標移上去才亮
static var kbd_nav := false
static var _serif: Font
static var _sans: Font
static var _ink_shader: Shader


# ------------------------------------------------------------------ 字型
static func serif() -> Font:
	## 標題、按鈕：粗襯線（隨遊戲附帶裁切後的 Noto Serif TC Black）
	if _serif == null:
		_serif = _font("res://assets/fonts/NotoSerifTC-Black.otf", ["Noto Serif CJK TC", "Noto Serif TC", "Source Han Serif TC", "DFKai-SB", "BiauKai", "PMingLiU", "serif"], 900)
	return _serif


static func sans() -> Font:
	## 內文、數值：粗黑體
	if _sans == null:
		_sans = _font("res://assets/fonts/NotoSansTC-Bold.otf", ["Noto Sans CJK TC", "Noto Sans TC", "Microsoft JhengHei", "PingFang TC", "sans-serif"], 700)
	return _sans


static func _font(path: String, names: Array, weight: int) -> Font:
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(names)
	sys.font_weight = weight
	if ResourceLoader.exists(path):
		var f: FontFile = load(path)
		f.fallbacks = [sys]
		return f
	return sys


# ------------------------------------------------------------------ 主題
static func theme() -> Theme:
	## 共用主題。CanvasLayer 會截斷主題繼承，所以各介面根節點要各自指定
	if _theme == null:
		_theme = make_theme()
	return _theme


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = sans()
	t.default_font_size = 20
	t.set_stylebox("panel", "PanelContainer", _flat(INK2, BONE, 3))
	t.set_stylebox("panel", "Panel", _flat(Color(INK, 0.82), BONE, 2))
	t.set_stylebox("normal", "Button", _button_style(INK, BONE, 3))
	t.set_stylebox("hover", "Button", _button_style(BLOOD, BONE, 3, true))
	t.set_stylebox("pressed", "Button", _button_style(BLOOD.darkened(0.25), BONE, 3, true))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", _button_style(Color("#1b1a1d"), Color("#4a474d"), 2))
	t.set_font("font", "Button", serif())
	t.set_color("font_color", "Button", BONE)
	t.set_color("font_hover_color", "Button", BONE)
	t.set_color("font_pressed_color", "Button", BONE)
	t.set_color("font_focus_color", "Button", BONE)
	t.set_color("font_disabled_color", "Button", Color("#5d5a60"))
	t.set_color("font_color", "Label", BONE)
	var tip := _flat(PAPER, INK, 3)
	tip.set_content_margin_all(12)
	tip.shadow_color = Color(TEAL, 0.6)
	tip.shadow_size = 4
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font("font", "TooltipLabel", sans())
	t.set_font_size("font_size", "TooltipLabel", 16)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 12)
	return t


static func _flat(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_content_margin_all(16)
	return s


static func _button_style(bg: Color, border: Color, width: int, glow := false) -> StyleBoxFlat:
	## 斜切按鈕：StyleBoxFlat 的 skew 做出刀切分格的平行四邊形
	var s := _flat(bg, border, width)
	s.skew = Vector2(0.28, 0)
	s.set_content_margin_all(10)
	s.anti_aliasing = true
	if glow:
		s.shadow_color = Color(EMBER, 0.55)
		s.shadow_size = 12
	return s


# ------------------------------------------------------------------ 擺放
static func place(c: Control, ax: float, ay: float, x: float, y: float, w: float, h: float) -> void:
	## 以錨點＋偏移量擺放（ax, ay 為 0~1 的錨點；x, y, w, h 為相對錨點的像素）
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + w
	c.offset_bottom = y + h


static func at(parent: Control, c: Control, x: float, y: float, w: float, h: float, ax := 0.5, ay := 0.5) -> Control:
	## 用設計稿（1600×900）上的座標擺放，貼齊指定錨點；畫面變寬時跟著錨點走
	place(c, ax, ay, x - BASE.x * ax, y - BASE.y * ay, w, h)
	parent.add_child(c)
	return c


static func overlay(alpha := 0.75, color := INK) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(color, alpha)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c


static func center_box(parent: Control, width := 0.0) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(cc)
	var v := VBoxContainer.new()
	if width > 0.0:
		v.custom_minimum_size.x = width
	cc.add_child(v)
	return v


# ------------------------------------------------------------------ 文字
static func label(text: String, size := 20, color := BONE, align := HORIZONTAL_ALIGNMENT_LEFT, use_serif := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", serif() if use_serif else sans())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func outlined(l: Label, width := 4, color := INK) -> Label:
	l.add_theme_constant_override("outline_size", width)
	l.add_theme_color_override("font_outline_color", color)
	return l


static func title(text: String, size := 64, color := BONE, stroke := 10, white_rim := false, rot := 0.0, align := HORIZONTAL_ALIGNMENT_CENTER) -> Control:
	## 狀聲詞標題：極粗襯線＋黑描邊（＋骨白外框），可傾斜
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layers: Array = []
	if white_rim:
		layers.append([BONE, stroke + 12, Color(BONE, 1)])
	layers.append([INK, stroke, color])
	for spec in layers:
		var l := label(text, size, spec[2], align, true)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		outlined(l, spec[1], spec[0])
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(l)
	root.rotation_degrees = rot
	root.resized.connect(func(): root.pivot_offset = root.size / 2.0)
	return root


static func set_title(t: Control, text: String, color = null) -> void:
	var labels: Array = t.get_children()
	for l in labels:
		l.text = text
	if color != null:
		labels[-1].add_theme_color_override("font_color", color)


# ------------------------------------------------------------------ 元件
static func button(text: String, cb: Callable, size := 24, w := 240.0, h := 56.0, key_hint := "") -> Button:
	var b := ComicButton.new()
	b.text = text
	b.key_hint = key_hint
	b.add_theme_font_size_override("font_size", size)
	if cb.is_valid():
		b.pressed.connect(cb)
	b.custom_minimum_size = Vector2(w, h)
	return b


static func box(kind := "narration", tag := "", pad := 16) -> ComicBox:
	var b := ComicBox.new()
	b.kind = kind
	b.tag = tag
	b.set_padding(pad)
	return b


static func box_text(kind: String, text: String, size := 20, tag := "", align := HORIZONTAL_ALIGNMENT_CENTER) -> ComicBox:
	## 旁白框／系統框＋一段文字（旁白用襯線、系統用黑體）
	var b := box(kind, tag)
	var narr := kind == "narration"
	var col := INK if kind == "system" else BONE
	var l := label(text, size, col, align, narr)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(l)
	b.set_meta("label", l)
	return b


static func bar(fill_a: Color, fill_b: Color, segs := 0, cut := 12.0) -> ComicBar:
	var b := ComicBar.new()
	b.fill_a = fill_a
	b.fill_b = fill_b
	b.segments = segs
	b.cut = cut
	return b


static func hp_bar() -> ComicBar:
	return bar(Color("#6e0a10"), EMBER, 0, 14.0)


static func seal(text: String, color := BLOOD, size := 26, rot := -4.0) -> ComicSeal:
	var s := ComicSeal.new()
	s.text = text
	s.color = color
	s.font_size = size
	s.rotation_degrees = rot
	return s


static func fx() -> ComicFX:
	var f := ComicFX.new()
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return f


static func pips(level: int, total := 5, size := 12.0, on := EMBER) -> ComicFX:
	## 武學／淬煉等級刻點；小成（3）、圓滿（5）畫成菱形
	var f := ComicFX.new()
	f.custom_minimum_size = Vector2(total * (size + 8), size + 4)
	f.add_pips(Vector2(size * 0.6, size * 0.6 + 2), level, total, size, on)
	return f


# ------------------------------------------------------------------ 圖像
static func portrait(cid: String, minimum_size: Vector2) -> TextureRect:
	var frame := TextureRect.new()
	frame.texture = load("res://assets/portraits/%s.webp" % cid)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame.custom_minimum_size = minimum_size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return frame


static func portrait_crop(cid: String, aspect: float, face_frac: float, face_pos := 0.45) -> Texture2D:
	## 依 characters.csv 的臉部位置（portrait_x／portrait_y＝臉中心、portrait_face＝臉高，皆為 0~1）裁出指定比例。
	## face_frac：臉高佔裁切高度的比例；face_pos：臉中心在裁切框內的垂直位置。
	var tex: Texture2D = load("res://assets/portraits/%s.webp" % cid)
	var row: Dictionary = Data.characters.get(cid, {})
	if tex == null or String(row.get("portrait_face", "")) == "":
		return tex
	var size := Vector2(tex.get_width(), tex.get_height())
	var center := Vector2(float(row.portrait_x), float(row.portrait_y)) * size
	var h := float(row.portrait_face) * size.y / face_frac
	var w := h * aspect
	if w > size.x:
		w = size.x
		h = w / aspect
	if h > size.y:
		h = size.y
		w = h * aspect
	var x := clampf(center.x - w / 2.0, 0.0, size.x - w)
	var y := clampf(center.y - h * face_pos, 0.0, size.y - h)
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(x, y, w, h)
	return atlas


static func clipped(tex: Texture2D, poly: PackedVector2Array, border := BONE, border_w := 4.0, inked := false) -> Control:
	## 多邊形裁切圖片（斜切立繪）；inked＝壓成墨色雙色調
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var clip := ComicFX.new()
	clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip.add_poly(poly, Color.WHITE)
	clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	root.add_child(clip)
	var img := TextureRect.new()
	img.texture = tex
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if inked:
		img.material = ink_material()
		img.modulate = Color(0.75, 0.73, 0.78)
	clip.add_child(img)
	if border_w > 0.0:
		var edge := ComicFX.new()
		edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		edge.add_outline(poly, border, border_w)
		root.add_child(edge)
	return root


static func ink_material(dark := Color("#050407"), light := Color("#6f6a76")) -> ShaderMaterial:
	## 墨色雙色調：未選角色、主選單背景
	if _ink_shader == null:
		_ink_shader = load("res://assets/ui/ink_tone.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _ink_shader
	m.set_shader_parameter("dark", dark)
	m.set_shader_parameter("light", light)
	return m


static func bloom(color := TEAL, alpha := 0.9) -> TextureRect:
	## 電光青背光（徑向漸層）
	var g := Gradient.new()
	g.set_color(0, Color(color, alpha))
	g.set_color(1, Color(color.darkened(0.6), 0.0))
	g.add_point(0.45, Color(color.darkened(0.45), alpha * 0.7))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func vignette(strength := 0.85) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, strength))
	g.add_point(0.62, Color(0, 0, 0, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 0.5)
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func backdrop(path: String, inked := true) -> TextureRect:
	var bg := TextureRect.new()
	bg.texture = load(path)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if inked:
		bg.material = ink_material(Color("#040405"), Color("#7c8a8c"))
	return bg


static func rarity_color(rarity: String) -> Color:
	return Data.rarity_color(rarity)


## 切換「鍵盤操作中」狀態，並刷新目前焦點按鈕的外觀
static func set_kbd_nav(on: bool, vp: Viewport) -> void:
	if kbd_nav == on:
		return
	kbd_nav = on
	var f := vp.gui_get_focus_owner() if vp else null
	if f and f.has_method("_on_focus"):
		f._on_focus(true)
	elif f:
		f.queue_redraw()
