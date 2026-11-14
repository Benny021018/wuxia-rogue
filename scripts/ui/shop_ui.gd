extends Control
## 休息區：鐵匠（兵器淬煉、配件重鑄）與商人（隨機上架武學）
## 版面對照 docs/ui-drafts/10-smith.svg、11-merchant.svg

signal closed

const RANGE_ZH := {"melee": "近戰", "mid": "中距離", "ranged": "遠程"}

var kind := "smith"
var coin_label: Label
var body: Control
var title_node: Control
var clang: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(UIKit.overlay(0.95))
	var glow := UIKit.bloom(UIKit.TEAL, 0.9)
	glow.modulate.a = 0.22
	_at(glow, -20, 10, 1640, 920)
	var lines := ComicFX.new()
	lines.add_speed_lines(Vector2(800, 470), 420, 1200, 110, Color(0, 0, 0, 0.6), 37, 1.3)
	_at(lines, 0, 0, 1600, 900)
	title_node = UIKit.title("", 64, UIKit.BONE, 9, false, -1)
	_at(title_node, 350, 26, 900, 90)
	var coin := UIKit.box_text("narration", "", 18)
	coin.set_padding(8, 20)
	coin_label = coin.get_meta("label")
	_at(coin, 560, 106, 480, 48)
	clang = Control.new()
	clang.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var burst := ComicFX.new()
	burst.add_burst(Vector2(90, 60), 90, 60, 16, 0.3, UIKit.BONE, UIKit.INK, 4.0, 11)
	UIKit.place(burst, 0, 0, 0, 0, 180, 120)
	clang.add_child(burst)
	var word := UIKit.title("鏘！", 44, UIKit.BLOOD, 7, false, -8)
	UIKit.place(word, 0, 0, 0, 24, 180, 70)
	clang.add_child(word)
	clang.pivot_offset = Vector2(90, 60)
	_at(clang, 1350, 70, 180, 120)
	body = Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(body, 0, 0, 1600, 900)


func _at(c: Control, x: float, y: float, w: float, h: float, ax := 0.5, ay := 0.5) -> Control:
	return UIKit.at(self, c, x, y, w, h, ax, ay)


func _put(c: Control, x: float, y: float, w: float, h: float) -> Control:
	## 放進 body（每次刷新會清掉）
	UIKit.place(c, 0, 0, x, y, w, h)
	body.add_child(c)
	return c


func open_smith() -> void:
	Sfx.play("ui_open")
	kind = "smith"
	visible = true
	_refresh()


func open_merchant() -> void:
	Sfx.play("ui_open")
	kind = "merchant"
	visible = true
	_refresh()


func _refresh() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	if kind == "smith":
		UIKit.set_title(title_node, "鐵匠・淬煉與重鑄")
		coin_label.text = "持有 %d 銀兩" % int(Game.gold)
		clang.visible = true
		_smith_weapon(110.0)
		_smith_gear(710.0)
	else:
		UIKit.set_title(title_node, "商人・武學")
		coin_label.text = "持有 %d 銀兩　｜　武學 %d / %d" % [int(Game.gold), Game.martial.size(), Game.martial_slots()]
		clang.visible = false
		if Game.merchant_stock.is_empty():
			_put(UIKit.box_text("narration", "今天沒有可以學的武學。", 26), 450, 420, 700, 90)
		# 3 欄網格，一次看完全部上架的武學（docs/ui-drafts/11-merchant.svg）
		var x0 := (1600.0 - (3.0 * MCW + 2.0 * MGAP)) / 2.0
		for i in Game.merchant_stock.size():
			_merchant_card(i, x0 + (i % 3) * (MCW + MGAP), 200.0 + floori(i / 3.0) * (MCH + 18.0))
		var refresh := UIKit.button("重新上架（%d）" % Game.merchant_refresh_cost(), _on_refresh, 20, 220, 50)
		refresh.disabled = Game.gold < Game.merchant_refresh_cost()
		_put(refresh, 580, 836, 220, 50)
		_put(UIKit.label("已習得的武學再買會升級；武學格滿時只上架已習得的武學", 13, UIKit.GREY, HORIZONTAL_ALIGNMENT_RIGHT), 1000, 878, 580, 22)
	var leave := UIKit.button("離開", _on_close, 22, 200, 50)
	_put(leave, 820 if kind == "merchant" else 700, 836, 200, 50)
	(func():
		if leave.is_visible_in_tree():
			leave.grab_focus()).call_deferred()


# ------------------------------------------------------------------ 鐵匠
func _card(x: float, y: float, cw: float, ch: float, label: String) -> void:
	var k := 28.0
	var outline := PackedVector2Array([Vector2(0, 0), Vector2(cw - k, 0), Vector2(cw, k), Vector2(cw, ch), Vector2(k, ch), Vector2(0, ch - k)])
	var card := ComicFX.new()
	card.add_poly(outline, Color("#0f0d12"))
	card.add_outline(outline, UIKit.BONE, 3.0)
	_put(card, x, y, cw, ch)
	var tag := UIKit.box("chip", "", 0)
	tag.fill = UIKit.TEAL
	tag.border = tag.fill
	tag.set_padding(2, 12)
	var tl := UIKit.label(label, 15, UIKit.INK)
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	tag.add_child(tl)
	_put(tag, x + 22, y - 12, 10, 26)


## 左：兵器淬煉（角色固定一把兵器，兵器本身沒有詞條）
func _smith_weapon(x: float) -> void:
	var y := 190.0
	var cw := 560.0
	_card(x, y, cw, 600.0, "兵器淬煉")
	var w: Dictionary = Game.weapons[0]
	var row: Dictionary = Data.weapons[w.id]
	var lv := int(w.lv)
	var badge := ComicFX.new()
	var sq := PackedVector2Array([Vector2(0, 0), Vector2(150, 0), Vector2(150, 150), Vector2(0, 150)])
	badge.add_poly(sq, UIKit.INK)
	badge.add_speed_lines(Vector2(75, 75), 40, 96, 20, Color(UIKit.VIOLET, 0.9), 7, 1.2)
	badge.clip_contents = true
	badge.add_weapon_icon(Vector2(75, 75), String(row["class"]), 150.0 / 110.0)
	badge.add_outline(sq, UIKit.BONE, 2.0)
	_put(badge, x + 30, y + 40, 150, 150)
	_put(UIKit.title(row.name_zh, 48, UIKit.BONE, 8, false, -2, HORIZONTAL_ALIGNMENT_LEFT), x + 200, y + 46, 280, 70)
	var sl := UIKit.seal(String(row["class"]), UIKit.BLOOD, 22, 5)
	_put(sl, x + cw - 64 - sl.size.x / 2.0, y + 52, sl.size.x, sl.size.y)
	_put(UIKit.label("%s・%s" % [row["class"], RANGE_ZH[row.range_type]], 17, UIKit.GREY, HORIZONTAL_ALIGNMENT_LEFT, true), x + 208, y + 124, 200, 26)
	var p := ComicFX.new()
	p.add_pips(Vector2(0, 0), lv, Game.MAX_LV, 12.0, UIKit.EMBER, [Game.MAX_LV])
	_put(p, x + 216, y + 178, 110, 1)
	_put(UIKit.label("淬煉 +%d" % lv if lv < Game.MAX_LV else "器靈覺醒", 18, UIKit.EMBER), x + 330, y + 166, 160, 26)
	var up_cost := Game.upgrade_cost(0)
	var d0 := roundi(Game.weapon_hit_dmg(w.id, lv))
	var info := "淬煉 +%d → +%d\n每段傷害 %d → %d" % [lv, lv + 1, d0, roundi(Game.weapon_hit_dmg(w.id, lv + 1))] if up_cost >= 0 else "已達器靈覺醒\n每段傷害 %d" % d0
	var box := UIKit.box_text("system", info, 18, "強化", HORIZONTAL_ALIGNMENT_LEFT)
	box.set_padding(12, 20)
	_put(box, x + 30, y + 240, cw - 60, 92)
	var up := UIKit.button("淬煉（%d 銀兩）" % up_cost if up_cost >= 0 else "已覺醒", _on_upgrade.bind(0), 20, 240, 52)
	up.disabled = up_cost < 0 or Game.gold < up_cost
	_put(up, x + 290, y + 350, 240, 52)
	_put(UIKit.label("淬煉到 +5 器靈覺醒。兵器本身沒有詞條，\n詞條改由打倒精英、首領掉落的配件提供。", 15, UIKit.GREY), x + 32, y + 460, cw - 64, 60)


## 右：配件重鑄（護符、腰牌、玉珮；本體不變，只重抽 ◆ 詞條）
func _smith_gear(x: float) -> void:
	var y := 190.0
	var cw := 780.0
	_card(x, y, cw, 600.0, "配件重鑄")
	for i in Game.GEAR_SLOTS.size():
		var slot: String = Game.GEAR_SLOTS[i]
		var g = Game.gear.get(slot)
		var yy := y + 30.0 + i * 186.0
		var frame := UIKit.box("chip", "", 0)
		frame.fill = UIKit.INK2
		frame.border = UIKit.rarity_color(Game.gear_quality(g)) if g != null else Color("#3a363e")
		_put(frame, x + 24, yy, cw - 48, 168)
		var icon := ComicFX.new()
		icon.add_gear_icon(Vector2(60, 84), slot, 0.95, UIKit.BONE if g != null else UIKit.DIM)
		_put(icon, x + 24, yy, 120, 168)
		var tag := UIKit.box("chip", "", 0)
		tag.fill = UIKit.GREY
		tag.border = tag.fill
		tag.set_padding(1, 8)
		var tl := UIKit.label(Game.gear_slot_name(slot), 14, UIKit.INK)
		tl.autowrap_mode = TextServer.AUTOWRAP_OFF
		tag.add_child(tl)
		_put(tag, x + 36, yy + 10, 10, 22)
		var re := UIKit.button("重鑄", _on_reforge_gear.bind(slot), 19, 236, 48)
		_put(re, x + cw - 284, yy + 104, 236, 48)
		if g == null:
			re.disabled = true
			_put(UIKit.label("尚未取得", 24, UIKit.DIM, HORIZONTAL_ALIGNMENT_LEFT, true), x + 160, yy + 44, 300, 36)
			_put(UIKit.label("打倒精英或首領有機會掉落", 15, UIKit.GREY), x + 160, yy + 90, 400, 22)
			continue
		var q := Game.gear_quality(g)
		var qc := UIKit.rarity_color(q)
		var gname: String = Data.accessories[g.id].name_zh
		_put(UIKit.label(gname, 26, qc, HORIZONTAL_ALIGNMENT_LEFT, true), x + 160, yy + 14, 260, 40)
		_put(UIKit.label(UIKit.rarity_name(q), 15, qc), x + 160 + gname.length() * 27 + 10, yy + 26, 80, 22)
		_put(UIKit.label("◇ %s（本體，重鑄不變）" % Data.affix_text(g.base), 15, UIKit.BONE), x + 162, yy + 58, 520, 22)
		var affixes: Array = g.get("affixes", [])
		for k in affixes.size():
			_put(UIKit.label("◆ " + Data.affix_text(affixes[k]), 15, UIKit.TEAL), x + 162, yy + 84 + k * 22, 330, 22)
		var cost := Game.gear_reforge_cost(slot)
		re.text = "重鑄（%d 銀兩）" % cost if cost >= 0 else "重鑄"
		re.disabled = cost < 0 or Game.gold < cost


func _on_reforge_gear(slot: String) -> void:
	if Game.reforge_gear(slot):
		Sfx.play("reforge")
		_clang()
	else:
		Sfx.play("ui_error")
	_refresh()


func _on_upgrade(slot: int) -> void:
	if Game.upgrade_weapon(slot):
		Sfx.play("forge")
		_clang()
	else:
		Sfx.play("ui_error")
	_refresh()


func _on_reforge(slot: int) -> void:
	if Game.reforge_weapon(slot):
		Sfx.play("reforge")
		_clang()
	else:
		Sfx.play("ui_error")
	_refresh()


func _clang() -> void:
	clang.scale = Vector2(1.35, 1.35)
	var t := create_tween()
	t.tween_property(clang, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ------------------------------------------------------------------ 商人
const MCW := 460.0
const MCH := 290.0
const MGAP := 22.0


func _merchant_card(i: int, x: float, y: float) -> void:
	var item: Dictionary = Game.merchant_stock[i]
	var m: Dictionary = Data.martial[item.id]
	var cw := MCW
	var ch := MCH
	var k := 22.0
	var col := UIKit.rarity_color(m.rarity)
	var lv: int = Game.martial.get(item.id, 0)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate.a = 0.45 if item.sold else 1.0
	UIKit.place(holder, 0, 0, x, y, cw, ch)
	holder.name = "MerchantCard%d" % i
	body.add_child(holder)
	var outline := PackedVector2Array([Vector2(0, 0), Vector2(cw - k, 0), Vector2(cw, k), Vector2(cw, ch), Vector2(k, ch), Vector2(0, ch - k)])
	var art := ComicFX.new()
	art.add_poly(outline, Color("#0f0d12"))
	art.add_poly(PackedVector2Array([Vector2(0, 0), Vector2(cw - k, 0), Vector2(cw, k), Vector2(cw, 34), Vector2(0, 46)]), Color(col, 0.95))
	art.add_outline(outline, col, 3.0)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(art)
	var sect: Dictionary = Data.sects[m.sect]
	var head := UIKit.label("武學・%s・%s" % [sect.name_zh, m.school], 14, UIKit.INK)
	head.autowrap_mode = TextServer.AUTOWRAP_OFF
	UIKit.place(head, 0, 0, 16, 7, cw - 80, 22)
	holder.add_child(head)
	var s := UIKit.seal(Data.rarity[m.rarity].name_zh, UIKit.INK if m.rarity == "legendary" else UIKit.BLOOD, 18, 5)
	UIKit.place(s, 0, 0, cw - 46 - s.size.x / 2.0, 52 - s.size.y / 2.0, s.size.x, s.size.y)
	holder.add_child(s)
	var badge := UIKit.box("chip", "", 0)
	var sc: Color = UIKit.SECT_COLORS.get(String(m.sect), UIKit.GREY)
	badge.fill = sc
	badge.border = sc
	var bl := UIKit.label(String(sect.name_zh).left(1), 30, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(bl)
	UIKit.place(badge, 0, 0, 16, 58, 52, 52)
	holder.add_child(badge)
	var name_node := UIKit.title(m.name_zh, 30 if String(m.name_zh).length() <= 4 else 26, UIKit.BONE, 6, false, -2, HORIZONTAL_ALIGNMENT_LEFT)
	UIKit.place(name_node, 0, 0, 80, 58, cw - 160, 52)
	holder.add_child(name_node)
	var lvtxt := "新習得・入門" if lv == 0 else "%s → %s" % [UIKit.LV_NAMES[lv], UIKit.LV_NAMES[mini(lv + 1, 5)]]
	var ll := UIKit.label(lvtxt, 15, UIKit.EMBER)
	ll.autowrap_mode = TextServer.AUTOWRAP_OFF
	UIKit.place(ll, 0, 0, 18, 118, 200, 24)
	holder.add_child(ll)
	var p := ComicFX.new()
	p.add_pips(Vector2(0, 0), lv, 5, 8.0)
	UIKit.place(p, 0, 0, cw - 120, 130, 100, 1)
	holder.add_child(p)
	var eff := UIKit.box_text("system", Data.martial_text(item.id, mini(lv + 1, 5)), 15, "", HORIZONTAL_ALIGNMENT_LEFT)
	eff.set_padding(8, 14)
	UIKit.place(eff, 0, 0, 16, 150, cw - 32, 56)
	holder.add_child(eff)
	var extra := UIKit.label(("小成：" + String(m.lv3_desc)) if lv + 1 <= 3 else ("圓滿：" + String(m.lv5_desc)), 13, UIKit.TEAL)
	extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIKit.place(extra, 0, 0, 18, 212, cw - 36, 22)
	extra.clip_text = true
	extra.tooltip_text = extra.text
	extra.mouse_filter = Control.MOUSE_FILTER_PASS
	holder.add_child(extra)
	if item.sold:
		var sold := UIKit.seal("已售出", UIKit.BLOOD, 34, -12)
		_put(sold, x + cw / 2.0 - sold.size.x / 2.0, y + ch / 2.0 + 10 - sold.size.y / 2.0, sold.size.x, sold.size.y)
		return
	var price := Game.martial_price(item.id)
	var label := "購買（%d 銀兩）" % price
	if not Game.can_learn(item.id):
		label = "武學格已滿"
	var buy := UIKit.button(label, _on_buy.bind(i), 18, 206, 42)
	buy.disabled = Game.gold < price or not Game.can_learn(item.id)
	_put(buy, x + cw - 226, y + ch - 56, 206, 42)


func _on_buy(i: int) -> void:
	Sfx.play("purchase" if Game.buy_martial(i) else "ui_error")
	_refresh()


func _on_refresh() -> void:
	Sfx.play("shop_refresh" if Game.refresh_merchant() else "ui_error")
	_refresh()


func _on_close() -> void:
	Sfx.play("ui_close")
	visible = false
	closed.emit()
