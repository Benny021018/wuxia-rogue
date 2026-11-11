extends Node3D
## 持續傷害區：毒池、毒霧、屍氣領域、火盆等
## hurts_player = true 時傷害玩家；否則傷害敵人（目前未用）

var radius := 2.0
var dps := 5.0
var duration := 3.0          # <= 0 表示永久
var hurts_player := true
var _t := 0.0
var _tick := 0.0
var _mesh: MeshInstance3D


func configure(r: float, damage_per_sec: float, dur: float, to_player := true, color := Color(0.35, 0.7, 0.2, 0.35)) -> void:
	radius = r
	dps = damage_per_sec
	duration = dur
	hurts_player = to_player
	_mesh = FX.cylinder(r, 0.08, color, 0.4)
	add_child(_mesh)
	_mesh.position.y = 0.05


func _physics_process(delta: float) -> void:
	_t += delta
	_tick += delta
	if duration > 0.0 and _t >= duration:
		queue_free()
		return
	if _tick < 0.25:
		return
	_tick = 0.0
	if hurts_player:
		var p = get_tree().get_first_node_in_group("player")
		if p:
			var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
			if d <= radius:
				p.take_damage(dps * 0.25, null, true)
