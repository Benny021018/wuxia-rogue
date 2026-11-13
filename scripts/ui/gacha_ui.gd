extends Control
## 悟道碑・天機輪：每次參悟先轉天機輪，依結果產生三選一候選（武器或武學）；可花銀兩重轉
## 版面對照 docs/ui-drafts/14-tianji-wheel.svg（轉輪）與 04-shrine.svg（候選卡片）
## 規則與數學模型：tools/shrine_math/wheel.py；data/wheel_*.csv

signal closed

const REEL := preload("res://scripts/ui/wheel_reel.gd")
const TILE_H := 112.0
const TILE_W := 150.0

var cost_label: Label
var pity_bar: ComicBar
var pity_label: Label
var cards_root: Control
var wheel_root: Control
var side_root: Control
var reels: Array = []
var banner: Control
var banner_title: Control
var banner_sub: Label
var wu_label: Label
var log_box: VBoxContainer
var draw_btn: Button
var reroll_btn: Button
var current: Array = []
var state := "idle"            # idle／spinning／result／cards
var spin_tween: Tween
var pending_stops: Array = []
var log_lines: Array = []
var auto_advance := true       # 結果顯示一下後自動換成候選卡片（截圖工具會關掉）


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(UIKit.overlay(0.94))
	var glow := UIKit.bloom(UIKit.TEAL, 0.9)
	glow.modulate.a = 0.35
	_at(glow, -20, 10, 1640, 920)
	var lines := ComicFX.new()
	lines.add_speed_lines(Vector2(800, 470), 420, 1200, 120, Color(0, 0, 0, 0.6), 31, 1.3)
	_at(lines, 0, 0, 1600, 900)
	_at(UIKit.title("悟道碑・天機輪", 64, UIKit.BONE, 9, false, -1), 400, 26, 800, 80)
	var cost := UIKit.box_text("narration", "", 18)
	cost.set_padding(8, 20)
	cost_label = cost.get_meta("label")
	_at(cost, 470, 98, 660, 48)
	_build_wheel()
	_build_side()
	cards_root = Control.new()
	cards_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(cards_root, 0, 0, 1600, 900)
	draw_btn = UIKit.button("參悟・轉輪", _on_draw, 22, 220, 54, "空白")
	_at(draw_btn, 470, 822, 220, 54)
	reroll_btn = UIKit.button("重轉", _on_reroll, 20, 210, 54)
	_at(reroll_btn, 714, 822, 210, 54)
	_at(UIKit.button("離開悟道碑", _on_close, 20, 200, 54), 948, 822, 200, 54)


func _at(c: Control, x: float, y: float, w: float, h: float, ax := 0.5, ay := 0.5) -> Control:
	return UIKit.at(self, c, x, y, w, h, ax, ay)


func _in(parent: Control, c: Control, x: float, y: float, w: float, h: float) -> Control:
	UIKit.place(c, 0, 0, x, y, w, h)
	parent.add_child(c)
	return c


# ------------------------------------------------------------------ 版面
func _build_wheel() -> void:
	wheel_root = Control.new()
	wheel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(wheel_root, 0, 0, 1600, 900)
	var x0 := 500.0
	var y0 := 176.0
	var w0 := 600.0
	var h0 := 470.0
	var slab := ComicFX.new()
	var shape := PackedVector2Array([Vector2(30, 0), Vector2(w0 - 30, 0), Vector2(w0, 30), Vector2(w0, h0), Vector2(0, h0), Vector2(0, 30)])
	slab.add_poly(shape, Color("#1a171d")).add_outline(shape, UIKit.BONE, 4.0)
	slab.add_line(PackedVector2Array([Vector2(18, 12), Vector2(w0 - 18, 12)]), Color(UIKit.BONE, 0.4), 1.0)
	_in(wheel_root, slab, x0, y0, w0, h0)
	_in(wheel_root, UIKit.label("天　機　輪", 22, UIKit.GREY, HORIZONTAL_ALIGNMENT_CENTER, true), x0, y0 + 14, w0, 30)
	var gap := 22.0
	var rx0 := 800.0 - (3.0 * TILE_W + 2.0 * gap) / 2.0
	var ry0 := y0 + 62.0
	for i in Data.wheel_reels.size():
		var rx := rx0 + i * (TILE_W + gap)
		var frame := ComicFX.new()
		var fr := PackedVector2Array([Vector2(0, 0), Vector2(TILE_W + 12, 0), Vector2(TILE_W + 12, 3 * TILE_H + 12), Vector2(0, 3 * TILE_H + 12)])
		frame.add_poly(fr, UIKit.INK).add_outline(fr, Color("#55505a"), 2.0)
		_in(wheel_root, frame, rx - 6, ry0 - 6, TILE_W + 12, 3 * TILE_H + 12)
		var reel = REEL.new()
		_in(wheel_root, reel, rx, ry0, TILE_W, 3 * TILE_H)
		reel.setup(Data.wheel_reels[i], Game.rng.randi_range(0, Data.wheel_reels[i].size() - 1), TILE_H)
		reels.append(reel)
	# 中線
	var ly := ry0 + TILE_H * 1.5
	var line := ComicFX.new()
	var lw := 3.0 * TILE_W + 2.0 * gap + 60.0
	var lr := PackedVector2Array([Vector2(0, 0), Vector2(lw, 0), Vector2(lw, TILE_H), Vector2(0, TILE_H)])
	line.add_outline(lr, UIKit.BLOOD, 4.0)
	line.add_poly(PackedVector2Array([Vector2(-30, TILE_H / 2 - 18), Vector2(-4, TILE_H / 2), Vector2(-30, TILE_H / 2 + 18)]), UIKit.BLOOD)
	line.add_poly(PackedVector2Array([Vector2(lw + 30, TILE_H / 2 - 18), Vector2(lw + 4, TILE_H / 2), Vector2(lw + 30, TILE_H / 2 + 18)]), UIKit.BLOOD)
	_in(wheel_root, line, rx0 - 30, ly - TILE_H / 2.0, lw, TILE_H)
	# 結果橫幅
	banner = Control.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_in(wheel_root, banner, 0, 0, 1600, 900)
	var burst := ComicFX.new()
	burst.add_burst(Vector2(800, 700), 270, 56, 22, 0.25, UIKit.BONE, UIKit.INK, 5.0, 6)
	_in(banner, burst, 0, 0, 1600, 900)
	banner_title = UIKit.title("", 46, UIKit.BLOOD, 8, false, -2)
	_in(banner, banner_title, 450, 664, 700, 70)
	banner_sub = UIKit.outlined(UIKit.label("", 18, UIKit.BONE, HORIZONTAL_ALIGNMENT_CENTER), 5)
	_in(banner, banner_sub, 400, 760, 800, 30)
	banner.visible = false


func _build_side() -> void:
	side_root = Control.new()
	side_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(side_root, 0, 0, 1600, 900)
	var odds := Game.wheel_odds()
	# 左：天機輪譜與機率公示
	_panel(side_root, 40, 176, 420, 560)
	_in(side_root, UIKit.label("天機輪譜", 26, UIKit.BONE, HORIZONTAL_ALIGNMENT_LEFT, true), 74, 200, 200, 36)
	_in(side_root, UIKit.label("每轉機率", 15, UIKit.GREY, HORIZONTAL_ALIGNMENT_RIGHT), 300, 206, 130, 24)
	var rows := [
		[["tangmen", "tangmen", "bagua"], "門派共鳴", "三張候選皆出該門派，稀有度升一階", odds.resonance, false],
		[["shaolin", "bagua", "cloud"], "門派感應", "前兩軸同門：一張候選保證是該門派", odds.sense, false],
		[["bagua", "bagua", "bagua"], "八卦歸一", "一張必出絕世，其餘稀有度升一階", odds.bagua, true],
		[["wu", "wu", "wu"], "頓悟", "任意位置 3 個悟：免費參悟 +%d，可再觸發" % int(Data.wheel_cfg.free_spins), odds.trigger, true],
	]
	for i in rows.size():
		var y := 250.0 + i * 112.0
		var row: Array = rows[i]
		var mini := Control.new()
		mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var syms: Array = row[0]
		mini.draw.connect(func():
			for k in syms.size():
				REEL.draw_tile(mini, Rect2(k * 46, 0, 42, 40), syms[k]))
		_in(side_root, mini, 70, y, 140, 40)
		_in(side_root, UIKit.label(row[1], 22, UIKit.EMBER if row[4] else UIKit.BONE, HORIZONTAL_ALIGNMENT_LEFT, true), 226, y + 2, 140, 32)
		_in(side_root, UIKit.label("%.2f%%" % (float(row[3]) * 100.0), 20, UIKit.TEAL, HORIZONTAL_ALIGNMENT_RIGHT), 330, y + 4, 100, 30)
		_in(side_root, UIKit.label(row[2], 15, Color("#c9c2cb")), 70, y + 52, 380, 24)
	_in(side_root, UIKit.label("每次參悟平均轉 %.3f 次（含頓悟）" % float(odds.spins), 14, UIKit.GREY), 70, 680, 380, 22)
	_in(side_root, UIKit.label("八卦百搭任何門派；悟每軸最多出現一個", 14, UIKit.GREY), 70, 704, 380, 22)
	# 右：天機、頓悟、本次紀錄
	_panel(side_root, 1140, 176, 420, 560)
	_in(side_root, UIKit.label("天機", 26, UIKit.BONE, HORIZONTAL_ALIGNMENT_LEFT, true), 1174, 200, 200, 36)
	pity_bar = UIKit.bar(UIKit.TEAL_D, UIKit.TEAL, int(Data.gacha.hard_pity), 6.0)
	pity_bar.max_value = float(Data.gacha.hard_pity)
	pity_bar.marker = float(Data.gacha.soft_pity_start) / float(Data.gacha.hard_pity)
	_in(side_root, pity_bar, 1174, 246, 340, 16)
	pity_label = UIKit.label("", 15, UIKit.GREY)
	pity_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_in(side_root, pity_label, 1174, 272, 360, 24)
	_in(side_root, UIKit.label("頓悟", 26, UIKit.EMBER, HORIZONTAL_ALIGNMENT_LEFT, true), 1174, 330, 200, 36)
	wu_label = UIKit.label("", 18, UIKit.BONE)
	wu_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_in(side_root, wu_label, 1174, 372, 360, 28)
	_in(side_root, UIKit.label("本次參悟", 20, UIKit.BONE, HORIZONTAL_ALIGNMENT_LEFT, true), 1174, 500, 200, 30)
	log_box = VBoxContainer.new()
	log_box.add_theme_constant_override("separation", 4)
	_in(side_root, log_box, 1174, 538, 360, 190)


func _panel(parent: Control, x: float, y: float, w: float, h: float) -> void:
	var p := ComicFX.new()
	var k := 22.0
	var shape := PackedVector2Array([Vector2(k, 0), Vector2(w, 0), Vector2(w - k, h), Vector2(0, h)])
	p.add_poly(shape, UIKit.INK).add_outline(shape, UIKit.BONE, 3.0)
	_in(parent, p, x, y, w, h)


# ------------------------------------------------------------------ 狀態
func open() -> void:
	Sfx.play("ui_open")
	visible = true
	current = []
	log_lines = []
	_set_state("idle")


func _set_state(s: String) -> void:
	state = s
	var show_wheel := s != "cards"
	wheel_root.visible = show_wheel
	side_root.visible = show_wheel
	cards_root.visible = s == "cards"
	if s == "idle" or s == "spinning":
		banner.visible = false
	_refresh()
	if s == "cards" and not current.is_empty():
		_reveal_sounds()


func _reveal_sounds() -> void:
	var t := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for i in current.size():
		t.tween_callback(func(): Sfx.play("card_reveal"))
		t.tween_interval(0.08)
	if current.any(func(c): return c.rarity == "legendary"):
		t.tween_callback(func(): Sfx.play("legend_sting"))


func _refresh() -> void:
	for c in cards_root.get_children():
		cards_root.remove_child(c)
		c.queue_free()
	var res := ""
	if not Game.wheel_last.is_empty() and state == "cards":
		res = _result_text(Game.wheel_last) + "　｜　"
	cost_label.text = "%s可參悟 %d 次（含頓悟 %d）　｜　持有 %d 銀兩" % [res, Game.draws_left(), Game.wheel_free, int(Game.gold)]
	pity_bar.value = Game.since_legendary
	pity_label.text = "%d / %d 未遇絕世　第 %d 次必出" % [Game.since_legendary, int(Data.gacha.hard_pity), int(Data.gacha.hard_pity)]
	wu_label.text = "剩餘免費參悟　%d" % Game.wheel_free
	draw_btn.disabled = state != "idle" or Game.draws_left() <= 0
	draw_btn.text = "參悟・轉輪" if state != "spinning" else "停輪"
	if state == "spinning":
		draw_btn.disabled = false
	reroll_btn.disabled = state != "cards" or Game.gold < Game.refresh_cost()
	reroll_btn.text = "重轉（免費）" if Game.refresh_cost() == 0 else "重轉（%d 兩）" % Game.refresh_cost()
	for c in log_box.get_children():
		log_box.remove_child(c)
		c.queue_free()
	for i in log_lines.size():
		var l := UIKit.label("第 %d 轉　%s" % [i + 1, log_lines[i]], 16, UIKit.TEAL if i == log_lines.size() - 1 else UIKit.BONE)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		log_box.add_child(l)
	while log_box.get_child_count() > 6:
		var first := log_box.get_child(0)
		log_box.remove_child(first)
		first.queue_free()
	if state == "idle":
		_focus(draw_btn)
		if Game.draws_left() <= 0:
			banner.visible = true
			UIKit.set_title(banner_title, "本區的參悟已用完")
			banner_sub.text = "破下一陣再來"
	if state == "cards":
		var centers := [335.0, 800.0, 1265.0]
		var order: Array = range(current.size())
		order.sort_custom(func(a, b): return current[a].rarity == "legendary" and current[b].rarity != "legendary")
		for i in order:   # 絕世卡先畫，集中線壓在兩側卡片下
			_card(current[i], centers[i % 3])


func _focus(b: Button) -> void:
	(func():
		if b.is_visible_in_tree() and not b.disabled:
			b.grab_focus()).call_deferred()


func _result_text(r: Dictionary) -> String:
	var name := Game.wheel_outcome_name(String(r.outcome))
	if name != "" and String(r.sect) != "":
		name += "・" + String(Data.sects[r.sect].name_zh)
	if int(r.scatters) >= 3:
		name = ("頓悟　" + name) if name != "" else "頓悟"
	return name if name != "" else "平"


# ------------------------------------------------------------------ 轉輪
func _spin(stops: Array) -> void:
	pending_stops = stops
	_set_state("spinning")
	if spin_tween:
		spin_tween.kill()
	spin_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	for i in reels.size():
		var reel = reels[i]
		reel.stopped = false
		reel.hot_mid = false
		var n: int = reel.strip.size()
		var from: float = fposmod(reel.pos, float(n))
		reel.pos = from
		var target := float(int(stops[i])) + float(n) * float(3 + i)
		while target < from + n * (3 + i):
			target += n
		spin_tween.tween_property(reel, "pos", target, 0.9 + 0.35 * i).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		spin_tween.tween_callback(func(): Sfx.play("wheel_stop")).set_delay(0.9 + 0.35 * i)
	spin_tween.set_parallel(false)
	spin_tween.tween_callback(_on_stopped)


func _skip() -> void:
	## 再按一次：立刻停輪
	if state != "spinning":
		return
	if spin_tween:
		spin_tween.kill()
	Sfx.play("wheel_stop")
	for i in reels.size():
		reels[i].pos = float(int(pending_stops[i]))
	_on_stopped()


func _on_stopped() -> void:
	if state != "spinning":
		return
	for i in reels.size():
		var reel = reels[i]
		reel.pos = float(int(pending_stops[i]))
		reel.stopped = true
	current = Game.wheel_roll(pending_stops)
	var r: Dictionary = Game.wheel_last
	var o := String(r.outcome)
	for i in reels.size():
		var mid_sym: String = reels[i].symbol_at(int(pending_stops[i]))
		reels[i].hot_mid = o == "bagua" or (o == "resonance") or (o == "sense" and i < 2 and mid_sym != "cloud")
		reels[i].queue_redraw()
	log_lines.append(_result_text(r))
	match o:
		"bagua": Sfx.play("wheel_bagua")
		"resonance": Sfx.play("wheel_resonance")
		"sense": Sfx.play("wheel_sense")
	if int(r.scatters) >= 3:
		Sfx.play("wheel_dunwu")
	banner.visible = true
	UIKit.set_title(banner_title, _result_text(r) if _result_text(r) != "平" else "天機未顯")
	banner_sub.text = _outcome_desc(r)
	_set_state("result")
	banner.visible = true
	var t := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_interval(0.9 if o != "none" or int(r.scatters) >= 3 else 0.45)
	t.tween_callback(func():
		if state == "result" and auto_advance:
			_set_state("cards"))


func _outcome_desc(r: Dictionary) -> String:
	var parts: Array = []
	match String(r.outcome):
		"sense": parts.append("一張候選保證是%s武學" % Data.sects[r.sect].name_zh)
		"resonance": parts.append("三張候選皆出%s武學，稀有度升一階" % Data.sects[r.sect].name_zh)
		"bagua": parts.append("一張必出絕世，其餘稀有度升一階")
	if int(r.scatters) >= 3:
		parts.append("免費參悟 +%d" % int(Data.wheel_cfg.free_spins))
	return "，".join(parts) if not parts.is_empty() else "一般三選一"


func _card(c: Dictionary, cx: float) -> void:
	var d := Game.describe(c)
	var legend: bool = c.rarity == "legendary"
	var cw := 420.0 if legend else 390.0
	var ch := 560.0 if legend else 520.0
	var x := cx - cw / 2.0
	var y := 236.0 if legend else 262.0
	var col := UIKit.rarity_color(c.rarity) if c.kind == "M" else UIKit.BONE   # 武器不分品質
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.place(root, 0, 0, x, y, cw, ch)
	var k := 28.0
	var outline := PackedVector2Array([Vector2(0, 0), Vector2(cw - k, 0), Vector2(cw, k), Vector2(cw, ch), Vector2(k, ch), Vector2(0, ch - k)])
	var art := ComicFX.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if legend:
		var area := Control.new()
		area.clip_contents = true
		area.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIKit.place(area, 0, 0, -260, -6, cw + 520, ch + 80)
		root.add_child(area)
		var back := ComicFX.new()
		back.add_speed_lines(Vector2(cw / 2.0 + 260, 260), 270, 620, 60, Color(col, 0.45), 41, 1.5)
		back.add_embers(Rect2(190, 0, cw + 140, ch + 70), 40, col, 13)
		back.drift = 22.0
		back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		area.add_child(back)
		for g in 4:
			var grow := 4.0 + g * 5.0
			art.add_poly(PackedVector2Array([Vector2(-grow, -grow), Vector2(cw - k + grow * 0.4, -grow), Vector2(cw + grow, k - grow * 0.4), Vector2(cw + grow, ch + grow), Vector2(k - grow * 0.4, ch + grow), Vector2(-grow, ch - k + grow * 0.4)]), Color(col, 0.16 - g * 0.035))
	art.add_poly(outline, Color("#0f0d12"))
	art.add_poly(PackedVector2Array([Vector2(0, 0), Vector2(cw - k, 0), Vector2(cw, k), Vector2(cw, 46), Vector2(0, 86)]), Color(col, 0.95))
	art.add_outline(outline, col, 6.0 if legend else 4.0)
	art.add_poly(PackedVector2Array([Vector2(22, 100), Vector2(134, 100), Vector2(134, 212), Vector2(22, 212)]), UIKit.INK)
	art.add_outline(PackedVector2Array([Vector2(22, 100), Vector2(134, 100), Vector2(134, 212), Vector2(22, 212)]), UIKit.BONE, 2.0)
	root.add_child(art)
	var kind := UIKit.label(d.sub, 16, UIKit.INK)
	kind.autowrap_mode = TextServer.AUTOWRAP_OFF
	UIKit.place(kind, 0, 0, 22, 14, cw - 120, 24)
	root.add_child(kind)
	var seal := UIKit.seal(d.rarity_name, UIKit.INK if legend else UIKit.BLOOD, 32 if legend else 26, 5)
	UIKit.place(seal, 0, 0, cw - 64 - seal.size.x / 2.0, 72 - seal.size.y / 2.0, seal.size.x, seal.size.y)
	root.add_child(seal)
	var icon := TextureRect.new()
	icon.texture = preload("res://assets/ui/weapon.webp") if c.kind == "W" else preload("res://assets/ui/manual.webp")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	UIKit.place(icon, 0, 0, 24, 102, 108, 108)
	root.add_child(icon)
	var name_size := 46 if String(d.title).length() <= 4 else 38
	var title := UIKit.title(d.title, name_size, UIKit.BONE, 8, false, -2, HORIZONTAL_ALIGNMENT_LEFT)
	UIKit.place(title, 0, 0, 148, 112, cw - 160, 66)
	root.add_child(title)
	var level := UIKit.label(d.level, 19, UIKit.EMBER)
	level.autowrap_mode = TextServer.AUTOWRAP_OFF
	UIKit.place(level, 0, 0, 152, 178, 170, 28)
	root.add_child(level)
	if c.kind == "M":
		var pips := ComicFX.new()
		pips.add_pips(Vector2(0, 0), int(Game.martial.get(c.id, 0)), 5, 10.0)
		UIKit.place(pips, 0, 0, cw - 110, 192, 100, 1)
		root.add_child(pips)
	var text := String(d.body)
	if c.kind == "W":
		text = text.replace("，間隔", "\n間隔").replace("，射程", "　射程")
	elif Game.martial.has(c.id):
		text += "\n（目前 %s）" % Data.martial_text(c.id, int(Game.martial[c.id]))
	var body := UIKit.box_text("system", text, 17, "", HORIZONTAL_ALIGNMENT_LEFT)
	body.set_padding(12, 20)
	UIKit.place(body, 0, 0, 22, 236, cw - 44, 112)
	root.add_child(body)
	var extra := UIKit.label(d.extra, 15, UIKit.TEAL)
	UIKit.place(extra, 0, 0, 24, 368, cw - 48, 70)
	root.add_child(extra)
	var buttons: Array = []
	if d.needs_slot:
		for i in 2:
			var cur: Dictionary = Game.weapons[i]
			buttons.append(UIKit.button("替換%s：%s" % [Game.slot_name(i), Data.weapons[cur.id].name_zh], _on_pick.bind(c, i), 19, cw - 60, 48))
	else:
		buttons.append(UIKit.button("領悟", _on_pick.bind(c, -1), 24, cw - 60, 48))
	var by := ch - 24 - 58 * buttons.size()
	for j in buttons.size():
		UIKit.place(buttons[j], 0, 0, 30, by + j * 58, cw - 60, 48)
		root.add_child(buttons[j])
	cards_root.add_child(root)


func _on_draw() -> void:
	if state == "spinning":
		_skip()
		return
	if state != "idle":
		return
	if not Game.take_draw():
		Sfx.play("ui_error")
		return
	_spin(Game.wheel_spin())


func _on_reroll() -> void:
	if state != "cards":
		return
	if not Game.pay_refresh():
		Sfx.play("ui_error")
		return
	Sfx.play("shop_refresh")
	current = []
	_spin(Game.wheel_spin())


func _on_pick(c: Dictionary, slot: int) -> void:
	Game.choose(c, slot)
	Sfx.play("card_pick")
	current = []
	_set_state("idle")


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("jump"):
		if state == "spinning" or state == "idle":
			_on_draw()
			get_viewport().set_input_as_handled()
		elif state == "result":
			_set_state("cards")
			get_viewport().set_input_as_handled()


func _on_close() -> void:
	if state == "spinning":
		_skip()
	if state == "result":
		_set_state("cards")
	if state == "cards" and not current.is_empty():
		return   # 候選還沒選，不能離開（避免白白浪費一次參悟）
	Sfx.play("ui_close")
	visible = false
	current = []
	closed.emit()
