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
		await _check_weapon_views(player)
		await _check_cover_tactics(world, player)
		await _check_hit_reactions(world)
		var gate = world.rooms[0].gate_out
		var meshes := (gate as Node).find_children("*", "MeshInstance3D", true, false)
		_check(meshes.size() == 1, "山寨門只有一個可見模型")
		if meshes.size() == 1:
			var gate_mesh: MeshInstance3D = meshes[0]
			var bounds := gate_mesh.global_transform * gate_mesh.get_aabb()
			_check(bounds.size.distance_to(Vector3(0.6, 4, 6)) < 0.03 and absf(bounds.position.y) < 0.01, "寨門與門洞對齊")
		for id in ["H01", "H02", "H03", "H07", "H08"]:
			var enemy = world.spawn_enemy(id, Vector3(-10, 0, 0), false)
			var parts: Array = enemy._visual.find_children("Smart_*", "MeshInstance3D", true, false)
			_check(parts.size() == 1 and enemy._body_mat.vertex_color_use_as_albedo, "%s 模型與攻擊預警材質" % id)
			var motion: AnimationPlayer = enemy._anim
			_check(motion != null and motion.has_animation("Walk") and motion.has_animation("Shoot" if id == "H02" else "Slash"), "%s 的移動與攻擊動作可播放" % id)
			if parts.size() == 1:
				var part: MeshInstance3D = parts[0]
				var bounds := part.global_transform * part.get_aabb()
				_check(absf(bounds.size.y - 1.8 * enemy.size) < 0.02 and absf(bounds.position.y) < 0.02, "%s 站姿與膠囊對齊" % id)
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


func _check_cover_tactics(world, player) -> void:
	# 第一房的中央路障佔 x=28..30、z=-3..3。
	var original: Vector3 = player.global_position
	world.set_physics_process(false)
	player.set_physics_process(false)
	world.current = 0
	player.global_position = Vector3(33,.1,0)
	var archer = world.spawn_enemy("H02",Vector3(26,0,0),false)
	archer._skill_cd = 0
	await _frames(3)
	_check(not archer._clear_shot() and archer._draw < 0 and archer.velocity.slide(Vector3.UP).length() > .1, "隔著路障先換位，不原地拉弓")
	var bolt = preload("res://scripts/projectile.gd").new()
	world.add_child(bolt)
	bolt.global_position = Vector3(26,1,0)
	bolt.from_player = false
	bolt.direction = Vector3.RIGHT
	bolt.speed = 80
	bolt._physics_process(.1)
	_check(bolt.is_queued_for_deletion() and bolt.global_position.x < 30, "飛行中的敵箭在障礙物表面停止")
	var fired: Array = []
	var capture := func(node):
		if node.get_script() == preload("res://scripts/projectile.gd"):
			fired.append(node)
	world.child_entered_tree.connect(capture)
	for i in 650:
		await get_tree().physics_frame
		if not fired.is_empty():
			break
	_check(not fired.is_empty() and archer._clear_shot(), "弓手繞出掩體後能恢復射擊")
	world.child_entered_tree.disconnect(capture)
	for shot in fired:
		if is_instance_valid(shot):
			shot.queue_free()
	archer.queue_free()
	var fighter = world.spawn_enemy("H01",Vector3(25,0,0),false)
	var ally = world.spawn_enemy("H01",Vector3(26,0,0),false)
	_check(absf(fighter._flank_offset(Vector3.RIGHT).y) > .5, "前方已有近戰同伴會找側面空位")
	ally.queue_free()
	var widest := 0.0
	for i in 550:
		await get_tree().physics_frame
		widest = maxf(widest,absf(fighter.global_position.z))
		if fighter.global_position.x > 31:
			break
	_check(widest > 3 and fighter.global_position.x > 31, "近戰實際繞過中央路障並回到玩家這一側")
	fighter.queue_free()
	world.current = -1
	player.global_position = original
	player.set_physics_process(true)
	world.set_physics_process(true)
	await _frames(2)

func _check_weapon_views(player) -> void:
	var allowed: Array = []
	for rarity in Data.rarity_order:
		allowed.append_array(Game._pool(rarity,"W",{})[0])
	allowed.sort()
	_check(allowed==["W001","W007","W301"],"此版本只開放太刀、弓、大劍")
	var old: Array = Game.weapons.duplicate(true)
	Game.weapons[0] = {"id":"W007","lv":1}
	Game.weapons[1] = {"id":"W303","lv":1}
	Game.recompute()
	var bow = player.weapon_models[0]
	var crossbow = player.weapon_models[1]
	var events: Array = []
	bow.attack(.8,1,func(i): events.append("弓%d"%i))
	crossbow.attack(.8,3,func(i): events.append("弩%d"%i))
	await _frames(8)
	_check(events.is_empty() and bow.arrow.visible,"蓄力尚未放箭")
	_check(bow.loader.visible and bow.loader.position.distance_to(bow.arrow.position)<.001,"搭箭時副手夾住箭尾")
	Game.recompute()
	_check(player.weapon_models[0] == bow,"刷新屬性保留進行中的動作")
	await _frames(21)
	_check(bow.flex_mesh.get_blend_shape_value(0)>.95 and bow.arrow.visible and bow.loader.position.distance_to(bow.arrow.position)<.001,"滿弓時弓身變形且箭尾仍在指間")
	await _frames(28)
	_check(events.count("弓0")==1 and events.count("弩0")==1 and events.count("弩1")==1 and events.count("弩2")==1 and events.size()==4,"雙手節拍獨立且每次放箭只觸發一次")
	_check(not bow.arrow.visible and not bow.loader.visible and bow.position.is_equal_approx(bow.home),"放箭後收臂回到握位")
	player._attack(0)
	var count: int = player.attack_count
	player._attack(1)
	_check(not crossbow.visible and player.attack_count==count,"副手搭箭時另一把武器收起並等待")
	await _frames(62)
	_check(crossbow.visible,"收勢後恢復另一把武器")
	Game.weapons[0] = {"id":"W001","lv":1}
	Game.recompute()
	var tachi = player.weapon_models[0]
	_check(not tachi.blade.visible, "太刀待機入鞘")
	var strokes: Array = []
	tachi.attack(.8,1,func(i): strokes.append([i,tachi.blade.scale.z]))
	await _frames(10)
	_check(tachi.saya_hand.visible and tachi.blade.visible and strokes.is_empty(), "扶鞘拔刀尚未命中")
	await _frames(46)
	_check(strokes.size()==1 and strokes[0][1]>.99 and tachi.blade.visible and tachi.tachi_open, "出鞘後命中一次並回到持刀架勢")
	await _frames(115)
	_check(not tachi.blade.visible,"停手後納刀")
	player.set_physics_process(false)
	Input.action_press(tachi.attack_action)
	for strike in 3:
		tachi.attack(.30,1,func(i): strokes.append([i,tachi.blade.scale.z]); return true)
		await _frames(21)
		_check(tachi.tachi_open and tachi.tachi_chain==strike, "第%d刀保持出鞘連段" % (strike+1))
	Input.action_release(tachi.attack_action)
	await _frames(115)
	_check(strokes.size()==4 and not tachi.blade.visible and not tachi.tachi_returning, "三連斬各一次傷害，鬆鍵收刀")
	player.set_physics_process(true)
	Game.weapons = old
	Game.recompute()

func _check_hit_reactions(world) -> void:
	var e = world.spawn_enemy("H03", Vector3(-10, 0, 0), false)
	e.set_physics_process(false)
	e.rotation = Vector3.ZERO
	var origin: Vector3 = e.global_position
	var right: Vector3 = e.player.cam.global_basis.x.slide(Vector3.UP).normalized()
	e.take_hit(1, origin - right, false, .65)
	await _frames(3)
	var light: float = e._impact_pivot.position.dot(right)
	_check(e._flash_meshes[0].material_overlay == e._flash and e._flash.albedo_color.a > .5, "受擊立即泛紅")
	await _frames(4)
	_check(light > 0 and e._impact_pivot.position.dot(right) < 0, "單次受擊在畫面左右兩側擺動")
	e.take_hit(1, origin + right, false, 1.8)
	await _frames(3)
	_check(e._impact_pivot.position.dot(right) < -light, "重擊晃動更大")
	var before = e._recoil
	e._apply_damage(1, false, true)
	_check(before == e._recoil, "毒傷不重啟受擊動作")
	e.take_hit(1, origin + Vector3.FORWARD, true)
	await _frames(3)
	_check(e._impact_pivot.position.length() > .01 and e._flash.albedo_color.a > 0, "盾擋也晃動泛紅")
	await _frames(32)
	_check(e._flash_meshes[0].material_overlay == null, "泛紅結束還原原本外觀")
	_check(e._impact_pivot.transform.is_equal_approx(Transform3D.IDENTITY) and e.global_position.is_equal_approx(origin), "連擊後完全回正，碰撞位置不漂移")
	e.queue_free()
