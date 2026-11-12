extends Node
const FEATURED_WEAPONS := ["W001","W007","W301"]

## 一局遊戲的狀態：角色、修為、銀兩、武器、武學、門派傳承，以及參悟（抽獎）邏輯

signal stats_changed
signal gold_changed
signal zhenqi_changed
signal acupoint_tried(point_id: String, ok: bool)
signal leveled_up(level: int)
signal realm_broken(realm: int, realm_name: String, effect: String)
signal martial_breakthrough(mid: String, lv: int, desc: String)
signal bond_activated(sect_id: String, tier: int, name: String)
signal message(text: String)
signal weapon_switched(slot: int)

const MAX_LV := 5

var char_id := "nangong"
var level := 1                         # 角色被動用的等級：依打通的穴位數換算（1～30）
var realm := 0                         # 境界：全通幾條經脈（0＝三流 … 8＝自然境）
var stage_zhenqi := 0.0                # 本區吸納的真氣（陰蹻脈・心靜神凝用）
var zhenqi := 0.0                      # 真氣：殺敵吸納，用來衝穴
var acu_open := {}                     # meridian_id -> 已依序打通的穴數
var acu_fails := {}                    # point_id -> 衝擊失敗次數（越多次成功率越高）
var shrine_charges := 0                # 本區悟道碑剩下的免費參悟
var wheel_free := 0                    # 天機輪・頓悟送的免費參悟（先用）
var wheel_last := {}                   # 上一次轉輪的結果 {stops, outcome, sect, scatters}
var refreshes_this_stage := 0
var gold := 0.0
var weapons: Array = [null, null]      # 0＝主武器、1＝副武器，每格 {id, lv, affixes, reforges}
var active_weapon := 0                 # 目前手上的武器格；同時只用一把
var merchant_stock: Array = []         # 商人上架的武學 [{id, rarity, sold}]
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
func new_run(cid: String, start_wid := "") -> void:
	char_id = cid
	level = 1
	realm = 0
	stage_zhenqi = 0.0
	zhenqi = 0.0
	acu_open = {}
	acu_fails = {}
	shrine_charges = 0
	wheel_free = 0
	wheel_last = {}
	refreshes_this_stage = 0
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
	# 開局自選一把起手武器（weapons.csv 的 starter 欄），沒有詞條
	var starters := starter_weapons()
	var first: String = start_wid if start_wid in starters else starters[0]
	weapons = [make_weapon(first, 0), null]
	active_weapon = 0
	merchant_stock = []
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
	# 角色的境界招式（一流＝2、絕頂＝3、化境＝5）
	for r in Data.realms:
		if r.char_id == char_id and int(r.realm) <= realm:
			match [char_id, String(r.realm_zh)]:
				["nangong", "一流"]: _flag("extra_hit_mult", 0.7)
				["nangong", "絕頂"]: _flag("extra_hit_qi", 0.5)
				["nangong", "化境"]: _flag("extra_hit_chain", 1)
				["han", "一流"]: _flag("low50_dr", 15)
				["han", "絕頂"]: _flag("kill_heal", 1.5)
				["han", "化境"]: _flag("blood_demon", 1)
				["tang", "一流"]: _flag("vs_poison_dmg", 20)
				["tang", "絕頂"]: _flag("poison_spread", 1)
				["tang", "化境"]: _flag("extra_choice", 1)
	# 境界本身的加成（realms.csv，累計值）
	var rr: Dictionary = Data.realm_list[realm]
	s["dmg_pct"] += float(rr.dmg_pct)
	s["max_hp_pct"] += float(rr.max_hp_pct)
	# 經脈：打通的穴位加屬性；整條全通啟動特殊效果（效果在 player.gd）
	for mid in acu_open:
		var n := acu_level(mid)
		for d in range(1, n + 1):
			var a: Dictionary = Data.acupoint(mid, d)
			s[a.stat_id] += float(a.value)
		if n >= Data.meridian_len(mid):
			_flag(String(Data.meridians[mid].special_id), 1)
	if ren_du_open():   # 小周天
		_add_points(s, "ren_du_stat", "ren_du_points")
	if realm >= Data.meridian_order.size():   # 大周天
		_add_points(s, "zhou_tian_stat", "zhou_tian_points")
	# 手上那把武器的詞條（收起的武器不生效）
	var held = current_weapon()
	if held != null:
		for a in held.get("affixes", []):
			s[Data.affixes[a.id].stat_id] += float(a.v)
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
		["M110", 5]: _flag("cost_growth_override", 0.25)
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


# ------------------------------------------------------------------ 主武器／副武器
func current_weapon():
	return weapons[active_weapon]


func switch_weapon(slot := -1) -> bool:
	## 切換到指定格（-1＝另一格）；該格沒有武器或已在手上時不切換
	var target := 1 - active_weapon if slot < 0 else slot
	if target == active_weapon or target < 0 or target > 1 or weapons[target] == null:
		return false
	active_weapon = target
	recompute()
	weapon_switched.emit(target)
	return true


static func slot_name(slot: int) -> String:
	return "主武器" if slot == 0 else "副武器"


static func starter_weapons() -> Array:
	var out: Array = []
	for wid in FEATURED_WEAPONS:
		if String(Data.weapons[wid].get("starter", "0")) == "1":
			out.append(wid)
	return out


# ------------------------------------------------------------------ 武器詞條與掉落
func weapon_hit_dmg(wid: String, lv: int) -> float:
	## 武器單段傷害（含淬煉，每級 +weapon_levelup_pct%）
	return float(Data.weapons[wid].dmg) * (1.0 + float(Data.gacha.weapon_levelup_pct) / 100.0 * (lv - 1))


func make_weapon(wid: String, affix_n: int) -> Dictionary:
	return {"id": wid, "lv": 1, "affixes": roll_affixes(wid, affix_n), "reforges": 0}


func roll_affixes(wid: String, n: int) -> Array:
	## 抽 n 條不重複的詞條；近戰、遠程限定詞條只出現在對應武器
	var kind: String = Data.weapons[wid].range_type
	var items: Array = []
	var weights: Array = []
	for aid in Data.affix_order:
		var row: Dictionary = Data.affixes[aid]
		var rt: String = row.range_type
		if rt == "melee" and kind == "ranged" or rt == "ranged" and kind == "melee":
			continue
		items.append(aid)
		weights.append(float(row.weight))
	var out: Array = []
	for i in mini(n, items.size()):
		var aid: String = _pick_weighted(items, weights)
		var k := items.find(aid)
		items.remove_at(k)
		weights.remove_at(k)
		var row: Dictionary = Data.affixes[aid]
		var tier := affix_tier(row)
		var lo: float = float(row.min) * tier
		var hi: float = float(row.max) * tier
		var v := rng.randf_range(lo, hi)
		v = snappedf(v, 0.01 if hi < 1.0 else (0.1 if hi <= 5.0 else 1.0))
		out.append({"id": aid, "v": v})
	return out


func affix_tier(row: Dictionary) -> float:
	## 詞條品階：越後面的區域掉的詞條數值越高（輸出詞條成長快、生存經濟詞條成長慢）
	var g: float = float(row.get("tier_growth", 0.0))
	return 1.0 + g * float(stage - 1)


func inherit_level(item: Dictionary, old) -> void:
	## 淬煉傳承：換上新武器時沿用被換下那把的淬煉等級（減 inherit_lv_loss）
	if old == null:
		return
	var lv: int = int(old.lv) - int(Data.cfg("inherit_lv_loss"))
	item.lv = clampi(maxi(int(item.lv), lv), 1, MAX_LV)


func affix_count(source: String) -> int:
	## source：minion／elite／boss／shrine，依 shop_config 的權重抽詞條數（1 起算）
	var w := Data.weights("affix_weights_" + source)
	if w.is_empty():
		return 1
	var idx: Array = range(w.size())
	return int(_pick_weighted(idx, w)) + 1


func roll_weapon_drop(rank: String) -> Dictionary:
	## 擊殺掉落：依敵人階級決定機率與詞條數；沒掉回傳空字典
	var chance := Data.cfg("drop_chance_" + rank) * (1.0 + st("luck") * Data.cfg("drop_luck_scale"))
	if rng.randf() >= chance:
		return {}
	# 武器不分品質：三把起手武器等機率
	var wid: String = FEATURED_WEAPONS[rng.randi() % FEATURED_WEAPONS.size()]
	return make_weapon(wid, affix_count(rank))


func pick_up(item: Dictionary):
	## 撿起掉落武器：副武器格空著就放進去，否則換掉手上那把；回傳被換下的武器（或 null）
	var old = null
	if weapons[1] == null:
		inherit_level(item, weapons[0])
		weapons[1] = item
	else:
		old = weapons[active_weapon]
		inherit_level(item, old)
		weapons[active_weapon] = item
	recompute()
	return old


# ------------------------------------------------------------------ 鐵匠與商人
func price_mult() -> float:
	return pow(1.0 + Data.cfg("price_stage_growth"), stage - 1)


func upgrade_cost(slot: int) -> int:
	## 強化（淬煉+1）的價格；無法強化時回傳 -1
	var w = weapons[slot]
	if w == null or int(w.lv) >= MAX_LV:
		return -1
	return int(round(Data.cfg("upgrade_cost_base") * pow(1.0 + Data.cfg("upgrade_cost_growth"), int(w.lv) - 1) * price_mult()))


func upgrade_weapon(slot: int) -> bool:
	var c := upgrade_cost(slot)
	if c < 0 or gold < c:
		return false
	gold -= c
	var w: Dictionary = weapons[slot]
	w.lv = int(w.lv) + 1
	if w.lv == MAX_LV:
		message.emit("器靈覺醒：%s" % Data.weapons[w.id].name_zh)
	gold_changed.emit()
	recompute()
	return true


func reforge_cost(slot: int) -> int:
	## 重鑄詞條的價格；沒有詞條（例如起手武器）時回傳 -1
	var w = weapons[slot]
	if w == null or w.get("affixes", []).is_empty():
		return -1
	return int(round(Data.cfg("reforge_cost_base") * pow(1.0 + Data.cfg("reforge_cost_growth"), int(w.get("reforges", 0))) * price_mult()))


func reforge_weapon(slot: int) -> bool:
	## 詞條數不變，全部重新抽
	var c := reforge_cost(slot)
	if c < 0 or gold < c:
		return false
	gold -= c
	var w: Dictionary = weapons[slot]
	w.affixes = roll_affixes(w.id, w.affixes.size())
	w.reforges = int(w.get("reforges", 0)) + 1
	gold_changed.emit()
	recompute()
	return true


func restock_merchant() -> void:
	## 商人上架：依稀有度、門派權重抽不重複的武學
	merchant_stock = []
	var seen := {}
	var weights := base_rarity_weights()
	var tries := 0
	while merchant_stock.size() < int(Data.cfg("merchant_slots")) and tries < 60:
		tries += 1
		var rar: String = _pick_weighted(Data.rarity_order, weights)
		var p := _pool(rar, "M", seen)
		if p[0].is_empty():
			continue
		var mid: String = _pick_weighted(p[0], p[1])
		seen[mid] = true
		merchant_stock.append({"id": mid, "rarity": rar, "sold": false})
	# 幸運把某些稀有度的權重壓到 0 時，補上其他還能學的武學
	for rar in Data.rarity_order:
		while merchant_stock.size() < int(Data.cfg("merchant_slots")):
			var p := _pool(rar, "M", seen)
			if p[0].is_empty():
				break
			var mid: String = _pick_weighted(p[0], p[1])
			seen[mid] = true
			merchant_stock.append({"id": mid, "rarity": rar, "sold": false})


func merchant_refresh_cost() -> int:
	return int(round(Data.cfg("merchant_refresh_cost") * price_mult()))


func refresh_merchant() -> bool:
	var c := merchant_refresh_cost()
	if gold < c:
		return false
	gold -= c
	gold_changed.emit()
	restock_merchant()
	return true


func martial_price(mid: String) -> int:
	return int(round(float(Data.rarity[Data.martial[mid].rarity].martial_price) * price_mult()))


func can_learn(mid: String) -> bool:
	var lv: int = martial.get(mid, 0)
	return lv < MAX_LV and (lv > 0 or martial.size() < martial_slots())


func buy_martial(i: int) -> bool:
	if i < 0 or i >= merchant_stock.size():
		return false
	var item: Dictionary = merchant_stock[i]
	var c := martial_price(item.id)
	if item.sold or gold < c or not can_learn(item.id):
		return false
	gold -= c
	gold_changed.emit()
	item.sold = true
	choose({"kind": "M", "id": item.id, "rarity": item.rarity})
	return true


# ------------------------------------------------------------------ 真氣、衝穴與境界
func realm_name(r := -1) -> String:
	return String(Data.realm_list[clampi(realm if r < 0 else r, 0, Data.realm_list.size() - 1)].name_zh)


func realm_list_ok() -> bool:
	## 冒煙測試用：目前境界的傷害加成有算進屬性
	return float(Data.realm_list[realm].dmg_pct) <= st("dmg_pct")


func special(mid: String, key: String) -> float:
	## 經脈全通特殊效果的數值（meridians.csv 的 special_a、special_b）
	return float(Data.meridians[mid]["special_" + key])


func special_on(mid: String) -> bool:
	return f(String(Data.meridians[mid].special_id)) > 0.0


func special_text(mid: String) -> String:
	var m: Dictionary = Data.meridians[mid]
	return String(m.special_desc).replace("{a}", _num(float(m.special_a))).replace("{b}", _num(float(m.special_b)))


static func _num(v: float) -> String:
	return ("%.2f" % v).rstrip("0").rstrip(".")


func _add_points(s: Dictionary, stat_key: String, pts_key: String) -> void:
	var sts := String(Data.meridian_cfg[stat_key]).split("|")
	var pts := String(Data.meridian_cfg[pts_key]).split("|")
	for i in sts.size():
		s[sts[i]] += float(pts[i]) * float(Data.stat_values[sts[i]])


func add_kill(eid: String) -> void:
	kills += 1
	var r := Data.enemy_rewards(eid)
	gold += r.y * (1.0 + st("gold_gain_pct") / 100.0)
	var zq: float = r.x * (1.0 + st("xiuwei_gain_pct") / 100.0)
	stage_zhenqi += zq
	add_zhenqi(zq)
	gold_changed.emit()


func add_zhenqi(v: float) -> void:
	zhenqi += v
	zhenqi_changed.emit()


func acu_level(mid: String) -> int:
	return int(acu_open.get(mid, 0))


func acu_total() -> int:
	var n := 0
	for mid in acu_open:
		n += int(acu_open[mid])
	return n


func next_point(mid: String) -> Dictionary:
	## 這條經脈下一個要衝的穴位；全通時回傳空字典
	return Data.acupoint(mid, acu_level(mid) + 1)


func ren_du_open() -> bool:
	return acu_level("ren") >= Data.meridian_len("ren") and acu_level("du") >= Data.meridian_len("du")


func break_cost() -> int:
	## 衝穴一次的真氣；隨已打通的穴位數成長
	var c: Dictionary = Data.meridian_cfg
	return int(round(float(c.cost_a) * pow(acu_total() + 1, float(c.cost_exp)) + float(c.cost_b)))


func break_chance(pid: String) -> float:
	var row: Dictionary = Data.acupoints[pid]
	return minf(1.0, float(row.base_chance) + float(Data.meridian_cfg.chance_step) * int(acu_fails.get(pid, 0)))


func try_break(mid: String) -> int:
	## 衝擊這條經脈的下一個穴位：1＝打通、0＝失敗（下次成功率更高）、-1＝不能衝
	var p := next_point(mid)
	if p.is_empty():
		return -1
	var c := break_cost()
	if zhenqi < c:
		return -1
	zhenqi -= c
	var pid: String = p.point_id
	var ok := rng.randf() < break_chance(pid)
	if ok:
		var had_ren_du := ren_du_open()
		acu_open[mid] = acu_level(mid) + 1
		acu_fails.erase(pid)
		_set_level(1 + int(floor(float(acu_total()) * 29.0 / float(Data.acupoints.size()))))
		var m: Dictionary = Data.meridians[mid]
		if acu_level(mid) >= Data.meridian_len(mid):
			message.emit("%s全通・%s" % [m.name_zh, m.special_name])
			_break_realm()
		if ren_du_open() and not had_ren_du:
			message.emit("打通任督二脈・小周天")
	else:
		acu_fails[pid] = int(acu_fails.get(pid, 0)) + 1
		zhenqi += c * float(Data.meridian_cfg.fail_refund)
	acupoint_tried.emit(pid, ok)
	zhenqi_changed.emit()
	recompute()
	return 1 if ok else 0


func _set_level(new_level: int) -> void:
	## 角色被動的等級：1＋打通穴位數×29÷總穴數（只影響被動數值，不再決定境界）
	new_level = mini(new_level, 30)
	while level < new_level:
		level += 1
	leveled_up.emit(level)   # 每打通一穴都觸發（頓悟心法・小成：回復生命）


func _break_realm() -> void:
	## 全通一條經脈＝進入下一個境界
	realm = mini(realm + 1, Data.realm_list.size() - 1)
	var eff := String(Data.realm_list[realm].title_zh)
	for r in Data.realms:
		if r.char_id == char_id and int(r.realm) == realm:
			eff = "%s：%s" % [r.name_zh, r.effect_desc]
	if f("realm_free_draw") > 0:
		free_draws += 1
	realm_broken.emit(realm, realm_name(), eff)
	if realm >= Data.meridian_order.size():
		message.emit("奇經八脈全通・大周天")


# ------------------------------------------------------------------ 參悟（抽獎）
func on_zone_cleared() -> void:
	## 破陣：悟道碑給本區的免費參悟次數
	shrine_charges += int(Data.per_stage("shrine_free_per_stage", stage))   # 沒用完的留到下一座悟道碑
	refreshes_this_stage = 0
	draws_this_stage = 0
	# 陰蹻脈・心靜神凝：破陣時額外獲得本區吸納真氣的 a%
	if special_on("yinqiao") and stage_zhenqi > 0.0:
		var bonus := stage_zhenqi * special("yinqiao", "a") / 100.0
		add_zhenqi(bonus)
		message.emit("心靜神凝：真氣 +%d" % int(bonus))
	stage_zhenqi = 0.0


func draws_left() -> int:
	return wheel_free + shrine_charges + free_draws


func take_draw() -> bool:
	## 參悟不花錢：先用頓悟送的，再用本區的次數，最後用武學給的額外次數
	if wheel_free > 0:
		wheel_free -= 1
		return true
	if shrine_charges > 0:
		shrine_charges -= 1
		return true
	if free_draws > 0:
		free_draws -= 1
		return true
	return false


func refresh_cost() -> int:
	## 刷新候選的價格；同一區每多刷新一次變貴
	if refreshes_this_stage == 0 and special_on("yinqiao"):
		return 0   # 陰蹻脈・心靜神凝：每區第一次刷新免費
	var g := Data.cfg("refresh_cost_growth")
	if f("cost_growth_override") > 0:
		g = f("cost_growth_override")
	var c := Data.cfg("refresh_cost_base") * price_mult() * pow(1.0 + g, refreshes_this_stage)
	if f("reroll_discount") > 0:
		c *= 1.0 - f("reroll_discount")
	return int(round(c))


func pay_refresh() -> bool:
	var c := refresh_cost()
	if f("free_draw_chance") > 0 and rng.randf() < f("free_draw_chance"):
		message.emit("生財之道：本次刷新免費！")
		refreshes_this_stage += 1
		return true
	if gold < c:
		return false
	gold -= c
	refreshes_this_stage += 1
	gold_changed.emit()
	return true


# ------------------------------------------------------------------ 天機輪
## 規則與數學模型見 tools/shrine_math/wheel.py（同一份 CSV；冒煙測試逐盤面比對兩邊的判定）
func wheel_spin() -> Array:
	## 轉一次：每軸均勻抽一個停輪位置（中線）
	var stops: Array = []
	for strip in Data.wheel_reels:
		stops.append(rng.randi_range(0, strip.size() - 1))
	return stops


func wheel_window(stops: Array) -> Array:
	## 畫面：每軸 [上, 中, 下]
	var out: Array = []
	for i in stops.size():
		var strip: PackedStringArray = Data.wheel_reels[i]
		var n := strip.size()
		var s := int(stops[i])
		out.append([strip[(s - 1 + n) % n], strip[s], strip[(s + 1) % n]])
	return out


func wheel_eval(stops: Array) -> Dictionary:
	## outcome：none／sense（門派感應）／resonance（門派共鳴）／bagua（八卦歸一）；scatters＝畫面上的悟
	var win := wheel_window(stops)
	var mid: Array = []
	var scat := 0
	for col in win:
		mid.append(col[1])
		for sym in col:
			if sym == "wu":
				scat += 1
	var res := {"stops": stops, "outcome": "none", "sect": "", "scatters": scat}
	if mid.all(func(x): return x == "bagua"):
		res.outcome = "bagua"
		return res
	var sect := _first_sect(mid)
	if sect != "" and mid.all(func(x): return x == sect or x == "bagua"):
		res.outcome = "resonance"
		res.sect = sect
		return res
	var two := mid.slice(0, 2)
	var sect2 := _first_sect(two)
	if sect2 != "" and two.all(func(x): return x == sect2 or x == "bagua"):
		res.outcome = "sense"
		res.sect = sect2
	return res


func _first_sect(syms: Array) -> String:
	for x in syms:
		if String(Data.wheel_symbols[x].kind) == "sect":
			return String(Data.wheel_symbols[x].sect_id)
	return ""


func wheel_roll(stops: Array) -> Array:
	## 依轉輪結果產生候選；頓悟時加免費參悟
	var r := wheel_eval(stops)
	wheel_last = r
	var free_n := int(Data.wheel_cfg.free_spins)
	if int(r.scatters) >= 3:
		wheel_free += free_n
		message.emit("頓悟！免費參悟 +%d" % free_n)
	match String(r.outcome):
		"sense":
			return roll_choices({"sect": r.sect, "sect_slots": int(Data.wheel_cfg.sense_sect_slots)})
		"resonance":
			return roll_choices({"sect": r.sect, "sect_slots": 99, "bump": int(Data.wheel_cfg.resonance_bump)})
		"bagua":
			return roll_choices({"legendary": true, "bump": int(Data.wheel_cfg.bagua_bump)})
	return roll_choices()


var _wheel_odds := {}


func wheel_odds() -> Dictionary:
	## 機率公示：窮舉全部停輪組合算出每轉的精確機率（和 tools/shrine_math/wheel.py 同一套判定）
	if not _wheel_odds.is_empty():
		return _wheel_odds
	var c := {"none": 0, "sense": 0, "resonance": 0, "bagua": 0, "trigger": 0, "total": 0}
	var L: Array = []
	for strip in Data.wheel_reels:
		L.append(strip.size())
	for a in L[0]:
		for b in L[1]:
			for d in L[2]:
				var r := wheel_eval([a, b, d])
				c[r.outcome] += 1
				if int(r.scatters) >= 3:
					c.trigger += 1
				c.total += 1
	var t := float(c.total)
	var p := float(c.trigger) / t
	_wheel_odds = {"sense": c.sense / t, "resonance": c.resonance / t, "bagua": c.bagua / t, "trigger": p,
		"spins": 1.0 / (1.0 - float(Data.wheel_cfg.free_spins) * p), "combos": c.total}
	return _wheel_odds


static func wheel_outcome_name(outcome: String) -> String:
	return {"none": "", "sense": "門派感應", "resonance": "門派共鳴", "bagua": "八卦歸一"}.get(outcome, "")


func base_rarity_weights() -> Array:
	## 稀有度權重（含幸運，不含天機保底）：掉落與商人用
	var out: Array = []
	var luck := st("luck")
	for r in Data.rarity_order:
		var row: Dictionary = Data.rarity[r]
		out.append(maxf(0.0, float(row.weight) * (1.0 + luck * float(row.luck_scale))))
	return out


func rarity_weights() -> Array:
	var out := base_rarity_weights()
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


func _sect_candidate(sect: String, rar: String, seen: Dictionary) -> Dictionary:
	## 指定門派的武學候選：先找同稀有度，沒有就往下找，再沒有就往上找
	var order: Array = Data.rarity_order
	var start := order.find(rar)
	var tries_order: Array = []
	for i in range(start, -1, -1):
		tries_order.append(order[i])
	for i in range(start + 1, order.size()):
		tries_order.append(order[i])
	for r in tries_order:
		var p := _pool(r, "M", seen)
		var items: Array = []
		var weights: Array = []
		for i in p[0].size():
			if String(Data.martial[p[0][i]].sect) == sect:
				items.append(p[0][i])
				weights.append(p[1][i])
		if not items.is_empty():
			return {"kind": "M", "id": _pick_weighted(items, weights), "rarity": r}
	return {}


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
			if lv > 0 and Data.cfg("shrine_weapon_upgrade") < 0.5:
				continue  # 淬煉交給鐵匠，悟道碑只出新武器
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


func roll_choices(o := {}) -> Array:
	## o（天機輪）：sect＋sect_slots＝前幾張保證是該門派武學；bump＝稀有度升幾階；legendary＝第一張必出絕世
	var n := int(Data.gacha.choices_per_draw) + int(f("extra_choice"))
	var cands: Array = []
	var seen := {}
	var weights := rarity_weights()
	var tries := 0
	var sect: String = o.get("sect", "")
	var sect_slots: int = int(o.get("sect_slots", 0))
	var bump: int = int(o.get("bump", 0))
	while cands.size() < n and tries < 60:
		tries += 1
		var rar: String = _pick_weighted(Data.rarity_order, weights)
		if bump > 0:
			rar = Data.rarity_order[mini(Data.rarity_order.find(rar) + bump, Data.rarity_order.size() - 1)]
		if cands.is_empty() and o.get("legendary", false) and not (_pool("legendary", "M", seen)[0].is_empty() and _pool("legendary", "W", seen)[0].is_empty()):
			rar = "legendary"   # 八卦歸一
		if cands.is_empty() and since_legendary >= int(Data.gacha.hard_pity) - 1 and not (_pool("legendary", "M", seen)[0].is_empty() and _pool("legendary", "W", seen)[0].is_empty()):
			rar = "legendary"   # 天機保底；已經沒有可出的絕世時不強制
		if sect != "" and cands.size() < sect_slots:
			var sc := _sect_candidate(sect, rar, seen)
			if not sc.is_empty():
				seen[sc.id] = true
				cands.append(sc)
				continue
		var kind := "W" if rng.randf() < float(Data.gacha.weapon_pool_ratio) else "M"
		var p := _pool(rar, kind, seen)
		if p[0].is_empty() and kind == "W":
			kind = "M"
			p = _pool(rar, kind, seen)
		if p[0].is_empty():
			continue
		var id: String = _pick_weighted(p[0], p[1])
		seen[id] = true
		var cand := {"kind": kind, "id": id, "rarity": rar}
		if kind == "W" and _owned_weapon_lv(id) == 0:
			cand.affixes = roll_affixes(id, affix_count("shrine"))
		cands.append(cand)
	# 武學全部圓滿、幸運又把凡品權重壓到接近 0 時，武器（全部同品質）仍可出現
	if cands.is_empty():
		for wid in FEATURED_WEAPONS:
			if _owned_weapon_lv(wid) == 0 and cands.size() < n:
				cands.append({"kind": "W", "id": wid, "rarity": Data.weapons[wid].rarity, "affixes": roll_affixes(wid, affix_count("shrine"))})
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
		var item := make_weapon(c.id, 0)
		item.affixes = c.get("affixes", [])
		inherit_level(item, weapons[slot] if weapons[slot] != null else weapons[0])
		weapons[slot] = item
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
		var lines: Array = []
		if lv == 0:
			for a in c.get("affixes", []):
				lines.append(Data.affix_text(a))
		out.extra = "詞條：" + "、".join(lines) if not lines.is_empty() else "器靈覺醒（+5）：" + String(w.awaken_desc)
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
	out.rarity_name = Data.rarity[c.rarity].name_zh if c.kind == "M" else String(Data.weapons[c.id]["class"])
	return out


# ------------------------------------------------------------------ 輸入
func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
		"jump": [KEY_SPACE], "dash": [KEY_SHIFT], "interact": [KEY_E], "inventory": [KEY_TAB], "meridian": [KEY_K],
		"pause": [KEY_ESCAPE],
	}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			for k in keys[a]:
				var ev := InputEventKey.new()
				ev.physical_keycode = k
				InputMap.action_add_event(a, ev)
	# 左鍵出招（弓：按住拉弓、放開射出）；右鍵瞄準；Q、滾輪切換主副武器；1、2 直接拿主武器、副武器
	var buttons := {"attack_1": [MOUSE_BUTTON_LEFT], "aim": [MOUSE_BUTTON_RIGHT], "switch_weapon": [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]}
	for a in buttons:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			for b in buttons[a]:
				var mb := InputEventMouseButton.new()
				mb.button_index = b
				InputMap.action_add_event(a, mb)
	for pair in [["switch_weapon", KEY_Q], ["weapon_main", KEY_1], ["weapon_sub", KEY_2]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		var ev := InputEventKey.new()
		ev.physical_keycode = pair[1]
		if not InputMap.action_has_event(pair[0], ev):
			InputMap.action_add_event(pair[0], ev)
