extends MultiMeshInstance3D
## 打擊粒子：一個 MultiMesh 畫全部粒子，自己算速度、重力、阻尼與淡出。
## 用遊戲時間（頓幀時跟著停住）。kind = "spark"（沿速度拉長的火花）、"ink"（受重力的血墨）、"dust"（上浮煙塵）

var vel: PackedVector3Array = []
var pos: PackedVector3Array = []
var life := 0.4
var t := 0.0
var gravity := Vector3.ZERO
var damping := 0.0
var color := Color.WHITE
var kind := "spark"
var size_m := 1.0
var sizes: PackedFloat32Array = []


func setup(at: Vector3, dir: Vector3, c: Color, amount: int, k: String, speed: float, s: float) -> void:
	kind = k
	color = c
	size_m = s
	var spread := 50.0
	match kind:
		"spark":
			life = 0.28
			gravity = Vector3(0, -6, 0)
			damping = 6.0
		"ink":
			life = 0.55
			gravity = Vector3(0, -14, 0)
			damping = 1.5
			spread = 65.0
		_:
			life = 0.6
			gravity = Vector3(0, 0.6, 0)
			damping = 2.5
			spread = 80.0
	var mesh: Mesh
	if kind == "spark":
		var b := BoxMesh.new()
		b.size = Vector3(0.022, 0.24, 0.022)
		mesh = b
	else:
		var q := QuadMesh.new()
		q.size = Vector2.ONE * (0.07 if kind == "ink" else 0.32)
		mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if kind != "spark":
		m.albedo_texture = _dot()
	mesh.surface_set_material(0, m)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = amount
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	global_position = Vector3.ZERO
	var d := dir.normalized() if not dir.is_zero_approx() else Vector3.UP
	var lo := 0.5 if kind == "spark" else (0.35 if kind == "ink" else 0.2)
	var hi := 1.0 if kind == "spark" else (0.8 if kind == "ink" else 0.5)
	for i in amount:
		var axis := d.cross(Vector3(randf() - .5, randf() - .5, randf() - .5)).normalized()
		if axis.is_zero_approx():
			axis = Vector3.RIGHT
		var v := d.rotated(axis, deg_to_rad(randf() * spread)) * speed * randf_range(lo, hi)
		vel.append(v)
		pos.append(at + v * 0.01)
		sizes.append(randf_range(0.6, 1.6) if kind != "spark" else randf_range(0.7, 1.3))
	_update(0.0)


static func _dot() -> GradientTexture2D:
	## 圓形柔邊點（血墨、煙塵用）
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.55, Color(1, 1, 1, 0.95))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	return tex


func _process(delta: float) -> void:
	t += delta
	if t >= life:
		queue_free()
		return
	_update(delta)


func _update(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var cam_basis: Basis = cam.global_basis if cam else Basis.IDENTITY
	var fade := 1.0 - t / life
	var k := exp(-damping * delta)
	for i in pos.size():
		vel[i] = vel[i] * k + gravity * delta
		pos[i] += vel[i] * delta
		var s := size_m * sizes[i]
		var b: Basis
		if kind == "spark":
			var y := vel[i].normalized() if vel[i].length() > 0.01 else Vector3.UP
			var view := (cam.global_position - pos[i]).normalized() if cam else Vector3.BACK
			var x := y.cross(view).normalized()
			if x.is_zero_approx():
				x = Vector3.RIGHT
			b = Basis(x, y, x.cross(y)).scaled(Vector3(s, s * clampf(vel[i].length() / 6.0, 0.4, 1.6), s))
		else:
			var grow := 1.0 + (1.0 - fade) * (1.2 if kind == "dust" else 0.0)
			b = cam_basis.scaled(Vector3.ONE * s * grow)
		multimesh.set_instance_transform(i, Transform3D(b, pos[i]))
		multimesh.set_instance_color(i, Color(color, color.a * (fade if kind != "spark" else fade * fade)))
