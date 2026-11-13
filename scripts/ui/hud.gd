extends Control
## 戰鬥 HUD：生命、真氣與境界、銀兩、主副武器、武學、區域資訊、首領血條、橫幅與訊息
## 版面對照 docs/ui-drafts/03-hud.svg

var player
var hp_bar: ComicBar
var xw_bar: ComicBar
var crosshair: Control
var reticle: Control                   # 弓：紅圈準星（圈的範圍＝散射）
var reticle_r := 0.0
var name_text: Label
var realm_chip: ComicBox
var realm_text: Label
var gold_text: Label
var free_chip: ComicBox
var free_text: Label
var weapon_cards: Array = []          # 每格 {root, name, lv, pips, icon, tag}
var swap_hint: Label
var zone_box: ComicBox
var enemy_box: ComicBox
var enemy_text: Label
var martial_head: Label
var martial_list: VBoxContainer
var boss_box: Control
var opponent
var boss_seal: ComicSeal
var boss_bar: ComicBar
var boss_name: Control
var boss
var banner: Control
var banner_burst: ComicFX
var banner_title: Control
var banner_sub: ComicBox
var msg_box: VBoxContainer
var hint_box: ComicBox
var prompt_box: ComicBox
var drop_panel: Control
var _drop_key := ""
var _martial_key := ""
var _weapon_key := ""
var _banner_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_crosshair()
	_build_vitals()
	_build_weapons()
	_build_skills()
	_build_zone()
	_build_boss()
	_build_banner()
	msg_box = VBoxContainer.new()
	msg_box.add_theme_constant_override("separation", 22)
	msg_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(msg_box, 30, 36, 360, 420, 0, 0)
	hint_box = UIKit.box_text("system_dark", "", 18)
	hint_box.set_padding(10, 22)
	hint_box.visible = false
	_at(hint_box, 560, 650, 480, 48, 0.5, 1)
	prompt_box = UIKit.box_text("system_dark", "", 18)
	prompt_box.set_padding(10, 22)
	prompt_box.visible = false
	_at(prompt_box, 560, 752, 480, 48, 0.5, 1)
	drop_panel = Control.new()
	drop_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_panel.visible = false
	_at(drop_panel, 380, 540, 840, 196, 0.5, 1)
	Game.message.connect(push_message)
	Game.martial_breakthrough.connect(func(mid, lv, desc): show_banner("%s・%s" % [Data.martial[mid].name_zh, "小成" if lv == 3 else "圓滿"], desc, "break"))
	Game.bond_activated.connect(func(sid, tier, nm): show_banner("門派傳承：%s" % nm, "%s 第%d階" % [Data.sects[sid].name_zh, tier], "break"))
	Game.realm_broken.connect(func(lv, rn, eff): show_banner("突破・%s" % rn, eff, "break"))
	Game.weapon_switched.connect(func(_slot): _weapon_key = "")
	# 受傷：畫面邊緣紅光（強度依傷害比例）
	hurt_vignette = UIKit.vignette(1.0)
	hurt_vignette.modulate = Color(UIKit.BLOOD, 0.0)
	add_child(hurt_vignette)
	Feel.player_hurt.connect(_on_hurt)


var hurt_vignette: TextureRect
var _hurt_tw: Tween


func _on_hurt(strength: float) -> void:
	if _hurt_tw:
		_hurt_tw.kill()
	hurt_vignette.modulate = Color(1.0, 0.08, 0.1, clampf(0.35 + 0.55 * strength, 0.0, 0.9))
	_hurt_tw = create_tween()
	_hurt_tw.tween_property(hurt_vignette, "modulate:a", 0.0, 0.45).set_delay(0.06)


func _at(c: Control, x: float, y: float, w: float, h: float, ax := 0.5, ay := 0.5) -> Control:
	return UIKit.at(self, c, x, y, w, h, ax, ay)


# ------------------------------------------------------------------ 建構
func _build_crosshair() -> void:
	var f := ComicFX.new()
	for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		f.add_line(PackedVector2Array([Vector2(20 + d.x * 14, 20 + d.y * 5), Vector2(20 + d.x * 14, 20 + d.y * 14), Vector2(20 + d.x * 5, 20 + d.y * 14)]), Color(UIKit.BONE, 0.9), 2.5)
	f.add_poly(PackedVector2Array([Vector2(18, 18), Vector2(22, 18), Vector2(22, 22), Vector2(18, 22)]), UIKit.TEAL)
	crosshair = _at(f, 780, 430, 40, 40)
	reticle = Control.new()
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.draw.connect(_draw_reticle)
	reticle.visible = false
	_at(reticle, 600, 250, 400, 400)


const AIM_RED := Color("#f0222e")


func _draw_reticle() -> void:
	## 一個紅圈：半徑＝這一箭的散射範圍投影到畫面上；拉滿時最小、線變粗
	var c := Vector2(200, 200)
	var full: bool = player != null and player.bow_draw() >= 0.999
	reticle.draw_arc(c, reticle_r + 2.0, 0.0, TAU, 64, Color(AIM_RED, 0.25), 6.0 if full else 4.0, true)
	reticle.draw_arc(c, reticle_r, 0.0, TAU, 64, AIM_RED, 3.5 if full else 2.5, true)


func _update_reticle() -> void:
	var bow: bool = player.is_bow()
	reticle.visible = bow
	crosshair.visible = not bow
	if not bow:
		return
	var half_fov := deg_to_rad(player.cam.fov / 2.0)
	var r := tan(deg_to_rad(player.bow_spread_deg())) / tan(half_fov) * 450.0
	r = clampf(r, 4.0, 190.0)
	if not is_equal_approx(r, reticle_r):
		reticle_r = r
		reticle.queue_redraw()


func _build_vitals() -> void:
	var back := ComicFX.new()
	back.add_poly(PackedVector2Array([Vector2(0, 0), Vector2(516, 0), Vector2(492, 146), Vector2(0, 146)]), Color(UIKit.INK, 0.78))
	_at(back, 24, 734, 520, 150, 0, 1)
	var clip := PackedVector2Array([Vector2(10, 6), Vector2(146, 6), Vector2(128, 132), Vector2(10, 132)])
	var face_bg := ComicFX.new()
	face_bg.add_poly(clip, Color("#123a40"))
	_at(face_bg, 30, 736, 150, 140, 0, 1)
	_at(UIKit.clipped(UIKit.portrait_crop(Game.char_id, 150.0 / 140.0, 0.62, 0.50), clip, UIKit.BONE, 4.0), 30, 736, 150, 140, 0, 1)
	name_text = UIKit.label("", 26, UIKit.BONE, HORIZONTAL_ALIGNMENT_LEFT, true)
	name_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_at(name_text, 196, 744, 100, 36, 0, 1)
	realm_chip = UIKit.box("chip", "", 0)
	realm_chip.fill = UIKit.TEAL
	realm_chip.border = UIKit.TEAL
	realm_chip.set_padding(1, 10)
	realm_text = UIKit.label("", 15, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	realm_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	realm_chip.add_child(realm_text)
	_at(realm_chip, 300, 752, 10, 26, 0, 1)
	hp_bar = UIKit.hp_bar()
	_at(hp_bar, 192, 792, 360, 34, 0, 1)
	xw_bar = UIKit.bar(UIKit.TEAL_D, UIKit.TEAL, 10, 6.0)
	_at(xw_bar, 192, 836, 340, 10, 0, 1)
	var coin := ComicFX.new()
	var ring := PackedVector2Array()
	for i in 16:
		ring.append(Vector2(10, 10) + Vector2.from_angle(TAU * i / 16.0) * 10.0)
	coin.add_poly(ring, UIKit.GOLD).add_outline(ring, UIKit.INK, 3.0)
	coin.add_poly(PackedVector2Array([Vector2(7, 7), Vector2(13, 7), Vector2(13, 13), Vector2(7, 13)]), UIKit.INK)
	_at(coin, 196, 856, 20, 20, 0, 1)
	gold_text = UIKit.outlined(UIKit.label("", 18, UIKit.GOLD), 4)
	gold_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_at(gold_text, 224, 852, 120, 28, 0, 1)
	free_chip = UIKit.box("chip", "", 0)
	free_chip.fill = UIKit.EMBER
	free_chip.border = UIKit.EMBER
	free_chip.set_padding(1, 8)
	free_text = UIKit.label("", 14, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	free_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	free_chip.add_child(free_text)
	_at(free_chip, 340, 856, 10, 22, 0, 1)


# ------------------------------------------------------------------ 技能列（docs/ui-drafts/16-skill-bar.svg）
const SKILL_SLOTS := ["skill1", "skill2", "skill3", "skill4", "skill5", "skill6", "skill7", "ult"]
const SKILL_KEYS := ["右鍵", "Q", "E", "R", "1", "2", "3", "V"]
var skill_ui: Array = []           # 每格 {frame, cd, num, name}
var rage_bar: ComicBar
var _skill_char := ""


func _build_skills() -> void:
	var x0 := 566.0
	var y := 800.0
	var w := 60.0
	var gap := 6.0
	_at(UIKit.label("怒氣", 13, UIKit.GREY), x0, y - 30, 40, 18, 0.5, 1)
	rage_bar = UIKit.bar(UIKit.BLOOD, UIKit.EMBER, 10, 5.0)
	_at(rage_bar, x0 + 40, y - 26, 8 * w + 7 * gap - 40, 12, 0.5, 1)
	for i in 8:
		var x := x0 + i * (w + gap)
		var ult := i == 7
		var frame := UIKit.box("chip", "", 0)
		frame.fill = UIKit.INK
		frame.border = UIKit.EMBER if ult else UIKit.BONE
		_at(frame, x, y, w, w, 0.5, 1)
		var cd := ColorRect.new()
		cd.color = Color(UIKit.BONE, 0.28)
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_at(cd, x + 1, y + 1, w - 2, 0, 0.5, 1)
		var num := UIKit.label("", 24, UIKit.BONE, HORIZONTAL_ALIGNMENT_CENTER)
		_at(num, x, y + 16, w, 30, 0.5, 1)
		var key := UIKit.box("chip", "", 0)
		key.fill = frame.border
		key.border = frame.border
		var kl := UIKit.label(SKILL_KEYS[i], 13, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
		kl.autowrap_mode = TextServer.AUTOWRAP_OFF
		key.add_child(kl)
		_at(key, x, y, 40 if SKILL_KEYS[i].length() > 1 else 24, 18, 0.5, 1)
		var nm := UIKit.label("", 12, UIKit.BONE, HORIZONTAL_ALIGNMENT_CENTER)
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		nm.clip_text = true
		_at(nm, x - 4, y + w + 2, w + 8, 18, 0.5, 1)
		skill_ui.append({"frame": frame, "cd": cd, "num": num, "name": nm, "h": w - 2})


func _refresh_skills() -> void:
	var r = player.runner
	if _skill_char != r.char_id:
		_skill_char = r.char_id
		for i in 8:
			var mid: String = r.slots.get(SKILL_SLOTS[i], "")
			var full: String = Data.moves[mid].name_zh if mid != "" else ""
			skill_ui[i].name.text = full.get_slice("・", full.get_slice_count("・") - 1)
			skill_ui[i].name.tooltip_text = full
	rage_bar.max_value = CombatState.cfg("rage_max")
	rage_bar.value = r.rage
	for i in 8:
		var u: Dictionary = skill_ui[i]
		var slot: String = SKILL_SLOTS[i]
		var left: float = r.cd_left(slot)
		var mid: String = r.slots.get(slot, "")
		var total: float = float(Data.moves[mid].cooldown_s) if mid != "" else 0.0
		var frac := clampf(left / total, 0.0, 1.0) if total > 0.0 else 0.0
		if slot == "ult":
			frac = 1.0 - clampf(r.rage / CombatState.cfg("rage_max"), 0.0, 1.0)
			u.frame.border = UIKit.EMBER if frac <= 0.0 else UIKit.DIM
		u.cd.size.y = float(u.h) * frac
		u.num.text = str(int(ceil(left))) if left > 0.05 else ""
		u.name.modulate.a = 0.5 if frac > 0.0 else 1.0


func _build_weapons() -> void:
	for i in 2:
		var x := 1110.0 + i * 240.0
		var y := 770.0
		var root := Control.new()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_at(root, x, y - 20, 240, 130, 1, 1)
		var card := UIKit.box("slant")
		card.slant = 18
		UIKit.place(card, 0, 0, 0, 20, 226, 104)
		root.add_child(card)
		var active_line := ColorRect.new()
		active_line.color = UIKit.TEAL
		UIKit.place(active_line, 0, 0, 0, 2, 226, 6)
		root.add_child(active_line)
		var icon := ComicFX.new()
		UIKit.place(icon, 0, 0, 30, 30, 100, 90)
		root.add_child(icon)
		var tag := UIKit.box("chip", "", 0)
		tag.set_padding(1, 8)
		var tag_text := UIKit.label(Game.slot_name(i), 14, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
		tag_text.autowrap_mode = TextServer.AUTOWRAP_OFF
		tag.add_child(tag_text)
		UIKit.place(tag, 0, 0, 18, 8, 10, 24)
		root.add_child(tag)
		var lv := UIKit.label("", 15, UIKit.EMBER, HORIZONTAL_ALIGNMENT_RIGHT)
		UIKit.place(lv, 0, 0, 96, 34, 114, 22)
		root.add_child(lv)
		var nm := UIKit.label("", 20, UIKit.BONE, HORIZONTAL_ALIGNMENT_RIGHT, true)
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		UIKit.place(nm, 0, 0, 60, 84, 150, 32)
		root.add_child(nm)
		var pips := ComicFX.new()
		UIKit.place(pips, 0, 0, 124, 62, 100, 16)
		root.add_child(pips)
		weapon_cards.append({"root": root, "card": card, "line": active_line, "icon": icon, "tag": tag, "tag_text": tag_text, "lv": lv, "name": nm, "pips": pips})
	swap_hint = UIKit.outlined(UIKit.label("Q／滾輪 切換主副武器", 14, UIKit.GREY, HORIZONTAL_ALIGNMENT_RIGHT), 4)
	_at(swap_hint, 1250, 878, 326, 20, 1, 1)


func _build_zone() -> void:
	zone_box = UIKit.box_text("narration", "", 21)
	zone_box.set_padding(10, 18)
	_at(zone_box, 1190, 26, 380, 64, 1, 0)
	enemy_box = UIKit.box("slant_red")
	enemy_box.slant = 12
	enemy_text = UIKit.label("", 19, UIKit.BONE, HORIZONTAL_ALIGNMENT_CENTER)
	enemy_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	enemy_box.add_child(enemy_text)
	enemy_box.visible = false
	_at(enemy_box, 1352, 102, 218, 40, 1, 0)
	martial_head = UIKit.outlined(UIKit.label("", 15, UIKit.GREY, HORIZONTAL_ALIGNMENT_RIGHT), 4)
	_at(martial_head, 1370, 150, 200, 24, 1, 0)
	martial_list = VBoxContainer.new()
	martial_list.add_theme_constant_override("separation", 6)
	martial_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(martial_list, 1406, 184, 164, 300, 1, 0)


func _build_boss() -> void:
	boss_box = Control.new()
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.visible = false
	_at(boss_box, 450, 14, 700, 100, 0.5, 0)
	boss_name = UIKit.title("", 44, UIKit.BONE, 8)
	UIKit.place(boss_name, 0, 0, 100, 0, 500, 60)
	boss_box.add_child(boss_name)
	boss_seal = UIKit.seal("首領", UIKit.BLOOD, 20, -6)
	UIKit.place(boss_seal, 0, 0, 150, 18, boss_seal.size.x, boss_seal.size.y)
	boss_box.add_child(boss_seal)
	boss_bar = UIKit.bar(Color("#6e0a10"), UIKit.EMBER, 4, 12.0)
	UIKit.place(boss_bar, 0, 0, 0, 68, 700, 24)
	boss_box.add_child(boss_bar)


func _build_banner() -> void:
	banner = Control.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	_at(banner, 300, 150, 1000, 250, 0.5, 0)
	banner.pivot_offset = Vector2(500, 100)
	banner_burst = ComicFX.new()
	banner_burst.add_burst(Vector2(500, 98), 230, 92, 22, 0.3, UIKit.BONE, UIKit.INK, 6.0, 8)
	UIKit.place(banner_burst, 0, 0, 0, 0, 1000, 200)
	banner.add_child(banner_burst)
	banner_title = UIKit.title("", 88, UIKit.BLOOD, 11, false, -3)
	UIKit.place(banner_title, 0, 0, 0, 40, 1000, 110)
	banner.add_child(banner_title)
	banner_sub = UIKit.box_text("narration", "", 19)
	banner_sub.set_padding(8, 22)
	UIKit.place(banner_sub, 0, 0, 200, 190, 600, 46)
	banner.add_child(banner_sub)


# ------------------------------------------------------------------ 每幀
func _process(_delta: float) -> void:
	if player == null:
		return
	var mh := Game.max_hp()
	hp_bar.max_value = mh
	hp_bar.value = player.hp
	hp_bar.overlay = player.shield
	hp_bar.text = "%d / %d" % [int(player.hp), int(mh)]
	_refresh_skills()
	var need := float(Game.break_cost())
	xw_bar.max_value = maxf(1.0, need)
	xw_bar.value = minf(Game.zhenqi, need)
	name_text.text = Data.characters[Game.char_id].name_zh
	if realm_text.text != Game.realm_name():
		realm_text.text = Game.realm_name()
		realm_chip.reset_size()
	gold_text.text = "銀兩 %d" % int(Game.gold)
	var chips: Array = []
	if Game.zhenqi >= need:
		chips.append("可衝穴（K）")
	if Game.free_draws > 0:
		chips.append("額外參悟 ×%d" % Game.free_draws)
	free_chip.visible = not chips.is_empty()
	if free_chip.visible and free_text.text != "　".join(chips):
		free_text.text = "　".join(chips)
		free_chip.reset_size()
	_update_reticle()
	_refresh_weapons()
	_refresh_martial()
	if is_instance_valid(opponent):
		boss_box.visible = true
		boss_bar.max_value = opponent.build.max_hp()
		boss_bar.value = opponent.hp
		boss_bar.text = "%d / %d" % [ceili(opponent.hp), ceili(boss_bar.max_value)]
	elif is_instance_valid(boss) and not boss.dead:
		boss_box.visible = true
		boss_bar.max_value = boss.max_hp
		boss_bar.value = boss.hp
	else:
		boss_box.visible = false


func _refresh_weapons() -> void:
	var key := "%d|%s" % [Game.active_weapon, str(Game.weapons)]
	if key == _weapon_key:
		return
	_weapon_key = key
	var has_sub := Game.weapons[1] != null
	swap_hint.visible = has_sub
	for i in 2:
		var c: Dictionary = weapon_cards[i]
		var w = Game.weapons[i]
		var on := i == Game.active_weapon
		c.root.visible = w != null or i == 0      # 角色固定一把兵器：空的副武器格不顯示
		c.root.modulate = Color(1, 1, 1, 1.0 if on else 0.6)
		c.line.visible = on
		c.tag.fill = UIKit.BONE if on else UIKit.GREY
		c.tag.border = c.tag.fill
		c.icon.clear()
		c.pips.clear()
		if w == null:
			c.card.border = Color("#3a363e")
			c.card.fill = Color(UIKit.INK, 0.6)
			c.name.text = "（空）"
			c.name.add_theme_color_override("font_color", UIKit.DIM)
			c.lv.text = ""
			continue
		var row: Dictionary = Data.weapons[w.id]
		c.card.border = UIKit.BONE if on else Color("#55505a")
		c.card.fill = Color(UIKit.INK, 0.9)
		c.name.text = row.name_zh
		c.name.add_theme_color_override("font_color", UIKit.BONE)
		var lv := int(w.lv)
		c.lv.text = "淬煉+%d" % lv if lv < Game.MAX_LV else "器靈覺醒"
		c.lv.add_theme_color_override("font_color", UIKit.EMBER if lv > 1 else UIKit.GREY)
		c.pips.add_pips(Vector2(8, 8), lv, Game.MAX_LV, 8.0, UIKit.EMBER, [Game.MAX_LV])
		c.icon.add_weapon_icon(Vector2(44, 44), String(row["class"]))


func _refresh_martial() -> void:
	var key := str(Game.martial) + str(Game.martial_order)
	if key == _martial_key:
		return
	_martial_key = key
	for ch in martial_list.get_children():
		ch.queue_free()
	martial_head.text = "武學 %d / %d" % [Game.martial.size(), Game.martial_slots()] if not Game.martial.is_empty() else ""
	for mid in Game.martial_order:
		var lv: int = Game.martial[mid]
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.custom_minimum_size = Vector2(164, 28)
		var chip := UIKit.box("chip", "", 0)
		chip.border = UIKit.EMBER if lv >= 3 else Color("#55505a")
		chip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.add_child(chip)
		var l := UIKit.label(Data.martial[mid].name_zh, 15, UIKit.BONE)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.clip_text = true
		UIKit.place(l, 0, 0, 10, 2, 76, 24)
		holder.add_child(l)
		var p := ComicFX.new()
		p.add_pips(Vector2(0, 0), lv, 5, 8.0)
		UIKit.place(p, 0, 0, 84, 14, 76, 1)
		holder.add_child(p)
		martial_list.add_child(holder)


# ------------------------------------------------------------------ 介面
func set_zone(title: String) -> void:
	zone_box.get_meta("label").text = title
	zone_box.visible = title != ""


func set_enemies(n: int) -> void:
	enemy_box.visible = n > 0
	enemy_text.text = "剩餘敵人 %d" % n


func set_opponent(fighter) -> void:
	opponent = fighter
	boss_seal.text = "對手"
	UIKit.set_title(boss_name, Data.characters[fighter.build.char_id].name_zh)


func set_boss(e) -> void:
	boss = e
	UIKit.set_title(boss_name, e.row.name_zh)
	show_banner(e.row.name_zh, e.row.special_desc, "boss")


func set_prompt(t: String) -> void:
	## 互動提示（撿武器、找鐵匠商人），每幀由 main 更新
	var l: Label = prompt_box.get_meta("label")
	if l.text != t:
		l.text = t
	prompt_box.visible = t != ""


func show_drop_compare(item) -> void:
	## 靠近掉落兵器時，比較地上那把與手上那把（副武器格空著則顯示放進副武器）
	if item == null:
		drop_panel.visible = false
		_drop_key = ""
		hint_box.modulate.a = 1.0
		return
	hint_box.modulate.a = 0.0
	drop_panel.visible = true
	var key := "%d|%s|%s" % [Game.active_weapon, str(item), str(Game.weapons)]
	if key == _drop_key:
		return
	_drop_key = key
	for c in drop_panel.get_children():
		drop_panel.remove_child(c)
		c.queue_free()
	var back := UIKit.box("slant")
	back.slant = 24
	back.fill = Color(UIKit.INK, 0.94)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drop_panel.add_child(back)
	var into_sub: bool = Game.weapons[1] == null
	var sides := [["地上", item, true], ["副武器格" if into_sub else "手上・%s" % Game.slot_name(Game.active_weapon), null if into_sub else Game.current_weapon(), false]]
	for j in 2:
		var x := 40.0 + j * 400.0
		var w = sides[j][1]
		var hi: bool = sides[j][2]
		var tag := UIKit.box("chip", "", 0)
		tag.fill = UIKit.TEAL if hi else UIKit.GREY
		tag.border = tag.fill
		tag.set_padding(1, 10)
		var tl := UIKit.label(sides[j][0], 16, UIKit.INK)
		tl.autowrap_mode = TextServer.AUTOWRAP_OFF
		tag.add_child(tl)
		UIKit.place(tag, 0, 0, x, 18, 10, 26)
		drop_panel.add_child(tag)
		if w == null:
			var empty := UIKit.label("（空，撿起後直接放進來）", 20, UIKit.GREY, HORIZONTAL_ALIGNMENT_LEFT, true)
			UIKit.place(empty, 0, 0, x, 62, 360, 30)
			drop_panel.add_child(empty)
			continue
		var row: Dictionary = Data.weapons[w.id]
		var nm := UIKit.label(row.name_zh, 30, UIKit.BONE, HORIZONTAL_ALIGNMENT_LEFT, true)
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		UIKit.place(nm, 0, 0, x, 52, 200, 42)
		drop_panel.add_child(nm)
		var sub := UIKit.label("淬煉+%d　%s" % [int(w.lv), row["class"]], 15, UIKit.EMBER if int(w.lv) > 1 else UIKit.GREY)
		sub.autowrap_mode = TextServer.AUTOWRAP_OFF
		UIKit.place(sub, 0, 0, x + String(row.name_zh).length() * 31 + 14, 64, 180, 22)
		drop_panel.add_child(sub)
		var affixes: Array = w.get("affixes", [])
		var lines: Array = []
		for a in affixes:
			lines.append("◆ " + Data.affix_text(a))
		var al := UIKit.label("\n".join(lines) if not lines.is_empty() else "（沒有詞條）", 17, UIKit.TEAL if hi else Color("#c9c2cb"))
		al.add_theme_constant_override("line_spacing", 2)
		UIKit.place(al, 0, 0, x + 2, 100, 360, 96)
		drop_panel.add_child(al)
	var mid := ComicFX.new()
	mid.add_line(PackedVector2Array([Vector2(410, 20), Vector2(398, 176)]), UIKit.GREY, 2.0)
	mid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drop_panel.add_child(mid)
	var arrow := UIKit.label("⇄", 30, UIKit.BONE, HORIZONTAL_ALIGNMENT_CENTER)
	UIKit.place(arrow, 0, 0, 384, 80, 40, 40)
	drop_panel.add_child(arrow)


func set_hint(t: String) -> void:
	hint_box.get_meta("label").text = t
	hint_box.visible = t != ""


func show_banner(title: String, sub := "", style = "map") -> void:
	## style：lock（鎖陣，爆框紅字）、boss（首領登場）、clear（破陣，青光）、break（突破、傳承）、map（換圖）
	if style is Color:
		style = "map"
	var burst: bool = style in ["lock", "boss"]
	banner_burst.visible = burst
	var color := UIKit.BONE
	match style:
		"lock", "boss":
			color = UIKit.BLOOD
		"clear", "break":
			color = UIKit.BONE
	UIKit.set_title(banner_title, title, color)
	var top: Label = banner_title.get_children()[-1]
	var glow: bool = style in ["clear", "break"]
	top.add_theme_color_override("font_shadow_color", Color(UIKit.TEAL, 0.8) if glow else Color(0, 0, 0, 0))
	top.add_theme_constant_override("shadow_offset_x", 0)
	top.add_theme_constant_override("shadow_offset_y", 0)
	top.add_theme_constant_override("shadow_outline_size", 26 if glow else 0)
	banner_title.get_children()[-1].add_theme_font_size_override("font_size", 88 if title.length() <= 6 else 60)
	banner_title.get_children()[0].add_theme_font_size_override("font_size", 88 if title.length() <= 6 else 60)
	banner_sub.get_meta("label").text = sub
	banner_sub.visible = sub != ""
	if _banner_tween:
		_banner_tween.kill()
	banner.scale = Vector2(1.18, 1.18) if burst else Vector2.ONE
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(banner, "modulate:a", 1.0, 0.18)
	_banner_tween.tween_property(banner, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.chain().tween_interval(2.2)
	_banner_tween.chain().tween_property(banner, "modulate:a", 0.0, 0.6)


func push_message(t: String) -> void:
	var tag := "江湖"
	var body := t
	var cut := t.find("：")
	if cut > 0 and cut <= 6:
		tag = t.left(cut)
		body = t.substr(cut + 1)
	var b := UIKit.box_text("system_dark", body, 16, tag, HORIZONTAL_ALIGNMENT_LEFT)
	b.set_padding(9, 18)
	b.custom_minimum_size = Vector2(330, 0)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	msg_box.add_child(b)
	if msg_box.get_child_count() > 5:
		msg_box.get_child(0).queue_free()
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(b, "modulate:a", 0.0, 0.8)
	tw.tween_callback(b.queue_free)
