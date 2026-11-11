extends CharacterBody3D
## 敵人：通用追擊／近戰，加上依 enemy_id 的專屬機制（見 data/enemies.csv）

const PROJ := preload("res://scripts/projectile.gd")
const HAZARD := preload("res://scripts/hazard.gd")
const BANDIT_MODELS := {
	"H01": preload("res://assets/models/bandit.glb"),
	"H02": preload("res://assets/models/archer.glb"),
	"H03": preload("res://assets/models/shield.glb"),
}
const GRAVITY := 18.0
const MAP_COLORS := {
	"greenwood": Color(0.55, 0.4, 0.28), "darkmoon": Color(0.16, 0.16, 0.2),
	"corpse_sect": Color(0.45, 0.55, 0.45), "heavenly_demon": Color(0.55, 0.12, 0.12),
}

var eid := ""
var row := {}
var rank := "minion"
var stage := 1
var world
var player
var max_hp := 100.0
var hp := 100.0
var dmg := 8.0
var speed := 2.0
var reach := 1.0
var dead := false
var hit_radius := 0.45
var size := 1.0
var summoner = null           # 召喚者（狼王判定狼群是否存活）
var summons: Array = []

var _visual: Node3D
var _body_mat: BaseMaterial3D
var _label: Label3D
const Bow := preload("res://scripts/archer_bow.gd")
var _bow: Bow
var _draw := -1.0
var _cut_reaction: Tween
var _anim: AnimationPlayer
var _atk_cd := 0.8
var _swing_dir := Vector3.FORWARD
var _windup := 0.0
var _skill_cd := 3.0
var _skill2_cd := 6.0
var _state := ""                    # "", "windup_hop", "hop", "windup_charge", "charge", "dive", "dash"
var _state_t := 0.0
var _move_dir := Vector3.ZERO
var _charge_hit := false
var _poison: Array = []             # 每層 [每秒傷害, 剩餘秒]
var _slow := 0.0
var _slow_t := 0.0
var _vuln := 0.0
var _vuln_t := 0.0
var _stun_t := 0.0
var _enraged := false
var _revived := false
var _last_hit_from_behind := false
var _phase := 1
var _flying := false
var _revealed := true
var _first_strike := true
var _route := PackedVector2Array()
var _route_target := Vector2.INF
var _route_retry := 0.0
var _armor := 0.0


func setup(id: String, stg: int, w, pos: Vector3) -> void:
	eid = id
	row = Data.enemies[id]
	rank = row.rank
	stage = stg
	world = w
	max_hp = Data.enemy_hp(id, stg)
	hp = max_hp
	dmg = Data.enemy_dmg(id, stg)
	speed = float(row.move_speed)
	reach = float(row.range_m)
	size = {"minion": 1.0, "elite": 1.5, "boss": 2.4}[rank]
	if id == "B04":
		size = 0.6
		_flying = true
	if id == "B01":
		size = 0.8
	if id == "Z04":
		_armor = 15.0 * pow(Data.cfg("enemy_hp_growth"), stg - 1)
	hit_radius = 0.45 * size
	position = pos


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1
	player = get_tree().get_first_node_in_group("player")
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4 * size
	cap.height = 1.8 * size
	col.shape = cap
	col.position.y = 0.9 * size
	add_child(col)
	_visual = Node3D.new()
	add_child(_visual)
	if BANDIT_MODELS.has(eid):
		var model: Node3D = BANDIT_MODELS[eid].instantiate()
		_visual.add_child(model)
		_anim = model.find_child("AnimationPlayer", true, false)
		for clip in [&"Walk", &"Idle"]:
			_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_anim.play(&"Idle")
		if eid == "H02":
			_bow = Bow.new()
			add_child(_bow)
			_bow.bind(model.find_children("*","Skeleton3D",true,false)[0])
		# 每個敵人各自控制蓄力發光，避免整群共用同一材質。
		var mesh: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
		_body_mat = mesh.get_active_material(0).duplicate()
		mesh.set_surface_override_material(0, _body_mat)
	else:
		_build_graybox()
	if rank != "minion":
		_label = FX.label3d(row.name_zh, 64, Color(1, 0.85, 0.6) if rank == "elite" else Color(1, 0.4, 0.3))
		_label.position.y = 2.2 * size + 0.3
		add_child(_label)
	if eid == "H06":      # 刺客：隱身
		_revealed = false
		_visual.visible = false
	if _flying:
		position.y = 3.0
	_skill_cd = randf_range(1.5, 4.0)
	if rank == "boss":
		world.boss_spawned(self)


func _build_graybox() -> void:
	var base_col: Color = MAP_COLORS.get(row.map_id, Color.GRAY)
	var tint := float(hash(eid) % 100) / 100.0 * 0.25 - 0.12
	base_col = base_col.lightened(tint) if tint > 0.0 else base_col.darkened(-tint)
	if rank == "elite":
		base_col = base_col.lerp(Color(0.8, 0.2, 0.15), 0.35)
	elif rank == "boss":
		base_col = base_col.lerp(Color(0.15, 0.12, 0.1), 0.4)
	var mi := MeshInstance3D.new()
	if _flying:
		var sm := SphereMesh.new()
		sm.radius = 0.35
		sm.height = 0.5
		mi.mesh = sm
		mi.position.y = 0.4
	else:
		var cm := CapsuleMesh.new()
		cm.radius = 0.4 * size
		cm.height = 1.8 * size
		mi.mesh = cm
		mi.position.y = 0.9 * size
	_body_mat = FX.mat(base_col)
	mi.material_override = _body_mat
	_visual.add_child(mi)
	var eyes := FX.box(Vector3(0.4 * size, 0.08 * size, 0.08), Color(0.9, 0.95, 0.4) if map_is("corpse_sect") else Color(1, 0.2, 0.15), 3.0)
	eyes.position = Vector3(0, (0.55 if _flying else 1.45) * size, -0.36 * size)
	_visual.add_child(eyes)
	if eid == "Z06":      # 鬼面屍王：背後的罩門
		var core := FX.sphere(0.35, Color(0.3, 1.0, 0.4), 3.0)
		core.position = Vector3(0, 1.6 * size * 0.5 + 0.6, 0.45 * size)
		_visual.add_child(core)


func map_is(m: String) -> bool:
	return row.map_id == m


func hit_center() -> Vector3:
	return global_position + Vector3(0, (0.4 if _flying else 0.9 * size), 0)


func _physics_process(delta: float) -> void:
	if dead or player == null:
		return
	_route_retry -= delta
	_tick_status(delta)
	if _stun_t > 0.0:
		if _bow:
			_cancel_draw()
			_bow.pose(-1, player.global_position + Vector3.UP)
		_stun_t -= delta
		velocity.x = 0
		velocity.z = 0
		_apply_gravity(delta)
		move_and_slide()
		return
	var to_p: Vector3 = player.global_position - global_position
	var flat := Vector3(to_p.x, 0, to_p.z)
	var dist := flat.length()
	if _state == "" and _windup <= 0:
		if dist > 0.05:
			rotation.y = atan2(-flat.x, -flat.z)
	_behaviour(delta, flat, dist)
	if _anim and _draw < 0.0 and _anim.current_animation not in [&"Slash", &"Shoot"]:
		var moving := Vector2(velocity.x, velocity.z).length() > 0.15
		var clip := &"Walk" if moving else &"Idle"
		if _anim.current_animation != clip:
			_anim.play(clip, 0.10)
	_apply_gravity(delta)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if _flying:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta


func _speed() -> float:
	var s := speed * (1.0 - _slow / 100.0)
	if _enraged:
		s *= 1.5
	return s


func _clear_shot() -> bool:
	var origin := global_position + Vector3.UP * (1.3 * size)
	var query := PhysicsRayQueryParameters3D.create(origin,player.global_position + Vector3.UP,1)
	query.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _ground_direction(goal: Vector2) -> Vector2:
	var here := Vector2(global_position.x,global_position.z)
	var direct := here.direction_to(goal)
	if _flying or world.current < 0:
		return direct
	var nav = world.rooms[world.current].navigation
	var radius := .4 * size + Data.cfg("ai_path_margin")
	if not nav.bounds.has_point(here):
		return direct
	goal = goal.clamp(nav.bounds.position+Vector2.ONE*radius,nav.bounds.end-Vector2.ONE*radius)
	if nav.clear(here,goal,radius):
		_route.clear()
		_route_retry = 0.0
		return here.direction_to(goal)
	if _route_retry <= 0 or goal.distance_to(_route_target) > Data.cfg("ai_repath_distance"):
		_route = nav.route(here,goal,radius)
		_route_target = goal
		_route_retry = Data.cfg("ai_repath_seconds")
	# 從最遠的可達格切角；不能跨過擋路的地圖物件。
	for i in range(_route.size()-1,-1,-1):
		if nav.clear(here,_route[i],radius):
			if here.distance_squared_to(_route[i]) <= .04:
				return Vector2.ZERO
			return here.direction_to(_route[i])
	return Vector2.ZERO


func _chase(flat: Vector3, dist: float, keep := 0.0, blocked := false) -> void:
	var dir := Vector3.ZERO
	if blocked:
		dir = flat.normalized()
	elif keep > 0.0:
		if dist < keep * 0.6:
			dir = -flat.normalized()
		elif dist > keep:
			dir = flat.normalized()
	elif dist > reach * 0.8:
		dir = flat.normalized()
	if not dir.is_zero_approx():
		var here := Vector2(global_position.x,global_position.z)
		var distance := keep if dir.dot(flat) < 0 else dist
		var goal := here + Vector2(dir.x,dir.z)*distance
		if keep == 0 and dist < Data.cfg("ai_flank_range") and dist > reach:
			goal += _flank_offset(dir)
		var step := _ground_direction(goal)
		dir = Vector3(step.x,0,step.y)
	dir = (dir + _separation() * 0.8).limit_length()
	velocity.x = dir.x * _speed()
	velocity.z = dir.z * _speed()


# 有同伴佔住正前方時，沿另一側接近；以相對站位選邊，避免每幀隨機換向。
func _flank_offset(forward: Vector3) -> Vector2:
	var side := Vector2(-forward.z,forward.x)
	var ahead := Vector2(forward.x,forward.z)
	var scan := Data.cfg("ai_flank_spacing")
	var nearest := scan
	var offset := Vector2.ZERO
	for ally in world.enemies_near(global_position,scan):
		if ally == self or ally.dead:
			continue
		var d: Vector3 = ally.global_position-global_position
		var planar := Vector2(d.x,d.z)
		var gap := planar.length()
		if gap >= nearest or planar.dot(ahead) <= 0 or absf(planar.dot(side)) > hit_radius+ally.hit_radius:
			continue
		var flank := -signf(planar.dot(side))
		if is_zero_approx(flank):
			flank = 1 if get_instance_id() % 2 == 0 else -1
		nearest = gap
		offset = side * flank * minf(scan,reach+hit_radius)
	return offset


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for o in world.enemies_near(global_position, 1.2):
		if o == self:
			continue
		var d: Vector3 = global_position - o.global_position
		d.y = 0
		var l := d.length()
		if l > 0.01:
			push += d / l * (1.2 - l)
	return push


func _melee(delta: float, dist: float, mult := 1.0) -> void:
	_atk_cd -= delta
	if _windup > 0.0:
		velocity.x = 0
		velocity.z = 0
		_windup -= delta
		if _windup <= 0.0:
			_body_mat.emission_enabled = false
			var impact_reach := reach + 0.8 + hit_radius
			FX.attack_trail(world,hit_center(),_swing_dir,impact_reach,180,0,Color("#ffa071"),.20)
			if _anim:
				FX.play(world,hit_center()+_swing_dir*impact_reach*.7,&"sword-slash",impact_reach*.8,.20)
			var toward: Vector3 = player.global_position-global_position
			toward.y = 0
			if dist <= impact_reach and _swing_dir.dot(toward.normalized()) >= 0 and _clear_shot():
				_hit_player(dmg * mult)
		return
	if _atk_cd <= 0.0 and dist <= reach + 0.5 + hit_radius and _clear_shot():
		_swing_dir = -global_basis.z
		velocity.x = 0
		velocity.z = 0
		_windup = 0.35
		_atk_cd = 1.3
		_body_mat.emission_enabled = true
		_body_mat.emission = Color(1, 0.3, 0.2)
		if _anim:
			_anim.play(&"Slash", 0.05)


func _hit_player(amount: float) -> void:
	if eid == "B01":
		var pack := 0
		for o in world.enemies_near(player.global_position, 4.0):
			if o.eid == "B01":
				pack += 1
		if pack >= 3:
			amount *= 1.3
	if eid == "H06" and _first_strike:
		amount *= 2.0
		_first_strike = false
	if eid == "H07" and hp < max_hp * 0.3:
		hp = minf(max_hp, hp + amount * 0.3)
	player.take_damage(amount, self)


func _cancel_draw() -> void:
	if _draw >= 0.0:
		_draw = -1.0
		_body_mat.emission_enabled = false
		_anim.play(&"Idle", .10)

func _archery(delta: float, flat: Vector3, dist: float) -> void:
	var target: Vector3 = player.global_position + Vector3.UP
	var blocked := not _clear_shot()
	if (dist >= 22.0 or blocked) and _draw < Bow.RELEASE:
		_cancel_draw()
	if _draw < 0.0:
		if blocked or dist >= 22.0 or _skill_cd > Bow.RELEASE:
			_chase(flat, dist, 10.0, blocked)
			_bow.pose(-1.0, target)
			return
		_draw = 0.0
		_anim.play(&"Shoot")
		_anim.pause()
	velocity.x = 0
	velocity.z = 0
	var prev := _draw
	_draw += delta
	if prev < Bow.RELEASE and _draw >= Bow.RELEASE:
		_anim.seek(Bow.RELEASE,true)
		_bow.pose(Bow.RELEASE,target)
		_shoot(24.0, dmg, Color(0.9,0.8,0.5), false, _bow.tip_position())
		_skill_cd = 2.0
	_anim.seek(_draw,true)
	_bow.pose(_draw,target)
	_body_mat.emission_enabled = _draw >= Bow.RELEASE - .3 and _draw < Bow.RELEASE
	_body_mat.emission = Color(.85,.58,.18)
	if _draw >= Bow.FINISH:
		_cancel_draw()

func _shoot(speed_mps: float, amount: float, color: Color, cloud := false, arrow_tip := Vector3.INF) -> void:
	var p := PROJ.new()
	world.add_child(p)
	var from := global_position + Vector3(0, 1.3 * size, 0)
	var target: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	if arrow_tip.is_finite():
		from = arrow_tip
	p.global_position = from
	p.from_player = false
	p.direction = (target - from).normalized()
	p.speed = speed_mps
	p.damage = amount
	p.max_range = 30.0
	p.radius = 0.4
	p.source = self
	if cloud:
		p.poison_cloud = true
		p.target_pos = Vector3(player.global_position.x, 0.2, player.global_position.z)
		p.direction = (p.target_pos - from).normalized()
		p.max_range = from.distance_to(p.target_pos)
	if arrow_tip.is_finite():
		var arrow := Bow.make_arrow()
		p.add_child(arrow)
		arrow.basis = Basis.looking_at(p.direction,Vector3.UP)
		arrow.position = -p.direction*Bow.LENGTH
	else:
		p.setup(color, 0.15)


func _aoe_after(center: Vector3, r: float, delay: float, amount: float) -> void:
	FX.warn_circle(world, center, r, delay)
	await get_tree().create_timer(delay, false).timeout
	if dead or not is_instance_valid(player):
		return
	var d := Vector2(player.global_position.x - center.x, player.global_position.z - center.z).length()
	FX.impact_wave(world,center,r,.3,Color(1,.4,.2))
	if d <= r:
		player.take_damage(amount, self)


func _summon(id: String, n: int, cap: int) -> void:
	summons = summons.filter(func(s): return is_instance_valid(s) and not s.dead)
	for i in n:
		if summons.size() >= cap:
			return
		var ang := randf() * TAU
		var pos := global_position + Vector3(cos(ang), 0, sin(ang)) * randf_range(2.0, 4.0)
		var e = world.spawn_enemy(id, pos, false)
		if e:
			e.summoner = self
			summons.append(e)


# ------------------------------------------------------------------ 專屬行為
func _behaviour(delta: float, flat: Vector3, dist: float) -> void:
	_skill_cd -= delta
	_skill2_cd -= delta
	match eid:
		"Z02": _b_hopper(delta, flat, dist)
		"Z05":
			if hp < max_hp * 0.5 and not _enraged:
				_enraged = true
				Game.message.emit("天魔護法狂暴！")
			if _skill_cd <= 0.0:
				_skill_cd = 8.0
				_summon("B01", 3, 9)
			_chase(flat, dist)
			_melee(delta, dist)
		"Z06":
			if _skill_cd <= 0.0 and dist < 12.0:
				_skill_cd = 15.0
				_aoe_after(global_position, 5.0, 2.0, dmg * 2.0)
			_chase(flat, dist)
			_melee(delta, dist)
		"B02": _b_boar(delta, flat, dist)
		"B04": _b_crow(delta, flat, dist)
		"B06": _b_tiger(delta, flat, dist)
		"B07":
			if _skill_cd <= 0.0:
				_skill_cd = 10.0
				Game.message.emit("暗月樓主結印：影衛現身！")
				_summon("H06", 6, 10)
			_chase(flat, dist)
			_melee(delta, dist)
		"H02":
			_archery(delta, flat, dist)
		"H04":
			var blocked := not _clear_shot()
			_chase(flat, dist, 8.0, blocked)
			if not blocked and _skill_cd <= 0.0 and dist < 18.0:
				_skill_cd = 2.5
				_shoot(14.0, dmg, Color(0.4, 0.9, 0.3))
			if _skill2_cd <= 0.0:
				_skill2_cd = 6.0
				_raise_corpse()
		"H05":
			var blocked := not _clear_shot()
			_chase(flat, dist, 8.0, blocked)
			if not blocked and _skill_cd <= 0.0 and dist < 16.0:
				_skill_cd = 4.0
				_shoot(12.0, dmg * 0.6, Color(0.3, 0.8, 0.2), true)
		"H06":
			if not _revealed and dist < 3.0:
				_revealed = true
				_visual.visible = true
				FX.play(world, hit_center(), &"poof", 1.4, 0.15, Color(0.8, 0.8, 0.9))
			_chase(flat, dist)
			if _revealed:
				_melee(delta, dist)
		"H07": _b_blade(delta, flat, dist)
		"H08":
			if _skill_cd <= 0.0 and dist < 10.0:
				_skill_cd = 12.0
				_aoe_after(global_position, 4.0, 1.5, dmg * 1.5)
			if _skill2_cd <= 0.0:
				_skill2_cd = 20.0
				Game.message.emit("黑風寨主吹響號角！")
				_summon("H01", 10, 14)
				_summon("H02", 2, 16)
			_chase(flat, dist)
			_melee(delta, dist)
		"H09": _b_final(delta, flat, dist)
		_:
			_chase(flat, dist)
			_melee(delta, dist)


func _b_hopper(delta: float, flat: Vector3, dist: float) -> void:
	match _state:
		"":
			_chase(flat, dist)
			_melee(delta, dist)
			if _skill_cd <= 0.0 and dist < 9.0 and dist > 2.0 and is_on_floor():
				_state = "windup"
				_state_t = 0.6
				_visual.scale = Vector3(1.2, 0.7, 1.2)
				velocity.x = 0
				velocity.z = 0
		"windup":
			_state_t -= delta
			velocity.x = 0
			velocity.z = 0
			if _state_t <= 0.0:
				_visual.scale = Vector3.ONE
				_state = "hop"
				var d := flat.normalized() * minf(dist, 6.0) / 0.8
				velocity = Vector3(d.x, 7.0, d.z)
		"hop":
			if is_on_floor() and velocity.y <= 0.0:
				_state = ""
				_skill_cd = 3.0
				var impact_radius := 2.0 + hit_radius
				if dist < impact_radius:
					_hit_player(dmg)
				FX.impact_wave(world, global_position, impact_radius, 0.2, Color(0.6, 0.6, 0.4))


func _b_boar(delta: float, flat: Vector3, dist: float) -> void:
	match _state:
		"":
			_chase(flat, dist)
			_melee(delta, dist)
			if _skill_cd <= 0.0 and dist < 14.0 and dist > 3.0:
				_state = "windup"
				_state_t = 1.0
				_move_dir = flat.normalized()
				FX.warn_circle(world, global_position + _move_dir * 3.0, 0.8, 1.0)
		"windup":
			_state_t -= delta
			velocity.x = 0
			velocity.z = 0
			_visual.position.z = sin(_state_t * 30.0) * 0.08
			if _state_t <= 0.0:
				_visual.position.z = 0
				_state = "charge"
				_state_t = 1.4
				_charge_hit = false
		"charge":
			_state_t -= delta
			velocity.x = _move_dir.x * 13.0
			velocity.z = _move_dir.z * 13.0
			if not _charge_hit and dist < 1.4:
				_charge_hit = true
				_hit_player(dmg * 1.6)
			if is_on_wall():
				_state = ""
				_skill_cd = 4.0
				stun(2.0)
				FX.float_text(world, hit_center() + Vector3(0, 1, 0), "暈眩", Color(1, 1, 0.5))
			elif _state_t <= 0.0:
				_state = ""
				_skill_cd = 4.0


func _b_crow(delta: float, flat: Vector3, dist: float) -> void:
	var target_y := 3.0
	match _state:
		"":
			var tang := Vector3(-flat.z, 0, flat.x).normalized()
			var want := flat.normalized() * (dist - 6.0) * 0.6 + tang * 2.5
			velocity.x = want.x
			velocity.z = want.z
			velocity.y = (target_y - global_position.y) * 2.0
			if _skill_cd <= 0.0 and dist < 12.0:
				_state = "dive"
				_state_t = 1.5
				_charge_hit = false
		"dive":
			_state_t -= delta
			var tp: Vector3 = player.global_position + Vector3(0, 1.2, 0)
			var d := (tp - global_position).normalized() * 9.0
			velocity = d
			if not _charge_hit and global_position.distance_to(tp) < 1.0:
				_charge_hit = true
				_hit_player(dmg)
				_state_t = 0.0
			if _state_t <= 0.0:
				_state = ""
				_skill_cd = 4.0


func _b_tiger(delta: float, flat: Vector3, dist: float) -> void:
	match _state:
		"":
			_chase(flat, dist)
			_melee(delta, dist)
			if _skill_cd <= 0.0 and dist < 12.0 and dist > 3.0 and is_on_floor():
				_state = "windup"
				_state_t = 0.6
				_visual.scale = Vector3(1.1, 0.75, 1.1)
		"windup":
			_state_t -= delta
			velocity.x = 0
			velocity.z = 0
			if _state_t <= 0.0:
				_visual.scale = Vector3.ONE
				_state = "hop"
				var d := flat.normalized() * dist / 0.8
				velocity = Vector3(d.x, 6.0, d.z)
		"hop":
			if is_on_floor() and velocity.y <= 0.0:
				_state = ""
				_skill_cd = 6.0
				var impact_radius := 2.5 + hit_radius
				if dist < impact_radius:
					_hit_player(dmg * 1.2)
				FX.impact_wave(world, global_position, impact_radius, 0.2, Color(1, 0.7, 0.3))


func _b_blade(delta: float, flat: Vector3, dist: float) -> void:
	match _state:
		"":
			_chase(flat, dist)
			_melee(delta, dist)
			if _skill_cd <= 0.0 and dist < 12.0:
				_state = "windup"
				_state_t = 0.5
				_move_dir = flat.normalized()
				_body_mat.emission_enabled = true
				_body_mat.emission = Color(1, 0.1, 0.1)
		"windup":
			_state_t -= delta
			velocity.x = 0
			velocity.z = 0
			if _state_t <= 0.0:
				_body_mat.emission_enabled = false
				_state = "dash"
				_state_t = 0.45
				_shoot(18.0, dmg * 1.2, Color(1, 0.2, 0.2))
		"dash":
			_state_t -= delta
			velocity.x = _move_dir.x * 12.0
			velocity.z = _move_dir.z * 12.0
			if _state_t <= 0.0:
				_state = ""
				_skill_cd = 5.0
				if dist < 2.0:
					_hit_player(dmg)


func _b_final(delta: float, flat: Vector3, dist: float) -> void:
	var ratio := hp / max_hp
	if _phase == 1 and ratio <= 0.66:
		_phase = 2
		Game.message.emit("天魔：天魔領域！")
		var hz := HAZARD.new()
		world.add_child(hz)
		hz.global_position = Vector3(global_position.x, 0, global_position.z)
		hz.configure(9.0, dmg * 0.3, -1.0, true, Color(0.3, 0.6, 0.2, 0.25))
		world.track_hazard(hz)
	elif _phase == 2 and ratio <= 0.33:
		_phase = 3
		_enraged = true
		hp = minf(max_hp, hp + max_hp * 0.15)
		Game.message.emit("天魔吸取血氣，狂暴了！")
		_summon("B01", 6, 12)
	if _phase == 1 and _skill2_cd <= 0.0:
		_skill2_cd = 25.0
		_summon("B02", 2, 3)
	if _skill_cd <= 0.0 and dist < 12.0:
		_skill_cd = 10.0 if _phase < 3 else 7.0
		_aoe_after(player.global_position, 3.5, 1.5, dmg * 1.2)
	_chase(flat, dist)
	_melee(delta, dist)


func _raise_corpse() -> void:
	var pos: Vector3 = world.take_corpse_near(global_position, 12.0)
	if pos == Vector3.INF:
		pos = global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	FX.play(world, pos + Vector3(0, 0.5, 0), &"poof", 1.68, 0.3, Color(0.4, 1, 0.4))
	var e = world.spawn_enemy("Z01", pos, false)
	if e:
		summons.append(e)


# ------------------------------------------------------------------ 狀態效果
func _tick_status(delta: float) -> void:
	if not _poison.is_empty():
		var total := 0.0
		for p in _poison:
			total += p[0] * delta
			p[1] -= delta
		_poison = _poison.filter(func(p): return p[1] > 0.0)
		if total > 0.0:
			_apply_damage(total, false, true)
	if _slow_t > 0.0:
		_slow_t -= delta
		if _slow_t <= 0.0:
			_slow = 0.0
	if _vuln_t > 0.0:
		_vuln_t -= delta
		if _vuln_t <= 0.0:
			_vuln = 0.0


func apply_poison(total: float, stack: bool) -> void:
	if total <= 0.0 or dead:
		return
	if _poison.is_empty():
		FX.play(self, hit_center() + Vector3.UP * size, &"poisoned", 0.65 * size, 0.55)
	if stack:
		_poison.append([total / 3.0, 3.0])
	elif _poison.is_empty():
		_poison.append([total / 3.0, 3.0])
	else:
		_poison[0] = [maxf(_poison[0][0], total / 3.0), 3.0]


func poison_left() -> float:
	var t := 0.0
	for p in _poison:
		t += p[0] * p[1]
	return t


func is_poisoned() -> bool:
	return not _poison.is_empty()


func apply_slow(pct: float, dur: float) -> void:
	if _slow_t <= 0.0 and pct > 0.0 and dur > 0.0:
		FX.play(self, global_position + Vector3.UP * 0.22, &"slowed", 1.2 * size, minf(dur, 0.6))
	_slow = clampf(maxf(_slow, pct), 0.0, 80.0)
	_slow_t = maxf(_slow_t, dur)


func is_slowed() -> bool:
	return _slow > 0.0


func apply_vuln(pct: float, dur: float) -> void:
	_vuln = maxf(_vuln, pct)
	_vuln_t = maxf(_vuln_t, dur)


func stun(t: float) -> void:
	if _stun_t <= 0.0 and t > 0.0:
		FX.play(self, hit_center() + Vector3.UP * size, &"stunned", 0.8 * size, t)
	_stun_t = maxf(_stun_t, t)


func react_to_cut() -> void:
	if _cut_reaction:
		_cut_reaction.kill()
	_cut_reaction = create_tween()
	_cut_reaction.tween_property(_visual,"rotation:x",-.11,.045)
	_cut_reaction.tween_property(_visual,"rotation:x",0.0,.14)


## 被玩家擊中：回傳實際造成的傷害
func take_hit(amount: float, from_pos: Vector3, crit: bool) -> float:
	if dead:
		return 0.0
	var dmg_in := amount * (1.0 + _vuln / 100.0)
	var to_attacker := Vector3(from_pos.x - global_position.x, 0, from_pos.z - global_position.z).normalized()
	var facing := Vector3(-sin(rotation.y), 0, -cos(rotation.y))
	var front := facing.dot(to_attacker) > cos(deg_to_rad(70.0))
	match eid:
		"H03":
			if front:
				dmg_in *= 0.3
				FX.play(world, hit_center() + facing * 0.48, &"shield-block", 0.65, 0.12, Color(1, 0.78, 0.32))
				if randf() < 0.3:
					FX.float_text(world, hit_center() + Vector3(0, 0.8, 0), "格擋", Color(0.8, 0.8, 0.8), 28)
		"Z04":
			dmg_in = maxf(dmg_in * 0.25, dmg_in - _armor)
		"Z06":
			dmg_in *= 0.6 if front else 1.5
			_last_hit_from_behind = not front
		"B04":
			if randf() < 0.3:
				FX.float_text(world, hit_center(), "閃開", Color(0.7, 0.7, 0.7), 28)
				return 0.0
		"B07":
			summons = summons.filter(func(s): return is_instance_valid(s) and not s.dead)
			if not summons.is_empty():
				dmg_in *= 0.5
	if rank == "elite" or rank == "boss":
		dmg_in /= float(row.ehp_factor) if eid != "Z06" and eid != "Z04" else 1.0
	return _apply_damage(dmg_in, crit, false)


func _apply_damage(v: float, crit: bool, dot: bool) -> float:
	if dead:
		return 0.0
	if not dot:
		var contact := hit_center()
		if is_instance_valid(player):
			contact += contact.direction_to(player.cam.global_position) * hit_radius
		FX.play(world, contact, &"crit-hit" if crit else &"hit-spark", (1.55 if crit else 0.76) * size, 0.24 if crit else 0.14)
	hp -= v
	var col := Color(1, 0.85, 0.3) if crit else (Color(0.5, 1, 0.4) if dot else Color.WHITE)
	if not dot or randf() < 0.15:
		FX.float_text(world, hit_center() + Vector3(0, 0.6 * size, 0), str(int(v)), col, 44 if crit else 32)
	if hp <= 0.0:
		if eid == "Z06" and not _revived and not _last_hit_from_behind:
			_revived = true
			hp = max_hp * 0.3
			Game.message.emit("罩門未破，鬼面屍王再起！（繞到背後攻擊罩門）")
			return v
		die()
	return v


func die() -> void:
	if dead:
		return
	dead = true
	FX.play(world, hit_center(), &"poof", 1.4 * size, 0.36)
	remove_from_group("enemies")
	Game.add_kill(eid)
	if is_instance_valid(player):
		player.on_enemy_killed(self)
	if eid == "Z03":
		var hz := HAZARD.new()
		world.add_child(hz)
		hz.global_position = Vector3(global_position.x, 0, global_position.z)
		hz.configure(2.0, dmg * 0.6, 3.0, true)
	world.on_enemy_died(self)
	queue_free()
