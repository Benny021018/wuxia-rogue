extends CharacterBody3D

const MELEE_EFFECTS := {"劍": &"thrust", "槍": &"thrust", "棍": &"spin-slash", "鞭": &"whip-crack", "鉤": &"double-slash", "拳": &"blunt-hit", "巨劍": &"heavy-cleave"}
## 第一人稱玩家：移動、雙武器攻擊、受傷流程，以及武學／門派／境界的戰鬥效果

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
var weapon_models: Array = [null, null]
var cooldowns := [0.0, 0.0]
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
	cam = Camera3D.new()
	cam.position = Vector3(0, 1.6, 0)
	cam.fov = 80.0
	cam.far = 300.0
	add_child(cam)
	cam.current = true
	hp = Game.max_hp()
	Game.stats_changed.connect(_on_stats_changed)
	refresh_weapon_models()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_stats_changed() -> void:
	hp = minf(hp, Game.max_hp())
	refresh_weapon_models()
	hp_changed.emit()


func refresh_weapon_models() -> void:
	for m in weapon_models:
		if m:
			m.queue_free()
	weapon_models = [null, null]
	for i in 2:
		var w = Game.weapons[i]
		if w == null:
			continue
		var row: Dictionary = Data.weapons[w.id]
		var length := 0.9 if row.range_type == "melee" else (1.1 if row.range_type == "mid" else 0.45)
		var m := FX.box(Vector3(0.06, 0.06, length), Data.rarity_color(row.rarity), 0.6)
		cam.add_child(m)
		m.position = Vector3(0.45 if i == 0 else -0.45, -0.35, -0.5 - length * 0.3)
		m.rotation_degrees = Vector3(10, 8 if i == 0 else -8, 0)
		weapon_models[i] = m


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENS
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS, -1.45, 1.45)
		rotation.y = yaw
		cam.rotation.x = pitch
	elif event.is_action_pressed("interact"):
		interact_pressed.emit()


func _physics_process(delta: float) -> void:
	_timers(delta)
	# 移動
	var dir := Vector3.ZERO
	if input_enabled:
		var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		dir = (transform.basis * Vector3(iv.x, 0, iv.y)).normalized()
		if Input.is_action_just_pressed("dash") and dash_cd <= 0.0:
			FX.play(get_parent(), cam.global_position - cam.global_basis.z * 1.1 - cam.global_basis.y * 0.32, &"blink-out", 0.5, 0.18)
			dash_t = 0.2
			dash_cd = 1.0
			invuln_t = maxf(invuln_t, 0.2)
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_V
	var spd := Game.move_speed() * (3.2 if dash_t > 0.0 else 1.0)
	if dash_t > 0.0 and dir == Vector3.ZERO:
		dir = -transform.basis.z
	velocity.x = move_toward(velocity.x, dir.x * spd, 60.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * spd, 60.0 * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()
	still_t = still_t + delta if Vector2(velocity.x, velocity.z).length() < 0.5 else 0.0
	if global_position.y < -10.0:
		global_position.y = 2.0
		velocity = Vector3.ZERO
	# 攻擊
	for i in 2:
		cooldowns[i] = maxf(0.0, cooldowns[i] - delta)
		if input_enabled and Input.is_action_pressed("attack_%d" % (i + 1)) and cooldowns[i] <= 0.0 and Game.weapons[i] != null:
			_attack(i)


# ------------------------------------------------------------------ 計時器與週期效果
func _timers(delta: float) -> void:
	dash_t -= delta
	dash_cd -= delta
	invuln_t -= delta
	cheat_cd -= delta
	demon_cd -= delta
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
	## 參考單擊傷害：第一把武器的單段傷害（含淬煉）
	var w = Game.weapons[0] if Game.weapons[0] != null else Game.weapons[1]
	if w == null:
		return 20.0
	return float(Data.weapons[w.id].dmg) * (1.0 + 0.15 * (int(w.lv) - 1))


func _attack(slot: int) -> void:
	var w = Game.weapons[slot]
	var row: Dictionary = Data.weapons[w.id]
	var atk_speed := Game.st("atk_speed_pct")
	if taiji_active > 0.0:
		atk_speed += 50.0
	if demon_speed:
		atk_speed += 100.0
	cooldowns[slot] = float(row.interval_s) / (1.0 + atk_speed / 100.0)
	if Game.f("instant_repeat") > 0.0 and randf() < Game.f("instant_repeat"):
		cooldowns[slot] = 0.05
	attack_count += 1
	var dmg := float(row.dmg) * (1.0 + 0.15 * (int(w.lv) - 1))
	var hits := int(row.hits)
	var range_m := float(row.range_m)
	var fwd := -cam.global_transform.basis.z
	var origin := cam.global_position
	_swing_anim(slot)
	var targets: Array = []
	if row.range_type == "ranged":
		range_m *= 1.0 + Game.st("range_pct") / 100.0
		var pierce := 0
		if "pierce" in String(row.tags):
			pierce = 2 if row["class"] == "弩" else 1
		var spread := 0.12 if hits >= 5 else 0.05
		for h in hits:
			var off := (h - (hits - 1) / 2.0) * spread
			var d := fwd.rotated(Vector3.UP, off)
			_shoot(origin + d * 0.6, d, dmg, pierce, range_m, Data.rarity_color(row.rarity))
			var sc := Game.f("split_chance")
			if sc > 0.0 and randf() * 100.0 < sc:
				var extra := 2 if Game.f("split3") > 0.0 else 1
				for k in extra:
					_shoot(origin + d * 0.6, d.rotated(Vector3.UP, 0.15 * (k * 2 - 1)), dmg, pierce + (1 if Game.martial.get("M106", 0) >= 3 else 0), range_m, Color.WHITE)
	else:
		range_m *= 1.0 + Game.st("area_pct") / 100.0
		targets = _melee_targets(row, range_m, fwd)
		for h in hits:
			for e in targets:
				if is_instance_valid(e) and not e.dead:
					deal(e, dmg, false)
		var swing: StringName = MELEE_EFFECTS.get(row["class"], &"sword-slash")
		var side := -1.0 if slot == 0 else 1.0
		var strike := origin + fwd * minf(range_m, 1.7) + cam.global_basis.x * side * 0.32 - cam.global_basis.y * 0.18
		FX.play(get_parent(), strike, swing, 1.3, minf(cooldowns[slot], 0.26), Color.WHITE, slot == 0)
		# 劍氣縱橫：近戰與中距離武器射出劍氣
		if Game.f("sword_qi_pct") > 0.0:
			var n := 1 + int(Game.f("sword_qi_count"))
			for k in n:
				var d2 := fwd.rotated(Vector3.UP, (k - (n - 1) / 2.0) * 0.2)
				_shoot(origin + d2 * 0.6, d2, dmg * Game.f("sword_qi_pct") / 100.0, 99, 12.0, Color(0.6, 0.9, 1.0))
	var primary = targets[0] if not targets.is_empty() else _nearest_in_front(15.0, fwd)
	_on_attack_effects(primary, dmg, fwd)


func _melee_targets(row: Dictionary, range_m: float, fwd: Vector3) -> Array:
	var cls: String = row["class"]
	var cone: float = {"刀": 120.0, "棍": 360.0, "拳": 60.0, "鉤": 90.0, "巨劍": 140.0, "扇": 50.0, "鞭": 360.0}.get(cls, 0.0)
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
			if along > -0.3 and lateral <= 0.9 + e.hit_radius:
				out.append(e)
		elif cone >= 360.0 or flat.length() < 0.8 or rad_to_deg(flat_fwd.angle_to(flat.normalized())) <= cone / 2.0:
			out.append(e)
	return out


func _shoot(pos: Vector3, dir: Vector3, dmg: float, pierce: int, rng: float, color: Color) -> void:
	var p := PROJ.new()
	get_parent().add_child(p)
	p.global_position = pos
	p.direction = dir.normalized()
	p.speed = 45.0
	p.damage = dmg
	p.pierce = pierce
	p.max_range = rng
	p.radius = 0.35
	p.on_hit = func(e, d): deal(e, d, false)
	p.setup(color, 0.1)


func _on_attack_effects(primary, base: float, fwd: Vector3) -> void:
	# 萬劍朝宗：每第 10 次攻擊展開劍陣 3 秒必暴
	if Game.f("sword_array") > 0.0 and attack_count % 10 == 0:
		array_t = 3.0
		Game.message.emit("萬劍朝宗！")
	if primary == null or not is_instance_valid(primary) or primary.dead:
		return
	var extra_mult := 1.0 + Game.f("extra_hit_mult") + Game.f("extra_hit_bonus")
	# 角色・追風劍意（南宮劍）
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
	# 劍氣離體：追擊同時射出劍氣
	if Game.f("extra_hit_qi") > 0.0:
		_shoot(cam.global_position + fwd * 0.6, fwd, dmg * Game.f("extra_hit_qi"), 99, 10.0, Color(0.5, 1.0, 0.8))


func _aoe(center: Vector3, r: float, dmg: float, color: Color) -> void:
	FX.play(get_parent(), center + Vector3(0, 0.5, 0), &"ground-slam", r * 2.0, 0.35, color)
	for e in _enemies_within(center, r):
		deal(e, dmg, false)


## 對敵人造成一次傷害（所有加成、暴擊、命中特效都在這裡）
func deal(e, base: float, _is_dot: bool) -> void:
	if not is_instance_valid(e) or e.dead:
		return
	var mult := 1.0 + Game.st("dmg_pct") / 100.0
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
	# 暴擊
	var crit_rate := float(Data.gacha.base_crit_rate_pct) + Game.st("crit_rate_pct")
	var forced := array_t > 0.0 or dodge_crit_ready
	if Game.f("every3_crit") > 0.0 and attack_count % 3 == 0:
		forced = true
	if Game.f("low30_crit_ls") > 0.0 and hp < Game.max_hp() * 0.3:
		forced = true
	var crit := forced or randf() * 100.0 < crit_rate
	if crit:
		mult *= (float(Data.gacha.base_crit_dmg_pct) + Game.st("crit_dmg_pct")) / 100.0
		dodge_crit_ready = false
	var dealt: float = e.take_hit(base * mult, global_position, crit)
	if dealt <= 0.0:
		return
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
		if Game.f("crit_splash") > 0.0:
			for o in _enemies_within(e.global_position, 2.0):
				if o != e:
					o.take_hit(dealt * Game.f("crit_splash"), global_position, false)


func on_enemy_killed(e) -> void:
	if Game.f("kill_heal") > 0.0:
		heal(Game.max_hp() * Game.f("kill_heal") / 100.0, false)
	if Game.f("kill_stack") > 0.0 and kill_stacks.size() < int(Game.f("kill_stack")):
		kill_stacks.append(5.0)
	if Game.f("poison_spread") > 0.0 and e.is_poisoned():
		for o in _enemies_within(e.global_position, 3.0):
			o.apply_poison(e.poison_left(), true)


# ------------------------------------------------------------------ 受傷
func take_damage(amount: float, attacker = null, is_dot := false) -> void:
	if hp <= 0.0 or invuln_t > 0.0 or amount <= 0.0:
		return
	if demon_t > 0.0 and (Game.f("demon_form") > 0.0 or Game.f("blood_demon") > 0.0):
		return
	if not is_dot:
		if randf() * 100.0 < Game.st("dodge_pct"):
			_dodged()
			return
		if Game.f("block_chance") > 0.0 and randf() * 100.0 < Game.f("block_chance"):
			FX.float_text(get_parent(), global_position + Vector3(0, 2, 0), "格擋", Color(1, 0.9, 0.5))
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


func _swing_anim(slot: int) -> void:
	var m = weapon_models[slot]
	if m == null:
		return
	var base_rot: Vector3 = Vector3(10, 8 if slot == 0 else -8, 0)
	var t: Tween = m.create_tween()
	t.tween_property(m, "rotation_degrees", base_rot + Vector3(-50, 0, 0), 0.06)
	t.tween_property(m, "rotation_degrees", base_rot, 0.12)
