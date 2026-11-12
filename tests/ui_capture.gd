extends Node
## 介面截圖：依序打開各畫面存成 PNG，用來對照 docs/ui-drafts/ 的初稿。
## 需要有畫面的環境（不能用 --headless）。Linux 可用 xvfb-run：
##   xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 res://tests/UICapture.tscn
## 截圖寫到 user://ui_capture/（Godot 使用者資料夾）

const MAIN := preload("res://scripts/main.gd")
var main
var out := "user://ui_capture"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1600, 900)
	main = MAIN.new()
	add_child(main)
	await _frames(20)
	await _shot("01-main-menu")
	main.screens.show_select()
	await _shot("02-character-select")
	main.screens.show_weapon_pick()
	await _shot("08-start-weapon")
	main._start("nangong")
	await _frames(10)
	var world = main.world
	var player = main.player
	player.invuln_t = 1.0e9
	Game.gold = 236
	Game.shrine_charges = 1
	Game.weapons[1] = {"id": "W007", "lv": 1}
	Game.weapons[0].lv = 3
	for pair in [["M007", 2], ["M006", 1], ["M002", 3]]:
		Game.martial[pair[0]] = pair[1]
		Game.martial_order.append(pair[0])
	Game.recompute()
	var r: Dictionary = world.rooms[1]
	player.global_position = Vector3(r.x0 + 3.0, 0.5, 0.0)
	player.yaw = -PI / 2.0
	player.rotation.y = player.yaw
	await _frames(40)
	player.hp = Game.max_hp() * 0.68
	main.hud.set_hint("［E］參悟　悟道碑已浮現")
	await _frames(20)
	Game.message.emit("精進：三流・第四重　生命回復 20%")
	Game.message.emit("銀兩：+18")
	main.hud.show_banner("鎖　陣", "寨外山道・戰鬥　殺光所有敵人以破陣", "lock")
	await _shot("03-hud", 2)
	main.hud.show_banner("破　陣", "悟道碑已浮現，按 E 參悟", "clear")
	await _shot("03b-hud-clear-banner", 2)
	main.mode = "gacha"
	get_tree().paused = true
	Game.shrine_charges = 2
	main.gacha.open()
	await _shot("04a-shrine-empty")
	# 天機輪：找一組「門派共鳴＋頓悟」的停輪位置來截圖
	var stops: Array = []
	for a in Data.wheel_reels[0].size():
		for b in Data.wheel_reels[1].size():
			for c in Data.wheel_reels[2].size():
				var wr := Game.wheel_eval([a, b, c])
				if wr.outcome == "resonance" and int(wr.scatters) >= 3 and stops.is_empty():
					stops = [a, b, c]
	if stops.is_empty():
		stops = [0, 0, 0]
	main.gacha.log_lines = ["門派感應・少林", "平"]
	Game.take_draw()
	main.gacha.auto_advance = false
	main.gacha._spin(stops)
	main.gacha.spin_tween.kill()
	for i in main.gacha.reels.size():
		main.gacha.reels[i].pos = float(stops[i]) + 0.45 + i * 0.2   # 轉動中的畫面
	await _shot("14a-tianji-spinning", 2)
	main.gacha._skip()
	await _shot("14-tianji-wheel", 4)
	main.gacha.auto_advance = true
	main.gacha.current = [{"kind": "W", "id": "W001", "rarity": "common"}, {"kind": "W", "id": "W301", "rarity": "legendary"}, {"kind": "M", "id": "M007", "rarity": "common"}]
	main.gacha._set_state("cards")
	await _shot("04-shrine")
	main.gacha.visible = false
	Game.weapons = [{"id": "W001", "lv": 3, "affixes": [{"id": "A01", "v": 9.0}, {"id": "A03", "v": 12.0}], "reforges": 0}, Game.make_weapon("W007", 0)]
	Game.active_weapon = 0
	Game.recompute()
	main.open_shop("smith")
	await _shot("10-smith")
	Game.restock_merchant()
	main.shop.open_merchant()
	Game.gold = 236
	main.shop._on_buy(2)
	await _shot("11-merchant")
	main.shop.visible = false
	get_tree().paused = false
	main.mode = "play"
	world.spawn_drop(player.global_position + player.global_basis.z * -1.0, {"id": "W007", "lv": 1, "affixes": [{"id": "A02", "v": 8.0}, {"id": "A11", "v": 12.0}, {"id": "A05", "v": 2.4}], "reforges": 0})
	await _shot("09-drop-compare", 8)
	for d in world.drops:
		d.queue_free()
	world.drops = []
	var shrine_pos: Vector3 = world.rooms[1].shrine
	world._spawn_rest_stop(shrine_pos)
	var mid: Vector3 = (world.smith_node.global_position + world.merchant_node.global_position) / 2.0
	player.global_position = Vector3(mid.x, 0.1, mid.z - 8.5 * signf(mid.z if mid.z != 0.0 else 1.0))
	player.yaw = PI
	player.rotation.y = PI
	player.cam.rotation.x = -0.08
	await _shot("12-rest-stop", 10)
	# 弓：拉弓中的紅圈
	Game.weapons = [Game.make_weapon("W007", 2), Game.make_weapon("W001", 1)]
	Game.active_weapon = 0
	Game.recompute()
	player.refresh_weapon_models()
	player.cam.rotation.x = 0.0
	player.yaw = 0.0
	player.rotation.y = 0.0
	Input.action_press("aim")
	Input.action_press("attack_1")
	await _shot("13-bow-aim", 30)
	Input.action_release("attack_1")
	Input.action_release("aim")
	await _frames(20)
	# 經脈頁
	Game.acu_open = {"ren": 9, "du": 4, "chong": 2, "yangwei": 5, "yinwei": 1}
	Game.acu_fails = {"du5": 2}
	Game.realm = 1
	Game.zhenqi = 1284.0
	Game.recompute()
	main.open_meridian()
	main.meridian._select("du")
	await _shot("12-meridian", 8)
	main.meridian._select("yangqiao")
	await _shot("12b-meridian-yangqiao", 6)
	main.meridian._on_close()
	get_tree().paused = true
	main.screens.show_inventory(false)
	await _shot("05-martial-panel")
	main.screens.show_pause()
	await _shot("06-pause")
	main.screens._confirm_quit()
	await _shot("06b-pause-confirm")
	main.screens.show_help(true)
	await _shot("06c-help")
	Game.stage = 13
	Game.kills = 214
	main.screens.show_end(false)
	await _shot("07-result")
	main.screens.show_end(true)
	await _shot("07b-result-win")
	print("UI_CAPTURE_DONE ", ProjectSettings.globalize_path(out))
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String, settle := 6) -> void:
	await _frames(settle)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
