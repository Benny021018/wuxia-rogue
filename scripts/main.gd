extends Node
## 主控：選單 → 角色選擇 → 遊戲（世界＋玩家＋HUD）→ 結算

const WORLD := preload("res://scripts/world.gd")
const PLAYER := preload("res://scripts/player.gd")
const HUD := preload("res://scripts/ui/hud.gd")
const GACHA := preload("res://scripts/ui/gacha_ui.gd")
const SCREENS := preload("res://scripts/ui/screens.gd")
const SHOP := preload("res://scripts/ui/shop_ui.gd")
const MERIDIAN := preload("res://scripts/ui/meridian_ui.gd")

var world
var player
var hud
var gacha
var shop
var meridian
var screens
var ui_layer: CanvasLayer
var mode := "menu"          # menu / play / pause / inventory / gacha / shop / meridian / end


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.theme = UIKit.theme()
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)
	screens = SCREENS.new()
	screens.theme = UIKit.theme()
	ui_layer.add_child(screens)
	screens.start_run.connect(_start)
	screens.resume.connect(_resume)
	screens.to_menu.connect(_to_menu)
	screens.quit_game.connect(func(): get_tree().quit())
	Game.leveled_up.connect(_on_level_up)
	Game.martial_breakthrough.connect(func(_m, _lv, _d): Sfx.play("chime_up"))
	Game.bond_activated.connect(func(_s, _t, _n): Sfx.play("chime_up", Vector3.INF, 0.0, 1.12))
	Game.gold_changed.connect(_on_gold_changed)
	_to_menu()


var _last_gold := 0.0


func _on_gold_changed() -> void:
	## 打怪拿到銀兩時叮一聲（花錢的音效由商店介面各自處理）
	if Game.gold > _last_gold + 0.5 and mode == "play":
		Sfx.play("coin")
	_last_gold = Game.gold


func _on_level_up(_lv: int) -> void:
	if player:
		player.level_up_heal()


func _to_menu() -> void:
	get_tree().paused = false
	Feel.reset()
	Game.running = false
	if world:
		world.set_physics_process(false)
		remove_child(world)
		world.queue_free()
		world = null
		player = null
	if hud:
		hud.queue_free()
		hud = null
	if gacha:
		gacha.queue_free()
		gacha = null
	if shop:
		shop.queue_free()
		shop = null
	if meridian:
		meridian.queue_free()
		meridian = null
	mode = "menu"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	screens.show_main()
	Music.play("menu")


func _start(cid: String, start_wid := "") -> void:
	Game.new_run(cid, start_wid)
	screens.hide_all()
	world = WORLD.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	player = PLAYER.new()
	world.add_child(player)
	world.player = player
	hud = HUD.new()
	hud.theme = UIKit.theme()
	ui_layer.add_child(hud)
	ui_layer.move_child(hud, 0)
	hud.player = player
	gacha = GACHA.new()
	gacha.theme = UIKit.theme()
	ui_layer.add_child(gacha)
	gacha.visible = false
	gacha.closed.connect(_resume)
	shop = SHOP.new()
	shop.theme = UIKit.theme()
	ui_layer.add_child(shop)
	shop.visible = false
	shop.closed.connect(_resume)
	meridian = MERIDIAN.new()
	meridian.theme = UIKit.theme()
	ui_layer.add_child(meridian)
	meridian.visible = false
	meridian.closed.connect(_resume)
	player.died.connect(_on_died)
	player.interact_pressed.connect(_on_interact)
	world.zone_locked.connect(_on_zone_locked)
	world.zone_cleared.connect(_on_zone_cleared)
	world.boss_appeared.connect(func(e): hud.set_boss(e))
	world.enemies_changed.connect(func(n): hud.set_enemies(n))
	world.map_entered.connect(_on_map_entered)
	world.run_won.connect(_on_won)
	world.build_map(0)
	mode = "play"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_map_entered(i: int) -> void:
	Music.play(Data.map_order[i])
	if hud == null:
		return
	var m: Dictionary = Data.maps[Data.map_order[i]]
	hud.show_banner("地圖 %d・%s" % [i + 1, m.name_zh], m.lore, "map")
	hud.set_zone(m.name_zh)
	hud.set_hint("往前走進入第一個區域")


func _on_zone_locked(stage: int, title: String) -> void:
	if hud == null:
		return
	var row: Dictionary = Data.stage_row(stage)
	hud.set_zone("%s・第 %d 區　%s" % [Data.maps[row.map_id].name_zh, stage, row.area_zh])
	hud.set_hint("")
	if row.boss == "":
		hud.show_banner("鎖　陣", "%s・%s　殺光所有敵人以破陣" % [row.area_zh, row.zone_type], "lock")


func _on_zone_cleared(stage: int) -> void:
	if hud == null:
		return
	hud.set_enemies(0)
	if stage >= Data.stages.size():
		return
	hud.show_banner("破　陣", "悟道碑已浮現，按 F 參悟", "clear")
	hud.set_hint("走到悟道碑按［F］參悟　｜　出口已開啟")


func _interactable() -> Array:
	## 目前可互動的目標：[種類, 節點]；掉落武器優先於設施（站在掉落物上表示想撿）
	if world == null or player == null:
		return ["", null]
	var radius := Data.cfg("pickup_radius") * (1.0 + Game.st("pickup_range_pct") / 100.0)
	var d = world.nearest_drop(radius)
	if d != null:
		return ["drop", d]
	if world.near_shrine():
		return ["shrine", world.shrine_node]
	if world.near_smith():
		return ["smith", world.smith_node]
	if world.near_merchant():
		return ["merchant", world.merchant_node]
	return ["", null]


func _process(_delta: float) -> void:
	if hud == null:
		return
	if mode != "play":
		hud.show_drop_compare(null)
		hud.set_prompt("")
		return
	var t: Array = _interactable()
	hud.show_drop_compare(t[1].get_meta("item") if t[0] == "drop" else null)
	var text := ""
	match t[0]:
		"drop":
			var item: Dictionary = t[1].get_meta("item")
			var wname: String = Data.weapons[item.id].name_zh
			if Game.weapons[1] == null:
				text = "［F］撿起 %s（放進副武器）" % wname
			else:
				text = "［F］撿起 %s（換掉手上的 %s）" % [wname, Data.weapons[Game.current_weapon().id].name_zh]
		"smith":
			text = "［F］鐵匠：強化武器、重鑄詞條"
		"merchant":
			text = "［F］商人：購買武學"
	hud.set_prompt(text)


func _on_interact() -> void:
	if mode != "play":
		return
	var t: Array = _interactable()
	match t[0]:
		"drop":
			var item: Dictionary = world.take_drop(t[1])
			Sfx.play("pickup")
			var old = Game.pick_up(item)
			if old != null:
				world.spawn_drop(player.global_position + player.global_basis.z * -1.2, old)
			Game.message.emit("撿起：%s　詞條 %d" % [Data.weapons[item.id].name_zh, item.get("affixes", []).size()])
		"shrine":
			mode = "gacha"
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			gacha.open()
		"smith", "merchant":
			open_shop(t[0])


func open_shop(kind: String) -> void:
	mode = "shop"
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if kind == "smith":
		shop.open_smith()
	else:
		shop.open_merchant()


func open_meridian() -> void:
	mode = "meridian"
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	meridian.open()


func _resume() -> void:
	if mode == "end" or mode == "menu":
		return
	if mode == "pause" or mode == "inventory":
		Sfx.play("ui_close")
	screens.hide_all()
	if gacha:
		gacha.visible = false
	if shop:
		shop.visible = false
	if meridian:
		meridian.visible = false
	get_tree().paused = false
	mode = "play"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_died() -> void:
	Feel.reset()
	Sfx.play("player_death")
	Sfx.play("defeat")
	mode = "end"
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	screens.show_end(false)


func _on_won() -> void:
	Feel.reset()
	Sfx.play("victory")
	mode = "end"
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	screens.show_end(true)


func _input(event: InputEvent) -> void:
	## 介面的焦點高亮只在鍵盤／手把操作時顯示
	if event is InputEventMouseMotion and event.relative.length() > 2.0:
		if UIKit.kbd_nav:
			UIKit.set_kbd_nav(false, get_viewport())
	elif (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed() and not UIKit.kbd_nav:
		var nav := false
		for a in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev"]:
			if event.is_action(a):
				nav = true
		if nav and get_viewport().gui_get_focus_owner() is ComicButton:
			# 第一次按方向鍵：先把目前焦點亮出來，不要直接跳到下一顆
			UIKit.set_kbd_nav(true, get_viewport())
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		match mode:
			"play":
				mode = "pause"
				get_tree().paused = true
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				Sfx.play("ui_open")
				screens.show_pause()
			"pause", "inventory":
				_resume()
			"gacha":
				gacha._on_close()
			"shop":
				shop._on_close()
			"meridian":
				meridian._on_close()
	elif event.is_action_pressed("meridian"):
		match mode:
			"play":
				open_meridian()
			"meridian":
				meridian._on_close()
	elif event.is_action_pressed("inventory"):
		match mode:
			"play":
				mode = "inventory"
				get_tree().paused = true
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				Sfx.play("ui_open")
				screens.show_inventory(false)
			"inventory":
				_resume()
