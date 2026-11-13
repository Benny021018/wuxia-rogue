extends Control
## 天機輪的一軸：依 pos（中線所在的輪帶位置，可為小數）畫出上中下三格；轉動時 pos 連續增加
## 符號外觀對照 docs/ui-drafts/14-tianji-wheel.svg

const GLYPH_SECT := {"tianjian": "劍", "tianmo": "魔", "tangmen": "唐", "shaolin": "禪", "wudang": "太"}

var strip: PackedStringArray = []
var pos := 0.0
var tile_h := 112.0
var stopped := true
var hot_mid := false        # 中線這格是否參與連線
var flash := 0.0


func setup(s: PackedStringArray, start: int, h: float) -> void:
	strip = s
	pos = float(start)
	tile_h = h
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func symbol_at(k: int) -> String:
	var n := strip.size()
	return strip[((k % n) + n) % n]


var _tick := -1


func _process(_delta: float) -> void:
	if not stopped or flash > 0.0:
		queue_redraw()
	var k := int(floor(pos))
	if not stopped and k != _tick and is_visible_in_tree():
		Sfx.play("wheel_tick")
	_tick = k


func _draw() -> void:
	if strip.is_empty():
		return
	var mid_y := size.y / 2.0
	var base := int(floor(pos))
	var frac := pos - float(base)
	for k in range(-2, 3):
		var y := mid_y + (float(k) - frac) * tile_h - tile_h / 2.0
		var sym := symbol_at(base + k)
		var is_mid := stopped and k == 0 and frac < 0.001
		var dim := stopped and not is_mid and sym != "wu"
		draw_tile(self, Rect2(4, y + 4, size.x - 8, tile_h - 8), sym, is_mid and hot_mid, dim, not stopped)


static func draw_tile(c: CanvasItem, r: Rect2, sym: String, hot := false, dim := false, blur := false) -> void:
	var a := 0.35 if dim else 1.0
	var font: Font = UIKit.serif()
	var glyph := "雲"
	var fg := Color("#4d4853")
	var fill := Color("#141217")
	var border := Color("#3b363f")
	var bw := 2.0
	if GLYPH_SECT.has(sym):
		glyph = GLYPH_SECT[sym]
		fg = UIKit.SECT_COLORS[sym]
		fill = UIKit.INK
		border = fg
		bw = 4.0 if hot else 2.5
	elif sym == "bagua":
		glyph = "卦"
		fg = UIKit.BONE
		fill = UIKit.TEAL_D
		border = UIKit.TEAL
		bw = 4.0 if hot else 3.0
	elif sym == "wu":
		glyph = "悟"
		fg = UIKit.EMBER
		fill = Color("#2a0f0a")
		border = UIKit.EMBER
		bw = 4.0 if hot else 3.0
	if hot or sym == "wu" and not dim:
		c.draw_rect(r.grow(6.0), Color(border, 0.22 * a))
	c.draw_rect(r, Color(fill, a))
	if GLYPH_SECT.has(sym):
		c.draw_rect(r.grow(-10.0), Color(fg, 0.16 * a))
	if sym == "bagua":
		var cen := r.get_center()
		var rad := r.size.y * 0.36
		var pts := PackedVector2Array()
		for i in 9:
			pts.append(cen + Vector2.from_angle(deg_to_rad(22.5 + 45.0 * i)) * rad)
		c.draw_polyline(pts, Color(UIKit.BONE, 0.6 * a), 2.0, true)
	c.draw_rect(r, Color(border, a), false, bw)
	var fs := int(r.size.y * (0.5 if sym == "bagua" else 0.6))
	var ts := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var p := r.get_center() + Vector2(-ts.x / 2.0, fs * 0.36)
	if sym == "wu":
		for d in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3)]:
			c.draw_string(font, p + d, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UIKit.INK, a))
	c.draw_string(font, p, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(fg, a * (0.6 if blur else 1.0)))
