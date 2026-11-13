extends Node
## 讀取 data/ 底下所有數值表（與平衡腳本共用同一份 CSV）

var rarity := {}            # rarity -> row
var rarity_order: Array = []
var stat_values := {}       # stat_id -> per_point
var stat_names := {}        # stat_id -> 中文名
var gacha := {}             # key -> value
var combat := {}            # key -> value
var shop := {}              # key -> value（掉落、鐵匠、商人）
var affixes := {}           # affix_id -> row（武器詞條）
var affix_order: Array = []
var characters := {}        # char_id -> row
var char_order: Array = []
var passives: Array = []
var realms: Array = []
var levels: Array = []      # index = level-1
var weapons := {}           # weapon_id -> row
var martial := {}           # martial_id -> row
var sects := {}             # sect_id -> row
var sect_order: Array = []
var bonds: Array = []
var maps := {}              # map_id -> row
var map_order: Array = []
var enemies := {}           # enemy_id -> row
var ranged_ai := {}         # enemy_id -> 遠程 AI 參數（ranged_ai.csv）
var music := {}             # key（menu 或 map_id）-> 配樂設定（music.csv）
var sfx := {}               # id -> 音效設定（sfx.csv）
var settings_cfg := {}      # key -> 設定預設值與範圍（settings_config.csv）
var settings_order: Array = []
var feel := {}              # 打擊感數值（feel_config.csv）
var combat_state := {}      # 戰鬥狀態數值（combat_state_config.csv）
var moves := {}             # move_id -> 招式（moves.csv），含 hits: Array（move_hits.csv）
var char_moves := {}        # char_id -> {slot: move_id}
var stages: Array = []      # index = stage-1
var stage_report: Array = []
var zones := {}             # "1".."20" -> layout
var meridians := {}         # meridian_id -> row（奇經八脈）
var meridian_order: Array = []
var acupoints := {}         # point_id -> row
var meridian_cfg := {}      # key -> value（衝穴）
var realm_list: Array = []  # index＝境界（0 三流 … 8 自然境）
var wheel_symbols := {}     # symbol_id -> row（天機輪符號）
var wheel_reels: Array = [] # 每軸的輪帶（Array of PackedStringArray）
var wheel_cfg := {}         # key -> value


func _ready() -> void:
	for r in _csv("rarity"):
		rarity[r.rarity] = r
		rarity_order.append(r.rarity)
	for r in _csv("stat_values"):
		stat_values[r.stat_id] = float(r.per_point)
		stat_names[r.stat_id] = r.name_zh
	gacha = _kv("gacha_config")
	combat = _kv("combat_config")
	shop = _kv("shop_config")
	for r in _csv("weapon_affixes"):
		affixes[r.affix_id] = r
		affix_order.append(r.affix_id)
	for r in _csv("characters"):
		characters[r.char_id] = r
		char_order.append(r.char_id)
	passives = _csv("character_passives")
	realms = _csv("character_realms")
	levels = _csv("character_levels")
	for r in _csv("weapons"):
		weapons[r.weapon_id] = r
	for r in _csv("martial_arts"):
		martial[r.martial_id] = r
	for r in _csv("sects"):
		sects[r.sect_id] = r
		sect_order.append(r.sect_id)
	bonds = _csv("sect_bonds")
	for r in _csv("maps"):
		maps[r.map_id] = r
	map_order = maps.keys()
	map_order.sort_custom(func(a, b): return int(maps[a].order) < int(maps[b].order))
	for r in _csv("enemies"):
		enemies[r.enemy_id] = r
	for r in _csv("ranged_ai"):
		ranged_ai[r.enemy_id] = r
	for r in _csv("music"):
		music[r.key] = r
	for r in _csv("sfx"):
		sfx[r.id] = r
	for r in _csv("settings_config"):
		settings_cfg[r.key] = r
		settings_order.append(r.key)
	feel = _kv("feel_config")
	combat_state = _kv("combat_state_config")
	for r in _csv("moves"):
		r["hits"] = []
		moves[r.move_id] = r
		if not char_moves.has(r.char_id):
			char_moves[r.char_id] = {}
		char_moves[r.char_id][r.slot] = r.move_id
	for r in _csv("move_hits"):
		moves[r.move_id].hits.append(r)
	for r in _csv("meridians"):
		meridians[r.meridian_id] = r
		meridian_order.append(r.meridian_id)
	for r in _csv("acupoints"):
		acupoints[r.point_id] = r
	meridian_cfg = _kv("meridian_config")
	realm_list = _csv("realms")
	for r in _csv("wheel_symbols"):
		wheel_symbols[r.symbol_id] = r
	var reels := _csv("wheel_reels")
	reels.sort_custom(func(a, b): return int(a.reel) < int(b.reel))
	for r in reels:
		wheel_reels.append(String(r.strip).split("|"))
	wheel_cfg = _kv("wheel_config")
	stages = _csv("stages")
	stage_report = _csv("stage_report")
	var f := FileAccess.open("res://data/zones.json", FileAccess.READ)
	zones = JSON.parse_string(f.get_as_text())


func _csv(name: String) -> Array:
	var path := "res://data/%s.csv" % name
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("無法讀取 " + path)
		return []
	var header := f.get_csv_line()
	var out: Array = []
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() < 2:
			continue
		var row := {}
		for i in header.size():
			row[header[i]] = line[i] if i < line.size() else ""
		out.append(row)
	return out


func _kv(name: String) -> Dictionary:
	var d := {}
	for r in _csv(name):
		var v: String = r.value
		d[r.key] = float(v) if v.is_valid_float() else v
	return d


func cfg(key: String) -> float:
	if combat.has(key):
		return float(combat[key])
	if shop.has(key):
		return float(shop[key])
	return float(gacha.get(key, 0.0))


func weights(key: String) -> Array:
	## 讀「a|b|c」格式的權重
	var out: Array = []
	for part in String(shop.get(key, "")).split("|", false):
		out.append(float(part))
	return out


func per_stage(key: String, stage: int) -> float:
	## 讀「a|b|c」依區排列的值，超過的區用最後一個
	var w := weights(key)
	if w.is_empty():
		return cfg(key)
	return w[clampi(stage, 1, w.size()) - 1]


func acupoint(mid: String, depth: int) -> Dictionary:
	return acupoints.get("%s%d" % [mid, depth], {})


func meridian_len(mid: String) -> int:
	var n := 0
	while acupoints.has("%s%d" % [mid, n + 1]):
		n += 1
	return n


func stat_text(stat: String, v: float) -> String:
	## 例：傷害+18%、每秒回血+1.2、幸運+0.12
	var s := ("%.2f" % v).rstrip("0").rstrip(".")
	var unit := "%" if stat.ends_with("_pct") else ""
	return "%s+%s%s" % [stat_names.get(stat, stat), s, unit]


func affix_text(a: Dictionary) -> String:
	## 武器詞條的顯示文字，例：鋒利　傷害+8%
	var row: Dictionary = affixes[a.id]
	var s := ("%.2f" % float(a.v)).rstrip("0").rstrip(".")
	return "%s　%s" % [row.name_zh, String(row.template).replace("{v}", s)]


func stage_row(stage: int) -> Dictionary:
	return stages[stage - 1]


func report_row(stage: int) -> Dictionary:
	return stage_report[stage - 1]


func rarity_color(r: String) -> Color:
	return Color(rarity[r].color) if rarity.has(r) else Color.WHITE


## 敵人在某區域的數值
func enemy_hp(eid: String, stage: int) -> float:
	return cfg("base_enemy_hp") * pow(cfg("enemy_hp_growth"), stage - 1) * float(enemies[eid].hp_mult)


func enemy_dmg(eid: String, stage: int) -> float:
	return cfg("base_enemy_dmg") * pow(cfg("enemy_dmg_growth"), stage - 1) * float(enemies[eid].dmg_mult)


func enemy_threat(eid: String) -> float:
	var e: Dictionary = enemies[eid]
	return float(e.hp_mult) * float(e.ehp_factor) * float(e.danger)


func enemy_rewards(eid: String) -> Vector2:
	## x = 真氣, y = 銀兩
	var e: Dictionary = enemies[eid]
	var m: Dictionary = maps[e.map_id]
	var base := enemy_threat(eid) * float(e.reward_mult)
	return Vector2(base * cfg("xiuwei_per_threat") * float(m.xiuwei_mult), base * cfg("gold_per_threat") * float(m.gold_mult))


## 武學 Lv 的數值
func martial_value(mid: String, lv: int) -> float:
	var m: Dictionary = martial[mid]
	return float(m.lv1_value) + float(m.per_level) * (lv - 1)


func martial_text(mid: String, lv: int) -> String:
	var v := martial_value(mid, lv)
	var s := ("%.2f" % v).rstrip("0").rstrip(".")
	return String(martial[mid].effect_template).replace("{v}", s)
