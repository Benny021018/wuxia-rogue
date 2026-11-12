class_name ComicSeal
extends Control
## 朱印：稀有度、門派、標記。印面邊緣略為不規則，像手蓋的印。

var text := "":
	set(v):
		text = v
		_fit()
var color := UIKit.BLOOD:
	set(v):
		color = v
		queue_redraw()
var font_size := 26:
	set(v):
		font_size = v
		_fit()
var ink := UIKit.BONE
var _edge := PackedVector2Array()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _fit() -> void:
	var n := text.length()
	var w := font_size * (1.25 if n <= 1 else 1.02 * n + 0.32)
	custom_minimum_size = Vector2(w, font_size * 1.4)
	size = custom_minimum_size
	pivot_offset = size / 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(text)
	_edge = PackedVector2Array()
	var steps := 6
	for side in 4:
		for i in steps:
			var t := i / float(steps)
			var p: Vector2
			match side:
				0: p = Vector2(w * t, 0)
				1: p = Vector2(w, size.y * t)
				2: p = Vector2(w * (1.0 - t), size.y)
				_: p = Vector2(0, size.y * (1.0 - t))
			_edge.append(p + Vector2(rng.randf_range(-1.6, 1.6), rng.randf_range(-1.6, 1.6)))
	queue_redraw()


func _draw() -> void:
	if _edge.is_empty():
		return
	draw_colored_polygon(_edge, color)
	draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), Color(ink, 0.8), false, 1.5)
	var f := UIKit.serif()
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(f, Vector2((size.x - tw) / 2.0, size.y / 2.0 + font_size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
