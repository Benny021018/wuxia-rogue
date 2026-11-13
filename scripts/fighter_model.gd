extends Node3D
## 第三人稱角色模型：Quaternius 通用假人（CC0）＋UAL1／UAL2 動作，右手掛兵器。
## 動作名稱直接用動作庫裡的名字；*_Loop 與待機類動作會循環。

const UAL1 := preload("res://assets/models/character/UAL1.glb")
const UAL2 := preload("res://assets/models/character/UAL2.glb")
const WEAPONS := {"W001": preload("res://assets/models/weapons/Tachi.glb"),
	"W007": preload("res://assets/models/weapons/W007.glb"), "W301": preload("res://assets/models/weapons/W301.glb")}
const LOOPS := ["Sword_Idle", "Idle_Loop"]
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
var current := ""


func setup(char_id: String, weapon_id: String) -> void:
	var body := UAL1.instantiate()
	add_child(body)
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
	for n in anim.get_animation_list():
		var a := anim.get_animation(n)
		a.loop_mode = Animation.LOOP_LINEAR if String(n).ends_with("_Loop") or String(n) in LOOPS else Animation.LOOP_NONE
	var mesh: MeshInstance3D = body.find_children("*", "MeshInstance3D", true, false)[0]
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
	play("Sword_Idle")


func has(n: String) -> bool:
	return anim != null and anim.has_animation(n)


## 播放動作；同一個循環動作重複呼叫不會重播
func play(n: String, speed := 1.0, from := 0.0, blend := 0.12, force := false) -> void:
	if not has(n):
		return
	if n == current and not force and anim.is_playing():
		anim.speed_scale = speed
		return
	current = n
	anim.play(n, blend, speed)
	if from > 0.0:
		anim.seek(from, true)


## 停在某個動作的某一格（倒地、浮空的姿勢）
func hold(n: String, at: float) -> void:
	if not has(n):
		return
	if current != n + "@hold":
		current = n + "@hold"
		anim.play(n, 0.0)
	anim.seek(minf(at, anim.get_animation(n).length - 0.01), true)
	anim.pause()
