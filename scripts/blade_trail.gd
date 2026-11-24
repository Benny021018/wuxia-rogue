extends MeshInstance3D
## 刀光拖尾：每幀記錄刀身根部與刀尖的位置，連成一條隨時間淡出的光帶。
## 直接跟著動畫裡的刀走，所以換動作（含動作擷取的新動作）不用另外調特效。
## 數值在 data/feel_config.csv 的 blade_trail_*。

const SHADER := preload("res://scripts/blade_trail.gdshader")

var blades: Array = []          # 依序找第一把看得到的刀（拔出的刀、出鞘中的刀）
var ends := {}                  # blade -> [根部, 刀尖]（手骨的本地座標）
var skel_node: Skeleton3D
var bone := -1
var samples: Array = []         # [時間, 根部, 刀尖]；中斷時放 null 斷開光帶
var active_left := 0.0
var delay_left := 0.0
var clock := 0.0
var im := ImmediateMesh.new()
var mat := ShaderMaterial.new()


## 南宮的刀是蒙皮在手骨上的網格，節點本身不會動，所以刀身兩端換算成手骨座標，每幀用手骨姿勢還原。
func setup(blade_nodes: Array, skel: Skeleton3D, bone_name: String) -> void:
	skel_node = skel
	bone = skel.find_bone(bone_name)
	var to_skel := skel.global_transform.affine_inverse()
	var to_bone := skel.get_bone_global_rest(bone).affine_inverse()
	var hand_pos := skel.global_transform * skel.get_bone_global_rest(bone).origin
	top_level = true
	mesh = im
	mat.shader = SHADER
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for b in blade_nodes:
		if b is MeshInstance3D and b.mesh:
			blades.append(b)
			var e := _blade_ends(b, hand_pos)
			ends[b] = [to_bone * (to_skel * e[0]), to_bone * (to_skel * e[1])]


## 從網格包圍盒的最長軸找出刀身兩端（世界座標），離手近的那端當根部。
static func _blade_ends(b: MeshInstance3D, hand_pos: Vector3) -> Array:
	var box: AABB = b.mesh.get_aabb()
	var axis := 0
	for i in 3:
		if box.size[i] > box.size[axis]:
			axis = i
	var c := box.get_center()
	var a := c
	var z := c
	a[axis] = box.position[axis]
	z[axis] = box.end[axis]
	if (b.global_transform * a).distance_to(hand_pos) > (b.global_transform * z).distance_to(hand_pos):
		var tmp := a
		a = z
		z = tmp
	# 根部往刀尖退一點，光帶從刀身中段開始比較好看
	var g := b.global_transform
	return [g * a.lerp(z, float(Data.feel.blade_trail_root)), g * z]


## delay 秒後開始拖尾，持續 length 秒（真實時間）。
func swing(delay: float, length: float, tint: Color) -> void:
	delay_left = delay
	active_left = length
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("strength", float(Data.feel.blade_trail_alpha))
	mat.set_shader_parameter("glow", float(Data.feel.blade_trail_glow))
	samples.append(null)


func stop() -> void:
	active_left = 0.0
	delay_left = 0.0


func _process(delta: float) -> void:
	clock += delta
	var life := float(Data.feel.blade_trail_life_s)
	if delay_left > 0.0:
		delay_left -= delta
	elif active_left > 0.0:
		active_left -= delta
		var b = _visible_blade()
		if b:
			var e: Array = ends[b]
			var hand_t := skel_node.global_transform * skel_node.get_bone_global_pose(bone)
			samples.append([clock, hand_t * e[0], hand_t * e[1]])
		else:
			samples.append(null)
	while not samples.is_empty() and (samples[0] == null or clock - float(samples[0][0]) > life):
		samples.pop_front()
	_rebuild(life)


func _visible_blade():
	for b in blades:
		if is_instance_valid(b) and b.is_visible_in_tree():
			return b
	return null


## 用 Catmull-Rom 在取樣之間補點，快速揮砍時光帶才會是圓弧而不是折線。
func _rebuild(life: float) -> void:
	im.clear_surfaces()
	var runs: Array = []
	var run: Array = []
	for s in samples:
		if s == null:
			if run.size() > 1:
				runs.append(run)
			run = []
		else:
			run.append(s)
	if run.size() > 1:
		runs.append(run)
	if runs.is_empty():
		return
	var steps := maxi(1, int(Data.feel.blade_trail_steps))
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in runs:
		var pts: Array = []          # [age01, 根部, 刀尖]
		for i in r.size() - 1:
			var p0: Array = r[maxi(i - 1, 0)]
			var p1: Array = r[i]
			var p2: Array = r[i + 1]
			var p3: Array = r[mini(i + 2, r.size() - 1)]
			for k in steps:
				var u := float(k) / steps
				var t := lerpf(float(p1[0]), float(p2[0]), u)
				pts.append([clampf((clock - t) / life, 0.0, 1.0),
					_cr(p0[1], p1[1], p2[1], p3[1], u), _cr(p0[2], p1[2], p2[2], p3[2], u)])
		var last: Array = r[r.size() - 1]
		pts.append([clampf((clock - float(last[0])) / life, 0.0, 1.0), last[1], last[2]])
		for i in pts.size() - 1:
			var a: Array = pts[i]
			var b: Array = pts[i + 1]
			_quad(a[1], a[2], b[1], b[2], float(a[0]), float(b[0]))
	im.surface_end()


func _quad(r0: Vector3, t0: Vector3, r1: Vector3, t1: Vector3, age0: float, age1: float) -> void:
	for v in [[r0, Vector2(age0, 0)], [t0, Vector2(age0, 1)], [t1, Vector2(age1, 1)],
			[r0, Vector2(age0, 0)], [t1, Vector2(age1, 1)], [r1, Vector2(age1, 0)]]:
		im.surface_set_uv(v[1])
		im.surface_add_vertex(v[0])


static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (p2 - p0) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * u3)
