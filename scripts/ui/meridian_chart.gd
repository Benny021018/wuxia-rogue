extends Control
## 經脈圖：墨圓＋招式剪影＋穴位星圖（依 acupoints.csv 的 fx、fy、via 擺放）
## 版面對照 docs/ui-drafts/12c-meridian-pose.svg

signal point_selected(index: int)

const SIL_SHADER := preload("res://assets/ui/silhouette.gdshader")

var mid := "du"
var selected := 0
var points: Array = []          # acupoints 列（依深度）
var pos: Array = []             # 每個穴位在本 Control 內的座標
var vias: Array = []            # 每個穴位前面的轉折點
var labels: Array = []
var sil: TextureRect
var overlay: Control            # 連線與穴位畫在剪影上面
var pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	sil = TextureRect.new()
	sil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sil.stretch_mode = TextureRect.STRETCH_SCALE
	sil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SIL_SHADER
	mat.set_shader_parameter("rim_px", 5.0)
	sil.material = mat
	add_child(sil)
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)


static func silhouette(mid_: String, fill: Color, rim_px := 0.0) -> TextureRect:
	## 小圖示用的剪影（單色，無描邊）
	var t := TextureRect.new()
	t.texture = load("res://assets/ui/meridian/%s.webp" % mid_)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SIL_SHADER
	mat.set_shader_parameter("fill_color", fill)
	mat.set_shader_parameter("rim_px", rim_px)
	t.material = mat
	return t


func show_meridian(m: String) -> void:
	mid = m
	points = []
	for d in range(1, Data.meridian_len(mid) + 1):
		points.append(Data.acupoint(mid, d))
	selected = mini(Game.acu_level(mid), points.size() - 1)
	sil.texture = load("res://assets/ui/meridian/%s.webp" % mid)
	_layout()


func _layout() -> void:
	var s := size.x
	sil.position = Vector2.ZERO
	sil.size = Vector2(s, s)
	overlay.position = Vector2.ZERO
	overlay.size = Vector2(s, s)
	pos = []
	vias = []
	for r in points:
		pos.append(Vector2(float(r.fx), float(r.fy)) * s)
		var v: Array = []
		for part in String(r.get("via", "")).split(";", false):
			var xy := part.split(",")
			v.append(Vector2(float(xy[0]), float(xy[1])) * s)
		vias.append(v)
	for l in labels:
		l.queue_free()
	labels = []
	var n := Game.acu_level(mid)
	for i in points.size():
		var on := i < n
		var nxt := i == n
		var col := UIKit.TEAL if on else (UIKit.EMBER if nxt else UIKit.BONE)
		var l := UIKit.outlined(UIKit.label(String(points[i].name_zh), 16, col, HORIZONTAL_ALIGNMENT_LEFT, true), 5)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var side := 1.0 if i % 2 == 0 else -1.0
		var w := 90.0
		var off := 30.0 if i == selected else 18.0
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side > 0 else HORIZONTAL_ALIGNMENT_RIGHT
		l.position = pos[i] + Vector2(off if side > 0 else -off - w, -13)
		l.size = Vector2(w, 26)
		l.modulate.a = 1.0 if (on or nxt or i == selected) else 0.75
		add_child(l)
		labels.append(l)
	queue_redraw()
	overlay.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not points.is_empty():
		_layout()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		pulse += delta
		overlay.queue_redraw()


func _draw() -> void:
	var s := size.x
	var c := Vector2(s / 2.0, s / 2.0 + 10.0)
	var r := s * 0.437
	# 墨圓
	draw_circle(c, r * 1.22, Color(UIKit.TEAL, 0.05))
	var steps := 14
	for k in steps:
		var t := float(k) / float(steps - 1)
		draw_circle(c + Vector2(-r * 0.12, -r * 0.14) * t, r * (1.0 - 0.75 * t), Color("#0b2a2f").lerp(Color("#3a9ea5"), t))
	draw_arc(c, r, 0.0, TAU, 96, Color("#050406"), r * 0.12, true)


func _draw_overlay() -> void:
	if pos.is_empty():
		return
	var o := overlay
	var n := Game.acu_level(mid)
	# 連線（已通＝青色亮線）
	for i in range(points.size() - 1):
		var seg := PackedVector2Array([pos[i]])
		for v in vias[i + 1]:
			seg.append(v)
		seg.append(pos[i + 1])
		var lit := i + 1 < n
		if lit:
			o.draw_polyline(seg, Color(UIKit.TEAL, 0.35), 10.0, true)
		o.draw_polyline(seg, UIKit.TEAL if lit else Color(UIKit.BONE, 0.65), 3.5 if lit else 1.8, true)
	# 穴位：已通＝青色亮點；下一穴＝橘點（呼吸）；未通＝白圈；最後一穴是大珠
	for i in pos.size():
		var p: Vector2 = pos[i]
		var on := i < n
		var nxt := i == n
		var r := 13.0 if i == pos.size() - 1 else 8.5
		if on:
			o.draw_circle(p, r + 6.0, Color(UIKit.TEAL, 0.25))
			o.draw_circle(p, r, UIKit.TEAL)
			o.draw_arc(p, r, 0.0, TAU, 32, UIKit.BONE, 2.0, true)
			o.draw_circle(p, r * 0.38, UIKit.BONE)
		else:
			if nxt:
				var glow := 0.5 + 0.5 * sin(pulse * 4.0)
				o.draw_circle(p, r + 8.0 + glow * 4.0, Color(UIKit.EMBER, 0.18 + glow * 0.12))
			o.draw_circle(p, r, UIKit.INK)
			o.draw_arc(p, r, 0.0, TAU, 32, UIKit.EMBER if nxt else UIKit.BONE, 3.0 if nxt else 1.8, true)
			o.draw_circle(p, r * 0.36, UIKit.EMBER if nxt else UIKit.BONE)
			if i == pos.size() - 1 and not nxt:
				o.draw_arc(p, r * 0.55, PI, TAU, 12, Color(UIKit.BONE, 0.7), 1.5, true)
		if i == selected:   # 準框
			var R := r + 12.0
			o.draw_arc(p, R, 0.0, TAU, 40, UIKit.BONE, 2.0, true)
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				var q: Vector2 = p + d * R
				o.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -5), q + Vector2(5, 0), q + Vector2(0, 5), q + Vector2(-5, 0)]), UIKit.BONE)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var best := -1
		var bd := 26.0
		for i in pos.size():
			var d: float = pos[i].distance_to(event.position)
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			selected = best
			_layout()
			point_selected.emit(best)
			accept_event()
