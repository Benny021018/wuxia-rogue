extends Node3D
## 唐門暗器落點隨地圖清理。毒囊持續跳傷，絲網只在有目標時收束一次。

var player
var hit: Dictionary
var radius: float
var damage: float
var trap: bool
var life: float
var until_tick: float


func setup(caster, hit_data: Dictionary, reach: float, power: float, is_trap: bool) -> void:
	player = caster
	hit = hit_data
	radius = reach
	damage = power
	trap = is_trap
	life = CombatState.cfg("tang_trap_s" if trap else "tang_cloud_s")
	until_tick = 0 if trap else CombatState.cfg("tang_cloud_tick_s")
	var tint := Color("#ab83d65a") if trap else Color("#95cd6540")
	add_child(FX.cylinder(radius, .04, tint, .35))
	if trap:
		for i in 4:
			var silk := FX.box(Vector3(.025, .02, radius * 2), tint.lightened(.3), .8)
			add_child(silk)
			silk.position.y = .06
			silk.rotation.y = PI * i / 4
	else:
		FX.play(self, global_position + Vector3.UP * .6, &"poison-cloud", radius * 1.6, 1.2)
		Sfx.play("poison_hiss", global_position)


func _physics_process(delta: float) -> void:
	until_tick -= minf(delta, life)
	life -= delta
	if until_tick <= .00001:
		var triggered := false
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.dead or not e.cs.hittable() or global_position.distance_to(e.global_position) > radius + e.hit_radius:
				continue
			if trap:
				player.deal(e, damage, false, .65, global_position, hit)
			else:
				e.take_poison_tick(damage)
			triggered = true
		if trap and triggered:
			FX.play(get_parent(), global_position + Vector3.UP, &"slowed", radius, .35)
			Sfx.play("hit_mid_metal", global_position)
			queue_free()
			return
		if not trap:
			until_tick += CombatState.cfg("tang_cloud_tick_s")
	if life <= .00001:
		queue_free()
