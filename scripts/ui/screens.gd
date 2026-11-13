extends Control
## 全螢幕畫面：主選單、操作說明、角色選擇、暫停、武學與門派面板、死亡與通關結算
## 版面對照 docs/ui-drafts/（座標沿用 1600×900 設計稿，以 UIKit.at 貼齊錨點）

signal start_run(char_id: String, weapon_id: String)
signal resume
signal to_menu
signal open_lan
signal quit_game

var _selected := "nangong"
var _weapon_sel := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _clear() -> void:
	set_meta("selecting", false)
	set_meta("picking_weapon", false)
	for c in get_children():
		remove_child(c)
		c.queue_free()
	visible = true


func hide_all() -> void:
	_clear()
	visible = false


func _at(c: Control, x: float, y: float, w: float, h: float, ax := 0.5, ay := 0.5) -> Control:
	return UIKit.at(self, c, x, y, w, h, ax, ay)


func _full(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	return c


func _fx() -> ComicFX:
	## 1600×900 的繪製層，置中；座標直接用設計稿座標
	var f := ComicFX.new()
	_at(f, 0, 0, 1600, 900)
	return f


func _focus_first(b: Control) -> void:
	(func():
		if is_instance_valid(b) and b.is_inside_tree() and b.is_visible_in_tree():
			b.grab_focus()).call_deferred()


# ------------------------------------------------------------------ 主選單
func show_main() -> void:
	_clear()
	_full(UIKit.backdrop("res://assets/ui/greenwood_pass.webp"))
	_full(UIKit.overlay(0.35))
	var glow := UIKit.bloom(UIKit.TEAL, 0.95)
	glow.modulate.a = 0.75
	_at(glow, 0, 30, 1120, 660)
	var lines := _fx()
	lines.add_speed_lines(Vector2(560, 360), 230, 1100, 110, Color(UIKit.INK, 0.55), 3, 1.3)
	_full(UIKit.vignette())
	var cut := _fx()
	cut.add_slash(Vector2(-60, 690), Vector2(1680, 170), 34)
	cut.add_splatter(Vector2(800, 330), 70, 70, UIKit.BLOOD, 5, 12)
	_at(UIKit.title("天魔劫", 200, UIKit.EMBER, 16, true, -3), 140, 220, 840, 230)
	_at(UIKit.box_text("narration", "十年前，天魔神教血洗中原。如今天魔復活，\n綠林、暗月樓、屍門盡成爪牙。\n一路殺上天魔神教總壇，了結這場劫數。", 21), 200, 500, 720, 124)
	var panel := UIKit.box("slant")
	panel.slant = 30
	_at(panel, 1060, 360, 470, 420)
	var first := UIKit.button("踏上江湖", show_select, 34, 380, 78)
	_at(first, 1100, 400, 380, 78)
	_at(UIKit.button("操作說明", show_help.bind(false), 28, 380, 66), 1100, 496, 380, 60)
	_at(UIKit.button("設定", show_settings.bind(false), 28, 380, 60), 1100, 572, 380, 60)
	_at(UIKit.button("離開遊戲", func(): quit_game.emit(), 28, 380, 60), 1100, 648, 380, 60)
	var multi := UIKit.button("",func(): open_lan.emit(),28,380,60)
	multi.accessibility_name = "多人遊玩"
	_at(multi,1100,710,380,60)
	var lettering := UIKit.multiplayer_title()
	multi.add_child(lettering)
	lettering.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lettering.offset_top = 4
	lettering.offset_bottom = -4
	var sparks := UIKit.fx()
	sparks.add_embers(Rect2(0, 560, 1600, 340), 70)
	sparks.drift = 26.0
	add_child(sparks)
	_at(UIKit.label("武俠 Roguelike・灰盒原型", 14, UIKit.GREY, HORIZONTAL_ALIGNMENT_RIGHT), 1270, 866, 300, 24, 1, 1)
	_focus_first(first)


func show_help(from_pause := false) -> void:
	_clear()
	_full(UIKit.overlay(0.96))
	var lines := _fx()
	lines.add_speed_lines(Vector2(800, 450), 420, 1200, 70, Color(UIKit.VIOLET, 0.8), 7, 1.3)
	_at(UIKit.title("操作說明", 64, UIKit.BONE, 9, false, -2), 500, 60, 600, 90)
	var keys := UIKit.box("system", "按鍵", 22)
	_at(keys, 210, 190, 1180, 160)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 12)
	keys.add_child(grid)
	for pair in [["WASD", "移動"], ["滑鼠", "視角"], ["空白鍵", "跳躍"], ["Shift", "閃避（短暫無敵）"],
			["左鍵", "普攻，連按接連段"], ["右鍵 Q E R 1 2 3", "七個技能"], ["V", "大招（怒氣滿）"], ["F", "參悟、鐵匠、商人"], ["K", "經脈"],
			["Tab", "武學與門派"], ["Esc", "暫停"]]:
		var row := HBoxContainer.new()
		var k := UIKit.box("chip", "", 4)
		k.fill = UIKit.INK
		k.border = UIKit.INK
		k.set_padding(3, 10)
		var key_label := UIKit.label(pair[0], 17, UIKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER)
		key_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		k.add_child(key_label)
		row.add_child(k)
		var what := UIKit.label(pair[1], 18, UIKit.INK)
		what.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(what)
		row.custom_minimum_size.x = 260
		grid.add_child(row)
	_at(UIKit.box_text("narration",
		"進入區域會「鎖陣」封住退路，殺光所有敵人後「破陣」。\n" +
		"破陣後悟道碑浮現，轉天機輪參悟三選一，武學強化自身。\n" +
		"敵人會被打出硬直、挑上半空、打倒在地；精英與首領有霸體，要用破霸體的招式打斷。\n" +
		"重複參悟同一門武學會升級，Lv3 小成、Lv5 圓滿各有特殊效果。\n" +
		"同門派武學達 2／4／5 門啟動門派傳承。擊敗敵人吸納真氣，按 K 衝擊奇經八脈的穴位，打通越多境界越高。", 21, "", HORIZONTAL_ALIGNMENT_LEFT), 210, 400, 1180, 250)
	var back := UIKit.button("返回", show_pause if from_pause else show_main, 22, 200, 50)
	_at(back, 700, 700, 200, 50)
	_focus_first(back)


# ------------------------------------------------------------------ 角色選擇
func show_select() -> void:
	_clear()
	_full(UIKit.overlay(1.0))
	var lines := _fx()
	lines.add_speed_lines(Vector2(800, 450), 380, 1100, 80, UIKit.VIOLET, 21, 1.5)
	_at(UIKit.title("選擇角色", 70, UIKit.BONE, 9, false, -2), 500, 40, 600, 90)
	for i in Data.char_order.size():
		_char_card(Data.char_order[i], i)
	set_meta("selecting", true)
	_at(UIKit.button("返回", show_main, 22, 200, 50), 1330, 836, 200, 50)


func _char_card(cid: String, i: int) -> void:
	var c: Dictionary = Data.characters[cid]
	var on := cid == _selected
	var x := 92.0 + i * 486.0
	var y := 150.0
	var w := 450.0
	var h := 660.0
	var k := 46.0
	var ph := 300.0
	var card := UIKit.box("slant")
	card.slant = k
	card.fill = UIKit.INK if on else UIKit.INK2
	card.border = UIKit.BLOOD if on else Color("#3a363e")
	card.glow = on
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_input.bind(cid))
	_at(card, x, y, w, h)
	if on:
		var glow := UIKit.bloom(UIKit.TEAL, 0.9)
		glow.modulate.a = 0.55
		_at(glow, x + 20, y + 120, w - 40, 300)
	var top := PackedVector2Array([Vector2(k + 10, 0), Vector2(w + 10, 0), Vector2(w + 10 - k * (ph - 34) / h, ph - 34), Vector2(10 + k - k * (ph + 8) / h, ph + 8)])
	var pic := UIKit.clipped(UIKit.portrait_crop(cid, (w + 20) / (ph + 10), 0.30, 0.40), top, UIKit.BONE, 0.0, not on)
	_at(pic, x - 10, y, w + 20, ph + 10)
	var edge := ComicFX.new()
	edge.add_line(PackedVector2Array([top[2], top[3]]), UIKit.BONE if on else UIKit.GREY, 5.0)
	_at(edge, x - 10, y, w + 20, ph + 10)
	_at(UIKit.title(c.name_zh, 66, UIKit.BONE if on else Color("#b9b3bb"), 10, false, -3, HORIZONTAL_ALIGNMENT_LEFT), x + 34, y + ph - 64, 330, 90)
	var sect_seal := UIKit.seal(Data.sects[c.origin_sect].name_zh, UIKit.BLOOD if on else Color("#4a2a2e"), 22, 4)
	_at(sect_seal, x + w - 92 - sect_seal.size.x / 2.0, y + ph - 22, sect_seal.size.x, sect_seal.size.y)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(v, x + 34, y + ph + 30, w - 76, h - ph - 36)
	v.add_child(UIKit.label(String(c.title), 21, UIKit.EMBER if on else UIKit.GREY, HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.label(String(c.bio), 16, Color("#c9c2cb") if on else Color("#6f6a72")))
	var stats := UIKit.box_text("system" if on else "system_dark", "生命 %s　移速 %s m/s" % [c.hp, c.move_speed], 17, "", HORIZONTAL_ALIGNMENT_LEFT)
	stats.set_padding(7, 18)
	if not on:
		stats.accent = Color("#3b4a4c")
	stats.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	stats.custom_minimum_size.x = w - 120
	v.add_child(stats)
	for p in Data.passives:
		if p.char_id == cid:
			var txt := String(p.effect_template).replace("{v}", str(float(p.lv1_value)).trim_suffix(".0"))
			v.add_child(_tagged_line("被動", "%s：%s" % [p.name_zh, txt], UIKit.EMBER if on else Color("#3a2a26"), UIKit.BONE if on else Color("#7d7880")))
	var realms := HFlowContainer.new()
	realms.add_theme_constant_override("h_separation", 14)
	realms.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(realms)
	for r in Data.realms:
		if r.char_id == cid:
			var line := UIKit.label("◆ %s・%s" % [r.realm_zh, r.name_zh], 14, UIKit.TEAL if on else Color("#3e5b5d"))
			line.autowrap_mode = TextServer.AUTOWRAP_OFF
			line.tooltip_text = "%s（全通 %s 條經脈）%s：%s" % [r.realm_zh, r.realm, r.name_zh, r.effect_desc]
			line.mouse_filter = Control.MOUSE_FILTER_PASS
			realms.add_child(line)
	if on:
		var go := UIKit.button("選定此人", func(): start_run.emit(_selected, ""), 26, 300, 58)
		_at(go, x + 60, y + h + 18, 300, 58)
		_focus_first(go)


func _weapon_badge(x: float, y: float, size: float, weapon_class: String, color: Color) -> void:
	var f := ComicFX.new()
	var sq := PackedVector2Array([Vector2(0, 0), Vector2(size, 0), Vector2(size, size), Vector2(0, size)])
	f.add_poly(sq, UIKit.INK)
	f.add_weapon_icon(Vector2(size, size) / 2.0, weapon_class, size / 110.0, color)
	f.add_outline(sq, color, 2.0)
	_at(f, x, y, size, size)


func _tagged_line(tag: String, text: String, tag_color: Color, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip := UIKit.box("chip", "", 2)
	chip.fill = tag_color
	chip.border = tag_color
	chip.set_padding(1, 6)
	chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var tl := UIKit.label(tag, 14, UIKit.INK if tag_color.v > 0.5 else UIKit.GREY)
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	chip.add_child(tl)
	row.add_child(chip)
	var l := UIKit.label(text, 15, color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row


func _on_card_input(event: InputEvent, cid: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if cid == _selected:
			start_run.emit(_selected, "")
		else:
			_selected = cid
			show_select()


func _unhandled_key_input(event: InputEvent) -> void:
	## 角色選擇：← → 切換
	if not visible or get_child_count() == 0 or not event.is_pressed():
		return
	var ke := event as InputEventKey
	if ke == null:
		return
	var keycode := ke.physical_keycode
	if has_meta("settings_from") and keycode == KEY_ESCAPE:
		_settings_back()
		get_viewport().set_input_as_handled()
		return
	if not get_meta("selecting", false):
		return
	var i := Data.char_order.find(_selected)
	if keycode == KEY_LEFT or keycode == KEY_A:
		_selected = Data.char_order[(i + Data.char_order.size() - 1) % Data.char_order.size()]
	elif keycode == KEY_RIGHT or keycode == KEY_D:
		_selected = Data.char_order[(i + 1) % Data.char_order.size()]
	elif keycode == KEY_ESCAPE:
		show_main()
		return
	else:
		return
	show_select()
	get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ 設定（docs/ui-drafts/15-settings.svg）
const SETTING_GROUPS := [["聲音", ["master_volume", "music_volume", "sfx_volume"]],
	["操作與畫面", ["mouse_sens", "screen_shake", "hitstop", "damage_numbers", "fullscreen"]]]
var settings_sliders := {}      # key -> ComicSlider（測試用）


func show_settings(from_pause := false) -> void:
	_clear()
	set_meta("settings_from", "pause" if from_pause else "main")
	if not from_pause:
		_full(UIKit.backdrop("res://assets/ui/greenwood_pass.webp"))
	_full(UIKit.overlay(0.7))
	var lines := _fx()
	lines.add_speed_lines(Vector2(330, 450), 300, 1200, 80, Color(UIKit.INK, 0.7), 61, 1.5)
	_at(UIKit.title("設定", 150, UIKit.BONE, 14, false, -5), 80, 200, 500, 170)
	_at(UIKit.box_text("narration", "音量即時生效，\n設定會自動保存。", 22), 110, 420, 440, 120)
	var panel := UIKit.box("slant")
	panel.slant = 30
	_at(panel, 640, 110, 880, 690)
	settings_sliders.clear()
	var y := 140.0
	var first: Control = null
	for g in SETTING_GROUPS:
		_at(UIKit.label(g[0], 18, UIKit.TEAL), 690, y, 300, 26)
		y += 32.0
		for key in g[1]:
			var c := _setting_row(key, y)
			if first == null:
				first = c
			y += 64.0 if not Settings.is_toggle(key) else 54.0
		y += 18.0
	_at(UIKit.button("恢復預設", func(): Settings.reset_defaults(); show_settings(from_pause), 22, 220, 54), 1000, 730, 220, 54)
	_at(UIKit.button("返回", _settings_back, 24, 220, 54, "Esc"), 1240, 730, 220, 54)
	_focus_first(first)


func _setting_text(key: String) -> String:
	var v := Settings.get_value(key)
	if key == "mouse_sens":
		return "%.2f×" % v
	return "%d%%" % int(round(v * 100.0))


func _setting_row(key: String, y: float) -> Control:
	var row: Dictionary = Data.settings_cfg[key]
	_at(UIKit.label(row.label_zh, 24, UIKit.BONE, HORIZONTAL_ALIGNMENT_LEFT, true), 700, y, 200, 40)
	if Settings.is_toggle(key):
		var on := Settings.on(key)
		var btns: Array = []
		for i in 2:
			var want := i == 0
			var b := UIKit.button("開" if want else "關", func():
				Settings.set_value(key, 1.0 if want else 0.0)
				_style_toggle(btns, Settings.on(key)), 20, 96, 38)
			_at(b, 900 + i * 110, y, 96, 38)
			btns.append(b)
		_style_toggle(btns, on)
		return btns[0]
	var sl := ComicSlider.new()
	sl.min_value = Settings.lo(key)
	sl.max_value = Settings.hi(key)
	sl.step = Settings.step(key)
	sl.value = Settings.get_value(key)
	_at(sl, 900, y - 6, 430, 44)
	var val := UIKit.label(_setting_text(key), 22, UIKit.BONE, HORIZONTAL_ALIGNMENT_RIGHT)
	_at(val, 1350, y, 110, 40)
	sl.value_changed.connect(func(v):
		Settings.set_value(key, v)
		val.text = _setting_text(key)
		if key == "sfx_volume" or key == "master_volume":
			Sfx.play("ui_hover"))
	settings_sliders[key] = sl
	return sl


func _style_toggle(btns: Array, on: bool) -> void:
	for i in btns.size():
		btns[i].set_meta("toggle", true)
		btns[i].selected = (i == 0) == on


func _settings_back() -> void:
	var from: String = get_meta("settings_from", "main")
	remove_meta("settings_from")
	if from == "pause":
		show_pause()
	else:
		show_main()


# ------------------------------------------------------------------ 暫停
func show_pause() -> void:
	_clear()
	_full(UIKit.overlay(0.62))
	var lines := _fx()
	lines.add_speed_lines(Vector2(420, 450), 330, 1200, 90, Color(UIKit.INK, 0.7), 51, 1.6)
	lines.add_slash(Vector2(-40, 900), Vector2(900, -40), 20)
	_at(UIKit.title("暫停", 150, UIKit.BONE, 14, false, -5), 170, 220, 500, 170)
	_at(UIKit.box_text("narration", "%s　%s\n第 %d 區　銀兩 %d　已參悟 %d 次" % [Data.characters[Game.char_id].name_zh, Game.realm_name(), Game.stage, int(Game.gold), Game.total_draws], 21), 170, 410, 500, 110)
	var panel := UIKit.box("slant")
	panel.slant = 30
	_at(panel, 900, 250, 520, 420)
	var first := UIKit.button("繼續", func(): resume.emit(), 32, 400, 72)
	_at(first, 960, 300, 400, 72)
	_at(UIKit.button("武學與門派", show_inventory.bind(true), 26, 400, 64), 960, 404, 400, 64)
	_at(UIKit.button("操作說明", show_help.bind(true), 26, 400, 56), 960, 488, 400, 56)
	_at(UIKit.button("設定", show_settings.bind(true), 26, 400, 56), 960, 556, 400, 56)
	_at(UIKit.button("放棄本局", _confirm_quit, 22, 400, 50), 960, 626, 400, 50)
	_at(UIKit.label("Esc 繼續", 16, UIKit.GREY, HORIZONTAL_ALIGNMENT_CENTER), 960, 694, 400, 26)
	_focus_first(first)


func _confirm_quit() -> void:
	var shade := UIKit.overlay(0.6)
	add_child(shade)
	var b := UIKit.box("system", "放棄本局", 28)
	_at(b, 560, 330, 480, 240)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 26)
	b.add_child(v)
	v.add_child(UIKit.label("確定放棄？本局進度不會保留。", 24, UIKit.BLOOD, HORIZONTAL_ALIGNMENT_CENTER, true))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	v.add_child(row)
	row.add_child(UIKit.button("放棄", func(): to_menu.emit(), 22, 170, 52))
	var keep := UIKit.button("取消", show_pause, 22, 170, 52)
	row.add_child(keep)
	_focus_first(keep)


# ------------------------------------------------------------------ 武學與門派
func show_inventory(from_pause := false) -> void:
	_clear()
	_full(UIKit.overlay(0.86))
	_at(UIKit.title("武學與門派傳承", 62, UIKit.BONE, 9, false, -1), 400, 34, 800, 90)
	_inventory_character(40, 130, 380, 680)
	_inventory_martial(450, 130, 620, 680)
	_inventory_sects(1100, 130, 460, 680)
	var back := UIKit.button("返回" if from_pause else "關閉（Tab）", _inventory_back.bind(from_pause), 20, 200, 50)
	_at(back, 700, 836, 200, 50)
	_focus_first(back)


func _inventory_character(x: float, y: float, w: float, h: float) -> void:
	var panel := UIKit.box("slant")
	panel.slant = 24
	_at(panel, x, y, w, h)
	var pclip := PackedVector2Array([Vector2(30, 10), Vector2(w - 30, 10), Vector2(w - 46, 180), Vector2(12, 180)])
	var bg := UIKit.bloom(UIKit.SECT_COLORS.get(String(Data.characters[Game.char_id].origin_sect), UIKit.TEAL), 0.6)
	_at(bg, x + 20, y + 10, w - 40, 180)
	_at(UIKit.clipped(UIKit.portrait_crop(Game.char_id, (w - 20) / 190.0, 0.42, 0.45), pclip, UIKit.BONE, 3.0), x + 10, y + 10, w - 20, 190)
	_at(UIKit.title(Data.characters[Game.char_id].name_zh, 44, UIKit.BONE, 8, false, -2, HORIZONTAL_ALIGNMENT_LEFT), x + 26, y + 196, 220, 64)
	var realm := _chip(Game.realm_name(), UIKit.TEAL, UIKit.INK, 15)
	_at(realm, x + 226, y + 210, 140, 28)
	var lines: Array = ["生命　%d" % int(Game.max_hp()), "暴擊率　%.0f%%" % (float(Data.gacha.base_crit_rate_pct) + Game.st("crit_rate_pct")),
		"暴擊傷害　%.0f%%" % (float(Data.gacha.base_crit_dmg_pct) + Game.st("crit_dmg_pct"))]
	for key in ["dmg_pct", "atk_speed_pct", "lifesteal_pct", "dmg_reduction_pct", "dodge_pct", "move_speed_pct", "area_pct", "range_pct", "hp_regen", "gold_gain_pct", "xiuwei_gain_pct", "luck"]:
		if Game.st(key) != 0.0 and lines.size() < 9:
			lines.append("%s　+%s" % [Data.stat_names.get(key, key), ("%.2f" % Game.st(key)).rstrip("0").rstrip(".")])
	var stats := UIKit.box_text("system", "\n".join(lines), 17, "屬性", HORIZONTAL_ALIGNMENT_LEFT)
	stats.set_padding(18, 20)
	stats.get_meta("label").vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_at(stats, x + 30, y + 276, w - 70, 246)
	_at(UIKit.label("武器　Q／滾輪切換", 15, UIKit.GREY), x + 30, y + 536, w - 60, 24)
	for i in 2:
		var row_y := y + 566 + i * 50
		var wpn = Game.weapons[i]
		var row := UIKit.box("slant")
		row.slant = 12
		row.fill = UIKit.INK2
		row.border = (UIKit.TEAL if i == Game.active_weapon else UIKit.BONE) if wpn != null else UIKit.DIM
		_at(row, x + 26, row_y, w - 66, 40)
		_at(UIKit.label(Game.slot_name(i), 14, UIKit.TEAL if i == Game.active_weapon else UIKit.GREY), x + 46, row_y + 9, 70, 24)
		if wpn == null:
			_at(UIKit.label("（空）", 18, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true), x + 116, row_y + 6, 200, 30)
			continue
		var wl := UIKit.label(Data.weapons[wpn.id].name_zh, 19, UIKit.BONE, HORIZONTAL_ALIGNMENT_LEFT, true)
		var tips: Array = []
		for a in wpn.get("affixes", []):
			tips.append("◆ " + Data.affix_text(a))
		wl.tooltip_text = "%s　淬煉+%d\n%s" % [Data.weapons[wpn.id].name_zh, int(wpn.lv), "\n".join(tips) if not tips.is_empty() else "（沒有詞條）"]
		wl.mouse_filter = Control.MOUSE_FILTER_PASS
		_at(wl, x + 116, row_y + 5, 170, 30)
		if not tips.is_empty():
			_at(UIKit.label("詞條 %d" % tips.size(), 13, UIKit.TEAL), x + 230, row_y + 11, 70, 20)
		_at(UIKit.label("淬煉+%d" % int(wpn.lv), 15, UIKit.EMBER if int(wpn.lv) > 1 else UIKit.GREY, HORIZONTAL_ALIGNMENT_RIGHT), x + w - 150, row_y + 9, 90, 24)


func _inventory_martial(x: float, y: float, w: float, h: float) -> void:
	var panel := UIKit.box("slant")
	panel.slant = 24
	_at(panel, x, y, w, h)
	_at(UIKit.label("武學", 26, UIKit.BONE, HORIZONTAL_ALIGNMENT_LEFT, true), x + 40, y + 18, 80, 36)
	_at(UIKit.label("%d / %d" % [Game.martial.size(), Game.martial_slots()], 22, UIKit.EMBER), x + 106, y + 22, 100, 32)
	_at(UIKit.label("◆ 小成、圓滿解鎖特效　游標停留看全文", 14, UIKit.GREY, HORIZONTAL_ALIGNMENT_RIGHT), x + w - 360, y + 30, 320, 24)
	var slots: int = Game.martial_slots()
	var gap := minf(74.0, (h - 80.0) / maxf(1.0, slots))
	for i in slots:
		var row_y := y + 70 + i * gap
		var rh := gap - 14.0
		if i >= Game.martial_order.size():
			var empty := ComicFX.new()
			empty.add_outline(PackedVector2Array([Vector2(44, 0), Vector2(w - 30, 0), Vector2(w - 42, rh), Vector2(32, rh)]), Color("#3a363e"), 2.0)
			_at(empty, x, row_y, w, rh)
			_at(UIKit.label("空", 18, UIKit.DIM, HORIZONTAL_ALIGNMENT_CENTER, true), x, row_y + rh / 2.0 - 14, w, 28)
			continue
		var mid: String = Game.martial_order[i]
		var m: Dictionary = Data.martial[mid]
		var lv: int = Game.martial[mid]
		var brk := lv >= 3
		var row := UIKit.box("slant")
		row.slant = 12
		row.fill = UIKit.INK2
		row.border = UIKit.EMBER if brk else Color("#4b4650")
		row.glow = lv == 5
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		var tip: Array = []
		for l in range(1, 6):
			tip.append("%s　%s" % [UIKit.LV_NAMES[l], Data.martial_text(mid, l)])
		tip.append("◆ 小成：%s" % m.lv3_desc)
		tip.append("◆ 圓滿：%s" % m.lv5_desc)
		row.tooltip_text = "%s【%s・%s】\n%s" % [m.name_zh, Data.sects[m.sect].name_zh, m.school, "\n".join(tip)]
		_at(row, x + 32, row_y, w - 62, rh)
		var sect_col: Color = UIKit.SECT_COLORS.get(String(m.sect), UIKit.GREY)
		var badge := _chip(String(Data.sects[m.sect].name_zh).left(1), sect_col, UIKit.INK, 26, true)
		_at(badge, x + 48, row_y + rh / 2.0 - 22, 44, 44)
		var name_col: Color = UIKit.BONE if m.rarity == "common" else UIKit.rarity_color(m.rarity)
		_at(UIKit.label(m.name_zh, 22, name_col, HORIZONTAL_ALIGNMENT_LEFT, true), x + 106, row_y + 2, 260, 30)
		_at(_chip(UIKit.LV_NAMES[lv], UIKit.EMBER if brk else Color("#3b363f"), UIKit.INK if brk else UIKit.BONE, 13), x + 108, row_y + 34, 46, 20)
		var eff := Data.martial_text(mid, lv)
		if brk:
			eff += "　◆" + String(m.lv5_desc if lv == 5 else m.lv3_desc)
		var el := UIKit.label(eff, 14, Color("#c9c2cb"))
		el.autowrap_mode = TextServer.AUTOWRAP_OFF
		el.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		el.clip_text = true
		_at(el, x + 164, row_y + 34, w - 220, 22)
		var p := UIKit.pips(lv, 5, 12.0)
		_at(p, x + w - 160, row_y + 12, 110, 20)


func _inventory_sects(x: float, y: float, w: float, h: float) -> void:
	var panel := UIKit.box("slant")
	panel.slant = 24
	_at(panel, x, y, w, h)
	_at(UIKit.label("門派傳承", 26, UIKit.BONE, HORIZONTAL_ALIGNMENT_LEFT, true), x + 40, y + 18, 200, 36)
	var counts := Game.sect_counts()
	var row := 0
	for sid in Data.sect_order:
		var s: Dictionary = Data.sects[sid]
		if s.has_bond != "1":
			continue
		var yy := y + 78 + row * 118
		row += 1
		var col: Color = UIKit.SECT_COLORS.get(String(sid), UIKit.GREY)
		var n := int(counts.get(sid, 0))
		var tiers: Array = []
		for b in Data.bonds:
			if b.sect_id == sid:
				tiers.append(b)
		var draw := ComicFX.new()
		draw.add_poly(PackedVector2Array([Vector2(34, 0), Vector2(40, 0), Vector2(40, 96), Vector2(34, 96)]), col)
		var nx0 := 70.0
		var nx1 := w - 70.0
		var ny := 52.0
		draw.add_line(PackedVector2Array([Vector2(nx0, ny), Vector2(nx1, ny)]), Color("#3b363f"), 4.0)
		draw.add_line(PackedVector2Array([Vector2(nx0, ny), Vector2(nx0 + (nx1 - nx0) * minf(1.0, n / 5.0), ny)]), col, 4.0)
		var active: Array = []
		var upcoming = null
		for t in tiers:
			var req := int(t.count_required)
			var cx := nx0 + (nx1 - nx0) * req / 5.0
			var lit := n >= req
			var d := PackedVector2Array([Vector2(cx, ny - 14), Vector2(cx + 14, ny), Vector2(cx, ny + 14), Vector2(cx - 14, ny)])
			if lit:
				draw.add_poly(PackedVector2Array([Vector2(cx, ny - 22), Vector2(cx + 22, ny), Vector2(cx, ny + 22), Vector2(cx - 22, ny)]), Color(col, 0.25))
				active.append(t)
			elif upcoming == null:
				upcoming = t
			draw.add_poly(d, col if lit else UIKit.INK)
			draw.add_outline(d, col if lit else Color("#55505a"), 3.0)
			var tl := UIKit.label("%d・%s" % [req, t.name_zh], 13, UIKit.BONE if lit else Color("#6f6a72"), HORIZONTAL_ALIGNMENT_CENTER)
			tl.tooltip_text = String(t.effect_desc)
			tl.mouse_filter = Control.MOUSE_FILTER_PASS
			_at(tl, x + cx - 70, yy + (ny - 42 if req == 5 else ny + 18), 140, 22)
		_at(draw, x, yy, w, 100)
		draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_at(UIKit.label(s.name_zh, 21, col if n >= 2 else UIKit.BONE, HORIZONTAL_ALIGNMENT_LEFT, true), x + 52, yy, 120, 30)
		_at(UIKit.label("%d 門　%s" % [n, s.style], 14, UIKit.GREY), x + 60 + s.name_zh.length() * 22, yy + 6, 260, 22)
		var msg := ""
		if not active.is_empty():
			msg = "已啟：" + String(active[-1].effect_desc)
		elif upcoming != null:
			msg = "下一階：" + String(upcoming.effect_desc)
		var ml := UIKit.label(msg, 13, UIKit.TEAL if not active.is_empty() else UIKit.GREY)
		ml.autowrap_mode = TextServer.AUTOWRAP_OFF
		ml.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		ml.clip_text = true
		ml.tooltip_text = msg
		ml.mouse_filter = Control.MOUSE_FILTER_PASS
		_at(ml, x + 52, yy + 94, w - 90, 22)


func _chip(text: String, bg: Color, fg: Color, size := 15, use_serif := false) -> ComicBox:
	var chip := UIKit.box("chip", "", 0)
	chip.fill = bg
	chip.border = bg
	var l := UIKit.label(text, size, fg, HORIZONTAL_ALIGNMENT_CENTER, use_serif)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	chip.add_child(l)
	return chip


func _inventory_back(from_pause: bool) -> void:
	if from_pause:
		show_pause()
	else:
		resume.emit()


# ------------------------------------------------------------------ 結算
func show_end(won: bool) -> void:
	_clear()
	_full(UIKit.overlay(1.0))
	var tone := UIKit.TEAL if won else UIKit.BLOOD
	var glow := UIKit.bloom(tone, 0.7 if won else 0.5)
	_at(glow, 40, -50, 1520, 600)
	var fx := _fx()
	fx.add_speed_lines(Vector2(800, 250), 260, 1200, 100, Color(tone, 0.35), 61, 1.3)
	if won:
		fx.add_slash(Vector2(-100, 430), Vector2(1700, 90), 26)
	else:
		fx.add_splatter(Vector2(560, 210), 120, 140, UIKit.BLOOD, 17, 18)
		fx.add_splatter(Vector2(1120, 300), 80, 70, UIKit.BLOOD, 19, 12)
		fx.add_slash(Vector2(1700, 90), Vector2(-100, 430), 22, false)
	var s := UIKit.seal("通關" if won else "敗北", UIKit.TEAL_D if won else UIKit.BLOOD, 34, -8)
	_at(s, 410, 82, s.size.x, s.size.y)
	var head := UIKit.title("天魔伏誅" if won else "道消身殞", 170, UIKit.BONE if won else UIKit.BLOOD, 16, not won, -2)
	if won:
		_glow(head, UIKit.TEAL)
	_at(head, 250, 130, 1100, 220)
	var row: Dictionary = Data.stage_row(Game.stage)
	var map_name: String = Data.maps[row.map_id].name_zh if Data.maps.has(row.map_id) else ""
	var where := ("通關　天魔神教總壇已破" if won else "殞落於 %s・第 %d 區　%s" % [map_name, Game.stage, row.area_zh])
	_at(UIKit.box_text("narration", where, 24), 430, 360, 740, 64)
	var t := int(Game.run_time)
	var best: Array = []
	for mid in Game.martial_order:
		if Game.martial[mid] >= 3:
			best.append("%s Lv%d" % [Data.martial[mid].name_zh, Game.martial[mid]])
	var bonds: Array = []
	for sid in Game.bond_tiers:
		bonds.append("%s 第%d階" % [Data.sects[sid].name_zh, Game.bond_tiers[sid]])
	var ws: Array = []
	for wpn in Game.weapons:
		if wpn != null:
			ws.append("%s+%d" % [Data.weapons[wpn.id].name_zh, int(wpn.lv)])
	var cells := [["角色", Data.characters[Game.char_id].name_zh], ["境界", Game.realm_name()], ["擊殺", str(Game.kills)],
		["參悟", "%d 次" % Game.total_draws], ["時間", "%d 分 %02d 秒" % [t / 60, t % 60]],
		["武器", "、".join(ws)], ["精進武學", "、".join(best.slice(0, 3)) if not best.is_empty() else "無"],
		["門派傳承", "、".join(bonds) if not bonds.is_empty() else "無"]]
	for i in cells.size():
		var bx: float
		var by: float
		var bw: float
		if i < 5:
			bx = 150 + i * 262
			by = 470
			bw = 238
		else:
			bx = [150.0, 520.0, 990.0][i - 5]
			by = 590
			bw = [340.0, 440.0, 460.0][i - 5]
		var cell := UIKit.box_text("system", cells[i][1], 21, cells[i][0])
		_at(cell, bx, by, bw, 86)
	var b := UIKit.button("回到主選單", func(): to_menu.emit(), 28, 300, 64)
	_at(b, 650, 740, 300, 64)
	_focus_first(b)


func _glow(t: Control, color: Color) -> void:
	## 狀聲詞標題加外光（突破、通關）
	var top: Label = t.get_children()[-1]
	top.add_theme_color_override("font_shadow_color", Color(color, 0.75))
	top.add_theme_constant_override("shadow_offset_x", 0)
	top.add_theme_constant_override("shadow_offset_y", 0)
	top.add_theme_constant_override("shadow_outline_size", 28)
