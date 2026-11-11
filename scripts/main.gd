extends Node
## 主控：選單 → 角色選擇 → 遊戲（世界＋玩家＋HUD）→ 結算

const WORLD := preload("res://scripts/world.gd")
const PLAYER := preload("res://scripts/player.gd")
const HUD := preload("res://scripts/ui/hud.gd")
const GACHA := preload("res://scripts/ui/gacha_ui.gd")
const SCREENS := preload("res://scripts/ui/screens.gd")

var world
var player
var hud
var gacha
var screens
var ui_layer: CanvasLayer
var mode := "menu"          # menu / play / pause / inventory / gacha / end


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.theme = UIKit.make_theme()
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)
	screens = SCREENS.new()
	ui_layer.add_child(screens)
	screens.start_run.connect(_start)
	screens.resume.connect(_resume)
	screens.to_menu.connect(_to_menu)
	screens.quit_game.connect(func(): get_tree().quit())
	Game.leveled_up.connect(_on_level_up)
	_to_menu()


func _on_level_up(_lv: int) -> void:
	if player:
		player.level_up_heal()


func _to_menu() -> void:
	get_tree().paused = false
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
	mode = "menu"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	screens.show_main()


func _start(cid: String) -> void:
	Game.new_run(cid)
	screens.hide_all()
	world = WORLD.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	player = PLAYER.new()
	world.add_child(player)
	world.player = player
	hud = HUD.new()
	ui_layer.add_child(hud)
	ui_layer.move_child(hud, 0)
	hud.player = player
	gacha = GACHA.new()
	ui_layer.add_child(gacha)
	gacha.visible = false
	gacha.closed.connect(_resume)
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
	if hud == null:
		return
	var m: Dictionary = Data.maps[Data.map_order[i]]
	hud.show_banner("地圖 %d・%s" % [i + 1, m.name_zh], m.lore)
	hud.set_zone(m.name_zh)
	hud.set_hint("往前走進入第一個區域")


func _on_zone_locked(stage: int, title: String) -> void:
	if hud == null:
		return
	var row: Dictionary = Data.stage_row(stage)
	hud.set_zone("第%d區　%s" % [stage, title])
	hud.set_hint("")
	if row.boss == "":
		hud.show_banner("鎖　陣", "%s・%s　殺光所有敵人以破陣" % [row.area_zh, row.zone_type])


func _on_zone_cleared(stage: int) -> void:
	if hud == null:
		return
	hud.set_enemies(0)
	if stage >= Data.stages.size():
		return
	hud.show_banner("破　陣", "悟道碑已浮現，按 E 參悟")
	hud.set_hint("走到悟道碑按［E］參悟　｜　出口已開啟")


func _on_interact() -> void:
	if mode == "play" and world and world.near_shrine():
		mode = "gacha"
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		gacha.open()


func _resume() -> void:
	if mode == "end" or mode == "menu":
		return
	screens.hide_all()
	if gacha:
		gacha.visible = false
	get_tree().paused = false
	mode = "play"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_died() -> void:
	mode = "end"
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	screens.show_end(false)


func _on_won() -> void:
	mode = "end"
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	screens.show_end(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		match mode:
			"play":
				mode = "pause"
				get_tree().paused = true
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				screens.show_pause()
			"pause", "inventory":
				_resume()
			"gacha":
				gacha._on_close()
	elif event.is_action_pressed("inventory"):
		match mode:
			"play":
				mode = "inventory"
				get_tree().paused = true
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				screens.show_inventory(false)
			"inventory":
				_resume()
