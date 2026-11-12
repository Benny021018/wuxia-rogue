class_name ComicSlider
extends Control
## 設定頁滑桿：斜切條＋菱形握把（docs/ui-drafts/15-settings.svg）。
## 可拖曳、滾輪、← → 微調；滑鼠移上或取得焦點時改成電光青。

signal value_changed(v: float)

var min_value := 0.0
var max_value := 1.0
var step := 0.05
var value := 0.0:
	set(v):
		v = clampf(snappedf(v, step), min_value, max_value)
		if not is_equal_approx(v, value):
			value = v
			queue_redraw()
			value_changed.emit(v)
var _hot := false
var _drag := false


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): _hot = true; queue_redraw())
	mouse_exited.connect(func(): _hot = false; queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	resized.connect(queue_redraw)


func ratio() -> float:
	return (value - min_value) / maxf(max_value - min_value, 0.0001)


func _set_from_x(x: float) -> void:
	var w := size.x - 8.0
	value = min_value + clampf(x / w, 0.0, 1.0) * (max_value - min_value)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			_drag = e.pressed
			if e.pressed:
				grab_focus()
				_set_from_x(e.position.x)
			accept_event()
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			value += step
			accept_event()
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			value -= step
			accept_event()
	elif e is InputEventMouseMotion and _drag:
		_set_from_x(e.position.x)
		accept_event()
	elif e.is_action_pressed("ui_left") or e.is_action_pressed("move_left"):
		value -= step
		accept_event()
	elif e.is_action_pressed("ui_right") or e.is_action_pressed("move_right"):
		value += step
		accept_event()


func _draw() -> void:
	var hot := _hot or has_focus()
	var h := 22.0
	var y0 := (size.y - h) / 2.0
	var w := size.x
	var k := 8.0
	var shape := PackedVector2Array([Vector2(0, y0), Vector2(w, y0), Vector2(w - k, y0 + h), Vector2(0, y0 + h)])
	var border := shape.duplicate()
	border.append(shape[0])
	draw_polyline(border, UIKit.INK, 7.0, true)
	draw_colored_polygon(shape, Color("#1b1418"))
	var a := UIKit.TEAL_D if hot else UIKit.BLOOD
	var b := UIKit.TEAL if hot else UIKit.EMBER
	var fx := (w - k) * ratio()
	if fx > 0.5:
		var top := minf(fx + k, w)
		draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(top, y0), Vector2(fx, y0 + h), Vector2(0, y0 + h)]),
			PackedColorArray([a, b, b, a]))
		draw_colored_polygon(PackedVector2Array([Vector2(0, y0), Vector2(top, y0), Vector2(top, y0 + h * 0.32), Vector2(0, y0 + h * 0.32)]), Color(1, 1, 1, 0.12))
	for i in range(1, 10):
		var sx := (w - k) * i / 10.0
		draw_line(Vector2(sx + k * 0.7, y0), Vector2(sx, y0 + h), UIKit.INK, 2.5)
	draw_polyline(border, UIKit.BONE, 2.0, true)
	var kx := (w - k) * ratio()
	var cy := size.y / 2.0
	var knob := PackedVector2Array([Vector2(kx, cy - 21), Vector2(kx + 12, cy), Vector2(kx, cy + 21), Vector2(kx - 12, cy)])
	draw_colored_polygon(knob, UIKit.BONE)
	knob.append(knob[0])
	draw_polyline(knob, UIKit.INK, 3.0, true)
