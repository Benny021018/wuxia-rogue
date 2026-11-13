extends Node3D
## 投射物：玩家的暗器／箭／劍氣，以及敵人的箭、毒鏢、刀氣
## 不用物理引擎，每幀以距離判定命中（灰盒原型夠用且穩定）

var from_player := true
var direction := Vector3.FORWARD
var speed := 40.0
var damage := 10.0
var pierce := 0
var max_range := 20.0
var radius := 0.5
var on_hit: Callable          # 玩家投射物：on_hit.call(enemy, damage)
var source: Node = null       # 敵人投射物的發射者（反彈傷害用）
var poison_cloud := false     # 毒手藥師的毒瓶：落地留下毒霧
var target_pos := Vector3.ZERO

var _travelled := 0.0
var _hit := {}


func setup(color: Color, size := 0.15) -> void:
	var m := FX.sphere(size, color, 2.0)
	add_child(m)
	if not poison_cloud and not direction.is_zero_approx():
		var up := Vector3.RIGHT if absf(direction.normalized().dot(Vector3.UP)) > 0.98 else Vector3.UP
		m.basis = Basis.looking_at(direction, up)
		m.scale = Vector3(0.48, 0.48, 2.6)
		var trail := FX.sphere(size, Color(color, 0.35), 1.1)
		m.add_child(trail)
		trail.position.z = size * 1.4
		trail.scale = Vector3(0.5, 0.5, 1.3)


func _physics_process(delta: float) -> void:
	var step := direction * speed * delta
	if not from_player and not step.is_zero_approx():
		var query := PhysicsRayQueryParameters3D.create(global_position,global_position+step,1)
		query.hit_from_inside = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			global_position = hit.position
			if poison_cloud:
				_spawn_cloud()
			else:
				Sfx.play("arrow_impact", global_position, -4.0)
			queue_free()
			return
	global_position += step
	_travelled += step.length()
	if poison_cloud:
		if global_position.distance_to(target_pos) < 0.8 or _travelled >= max_range:
			_spawn_cloud()
			queue_free()
		return
	if _travelled >= max_range or global_position.y < -1.0:
		queue_free()
		return
	if from_player:
		for e in get_tree().get_nodes_in_group("enemies"):
			if _hit.has(e) or not is_instance_valid(e) or e.dead:
				continue
			if e.hit_center().distance_to(global_position) <= radius + e.hit_radius:
				_hit[e] = true
				if on_hit.is_valid():
					on_hit.call(e, damage)
				if pierce <= 0:
					queue_free()
					return
				pierce -= 1
	else:
		var p = get_tree().get_first_node_in_group("player")
		if p and p.global_position.distance_to(global_position - Vector3(0, 0.9, 0)) <= radius + 0.5:
			p.take_damage(damage, source)
			queue_free()


func _spawn_cloud() -> void:
	Sfx.play("glass_shatter", global_position)
	Sfx.play("poison_hiss", global_position)
	var hz := preload("res://scripts/hazard.gd").new()
	get_parent().add_child(hz)
	hz.global_position = Vector3(global_position.x, 0, global_position.z)
	hz.configure(3.0, damage, 5.0, true, Color(0.35, 0.7, 0.2, 0.35))
