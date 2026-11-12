extends Control
## 悟道碑・參悟：花銀兩三選一（武器或武學），可再悟（重抽）
## 版面對照 docs/ui-drafts/04-shrine.svg

signal closed

var cost_label: Label
var pity_bar: ComicBar
var pity_label: Label
var cards_root: Control
var draw_btn: Button
var reroll_btn: Button
var current: Array = []


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
	_at(UIKit.title("悟道碑・參悟", 64, UIKit.BONE, 9, false, -1), 400, 26, 800, 80)
	var cost := UIKit.box_text("narration", "", 18)
	cost.set_padding(8, 20)
	cost_label = cost.get_meta("label")
	_at(cost, 470, 98, 660, 48)
	_at(UIKit.label("天機", 18, UIKit.TEAL, HORIZONTAL_ALIGNMENT_RIGHT, true), 500, 156, 60, 26)
	pity_bar = UIKit.bar(UIKit.TEAL_D, UIKit.TEAL, int(Data.gacha.hard_pity), 8.0)
	pity_bar.max_value = float(Data.gacha.hard_pity)
	pity_bar.marker = float(Data.gacha.soft_pity_start) / float(Data.gacha.hard_pity)
	_at(pity_bar, 572, 160, 420, 18)
	pity_label = UIKit.label("", 15, UIKit.GREY)
	pity_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_at(pity_label, 1004, 158, 300, 24)
	_at(UIKit.label("▲ 第 %d 次起天機漸顯，第 %d 次必出絕世" % [int(Data.gacha.soft_pity_start), int(Data.gacha.hard_pity)], 13, UIKit.EMBER), 564, 190, 500, 22)
	cards_root = Control.new()
	cards_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(cards_root, 0, 0, 1600, 900)
	draw_btn = UIKit.button("參悟", _on_draw, 22, 200, 50)
	_at(draw_btn, 470, 836, 200, 50)
	reroll_btn = UIKit.button("再悟", _on_reroll, 22, 200, 50)
	_at(reroll_btn, 700, 836, 200, 50)
	_at(UIKit.button("離開悟道碑", _on_close, 20, 200, 50), 930, 836, 200, 50)
	_at(UIKit.label("已習得的武學再次出現會升級；同門派武學越多，越容易參悟到該門派", 13, UIKit.GREY, HORIZONTAL_ALIGNMENT_RIGHT), 1000, 876, 580, 22, 1, 1)


func _at(c: Control, x: float, y: float, w: float, h: float, ax := 0.5, ay := 0.5) -> Control:
	return UIKit.at(self, c, x, y, w, h, ax, ay)


func open() -> void:
	visible = true
	current = []
	_refresh()


func _refresh() -> void:
	for c in cards_root.get_children():
		cards_root.remove_child(c)
		c.queue_free()
	var cost := Game.draw_cost()
	cost_label.text = "參悟費用 %d 銀兩　｜　持有 %d 銀兩%s" % [cost, int(Game.gold), ("　｜　免費參悟 ×%d" % Game.free_draws) if Game.free_draws > 0 else ""]
	pity_bar.value = Game.since_legendary
	pity_label.text = "%d / %d 未遇絕世　幸運 %.2f" % [Game.since_legendary, int(Data.gacha.hard_pity), Game.st("luck")]
	draw_btn.disabled = not current.is_empty() or not Game.can_afford(cost)
	reroll_btn.disabled = current.is_empty() or Game.gold < Game.reroll_cost()
	reroll_btn.text = "再悟（%d）" % Game.reroll_cost()
	if current.is_empty():
		var hint := UIKit.box_text("narration", "按下「參悟」，從天機中領悟三選一。", 26)
		UIKit.place(hint, 0, 0, 450, 470, 700, 90)
		cards_root.add_child(hint)
		(func():
			if draw_btn.is_visible_in_tree():
				draw_btn.grab_focus()).call_deferred()
		return
	var centers := [335.0, 800.0, 1265.0]
	var order: Array = range(current.size())
	order.sort_custom(func(a, b): return current[a].rarity == "legendary" and current[b].rarity != "legendary")
	for i in order:   # 絕世卡先畫，集中線壓在兩側卡片下
		_card(current[i], centers[i % 3])


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
	if not Game.pay(Game.draw_cost()):
		return
	current = Game.roll_choices()
	_refresh()


func _on_reroll() -> void:
	var c := Game.reroll_cost()
	if Game.gold < c:
		return
	Game.gold -= c
	Game.gold_changed.emit()
	current = Game.roll_choices()
	Game.draws_this_stage -= 1      # 再悟不推高下一次參悟的價格
	_refresh()


func _on_pick(c: Dictionary, slot: int) -> void:
	Game.choose(c, slot)
	current = []
	_refresh()


func _on_close() -> void:
	visible = false
	current = []
	closed.emit()
