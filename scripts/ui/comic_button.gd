class_name ComicButton
extends Button
## 斜切按鈕：外觀來自主題（StyleBoxFlat skew）；游標或焦點時加青色括弧，可附按鍵提示

var key_hint := ""
var selected := false:          # 開／關這類二選一：選中的那顆常駐血紅底
	set(v):
		selected = v
		_on_focus(has_focus())


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))


func _on_focus(on: bool) -> void:
	## 鍵盤焦點與游標同樣顯示血紅底
	if on or selected:
		add_theme_stylebox_override("normal", get_theme_stylebox("hover"))
	else:
		remove_theme_stylebox_override("normal")
	add_theme_color_override("font_color", UIKit.GREY if has_meta("toggle") and not selected and not on else UIKit.BONE)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var hot := not disabled and (is_hovered() or has_focus())
	if hot:
		var c := UIKit.TEAL
		draw_polyline(PackedVector2Array([Vector2(-4, h * 0.3), Vector2(-4, -8), Vector2(34, -8)]), c, 3.0)
		draw_polyline(PackedVector2Array([Vector2(w + 4, h * 0.7), Vector2(w + 4, h + 8), Vector2(w - 34, h + 8)]), c, 3.0)
	if key_hint != "":
		var f := UIKit.sans()
		var fs := 12
		var tw := f.get_string_size(key_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12
		var r := Rect2(w - tw - 18, h - 18, tw, 16)
		draw_rect(r, UIKit.TEAL if not disabled else UIKit.DIM)
		draw_string(f, Vector2(r.position.x + 6, r.end.y - 3), key_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UIKit.INK)
