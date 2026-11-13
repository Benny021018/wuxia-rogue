extends Node3D
## 第三人稱角色模型：Quaternius 通用假人（CC0）＋UAL1／UAL2 動作，右手掛兵器。
## 動作名稱直接用動作庫裡的名字；*_Loop 與待機類動作會循環。

const UAL1 := preload("res://assets/models/character/UAL1.glb")
const UAL2 := preload("res://assets/models/character/UAL2.glb")
const WEAPONS := {"W001": preload("res://assets/models/weapons/Tachi.glb"),
	"W007": preload("res://assets/models/weapons/W007.glb"), "W301": preload("res://assets/models/weapons/W301.glb")}
const LOOPS := ["Sword_Idle"]
# 兵器在右手骨頭上的擺放（位置、歐拉角、縮放）；用 tests/UICapture 對照調整
const GRIP := {"W001": [Vector3(0, 0.09, 0.03), Vector3(0, 180, 0), 1.0],
	"W301": [Vector3(0, 0.09, 0.03), Vector3(0, 180, 0), 1.0],
	"W007": [Vector3(0, 0.09, 0.03), Vector3(0, 180, 90), 1.0]}
const SHEATHS := ["Saya", "Scabbard"]       # 第三人稱先不顯示刀鞘
const TINT := {"nangong": [Color("#e9e6df"), Color("#1f8f99")], "han": [Color("#3a2c30"), Color("#c8262e")], "tang": [Color("#3c3350"), Color("#9a5cf0")]}

var anim: AnimationPlayer
var skeleton: Skeleton3D
var hand: BoneAttachment3D
var weapon: Node3D
var body_meshes: Array[Node] = []
var status_material := ShaderMaterial.new()
var flash_left := 0.0
var armored := false
var invincible := false
var current := ""
var motion_pivot := Node3D.new()
var idle := "Sword_Idle"


func setup(char_id: String, weapon_id: String) -> void:
	var body := UAL1.instantiate()
	add_child(motion_pivot)
	motion_pivot.add_child(body)
	body.rotation.y = PI          # 模型朝 +Z，轉成朝 -Z（Godot 的前方）
	anim = body.find_children("*", "AnimationPlayer", true, false)[0]
	skeleton = body.find_children("*", "Skeleton3D", true, false)[0]
	var extra := UAL2.instantiate()
	var ap2: AnimationPlayer = extra.find_children("*", "AnimationPlayer", true, false)[0]
	var lib: AnimationLibrary = anim.get_animation_library(&"")
	for n in ap2.get_animation_list():
		if not lib.has_animation(n):
			lib.add_animation(n, ap2.get_animation(n))
	extra.free()
	# Godot 匯入時會把名稱結尾的 _Loop 去掉並設成循環；這裡只補上沒標記但要循環的待機動作
	for n in LOOPS:
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	# 產生獨立招式片段，保留原庫供通用移動及受擊共用。
	for id in Data.char_moves[char_id].values():
		var move: Dictionary = Data.moves[id]
		if move.has("motion") and not lib.has_animation(id):
			lib.add_animation(id, _compose(move))
	body_meshes = body.find_children("*", "MeshInstance3D", true, false)
	status_material.shader = preload("res://scripts/fighter_status.gdshader")
	var mesh: MeshInstance3D = body_meshes[0]
	var tint: Array = TINT.get(char_id, TINT.nangong)
	for i in mesh.mesh.get_surface_count():
		var m := StandardMaterial3D.new()
		m.albedo_color = tint[mini(i, 1)]
		m.roughness = 0.75
		mesh.set_surface_override_material(i, m)
	hand = BoneAttachment3D.new()
	skeleton.add_child(hand)
	hand.bone_name = "hand_r"
	if WEAPONS.has(weapon_id):
		weapon = WEAPONS[weapon_id].instantiate()
		hand.add_child(weapon)
		var g: Array = GRIP[weapon_id]
		weapon.position = g[0]
		weapon.rotation_degrees = g[1]
		weapon.scale = Vector3.ONE * float(g[2])
		for n in SHEATHS:
			var sh := weapon.find_child(n, true, false)
			if sh:
				sh.visible = false
		for ap in weapon.find_children("*", "AnimationPlayer", true, false):
			ap.stop()
	elif weapon_id == "W006":
		weapon = flying_blade()
		hand.add_child(weapon)
		weapon.rotation_degrees.x = 75
		idle = "Crouch_Idle_Loop"
	play(idle)


func set_defense(armor: bool, immune: bool) -> void:
	if armored == armor and invincible == immune:
		return
	armored = armor
	invincible = immune
	status_material.set_shader_parameter("armored", armor)
	status_material.set_shader_parameter("invincible", immune)
	_refresh_overlay()


func flash_hit() -> void:
	flash_left = float(Data.feel.flash_hold_s) + float(Data.feel.flash_fade_s)
	status_material.set_shader_parameter("flash", 1.0)
	_refresh_overlay()


func _process(delta: float) -> void:
	if flash_left > 0:
		flash_left = maxf(0.0, flash_left - delta)
		status_material.set_shader_parameter("flash", minf(1.0, flash_left / float(Data.feel.flash_fade_s)))
		if flash_left == 0:
			_refresh_overlay()


func _refresh_overlay() -> void:
	for mesh in body_meshes:
		mesh.material_overlay = status_material if armored or invincible or flash_left > 0 else null


## 雙脊柳葉刃，掌中與飛行中的模型共用，刃尖朝 -Z。
static func flying_blade() -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim := [Vector3(0,0,-0.31), Vector3(.046,0,-.07), Vector3(0,0,.12), Vector3(-.046,0,-.07)]
	for side in [-1, 1]:
		for i in rim.size():
			tool.add_vertex(Vector3(0, .018 * side, -.065))
			tool.add_vertex(rim[i])
			tool.add_vertex(rim[(i + side + rim.size()) % rim.size()])
	tool.generate_normals()
	var blade := MeshInstance3D.new()
	blade.mesh = tool.commit()
	var metal := FX.mat(Color("#c2a5e5"), .65)
	metal.cull_mode = BaseMaterial3D.CULL_DISABLED
	blade.material_override = metal
	return blade


## 逐段取樣 UAL 的預備、伸展、收勢。每個有效判定時間正好落在伸展姿勢。
func _compose(move: Dictionary) -> Animation:
	var m: Dictionary = move.motion
	var source: Animation = anim.get_animation(clip(m.source))
	var result := Animation.new()
	result.length = float(move.duration_s)
	var beats: Array[float] = []
	for h in move.hits:
		if float(h.time_s) > 0:
			beats.append(float(h.time_s))
	if beats.is_empty():
		beats.append(result.length * .5)
	var times: Array[float] = [0.0]
	var phases: Array[float] = [0.0]
	var dash_cut := String(m.dash_windup) != ""
	if dash_cut:
		times.append(float(move.lunge_from_s))
		phases.append(float(m.dash_windup))
	for i in beats.size():
		if i > 0:
			times.append(lerpf(beats[i-1], beats[i], .48))
			phases.append(.20)
		times.append(beats[i])
		phases.append(float(m.extension))
	if dash_cut:
		times.append(float(move.lunge_to_s))
		phases.append(float(m.dash_follow))
	times.append(result.length)
	phases.append(1.0)
	for track in source.get_track_count():
		var type := source.track_get_type(track)
		if type not in [Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var out := result.add_track(type)
		var path := source.track_get_path(track)
		result.track_set_path(out, path)
		var bone := String(path.get_concatenated_subnames())
		for k in range(1, times.size()):
			var frames := maxi(1, ceili((times[k] - times[k-1]) * 30))
			for j in range(0 if k == 1 else 1, frames + 1):
				var f := float(j) / frames
				var at := lerpf(times[k-1], times[k], f)
				var phase := lerpf(phases[k-1], phases[k], f if dash_cut else smoothstep(0, 1, f))
				var src := phase * source.length
				var pose := sin(phase * PI) * (2 * phase - .45)
				match type:
					Animation.TYPE_ROTATION_3D:
						var q := source.rotation_track_interpolate(track, src)
						if bone == "spine_02":
							q *= Quaternion(Vector3.UP, deg_to_rad(float(m.spine_deg)) * pose)
						elif bone == "hand_r":
							q *= Quaternion(Vector3.FORWARD, deg_to_rad(float(m.wrist_deg)) * pose)
						result.rotation_track_insert_key(out, at, q.normalized())
					Animation.TYPE_POSITION_3D:
						var pos := source.position_track_interpolate(track, src)
						result.position_track_insert_key(out, at, pos)
					Animation.TYPE_SCALE_3D:
						result.scale_track_insert_key(out, at, source.scale_track_interpolate(track, src))
	# 在世界直立軸旋轉；骨盆本地軸會隨原片姿勢傾斜。
	var pivot_path := anim.get_node(anim.root_node).get_path_to(motion_pivot)
	for prop in ["rotation:y", "position:y"]:
		var out := result.add_track(Animation.TYPE_VALUE)
		result.track_set_path(out, NodePath("%s:%s" % [pivot_path, prop]))
		for i in 31:
			var f := float(i) / 30
			var value := TAU * float(m.turns) * f if prop == "rotation:y" else float(m.lift_m) * sin(PI * f)
			result.track_insert_key(out, result.length * f, value)
	return result


## 動作庫原名（含 _Loop）或匯入後的名稱都可以
func clip(n: String) -> String:
	if anim == null:
		return ""
	if anim.has_animation(n):
		return n
	var short := n.trim_suffix("_Loop")
	return short if anim.has_animation(short) else ""


func has(n: String) -> bool:
	return clip(n) != ""


## 播放動作；同一個循環動作重複呼叫不會重播
func play(n: String, speed := 1.0, from := 0.0, blend := 0.12, force := false) -> void:
	n = clip(n)
	if n == "":
		return
	if n == current and not force and anim.is_playing():
		anim.speed_scale = speed
		return
	motion_pivot.transform = Transform3D.IDENTITY
	current = n
	anim.play(n, blend, speed)
	if from > 0.0:
		anim.seek(from, true)


## 停在某個動作的某一格（倒地、浮空的姿勢）
func hold(n: String, at: float) -> void:
	n = clip(n)
	if n == "":
		return
	if current != n + "@hold":
		motion_pivot.transform = Transform3D.IDENTITY
		current = n + "@hold"
		anim.play(n, 0.0)
	anim.seek(minf(at, anim.get_animation(n).length - 0.01), true)
	anim.pause()
