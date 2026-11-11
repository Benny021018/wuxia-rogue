class_name UIKit
## 介面共用：水墨配色的主題、按鈕與文字工廠

const INK := Color(0.09, 0.085, 0.08)
const PAPER := Color(0.93, 0.89, 0.8)
const VERM := Color(0.75, 0.22, 0.16)
const JADE := Color(0.25, 0.62, 0.5)
const GOLD := Color(0.85, 0.7, 0.4)
const MUTED := Color(0.7, 0.66, 0.58)


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = FX.font()
	t.default_font_size = 20
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.08, 0.075, 0.07, 0.92)
	panel.border_color = GOLD.darkened(0.3)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(16)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.16, 0.14, 0.12)
	btn.border_color = GOLD.darkened(0.4)
	btn.set_border_width_all(2)
	btn.set_corner_radius_all(4)
	btn.set_content_margin_all(10)
	var hover: StyleBoxFlat = btn.duplicate()
	hover.bg_color = VERM.darkened(0.25)
	hover.border_color = GOLD
	var disabled: StyleBoxFlat = btn.duplicate()
	disabled.bg_color = Color(0.12, 0.12, 0.12)
	disabled.border_color = Color(0.3, 0.3, 0.3)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", hover)
	t.set_stylebox("focus", "Button", hover)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", PAPER)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.5))
	t.set_color("font_color", "Label", PAPER)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.13, 0.12, 0.9)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = VERM
	fill.set_corner_radius_all(3)
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 12)
	return t


static func label(text: String, size := 20, color := PAPER, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func portrait(cid: String, minimum_size: Vector2) -> TextureRect:
	var frame := TextureRect.new()
	frame.texture = load("res://assets/portraits/%s.webp" % cid)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame.custom_minimum_size = minimum_size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return frame


static func button(text: String, cb: Callable, size := 22) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(cb)
	b.custom_minimum_size = Vector2(220, 52)
	return b


static func bar(color: Color, h := 18.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, h)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	p.add_theme_stylebox_override("fill", fill)
	return p


static func overlay(alpha := 0.75) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0, 0, 0, alpha)
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


## 以錨點＋偏移量擺放（ax, ay 為 0~1 的錨點；x, y, w, h 為相對錨點的像素）
static func place(c: Control, ax: float, ay: float, x: float, y: float, w: float, h: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + w
	c.offset_bottom = y + h
