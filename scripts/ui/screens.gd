extends Control
## 全螢幕畫面：主選單、角色選擇、暫停、武學與門派面板、死亡與通關結算

signal start_run(char_id: String)
signal resume
signal to_menu
signal quit_game

var _selected := "nangong"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	visible = true


func hide_all() -> void:
	_clear()
	visible = false


# ------------------------------------------------------------------ 主選單
func show_main() -> void:
	_clear()
	var bg := TextureRect.new()
	bg.texture = preload("res://assets/ui/greenwood_pass.webp")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = Color(0.58, 0.62, 0.64)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var v := UIKit.center_box(self, 700)
	v.add_child(UIKit.label("天 魔 劫", 110, UIKit.PAPER, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.label("武俠 Roguelike・第一人稱", 26, UIKit.VERM.lightened(0.2), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.label("十年前，天魔神教血洗中原。如今天魔復活，綠林、暗月樓、屍門盡成爪牙。\n一路殺上天魔神教總壇，了結這場劫數。", 20, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 30)
	v.add_child(sp)
	for b in [UIKit.button("踏上江湖", show_select, 28), UIKit.button("操作說明", show_help, 24), UIKit.button("離開遊戲", func(): quit_game.emit(), 24)]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.custom_minimum_size = Vector2(320, 60)
		v.add_child(b)


func show_help() -> void:
	_clear()
	add_child(UIKit.overlay(0.95))
	var v := UIKit.center_box(self, 900)
	v.add_child(UIKit.label("操作說明", 44, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.label(
		"WASD 移動　滑鼠 視角　空白鍵 跳躍　Shift 衝刺（短暫無敵）\n" +
		"左鍵 左手武器　右鍵 右手武器（兩把可同時使用）\n" +
		"E 在悟道碑參悟　Tab 武學與門派面板　Esc 暫停\n\n" +
		"進入區域會「鎖陣」封住退路，殺光所有敵人後「破陣」。\n" +
		"破陣後悟道碑浮現，花銀兩參悟三選一：武器決定攻擊方式，武學強化自身。\n" +
		"重複參悟同一門武學會升級，Lv3 小成、Lv5 圓滿各有特殊效果。\n" +
		"同門派武學達 2／4／5 門啟動門派傳承。擊敗敵人累積修為，突破一流、絕頂、化境。", 22, UIKit.PAPER))
	var b := UIKit.button("返回", show_main)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)


# ------------------------------------------------------------------ 角色選擇
func show_select() -> void:
	_clear()
	add_child(UIKit.overlay(0.95))
	var v := UIKit.center_box(self, 1400)
	v.add_child(UIKit.label("選擇角色", 48, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	v.add_child(row)
	for cid in Data.char_order:
		row.add_child(_char_card(cid))
	var b := HBoxContainer.new()
	b.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(b)
	b.add_child(UIKit.button("返回", show_main))


func _char_card(cid: String) -> Control:
	var c: Dictionary = Data.characters[cid]
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(420, 520)
	var v := VBoxContainer.new()
	pc.add_child(v)
	var portrait := UIKit.portrait(cid, Vector2(0, 250))
	# 橫幅從頭頂取景，保留束髮與五官；HUD 仍使用完整方形立繪。
	var crop := AtlasTexture.new()
	crop.atlas = portrait.texture
	crop.region = Rect2(0, 0, crop.atlas.get_width(), crop.atlas.get_height() * 0.69)
	portrait.texture = crop
	v.add_child(portrait)
	v.add_child(UIKit.label(c.name_zh, 40, UIKit.PAPER))
	v.add_child(UIKit.label("%s・出身 %s" % [c.title, Data.sects[c.origin_sect].name_zh], 19, UIKit.VERM.lightened(0.3)))
	v.add_child(UIKit.label(c.bio, 17, UIKit.MUTED))
	v.add_child(UIKit.label("生命 %s　移速 %s m/s" % [c.hp, c.move_speed], 18, UIKit.PAPER))
	for p in Data.passives:
		if p.char_id == cid:
			var txt := String(p.effect_template).replace("{v}", str(float(p.lv1_value)).trim_suffix(".0"))
			v.add_child(UIKit.label("被動・%s：%s" % [p.name_zh, txt], 17, UIKit.GOLD))
	for r in Data.realms:
		if r.char_id == cid:
			v.add_child(UIKit.label("%s（Lv%s）%s：%s" % [r.realm_zh, r.level, r.name_zh, r.effect_desc], 15, UIKit.JADE.lightened(0.3)))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	v.add_child(UIKit.button("以此人出師", func(): start_run.emit(cid)))
	return pc


# ------------------------------------------------------------------ 暫停
func show_pause() -> void:
	_clear()
	add_child(UIKit.overlay(0.7))
	var v := UIKit.center_box(self, 520)
	v.add_child(UIKit.label("暫停", 52, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.label("%s　%s\n第 %d 區　銀兩 %d　已參悟 %d 次" % [Data.characters[Game.char_id].name_zh, Game.realm_name(Game.level), Game.stage, int(Game.gold), Game.total_draws], 20, UIKit.PAPER, HORIZONTAL_ALIGNMENT_CENTER))
	for b in [UIKit.button("繼續", func(): resume.emit()), UIKit.button("武學與門派", func(): show_inventory(true)), UIKit.button("放棄本局", func(): to_menu.emit())]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.custom_minimum_size = Vector2(320, 56)
		v.add_child(b)


# ------------------------------------------------------------------ 武學與門派
func show_inventory(from_pause := false) -> void:
	_clear()
	add_child(UIKit.overlay(0.85))
	var v := UIKit.center_box(self, 1500)
	v.add_child(UIKit.label("武學與門派傳承", 40, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	v.add_child(cols)
	# 左：角色與屬性
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(360, 560)
	cols.add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	lv.add_child(UIKit.label("%s　%s" % [Data.characters[Game.char_id].name_zh, Game.realm_name(Game.level)], 24, UIKit.PAPER))
	var lines: Array = ["生命 %d" % int(Game.max_hp()), "暴擊率 %.0f%%" % (float(Data.gacha.base_crit_rate_pct) + Game.st("crit_rate_pct")),
		"暴擊傷害 %.0f%%" % (float(Data.gacha.base_crit_dmg_pct) + Game.st("crit_dmg_pct"))]
	for k in ["dmg_pct", "atk_speed_pct", "lifesteal_pct", "dmg_reduction_pct", "dodge_pct", "move_speed_pct", "area_pct", "range_pct", "hp_regen", "gold_gain_pct", "xiuwei_gain_pct", "luck"]:
		if Game.st(k) != 0.0:
			lines.append("%s +%s" % [Data.stat_names.get(k, k), ("%.2f" % Game.st(k)).rstrip("0").rstrip(".")])
	lv.add_child(UIKit.label("\n".join(lines), 17, UIKit.MUTED))
	for i in 2:
		var w = Game.weapons[i]
		if w != null:
			lv.add_child(UIKit.label("%s：%s 淬煉+%d" % ["左手" if i == 0 else "右手", Data.weapons[w.id].name_zh, int(w.lv)], 18, Data.rarity_color(Data.weapons[w.id].rarity)))
	# 中：武學
	var mid := PanelContainer.new()
	mid.custom_minimum_size = Vector2(560, 560)
	cols.add_child(mid)
	var mv := VBoxContainer.new()
	mid.add_child(mv)
	mv.add_child(UIKit.label("武學 %d / %d" % [Game.martial.size(), Game.martial_slots()], 24, UIKit.PAPER))
	var names := ["", "入門", "熟練", "小成", "大成", "圓滿"]
	for mid_id in Game.martial_order:
		var m: Dictionary = Data.martial[mid_id]
		var lvl: int = Game.martial[mid_id]
		mv.add_child(UIKit.label("%s【%s・%s】%s" % [m.name_zh, Data.sects[m.sect].name_zh, names[lvl], Data.martial_text(mid_id, lvl)], 16, Data.rarity_color(m.rarity)))
	if Game.martial.is_empty():
		mv.add_child(UIKit.label("尚未習得武學。破陣後到悟道碑參悟。", 17, UIKit.MUTED))
	# 右：門派
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(500, 560)
	cols.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	rv.add_child(UIKit.label("門派傳承", 24, UIKit.PAPER))
	var counts := Game.sect_counts()
	for sid in Data.sect_order:
		var s: Dictionary = Data.sects[sid]
		if s.has_bond != "1":
			continue
		var n := int(counts.get(sid, 0))
		rv.add_child(UIKit.label("%s　%d 門　（%s）" % [s.name_zh, n, s.style], 19, UIKit.GOLD if n >= 2 else UIKit.MUTED))
		for b in Data.bonds:
			if b.sect_id == sid:
				var on := n >= int(b.count_required)
				rv.add_child(UIKit.label("　%s %s門・%s：%s" % ["●" if on else "○", b.count_required, b.name_zh, b.effect_desc], 14, UIKit.JADE.lightened(0.3) if on else Color(0.55, 0.53, 0.5)))
	var back := UIKit.button("返回" if from_pause else "關閉（Tab）", _inventory_back.bind(from_pause))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(back)


func _inventory_back(from_pause: bool) -> void:
	if from_pause:
		show_pause()
	else:
		resume.emit()


# ------------------------------------------------------------------ 結算
func show_end(won: bool) -> void:
	_clear()
	add_child(UIKit.overlay(0.9))
	var v := UIKit.center_box(self, 900)
	v.add_child(UIKit.label("天魔伏誅・通關" if won else "敗北・道消身殞", 64, UIKit.GOLD if won else UIKit.VERM.lightened(0.2), HORIZONTAL_ALIGNMENT_CENTER))
	var t := int(Game.run_time)
	var best: Array = []
	for mid in Game.martial_order:
		if Game.martial[mid] >= 3:
			best.append("%s Lv%d" % [Data.martial[mid].name_zh, Game.martial[mid]])
	var bonds: Array = []
	for sid in Game.bond_tiers:
		bonds.append("%s 第%d階" % [Data.sects[sid].name_zh, Game.bond_tiers[sid]])
	var ws: Array = []
	for w in Game.weapons:
		if w != null:
			ws.append("%s+%d" % [Data.weapons[w.id].name_zh, int(w.lv)])
	v.add_child(UIKit.label(
		"角色：%s　境界：%s\n抵達：第 %d 區（%s）\n擊殺：%d　參悟：%d 次　時間：%d 分 %02d 秒\n武器：%s\n精進武學：%s\n門派傳承：%s" % [
			Data.characters[Game.char_id].name_zh, Game.realm_name(Game.level), Game.stage, Data.stage_row(Game.stage).area_zh,
			Game.kills, Game.total_draws, t / 60, t % 60, "、".join(ws),
			"、".join(best) if not best.is_empty() else "無", "、".join(bonds) if not bonds.is_empty() else "無"],
		22, UIKit.PAPER, HORIZONTAL_ALIGNMENT_CENTER))
	var b := UIKit.button("回到主選單", func(): to_menu.emit())
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
