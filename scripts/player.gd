extends CharacterBody3D

const MELEE_EFFECTS := {"劍": &"thrust", "槍": &"thrust", "棍": &"spin-slash", "鞭": &"whip-crack", "鉤": &"double-slash", "拳": &"blunt-hit", "巨劍": &"heavy-cleave"}
const SWEEP_DEGREES := {"刀": 120.0, "棍": 360.0, "拳": 60.0, "鉤": 90.0, "巨劍": 140.0, "扇": 50.0, "鞭": 360.0}
const THRUST_HALF_WIDTH := 0.9
## 第一人稱玩家：移動、主副武器切換與攻擊、受傷流程，以及武學／門派／境界的戰鬥效果

signal hp_changed
signal died
signal interact_pressed

const GRAVITY := 18.0
const JUMP_V := 7.5
const MOUSE_SENS := 0.0025
const PROJ := preload("res://scripts/projectile.gd")

var hp := 100.0
var shield := 0.0
var cam: Camera3D
var weapon_models: Array = [null, null]   # 對應 Game.weapons；只有手上那把可見
var queued_press := [false,false]
var cooldowns := [0.0, 0.0]
var swap_t := 0.0                          # 切換武器的收出時間，期間不能出招
var switch_request := -9                   # 待切換的武器格（-9＝無）
var yaw := 0.0
var pitch := 0.0
var dash_t := 0.0
var dash_cd := 0.0
var invuln_t := 0.0
var last_dodge_t := -99.0
var dodge_crit_ready := false
var attack_count := 0
var kill_stacks: Array = []        # 每層的剩餘時間（鐵砂掌・圓滿）
var cheat_cd := 0.0
var demon_t := 0.0                 # 天魔降世／血魔附體 剩餘時間
var demon_cd := 0.0
var demon_speed := false
var array_t := 0.0                 # 萬劍朝宗劍陣
var guard_ready := true
var guard_t := 0.0
var shield_t := 0.0
var palm_t := 0.0
var bagua_t := 0.0
var zhengqi_t := 0.0
var taiji_t := 0.0
var taiji_active := 0.0
var yinyang_t := 0.0
var yang := true
var arhat_t := 0.0
var arhat_nodes: Array = []
var regen_acc := 0.0
var still_t := 0.0
var input_enabled := true
# 弓：按住左鍵拉弓、放開射出；右鍵瞄準
var bow_t := 0.0                   # 這一箭按住多久
var bow_held := false
var aim := 0.0                     # 瞄準程度 0~1（平滑過渡）
var arrow_speed_mult := 1.0        # 滿弓箭速較快
var arrow_spread_deg := 0.0        # 這一箭的散射半角；拉越滿越小
# 經脈全通的特殊效果
var du_charged := false            # 督脈貫頂：下一擊必暴＋增傷
var ren_cd := 0.0                  # 任脈歸元冷卻
var chong_t := 0.0                 # 氣血奔湧剩餘時間
var dai_t := 0.0                   # 束脈護體剩餘時間
var dai_cd := 0.0
var qiao_ready := false            # 蹻捷如風：衝刺後下一擊增傷
const BASE_FOV := 80.0


# 打擊感與音效
var _imp := {"crit": false, "kill": false, "metal": false}
# 第三人稱戰鬥（docs/combat-design.md）
const FIGHTER := preload("res://scripts/fighter_model.gd")
const RUNNER := preload("res://scripts/move_runner.gd")
var cs := CombatState.new()        # 六種狀態
var runner = RUNNER.new()          # 招式執行器
var model                          # 角色模型
var pivot: Node3D                  # 鏡頭俯仰軸（在角色肩膀高度）
var body_yaw := 0.0                # 模型朝向（世界座標）
var hit_guard := 0.0               # 受擊保護剩餘時間
var _cur_hit := {}                 # 這次 deal() 要帶給敵人的狀態屬性
var _down_anim_t := 0.0
var _was_floor := true
var _fall_v := 0.0
var _step_m := 0.0
var _beat_t := 0.0

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	# 第三人稱：玩家節點的 yaw 就是鏡頭水平方向；模型另外轉向移動或出招方向
	pivot = Node3D.new()
	pivot.position = Vector3(0, CombatState.cfg("cam_height_m"), 0)
	add_child(pivot)
	cam = Camera3D.new()
	cam.position = Vector3(CombatState.cfg("cam_side_m"), 0.25, CombatState.cfg("cam_dist_m"))
	cam.fov = BASE_FOV
	cam.far = 300.0
	pivot.add_child(cam)
	cam.current = true
	pitch = -0.18
	pivot.rotation.x = pitch
	model = FIGHTER.new()
	model.top_level = true
	add_child(model)
	model.setup(Game.char_id, String(Data.characters[Game.char_id].weapon_id))
	runner.setup(self, Game.char_id)
	hp = Game.max_hp()
	Game.stats_changed.connect(_on_stats_changed)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_stats_changed() -> void:
	hp = minf(hp, Game.max_hp())
	hp_changed.emit()


const ACTIONS := ["attack", "skill1", "skill2", "skill3", "skill4", "skill5", "skill6", "skill7", "ult"]


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENS * Settings.get_value("mouse_sens")
		yaw -= event.relative.x * sens
		pitch = clampf(pitch - event.relative.y * sens, -1.2, 0.7)
		rotation.y = yaw
		pivot.rotation.x = pitch
	elif event.is_action_pressed("interact"):
		interact_pressed.emit()
	else:
		for a in ACTIONS:
			if event.is_action_pressed(a):
				use(a)
				break


## 出招（普攻、技能、大招）；不能操控的狀態下無效
func use(action: String) -> void:
	if hp <= 0.0 or not cs.can_act() or dash_t > 0.0:
		return
	runner.press(action)


## 鏡頭的水平前方
func aim_flat() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


## 準星指向的世界座標（最遠 max_m）
func aim_point(max_m: float) -> Vector3:
	var from := cam.global_position
	var to := from - cam.global_basis.z * (max_m + CombatState.cfg("cam_dist_m"))
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q) if is_inside_tree() else {}
	return hit.position if not hit.is_empty() else to


## 從 origin 射向準星的方向
func aim_dir(origin: Vector3) -> Vector3:
	var d := aim_point(40.0) - origin
	return d.normalized() if d.length() > 0.5 else aim_flat()


func face(d: Vector3) -> void:
	if d.length() > 0.01:
		body_yaw = atan2(-d.x, -d.z)


func shoot(pos: Vector3, d: Vector3, dmg: float, pierce: int, rng: float, color: Color, hit: Dictionary) -> void:
	var w := String(Data.characters[Game.char_id].weapon_id)
	_shoot(pos, d, dmg, pierce, rng, color, w if w == "W006" else "", hit)


func _physics_process(delta: float) -> void:
	_timers(delta)
	hit_guard = maxf(0.0, hit_guard - delta)
	cs.tick(delta, is_on_floor())
	var can := cs.can_act() and hp > 0.0
	if not can and runner.busy():
		runner.interrupt()
	var lunge: Vector3 = runner.update(delta) if can else Vector3.ZERO
	var dir := Vector3.ZERO
	if input_enabled and can:
		var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		dir = (transform.basis * Vector3(iv.x, 0, iv.y)).normalized()
		if Input.is_action_just_pressed("dash") and dash_cd <= 0.0 and not (runner.busy() and runner.move.slot == "ult"):
			runner.interrupt()
			dash_t = CombatState.cfg("dodge_time_s")
			dash_cd = CombatState.cfg("dodge_cd_s")
			Sfx.play("dash")
			if Game.special_on("yangqiao"):   # 陽蹻脈・蹻捷如風
				dash_cd *= 1.0 - Game.special("yangqiao", "a") / 100.0
				qiao_ready = true
			cs.give_invincible(CombatState.cfg("dodge_invincible_s"))
			_dash_dir = dir if dir != Vector3.ZERO else Vector3(-sin(body_yaw), 0, -cos(body_yaw))
			face(_dash_dir)
			model.play("Sprint_Loop", 1.6, 0.0, 0.05, true)      # 閃避：身體前傾衝一小段（傾角在 _animate）
		if Input.is_action_just_pressed("jump") and is_on_floor() and not runner.busy() and dash_t <= 0.0:
			velocity.y = JUMP_V
			Sfx.play("jump")
	var spd := Game.move_speed()
	if dash_t > 0.0:
		dir = _dash_dir
		spd *= CombatState.cfg("dodge_speed_mult")
	elif runner.busy():
		dir = Vector3.ZERO
	if lunge != Vector3.ZERO:
		velocity.x = lunge.x
		velocity.z = lunge.z
	else:
		velocity.x = move_toward(velocity.x, dir.x * spd, 60.0 * delta)
		velocity.z = move_toward(velocity.z, dir.z * spd, 60.0 * delta)
	if not is_on_floor():
		velocity.y -= (CombatState.cfg("air_gravity") if cs.base == CombatState.S.AIR else GRAVITY) * delta
		_fall_v = minf(_fall_v, velocity.y)
	move_and_slide()
	if dir != Vector3.ZERO and not runner.busy():
		face(dir)
	still_t = still_t + delta if Vector2(velocity.x, velocity.z).length() < 0.5 else 0.0
	_move_sounds(delta)
	if global_position.y < -10.0:
		global_position.y = 2.0
		velocity = Vector3.ZERO
	_update_camera()
	_animate(delta)


var _dash_dir := Vector3.FORWARD


func _update_camera() -> void:
	## 鏡頭被牆擋住時往前收
	var want := Vector3(CombatState.cfg("cam_side_m"), 0.25, CombatState.cfg("cam_dist_m"))
	if is_inside_tree():
		var from := pivot.global_position
		var to := pivot.global_transform * want
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var k: float = clampf((from.distance_to(hit.position) - 0.25) / from.distance_to(to), 0.12, 1.0)
			want *= k
	cam.position = cam.position.lerp(want, 0.35)


func _animate(delta: float) -> void:
	model.global_position = global_position
	var m_rot: float = model.rotation.y
	model.rotation.y = lerp_angle(m_rot, body_yaw, minf(1.0, delta * 18.0))
	var S := CombatState.S
	var lean := -deg_to_rad(CombatState.cfg("dodge_lean_deg")) if dash_t > 0.0 and hp > 0.0 else 0.0
	model.rotation.x = lerpf(model.rotation.x, lean, minf(1.0, delta * 22.0))
	if hp <= 0.0:
		model.play("Death01", 1.0, 0.0, 0.1)
		return
	match cs.base:
		S.HIT:
			model.play("Hit_Chest", 1.0, 0.0, 0.04)
			return
		S.AIR:
			model.hold("Hit_Knockback", 0.45)
			_down_anim_t = 0.0
			return
		S.DOWN:
			model.hold("Hit_Knockback", 0.83)
			_down_anim_t = 0.0
			return
	if _down_anim_t >= 0.0 and cs.inv_t > 0.0 and model.current.ends_with("@hold"):
		model.play("LayToIdle", 2.4, 0.0, 0.08, true)      # 起身
		return
	if model.current == "LayToIdle" and model.anim.is_playing():
		return
	if runner.busy() or (dash_t > 0.0):
		return
	if not is_on_floor():
		model.play("Jump_Loop", 1.0, 0.0, 0.1)
		return
	if model.current == "Sprint":
		model.current = ""
	var speed2 := Vector2(velocity.x, velocity.z).length()
	if speed2 > 0.6:
		model.play("Jog_Fwd_Loop", clampf(speed2 / 4.2, 0.7, 1.6))
	else:
		model.play(model.idle)


func is_bow() -> bool:
	return false


func atk_speed_now() -> float:
	var atk_speed := Game.st("atk_speed_pct")
	if taiji_active > 0.0:
		atk_speed += 50.0
	if demon_speed:
		atk_speed += 100.0
	if chong_t > 0.0:   # 衝脈・氣血奔湧
		atk_speed += Game.special("chong", "a")
	return atk_speed


func _bow_interval(a: int) -> float:
	var atk_speed := atk_speed_now()
	return float(Data.weapons[Game.weapons[a].id].interval_s) / (1.0 + atk_speed / 100.0)


func bow_draw() -> float:
	## 目前拉弓程度 0~1（HUD 準星用）
	if not bow_held or not is_bow():
		return 0.0
	var iv := _bow_interval(Game.active_weapon)
	var load_s := iv * Data.cfg("bow_load_frac")
	return clampf((bow_t - load_s) / (iv * Data.cfg("bow_draw_frac")), 0.0, 1.0)


func bow_spread_deg(draw := -1.0) -> float:
	## 箭的散射半角（度）：拉越滿越小，瞄準時再縮小。HUD 的紅圈就畫這個範圍
	if draw < 0.0:
		draw = bow_draw()
	var deg := lerpf(Data.cfg("bow_spread_max_deg"), Data.cfg("bow_spread_min_deg"), clampf(draw, 0.0, 1.0))
	return deg * lerpf(1.0, Data.cfg("bow_aim_spread_mult"), aim)


func _spread_dir(d: Vector3, half_deg: float) -> Vector3:
	## 在半角 half_deg 的圓錐內均勻取一個方向
	var r := tan(deg_to_rad(half_deg)) * sqrt(randf())
	var th := randf() * TAU
	return (d + (cam.global_basis.x * cos(th) + cam.global_basis.y * sin(th)) * r).normalized()


func _count_du() -> void:
	## 督脈・督脈貫頂：每出招 a 次，下一擊必暴並增傷
	if Game.special_on("du") and attack_count % int(Game.special("du", "a")) == 0:
		du_charged = true


func _timers(delta: float) -> void:
	dash_t -= delta
	dash_cd -= delta
	invuln_t -= delta
	cheat_cd -= delta
	demon_cd -= delta
	ren_cd -= delta
	chong_t -= delta
	dai_t -= delta
	dai_cd -= delta
	array_t -= delta
	if demon_t > 0.0:
		demon_t -= delta
		if demon_t <= 0.0:
			demon_speed = false
	for i in range(kill_stacks.size() - 1, -1, -1):
		kill_stacks[i] -= delta
		if kill_stacks[i] <= 0.0:
			kill_stacks.remove_at(i)
	# 回血
	if Game.st("hp_regen") > 0.0 and hp < Game.max_hp():
		heal(Game.st("hp_regen") * delta, false)
	# 金鐘罩・小成：每 10 秒一層護體
	if Game.f("guard_every") > 0.0 and not guard_ready:
		guard_t += delta
		if guard_t >= Game.f("guard_every"):
			guard_ready = true
			guard_t = 0.0
	# 少林・金剛護體：每 8 秒 30% 生命護盾
	if Game.f("shield_every8") > 0.0:
		shield_t += delta
		if shield_t >= 8.0:
			shield_t = 0.0
			shield = maxf(shield, Game.max_hp() * 0.3)
			hp_changed.emit()
	# 金剛伏魔掌：每 10 秒在敵人最密集處拍下巨掌
	if Game.f("palm_pct") > 0.0:
		palm_t += delta
		if palm_t >= 10.0:
			palm_t = 0.0
			var c := _densest_point(15.0)
			if c != Vector3.INF:
				_aoe(c, 6.0, ref_hit() * Game.f("palm_pct") / 100.0, Color(1.0, 0.8, 0.3))
	# 八卦遊身掌・圓滿：每 5 秒八卦氣場
	if Game.f("bagua_pulse") > 0.0:
		bagua_t += delta
		if bagua_t >= 5.0:
			bagua_t = 0.0
			_aoe(global_position, 4.0, ref_hit() * Game.f("bagua_pulse"), Color(0.6, 0.9, 1.0))
	# 血河大法・圓滿：每 10 秒衝擊
	if Game.f("zhengqi_pulse") > 0.0:
		zhengqi_t += delta
		if zhengqi_t >= 10.0:
			zhengqi_t = 0.0
			_aoe(global_position, 6.0, ref_hit() * Game.f("zhengqi_pulse"), Color(0.9, 0.2, 0.2))
	# 武當・太極兩儀
	if Game.f("taiji") > 0.0:
		taiji_t += delta
		taiji_active -= delta
		if taiji_t >= 10.0:
			taiji_t = 0.0
			taiji_active = 5.0
			FX.warn_circle(get_parent(), global_position, 6.0, 5.0, Color(0.9, 0.9, 0.95, 0.25))
		if taiji_active > 0.0:
			for e in _enemies_within(global_position, 6.0):
				e.apply_slow(60.0, 0.5)
	# 太極神功・圓滿：陰陽切換
	if Game.f("yinyang") > 0.0:
		yinyang_t += delta
		if yinyang_t >= 10.0:
			yinyang_t = 0.0
			yang = not yang
	# 少林・十八羅漢陣
	_update_arhats(delta)


func _update_arhats(delta: float) -> void:
	var want := 4 if Game.f("arhats") > 0.0 else 0
	while arhat_nodes.size() < want:
		var a := FX.sphere(0.35, Color(1.0, 0.75, 0.3), 1.5)
		get_parent().add_child(a)
		arhat_nodes.append(a)
	if want == 0:
		return
	arhat_t += delta
	for i in arhat_nodes.size():
		var ang := arhat_t * 2.0 + TAU * i / 4.0
		arhat_nodes[i].global_position = global_position + Vector3(cos(ang) * 2.5, 1.0, sin(ang) * 2.5)
	if fmod(arhat_t, 0.5) < delta:
		for a in arhat_nodes:
			for e in _enemies_within(a.global_position, 1.2):
				deal(e, ref_hit() * 0.5 * 0.5, false)


# ------------------------------------------------------------------ 攻擊
func ref_hit() -> float:
	## 基礎攻擊力：角色固定兵器的單段傷害（含淬煉）；招式傷害是它的百分比
	var w = Game.current_weapon()
	if w == null:
		return 20.0
	return Game.weapon_hit_dmg(w.id, int(w.lv))


func _melee_targets(row: Dictionary, range_m: float, fwd: Vector3) -> Array:
	var cls: String = row["class"]
	var cone: float = SWEEP_DEGREES.get(cls, 0.0)
	var line := cone == 0.0      # 劍、槍：直線穿刺
	var flat_fwd := Vector3(fwd.x, 0, fwd.z).normalized()
	var out: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var to: Vector3 = e.hit_center() - cam.global_position
		if absf(to.y) > 3.0:
			continue
		var flat := Vector3(to.x, 0, to.z)
		var dist: float = flat.length() - e.hit_radius
		if dist > range_m:
			continue
		if line:
			var along := flat.dot(flat_fwd)
			var lateral := (flat - flat_fwd * along).length()
			if along > -0.3 and lateral <= THRUST_HALF_WIDTH + e.hit_radius:
				out.append(e)
		elif cone >= 360.0 or flat.length() < 0.8 or rad_to_deg(flat_fwd.angle_to(flat.normalized())) <= cone / 2.0:
			out.append(e)
	return out


func _shoot(pos: Vector3, dir: Vector3, dmg: float, pierce: int, rng: float, color: Color, visual_id := "", hit := {}) -> void:
	var p := PROJ.new()
	get_parent().add_child(p)
	p.global_position = pos
	p.direction = dir.normalized()
	p.speed = 45.0 * arrow_speed_mult
	p.damage = dmg
	p.pierce = pierce
	p.max_range = rng
	p.radius = 0.35
	p.on_hit = func(e, d):
		_imp = {"crit": false, "kill": false, "metal": false}
		if deal(e, d, false, _impact_weight(visual_id), e.global_position - dir, hit):
			runner.add_rage(CombatState.cfg("rage_per_hit"))
			Sfx.play("hit_high" if visual_id == "W006" else "arrow_impact", e.hit_center())
			_impact_feedback(_impact_weight(visual_id) * 0.8)
	if visual_id == "W006":
		var blade := preload("res://scripts/fighter_model.gd").flying_blade()
		p.add_child(blade)
		var up := Vector3.RIGHT if absf(p.direction.y) > .98 else Vector3.UP
		blade.basis = Basis.looking_at(p.direction, up)
		var trail := FX.sphere(.065, Color(color, .7), 1.5)
		blade.add_child(trail)
		trail.scale = Vector3(.35,.35,3.5)
		trail.position.z = .14
	elif visual_id in ["W007","W303","W103","W203"]:
		var missile := preload("res://scripts/archer_bow.gd").make_arrow()
		var factor := .76 if visual_id=="W007" else (.48 if visual_id=="W303" else .24)
		p.add_child(missile)
		missile.basis = Basis.looking_at(p.direction).scaled(Vector3.ONE*factor)
		missile.position = -p.direction * preload("res://scripts/archer_bow.gd").LENGTH * factor
	else:
		p.setup(color, 0.1)


func _on_attack_effects(primary, base: float, fwd: Vector3) -> void:
	# 萬劍朝宗：每第 10 次攻擊展開劍陣 3 秒必暴
	if Game.f("sword_array") > 0.0 and attack_count % 10 == 0:
		array_t = 3.0
		Game.message.emit("萬劍朝宗！")
	if primary == null or not is_instance_valid(primary) or primary.dead:
		return
	var extra_mult := 1.0 + Game.f("extra_hit_mult") + Game.f("extra_hit_bonus")
	# 角色・追風殘影（南宮逸）
	var chance := Game.f("extra_hit_chance")
	if chance > 0.0 and randf() * 100.0 < chance:
		_extra_hit(primary, base * extra_mult, fwd)
		if Game.f("extra_hit_chain") > 0.0 and randf() * 100.0 < chance:
			_extra_hit(primary, base * extra_mult, fwd)
	# 連環腿
	if Game.f("chain_kick") > 0.0:
		var chains := 3 if Game.f("chain_kick_chain") > 0.0 else 1
		for c in chains:
			if randf() >= 0.3:
				break
			_extra_hit(primary, base * Game.f("chain_kick") / 100.0 * (1.0 + Game.f("extra_hit_bonus")), fwd)
	# 疾風快劍・小成：每第 5 次攻擊追加一擊
	if Game.f("every5_extra") > 0.0 and attack_count % 5 == 0:
		_extra_hit(primary, base, fwd)
	# 萬劍歸宗：飛劍追擊
	var fs := Game.f("flying_sword_chance")
	while fs > 0.0:
		if randf() * 100.0 < fs:
			var tgt = _random_enemy_near(15.0)
			if tgt:
				deal(tgt, base * 2.0 * (1.0 + Game.f("extra_hit_bonus")), false)
				FX.play(get_parent(), tgt.hit_center(), &"thrust", 1.3, 0.18)
		fs -= 100.0
	# 雷霆劍訣：每第 5 次攻擊落雷
	if Game.f("thunder_pct") > 0.0 and attack_count % 5 == 0:
		FX.play(get_parent(), primary.hit_center() + Vector3.UP * 1.3, &"lightning-strike", 4.2, 0.38)
		_aoe(primary.global_position, 2.0, base * Game.f("thunder_pct") / 100.0, Color(0.8, 0.8, 1.0))


func _extra_hit(e, dmg: float, fwd: Vector3) -> void:
	if not is_instance_valid(e) or e.dead:
		return
	deal(e, dmg, false)
	FX.play(get_parent(), e.hit_center(), &"sword-slash", 1.2, 0.18, Color(0.65, 1.0, 0.85))
	# 氣勁離體：追擊同時射出氣勁
	if Game.f("extra_hit_qi") > 0.0:
		_shoot(cam.global_position + fwd * 0.6, fwd, dmg * Game.f("extra_hit_qi"), 99, 10.0, Color(0.5, 1.0, 0.8))


func _aoe(center: Vector3, r: float, dmg: float, color: Color) -> void:
	FX.impact_wave(get_parent(),center,r,.35,color)
	for e in _enemies_within(center, r):
		deal(e, dmg, false)


## 對敵人造成一次傷害（所有加成、暴擊、命中特效都在這裡）
func _impact_weight(wid: String) -> float:
	match wid:
		"W101", "W204", "W301": return 1.8
		"W003", "W006", "W103", "W203", "W303": return .65
	return 1.0


func deal(e, base: float, _is_dot: bool, weight := 1.0, source := Vector3.INF, hit := {}) -> bool:
	if not is_instance_valid(e) or e.dead:
		return false
	var mult := 1.0 + Game.st("dmg_pct") / 100.0
	if runner.blood_rage_left > 0:
		mult += CombatState.cfg("han_rage_bonus_pct") / 100
	var missing10 := (1.0 - hp / Game.max_hp()) * 10.0
	mult += Game.f("low_hp_dmg_per10") * missing10 / 100.0
	if Game.f("full_hp_dmg") > 0.0 and hp >= Game.max_hp() - 0.5:
		mult += Game.f("full_hp_dmg") / 100.0
	if Game.f("moving_dmg") > 0.0 and still_t == 0.0:
		mult += Game.f("moving_dmg") / 100.0
	if Game.f("stand_dmg") > 0.0 and still_t > 0.5:
		mult += Game.f("stand_dmg") / 100.0
	if Game.f("near_enemy_dmg") > 0.0:
		var cap := 20 if Game.f("near_cap20") > 0.0 else 10
		mult += Game.f("near_enemy_dmg") * mini(cap, _enemies_within(global_position, 5.0).size()) / 100.0
	if Game.f("per_enemy_in_range") > 0.0:
		mult += Game.f("per_enemy_in_range") * _enemies_within(global_position, 4.0).size() / 100.0
	if Game.f("elite_dmg") > 0.0 and e.rank != "minion":
		mult += Game.f("elite_dmg") / 100.0
	if Game.f("far_dmg") > 0.0 and e.global_position.distance_to(global_position) > 6.0:
		mult += Game.f("far_dmg") / 100.0
	if Game.f("vs_poison_dmg") > 0.0 and e.is_poisoned():
		mult += Game.f("vs_poison_dmg") / 100.0
	if Game.f("vs_slowed_dmg") > 0.0 and e.is_slowed():
		mult += Game.f("vs_slowed_dmg") / 100.0
	if Game.f("dodge_dmg") > 0.0 and _now() - last_dodge_t < 3.0:
		mult += Game.f("dodge_dmg") / 100.0
	mult += kill_stacks.size() / 100.0
	if shield > 0.0 and Game.f("shield_every8") > 0.0:
		mult += 0.3
	if Game.f("yinyang") > 0.0 and yang:
		mult += 0.5
	if demon_t > 0.0 and Game.f("demon_form") > 0.0:
		mult *= 2.0
	var du_hit := du_charged
	if du_hit:
		du_charged = false
		mult *= 1.0 + Game.special("du", "b") / 100.0
	if qiao_ready:
		qiao_ready = false
		mult *= 1.0 + Game.special("yangqiao", "b") / 100.0
	# 暴擊
	var crit_rate := float(Data.gacha.base_crit_rate_pct) + Game.st("crit_rate_pct")
	var forced := bool(hit.get("forced_crit", false)) or array_t > 0.0 or dodge_crit_ready or du_hit
	if Game.f("every3_crit") > 0.0 and attack_count % 3 == 0:
		forced = true
	if Game.f("low30_crit_ls") > 0.0 and hp < Game.max_hp() * 0.3:
		forced = true
	var crit := forced or randf() * 100.0 < crit_rate
	if crit:
		mult *= (float(Data.gacha.base_crit_dmg_pct) + Game.st("crit_dmg_pct")) / 100.0
		dodge_crit_ready = false
	var dealt: float = e.take_hit(base * mult, global_position if source == Vector3.INF else source, crit, weight, hit)
	if dealt <= 0.0:
		return false
	_imp.crit = _imp.crit or crit
	_imp.kill = _imp.kill or e.dead
	_imp.metal = _imp.metal or e.last_hit_metal
	# 命中特效
	var ls := Game.st("lifesteal_pct")
	if Game.f("low_hp_lifesteal_x2") > 0.0 and hp < Game.max_hp() * 0.5:
		ls *= 2.0
	if Game.f("low30_crit_ls") > 0.0 and hp < Game.max_hp() * 0.3:
		ls += 10.0
	if ls > 0.0:
		heal(dealt * ls / 100.0, false)
	if Game.f("poison_pct") > 0.0:
		e.apply_poison(dealt * Game.f("poison_pct") / 100.0, Game.f("poison_stack") > 0.0)
	if Game.f("slow_pct") > 0.0:
		e.apply_slow(Game.f("slow_pct"), 2.0)
	if Game.f("vuln_pct") > 0.0:
		e.apply_vuln(Game.f("vuln_pct"), 3.0)
	if crit:
		if Game.f("crit_vuln") > 0.0:
			e.apply_vuln(Game.f("crit_vuln"), 3.0)
		if Game.f("crit_heal") > 0.0:
			heal(Game.max_hp() * 0.01, false)
		if Game.special_on("yangwei"):   # 陽維脈・陽氣外發
			for o in _enemies_within(e.global_position, Game.special("yangwei", "b")):
				if o != e and not o.dead:
					o.take_hit(dealt * Game.special("yangwei", "a") / 100.0, global_position, false)
		if Game.special_on("yinwei"):    # 陰維脈・陰勁透骨
			e.apply_vuln(Game.special("yinwei", "a"), Game.special("yinwei", "b"))
		if Game.f("crit_splash") > 0.0:
			for o in _enemies_within(e.global_position, 2.0):
				if o != e:
					o.take_hit(dealt * Game.f("crit_splash"), global_position, false)
	return true


func on_enemy_killed(e) -> void:
	if Game.special_on("chong"):
		chong_t = Game.special("chong", "b")
	if Game.f("kill_heal") > 0.0:
		heal(Game.max_hp() * Game.f("kill_heal") / 100.0, false)
	if Game.f("kill_stack") > 0.0 and kill_stacks.size() < int(Game.f("kill_stack")):
		kill_stacks.append(5.0)
	if Game.f("poison_spread") > 0.0 and e.is_poisoned():
		for o in _enemies_within(e.global_position, 3.0):
			o.apply_poison(e.poison_left(), true)


# ------------------------------------------------------------------ 受傷
func take_damage(amount: float, attacker = null, is_dot := false, hit := {}) -> void:
	if hp <= 0.0 or amount <= 0.0:
		return
	if not is_dot and runner.try_counter(attacker):      # 殘影反擊
		return
	if invuln_t > 0.0 or not cs.hittable():
		return
	if demon_t > 0.0 and (Game.f("demon_form") > 0.0 or Game.f("blood_demon") > 0.0):
		return
	if not is_dot:
		if randf() * 100.0 < Game.st("dodge_pct"):
			_dodged()
			return
		if Game.f("block_chance") > 0.0 and randf() * 100.0 < Game.f("block_chance"):
			FX.float_text(get_parent(), global_position + Vector3(0, 2, 0), "格擋", Color(1, 0.9, 0.5))
			Sfx.play("hit_mid_metal")
			if attacker and is_instance_valid(attacker):
				attacker.stun(0.5)
			return
		if Game.f("parry") > 0.0 and randf() < Game.f("parry"):
			FX.float_text(get_parent(), global_position + Vector3(0, 2, 0), "卸力", Color(0.7, 0.9, 1))
			if attacker and is_instance_valid(attacker) and not attacker.dead:
				deal(attacker, ref_hit() * 2.0, false)
			return
		if guard_ready and Game.f("guard_every") > 0.0:
			guard_ready = false
			FX.play(get_parent(), cam.global_position - cam.global_basis.z, &"divine-shield", 0.9, 0.32)
			FX.float_text(get_parent(), global_position + Vector3(0, 2, 0), "護體", Color(1, 0.85, 0.3))
			return
	var dr := Game.st("dmg_reduction_pct")
	if dai_t > 0.0:   # 帶脈・束脈護體
		dr += Game.special("dai", "a")
	if Game.f("low50_dr") > 0.0 and hp < Game.max_hp() * 0.5:
		dr += Game.f("low50_dr")
	if taiji_active > 0.0:
		dr += 50.0
	if Game.f("yinyang") > 0.0 and not yang:
		dr += 50.0
	var dmg := amount * (1.0 - minf(dr, 85.0) / 100.0)
	if shield > 0.0:
		var absorbed := minf(shield, dmg)
		shield -= absorbed
		dmg -= absorbed
	hp -= dmg
	if dmg > 0.0 and not is_dot:
		runner.add_rage(CombatState.cfg("rage_per_hurt"))
		# 狀態：硬直、浮空、倒地（受擊保護期間只受傷）
		var h := hit if not hit.is_empty() else {"hitstun_s": CombatState.cfg("enemy_hitstun_s")}
		if hit_guard <= 0.0 or int(h.get("launch", 0)) == 1 or int(h.get("knockdown", 0)) == 1:
			var before := cs.base
			var res: Dictionary = cs.apply_hit(h)
			if float(res.launch_v) > 0.0:
				velocity.y = float(res.launch_v)
			if cs.base != CombatState.S.NORMAL and before == CombatState.S.NORMAL:
				hit_guard = float(h.get("hitstun_s", 0.0)) + CombatState.cfg("player_hit_guard_s")
				model.current = ""
	if dmg > 0.0:
		var ratio := dmg / Game.max_hp()
		Sfx.play("player_hurt", Vector3.INF, lerpf(-4.0, 2.0, clampf(ratio * 5.0, 0.0, 1.0)))
		Feel.shake(float(Data.feel.shake_hurt) * clampf(ratio * 5.0, 0.35, 1.0) * (0.4 if is_dot else 1.0))
		Feel.player_hurt.emit(clampf(ratio * 5.0, 0.3, 1.0))
	if Game.special_on("dai") and dai_cd <= 0.0 and dmg > 0.0:
		dai_t = Game.special("dai", "b")
		dai_cd = 6.0
	# 任脈・任脈歸元：生命低於 a% 時回復 b%
	if Game.special_on("ren") and ren_cd <= 0.0 and hp > 0.0 and hp < Game.max_hp() * Game.special("ren", "a") / 100.0:
		ren_cd = 60.0
		heal(Game.max_hp() * Game.special("ren", "b") / 100.0)
		Game.message.emit("任脈歸元！")
	# 反彈（移花接木、先天罡氣・小成）
	var refl := Game.f("reflect_pct") + Game.f("thorns")
	if refl > 0.0 and attacker and is_instance_valid(attacker) and not attacker.dead and not is_dot:
		attacker.take_hit(amount * refl / 100.0, global_position, false)
	# 天魔教・天魔降世：生命低於 30% 化身天魔
	if Game.f("demon_form") > 0.0 and demon_cd <= 0.0 and hp > 0.0 and hp < Game.max_hp() * 0.3:
		demon_t = 5.0
		demon_cd = 45.0
		Game.message.emit("天魔降世！")
	if hp <= 0.0:
		_try_survive()
	hp_changed.emit()


func _dodged() -> void:
	last_dodge_t = _now()
	if Game.f("dodge_crit") > 0.0:
		dodge_crit_ready = true
	FX.float_text(get_parent(), global_position + Vector3(0, 2, 0), "閃避", Color(0.7, 1, 0.8))
	Sfx.play("dash", Vector3.INF, -5.0, 1.2)


func _try_survive() -> void:
	if Game.f("blood_demon") > 0.0 and cheat_cd <= 0.0:
		hp = 1.0
		cheat_cd = 60.0
		demon_t = 3.0
		demon_speed = true
		Game.message.emit("血魔附體！")
		return
	if Game.f("cheat_death") > 0.0 and cheat_cd <= 0.0:
		hp = 1.0
		cheat_cd = 60.0
		invuln_t = 2.0
		Game.message.emit("天魔解體・小成：死裡逃生！")
		return
	hp = 0.0
	died.emit()


func heal(v: float, show := true) -> void:
	if hp <= 0.0:
		return
	var gained := minf(v, Game.max_hp() - hp)
	hp = minf(Game.max_hp(), hp + v)
	if show and gained > 0.0:
		FX.play(get_parent(), cam.global_position - cam.global_basis.z - cam.global_basis.y * 0.3, &"heal", 0.48, 0.35)
		Sfx.play("heal")
		FX.float_text(get_parent(), global_position + Vector3(0, 2, 0), "+%d" % int(v), Color(0.4, 1, 0.4))
	hp_changed.emit()


func level_up_heal() -> void:
	FX.play(get_parent(), cam.global_position - cam.global_basis.z * 1.5 - cam.global_basis.y * 0.36, &"blessing", 0.68, 0.65)
	if Game.f("levelup_heal") > 0.0:
		heal(Game.max_hp() * Game.f("levelup_heal"))


# ------------------------------------------------------------------ 輔助
func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _enemies_within(p: Vector3, r: float) -> Array:
	var out: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.dead and Vector2(e.global_position.x - p.x, e.global_position.z - p.z).length() <= r + e.hit_radius:
			out.append(e)
	return out


func _nearest_in_front(r: float, fwd: Vector3):
	var best = null
	var bd := r
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var to: Vector3 = e.global_position - global_position
		var d := to.length()
		if d < bd and Vector3(to.x, 0, to.z).normalized().dot(Vector3(fwd.x, 0, fwd.z).normalized()) > 0.5:
			bd = d
			best = e
	return best


func _random_enemy_near(r: float):
	var list := _enemies_within(global_position, r)
	return list[randi() % list.size()] if not list.is_empty() else null


func _densest_point(r: float) -> Vector3:
	var list := _enemies_within(global_position, r)
	if list.is_empty():
		return Vector3.INF
	var best: Vector3 = list[0].global_position
	var best_n := 0
	for e in list:
		var n := _enemies_within(e.global_position, 6.0).size()
		if n > best_n:
			best_n = n
			best = e.global_position
	return best


# ------------------------------------------------------------------ 打擊感與音效
func _impact_feedback(weight: float) -> void:
	## 一次出招（或一支箭）命中後：分層音效＋頓幀＋震動
	Sfx.hit(weight, _imp.crit, _imp.kill, _imp.metal)
	Feel.impact(weight, _imp.crit, _imp.kill)


func _swing_sound(row: Dictionary) -> void:
	if row.range_type == "ranged":
		Sfx.play("throw", Vector3.INF, -2.0, 1.1)
		return
	var cls: String = row["class"]
	if cls in ["劍", "槍"]:
		Sfx.play("swing_thrust")
	elif _impact_weight(row.weapon_id) >= 1.5:
		Sfx.play("swing_heavy")
	else:
		Sfx.play("swing_light")


func _move_sounds(delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_floor and _fall_v < -4.0:
		Sfx.play("land", Vector3.INF, lerpf(-6.0, 0.0, clampf((-_fall_v - 4.0) / 8.0, 0.0, 1.0)))
	if on_floor:
		_fall_v = 0.0
		var spd := Vector2(velocity.x, velocity.z).length()
		if spd > 1.0 and dash_t <= 0.0:
			_step_m += spd * delta
			if _step_m >= float(Data.feel.footstep_m):
				_step_m = 0.0
				Sfx.play("footstep")
	_was_floor = on_floor
	# 低血量心跳：越低越快
	var frac := hp / maxf(1.0, Game.max_hp())
	if hp > 0.0 and frac < float(Data.feel.heartbeat_hp):
		_beat_t -= delta
		if _beat_t <= 0.0:
			_beat_t = lerpf(0.55, 1.1, frac / float(Data.feel.heartbeat_hp))
			Sfx.play("heartbeat")
	else:
		_beat_t = 0.0
