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
