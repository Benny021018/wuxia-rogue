class_name ComicFX
extends Control
## 條漫繪製層：集中線、刀光、吶喊爆框、血點、火星、多邊形、刻點、括弧。
## 以 add_* 累積繪製指令，座標為本節點的區域座標。

var _ops: Array = []
var drift := 0.0                      # 火星往上飄的速度（像素／秒）；0＝靜止
var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func clear() -> void:
	_ops.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if drift > 0.0 and is_visible_in_tree():
		_t += delta
		queue_redraw()


func add_poly(pts: PackedVector2Array, color: Color) -> ComicFX:
	_ops.append(["poly", pts, color])
	queue_redraw()
	return self


func add_outline(pts: PackedVector2Array, color: Color, width := 3.0) -> ComicFX:
	var closed := pts.duplicate()
	closed.append(pts[0])
	closed.append(pts[1])
	_ops.append(["line", closed, color, width])
	queue_redraw()
	return self


func add_line(pts: PackedVector2Array, color: Color, width := 3.0) -> ComicFX:
	_ops.append(["line", pts, color, width])
	queue_redraw()
	return self


func add_speed_lines(center: Vector2, r0: float, r1: float, n: int, color: Color, seed_value := 3, width := 1.0) -> ComicFX:
	## 集中線：從外往中心收細的三角
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in n:
		var a := rng.randf() * TAU
		var spread := rng.randf_range(0.004, 0.012) * width
		var inner := rng.randf_range(r0, r0 * 1.5)
		_ops.append(["poly", PackedVector2Array([center + Vector2.from_angle(a - spread) * r1,
			center + Vector2.from_angle(a + spread) * r1, center + Vector2.from_angle(a) * inner]), color])
	queue_redraw()
	return self


func add_slash(p0: Vector2, p1: Vector2, width := 26.0, glow := true) -> ComicFX:
	## 刀光：白刃新月形，外帶青光
	var d := p1 - p0
	var n := Vector2(d.y, -d.x).normalized()
	var pts := PackedVector2Array()
	var steps := 24
	for i in steps + 1:
		var t := i / float(steps)
		pts.append(p0 + d * t + n * sin(t * PI) * width)
	for i in range(steps, -1, -1):
		var t := i / float(steps)
		pts.append(p0 + d * t + n * sin(t * PI) * width * 0.35)
	if glow:
		for g in 4:
			var halo := PackedVector2Array()
			for i in steps + 1:
				var t := i / float(steps)
				halo.append(p0 + d * t + n * sin(t * PI) * (width + 6 + g * 7))
			for i in range(steps, -1, -1):
				var t := i / float(steps)
				halo.append(p0 + d * t - n * (6 + g * 7) * sin(t * PI))
			_ops.append(["poly", halo, Color(UIKit.TEAL, 0.12 - g * 0.025)])
	_ops.append(["poly", pts, Color.WHITE])
	queue_redraw()
	return self


func add_burst(center: Vector2, rx: float, ry: float, n := 22, jag := 0.28, fill := UIKit.BONE, stroke := UIKit.INK, stroke_w := 6.0, seed_value := 1) -> ComicFX:
	## 吶喊泡泡：鋸齒爆框
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pts := PackedVector2Array()
	for i in n * 2:
		var a := TAU * i / float(n * 2)
		var k := 1.0 if i % 2 == 0 else 1.0 - jag * (0.7 + 0.6 * rng.randf())
		pts.append(center + Vector2(cos(a) * rx * k, sin(a) * ry * k))
	_ops.append(["poly", pts, fill])
	add_outline(pts, stroke, stroke_w)
	return self


func add_splatter(center: Vector2, spread: float, n: int, color := UIKit.BLOOD, seed_value := 5, big := 10.0) -> ComicFX:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in n:
		var a := rng.randf() * TAU
		var d := absf(rng.randfn(0.0, spread))
		var r := maxf(0.8, big * exp(-d / spread * 1.6) * rng.randf_range(0.3, 1.0))
		_ops.append(["circle", center + Vector2.from_angle(a) * d, r, color])
	queue_redraw()
	return self


func add_embers(rect: Rect2, n: int, color := UIKit.EMBER, seed_value := 9) -> ComicFX:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in n:
		_ops.append(["ember", Vector2(rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y)),
			rng.randf_range(2.0, 7.0), rng.randf_range(-1.0, 1.0), rng.randf_range(0.4, 1.0), rect, color])
	queue_redraw()
	return self


func add_pips(origin: Vector2, level: int, total := 5, size_px := 12.0, on := UIKit.EMBER, marks := [3, 5]) -> ComicFX:
	## 等級刻點：方點，關鍵等級為菱形
	for i in total:
		var c := origin + Vector2(i * (size_px + 8), 0)
		var lv := i + 1
		var col := on if lv <= level else Color("#2e2a31")
		if lv in marks:
			var r := size_px * 0.62
			var dia := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
			_ops.append(["poly", dia, col])
			add_outline(dia, UIKit.BONE if lv <= level else Color("#555"), 1.5)
		else:
			var s := size_px * 0.8
			_ops.append(["rect", Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), col])
	queue_redraw()
	return self


func add_brackets(rect: Rect2, color := UIKit.TEAL, length := 14.0, width := 3.0, offset := 5.0) -> ComicFX:
	## 系統框外角括弧
	var r := rect.grow(offset)
	for corner in [[r.position, Vector2(1, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 1)],
			[Vector2(r.position.x, r.end.y), Vector2(1, -1)], [r.end, Vector2(-1, -1)]]:
		var p: Vector2 = corner[0]
		var d: Vector2 = corner[1]
		add_line(PackedVector2Array([p + Vector2(0, d.y * length), p, p + Vector2(d.x * length, 0)]), color, width)
	return self


const WEAPON_SHAPES := {"刀": "tachi", "弓": "bow", "弩": "bow", "巨劍": "sword", "劍": "sword"}


func add_weapon_icon(center: Vector2, weapon_class: String, scale := 1.0, color := UIKit.BONE) -> ComicFX:
	## 武器剪影（依 weapons.csv 的 class）：刀、弓、劍類各一種簡單幾何
	var kind: String = WEAPON_SHAPES.get(weapon_class, "sword")
	if kind == "bow":
		var arc := PackedVector2Array()
		for i in 13:
			var t := i / 12.0
			arc.append(center + Vector2(-8 + sin(t * PI) * 40, -44 + t * 88) * scale)
		add_line(arc, color, 5.0 * scale)
		add_line(PackedVector2Array([center + Vector2(-8, -44) * scale, center + Vector2(-8, 44) * scale]), color, 1.5 * scale)
		add_line(PackedVector2Array([center + Vector2(-30, 0) * scale, center + Vector2(36, 0) * scale]), color, 2.5 * scale)
		add_line(PackedVector2Array([center + Vector2(28, -6) * scale, center + Vector2(36, 0) * scale, center + Vector2(28, 6) * scale]), color, 2.5 * scale)
		return self
	var ang := -0.5
	var polys: Array = []
	if kind == "tachi":
		polys = [[Vector2(-46, 4), Vector2(0, -6), Vector2(50, -14), Vector2(54, -12), Vector2(4, 0), Vector2(-44, 8)],
			[Vector2(-62, 2), Vector2(-46, 2), Vector2(-46, 8), Vector2(-62, 8)], [Vector2(-47, -4), Vector2(-42, -4), Vector2(-42, 14), Vector2(-47, 14)]]
	else:
		ang = -0.6
		polys = [[Vector2(-40, -7), Vector2(52, -7), Vector2(60, 0), Vector2(52, 7), Vector2(-40, 7)],
			[Vector2(-48, -14), Vector2(-40, -14), Vector2(-40, 14), Vector2(-48, 14)], [Vector2(-66, -4), Vector2(-48, -4), Vector2(-48, 4), Vector2(-66, 4)]]
	for poly in polys:
		var out := PackedVector2Array()
		for p in poly:
			out.append(center + (p as Vector2).rotated(ang) * 0.95 * scale)
		_ops.append(["poly", out, color])
	queue_redraw()
	return self


func add_gear_icon(center: Vector2, slot: String, scale := 1.0, color := UIKit.BONE) -> ComicFX:
	## 配件剪影（docs/ui-drafts/10-smith.svg）：護符＝摺紙符、腰牌＝圓角牌、玉珮＝環形玉
	var c := center
	var s := scale
	match slot:
		"charm":
			add_outline(PackedVector2Array([c + Vector2(-22, -34) * s, c + Vector2(22, -34) * s, c + Vector2(22, 30) * s, c + Vector2(0, 40) * s, c + Vector2(-22, 30) * s]), color, 4.0 * s)
			add_line(PackedVector2Array([c + Vector2(-10, -20) * s, c + Vector2(10, -20) * s]), UIKit.BLOOD, 4.0 * s)
			add_line(PackedVector2Array([c + Vector2(0, -26) * s, c + Vector2(0, 20) * s]), UIKit.BLOOD, 4.0 * s)
			add_line(PackedVector2Array([c + Vector2(-12, 4) * s, c + Vector2(12, 4) * s]), UIKit.BLOOD, 4.0 * s)
		"token":
			add_line(PackedVector2Array([c + Vector2(0, -44) * s, c + Vector2(0, -34) * s]), color, 3.0 * s)
			var plate := PackedVector2Array()
			for i in 24:
				var a := TAU * i / 24.0
				var q := Vector2(cos(a), sin(a))
				plate.append(c + Vector2(signf(q.x) * 12.0 + q.x * 12.0, signf(q.y) * 21.0 + q.y * 12.0) * s + Vector2(0, -1) * s)
			add_outline(plate, color, 4.0 * s)
			for k in 3:
				var yy := -14.0 + k * 14.0
				add_line(PackedVector2Array([c + Vector2(-12, yy) * s, c + Vector2(12 if k < 2 else 6, yy) * s]), UIKit.GOLD, 4.0 * s)
		_:
			add_line(PackedVector2Array([c + Vector2(0, -44) * s, c + Vector2(0, -30) * s]), color, 3.0 * s)
			for r in [[30.0, 10.0, Color(UIKit.TEAL, 0.85)], [30.0, 2.0, color], [12.0, 2.0, color]]:
				var ring := PackedVector2Array()
				for i in 41:
					ring.append(c + Vector2.from_angle(TAU * i / 40.0) * float(r[0]) * s)
				add_line(ring, r[2], float(r[1]) * s)
			add_line(PackedVector2Array([c + Vector2(0, 30) * s, c + Vector2(0, 46) * s]), UIKit.BLOOD, 3.0 * s)
			add_line(PackedVector2Array([c + Vector2(-6, 46) * s, c + Vector2(0, 58) * s, c + Vector2(6, 46) * s]), UIKit.BLOOD, 3.0 * s)
	queue_redraw()
	return self


func _draw() -> void:
	for op in _ops:
		match op[0]:
			"poly":
				draw_colored_polygon(op[1], op[2])
			"line":
				draw_polyline(op[1], op[2], op[3], true)
			"circle":
				draw_circle(op[1], op[2], op[3])
			"rect":
				draw_rect(op[1], op[2])
			"ember":
				var p: Vector2 = op[1]
				var area: Rect2 = op[5]
				if drift > 0.0:
					p.y = area.position.y + fposmod(p.y - area.position.y - _t * drift * (0.6 + op[4]), area.size.y)
					p.x += sin(_t * 1.3 + op[3] * 6.0) * 6.0
				var s: float = op[2]
				var col: Color = op[6]
				draw_set_transform(p, op[3], Vector2.ONE)
				draw_rect(Rect2(-s, -s * 0.22, s * 2.0, s * 0.45), Color(col, 0.18 * op[4]))
				draw_rect(Rect2(-s / 2.0, -s * 0.11, s, s * 0.22), Color(col.lightened(0.2), op[4]))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
