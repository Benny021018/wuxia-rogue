extends Control
## 奇經八脈・衝穴（K 鍵）：一脈一頁、一脈一式；以真氣衝擊下一個穴位
## 版面對照 docs/ui-drafts/12c-meridian-pose.svg

signal closed

const CHART := preload("res://scripts/ui/meridian_chart.gd")

var mid := "du"
var chart
var realm_chip: ComicBox
var realm_text: Label
var realm_track: Array = []
var count_label: Label
var zhenqi_label: Label
var head_icon: TextureRect
var head_name: Control
var head_alias: Label
var head_pose: Label
var panel: Control
var tabs: Array = []
var fx_layer: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(UIKit.overlay(0.985))
	# 標題列
	_at(UIKit.outlined(UIKit.label("經脈", 44, UIKit.BONE, HORIZONTAL_ALIGNMENT_LEFT, true), 8), 40, 22, 120, 60)
	realm_chip = UIKit.box("chip", "", 0)
	realm_chip.fill = UIKit.TEAL
	realm_chip.border = UIKit.TEAL
	realm_chip.set_padding(2, 14)
	realm_text = UIKit.label("", 18, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	realm_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	realm_chip.add_child(realm_text)
	_at(realm_chip, 150, 34, 10, 32)
	count_label = UIKit.label("", 15, UIKit.GREY)
	count_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_at(count_label, 150, 70, 300, 22)
	# 九境
	for i in Data.realm_list.size():
		var l := UIKit.label(String(Data.realm_list[i].name_zh), 15, UIKit.GREY, HORIZONTAL_ALIGNMENT_CENTER, true)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.tooltip_text = "%s・%s\n%s" % [Data.realm_list[i].name_zh, Data.realm_list[i].title_zh, Data.realm_list[i].desc]
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		_at(l, 1010 + i * 62, 40, 62, 24)
		realm_track.append(l)
	var track := ComicFX.new()
	track.add_line(PackedVector2Array([Vector2(1030, 72), Vector2(1550, 72)]), Color(UIKit.GREY, 0.5), 2.0)
	_at(track, 0, 0, 1600, 900)
	realm_track.append(track)
	# 大框
	var frame := ComicFX.new()
	var r := PackedVector2Array([Vector2(40, 96), Vector2(1560, 96), Vector2(1560, 796), Vector2(40, 796)])
	frame.add_poly(r, UIKit.INK2).add_outline(r, UIKit.BONE, 3.0)
	_at(frame, 0, 0, 1600, 900)
	var tag := UIKit.box("slant")
	tag.slant = 16
	var tag_text := UIKit.label("經脈圖", 26, UIKit.BONE, HORIZONTAL_ALIGNMENT_CENTER, true)
	tag.add_child(tag_text)
	_at(tag, 620, 74, 360, 46)
	# 左上：這條經脈
	var dia := ComicFX.new()
	var d := PackedVector2Array([Vector2(130, 116), Vector2(184, 170), Vector2(130, 224), Vector2(76, 170)])
	dia.add_poly(d, UIKit.INK).add_outline(d, UIKit.TEAL, 3.0)
	_at(dia, 0, 0, 1600, 900)
	head_icon = CHART.silhouette("du", UIKit.BONE)
	_at(head_icon, 92, 132, 76, 76)
	head_name = UIKit.title("", 34, UIKit.EMBER, 7, false, -2)
	_at(head_name, 50, 234, 160, 50)
	head_alias = UIKit.label("", 15, UIKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER)
	_at(head_alias, 50, 282, 160, 22)
	head_pose = UIKit.label("", 15, UIKit.GREY, HORIZONTAL_ALIGNMENT_CENTER, true)
	_at(head_pose, 50, 306, 160, 22)
	# 中：經脈圖
	chart = CHART.new()
	_at(chart, 290, 112, 600, 600)
	chart.point_selected.connect(func(_i): _refresh_panel())
	for side in [-1, 1]:
		var b := UIKit.button("◀" if side < 0 else "▶", _cycle.bind(side), 26, 56, 72)
		_at(b, 208 if side < 0 else 916, 424, 56, 72)
		_at(UIKit.label("A" if side < 0 else "D", 14, UIKit.GREY, HORIZONTAL_ALIGNMENT_CENTER), 208 if side < 0 else 916, 500, 56, 20)
	var back := UIKit.button("返回（K）", _on_close, 22, 220, 50)
	_at(back, 470, 728, 220, 50)
	zhenqi_label = UIKit.outlined(UIKit.label("", 22, UIKit.TEAL), 4)
	zhenqi_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_at(zhenqi_label, 720, 736, 300, 34)
	# 右：衝擊穴位
	panel = Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(panel, 0, 0, 1600, 900)
	# 下：八脈
	for i in Data.meridian_order.size():
		var m: String = Data.meridian_order[i]
		var cx := 150.0 + i * 186.0
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_select.bind(m))
		var bg := UIKit.box("slant")
		bg.slant = 14
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.add_child(bg)
		var icon := CHART.silhouette(m, UIKit.BONE)
		UIKit.place(icon, 0, 0, 10, 4, 66, 66)
		btn.add_child(icon)
		var nm := UIKit.label(String(Data.meridians[m].name_zh), 18, UIKit.BONE, HORIZONTAL_ALIGNMENT_CENTER, true)
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		UIKit.place(nm, 0, 0, 76, 10, 92, 26)
		btn.add_child(nm)
		var cnt := UIKit.label("", 13, UIKit.GREY, HORIZONTAL_ALIGNMENT_CENTER)
		UIKit.place(cnt, 0, 0, 76, 40, 92, 22)
		btn.add_child(cnt)
		_at(btn, cx - 84, 812, 172, 74)
		tabs.append({"mid": m, "bg": bg, "icon": icon, "name": nm, "count": cnt})
	fx_layer = Control.new()
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(fx_layer, 0, 0, 1600, 900)


func _at(c: Control, x: float, y: float, w: float, h: float, ax := 0.5, ay := 0.5) -> Control:
	return UIKit.at(self, c, x, y, w, h, ax, ay)


func _put(c: Control, x: float, y: float, w: float, h: float) -> Control:
	UIKit.place(c, 0, 0, x, y, w, h)
	panel.add_child(c)
	return c


func open() -> void:
	Sfx.play("ui_open")
	visible = true
	# 預設停在正在衝的經脈（有進度、還沒全通的那條）
	var pick := mid
	for m in Data.meridian_order:
		var n := Game.acu_level(m)
		if n > 0 and n < Data.meridian_len(m):
			pick = m
			break
	_select(pick)


func _select(m: String) -> void:
	mid = m
	chart.show_meridian(mid)
	_refresh()


func _cycle(step: int) -> void:
	var order: Array = Data.meridian_order
	_select(order[(order.find(mid) + step + order.size()) % order.size()])


func _refresh() -> void:
	var row: Dictionary = Data.meridians[mid]
	realm_text.text = Game.realm_name()
	realm_chip.reset_size()
	count_label.text = "已通 %d / %d 穴　全通 %d / 8 脈" % [Game.acu_total(), Data.acupoints.size(), Game.realm]
	for i in Data.realm_list.size():
		var l: Label = realm_track[i]
		l.add_theme_color_override("font_color", UIKit.TEAL if i == Game.realm else (UIKit.BONE if i < Game.realm else Color(UIKit.GREY, 0.6)))
	zhenqi_label.text = "真氣　%d" % int(Game.zhenqi)
	(head_icon.material as ShaderMaterial).set_shader_parameter("fill_color", UIKit.BONE)
	head_icon.texture = load("res://assets/ui/meridian/%s.webp" % mid)
	UIKit.set_title(head_name, String(row.name_zh))
	head_alias.text = String(row.alias_zh)
	head_pose.text = String(row.pose_zh)
	for t in tabs:
		var m: String = t.mid
		var n := Game.acu_level(m)
		var total := Data.meridian_len(m)
		var on: bool = m == mid
		var bg: ComicBox = t.bg
		bg.fill = Color("#231019") if on else UIKit.INK
		bg.border = UIKit.EMBER if on else (UIKit.TEAL_D if n >= total else Color("#55505a"))
		bg.queue_redraw()
		(t.icon.material as ShaderMaterial).set_shader_parameter("fill_color", UIKit.BONE if (on or n > 0) else Color("#77727a"))
		t.name.add_theme_color_override("font_color", UIKit.BONE if (on or n > 0) else UIKit.GREY)
		t.count.text = "%d / %d" % [n, total]
		t.count.add_theme_color_override("font_color", UIKit.TEAL if n >= total else UIKit.GREY)
	_refresh_panel()


func _refresh_panel() -> void:
	for c in panel.get_children():
		panel.remove_child(c)
		c.queue_free()
	var row: Dictionary = Data.meridians[mid]
	var x := 1050.0
	var y := 124.0
	var w := 480.0
	var h := 644.0
	var bg := ComicFX.new()
	var rect := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
	bg.add_poly(rect, UIKit.INK).add_outline(rect, Color("#55505a"), 2.0)
	bg.add_poly(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, 50), Vector2(0, 50)]), Color("#221d27"))
	_put(bg, x, y, w, h)
	_put(UIKit.label("衝擊穴位", 24, UIKit.BONE, HORIZONTAL_ALIGNMENT_CENTER, true), x, y + 10, w, 34)
	var n := Game.acu_level(mid)
	var total := Data.meridian_len(mid)
	var idx: int = chart.selected
	var p: Dictionary = Data.acupoint(mid, idx + 1)
	var opened := idx < n
	var is_next := idx == n
	_put(UIKit.title(String(p.name_zh), 50, UIKit.BONE, 8, false, -2, HORIZONTAL_ALIGNMENT_LEFT), x + 36, y + 66, 260, 70)
	var where := UIKit.label("%s・第 %d 穴" % [row.name_zh, idx + 1], 16, UIKit.GREY, HORIZONTAL_ALIGNMENT_RIGHT)
	where.autowrap_mode = TextServer.AUTOWRAP_OFF
	_put(where, x + w - 240, y + 98, 200, 24)
	var line := ColorRect.new()
	line.color = Color("#3b363f")
	_put(line, x + 40, y + 146, w - 80, 2)
	var stat := UIKit.label(Data.stat_text(String(p.stat_id), float(p.value)).replace("+", "　+"), 24, UIKit.TEAL)
	stat.autowrap_mode = TextServer.AUTOWRAP_OFF
	_put(stat, x + 40, y + 164, w - 80, 34)
	if opened:
		_put(UIKit.label("已打通", 22, UIKit.TEAL, HORIZONTAL_ALIGNMENT_LEFT, true), x + 40, y + 226, w - 80, 34)
	elif not is_next:
		_put(UIKit.label("需先打通前面的穴位（首衝成功率 %d%%）" % int(round(float(p.base_chance) * 100.0)), 16, UIKit.GREY), x + 40, y + 230, w - 80, 26)
	else:
		var base := float(p.base_chance)
		var ch := Game.break_chance(String(p.point_id))
		var k := int(Game.acu_fails.get(String(p.point_id), 0))
		_put(UIKit.label("成功率", 17, UIKit.GREY), x + 40, y + 226, 120, 28)
		var pct := UIKit.label("%d%%" % int(round(ch * 100.0)), 30, UIKit.EMBER, HORIZONTAL_ALIGNMENT_RIGHT)
		_put(pct, x + w - 200, y + 214, 160, 40)
		var bw := w - 80.0
		var bar_bg := ColorRect.new()
		bar_bg.color = Color("#1b1418")
		_put(bar_bg, x + 40, y + 266, bw, 16)
		var b1 := ColorRect.new()
		b1.color = UIKit.TEAL
		_put(b1, x + 40, y + 266, bw * base, 16)
		var b2 := ColorRect.new()
		b2.color = UIKit.EMBER
		_put(b2, x + 40 + bw * base, y + 266, bw * maxf(0.0, ch - base), 16)
		var frame := ComicFX.new()
		frame.add_outline(PackedVector2Array([Vector2(0, 0), Vector2(bw, 0), Vector2(bw, 16), Vector2(0, 16)]), UIKit.BONE, 1.5)
		_put(frame, x + 40, y + 266, bw, 16)
		_put(UIKit.label("基礎 %d%%　＋　已衝擊 %d 次 ×%d%%" % [int(round(base * 100.0)), k, int(round(float(Data.meridian_cfg.chance_step) * 100.0))], 15, UIKit.GREY), x + 40, y + 296, w - 80, 22)
		_put(UIKit.label("失敗會耗去真氣，但下次更容易打通", 15, UIKit.GREY), x + 40, y + 320, w - 80, 22)
	var sp := UIKit.box_text("system_dark", "%s：%s" % [row.special_name, Game.special_text(mid)], 16, "%s全通" % row.name_zh, HORIZONTAL_ALIGNMENT_LEFT)
	sp.set_padding(12, 18)
	_put(sp, x + 40, y + 368, w - 80, 104)
	if Game.special_on(mid):
		var seal := UIKit.seal("已啟", UIKit.BLOOD, 20, -6)
		_put(seal, x + w - 96, y + 350, seal.size.x, seal.size.y)
	var prog := UIKit.label("%s：%d / %d" % [row.name_zh, n, total], 22, UIKit.BONE, HORIZONTAL_ALIGNMENT_CENTER, true)
	_put(prog, x, y + h - 152, w, 30)
	var pips := ComicFX.new()
	pips.add_pips(Vector2(0, 0), n, total, 12.0, UIKit.TEAL, [])
	_put(pips, x + w / 2.0 - total * 11.0, y + h - 114, total * 22.0, 14)
	var cost := Game.break_cost()
	var can := n < total and Game.zhenqi >= cost
	var btn := UIKit.button("衝　擊" if n < total else "已全通", _on_break, 26, 260, 54, "空白")
	btn.disabled = not can
	_put(btn, x + 110, y + h - 96, 260, 54)
	var cost_l := UIKit.label("消耗真氣　%d" % cost if n < total else "", 18, UIKit.BONE if Game.zhenqi >= cost else UIKit.BLOOD, HORIZONTAL_ALIGNMENT_CENTER)
	if n < total and Game.zhenqi < cost:
		cost_l.text = "真氣不足　%d / %d" % [int(Game.zhenqi), cost]
	_put(cost_l, x, y + h - 34, w, 26)
	if can:
		(func():
			if btn.is_inside_tree() and is_visible_in_tree():
				btn.grab_focus()).call_deferred()


func _on_break() -> void:
	var n := Game.acu_level(mid)
	if n >= Data.meridian_len(mid):
		return
	var at: Vector2 = chart.pos[n] + Vector2(290, 112)
	var before := Game.realm
	var res := Game.try_break(mid)
	if res < 0:
		Sfx.play("ui_error")
		return
	if Game.realm > before:
		Sfx.play("realm_break")
		Feel.shake(0.3)
	elif res == 1 and Game.acu_level(mid) >= Data.meridian_len(mid):
		Sfx.play("meridian_full")
	else:
		Sfx.play("acu_success" if res == 1 else "acu_fail")
	chart.show_meridian(mid)
	chart.selected = mini(Game.acu_level(mid), Data.meridian_len(mid) - 1)
	chart._layout()
	_refresh()
	_pop(at, "打通！" if res == 1 else "衝擊失敗", UIKit.TEAL if res == 1 else UIKit.BLOOD)
	if Game.realm > before:
		_realm_banner()


func _pop(at: Vector2, text: String, color: Color) -> void:
	var l := UIKit.title(text, 36, color, 7, false, -4)
	UIKit.place(l, 0, 0, at.x - 120, at.y - 70, 240, 56)
	fx_layer.add_child(l)
	l.pivot_offset = Vector2(120, 28)
	l.scale = Vector2(0.6, 0.6)
	var t := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(l, "scale", Vector2.ONE, 0.12)
	t.parallel().tween_property(l, "position:y", l.position.y - 30, 0.7)
	t.tween_property(l, "modulate:a", 0.0, 0.3)
	t.tween_callback(l.queue_free)


func _realm_banner() -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.place(root, 0, 0, 0, 0, 1600, 900)
	fx_layer.add_child(root)
	var burst := ComicFX.new()
	burst.add_burst(Vector2(800, 430), 330, 130, 24, 0.3, UIKit.BONE, UIKit.INK, 6.0, 9)
	UIKit.place(burst, 0, 0, 0, 0, 1600, 900)
	root.add_child(burst)
	var t1 := UIKit.title("突破・%s" % Game.realm_name(), 84, UIKit.BLOOD, 11, false, -3)
	UIKit.place(t1, 0, 0, 400, 360, 800, 110)
	root.add_child(t1)
	var r: Dictionary = Data.realm_list[Game.realm]
	var sub := UIKit.box_text("narration", "%s　%s" % [r.title_zh, r.desc], 20)
	UIKit.place(sub, 0, 0, 480, 486, 640, 56)
	root.add_child(sub)
	var t := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_interval(1.6)
	t.tween_property(root, "modulate:a", 0.0, 0.4)
	t.tween_callback(root.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("move_left"):
		_cycle(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		_cycle(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("jump"):
		_on_break()
		get_viewport().set_input_as_handled()


func _on_close() -> void:
	Sfx.play("ui_close")
	visible = false
	closed.emit()
