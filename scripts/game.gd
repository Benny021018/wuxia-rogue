extends Node
const FEATURED_WEAPONS := ["W001","W007","W301"]

## 一局遊戲的狀態：角色、修為、銀兩、武器、武學、門派傳承，以及參悟（抽獎）邏輯

signal stats_changed
signal gold_changed
signal xiuwei_changed
signal leveled_up(level: int)
signal realm_broken(level: int, realm_name: String, effect: String)
signal martial_breakthrough(mid: String, lv: int, desc: String)
signal bond_activated(sect_id: String, tier: int, name: String)
signal message(text: String)

const MAX_LV := 5

var char_id := "nangong"
var level := 1
var xiuwei := 0.0
var gold := 0.0
var weapons: Array = [null, null]      # 每格 {id, lv}
var martial := {}                      # martial_id -> lv
var martial_order: Array = []
var stage := 1
var draws_this_stage := 0
var total_draws := 0
var since_legendary := 0
var kills := 0
var run_time := 0.0
var free_draws := 0
var stats := {}
var flags := {}                        # 已啟用的特殊效果 -> 數值
var bond_tiers := {}                   # sect_id -> 已啟用最高階
var rng := RandomNumberGenerator.new()
var running := false


func _ready() -> void:
	rng.randomize()
	_setup_input()


func _process(delta: float) -> void:
	if running and not get_tree().paused:
		run_time += delta


# ------------------------------------------------------------------ 開局
func new_run(cid: String) -> void:
	char_id = cid
	level = 1
	xiuwei = 0.0
	gold = 0.0
	martial = {}
	martial_order = []
	stage = 1
	draws_this_stage = 0
	total_draws = 0
	since_legendary = 0
	kills = 0
	run_time = 0.0
	free_draws = 0
	bond_tiers = {}
	# 開局從凡品武器中隨機給一把（近戰／中距離／遠程各有機會）
	var starters: Array = []
	for wid in FEATURED_WEAPONS:
		if Data.weapons[wid].rarity == "common":
			starters.append(wid)
	weapons = [{"id": starters[rng.randi() % starters.size()], "lv": 1}, null]
	running = true
	recompute()


# ------------------------------------------------------------------ 屬性彙總
func recompute() -> void:
	var s := {}
	for k in Data.stat_values:
		s[k] = 0.0
	flags = {}
	# 角色被動
	for p in Data.passives:
		if p.char_id != char_id:
			continue
		var v := float(p.lv1_value) + float(p.per_level) * (level - 1)
		match p.passive_id:
			"ng_p1": _flag("extra_hit_chance", v)
			"han_p2": _flag("low_hp_dmg_per10", v)
			"tang_p1": _flag("poison_pct", v)
			_: s[p.stat_id] += v
	# 境界
	for r in Data.realms:
		if r.char_id == char_id and int(r.level) <= level:
			match [char_id, int(r.level)]:
				["nangong", 10]: _flag("extra_hit_mult", 0.7)
				["nangong", 20]: _flag("extra_hit_qi", 0.5)
				["nangong", 30]: _flag("extra_hit_chain", 1)
				["han", 10]: _flag("low50_dr", 15)
				["han", 20]: _flag("kill_heal", 1.5)
				["han", 30]: _flag("blood_demon", 1)
				["tang", 10]: _flag("vs_poison_dmg", 20)
				["tang", 20]: _flag("poison_spread", 1)
				["tang", 30]: _flag("extra_choice", 1)
	# 武學
	for mid in martial:
		var lv: int = martial[mid]
		var m: Dictionary = Data.martial[mid]
		var v := Data.martial_value(mid, lv)
		if m.stat_id != "custom":
			s[m.stat_id] += v
		else:
			match mid:
				"M101": _flag("chain_kick", v)
				"M104": _flag("poison_pct", v)
				"M106": _flag("split_chance", v)
				"M109": _flag("near_enemy_dmg", v)
				"M111": _flag("moving_dmg", v)
				"M112": _flag("slow_pct", v)
				"M201": _flag("sword_qi_pct", v)
				"M202": _flag("low_hp_dmg_per10", v)
				"M205": _flag("thunder_pct", v)
				"M206": _flag("reflect_pct", v)
				"M208": _flag("vuln_pct", v)
				"M301":
					s.atk_speed_pct += v
					s.max_hp_pct += v
				"M302": _flag("flying_sword_chance", v)
				"M305": s.dmg_pct += v * martial.size()
				"M306": _flag("palm_pct", v)
		if lv >= 3:
			_apply_breakthrough(mid, 3, s)
		if lv >= 5:
			_apply_breakthrough(mid, 5, s)
	# 門派傳承
	var counts := sect_counts()
	for b in Data.bonds:
		if counts.get(b.sect_id, 0) >= int(b.count_required):
			for i in [1, 2]:
				var st: String = b["stat%d" % i]
				if st != "":
					s[st] += float(b["val%d" % i])
			_apply_bond(b.sect_id, int(b.tier))
			if int(b.tier) > int(bond_tiers.get(b.sect_id, 0)):
				bond_tiers[b.sect_id] = int(b.tier)
				bond_activated.emit(b.sect_id, int(b.tier), b.name_zh)
	if flags.has("per_perfect"):
		var perfect := 0
		for mid in martial:
			if martial[mid] >= 5:
				perfect += 1
		s.dmg_pct += flags.per_perfect * perfect
	if flags.has("hp_to_dmg"):
		s.dmg_pct += flags.hp_to_dmg * s.max_hp_pct
	s.dmg_reduction_pct = minf(s.dmg_reduction_pct, 60.0)
	s.dodge_pct = minf(s.dodge_pct, 60.0)
	stats = s
	stats_changed.emit()


func _flag(k: String, v: float) -> void:
	flags[k] = float(flags.get(k, 0.0)) + v


func _apply_breakthrough(mid: String, tier: int, s: Dictionary) -> void:
	match [mid, tier]:
		["M001", 3]: _flag("elite_dmg", 25)
		["M001", 5]: _flag("kill_stack", 40)
		["M002", 3]: _flag("guard_every", 10)
		["M003", 3]: s.dodge_pct += 5
		["M003", 5]: _flag("dodge_crit", 1)
		["M004", 3]: s.lifesteal_pct += 2.5
		["M004", 5]: _flag("full_hp_dmg", 40)
		["M005", 3]: s.luck += 0.1
		["M005", 5]: _flag("free_draw_chance", 0.2)
		["M006", 3]: s.crit_rate_pct += 16
		["M006", 5]: _flag("every3_crit", 1)
		["M007", 3]: s.crit_dmg_pct += 40
		["M007", 5]: _flag("crit_heal", 1)
		["M010", 3]: _flag("far_dmg", 12)
		["M011", 3]: _flag("levelup_heal", 0.2)
		["M011", 5]: _flag("realm_free_draw", 1)
		["M012", 3]: s.gold_gain_pct += 12
		["M101", 5]: _flag("chain_kick_chain", 1)
		["M102", 3]: _flag("crit_vuln", 15)
		["M102", 5]: _flag("crit_splash", 0.5)
		["M103", 3]: _flag("low_hp_lifesteal_x2", 1)
		["M104", 3]: _flag("poison_stack", 1)
		["M104", 5]: _flag("poison_spread", 1)
		["M105", 3]: s.move_speed_pct += 13
		["M106", 5]: _flag("split3", 1)
		["M107", 3]: _flag("every5_extra", 1)
		["M108", 3]: _flag("stand_dmg", 50)
		["M108", 5]: _flag("block_chance", 20)
		["M109", 5]: _flag("near_cap20", 1)
		["M110", 3]: _flag("reroll_discount", 0.5)
		["M110", 5]: _flag("cost_growth_override", 0.08)
		["M111", 3]: s.move_speed_pct += 13
		["M112", 3]: _flag("vs_slowed_dmg", 25)
		["M201", 3]: _flag("sword_qi_count", 1)
		["M202", 3]: _flag("cheat_death", 1)
		["M202", 5]: _flag("low30_crit_ls", 1)
		["M203", 3]: _flag("per_enemy_in_range", 3)
		["M203", 5]: _flag("bagua_pulse", 3.0)
		["M204", 3]: _flag("thorns", 30)
		["M204", 5]: _flag("hp_to_dmg", 0.4)
		["M207", 3]: _flag("instant_repeat", 0.3)
		["M301", 3]: _flag("parry", 0.3)
		["M301", 5]: _flag("yinyang", 1)
		["M303", 3]: _flag("extra_choice", 1)
		["M303", 5]: _flag("guarantee_upgrade", 1)
		["M304", 3]: s.max_hp_pct += 144
		["M304", 5]: _flag("zhengqi_pulse", 5.0)
		["M305", 3]: _flag("per_perfect", 20)
		["M305", 5]: _flag("extra_slots", 2)


func _apply_bond(sect: String, tier: int) -> void:
	match [sect, tier]:
		["tianjian", 2]: _flag("extra_hit_bonus", 0.5)
		["tianjian", 3]: _flag("sword_array", 1)
		["tianmo", 2]: _flag("low_hp_dmg_per10", 12)
		["tianmo", 3]: _flag("demon_form", 1)
		["tangmen", 2]:
			_flag("poison_pct", 20)
			_flag("vs_poison_dmg", 25)
		["tangmen", 3]:
			_flag("extra_choice", 1)
			_flag("guarantee_tangmen", 1)
		["shaolin", 2]: _flag("shield_every8", 1)
		["shaolin", 3]: _flag("arhats", 1)
		["wudang", 2]: _flag("dodge_dmg", 50)
		["wudang", 3]: _flag("taiji", 1)


func f(k: String) -> float:
	return float(flags.get(k, 0.0))


func st(k: String) -> float:
	return float(stats.get(k, 0.0))


func sect_counts() -> Dictionary:
	var c := {}
	for mid in martial:
		var sid: String = Data.martial[mid].sect
		c[sid] = int(c.get(sid, 0)) + 1
	return c


func max_hp() -> float:
	return float(Data.characters[char_id].hp) * (1.0 + st("max_hp_pct") / 100.0)


func move_speed() -> float:
	return float(Data.characters[char_id].move_speed) * (1.0 + st("move_speed_pct") / 100.0)


func martial_slots() -> int:
	return int(Data.gacha.martial_slots) + int(f("extra_slots"))


# ------------------------------------------------------------------ 修為與境界
func realm_name(lv: int) -> String:
	return String(Data.levels[lv - 1].display_zh)


func xiuwei_for_next() -> float:
	if level >= Data.levels.size():
		return 0.0
	return float(Data.levels[level - 1].xiuwei_to_next)


func xiuwei_into_level() -> float:
	return xiuwei - float(Data.levels[level - 1].xiuwei_total)


func add_kill(eid: String) -> void:
	kills += 1
	var r := Data.enemy_rewards(eid)
	gold += r.y * (1.0 + st("gold_gain_pct") / 100.0)
	add_xiuwei(r.x * (1.0 + st("xiuwei_gain_pct") / 100.0))
	gold_changed.emit()


func add_xiuwei(v: float) -> void:
	xiuwei += v
	var leveled := false
	while level < Data.levels.size() and xiuwei >= float(Data.levels[level].xiuwei_total):
		level += 1
		leveled = true
		leveled_up.emit(level)
		if level in [10, 20, 30]:
			var eff := ""
			for r in Data.realms:
				if r.char_id == char_id and int(r.level) == level:
					eff = "%s：%s" % [r.name_zh, r.effect_desc]
			if f("realm_free_draw") > 0:
				free_draws += 1
			realm_broken.emit(level, String(Data.levels[level - 1].realm_zh), eff)
	if leveled:
		recompute()
	xiuwei_changed.emit()


# ------------------------------------------------------------------ 參悟（抽獎）
func draw_cost() -> int:
	var k: float = Data.gacha.cost_growth_k
	if f("cost_growth_override") > 0:
		k = f("cost_growth_override")
	var base := float(Data.gacha.base_cost) * pow(1.0 + Data.cfg("draw_cost_stage_growth"), stage - 1)
	return int(round(base * pow(1.0 + k, draws_this_stage)))


func reroll_cost() -> int:
	var c := draw_cost() * float(Data.gacha.reroll_cost_ratio)
	if f("reroll_discount") > 0:
		c *= 1.0 - f("reroll_discount")
	return int(round(c))


func can_afford(c: int) -> bool:
	return free_draws > 0 or gold >= c


func pay(c: int) -> bool:
	if free_draws > 0:
		free_draws -= 1
		return true
	if f("free_draw_chance") > 0 and rng.randf() < f("free_draw_chance"):
		message.emit("生財之道：本次參悟免費！")
		return true
	if gold < c:
		return false
	gold -= c
	gold_changed.emit()
	return true


func rarity_weights() -> Array:
	var out: Array = []
	var luck := st("luck")
	for r in Data.rarity_order:
		var row: Dictionary = Data.rarity[r]
		out.append(maxf(0.0, float(row.weight) * (1.0 + luck * float(row.luck_scale))))
	if since_legendary >= int(Data.gacha.soft_pity_start):
		out[3] += (since_legendary - int(Data.gacha.soft_pity_start) + 1) * float(Data.gacha.soft_pity_step)
	return out


func _pick_weighted(items: Array, weights: Array):
	var total := 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return null
	var x := rng.randf() * total
	for i in items.size():
		x -= weights[i]
		if x <= 0.0:
			return items[i]
	return items[items.size() - 1]


func _owned_weapon_lv(wid: String) -> int:
	for w in weapons:
		if w != null and w.id == wid:
			return int(w.lv)
	return 0


func _pool(rar: String, kind: String, seen: Dictionary) -> Array:
	## 回傳 [items, weights]
	var items: Array = []
	var weights: Array = []
	var own_mult: float = Data.gacha.owned_upgrade_weight_mult
	if kind == "W":
		for wid in FEATURED_WEAPONS:
			if Data.weapons[wid].rarity != rar or seen.has(wid):
				continue
			var lv := _owned_weapon_lv(wid)
			if lv >= MAX_LV:
				continue
			items.append(wid)
			weights.append(own_mult if lv > 0 else 1.0)
	else:
		var counts := sect_counts()
		var origin: String = Data.characters[char_id].origin_sect
		var full := martial.size() >= martial_slots()
		for mid in Data.martial:
			var m: Dictionary = Data.martial[mid]
			if m.rarity != rar or seen.has(mid):
				continue
			var lv: int = martial.get(mid, 0)
			if lv >= MAX_LV or (lv == 0 and full):
				continue
			var w := 1.0
			if lv > 0:
				w = own_mult
			else:
				var n := float(counts.get(m.sect, 0)) + (Data.cfg("origin_sect_count") if m.sect == origin else 0.0)
				w = minf(Data.cfg("sect_weight_cap"), 1.0 + Data.cfg("sect_weight_per_owned") * n)
			items.append(mid)
			weights.append(w)
	return [items, weights]


func roll_choices() -> Array:
	var n := int(Data.gacha.choices_per_draw) + int(f("extra_choice"))
	var cands: Array = []
	var seen := {}
	var weights := rarity_weights()
	var tries := 0
	while cands.size() < n and tries < 60:
		tries += 1
		var rar: String = _pick_weighted(Data.rarity_order, weights)
		if cands.is_empty() and since_legendary >= int(Data.gacha.hard_pity) - 1:
			rar = "legendary"
		var kind := "W" if rng.randf() < float(Data.gacha.weapon_pool_ratio) else "M"
		var p := _pool(rar, kind, seen)
		if p[0].is_empty() and kind == "W":
			kind = "M"
			p = _pool(rar, kind, seen)
		if p[0].is_empty():
			continue
		var id: String = _pick_weighted(p[0], p[1])
		seen[id] = true
		cands.append({"kind": kind, "id": id, "rarity": rar})
	# 唐門門主：必有一門唐門武學
	if f("guarantee_tangmen") > 0 and not cands.any(func(c): return c.kind == "M" and Data.martial[c.id].sect == "tangmen"):
		var opts: Array = []
		for mid in Data.martial:
			if Data.martial[mid].sect == "tangmen" and int(martial.get(mid, 0)) < MAX_LV and not seen.has(mid):
				opts.append(mid)
		if not opts.is_empty():
			var mid: String = opts[rng.randi() % opts.size()]
			var offer := {"kind": "M", "id": mid, "rarity": Data.martial[mid].rarity}
			if cands.is_empty(): cands.append(offer)
			else: cands[cands.size() - 1] = offer
	# 天命・圓滿：必有一個已習得武學的升級
	if f("guarantee_upgrade") > 0 and not cands.any(func(c): return c.kind == "M" and martial.has(c.id)):
		var opts: Array = []
		for mid in martial:
			if martial[mid] < MAX_LV and not seen.has(mid):
				opts.append(mid)
		if not opts.is_empty():
			var mid: String = opts[rng.randi() % opts.size()]
			var offer := {"kind": "M", "id": mid, "rarity": Data.martial[mid].rarity}
			if cands.is_empty(): cands.append(offer)
			else: cands[0] = offer
	if cands.any(func(c): return c.rarity == "legendary"):
		since_legendary = 0
	else:
		since_legendary += 1
	draws_this_stage += 1
	total_draws += 1
	return cands


func choose(c: Dictionary, replace_slot: int = -1) -> void:
	if c.kind == "W":
		for w in weapons:
			if w != null and w.id == c.id:
				w.lv = mini(MAX_LV, int(w.lv) + 1)
				if w.lv == MAX_LV:
					message.emit("器靈覺醒：%s" % Data.weapons[c.id].name_zh)
				recompute()
				return
		var slot := weapons.find(null)
		if slot == -1:
			slot = replace_slot if replace_slot >= 0 else 1
		weapons[slot] = {"id": c.id, "lv": 1}
	else:
		var lv: int = martial.get(c.id, 0) + 1
		if lv == 1:
			martial_order.append(c.id)
		martial[c.id] = lv
		var m: Dictionary = Data.martial[c.id]
		if lv == 3:
			martial_breakthrough.emit(c.id, 3, "小成：" + String(m.lv3_desc))
		elif lv == 5:
			martial_breakthrough.emit(c.id, 5, "圓滿：" + String(m.lv5_desc))
	recompute()


func describe(c: Dictionary) -> Dictionary:
	## 參悟卡片的顯示文字
	var out := {}
	if c.kind == "W":
		var w: Dictionary = Data.weapons[c.id]
		var lv := _owned_weapon_lv(c.id)
		out.title = w.name_zh
		out.sub = "武器・%s・%s" % [w["class"], {"melee": "近戰", "mid": "中距離", "ranged": "遠程"}[w.range_type]]
		out.level = "淬煉 +%d → +%d" % [lv, lv + 1] if lv > 0 else "新武器"
		out.body = "%s\n傷害 %s × %s 段，間隔 %s 秒，射程 %s m" % [w.pattern_desc, w.dmg, w.hits, w.interval_s, w.range_m]
		out.extra = "器靈覺醒（+5）：" + String(w.awaken_desc)
		out.needs_slot = lv == 0 and not weapons.has(null)
	else:
		var m: Dictionary = Data.martial[c.id]
		var lv: int = martial.get(c.id, 0)
		var stage_names := ["", "入門", "熟練", "小成", "大成", "圓滿"]
		out.title = m.name_zh
		out.sub = "武學・%s・%s" % [Data.sects[m.sect].name_zh, m.school]
		out.level = "%s → %s" % [stage_names[lv], stage_names[lv + 1]] if lv > 0 else "新習得"
		out.body = Data.martial_text(c.id, lv + 1)
		if lv + 1 <= 3:
			out.extra = "小成：" + String(m.lv3_desc)
		else:
			out.extra = "圓滿：" + String(m.lv5_desc)
		out.needs_slot = false
	out.rarity_name = Data.rarity[c.rarity].name_zh
	return out


# ------------------------------------------------------------------ 輸入
func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
		"jump": [KEY_SPACE], "dash": [KEY_SHIFT], "interact": [KEY_E], "inventory": [KEY_TAB],
		"pause": [KEY_ESCAPE],
	}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			for k in keys[a]:
				var ev := InputEventKey.new()
				ev.physical_keycode = k
				InputMap.action_add_event(a, ev)
	for pair in [["attack_1", MOUSE_BUTTON_LEFT], ["attack_2", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
			var mb := InputEventMouseButton.new()
			mb.button_index = pair[1]
			InputMap.action_add_event(pair[0], mb)
