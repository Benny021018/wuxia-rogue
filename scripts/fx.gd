class_name FX
## 共用的灰盒視覺工具：材質、浮動傷害數字、範圍預警圈

const COMBAT_FRAMES := preload("res://assets/effects/combat.tres")

static var _font: SystemFont


static func font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Microsoft JhengHei", "Microsoft YaHei", "Noto Sans TC", "Noto Sans CJK TC", "PingFang TC", "sans-serif"])
	return _font


static func mat(color: Color, emission := 0.0, transparent := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	if transparent or color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func box(size: Vector3, color: Color, emission := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat(color, emission)
	return mi


static func cylinder(radius: float, height: float, color: Color, emission := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	mi.mesh = c
	mi.material_override = mat(color, emission)
	return mi


static func sphere(radius: float, color: Color, emission := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	mi.mesh = s
	mi.material_override = mat(color, emission)
	return mi


static func label3d(text: String, size := 48, color := Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font()
	l.font_size = size
	l.modulate = color
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.006
	return l


static func float_text(parent: Node, pos: Vector3, text: String, color := Color.WHITE, size := 40) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var l := label3d(text, size, color)
	parent.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.2, randf_range(-0.3, 0.3))
	var t := l.create_tween()
	t.set_parallel(true)
	t.tween_property(l, "global_position", l.global_position + Vector3(0, 1.2, 0), 0.8)
	t.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	t.chain().tween_callback(l.queue_free)


## 地面預警圈：duration 秒後消失
static func warn_circle(parent: Node, pos: Vector3, radius: float, duration: float, color := Color(0.85, 0.15, 0.1, 0.35)) -> Node3D:
	var marker := Node3D.new()
	parent.add_child(marker)
	marker.global_position = Vector3(pos.x, 0.06, pos.z)
	var rim := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = radius * 0.94
	ring.outer_radius = radius
	rim.mesh = ring
	rim.scale.y = 0.15
	rim.material_override = mat(Color(color, 0.9), 1.2, true)
	marker.add_child(rim)
	var fill := cylinder(radius, 0.025, color, 0.5)
	marker.add_child(fill)
	fill.scale = Vector3(0.02, 1, 0.02)
	var t := marker.create_tween()
	t.tween_property(fill, "scale", Vector3.ONE, duration)
	t.tween_callback(marker.queue_free)
	return marker


## 非循環影格播畢自行釋放；毒霧與火焰跟隨傷害區的生命週期。
static func play(parent: Node3D, pos: Vector3, clip: StringName, span: float, duration: float, tint := Color.WHITE, flip := false) -> AnimatedSprite3D:
	var sprite := AnimatedSprite3D.new()
	sprite.sprite_frames = COMBAT_FRAMES
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	sprite.flip_h = flip
	sprite.modulate = tint
	var frame := COMBAT_FRAMES.get_frame_texture(clip, 0)
	sprite.pixel_size = span / maxf(frame.get_width(), frame.get_height())
	parent.add_child(sprite)
	sprite.global_position = pos
	if not COMBAT_FRAMES.get_animation_loop(clip):
		sprite.animation_finished.connect(sprite.queue_free)
	var speed := COMBAT_FRAMES.get_frame_count(clip) / (duration * COMBAT_FRAMES.get_animation_speed(clip))
	sprite.play(clip, speed)
	return sprite

## 水平刀光：外緣落在傷害半徑上；直刺的兩道細痕沿判定寬度收束到圓弧前端。
static func attack_trail(parent: Node3D, center: Vector3, forward: Vector3, reach: float, degrees: float, half_width: float, tint: Color, duration: float) -> MeshInstance3D:
	var path := PackedVector3Array()
	var inner := PackedVector3Array()
	var angle := deg_to_rad(degrees * 0.5) if degrees > 0 else asin(minf(1,half_width/reach))
	var steps := maxi(8,ceili(angle * 24))
	for i in steps + 1:
		var a := lerpf(-angle,angle,float(i)/steps)
		var ray := Vector3(sin(a),0,-cos(a))
		path.append(ray * reach)
		var taper := sin(PI*float(i)/steps)
		inner.append(ray * reach * (.94 - .15*taper))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_trail_band(tool,path,inner,tint)
	if degrees > 0 and degrees < 360:
		# A dark echo follows only the middle of the sweep, leaving its tips sharp.
		var ink_outer := PackedVector3Array()
		var ink_inner := PackedVector3Array()
		for j in range(steps/5,steps*4/5+1):
			ink_outer.append(inner[j]*.985)
			ink_inner.append(inner[j]*(.975-.025*sin(PI*j/steps)))
		_trail_band(tool,ink_outer,ink_inner,Color("#343754"))
	if degrees <= 0:
		for idx in [0,steps]:
			var end := path[idx]
			var start := Vector3(end.x,0,end.z*.58)
			_trail_band(tool,PackedVector3Array([start,end]),PackedVector3Array([Vector3(start.x*.99,0,start.z),Vector3(end.x*.90,0,end.z)]),tint)
	var m := MeshInstance3D.new()
	m.mesh = tool.commit()
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material_override = material
	parent.add_child(m)
	m.global_position = center
	var heading := Vector3(forward.x,0,forward.z)
	if not heading.is_zero_approx():
		m.global_basis = Basis.looking_at(heading.normalized())
	m.scale = Vector3(.84,1,.84)
	var tween := m.create_tween().set_parallel(true)
	tween.tween_property(m,"scale",Vector3.ONE,duration*.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(material,"albedo_color:a",0.0,duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(m.queue_free)
	return m


static func _trail_band(tool: SurfaceTool, outer: PackedVector3Array, inner: PackedVector3Array, tint: Color) -> void:
	for i in range(outer.size()-1):
		for k in [0,1,2,2,1,3]:
			var j: int = i + (k >> 1)
			var edge: bool = (k & 1) == 0
			tool.set_color(Color(tint, .92 if edge else .025))
			tool.add_vertex(outer[j] if edge else inner[j])


static func impact_wave(parent: Node3D, center: Vector3, radius: float, duration: float, color: Color) -> void:
	attack_trail(parent,center+Vector3.UP*.09,Vector3.FORWARD,radius,360,0,color,duration)
	play(parent,center+Vector3.UP*.35,&"ground-slam",radius*.95,duration,color)
