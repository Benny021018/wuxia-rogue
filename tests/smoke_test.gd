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
	if cid == Data.char_order[0]:
		var gate = world.rooms[0].gate_out
		var meshes := (gate as Node).find_children("*", "MeshInstance3D", true, false)
		_check(meshes.size() == 1, "山寨門只有一個可見模型")
		if meshes.size() == 1:
			var gate_mesh: MeshInstance3D = meshes[0]
			var bounds := gate_mesh.global_transform * gate_mesh.get_aabb()
			_check(bounds.size.distance_to(Vector3(0.6, 4, 6)) < 0.03 and absf(bounds.position.y) < 0.01, "寨門與門洞對齊")
		for id in ["H01", "H02", "H03"]:
			var enemy = world.spawn_enemy(id, Vector3(-10, 0, 0), false)
			var parts: Array = enemy._visual.find_children("*", "MeshInstance3D", true, false)
			_check(parts.size() == 1 and enemy._body_mat != null, "%s 模型與攻擊預警材質" % id)
			var motion: AnimationPlayer = enemy._anim
			_check(motion != null and motion.has_animation("Walk") and motion.has_animation("Shoot" if id == "H02" else "Slash"), "%s 的移動與攻擊動作可播放" % id)
			if parts.size() == 1:
				var part: MeshInstance3D = parts[0]
				var bounds := part.global_transform * part.get_aabb()
				_check(absf(bounds.size.y - 1.8) < 0.02 and absf(bounds.position.y) < 0.02, "%s 站姿與膠囊對齊" % id)
			if id == "H02":
				_check_draw(enemy, world)
			enemy.queue_free()
		var spark := FX.play(world, Vector3.ZERO, &"hit-spark", 1.0, 0.1)
		await _frames(12)
		_check(not is_instance_valid(spark), "一次性命中特效播放完畢會釋放")
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


func _check_draw(enemy, world) -> void:
	var flat: Vector3 = Vector3.FORWARD * 12
	var shots: Array = []
	var capture := func(child):
		if child.get_script() == preload("res://scripts/projectile.gd"):
			shots.append(child)
	world.child_entered_tree.connect(capture)
	enemy._skill_cd = -5.0
	enemy._behaviour(.35, flat, 12)
	_check(shots.is_empty() and enemy._bow.arrow.visible, "進入射程時先搭箭")
	enemy._behaviour(.02, flat, 24)
	_check(enemy._draw < 0 and not enemy._bow.arrow.visible, "離開射程會收弓")
	enemy._behaviour(.5, flat, 12)
	enemy._stun_t = .05
	enemy._physics_process(.05)
	_check(enemy._draw < 0 and shots.is_empty(), "暈眩中斷引弓")
	enemy._behaviour(.25, flat, 12)
	var start_gap: float = enemy._bow.palm(0).distance_to(enemy._bow.palm(1))
	enemy._behaviour(.88, flat, 12)
	var full_gap: float = enemy._bow.palm(0).distance_to(enemy._bow.palm(1))
	_check(shots.is_empty() and full_gap > start_gap + .28, "滿弓時雙手拉開，箭仍在弦上")
	var tip: Vector3 = enemy._bow.tip_position()
	enemy._behaviour(.04, flat, 12)
	_check(shots.size() == 1 and not enemy._bow.arrow.visible, "放弦只發射一支箭")
	if shots.size() == 1:
		_check(tip.distance_to(shots[0].global_position) < .035, "飛箭與弦上箭頭對齊")
	enemy._behaviour(.65, flat, 12)
	_check(enemy._draw < 0 and shots.size() == 1, "收勢不會重複發射")
	world.child_entered_tree.disconnect(capture)
	for shot in shots:
		shot.queue_free()
