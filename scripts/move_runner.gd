extends RefCounted
## 招式執行器：依 data/moves.csv、move_hits.csv 執行普攻連段、技能與大招。
## 負責：冷卻、怒氣、連段與預輸入、招式期間的霸體／無敵、位移、每一下的判定與狀態屬性。
## 由 player.gd 擁有並每個物理幀呼叫 update()。

const SKILLS := ["skill1", "skill2", "skill3", "skill4", "skill5", "skill6", "skill7"]

var p                         # player
var char_id := ""
var slots := {}               # slot -> move_id
var move: Dictionary = {}     # 正在出的招（空 = 沒有）
var t := 0.0
var fired := 0                # 已經打出的段數
var combo := 0                # 下一段普攻的索引（0 起算）
var combo_t := 0.0
var queued := ""              # 預輸入的 slot
var cds := {}                 # slot -> 剩餘冷卻
var rage := 0.0
var counter_ready := false    # 殘影：無敵期間被打就反擊
var counter_done := false
var speed := 1.0
var dir := Vector3.FORWARD    # 這一招的方向（出招瞬間的鏡頭水平方向）
var next_crit := false
var blood_rage_left := 0.0


func setup(player, cid: String) -> void:
	p = player
	char_id = cid
	slots = Data.char_moves.get(cid, {})
	cds.clear()
	rage = 0.0
	move = {}


func normals() -> int:
	var n := 0
	while slots.has("normal%d" % (n + 1)):
		n += 1
	return n


func busy() -> bool:
	return not move.is_empty()


func cd_left(slot: String) -> float:
	return float(cds.get(slot, 0.0))


func ready(slot: String) -> bool:
	if not slots.has(slot):
		return false
	if slot == "ult":
		return rage >= CombatState.cfg("rage_max")
	return cd_left(slot) <= 0.0


## 普攻收招（最後一段判定已出）之後可以被技能取消
func cancellable() -> bool:
	if move.is_empty():
		return true
	return String(move.slot).begins_with("normal") and fired >= move.hits.size()


func press(slot: String) -> void:
	if slot == "attack":
		if move.is_empty():
			_start("normal%d" % (combo + 1))
		else:
			queued = "attack"
	elif ready(slot):
		if cancellable():
			_start(slot)
		else:
			queued = slot


func _start(slot: String) -> void:
	if not slots.has(slot):
		return
	move = Data.moves[slots[slot]]
	t = 0.0
	fired = 0
	queued = ""
	counter_ready = move.kind == "counter"
	counter_done = false
	speed = 1.0 + (p.atk_speed_now() / 100.0 if slot.begins_with("normal") else 0.0)
	dir = p.aim_flat()
	p.face(dir)
	if slot == "ult":
		rage = 0.0
		Sfx.play("legend_sting")
		Feel.shake(0.3)
	elif not slot.begins_with("normal"):
		cds[slot] = float(move.cooldown_s) * (1.0 - minf(p.build.st("cdr_pct"), 60.0) / 100.0)
	if slot.begins_with("normal"):
		combo = (combo + 1) % normals()
		p.attack_count += 1
		p._count_du()
	var st := String(move.self_state)
	if st != "" and float(move.self_from_s) <= 0.0:
		_self_state(st, float(move.self_to_s))
	var dur := float(move.duration_s)
	var a: Animation = p.model.anim.get_animation(p.model.clip(move.anim)) if p.model.has(move.anim) else null
	var from := float(move.anim_from_s)
	var aspeed := speed
	if a:
		aspeed = clampf((a.length - from) / dur, 0.4, 4.0) * speed
	p.model.play(move.anim, aspeed, from, 0.06, true)
	if move.kind == "buff":
		blood_rage_left = float(move.self_to_s)
		p.hp = maxf(1, p.hp - p.build.max_hp() * CombatState.cfg("han_rage_cost_pct") / 100)
		p.hp_changed.emit()
	elif move.move_id == "tang_s7":
		next_crit = true
	if move.hits.is_empty() or move.kind == "counter":
		_cue(p.global_position + Vector3.UP, 2.3, false)



func _self_state(st: String, sec: float) -> void:
	if st == "armor":
		p.cs.give_armor(sec)
	elif st == "invincible":
		p.cs.give_invincible(sec)


func interrupt() -> void:
	move = {}
	queued = ""
	counter_ready = false


## 回傳這一幀的位移速度（公尺／秒，水平），沒有就回傳 Vector3.ZERO
func update(delta: float) -> Vector3:
	blood_rage_left = maxf(0, blood_rage_left - delta)
	for k in cds.keys():
		cds[k] = maxf(0.0, float(cds[k]) - delta)
	if move.is_empty():
		combo_t += delta
		if combo_t > CombatState.cfg("combo_reset_s"):
			combo = 0
		return Vector3.ZERO
	combo_t = 0.0
	var prev := t
	t += delta * speed
	var st := String(move.self_state)
	var f0 := float(move.self_from_s)
	if st != "" and f0 > 0.0 and prev < f0 and t >= f0:
		_self_state(st, float(move.self_to_s) - f0)
	if move.kind != "counter":
		while fired < move.hits.size() and float(move.hits[fired].time_s) <= t:
			_fire(move.hits[fired])
			fired += 1
	var vel := Vector3.ZERO
	var l0 := float(move.lunge_from_s)
	var l1 := float(move.lunge_to_s)
	if l1 > l0 and delta > 0:
		var overlap := maxf(0.0, minf(t, l1) - maxf(prev, l0))
		vel = dir * float(move.lunge_m) * overlap / ((l1 - l0) * delta)
	if t >= float(move.duration_s) or (queued != "" and cancellable() and (queued != "attack" or t >= float(move.duration_s) * 0.72)):
		var q := queued
		move = {}
		counter_ready = false
		if q == "attack":
			_start("normal%d" % (combo + 1))
		elif q != "" and ready(q):
			_start(q)
	return vel


## 殘影：無敵期間被攻擊 → 閃到攻擊者身後反擊
func try_counter(attacker) -> bool:
	if not counter_ready or counter_done or attacker == null or not is_instance_valid(attacker):
		return false
	counter_done = true
	var away: Vector3 = attacker.global_position - p.global_position
	away.y = 0
	var d := away.normalized() if away.length() > 0.1 else dir
	p.global_position = attacker.global_position + d * 1.4
	p.global_position.y = attacker.global_position.y
	dir = -d
	p.face(dir)
	p.cs.give_invincible(0.5)
	FX.play(p.get_parent(), p.global_position + Vector3.UP, &"blink-out", 0.8, 0.2)
	p.model.play("Sword_Regular_B", 1.4, 0.0, 0.03, true)
	for h in move.hits:
		_fire(h)
	return true


func add_rage(v: float) -> void:
	rage = minf(CombatState.cfg("rage_max"), rage + v)


func _fire(h: Dictionary) -> void:
	var base: float = p.ref_hit() * float(h.dmg_pct) / 100.0
	var origin: Vector3 = p.global_position + Vector3.UP * 1.1
	var shape := String(h.shape)
	if shape == "proj":
		var aim: Vector3 = p.aim_dir(origin)
		_cue(origin + aim, .85 * CombatState.cfg("attack_fx_span_mult"), false)
		if next_crit:
			h = h.duplicate()
			h["forced_crit"] = true
			next_crit = false
		p.shoot(origin + aim * 0.6, aim, base, int(h.pierce), float(h.range_m), Color(move.fx_tint), h)
		return
	var center: Vector3 = p.global_position
	var r := float(h.range_m)
	if move.move_id == "tang_s3" or move.kind == "trap":
		var trap: bool = move.kind == "trap"
		if not trap:
			center = p.aim_point(r)
			center.y = minf(center.y, p.global_position.y + .1)
			r = CombatState.cfg("tang_cloud_radius_m")
		var field := preload("res://scripts/hidden_weapon_field.gd").new()
		p.get_parent().level_root.add_child(field)
		field.global_position = center
		field.setup(p, h, r, base, trap)
		_cue(center + Vector3.UP * .35, r, false)
		return
	if shape == "target":
		center = p.aim_point(r)
		r = CombatState.cfg("target_area_radius_m")
		if char_id == "tang":
			_needle_rain(center, r)
	var targets: Array = []
	var cosv := cos(deg_to_rad(float(h.arc_deg) / 2.0))
	for e in p.targets():
		if e.dead:
			continue
		var to: Vector3 = e.global_position - center
		var dy := absf(to.y)
		to.y = 0
		if to.length() > r + e.hit_radius or dy > 5.0:
			continue
		if shape in ["arc", "line"] and to.length() > 0.6 and to.normalized().dot(dir) < cosv:
			continue
		targets.append(e)
	var tint := Color(move.fx_tint)
	var finisher: bool = move.slot == "ult" and fired == move.hits.size() - 1
	if shape in ["circle", "target"]:
		FX.impact_wave(p.get_parent(), center, r, .22, tint)
		_cue(center + Vector3.UP * .6, r * CombatState.cfg("area_fx_span_mult"), finisher)
	else:
		FX.attack_trail(p.get_parent(), origin, dir, r, float(h.arc_deg), .2, tint, .2)
		var distance := r * .5 if shape == "line" else minf(r, 3.0) * .6
		_cue(origin + dir * distance, r * CombatState.cfg("attack_fx_span_mult"), finisher)
	p._imp = {"crit": false, "kill": false, "metal": false}
	var any := false
	# 擊退方向：近戰往出招方向推（目標留在正前方），範圍招從中心往外推
	h = h.duplicate()
	h["push_from"] = center
	if shape in ["arc", "line"]:
		h["push_fwd"] = dir
	for e in targets:
		if p.deal(e, base, false, _weight(h), Vector3.INF, h):
			any = true
			add_rage(CombatState.cfg("rage_per_hit"))
	if any:
		p._impact_feedback(_weight(h))
		if fired == 0 and not targets.is_empty():
			p._on_attack_effects(targets[0], base, dir)


## 刀光、毒色與聲音在實際出手時出現；反擊和無判定招以起勢為準。
func _cue(pos: Vector3, span: float, finisher: bool) -> void:
	p.skill_cue.emit(move.move_id, pos, span, finisher)
	var clip := StringName(move.fx_clip)
	var sound := String(move.strike_sfx)
	if finisher:
		clip = &"ground-slam" if char_id != "nangong" else &"heavy-cleave"
		sound = "aoe_boom"
	FX.play(p.get_parent(), pos, clip, span, .24, Color(move.fx_tint), fired % 2 == 1)
	Sfx.play(sound, pos)


## 每一波針雨都在該次判定中心落下，散點固定以免干擾遊戲亂數。
func _needle_rain(center: Vector3, radius: float) -> void:
	for i in 5:
		var angle := TAU * i / 5.0 + fired
		var offset := Vector3(cos(angle), 0, sin(angle)) * radius * (.25 + .13 * i)
		var end := center + offset + Vector3.UP * .1
		var needle := FX.box(Vector3(.025, .68, .025), Color(move.fx_tint), 2)
		p.get_parent().add_child(needle)
		needle.global_position = end + Vector3.UP * 2.4
		var fall := needle.create_tween()
		fall.tween_property(needle, "global_position", end, .10)
		fall.tween_callback(needle.queue_free)


func _weight(h: Dictionary) -> float:
	return clampf(float(h.dmg_pct) / 80.0, 0.65, 2.0)
