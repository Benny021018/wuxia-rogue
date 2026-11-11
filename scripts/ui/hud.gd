extends Control
## 戰鬥 HUD：生命、修為與境界、銀兩、武器、武學、區域資訊、首領血條、橫幅與訊息

var player
var hp_bar: ProgressBar
var shield_bar: ProgressBar
var hp_text: Label
var xw_bar: ProgressBar
var realm_text: Label
var gold_text: Label
var weapon_text: Label
var martial_text: Label
var zone_text: Label
var enemy_text: Label
var boss_box: VBoxContainer
var boss_bar: ProgressBar
var boss_name: Label
var boss
var banner: Label
var sub_banner: Label
var msg_box: VBoxContainer
var hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 準星
	var cross := UIKit.label("+", 28, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	UIKit.place(cross, 0.5, 0.5, -20, -22, 40, 40)
	add_child(cross)
	# 左下：生命、修為
	var vitals_back := Panel.new()
	UIKit.place(vitals_back, 0, 1, 16, -128, 556, 124)
	vitals_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vitals_back)
	var bl := VBoxContainer.new()
	UIKit.place(bl, 0.0, 1.0, 134, -200, 420, 190)
	bl.alignment = BoxContainer.ALIGNMENT_END
	add_child(bl)
	var portrait_frame := PanelContainer.new()
	UIKit.place(portrait_frame, 0, 1, 20, -116, 104, 104)
	portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait_frame)
	portrait_frame.add_child(UIKit.portrait(Game.char_id, Vector2(70, 70)))
	realm_text = UIKit.label("", 22, UIKit.GOLD)
	bl.add_child(realm_text)
	var hb := Control.new()
	hb.custom_minimum_size = Vector2(420, 26)
	bl.add_child(hb)
	hp_bar = UIKit.bar(UIKit.VERM, 26)
	hp_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.add_child(hp_bar)
	shield_bar = UIKit.bar(Color(1, 0.85, 0.4, 0.6), 8)
	shield_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	shield_bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	hb.add_child(shield_bar)
	hp_text = UIKit.label("", 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	hp_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.add_child(hp_text)
	xw_bar = UIKit.bar(UIKit.JADE, 10)
	bl.add_child(xw_bar)
	gold_text = UIKit.label("", 20, UIKit.GOLD)
	bl.add_child(gold_text)
	# 右下：武器
	weapon_text = UIKit.label("", 18)
	UIKit.place(weapon_text, 1.0, 1.0, -460, -110, 430, 90)
	weapon_text.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	weapon_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(weapon_text)
	# 右上：區域與武學
	var tr := VBoxContainer.new()
	UIKit.place(tr, 1.0, 0.0, -420, 24, 390, 300)
	add_child(tr)
	zone_text = UIKit.label("", 22, UIKit.PAPER, HORIZONTAL_ALIGNMENT_RIGHT)
	tr.add_child(zone_text)
	enemy_text = UIKit.label("", 18, UIKit.VERM.lightened(0.3), HORIZONTAL_ALIGNMENT_RIGHT)
	tr.add_child(enemy_text)
	martial_text = UIKit.label("", 15, UIKit.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	tr.add_child(martial_text)
	for field in [weapon_text, zone_text, enemy_text, martial_text]:
		field.add_theme_constant_override("outline_size", 4)
		field.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.05, 0.9))
	# 上方：首領血條
	boss_box = VBoxContainer.new()
	UIKit.place(boss_box, 0.5, 0.0, -400, 24, 800, 64)
	boss_box.visible = false
	add_child(boss_box)
	boss_name = UIKit.label("", 26, Color(1, 0.5, 0.4), HORIZONTAL_ALIGNMENT_CENTER)
	boss_box.add_child(boss_name)
	boss_bar = UIKit.bar(Color(0.7, 0.1, 0.1), 20)
	boss_box.add_child(boss_bar)
	# 中央橫幅
	banner = UIKit.label("", 64, UIKit.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	UIKit.place(banner, 0.5, 0.0, -600, 170, 1200, 90)
	banner.add_theme_constant_override("outline_size", 10)
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	banner.modulate.a = 0.0
	add_child(banner)
	sub_banner = UIKit.label("", 26, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	UIKit.place(sub_banner, 0.5, 0.0, -600, 262, 1200, 80)
	sub_banner.add_theme_constant_override("outline_size", 6)
	sub_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	sub_banner.modulate.a = 0.0
	add_child(sub_banner)
	# 左上：訊息
	msg_box = VBoxContainer.new()
	UIKit.place(msg_box, 0.0, 0.0, 30, 24, 520, 300)
	add_child(msg_box)
	# 下方提示
	hint = UIKit.label("", 20, UIKit.JADE.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER)
	UIKit.place(hint, 0.5, 1.0, -400, -260, 800, 40)
	add_child(hint)
	Game.message.connect(push_message)
	Game.martial_breakthrough.connect(func(mid, lv, desc): show_banner("%s・%s" % [Data.martial[mid].name_zh, "小成" if lv == 3 else "圓滿"], desc))
	Game.bond_activated.connect(func(sid, tier, nm): show_banner("門派傳承：%s" % nm, "%s 第%d階" % [Data.sects[sid].name_zh, tier]))
	Game.realm_broken.connect(func(lv, rn, eff): show_banner("突破・%s" % rn, eff))


func _process(_delta: float) -> void:
	if player == null:
		return
	var mh := Game.max_hp()
	hp_bar.max_value = mh
	hp_bar.value = player.hp
	shield_bar.max_value = mh
	shield_bar.value = player.shield
	hp_text.text = "%d / %d" % [int(player.hp), int(mh)]
	var need := Game.xiuwei_for_next()
	xw_bar.max_value = maxf(1.0, need)
	xw_bar.value = Game.xiuwei_into_level() if need > 0.0 else need
	realm_text.text = "%s　%s" % [Data.characters[Game.char_id].name_zh, Game.realm_name(Game.level)]
	gold_text.text = "銀兩 %d" % int(Game.gold) + ("　免費參悟 ×%d" % Game.free_draws if Game.free_draws > 0 else "")
	var wl: Array = []
	for i in 2:
		var w = Game.weapons[i]
		var key := "左鍵" if i == 0 else "右鍵"
		if w == null:
			wl.append("［%s］（空）" % key)
		else:
			wl.append("［%s］%s  淬煉+%d" % [key, Data.weapons[w.id].name_zh, int(w.lv)])
	weapon_text.text = "\n".join(wl)
	var ml: Array = []
	for mid in Game.martial_order:
		ml.append("%s Lv%d" % [Data.martial[mid].name_zh, Game.martial[mid]])
	martial_text.text = "武學 %d/%d：%s" % [Game.martial.size(), Game.martial_slots(), "、".join(ml)] if not ml.is_empty() else ""
	if boss and is_instance_valid(boss) and not boss.dead:
		boss_box.visible = true
		boss_bar.max_value = boss.max_hp
		boss_bar.value = boss.hp
	else:
		boss_box.visible = false


func set_zone(title: String) -> void:
	zone_text.text = title


func set_enemies(n: int) -> void:
	enemy_text.text = "剩餘敵人 %d" % n if n > 0 else ""


func set_boss(e) -> void:
	boss = e
	boss_name.text = e.row.name_zh
	show_banner(e.row.name_zh, e.row.special_desc)


func set_hint(t: String) -> void:
	hint.text = t


func show_banner(title: String, sub := "", color := UIKit.PAPER) -> void:
	banner.add_theme_color_override("font_color", color)
	banner.text = title
	sub_banner.text = sub
	for l in [banner, sub_banner]:
		var t := create_tween()
		t.tween_property(l, "modulate:a", 1.0, 0.25)
		t.tween_interval(2.2)
		t.tween_property(l, "modulate:a", 0.0, 0.6)


func push_message(t: String) -> void:
	var l := UIKit.label(t, 20, UIKit.GOLD)
	msg_box.add_child(l)
	if msg_box.get_child_count() > 6:
		msg_box.get_child(0).queue_free()
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)
