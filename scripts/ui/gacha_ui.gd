extends Control
## 悟道碑・參悟：花銀兩三選一（武器或武學），可再悟（重抽）

signal closed

var cards_row: HBoxContainer
var cost_label: Label
var pity_label: Label
var draw_btn: Button
var reroll_btn: Button
var current: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(UIKit.overlay(0.8))
	var v := UIKit.center_box(self, 1400)
	v.add_child(UIKit.label("悟道碑・參悟", 48, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	cost_label = UIKit.label("", 22, UIKit.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(cost_label)
	pity_label = UIKit.label("", 16, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(pity_label)
	cards_row = HBoxContainer.new()
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_row.custom_minimum_size = Vector2(0, 470)
	cards_row.add_theme_constant_override("separation", 24)
	v.add_child(cards_row)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btns)
	draw_btn = UIKit.button("參悟", _on_draw)
	btns.add_child(draw_btn)
	reroll_btn = UIKit.button("再悟", _on_reroll)
	btns.add_child(reroll_btn)
	btns.add_child(UIKit.button("離開悟道碑", _on_close))
	v.add_child(UIKit.label("提示：已習得的武學再次出現時會升級；同門派武學越多，越容易參悟到該門派。", 16, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))


func open() -> void:
	visible = true
	current = []
	_refresh()


func _refresh() -> void:
	for c in cards_row.get_children():
		c.queue_free()
	var cost := Game.draw_cost()
	cost_label.text = "參悟費用 %d 銀兩　｜　持有 %d 銀兩%s" % [cost, int(Game.gold), ("　｜　免費參悟 ×%d" % Game.free_draws) if Game.free_draws > 0 else ""]
	var soft := int(Data.gacha.soft_pity_start)
	pity_label.text = "距上次出現絕世已 %d 次（第 %d 次起機率提升，第 %d 次必出）　幸運 %.2f" % [Game.since_legendary, soft, int(Data.gacha.hard_pity), Game.st("luck")]
	draw_btn.disabled = not current.is_empty() or not Game.can_afford(cost)
	reroll_btn.disabled = current.is_empty() or Game.gold < Game.reroll_cost()
	reroll_btn.text = "再悟（%d）" % Game.reroll_cost()
	if current.is_empty():
		var hint := UIKit.label("按下「參悟」，從天機中領悟三選一。", 24, UIKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		hint.custom_minimum_size = Vector2(600, 0)
		cards_row.add_child(hint)
		return
	for c in current:
		cards_row.add_child(_card(c))


func _card(c: Dictionary) -> Control:
	var d := Game.describe(c)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(400, 460)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.09, 0.08, 0.97)
	sb.border_color = Data.rarity_color(c.rarity)
	sb.set_border_width_all(4 if c.rarity == "legendary" else 3)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	if c.rarity == "legendary":
		sb.shadow_color = Color(1, 0.75, 0.3, 0.5)
		sb.shadow_size = 18
	pc.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	pc.add_child(v)
	v.add_child(UIKit.label(d.rarity_name, 18, Data.rarity_color(c.rarity)))
	v.add_child(UIKit.label(d.title, 34, UIKit.PAPER))
	v.add_child(UIKit.label(d.sub, 17, UIKit.MUTED))
	v.add_child(UIKit.label(d.level, 20, UIKit.GOLD))
	var body := UIKit.label(d.body, 19, UIKit.PAPER)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	v.add_child(UIKit.label(d.extra, 16, UIKit.JADE.lightened(0.25)))
	if d.needs_slot:
		for i in 2:
			var cur: Dictionary = Game.weapons[i]
			var b := UIKit.button("替換%s：%s" % ["左手" if i == 0 else "右手", Data.weapons[cur.id].name_zh], _on_pick.bind(c, i), 18)
			v.add_child(b)
	else:
		v.add_child(UIKit.button("領悟", _on_pick.bind(c, -1)))
	return pc


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
