extends Node
## 自動冒煙測試：三名角色各自跑完 4 張地圖 20 區，並測試武器、參悟、全武學圓滿、受傷與介面
## 執行：run_tests.bat（或 godot --headless --fixed-fps 60 --path . res://tests/Smoke.tscn）

const MAIN := preload("res://scripts/main.gd")
var main
var errors := 0


func _ready() -> void:
	main = MAIN.new()
	add_child(main)
	await _frames(5)
	for cid in Data.char_order:
		await _run_character(cid)
	print("SMOKE_DONE errors=%d" % errors)
	get_tree().quit(0 if errors == 0 else 1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(cond: bool, what: String) -> void:
	if not cond:
		errors += 1
		push_error("SMOKE_FAIL: " + what)


func _run_character(cid: String) -> void:
	print("--- 角色 ", cid)
	main._start(cid)
	await _frames(3)
	var world = main.world
	var player = main.player
	player.invuln_t = 1.0e9
	var wids: Array = Data.weapons.keys()
	for mi in Data.map_order.size():
		if mi > 0:
			world.build_map(mi)
			await _frames(3)
		_check(world.map_index == mi, "換圖 %d" % mi)
		for ri in 5:
			var r: Dictionary = world.rooms[ri]
			# 從門外走進去（確認入口沒有被擋住），失敗才傳送
			player.global_position = Vector3(r.x0 - 3.0, 0.5, 0.0)
			player.yaw = -PI / 2.0
			player.rotation.y = player.yaw
			Input.action_press("move_forward")
			var walk := 0
			while world.state != "fighting" and walk < 180:
				walk += 1
				await get_tree().physics_frame
			Input.action_release("move_forward")
			_check(world.state == "fighting", "第%d區入口可走進（%d 幀）" % [r.stage, walk])
			if world.state != "fighting":
				player.global_position = Vector3(r.x0 + 3.0, 0.5, 0.0)
				await _frames(3)
			_check(world.state == "fighting", "第%d區鎖陣" % r.stage)
			# 換一把武器測試攻擊方式
			var wid: String = wids[(mi * 5 + ri) % wids.size()]
			Game.weapons[0] = {"id": wid, "lv": 1}
			Game.recompute()
			var guard := 0
			while world.state == "fighting" and guard < 6000:
				guard += 1
				await get_tree().physics_frame
				if guard % 20 == 0:
					player.cooldowns[0] = 0.0
					player._attack(0)
				for e in get_tree().get_nodes_in_group("enemies"):
					if guard % 30 == 0:
						player.deal(e, 1.0e7, false)
			_check(world.state == "cleared", "第%d區破陣（%d 幀）" % [r.stage, guard])
			# 參悟
			if r.stage < Data.stages.size():
				Game.gold += 5000.0
				for d in 3:
					var c: Array = Game.roll_choices()
					_check(not c.is_empty(), "參悟有候選")
					if not c.is_empty():
						Game.describe(c[0])
						Game.choose(c[0], 1)
				main.gacha.open()
				main.gacha._on_draw()
				main.gacha._on_close()
				main.mode = "play"
			if ri < 4:
				var nx: Dictionary = world.rooms[ri + 1]
				player.global_position = Vector3(r.x0 + r.w - 3.0, 0.5, 0.0)
				Input.action_press("move_forward")
				var go := 0
				while player.global_position.x < r.x0 + r.w + 2.0 and go < 180:
					go += 1
					await get_tree().physics_frame
				Input.action_release("move_forward")
				_check(player.global_position.x >= r.x0 + r.w + 2.0, "第%d區出口可走出" % r.stage)
			print("  區域 %d 完成，境界 %s，武學 %d 門，抽數 %d" % [r.stage, Game.realm_name(Game.level), Game.martial.size(), Game.total_draws])
		# 走到出口
		player.global_position = Vector3(world.portal_x, 0.5, 0.0)
		await _frames(3)
	# 全部武學圓滿＋全武器，測試所有特效路徑
	Game.martial = {}
	Game.martial_order = []
	for mid in Data.martial:
		Game.martial[mid] = 5
		Game.martial_order.append(mid)
	Game.add_xiuwei(1.0e7)
	Game.recompute()
	world.build_map(0)
	await _frames(3)
	var r0: Dictionary = world.rooms[4]
	player.global_position = Vector3(r0.x0 + 3.0, 0.5, 0.0)
	await _frames(5)
	for wid in wids:
		Game.weapons = [{"id": wid, "lv": 5}, {"id": wids[0], "lv": 5}]
		Game.recompute()
		for k in 3:
			player.cooldowns = [0.0, 0.0]
			player._attack(0)
			player._attack(1)
			await _frames(2)
	player.invuln_t = 0.0
	for k in 30:
		player.take_damage(5.0, null)
		player.hp = Game.max_hp()
		await _frames(1)
	player.invuln_t = 1.0e9
	await _frames(400)
	# 介面
	main.screens.show_pause()
	main.screens.show_inventory(true)
	main.screens.show_end(true)
	main.screens.show_select()
	main.screens.show_help()
	await _frames(2)
	print("SMOKE_OK ", cid)
	main._to_menu()
	await _frames(3)
