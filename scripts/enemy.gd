extends CharacterBody3D
## 敵人：通用追擊／近戰，加上依 enemy_id 的專屬機制（見 data/enemies.csv）

const PROJ := preload("res://scripts/projectile.gd")
const HAZARD := preload("res://scripts/hazard.gd")
const GRAVITY := 18.0
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
var _recoil: Tween
var _flash := StandardMaterial3D.new()
var _flash_meshes: Array[Node] = []
var _hit_side := 1.0
var _impact_pivot := Node3D.new()
var _skeleton: Skeleton3D
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
# 遠程 AI（ranged_ai.csv）：走位 → 起手（可讀的蓄力）→ 鎖定 → 出手 → 收勢
var ai := {}                        # 數值副本，測試可個別調整
var _rstate := ""                   # "move", "aim", "recover"
var _rt := 0.0
var _aim_cd := 0.0
var _strafe := 1.0
var _strafe_t := 0.0
var _lock := Vector3.INF
var _last_pos := Vector3.ZERO
var _stuck_t := 0.0
# 打擊感
var _knock := Vector3.ZERO          # 擊退速度（逐幀衰減）
var _away := Vector3.FORWARD        # 最後一次被打的方向（玩家 → 敵人）
var cs := CombatState.new()         # 六種狀態（與玩家共用，見 docs/combat-design.md）
# 近戰戰術（docs/combat-design.md「敵人 AI」）：出手權、外圈包圍、招式表、反擊、首領階段
var role := {}                      # enemy_roles.csv
var _token := false                 # 拿著近戰出手權
var _token_t := 0.0                 # 拿著出手權多久了
var _token_rest := 0.0              # 交回出手權後的休息
var _mv := {}                       # 正在出的招（enemy_moves.csv）
var _mv_root := ""                  # 連招的第一招（冷卻記在它身上）
var _mv_cds := {}                   # move_id -> 剩餘冷卻
var _windup_total := 0.0
var _recover_t := 0.0
var _offscreen_t := 0.0
var _slot_angle := NAN              # 外圈分配到的角度（NAN = 沒有分配）
var _slot_t := 0.0
var _sway := 0.0
var _combo_taken := 0               # 這次被連打了幾下
var _was_stunned := false
var _evade_t := 0.0
var _evade_dir := Vector3.ZERO
var _counter_t := 0.0               # >0：霸體空窗剛結束，可以反擊
var _broken_by_hit := false
var phase_row := {}                 # boss_phases.csv 目前階段
var view_override := 0              # 測試用：1 = 一定在畫面內，-1 = 一定在畫面外，0 = 依鏡頭判斷
var _pose: Node3D                   # 倒地／浮空時把整個外觀放平
var last_hit_metal := false         # 最後一擊打在盾牌／鎧甲上（音效用金屬層）


func setup(id: String, stg: int, w, pos: Vector3) -> void:
	eid = id
	row = Data.enemies[id]
	rank = row.rank
	cs.armor_always = rank != "minion"
	cs.hitstun_mult = 1.0 if rank == "minion" else CombatState.cfg("hitstun_elite_mult" if rank == "elite" else "hitstun_boss_mult")
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
	role = Data.enemy_roles.get(String(row.role), {})
	if Data.boss_phases.has(id):
		phase_row = Data.boss_phases[id][0]
	_sway = randf() * TAU
	if Data.ranged_ai.has(id):
		var r: Dictionary = Data.ranged_ai[id]
		for k in r:
			if k != "enemy_id" and k != "note":
				ai[k] = float(r[k])
		_rstate = "move"
		_aim_cd = ai.first_delay_s + randf() * 0.8
		_strafe = 1.0 if randf() < 0.5 else -1.0
		_strafe_t = randf_range(0.5, 1.0) * ai.strafe_s


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
	_pose = Node3D.new()
	add_child(_pose)
	_pose.add_child(_impact_pivot)
	_impact_pivot.add_child(_visual)
	var scene: PackedScene = load("res://assets/models/enemy-motion/%s.glb" % eid)
	var model := scene.instantiate() as Node3D
	_visual.add_child(model)
	model.scale = Vector3.ONE * size
	_anim = model.find_child("AnimationPlayer", true, false)
	for clip in [&"Idle", &"Walk"]:
		_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_anim.play(&"Idle")
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	if eid == "H02":
		_bow = Bow.new()
		_impact_pivot.add_child(_bow)
		_bow.bind(_skeleton)
	# 起手光：身體由多個部位、多張貼圖組成，所以用一層疊加材質（加色）統一發光，
	# 平常加黑色＝看不出來；受擊閃白暫時換成 _flash，結束後換回來
	_body_mat = StandardMaterial3D.new()
	_body_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_body_mat.albedo_color = Color.BLACK
	_body_mat.metallic_specular = 0.0
	_body_mat.roughness = 1.0
	_body_mat.emission_energy_multiplier = 0.55
	if eid in ["H01","H07","H08"]:
		var wrist := BoneAttachment3D.new()
		_skeleton.add_child(wrist)
		wrist.bone_name = "hand_r" if _skeleton.find_bone("hand_r") >= 0 else "RightHand"
		var sword := preload("res://assets/models/weapons/Tachi.glb").instantiate()
		wrist.add_child(sword)
		sword.find_child("Saya",true,false).hide()
		var g: Array = preload("res://scripts/fighter_model.gd").GRIP["W001"]
		sword.position = g[0]
		sword.rotation_degrees = g[1]
		sword.scale = Vector3.ONE * (.82 if eid=="H01" else 1.0)
	if eid == "Z06":
		var core := FX.sphere(0.35, Color(0.3, 1.0, 0.4), 3.0)
		core.position = Vector3(0, 1.6 * size * 0.5 + 0.6, 0.45 * size)
		_visual.add_child(core)
	_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_meshes = _visual.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.get_parent() is Skeleton3D)
	for mesh in _flash_meshes:
		mesh.material_overlay = _body_mat
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


func hit_center() -> Vector3:
	return global_position + Vector3(0, (0.4 if _flying else 0.9 * size), 0)


func _physics_process(delta: float) -> void:
	if dead or player == null:
		return
	_route_retry -= delta
	_tick_status(delta)
	cs.tick(delta, is_on_floor())
	var lying := cs.base == CombatState.S.DOWN
	if _pose:
		if cs.base == CombatState.S.AIR:
			_pose.rotation.x = CombatState.airborne_pitch()
			if _anim and (_anim.assigned_animation != &"Hit" or _anim.is_playing()):
				# 浮空：停在受擊第一格（仰頭、手腳收起）；新骨架的靜止姿勢是 T 字，不能 reset 骨頭
				_anim.play(&"Hit", 0)
				_anim.seek(0, true)
				_anim.pause()
		else:
			_pose.rotation.x = lerp_angle(_pose.rotation.x, -PI / 2.0 if lying else 0.0, minf(1.0, delta * 16.0))
		_pose.position.y = lerpf(_pose.position.y, 0.35 * size if lying else 0.0, minf(1.0, delta * 16.0))
	if not cs.can_act():
		# 受擊、浮空、倒地：不能行動，招式被打斷
		_stun_t = maxf(_stun_t, delta)
		_windup = 0.0
		_state = ""
		_body_mat.emission_enabled = false
	if _stun_t > 0.0:
		_was_stunned = true
		_abort_move()
		if _rstate == "aim" or _rstate == "recover":
			_ranged_cancel(0.6)
		if _bow:
			_bow.pose(-1, player.global_position + Vector3.UP)
		_stun_t -= delta
		velocity.x = 0
		velocity.z = 0
		_apply_knock(delta)
		_apply_gravity(delta)
		move_and_slide()
		return
	var to_p: Vector3 = player.global_position - global_position
	var flat := Vector3(to_p.x, 0, to_p.z)
	var dist := flat.length()
	if _was_stunned:
		_was_stunned = false
		_on_recovered(flat)
	if _state == "" and _windup <= 0 and _recover_t <= 0 and _evade_t <= 0 and not _lock.is_finite():
		if dist > 0.05:
			rotation.y = atan2(-flat.x, -flat.z)
	_tactics_tick(delta)
	if _evade_t > 0.0:
		_evade_t -= delta
		velocity.x = _evade_dir.x * Data.cfg("ai_escape_speed")
		velocity.z = _evade_dir.z * Data.cfg("ai_escape_speed")
	else:
		_behaviour(delta, flat, dist)
	if _draw < 0.0 and (not _anim.is_playing() or _anim.current_animation in [&"Walk", &"Idle"]):
		var moving := Vector2(velocity.x, velocity.z).length() > 0.15
		var clip := &"Walk" if moving else &"Idle"
		if _anim.current_animation != clip or not _anim.is_playing():
			_anim.play(clip, 0.10)
	_apply_knock(delta)
	_apply_gravity(delta)
	move_and_slide()


func _apply_knock(delta: float) -> void:
	if _knock.length_squared() < 0.0004:
		_knock = Vector3.ZERO
		return
	velocity.x += _knock.x
	velocity.z += _knock.z
	_knock *= exp(-float(Data.feel.knock_decay) * delta)


func _knock_mass() -> float:
	match rank:
		"elite": return float(Data.feel.knock_mass_elite)
		"boss": return float(Data.feel.knock_mass_boss)
	return 1.0


func _apply_gravity(delta: float) -> void:
	if cs.base == CombatState.S.AIR:
		velocity.y -= CombatState.cfg("air_gravity") * delta
		return
	if _flying:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta


func _speed() -> float:
	var s := speed * (1.0 - _slow / 100.0) * float(phase_row.get("speed_mult", 1.0))
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
	if keep == 0.0 and not blocked and _uses_token() and _revealed:
		_engage(flat, dist)
		return
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
	for k in _mv_cds:
		_mv_cds[k] = float(_mv_cds[k]) - delta
	if _windup > 0.0:
		velocity.x = 0
		velocity.z = 0
		_windup -= delta
		if _windup <= 0.0:
			_strike(dist, mult)
		return
	if _recover_t > 0.0:
		velocity.x = 0
		velocity.z = 0
		_recover_t -= delta
		if _recover_t <= 0.0:
			_after_move(dist)
		return
	var mv := _pick_move(dist)
	if mv.is_empty() or not _clear_shot() or not _may_attack():
		return
	_start_move(mv)


## 這隻敵人的招式：自己的（enemy_moves.csv 以 enemy_id 列出），沒有就用階級預設
func _move_table() -> Dictionary:
	return Data.enemy_moves.get(eid, Data.enemy_moves.get(rank, {}))


func _move_reach(mv: Dictionary) -> float:
	return reach + float(mv.reach_add_m) + hit_radius


## 選一招：反擊優先；否則從冷卻好、階段夠、打得到的招式裡依權重抽
func _pick_move(dist: float) -> Dictionary:
	var table := _move_table()
	if _counter_t > 0.0:
		var c: Dictionary = table.get("counter", Data.enemy_moves.get(rank, {}).get("counter", {}))
		if not c.is_empty() and dist <= _move_reach(c) - 0.3:
			return c
	if _atk_cd > 0.0:
		return {}
	var pool: Array = []
	var total := 0.0
	for id in table:
		var mv: Dictionary = table[id]
		if mv.kind != "melee" or float(mv.weight) <= 0.0 or int(mv.min_phase) > _phase:
			continue
		if float(_mv_cds.get(id, 0.0)) > 0.0 or dist > _move_reach(mv) - 0.3:
			continue
		pool.append(mv)
		total += float(mv.weight)
	if pool.is_empty():
		return {}
	var roll := randf() * total
	for mv in pool:
		roll -= float(mv.weight)
		if roll <= 0.0:
			return mv
	return pool[-1]


func _start_move(mv: Dictionary) -> void:
	if _mv.is_empty() or mv.kind == "counter":
		_mv_root = mv.move_id
	_mv = mv
	_swing_dir = -global_basis.z
	var t := float(mv.windup_s) * float(phase_row.get("windup_mult", 1.0))
	if not _onscreen():
		t *= Data.cfg("ai_offscreen_windup_mult")
	_windup = maxf(t, 0.05)
	_windup_total = _windup
	velocity.x = 0
	velocity.z = 0
	Sfx.play("enemy_windup", hit_center())
	# 起手光：破霸體是金色、擊倒或挑空是暗紅，一般是橘紅
	_body_mat.emission_enabled = true
	_body_mat.emission = Color(1, 0.78, 0.15) if int(mv.break_armor) == 1 else (Color(0.85, 0.05, 0.1) if int(mv.knockdown) == 1 or int(mv.launch) == 1 else Color(1, 0.3, 0.2))
	if mv.kind == "counter":
		_counter_t = 0.0
		FX.float_text(world, hit_center() + Vector3(0, 1.0 * size, 0), "反擊", Color(1, 0.8, 0.3), 34)
	var clip := StringName(mv.anim) if mv.anim != "" and _anim.has_animation(StringName(mv.anim)) else &"Slash"
	if not _anim.is_playing() or _anim.current_animation in [&"Walk", &"Idle", &"Slash", clip]:
		_anim.play(clip, 0.05)


func _strike(dist: float, mult: float) -> void:
	_body_mat.emission_enabled = false
	var mv := _mv
	var impact_reach := _move_reach(mv)
	var arc := float(mv.arc_deg)
	if arc >= 359.0:
		FX.impact_wave(world, global_position, impact_reach, 0.2, Color(1, 0.45, 0.3))
	else:
		FX.attack_trail(world, hit_center(), _swing_dir, impact_reach, arc, 0, Color("#ffa071"), .20)
		FX.play(world, hit_center() + _swing_dir * impact_reach * .7, &"sword-slash", impact_reach * .8, .20)
	Sfx.play("enemy_swing", hit_center())
	var toward: Vector3 = player.global_position - global_position
	toward.y = 0
	var in_arc := arc >= 359.0 or toward.length() < 0.05 or _swing_dir.dot(toward.normalized()) >= cos(deg_to_rad(arc * 0.5))
	if dist <= impact_reach and in_arc and _clear_shot():
		_hit_player(dmg * mult * float(mv.dmg_mult), _hit_dict(mv))
	_recover_t = maxf(float(mv.recover_s), 0.01)


## 收招：有連招就接下去，否則記冷卻、交回出手權
func _after_move(dist: float) -> void:
	var mv := _mv
	var table := _move_table()
	if not mv.is_empty() and mv.chain != "" and table.has(mv.chain):
		var nxt: Dictionary = table[mv.chain]
		var pv := _player_view()
		if dist <= _move_reach(nxt) + 0.6 and not pv.inv:
			_start_move(nxt)
			return
	var root: Dictionary = table.get(_mv_root, {})
	if not root.is_empty():
		_mv_cds[_mv_root] = float(root.cd_s)
	_atk_cd = Data.cfg("ai_attack_gap_s")
	_mv = {}
	_mv_root = ""
	_release_token(Data.cfg("ai_token_rest_s"))


## 被打斷（硬直、浮空、倒地、跳開）：招式作廢
func _abort_move() -> void:
	if not _mv.is_empty():
		var root: Dictionary = _move_table().get(_mv_root, {})
		if not root.is_empty():
			_mv_cds[_mv_root] = float(root.cd_s) * 0.5
		_atk_cd = Data.cfg("ai_attack_gap_s")
	_mv = {}
	_mv_root = ""
	_windup = 0.0
	_recover_t = 0.0
	_release_token(Data.cfg("ai_token_rest_s"))


## 一招打在玩家身上的屬性；留空的欄位用階級預設（combat_state_config.csv）
func _hit_dict(mv: Dictionary) -> Dictionary:
	var tier := "" if rank == "minion" else ("_elite" if rank == "elite" else "_boss")
	var h := {}
	h["hitstun_s"] = float(mv.hitstun_s) if mv.get("hitstun_s", "") != "" else CombatState.cfg("enemy_hitstun%s_s" % tier)
	h["push_m"] = float(mv.push_m) if mv.get("push_m", "") != "" else CombatState.cfg("enemy_push%s_m" % tier)
	h["launch"] = int(mv.get("launch", 0))
	h["launch_h_m"] = float(mv.get("launch_h_m", 0))
	h["break_armor"] = int(mv.get("break_armor", 0))
	h["knockdown"] = int(mv.get("knockdown", 0))
	return h


## 專屬技能（跳擊、衝撞…）的命中屬性，在 enemy_moves.csv 的 skill 列
func _skill_hit(key: String) -> Dictionary:
	var mv: Dictionary = Data.enemy_moves.get(eid, {}).get(key, Data.enemy_moves.get("*", {}).get(key, {}))
	return _hit_dict(mv) if not mv.is_empty() else {}


# ------------------------------------------------------------------ 戰術判斷
func _uses_token() -> bool:
	return int(role.get("token", 0)) == 1


## 玩家現在的狀態（區網的對方也一樣是 player.gd）
func _player_view() -> Dictionary:
	var v := {"inv": false, "armor": false, "air_down": false, "busy_long": false}
	if player == null or not is_instance_valid(player):
		return v
	var pcs = player.get("cs")
	if pcs != null:
		v.inv = pcs.state() == CombatState.S.INVINCIBLE or (player.has_method("damage_immune") and player.damage_immune())
		v.armor = pcs.has_armor()
		v.air_down = pcs.base == CombatState.S.AIR or pcs.base == CombatState.S.DOWN
	var r = player.get("runner")
	if r != null and not r.move.is_empty():
		v.armor = v.armor or String(r.move.get("slot", "")) == "ult"
		v.busy_long = float(r.move.get("duration_s", 0.0)) >= Data.cfg("ai_punish_move_s")
	return v


## 在玩家的畫面裡嗎？本機玩家看鏡頭；區網對方沒有鏡頭資訊，看面向
func _onscreen() -> bool:
	if view_override != 0:
		return view_override > 0
	if player == null or not is_instance_valid(player):
		return true
	var c = player.get("cam")
	if c != null and c.is_inside_tree() and c.get_viewport().get_camera_3d() == c:
		return c.is_position_in_frustum(hit_center())
	var yaw = player.get("body_yaw")
	if yaw == null:
		return true
	var to: Vector3 = global_position - player.global_position
	to.y = 0
	if to.length() < 0.1:
		return true
	return Vector3(-sin(yaw), 0, -cos(yaw)).dot(to.normalized()) >= cos(deg_to_rad(Data.cfg("ai_behind_deg")))


## 可以起手嗎：看玩家狀態、出手權、在不在鏡頭裡
func _may_attack() -> bool:
	if _counter_t > 0.0:
		return true
	var pv := _player_view()
	if pv.inv:
		return false
	if pv.air_down and int(role.get("pursue_down", 0)) != 1:
		return false
	if pv.armor and int(role.get("fear_armor", 0)) == 1:
		return false
	if _uses_token() and not _token:
		return false
	if not _onscreen():
		if _offscreen_t > 0.0:
			return false
		if randf() > Data.cfg("ai_offscreen_attack_chance"):
			_offscreen_t = Data.cfg("ai_offscreen_retry_s")
			return false
	return true


## 專屬技能（跳擊、衝鋒、撲擊…）能不能放：玩家無敵或倒地時不放，鏡頭外機率降低
func _skill_ok() -> bool:
	var pv := _player_view()
	if pv.inv or (pv.air_down and int(role.get("pursue_down", 0)) != 1):
		return false
	if not _onscreen():
		if _offscreen_t > 0.0:
			return false
		if randf() > Data.cfg("ai_offscreen_attack_chance"):
			_offscreen_t = Data.cfg("ai_offscreen_retry_s")
			return false
	return true


func token_limit(pv := {}) -> int:
	var n := int(Data.cfg("ai_tokens_base") + Data.cfg("ai_tokens_per_map") * float(world.map_index if world else 0))
	n = mini(n, int(Data.cfg("ai_tokens_max")))
	if pv.get("busy_long", false):
		n += int(Data.cfg("ai_punish_extra_tokens"))
	return maxi(1, n)


func _token_holders() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and not e.dead and e._token and e.player == player:
			n += 1
	return n


func _take_token(pv: Dictionary) -> bool:
	if _token:
		return true
	var pursuit: bool = pv.air_down and int(role.get("pursue_down", 0)) == 1
	if pursuit or _token_holders() < token_limit(pv):
		_token = true
		_token_t = 0.0
		return true
	return false


func _release_token(rest: float) -> void:
	if _token:
		_token = false
		_token_rest = maxf(_token_rest, rest)


## 每幀的戰術計時：出手權逾時、反擊時機、首領階段
func _tactics_tick(delta: float) -> void:
	_offscreen_t -= delta
	_token_rest -= delta
	_slot_t -= delta
	_sway += delta * TAU / maxf(0.1, Data.cfg("ai_ring_sway_s"))
	if _token and _windup <= 0.0 and _recover_t <= 0.0:
		_token_t += delta
		if _token_t > Data.cfg("ai_token_hold_s"):
			_release_token(Data.cfg("ai_token_rest_s"))
	# 精英與首領：被破霸體的空窗結束時反擊
	if cs.armor_always:
		if _broken_by_hit and cs.armor_broken_t <= 0.0:
			_broken_by_hit = false
			_counter_t = Data.cfg("ai_counter_window_s")
		_counter_t -= delta
	_update_phase()


## 外圈站位與輪流上前：拿到出手權就衝進去，沒拿到在外圈散開包圍
func _engage(flat: Vector3, dist: float) -> void:
	var pv := _player_view()
	var radius := float(role.ring_m)
	var fear: bool = pv.armor and int(role.get("fear_armor", 0)) == 1
	if fear:
		_release_token(0.3)
		radius = maxf(radius, Data.cfg("ai_armor_retreat_m"))
	elif pv.inv:
		radius = maxf(minf(radius, dist), reach + hit_radius + Data.cfg("ai_backoff_m"))
	elif not _token and _atk_cd <= 0.0 and _token_rest <= 0.0 and dist < radius + 2.5:
		if not pv.air_down or int(role.get("pursue_down", 0)) == 1:
			_take_token(pv)
	if _token and not fear and not pv.inv:
		_approach(flat, dist)
	else:
		_ring_move(flat, dist, radius)


## 拿著出手權：直接靠近，前方有同伴就從側面繞
func _approach(flat: Vector3, dist: float) -> void:
	var dir := Vector3.ZERO
	if dist > reach * 0.8:
		dir = flat.normalized()
		var here := Vector2(global_position.x, global_position.z)
		var goal := here + Vector2(dir.x, dir.z) * dist
		if dist < Data.cfg("ai_flank_range") and dist > reach:
			goal += _flank_offset(dir)
		var step := _ground_direction(goal)
		dir = Vector3(step.x, 0, step.y)
	dir = (dir + _separation() * 0.8).limit_length()
	velocity.x = dir.x * _speed()
	velocity.z = dir.z * _speed()


## 外圈：依定位決定站在哪個角度（側翼散開、刀盾手擋在遠程隊友前面），沿圓周移過去
func _ring_move(flat: Vector3, dist: float, radius: float) -> void:
	var pp: Vector3 = player.global_position
	var now := atan2(-flat.x, -flat.z)          # 玩家 → 自己 的角度
	if _slot_t <= 0.0:
		_slot_t = 0.3
		_slot_angle = _formation_angle(now)
	var target := now if is_nan(_slot_angle) else _slot_angle
	target += sin(_sway) * deg_to_rad(Data.cfg("ai_ring_sway_deg"))
	var d_ang := wrapf(target - now, -PI, PI)
	var a := target if absf(d_ang) < 0.6 else now + signf(d_ang) * 0.6     # 沿圓周走，不穿過玩家
	var goal := pp + Vector3(sin(a), 0, cos(a)) * radius
	var to := goal - global_position
	to.y = 0
	var dir := Vector3.ZERO
	if to.length() > 0.25:
		var step := _ground_direction(Vector2(goal.x, goal.z))
		dir = Vector3(step.x, 0, step.y)
	dir = (dir + _separation() * 0.8).limit_length()
	var mult := Data.cfg("ai_ring_speed_mult") if absf(dist - radius) < Data.cfg("ai_ring_band_m") else 1.0
	velocity.x = dir.x * _speed() * mult
	velocity.z = dir.z * _speed() * mult


## 外圈角度（玩家 → 自己 的方向，atan2(x, z)）
func _formation_angle(now: float) -> float:
	var pp: Vector3 = player.global_position
	if role.get("formation", "") == "front":
		# 刀盾手：站在玩家與最近的遠程隊友之間
		var best = null
		var best_d := Data.cfg("ai_cover_scan_m")
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.dead or e.role.get("formation", "") != "ranged":
				continue
			var d: float = e.global_position.distance_to(global_position)
			if d < best_d:
				best_d = d
				best = e
		if best != null:
			var v: Vector3 = best.global_position - pp
			return atan2(v.x, v.z)
		return now
	if role.get("formation", "") != "flank":
		return now
	# 側翼：同一個目標的外圈隊友在玩家鏡頭前方平均散開
	var members: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.dead and e.player == player and not e._token and e.role.get("formation", "") == "flank":
			members.append(e)
	members.sort_custom(func(x, y): return x.get_instance_id() < y.get_instance_id())
	var i := members.find(self)
	if i < 0:
		return now
	var yaw = player.get("yaw")
	if yaw == null:
		yaw = player.get("body_yaw")
	if yaw == null:
		return now
	var front := float(yaw) + PI                # 玩家鏡頭正前方
	var spread := deg_to_rad(Data.cfg("ai_ring_spread_deg"))
	var k := (float(i) + 0.5) / float(members.size()) - 0.5
	return wrapf(front + spread * k, -PI, PI)


## 硬直結束：被連打夠多下的小怪往後跳開
func _on_recovered(flat: Vector3) -> void:
	var hits := _combo_taken
	_combo_taken = 0
	if dead or int(role.get("escape", 0)) != 1 or hits < int(Data.cfg("ai_combo_escape_hits")):
		return
	if randf() > Data.cfg("ai_escape_chance"):
		return
	_evade_dir = -flat.normalized() if flat.length() > 0.05 else _away
	_evade_t = Data.cfg("ai_escape_time_s")
	_release_token(Data.cfg("ai_token_rest_s"))
	if _anim.has_animation(&"Walk"):
		_anim.play(&"Walk", 0.05)


## 首領依血量換階段（boss_phases.csv）
func _update_phase() -> void:
	if not Data.boss_phases.has(eid):
		return
	var ratio := hp / max_hp
	for r in Data.boss_phases[eid]:
		var p := int(r.phase)
		if p > _phase and ratio <= float(r.hp_below):
			_phase = p
			phase_row = r
			_on_phase(p)


func _on_phase(p: int) -> void:
	if phase_row.message != "":
		Game.message.emit(phase_row.message)
	Sfx.play("roar", global_position, 2.0, 0.85)
	if _anim.has_animation(&"Burst") and _state == "" and _windup <= 0.0:
		_anim.play(&"Burst", .08)
	if eid == "H09":
		if p == 2:
			if _anim.has_animation(&"Realm"):
				_anim.play(&"Realm", .08)
			Sfx.play("chant", global_position, 2.0, 0.8)
			var hz := HAZARD.new()
			world.add_child(hz)
			hz.global_position = Vector3(global_position.x, 0, global_position.z)
			hz.configure(9.0, dmg * 0.3, -1.0, true, Color(0.3, 0.6, 0.2, 0.25))
			world.track_hazard(hz)
		elif p == 3:
			_enraged = true
			hp = minf(max_hp, hp + max_hp * 0.15)
			_summon("B01", 6, 12)


## 首領放完技能後的破綻：霸體暫時消失，原地不動一小段
func _open_window() -> void:
	if phase_row.is_empty() or dead:
		return
	var t := float(phase_row.opening_s)
	if t <= 0.0:
		return
	cs.armor_broken_t = maxf(cs.armor_broken_t, t)
	_recover_t = maxf(_recover_t, t * Data.cfg("ai_opening_stand_ratio"))
	FX.float_text(world, hit_center() + Vector3(0, 1.2 * size, 0), "破綻", Color(0.6, 0.95, 1.0), 40)


func _hit_player(amount: float, h := {}) -> void:
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
	if h.is_empty():
		h = _hit_dict({})
	player.take_damage(amount, self, false, h)


func _cancel_draw() -> void:
	if _draw >= 0.0:
		_draw = -1.0
		_body_mat.emission_enabled = false
		_anim.play(&"Idle", .10)

# ------------------------------------------------------------------ 遠程 AI
func _ranged_cancel(retry: float) -> void:
	if _anim.current_animation == &"Shoot":
		_anim.play(&"Idle", .1)
	_cancel_draw()
	_body_mat.emission_enabled = false
	_lock = Vector3.INF
	_rstate = "move"
	_aim_cd = maxf(_aim_cd, retry)


func _aiming_count() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and not e.dead and e._rstate == "aim":
			n += 1
	return n


func _ranged(delta: float, flat: Vector3, dist: float) -> void:
	var target: Vector3 = player.global_position + Vector3.UP
	var blocked := not _clear_shot()
	match _rstate:
		"aim":
			velocity.x = 0
			velocity.z = 0
			_rt += delta
			var locked: bool = _rt >= ai.windup_s - ai.lock_s
			# 鎖定前：被逼近、斷了視線或超出射程就收手後撤；鎖定後一定出手（玩家看到紅光就該閃）。
			if not locked and (blocked or dist > ai.max_m or dist < ai.panic_m):
				_ranged_cancel(0.5)
				return
			if locked and not _lock.is_finite():
				_lock = player.global_position
			var aim_at: Vector3 = _lock + Vector3.UP if locked else target
			var f := aim_at - global_position
			if Vector2(f.x, f.z).length() > 0.05:
				rotation.y = atan2(-f.x, -f.z)
			var k: float = clampf(_rt / ai.windup_s, 0.0, 1.0)
			_body_mat.emission_enabled = true
			_body_mat.emission = Color(1.0, 0.12, 0.08) if locked else Color(.85, .58, .18) * (0.35 + 0.65 * k)
			if _bow:
				_draw = k * Bow.RELEASE
				_anim.seek(_draw, true)
				_bow.pose(_draw, aim_at)
			if _rt >= ai.windup_s:
				_ranged_fire(dist)
				_rstate = "recover"
				_rt = 0.0
				_body_mat.emission_enabled = false
			return
		"recover":
			velocity.x = 0
			velocity.z = 0
			_rt += delta
			if _bow:
				_draw = Bow.RELEASE + (_rt / ai.recover_s) * (Bow.FINISH - Bow.RELEASE)
				_anim.seek(minf(_draw, Bow.FINISH), true)
				_bow.pose(_draw, _lock + Vector3.UP)
			if _rt >= ai.recover_s:
				_cancel_draw()
				_lock = Vector3.INF
				_rstate = "move"
				_aim_cd = randf_range(ai.cd_min_s, ai.cd_max_s)
			return
	# 走位
	_aim_cd -= delta
	if _bow:
		_bow.pose(-1.0, target)
	_reposition(delta, flat, dist, blocked)
	var cornered: bool = _stuck_t > 0.5 and dist < ai.min_m
	if _aim_cd <= 0.0:
		var in_band: bool = dist <= ai.max_m and (dist >= ai.panic_m or cornered)
		if blocked or not in_band:
			_aim_cd = 0.25
		elif _aiming_count() >= int(Data.cfg("ai_ranged_max_aiming")) or randf() > ai.attack_chance or (not _onscreen() and randf() > Data.cfg("ai_offscreen_attack_chance")):
			_aim_cd = randf_range(Data.cfg("ai_ranged_retry_min"), Data.cfg("ai_ranged_retry_max"))
		else:
			_rstate = "aim"
			_rt = 0.0
			_lock = Vector3.INF
			Sfx.play("archer_draw" if eid == "H02" else "enemy_windup", hit_center())
			velocity.x = 0
			velocity.z = 0
			_anim.play(&"Shoot", 0 if _bow else 0.05)
			if _bow:
				_draw = 0.0
				_anim.seek(0, true)
				_anim.pause()


# 依距離決定走位：太近後撤（退不動就橫移）、太遠或被擋住就靠近、在舒適距離內繞著玩家橫移。
func _reposition(delta: float, flat: Vector3, dist: float, blocked: bool) -> void:
	var toward := flat.normalized() if dist > 0.01 else Vector3.FORWARD
	var side := Vector3(-toward.z, 0, toward.x) * _strafe
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe = -_strafe
		_strafe_t = randf_range(0.7, 1.3) * ai.strafe_s
	var moved := Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
	_last_pos = global_position
	var want := Vector3.ZERO
	var mult := 1.0
	if blocked:
		_chase(flat, dist, ai.pref_m, true)
		return
	if dist < ai.min_m:
		want = -toward + side * (0.6 if _stuck_t > 0.4 else 0.25)
		mult = ai.retreat_mult
	elif dist > ai.max_m:
		want = toward
	elif dist > ai.pref_m + 2.0:
		want = toward * 0.7 + side * 0.5
	else:
		var drift := clampf((dist - ai.pref_m) / 2.0, -1.0, 1.0)
		want = side * 0.8 + toward * drift * 0.4
		mult = 0.7
		var cover := _cover_point()
		if cover.is_finite():
			var to_cover := cover - global_position
			to_cover.y = 0
			if to_cover.length() > 1.2:
				want = to_cover.normalized() + side * 0.25
				mult = 0.9
	if want.is_zero_approx():
		velocity.x = 0
		velocity.z = 0
		return
	want = want.normalized()
	var here := Vector2(global_position.x, global_position.z)
	var step := _ground_direction(here + Vector2(want.x, want.z) * 3.0)
	var dir := Vector3(step.x, 0, step.y)
	if dir.is_zero_approx() or (moved < _speed() * delta * 0.2 and velocity.length() > 0.1):
		_stuck_t += delta
		if _stuck_t > 0.4:
			_strafe = -_strafe
			_strafe_t = ai.strafe_s
	else:
		_stuck_t = maxf(0.0, _stuck_t - delta)
	dir = (dir + _separation() * 0.8).limit_length()
	velocity.x = dir.x * _speed() * mult
	velocity.z = dir.z * _speed() * mult


## 遠程：附近有刀盾手時，站到他背後（玩家 → 刀盾手 的延長線上）
func _cover_point() -> Vector3:
	var best = null
	var best_d := Data.cfg("ai_cover_scan_m")
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead or e.role.get("formation", "") != "front":
			continue
		var d: float = e.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return Vector3.INF
	var v: Vector3 = best.global_position - player.global_position
	v.y = 0
	if v.length() < 0.1:
		return Vector3.INF
	var pt: Vector3 = best.global_position + v.normalized() * Data.cfg("ai_cover_offset_m")
	var d_p := Vector2(pt.x - player.global_position.x, pt.z - player.global_position.z).length()
	return pt if d_p <= ai.max_m else Vector3.INF


func _ranged_fire(dist: float) -> void:
	var at: Vector3 = _lock if _lock.is_finite() else player.global_position
	Sfx.play("archer_release" if eid == "H02" else "throw", hit_center())
	match eid:
		"H02":
			_bow.pose(Bow.RELEASE, at + Vector3.UP)
			_shoot(24.0, dmg, Color(0.9,0.8,0.5), false, _bow.tip_position(), at)
		"H04":
			_shoot(14.0, dmg, Color(0.4, 0.9, 0.3), false, Vector3.INF, at)
		"H05":
			_shoot(12.0, dmg * 0.6, Color(0.3, 0.8, 0.2), true, Vector3.INF, at)


func _shoot(speed_mps: float, amount: float, color: Color, cloud := false, arrow_tip := Vector3.INF, at := Vector3.INF) -> void:
	var p := PROJ.new()
	world.add_child(p)
	var from := global_position + Vector3(0, 1.3 * size, 0)
	var ground: Vector3 = at if at.is_finite() else player.global_position
	var target: Vector3 = ground + Vector3(0, 1.0, 0)
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
		p.target_pos = Vector3(ground.x, 0.2, ground.z)
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
	_anim.play(&"Burst", .05)
	world.warn_area(center, r, delay)
	Sfx.play("aoe_warn", center)
	await get_tree().create_timer(delay, false).timeout
	if dead or not is_instance_valid(player):
		return
	var d := Vector2(player.global_position.x - center.x, player.global_position.z - center.z).length()
	FX.impact_wave(world,center,r,.3,Color(1,.4,.2))
	FX.burst(world, center + Vector3.UP * .2, Vector3.UP, Color(.6, .55, .5, .55), 18, "dust", 5.0, 1.6)
	Sfx.play("aoe_boom", center)
	Feel.shake(float(Data.feel.shake_boom) * clampf(1.0 - d / (r * 3.0), 0.2, 1.0))
	if d <= r:
		player.take_damage(amount, self, false, {"hitstun_s": 0.4, "launch": 1, "launch_h_m": CombatState.cfg("enemy_aoe_launch_h_m"), "push_m": CombatState.cfg("enemy_aoe_push_m")})
	_open_window()


func _summon(id: String, n: int, cap: int) -> void:
	_anim.play(&"Summon", .08)
	summons = summons.filter(func(s): return is_instance_valid(s) and not s.dead)
	for i in n:
		if summons.size() >= cap:
			break
		var ang := randf() * TAU
		var pos := global_position + Vector3(cos(ang), 0, sin(ang)) * randf_range(2.0, 4.0)
		var e = world.spawn_enemy(id, pos, false)
		if e:
			e.summoner = self
			summons.append(e)
	_open_window()


# ------------------------------------------------------------------ 專屬行為
func _behaviour(delta: float, flat: Vector3, dist: float) -> void:
	var rate := float(phase_row.get("skill_rate", 1.0))
	_skill_cd -= delta * rate
	_skill2_cd -= delta * rate
	match eid:
		"Z02": _b_hopper(delta, flat, dist)
		"Z05":
			if hp < max_hp * 0.5 and not _enraged:
				_enraged = true
				Sfx.play("roar", global_position)
				Game.message.emit("天魔護法狂暴！")
			if _skill_cd <= 0.0:
				_skill_cd = 8.0
				Sfx.play("roar", global_position, -3.0, 1.15)
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
				Sfx.play("chant", global_position)
				Game.message.emit("暗月樓主結印：影衛現身！")
				_summon("H06", 6, 10)
			_chase(flat, dist)
			_melee(delta, dist)
		"H02":
			_ranged(delta, flat, dist)
		"H04":
			_ranged(delta, flat, dist)
			if _skill2_cd <= 0.0:
				_skill2_cd = 6.0
				_raise_corpse()
		"H05":
			_ranged(delta, flat, dist)
		"H06":
			if not _revealed and dist < 3.0:
				_revealed = true
				Sfx.play("assassin_reveal", global_position)
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
				Sfx.play("horn", global_position)
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
			if _skill_cd <= 0.0 and dist < 9.0 and dist > 2.0 and is_on_floor() and _windup <= 0.0 and _skill_ok():
				_state = "windup"
				Sfx.play("roar" if eid == "B06" or eid == "B02" else "enemy_windup", hit_center(), -4.0)
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
				_anim.play(&"Leap", .05)
				var d := flat.normalized() * minf(dist, 6.0) / 0.8
				velocity = Vector3(d.x, 7.0, d.z)
		"hop":
			if is_on_floor() and velocity.y <= 0.0:
				_state = ""
				_skill_cd = 3.0
				var impact_radius := 2.0 + hit_radius
				if dist < impact_radius:
					_hit_player(dmg, _skill_hit("hop"))
				FX.impact_wave(world, global_position, impact_radius, 0.2, Color(0.6, 0.6, 0.4))


func _b_boar(delta: float, flat: Vector3, dist: float) -> void:
	match _state:
		"":
			_chase(flat, dist)
			_melee(delta, dist)
			if _skill_cd <= 0.0 and dist < 14.0 and dist > 3.0 and _windup <= 0.0 and _skill_ok():
				_state = "windup"
				Sfx.play("roar" if eid == "B06" or eid == "B02" else "enemy_windup", hit_center(), -4.0)
				_state_t = 1.0
				_move_dir = flat.normalized()
				world.warn_area(global_position + _move_dir * 3.0, 0.8, 1.0)
		"windup":
			_state_t -= delta
			velocity.x = 0
			velocity.z = 0
			_visual.position.z = sin(_state_t * 30.0) * 0.08
			if _state_t <= 0.0:
				_visual.position.z = 0
				_state = "charge"
				_anim.play(&"Charge", .05)
				_state_t = 1.4
				_charge_hit = false
		"charge":
			_state_t -= delta
			velocity.x = _move_dir.x * 13.0
			velocity.z = _move_dir.z * 13.0
			if not _charge_hit and dist < 1.4:
				_charge_hit = true
				_hit_player(dmg * 1.6, _skill_hit("charge"))
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
			if _skill_cd <= 0.0 and dist < 12.0 and _skill_ok():
				_state = "dive"
				_anim.play(&"Dive", .05)
				_state_t = 1.5
				_charge_hit = false
		"dive":
			_state_t -= delta
			var tp: Vector3 = player.global_position + Vector3(0, 1.2, 0)
			var d := (tp - global_position).normalized() * 9.0
			velocity = d
			if not _charge_hit and global_position.distance_to(tp) < 1.0:
				_charge_hit = true
				_hit_player(dmg, _skill_hit("dive"))
				_state_t = 0.0
			if _state_t <= 0.0:
				_state = ""
				_skill_cd = 4.0


func _b_tiger(delta: float, flat: Vector3, dist: float) -> void:
	match _state:
		"":
			_chase(flat, dist)
			_melee(delta, dist)
			if _skill_cd <= 0.0 and dist < 12.0 and dist > 3.0 and is_on_floor() and _windup <= 0.0 and _recover_t <= 0.0 and _skill_ok():
				_state = "windup"
				Sfx.play("roar" if eid == "B06" or eid == "B02" else "enemy_windup", hit_center(), -4.0)
				_state_t = 0.6
				_visual.scale = Vector3(1.1, 0.75, 1.1)
		"windup":
			_state_t -= delta
			velocity.x = 0
			velocity.z = 0
			if _state_t <= 0.0:
				_visual.scale = Vector3.ONE
				_state = "hop"
				_anim.play(&"Leap", .05)
				var d := flat.normalized() * dist / 0.8
				velocity = Vector3(d.x, 6.0, d.z)
		"hop":
			if is_on_floor() and velocity.y <= 0.0:
				_state = ""
				_skill_cd = 6.0
				var impact_radius := 2.5 + hit_radius
				if dist < impact_radius:
					_hit_player(dmg * 1.2, _skill_hit("pounce"))
				FX.impact_wave(world, global_position, impact_radius, 0.2, Color(1, 0.7, 0.3))


func _b_blade(delta: float, flat: Vector3, dist: float) -> void:
	match _state:
		"":
			_chase(flat, dist)
			_melee(delta, dist)
			if _skill_cd <= 0.0 and dist < 12.0 and _windup <= 0.0 and _recover_t <= 0.0 and _skill_ok():
				_state = "windup"
				Sfx.play("roar" if eid == "B06" or eid == "B02" else "enemy_windup", hit_center(), -4.0)
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
				_anim.play(&"Dash", .05)
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
					_hit_player(dmg, _skill_hit("dash"))


func _b_final(delta: float, flat: Vector3, dist: float) -> void:
	# 階段變化（領域、狂暴）在 _on_phase，門檻在 boss_phases.csv
	if _phase == 1 and _skill2_cd <= 0.0:
		_skill2_cd = 25.0
		_summon("B02", 2, 3)
	if _skill_cd <= 0.0 and dist < 12.0:
		_skill_cd = 10.0 if _phase < 3 else 7.0
		_aoe_after(player.global_position, 3.5, 1.5, dmg * 1.2)
	_chase(flat, dist)
	_melee(delta, dist)


func _raise_corpse() -> void:
	if _rstate == "move":
		_anim.play(&"Summon", .08)
	var pos: Vector3 = world.take_corpse_near(global_position, 12.0)
	if pos == Vector3.INF:
		pos = global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	FX.play(world, pos + Vector3(0, 0.5, 0), &"poof", 1.68, 0.3, Color(0.4, 1, 0.4))
	Sfx.play("chant", global_position)
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


## 只動顯示層：腳下碰撞與敵人正在播放的招式保持同步。
func _react_to_hit(away: Vector3, weight: float, guard: bool) -> void:
	if _draw < 0 and (_anim.current_animation in [&"Idle", &"Walk", &"Hit"] or not _anim.is_playing()):
		_anim.play(&"Hit", .03)
	if _recoil:
		_recoil.kill()
	var right := global_basis.x
	if is_instance_valid(player):
		right = player.cam.global_basis.x
	right = (global_basis.inverse() * right).slide(Vector3.UP).normalized()
	var side := (global_basis * right).dot(away)
	_hit_side = signf(side) if absf(side) > .25 else -_hit_side
	var force := clampf(weight, .65, 2.0) * (.65 if guard or rank == "boss" else 1.0)
	var offset := right * _hit_side * force * .12 * size
	var roll := Vector3.UP.cross(right) * _hit_side * force * .14
	for mesh in _flash_meshes:
		mesh.material_overlay = _flash
	# 受擊閃白：全白維持 flash_hold，再淡出；暴擊（weight 已乘 1.5）更亮
	_flash.albedo_color = Color(1, 1, 1, .95 if weight >= 1.4 else .82)
	var sq := float(Data.feel.squash) * clampf(force, .5, 1.6) * (.5 if rank == "boss" else 1.0)
	var squash := Vector3(1.0 + sq * .8, 1.0 - sq, 1.0 + sq * .8)
	var stretch := Vector3(1.0 - sq * .35, 1.0 + sq * .45, 1.0 - sq * .35)
	var hold := float(Data.feel.flash_hold_s)
	var fade := float(Data.feel.flash_fade_s)
	_recoil = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_recoil.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil.tween_property(_impact_pivot, "position", offset, .04)
	_recoil.parallel().tween_property(_impact_pivot, "rotation", roll, .04)
	_recoil.parallel().tween_property(_impact_pivot, "scale", squash, .04)
	_recoil.tween_interval(maxf(0.0, hold - .04))
	_recoil.tween_property(_impact_pivot, "position", -offset * .68, .075)
	_recoil.parallel().tween_property(_impact_pivot, "rotation", -roll * .68, .075)
	_recoil.parallel().tween_property(_impact_pivot, "scale", stretch, .075)
	_recoil.parallel().tween_property(_flash, "albedo_color", Color(1, .1, .1, .35), fade * .5)
	_recoil.tween_property(_impact_pivot, "position", Vector3.ZERO, .095)
	_recoil.parallel().tween_property(_impact_pivot, "rotation", Vector3.ZERO, .095)
	_recoil.parallel().tween_property(_impact_pivot, "scale", Vector3.ONE, .12).set_trans(Tween.TRANS_BACK)
	_recoil.parallel().tween_property(_flash, "albedo_color:a", 0.0, fade * .5)
	_recoil.tween_callback(func():
		for mesh in _flash_meshes:
			mesh.material_overlay = _body_mat)


## 被玩家擊中：回傳實際造成的傷害
func take_hit(amount: float, from_pos: Vector3, crit: bool, weight := 1.0, hit := {}) -> float:
	if dead or not cs.hittable():
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
					FX.float_text(world, hit_center() + Vector3(0, 0.8, 0), "格", UIKit.TEAL, 36)
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
	last_hit_metal = (eid == "H03" and front) or eid == "Z04"
	_away = -to_attacker if not to_attacker.is_zero_approx() else _away
	var dealt := _apply_damage(dmg_in, crit, false)
	if dealt > 0 and not dead:
		_react_to_hit(-to_attacker, weight * (1.5 if crit else 1.0), eid == "H03" and front)
		if hit.is_empty():
			# 沒有招式資料的傷害（武學的追加傷害等）：用通用的小擊退
			var kv := float(Data.feel.knock_speed) * clampf(weight, .5, 2.0) * (float(Data.feel.knock_crit_mult) if crit else 1.0)
			_knock += _away * kv * _knock_mass() * (.4 if last_hit_metal else 1.0)
		else:
			# 狀態屬性：硬直、浮空、破霸體、擊倒；擊退距離由招式的 push_m 決定，受擊、浮空、倒地都會退
			var armored := cs.armor_always and cs.armor_broken_t <= 0.0
			var res: Dictionary = cs.apply_hit(hit)
			if float(res.launch_v) > 0.0:
				velocity.y = float(res.launch_v)
			if res.taken:
				_combo_taken += 1
			if armored and cs.armor_broken_t > 0.0:
				_broken_by_hit = true
				_counter_t = 0.0
			var dist := float(hit.get("push_m", 0.0)) * _knock_mass()
			if res.absorbed:
				dist *= float(Data.feel.knock_armor_mult)
			# _knock 是逐幀衰減的速度：初速 = 距離 × 衰減率，總位移剛好是這段距離
			_knock = CombatState.push_dir(hit, global_position, _away) * dist * float(Data.feel.knock_decay)
	return dealt


func take_poison_tick(amount: float) -> void:
	if cs.hittable():
		_apply_damage(amount, false, true)


func _apply_damage(v: float, crit: bool, dot: bool) -> float:
	if dead:
		return 0.0
	if not dot:
		var contact := hit_center()
		if is_instance_valid(player):
			contact += contact.direction_to(player.cam.global_position) * hit_radius
		FX.play(world, contact, &"crit-hit" if crit else &"hit-spark", (1.55 if crit else 0.76) * size, 0.24 if crit else 0.14)
		# 第一人稱看得到：火花往攻擊者那側與上方噴，血墨往側上方灑
		var side := _away.cross(Vector3.UP).normalized() * (1.0 if randf() < .5 else -1.0)
		var out := (-_away * .55 + side * .45 + Vector3.UP * .6).normalized()
		var metal := last_hit_metal
		FX.burst(world, contact, out, Color(1, .92, .6) if not metal else Color(.8, .95, 1), int(Data.feel.particles_crit if crit else Data.feel.particles_hit), "spark", 11.0 if crit else 7.0)
		if not metal:
			FX.burst(world, contact, out, Color(.45, .02, .05, .95), 6 if not crit else 12, "ink", 5.0)
	hp -= v
	var col := UIKit.EMBER if crit else (Color(0.5, 1, 0.4) if dot else UIKit.BONE)
	if Settings.on("damage_numbers") and (not dot or randf() < 0.15):
		FX.damage_number(world, hit_center() + Vector3(0, 0.6 * size, 0), int(v), crit, col)
	if hp <= 0.0:
		if eid == "Z06" and not _revived and not _last_hit_from_behind:
			_revived = true
			hp = max_hp * 0.3
			Game.message.emit("罩門未破，鬼面屍王再起！（繞到背後攻擊罩門）")
			return v
		die()
	return v


func die() -> void:
	_token = false
	if dead:
		return
	dead = true
	FX.play(world, hit_center(), &"poof", 1.4 * size, 0.36)
	FX.burst(world, hit_center(), (Vector3.UP * .8 + _away * .3).normalized(), Color(.42, .02, .05, .95), int(Data.feel.particles_kill), "ink", 7.0, 1.2)
	FX.burst(world, global_position + Vector3.UP * .3, Vector3.UP, Color(.55, .52, .5, .5), 8, "dust", 3.0, size)
	Sfx.play("enemy_death", global_position)
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
	_death_fling()


## 擊殺後屍身被打飛、壓扁、縮小再消失（不再有碰撞）
func _death_fling() -> void:
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	if _label:
		_label.hide()
	if _recoil:
		_recoil.kill()
	for mesh in _flash_meshes:
		mesh.material_overlay = _flash
	_flash.albedo_color = Color(1, 1, 1, .9)
	var dur := float(Data.feel.death_fling_s)
	var dist := float(Data.feel.death_fling_m) * _knock_mass() ** 0.5
	var local_away := global_basis.inverse() * _away
	# 擊殺也會打飛。飛行方向只控制位移，仰面角度由外觀節點統一負責。
	_anim.play(&"Death", 0)
	var t := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_impact_pivot, "scale", Vector3(1.25, .7, 1.25), .05)
	t.tween_property(_impact_pivot, "position", local_away * dist + Vector3.UP * .35, dur)
	t.parallel().tween_property(_impact_pivot, "rotation", Vector3.ZERO, .05)
	t.parallel().tween_property(_pose, "rotation:x", CombatState.airborne_pitch(), dur * .35).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_impact_pivot, "scale", Vector3.ONE * .15, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_flash, "albedo_color", Color(.1, 0, 0, .8), dur)
	t.tween_callback(queue_free)
