class_name ComicBar
extends Control
## 粗黑邊斜尾條：生命、修為、首領、天機

var value := 0.0:
	set(v):
		if v != value:
			value = v
			queue_redraw()
var max_value := 1.0:
	set(v):
		if v != max_value:
			max_value = v
			queue_redraw()
var fill_a := UIKit.BLOOD
var fill_b := UIKit.EMBER
var segments := 0
var cut := 12.0
var text := "":
	set(v):
		if v != text:
			text = v
			queue_redraw()
var font_size := 19
var overlay := 0.0:                  # 護盾等疊加量（同一個 max_value）
	set(v):
		if v != overlay:
			overlay = v
			queue_redraw()
var overlay_color := UIKit.GOLD
var marker := -1.0                    # 0~1 的刻度（例：軟保底起點）


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func ratio() -> float:
	return clampf(value / maxf(max_value, 0.0001), 0.0, 1.0)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var k := minf(cut, h)
	var shape := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w - k, h), Vector2(0, h)])
	var border := shape.duplicate()
	border.append(shape[0])
	draw_polyline(border, UIKit.INK, 7.0 if h > 14 else 5.0, true)
	draw_colored_polygon(shape, Color("#1b1418"))
	var fx := (w - k) * ratio()
	if fx > 0.5:
		var top := minf(fx + k, w)
		var fill := PackedVector2Array([Vector2(0, 0), Vector2(top, 0), Vector2(fx, h), Vector2(0, h)])
		var mid := fill_a.lerp(fill_b, 0.6)
		draw_polygon(fill, PackedColorArray([fill_a, fill_b, fill_b, fill_a.lerp(mid, 0.3)]))
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(top, 0), Vector2(top - k * 0.32, h * 0.32), Vector2(0, h * 0.32)]), Color(1, 1, 1, 0.13))
		var x := 6.0
		while x + h * 0.58 < top and h > 12:   # 斜紋
			draw_line(Vector2(x, h), Vector2(x + h * 0.58, 0), Color(1, 1, 1, 0.05), 3.0)
			x += 10.0
	if overlay > 0.0:
		var ow := (w - k) * clampf(overlay / maxf(max_value, 0.0001), 0.0, 1.0)
		draw_line(Vector2(0, -3), Vector2(ow, -3), overlay_color, 5.0)
	for i in range(1, segments):
		var sx := (w - k) * i / float(segments)
		draw_line(Vector2(sx + k * 0.7, 0), Vector2(sx, h), UIKit.INK, 2.5)
	if marker >= 0.0:
		var mx := (w - k) * marker + k * 0.5
		draw_line(Vector2(mx, -4), Vector2(mx, h + 4), UIKit.EMBER, 3.0)
	draw_polyline(border, UIKit.BONE, 2.0, true)
	if text != "":
		var f := UIKit.sans()
		var y := h / 2.0 + font_size * 0.36
		draw_string_outline(f, Vector2(14, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, UIKit.INK)
		draw_string(f, Vector2(14, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UIKit.BONE)
