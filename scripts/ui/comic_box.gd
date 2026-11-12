class_name ComicBox
extends MarginContainer
## 條漫框：narration（旁白黑框）、system（系統白框）、system_dark（暗版系統框）、
## slant（斜切面板）、slant_red（血紅斜切標籤）、chip（小標籤）

var kind := "narration":
	set(v):
		kind = v
		queue_redraw()
var tag := "":
	set(v):
		tag = v
		queue_redraw()
var accent := UIKit.TEAL:
	set(v):
		accent = v
		queue_redraw()
var fill := Color(0, 0, 0, 0):        # 不為透明時覆蓋預設底色
	set(v):
		fill = v
		queue_redraw()
var border := Color(0, 0, 0, 0):
	set(v):
		border = v
		queue_redraw()
var slant := 18.0
var glow := false:
	set(v):
		glow = v
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func set_padding(pad: int, horizontal := -1) -> void:
	var h := pad if horizontal < 0 else horizontal
	add_theme_constant_override("margin_left", h)
	add_theme_constant_override("margin_right", h)
	add_theme_constant_override("margin_top", pad)
	add_theme_constant_override("margin_bottom", pad)


func _draw() -> void:
	var w := size.x
	var h := size.y
	match kind:
		"narration":
			draw_rect(Rect2(Vector2.ZERO, size), _or(fill, Color(UIKit.INK, 0.96)))
			draw_rect(Rect2(Vector2.ZERO, size), _or(border, UIKit.BONE), false, 3.0)
			draw_rect(Rect2(Vector2(6, 6), size - Vector2(12, 12)), Color(_or(border, UIKit.BONE), 0.55), false, 1.0)
		"system", "system_dark":
			var dark := kind == "system_dark"
			var c := 10.0
			var pts := PackedVector2Array([Vector2(c, 0), Vector2(w - c, 0), Vector2(w, c), Vector2(w, h - c),
				Vector2(w - c, h), Vector2(c, h), Vector2(0, h - c), Vector2(0, c)])
			draw_colored_polygon(pts, _or(fill, Color(UIKit.INK2, 0.9) if dark else UIKit.PAPER))
			_outline(pts, _or(border, accent if dark else UIKit.INK), 3.5)
			var b := 14.0
			for corner in [[Vector2(-5, -5), Vector2(1, 1)], [Vector2(w + 5, -5), Vector2(-1, 1)],
					[Vector2(-5, h + 5), Vector2(1, -1)], [Vector2(w + 5, h + 5), Vector2(-1, -1)]]:
				var p: Vector2 = corner[0]
				var d: Vector2 = corner[1]
				draw_polyline(PackedVector2Array([p + Vector2(0, d.y * b), p, p + Vector2(d.x * b, 0)]), accent, 3.0)
			if tag != "":
				var f := UIKit.sans()
				var fs := 15
				var tw := f.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_rect(Rect2(14, -13, tw + 18, fs + 9), accent if dark else UIKit.INK)
				draw_string(f, Vector2(23, -13 + fs + 1), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIKit.INK if dark else accent)
		"slant", "slant_red":
			var k := slant
			var pts := PackedVector2Array([Vector2(k, 0), Vector2(w, 0), Vector2(w - k, h), Vector2(0, h)])
			var bg := _or(fill, UIKit.BLOOD if kind == "slant_red" else Color(UIKit.INK, 0.9))
			if glow:
				for i in 4:
					var grow := 3.0 + i * 4.0
					var g := PackedVector2Array([Vector2(k - grow, -grow), Vector2(w + grow, -grow), Vector2(w - k + grow, h + grow), Vector2(-grow, h + grow)])
					draw_colored_polygon(g, Color(UIKit.EMBER, 0.14 - i * 0.03))
			draw_colored_polygon(pts, bg)
			_outline(pts, _or(border, UIKit.BONE), 3.0 if kind == "slant" else 2.0)
		"chip":
			draw_rect(Rect2(Vector2.ZERO, size), _or(fill, Color(UIKit.INK, 0.85)))
			draw_rect(Rect2(Vector2.ZERO, size), _or(border, UIKit.DIM), false, 2.0)


func _outline(pts: PackedVector2Array, color: Color, width: float) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	closed.append(pts[1])
	draw_polyline(closed, color, width, true)


func _or(c: Color, fallback: Color) -> Color:
	return fallback if c.a == 0.0 else c
