extends Node
## 自動冒煙測試：三名角色各自跑完 4 張地圖 20 區，並測試武器、參悟、全武學圓滿、受傷與介面
## 執行：run_tests.bat（或 godot --headless --fixed-fps 60 --path . res://tests/Smoke.tscn）

const MAIN := preload("res://scripts/main.gd")
var main
var errors := 0


func _ready() -> void:
	Settings.save_enabled = false     # 不寫入玩家的設定檔
	Settings.values["hitstop"] = 0.0   # 頓幀以真實時間計算，整局流程測試先關掉（_check_game_feel 會單獨測）
	main = MAIN.new()
	add_child(main)
	await _frames(5)
	_check_music("menu")
	var first_btn = get_viewport().gui_get_focus_owner()
	_check(first_btn is ComicButton and first_btn.text == "踏上江湖", "主選單焦點在「踏上江湖」（Enter 可直接開始）")
	UIKit.kbd_nav = false
	first_btn._on_focus(true)
	_check(not first_btn.has_theme_stylebox_override("normal"), "滑鼠操作時「踏上江湖」預設不顯示高亮")
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.physical_keycode = KEY_DOWN
	down.pressed = true
	main._input(down)
	_check(UIKit.kbd_nav and first_btn.has_theme_stylebox_override("normal") and get_viewport().gui_get_focus_owner() == first_btn, "第一次按方向鍵先亮出目前焦點")
	var mv := InputEventMouseMotion.new()
	mv.relative = Vector2(10, 0)
	main._input(mv)
	_check(not UIKit.kbd_nav and not first_btn.has_theme_stylebox_override("normal"), "動滑鼠後焦點高亮消失")
	await _check_audio_settings()
	for cid in Data.char_order:
		await _run_character(cid)
	print("SMOKE_DONE errors=%d" % errors)
	get_tree().quit(0 if errors == 0 else 1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e


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
		_check_music(Data.map_order[0])
		await _check_weapon_views(player)
		await _check_loot_and_shops(world, player)
		_check_meridians_and_shrine(player)
		_check_wheel()
		await _check_bow(player)
		await _check_cover_tactics(world, player)
		await _check_hit_reactions(world)
		await _check_game_feel(world, player)
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
	var wids: Array = Game.FEATURED_WEAPONS.duplicate()
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
			if String(Data.stage_row(r.stage).rest_stop) == "1":
				var learnable: bool = Data.martial.keys().any(func(mid): return Game.can_learn(mid))
				_check(world.smith_node != null and world.merchant_node != null and (Game.merchant_stock.size() > 0 or not learnable), "第%d區破陣後出現鐵匠與商人" % r.stage)
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
				main.gacha._skip()
				_check(main.gacha.state == "result" and not main.gacha.current.is_empty(), "天機輪轉完有候選")
				main.gacha._set_state("cards")
				main.gacha._on_pick(main.gacha.current[0], 1)
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
			print("  區域 %d 完成，境界 %s，武學 %d 門，抽數 %d" % [r.stage, Game.realm_name(), Game.martial.size(), Game.total_draws])
		# 走到出口
		player.global_position = Vector3(world.portal_x, 0.5, 0.0)
		await _frames(3)
	# 全部武學圓滿＋全武器，測試所有特效路徑
	Game.martial = {}
	Game.martial_order = []
	for mid in Data.martial:
		Game.martial[mid] = 5
		Game.martial_order.append(mid)
	Game.zhenqi = 1.0e9
	for mid in Data.meridian_order:
		var guard := 0
		while not Game.next_point(mid).is_empty() and guard < 60:
			guard += 1
			Game.try_break(mid)
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
			player._attack(Game.active_weapon)
			await _frames(2)
			player._do_switch(-1)
			player.swap_t = 0.0
	player.invuln_t = 0.0
	for k in 30:
		player.take_damage(5.0, null)
		player.hp = Game.max_hp()
		await _frames(1)
	player.invuln_t = 1.0e9
	await _frames(400)
	# 介面
	_check(main.screens.theme == UIKit.theme() and main.hud.theme == UIKit.theme() and main.gacha.theme == UIKit.theme(), "介面根節點套用條漫主題")
	_check(UIKit.serif() is FontFile and UIKit.sans() is FontFile, "載入隨附的裁切字型")
	for pid in Data.char_order:
		var crop = UIKit.portrait_crop(pid, 1.5, 0.3)
		var full: Texture2D = load("res://assets/portraits/%s.webp" % pid)
		_check(crop is AtlasTexture and Rect2(Vector2.ZERO, Vector2(full.get_size())).encloses(crop.region) and absf(crop.region.size.aspect() - 1.5) < 0.01, "%s 立繪依臉部位置裁切" % pid)
	Game.weapons = [{"id": "W001", "lv": 2}, {"id": "W007", "lv": 1}]
	Game.active_weapon = 0
	Game.recompute()
	main.hud._process(0.0)
	_check(main.hud.weapon_cards[0].line.visible and not main.hud.weapon_cards[1].line.visible, "HUD 標出手上的主武器")
	Game.switch_weapon()
	main.hud._process(0.0)
	_check(main.hud.weapon_cards[1].line.visible and main.hud.weapon_cards[1].name.text == "竹弓", "HUD 跟著切換到副武器")
	Game.switch_weapon(0)
	main.gacha.open()
	main.gacha.current = [{"kind": "W", "id": "W301", "rarity": "legendary"}]
	main.gacha._set_state("cards")
	var labels: Array = []
	for b in main.gacha.cards_root.find_children("*", "Button", true, false):
		labels.append(b.text)
	_check(labels.has("替換主武器：太刀") and labels.has("替換副武器：竹弓"), "參悟卡以主副武器替換")
	main.gacha._on_close()
	main.mode = "play"
	main.hud.show_banner("鎖　陣", "測試", "lock")
	main.hud.push_message("器靈覺醒：測試")
	await _frames(2)
	_check(main.hud.banner_burst.visible and main.hud.msg_box.get_child_count() > 0, "鎖陣橫幅與系統訊息")
	# 起手兵器、掉落比較、鐵匠、商人
	main.screens.show_weapon_pick()
	_check(main.screens.get_meta("picking_weapon", false), "選角後進入起手兵器")
	var picked: Array = []
	var record := func(_c, w): picked.append(w)
	main.screens.start_run.disconnect(main._start)
	main.screens.start_run.connect(record)
	main.screens._on_weapon_card_input(_click(), "W301", main.screens._weapon_sel)
	main.screens.start_run.disconnect(record)
	main.screens.start_run.connect(main._start)
	_check(picked == ["W301"], "點選起手兵器入江湖")
	main.hud.show_drop_compare(Game.make_weapon("W007", 2))
	_check(main.hud.drop_panel.visible and main.hud.drop_panel.get_child_count() > 3, "掉落兵器比較面板")
	main.hud.show_drop_compare(null)
	Game.gold = 5000.0
	Game.weapons = [Game.make_weapon("W001", 0), Game.make_weapon("W007", 2)]
	Game.recompute()
	main.open_shop("smith")
	await _frames(2)
	var lv0: int = Game.weapons[1].lv
	main.shop._on_upgrade(1)
	_check(Game.weapons[1].lv == lv0 + 1 and main.mode == "shop", "鐵匠頁強化副武器")
	main.shop._on_reforge(1)
	_check(Game.weapons[1].reforges == 1, "鐵匠頁重鑄副武器詞條")
	main.shop._on_close()
	main.open_shop("merchant")
	Game.restock_merchant()
	main.shop._refresh()
	await _frames(2)
	main.shop._on_buy(0)
	var stamps: int = main.shop.body.find_children("*", "ComicSeal", true, false).filter(func(n): return n.text == "已售出").size()
	_check(Game.merchant_stock.is_empty() or (Game.merchant_stock[0].sold and stamps == 1), "商人賣出後蓋已售出印章")
	main.shop._on_close()
	_check(main.mode == "play" and not main.shop.visible, "離開商人回到遊戲")
	# 經脈頁
	var keep_acu: Dictionary = Game.acu_open.duplicate()
	var keep_zq := Game.zhenqi
	Game.acu_open = {"du": 3}
	Game.zhenqi = 1.0e6
	main.open_meridian()
	await _frames(2)
	_check(main.mode == "meridian" and main.meridian.visible and main.meridian.chart.pos.size() == Data.meridian_len(main.meridian.mid), "K 打開經脈頁，穴位照該脈數量畫出")
	var open0 := Game.acu_total()
	main.meridian._on_break()
	_check(Game.acu_total() >= open0 and Game.zhenqi < 1.0e6, "經脈頁衝擊扣真氣")
	main.meridian._cycle(1)
	_check(main.meridian.mid != "" and main.meridian.chart.mid == main.meridian.mid, "A／D 切換經脈")
	main.meridian._on_close()
	_check(main.mode == "play" and not main.meridian.visible, "離開經脈頁回到遊戲")
	Game.acu_open = keep_acu
	Game.zhenqi = keep_zq
	Game.recompute()
	# 弓的紅圈準星
	Game.weapons = [Game.make_weapon("W007", 0), Game.make_weapon("W001", 0)]
	Game.active_weapon = 0
	Game.recompute()
	main.player.refresh_weapon_models()
	await _frames(3)
	_check(main.hud.reticle.visible and not main.hud.crosshair.visible and main.hud.reticle_r > 4.0, "拿弓時改用紅圈準星")
	Game.switch_weapon(1)
	main.player.refresh_weapon_models()
	await _frames(3)
	_check(not main.hud.reticle.visible and main.hud.crosshair.visible, "換回刀時恢復一般準星")
	main.screens.show_pause()
	main.screens.show_inventory(true)
	main.screens.show_end(true)
	main.screens.show_select()
	main.screens.show_help()
	await _frames(2)
	print("SMOKE_OK ", cid)
	main._to_menu()
	await _frames(3)


func _check_meridians_and_shrine(player) -> void:
	var keep := [Game.zhenqi, Game.acu_open.duplicate(), Game.acu_fails.duplicate(), Game.level, Game.gold, Game.shrine_charges, Game.refreshes_this_stage, Game.free_draws, Game.realm]
	# 真氣與衝穴
	Game.acu_open = {}
	Game.acu_fails = {}
	Game.level = 1
	Game.realm = 0
	Game.zhenqi = 0.0
	Game.recompute()
	_check(Data.meridian_order.size() == 8 and Data.acupoints.size() == 61 and Data.realm_list.size() == 9, "奇經八脈 61 穴、九個境界")
	var lens_ok := true
	for mid in Data.meridian_order:
		lens_ok = lens_ok and Data.meridian_len(mid) >= 6 and Data.meridian_len(mid) <= 10
	_check(lens_ok, "每條經脈 6～10 個穴位")
	_check(Game.try_break("du") == -1, "真氣不夠時不能衝穴")
	var pid: String = Game.next_point("du").point_id
	var c0 := Game.break_chance(pid)
	Game.acu_fails[pid] = 2
	_check(is_equal_approx(Game.break_chance(pid), minf(1.0, c0 + 2.0 * float(Data.meridian_cfg.chance_step))), "同一穴位衝擊越多次成功率越高")
	Game.acu_fails = {}
	var dmg0 := Game.st("dmg_pct")
	Game.zhenqi = 1.0e9
	var tries := 0
	while Game.acu_level("du") < 1 and tries < 30:
		tries += 1
		Game.try_break("du")
	_check(Game.acu_level("du") == 1 and Game.st("dmg_pct") > dmg0 and Game.realm == 0, "打通長強：傷害提升，還沒進境界")
	tries = 0
	while not Game.next_point("du").is_empty() and tries < 200:
		tries += 1
		Game.try_break("du")
	_check(Game.realm == 1 and Game.realm_name() == "二流" and Game.special_on("du"), "督脈全通：進入二流、啟動督脈貫頂")
	_check(Game.realm_list_ok(), "境界加成依 realms.csv")
	# 特殊效果
	player.du_charged = false
	var a0: int = player.attack_count
	for k in int(Game.special("du", "a")):
		player.attack_count += 1
		player._count_du()
	_check(player.du_charged or a0 < 0, "督脈貫頂：出招數到了會充能")
	player.du_charged = false
	for mid in Data.meridian_order:
		tries = 0
		while not Game.next_point(mid).is_empty() and tries < 200:
			tries += 1
			Game.try_break(mid)
	_check(Game.acu_total() == 61 and Game.realm == 8 and Game.realm_name() == "自然境" and Game.ren_du_open(), "八脈全通：自然境、小周天")
	var sp0: float = player.atk_speed_now()
	player.chong_t = 0.0
	player.chong_t = Game.special("chong", "b")
	_check(player.atk_speed_now() > sp0, "氣血奔湧：擊殺後攻速提升")
	player.chong_t = 0.0
	var hp_keep: float = player.hp
	player.ren_cd = 0.0
	player.invuln_t = 0.0
	for k in 20:   # 可能被閃避或減傷吃掉，多打幾下
		if player.ren_cd > 0.0:
			break
		player.hp = Game.max_hp() * 0.29
		player.take_damage(1.0)   # 低於 30% 時受到任何傷害就觸發；傷害很小不會死
		player.invuln_t = 0.0
	_check(player.hp > Game.max_hp() * 0.5 and player.ren_cd > 0.0, "任脈歸元：低血量時回復")
	player.hp = hp_keep
	player.invuln_t = 1.0e9
	# 悟道碑：每區免費參悟、刷新花銀兩（陰蹻脈全通：每區第一次刷新免費）
	Game.shrine_charges = 0
	Game.free_draws = 0
	Game.stage_zhenqi = 100.0
	var zq0 := Game.zhenqi
	Game.on_zone_cleared()
	_check(Game.zhenqi > zq0, "心靜神凝：破陣額外獲得真氣")
	var n := Game.draws_left()
	_check(n >= 1 and Game.take_draw() and Game.draws_left() == n - 1, "破陣後悟道碑可免費參悟")
	Game.gold = 1000.0
	_check(Game.refresh_cost() == 0 and Game.pay_refresh() and Game.refresh_cost() > 0, "心靜神凝：每區第一次刷新免費，之後花銀兩")
	var r0 := Game.refresh_cost()
	_check(Game.pay_refresh() and Game.refresh_cost() > r0 and Game.gold < 1000.0, "刷新候選花銀兩，同區越刷越貴")
	Game.zhenqi = keep[0]
	Game.acu_open = keep[1]
	Game.acu_fails = keep[2]
	Game.level = keep[3]
	Game.gold = keep[4]
	Game.shrine_charges = keep[5]
	Game.refreshes_this_stage = keep[6]
	Game.free_draws = keep[7]
	Game.realm = keep[8]
	Game.recompute()


func _check_wheel() -> void:
	## 天機輪：遊戲實作（GDScript）和數學模型（tools/shrine_math/wheel.py）分別驗證，再逐盤面對照
	var f := FileAccess.open("res://tests/wheel_golden.json", FileAccess.READ)
	_check(f != null, "找到天機輪黃金樣本 tests/wheel_golden.json")
	if f == null:
		return
	var cases: Array = JSON.parse_string(f.get_as_text()).cases
	var bad := 0
	for c in cases:
		var r := Game.wheel_eval(c.stops.map(func(x): return int(x)))
		if r.outcome != c.outcome or r.sect != c.sect or int(r.scatters) != int(c.scatters):
			bad += 1
			if bad <= 3:
				print("  天機輪不一致：", c, " → ", r)
	_check(cases.size() > 400 and bad == 0, "天機輪逐盤面判定與數學模型一致（%d 組）" % cases.size())
	# 機率公示：遊戲窮舉的精確機率＝模型的精確機率
	var rf := FileAccess.open("res://docs/shrine-math/results.json", FileAccess.READ)
	if rf:
		var th: Dictionary = JSON.parse_string(rf.get_as_text())
		var odds := Game.wheel_odds()
		_check(is_equal_approx(odds.sense, th.P.sense) and is_equal_approx(odds.resonance, th.P.resonance) and is_equal_approx(odds.bagua, th.P.bagua) and is_equal_approx(odds.trigger, th.p_trigger), "機率公示與數學模型的精確值相同")
	# 遊戲的亂數實際轉：頓悟率、門派共鳴率要落在理論的 99.9% 區間（|z| ≤ 3.29）
	var n := 20000
	var trig := 0
	var res := 0
	var saved_state := Game.rng.state
	Game.rng.seed = 20261113          # 固定種子：結果可重現，不會有千分之一的隨機失敗
	for i in n:
		var r := Game.wheel_eval(Game.wheel_spin())
		if int(r.scatters) >= 3:
			trig += 1
		if r.outcome == "resonance":
			res += 1
	Game.rng.state = saved_state
	var odds2 := Game.wheel_odds()
	var z1: float = (float(trig) / n - odds2.trigger) / sqrt(odds2.trigger * (1.0 - odds2.trigger) / n)
	var z2: float = (float(res) / n - odds2.resonance) / sqrt(odds2.resonance * (1.0 - odds2.resonance) / n)
	print("  天機輪 20,000 轉：頓悟 z=%.2f、門派共鳴 z=%.2f" % [z1, z2])
	_check(absf(z1) <= 3.29 and absf(z2) <= 3.29, "遊戲亂數的頓悟率與共鳴率符合理論")
	if rf:
		_check_wheel_budget(JSON.parse_string(FileAccess.get_file_as_string("res://docs/shrine-math/results.json")))
	# 結果套用到候選
	var keep_l := Game.since_legendary
	var keep_m: Dictionary = Game.martial.duplicate()
	var keep_free := Game.wheel_free
	Game.martial = {}
	var cands := Game.roll_choices({"sect": "tangmen", "sect_slots": 99, "bump": 1})
	_check(cands.size() >= 3 and cands.all(func(c): return c.kind == "M" and Data.martial[c.id].sect == "tangmen"), "門派共鳴：三張候選都是該門派")
	cands = Game.roll_choices({"legendary": true, "bump": 1})
	_check(cands.any(func(c): return c.rarity == "legendary") and cands.all(func(c): return c.rarity != "common"), "八卦歸一：必出絕世、其餘升階")
	Game.wheel_free = 0
	var trig_stops: Array = []
	for c in cases:
		if int(c.scatters) >= 3:
			trig_stops = c.stops.map(func(x): return int(x))
			break
	Game.wheel_roll(trig_stops)
	_check(Game.wheel_free == int(Data.wheel_cfg.free_spins) and Game.draws_left() >= Game.wheel_free, "頓悟送免費參悟")
	Game.since_legendary = keep_l
	Game.martial = keep_m
	Game.wheel_free = keep_free
	Game.recompute()


func _check_wheel_budget(th: Dictionary) -> void:
	## 候選稀有度：讓 Game.roll_choices() 實際抽，平均預算要符合模型的期望值（|z| ≤ 3.29）
	## 模型的計算邊界是起始狀態：沒學過武學、無幸運、無保底、無額外候選與保證效果
	var keep_l := Game.since_legendary
	var keep_m: Dictionary = Game.martial.duplicate()
	var keep_d := [Game.draws_this_stage, Game.total_draws]
	var keep_rng: int = Game.rng.state
	Game.rng.seed = 20261112   # 固定種子，結果可重現
	Game.martial = {}
	Game.recompute()
	var clean: bool = Game.st("luck") == 0.0 and Game.f("extra_choice") == 0.0 and Game.f("guarantee_tangmen") == 0.0 and Game.f("guarantee_upgrade") == 0.0
	_check(clean, "天機輪預算檢查的前提：無幸運、無額外候選與保證效果")
	if clean:
		var budget := {}
		for r in Data.rarity_order:
			budget[r] = float(Data.rarity[r].power_budget)
		var cases: Array = [["一般", {}, float(th.g.none)],
			["八卦歸一", {"legendary": true, "bump": int(Data.wheel_cfg.bagua_bump)}, float(th.g.bagua)]]
		for sect in th.g.resonance_by_sect:
			cases.append(["共鳴・" + String(sect), {"sect": sect, "sect_slots": 99, "bump": int(Data.wheel_cfg.resonance_bump)}, float(th.g.resonance_by_sect[sect])])
		var n := 4000
		var bad: Array = []
		var line: Array = []
		for c in cases:
			var s := 0.0
			var s2 := 0.0
			for i in n:
				Game.martial = {}
				Game.since_legendary = 0
				var tot := 0.0
				for cand in Game.roll_choices(c[1]):
					tot += float(budget[cand.rarity])
				s += tot
				s2 += tot * tot
			var mean := s / n
			var sd := sqrt(maxf(1e-12, (s2 / n - mean * mean) * n / (n - 1)))
			var z: float = (mean - float(c[2])) / (sd / sqrt(n))
			var extra := ""
			if String(c[0]).begins_with("共鳴"):
				extra = "（v1 %.2f）" % ((mean - float(th.naive_v1.g_resonance)) / (sd / sqrt(n)))
			line.append("%s %.3f/%.3f z=%+.2f%s" % [c[0], mean, float(c[2]), z, extra])
			if absf(z) > 3.29:
				bad.append(c[0])
		print("  天機輪候選預算（種子 20261112，實抽/理論，各 %d 次）：" % n, "、".join(line))
		_check(bad.is_empty(), "天機輪候選預算符合模型 %s" % [bad])
	Game.since_legendary = keep_l
	Game.martial = keep_m
	Game.draws_this_stage = keep_d[0]
	Game.total_draws = keep_d[1]
	Game.rng.state = keep_rng
	Game.recompute()


func _check_bow(player) -> void:
	var keep: Array = Game.weapons.duplicate(true)
	var keep_slot := Game.active_weapon
	Game.weapons = [Game.make_weapon("W007", 0), null]
	Game.active_weapon = 0
	Game.recompute()
	player.refresh_weapon_models()
	player.cooldowns = [0.0, 0.0]
	await _frames(2)
	_check(player.is_bow(), "弓走拉弓流程")
	var shots: int = player.attack_count
	Input.action_press("aim")
	Input.action_press("attack_1")
	await _frames(50)
	_check(player.bow_held and player.bow_draw() > 0.5, "按住左鍵拉弓")
	_check(player.cam.fov < 60.0, "右鍵瞄準視角放大")
	_check(player.attack_count == shots, "拉弓中還沒射出")
	var sp_full: float = player.bow_spread_deg(1.0)
	_check(player.bow_spread_deg(0.0) > sp_full * 3.0 and sp_full > 0.0, "拉越滿散射越小")
	var dir: Vector3 = player._spread_dir(Vector3.FORWARD, 5.0)
	_check(rad_to_deg(dir.angle_to(Vector3.FORWARD)) <= 5.01, "箭落在散射圈內")
	Input.action_release("attack_1")
	await _frames(2)
	_check(player.attack_count == shots + 1 and not player.bow_held, "放開左鍵射出")
	Input.action_release("aim")
	await _frames(20)
	_check(player.cam.fov > 79.0, "放開右鍵視角恢復")
	# 拉不夠就放開：不射
	player.cooldowns = [0.0, 0.0]
	await _frames(30)
	Input.action_press("attack_1")
	await _frames(3)
	Input.action_release("attack_1")
	await _frames(2)
	_check(player.attack_count == shots + 1, "拉弓不足就放開不會射出")
	await _frames(20)
	Game.weapons = keep
	Game.active_weapon = keep_slot
	Game.recompute()
	player.refresh_weapon_models()


func _check_loot_and_shops(world, player) -> void:
	var old_weapons: Array = Game.weapons.duplicate(true)
	var old_gold: float = Game.gold
	var old_martial: Dictionary = Game.martial.duplicate()
	var old_order: Array = Game.martial_order.duplicate()
	# 起手武器
	_check(Game.starter_weapons() == ["W001", "W007", "W301"], "起手可選太刀、弓、大劍")
	# 詞條
	var affixes: Array = Game.roll_affixes("W007", 4)
	var ids := {}
	var in_range := true
	for a in affixes:
		ids[a.id] = true
		var row: Dictionary = Data.affixes[a.id]
		var t: float = Game.affix_tier(row)
		in_range = in_range and float(a.v) >= float(row.min) * t - 0.01 and float(a.v) <= float(row.max) * t + 0.01 and row.range_type != "melee"
	_check(affixes.size() == 4 and ids.size() == 4 and in_range, "遠程武器抽 4 條不重複、在範圍內、沒有近戰限定的詞條")
	# 詞條品階：後面區域數值較高，輸出詞條成長比生存詞條快
	var keep_stage: int = Game.stage
	Game.stage = 20
	var late_tier: float = Game.affix_tier(Data.affixes["A01"])
	_check(late_tier > 3.0 and Game.affix_tier(Data.affixes["A07"]) < 2.0, "第20區輸出詞條品階>3、減傷詞條品階<2")
	Game.stage = keep_stage
	# 淬煉傳承
	var heir: Dictionary = Game.make_weapon("W007", 1)
	Game.inherit_level(heir, {"id": "W001", "lv": 4, "affixes": [], "reforges": 0})
	_check(int(heir.lv) == 4 - int(Data.cfg("inherit_lv_loss")), "換武器時沿用舊武器的淬煉等級")
	# 悟道碑不再為已持有武器淬煉
	var keep_w: Array = Game.weapons.duplicate(true)
	Game.weapons = [Game.make_weapon("W001", 0), null]
	var pw: Array = Game._pool(Data.weapons["W001"].rarity, "W", {})
	_check(not ("W001" in pw[0]) and "W007" in pw[0], "悟道碑武器候選不含已持有的武器")
	Game.weapons = keep_w
	var boss_drop: Dictionary = Game.roll_weapon_drop("boss")
	_check(not boss_drop.is_empty() and boss_drop.affixes.size() >= 3 and boss_drop.id in Game.FEATURED_WEAPONS, "首領必掉至少 3 條詞條的武器")
	# 手上那把的詞條才生效
	Game.weapons = [Game.make_weapon("W001", 0), {"id": "W007", "lv": 1, "affixes": [{"id": "A01", "v": 10.0}], "reforges": 0}]
	Game.active_weapon = 0
	Game.recompute()
	var base_dmg := Game.st("dmg_pct")
	Game.switch_weapon(1)
	_check(is_equal_approx(Game.st("dmg_pct"), base_dmg + 10.0), "切到副武器後它的詞條生效")
	Game.switch_weapon(0)
	_check(is_equal_approx(Game.st("dmg_pct"), base_dmg), "收起的武器詞條不生效")
	# 撿取
	Game.weapons[1] = null
	var drop: Dictionary = Game.make_weapon("W301", 2)
	_check(Game.pick_up(drop) == null and Game.weapons[1] == drop, "副武器格空著時撿起放進副武器")
	var again: Dictionary = Game.make_weapon("W007", 1)
	var swapped = Game.pick_up(again)
	_check(swapped != null and swapped.id == "W001" and Game.weapons[0] == again, "兩格都有武器時換掉手上那把")
	var node: Node3D = world.spawn_drop(player.global_position, Game.make_weapon("W001", 3))
	main.mode = "play"
	main._on_interact()
	_check(not is_instance_valid(node) or node.is_queued_for_deletion(), "站在掉落武器上按 E 撿起")
	_check(Game.current_weapon().id == "W001" and Game.current_weapon().affixes.size() == 3, "撿起的武器換到手上")
	_check(world.drops.size() == 1, "換下的武器掉在地上")
	for d in world.drops:
		d.queue_free()
	world.drops = []
	# 鐵匠
	Game.gold = 1000.0
	var cost := Game.upgrade_cost(0)
	var lv: int = Game.weapons[0].lv
	_check(cost > 0 and Game.upgrade_weapon(0) and Game.weapons[0].lv == lv + 1 and is_equal_approx(Game.gold, 1000.0 - cost), "鐵匠強化扣銀兩並淬煉+1")
	var before: Array = Game.weapons[0].affixes.duplicate(true)
	cost = Game.reforge_cost(0)
	_check(cost > 0 and Game.reforge_weapon(0) and Game.weapons[0].affixes.size() == before.size() and Game.weapons[0].reforges == 1, "重鑄詞條數不變並記錄次數")
	_check(Game.reforge_cost(0) > cost, "重鑄越多次越貴")
	Game.weapons[1] = Game.make_weapon("W007", 0)
	_check(Game.reforge_cost(1) == -1 and not Game.reforge_weapon(1), "沒有詞條的武器不能重鑄")
	# 商人
	Game.martial = {}
	Game.martial_order = []
	Game.restock_merchant()
	_check(Game.merchant_stock.size() == int(Data.cfg("merchant_slots")), "商人上架 %d 門武學" % int(Data.cfg("merchant_slots")))
	var first: Dictionary = Game.merchant_stock[0]
	var price := Game.martial_price(first.id)
	var gold_before := Game.gold
	_check(Game.buy_martial(0) and Game.martial.get(first.id, 0) == 1 and is_equal_approx(Game.gold, gold_before - price), "買武學扣銀兩並習得")
	_check(not Game.buy_martial(0), "賣出的武學不能再買")
	var refresh := Game.merchant_refresh_cost()
	gold_before = Game.gold
	_check(Game.refresh_merchant() and is_equal_approx(Game.gold, gold_before - refresh), "刷新上架扣銀兩")
	Game.weapons = old_weapons
	Game.active_weapon = 0
	Game.gold = old_gold
	Game.martial = old_martial
	Game.martial_order = old_order
	Game.recompute()
	await _frames(2)


func _check_audio_settings() -> void:
	# 預設值：音樂 30%、音效 50%（data/settings_config.csv）
	_check(is_equal_approx(float(Data.settings_cfg.music_volume.default), 0.3) and is_equal_approx(float(Data.settings_cfg.sfx_volume.default), 0.5), "預設音樂 30%、音效 50%")
	var mi := AudioServer.get_bus_index("Music")
	var si := AudioServer.get_bus_index("SFX")
	_check(mi > 0 and si > 0, "建立 Music／SFX 匯流排")
	_check(Music.players[0].bus == "Music" and Sfx._p2[0].bus == "SFX" and Sfx._p3[0].bus == "SFX", "配樂與音效走各自的匯流排")
	var old := Settings.get_value("music_volume")
	Settings.set_value("music_volume", 0.5)
	_check(absf(AudioServer.get_bus_volume_db(mi) - linear_to_db(0.5)) < 0.01, "音樂音量套用到匯流排")
	Settings.set_value("music_volume", 0.0)
	_check(AudioServer.is_bus_mute(mi), "音樂調到 0 會靜音")
	Settings.set_value("music_volume", old)
	_check(not AudioServer.is_bus_mute(mi) or old <= 0.001, "還原音樂音量")
	# 每個音效都載得到
	var missing: Array = []
	for id in Data.sfx:
		if Sfx.streams(id).is_empty():
			missing.append(id)
	_check(missing.is_empty(), "sfx.csv 的音效檔都在（缺：%s）" % str(missing))
	_check(Data.sfx.size() >= 60, "音效清單至少 60 個（實際 %d）" % Data.sfx.size())
	Sfx._last_ms.clear()
	_check(Sfx.play("ui_click") != null and Sfx.play("ui_click") == null, "同一音效最短間隔內不重播")
	_check(Sfx.play("not_a_sound") == null, "未知音效不會當機")
	# 設定頁
	main.screens.show_settings(false)
	await _frames(2)
	var sl = main.screens.settings_sliders.get("sfx_volume")
	_check(sl != null and main.screens.settings_sliders.size() == 5, "設定頁有 5 個滑桿（實際 %d）" % main.screens.settings_sliders.size())
	if sl:
		var before := Settings.get_value("sfx_volume")
		sl.value = 0.8
		_check(is_equal_approx(Settings.get_value("sfx_volume"), 0.8), "拖滑桿改音效音量")
		Settings.set_value("sfx_volume", before)
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	main.screens._unhandled_key_input(esc)
	await _frames(1)
	_check(not main.screens.has_meta("settings_from"), "Esc 離開設定頁")
	main.screens.show_main()


func _check_game_feel(world, player) -> void:
	# 頓幀：時間變慢，之後自動恢復；關掉設定就沒有
	Feel.reset()
	Settings.values["hitstop"] = 1.0
	Feel.hitstop(0.05)
	_check(Engine.time_scale < 0.2, "命中頓幀壓低時間")
	var waited := 0
	while Engine.time_scale < 1.0 and waited < 2000:
		await get_tree().process_frame
		waited += 1
	_check(Engine.time_scale == 1.0, "頓幀結束恢復正常時間")
	Settings.values["hitstop"] = 0.0
	Feel.hitstop(0.05)
	_check(Engine.time_scale == 1.0, "關閉頓幀設定後不停頓")
	# 震動
	Feel.shake(0.6)
	await get_tree().process_frame
	_check(Feel.trauma > 0.0 and absf(player.cam.h_offset) + absf(player.cam.v_offset) > 0.0, "畫面震動帶動相機")
	Settings.values["screen_shake"] = 0.0
	Feel.reset()
	Feel.shake(0.6)
	_check(Feel.trauma == 0.0, "畫面震動設為 0 就不震")
	Settings.values["screen_shake"] = 1.0
	Feel.reset()
	# 一次命中：分層音效、擊退、形變、粒子、跳字
	Sfx.log_plays = true
	Sfx.played.clear()
	Sfx._last_ms.clear()
	var e = world.spawn_enemy("H01", player.global_position + player.global_basis * Vector3(0, 0, -2.5), false)
	e.max_hp = 1.0e6
	e.hp = 1.0e6
	var before_nodes: Array = world.get_children()
	player._imp = {"crit": false, "kill": false, "metal": false}
	_check(player.deal(e, 10.0, false, 1.0), "測試命中成功")
	player._impact_feedback(1.0)
	_check(e._knock.length() > 0.5, "命中把敵人往後擊退")
	_check(Sfx.played.has("hit_low") and Sfx.played.has("hit_mid_flesh") and Sfx.played.has("hit_high"), "命中播三層音效（低頻、中頻、高頻）：%s" % str(Sfx.played))
	await _frames(2)
	_check(not e._impact_pivot.scale.is_equal_approx(Vector3.ONE), "受擊形變（擠壓伸展）")
	var parts := 0
	var nums := 0
	for c in world.get_children():
		if c in before_nodes:
			continue
		if c.get_script() == preload("res://scripts/burst.gd"):
			parts += 1
		elif c is Label3D:
			nums += 1
	_check(parts >= 2 and nums >= 1, "命中噴出粒子與傷害跳字（粒子 %d、跳字 %d）" % [parts, nums])
	# 擊殺：加層音效、屍身打飛後才消失
	Sfx.played.clear()
	Sfx._last_ms.clear()
	e.hp = 1.0
	player._imp = {"crit": false, "kill": false, "metal": false}
	player.deal(e, 50.0, false, 1.8)
	player._impact_feedback(1.8)
	_check(e.dead and is_instance_valid(e) and e.collision_layer == 0, "擊殺後屍身先被打飛（無碰撞）")
	_check(Sfx.played.has("kill_boom") and Sfx.played.has("enemy_death"), "擊殺加層音效")
	var gone := false
	for i in 200:
		await get_tree().physics_frame
		if not is_instance_valid(e):
			gone = true
			break
	_check(gone, "打飛結束後移除屍身")
	Sfx.log_plays = false
	Feel.reset()


func _check_music(key: String) -> void:
	_check(Music.current == key, "目前配樂是 %s（實際 %s）" % [key, Music.current])
	var row: Dictionary = Data.music.get(key, {})
	_check(not row.is_empty(), "music.csv 有 %s" % key)
	if row.is_empty():
		return
	var p: AudioStreamPlayer = Music.active_player()
	var s = p.stream
	_check(p.playing and s is AudioStreamOggVorbis, "%s 配樂正在播放" % key)
	if s is AudioStreamOggVorbis:
		_check(s.loop and absf(s.loop_offset - float(row.loop_offset_s)) < 0.001, "%s 配樂循環點正確" % key)
		_check(float(row.loop_offset_s) < s.get_length(), "%s 循環點在曲長之內" % key)


func _check_draw(enemy, world) -> void:
	var flat: Vector3 = Vector3.FORWARD * 12
	var shots: Array = []
	var capture := func(child):
		if child.get_script() == preload("res://scripts/projectile.gd"):
			shots.append(child)
	world.child_entered_tree.connect(capture)
	var ai: Dictionary = enemy.ai
	_check(ai.windup_s >= 1.0 and ai.lock_s > 0.2 and ai.lock_s < ai.windup_s, "弓手起手至少 1 秒，最後一段才鎖定")
	_check(ai.cd_min_s >= 2.0 and ai.attack_chance < 1.0, "弓手出手間隔拉長，不會每次輪到就射")
	ai.attack_chance = 1.0
	enemy._aim_cd = 0.0
	enemy._behaviour(.02, Vector3.FORWARD * 2, 2)
	_check(enemy._rstate == "move" and enemy._draw < 0, "玩家貼身時不起手，先後撤")
	enemy._aim_cd = 0.0
	enemy._behaviour(.02, flat, 12)
	_check(enemy._rstate == "aim" and shots.is_empty(), "舒適距離內起手拉弓")
	enemy._behaviour(.35, flat, 12)
	_check(shots.is_empty() and enemy._bow.arrow.visible, "拉弓中先搭箭")
	enemy._behaviour(ai.windup_s - ai.lock_s - .45, flat, 12)
	_check(shots.is_empty() and not enemy._lock.is_finite(), "鎖定前不出手")
	enemy._behaviour(.02, Vector3.FORWARD * 2, 2)
	_check(enemy._rstate == "move" and enemy._draw < 0 and shots.is_empty(), "鎖定前被逼近會收弓後撤")
	enemy._stun_t = 0.0
	enemy._aim_cd = 0.0
	enemy._behaviour(.02, flat, 12)
	enemy._behaviour(.3, flat, 12)
	enemy._stun_t = .05
	enemy._physics_process(.05)
	_check(enemy._rstate == "move" and enemy._draw < 0 and shots.is_empty(), "暈眩中斷引弓")
	enemy._stun_t = 0.0
	enemy._aim_cd = 0.0
	enemy._behaviour(.02, flat, 12)
	var start_gap: float = enemy._bow.palm(0).distance_to(enemy._bow.palm(1))
	enemy._behaviour(ai.windup_s - ai.lock_s + .05, flat, 12)
	var full_gap: float = enemy._bow.palm(0).distance_to(enemy._bow.palm(1))
	_check(shots.is_empty() and enemy._lock.is_finite() and full_gap > start_gap + .2, "鎖定時弓已拉開、方向固定，箭仍在弦上")
	enemy._behaviour(.02, Vector3.FORWARD * 2, 2)
	_check(enemy._rstate == "aim", "鎖定後即使被逼近也照樣放箭（給玩家閃避的窗口）")
	enemy._behaviour(ai.lock_s, flat, 12)
	_check(shots.size() == 1 and enemy._rstate == "recover", "放弦只發射一支箭")
	enemy._behaviour(ai.recover_s + .02, flat, 12)
	_check(enemy._rstate == "move" and enemy._draw < 0 and shots.size() == 1, "收勢不會重複發射")
	_check(enemy._aim_cd >= ai.cd_min_s - .01, "收勢後至少等 %.1f 秒才再起手" % ai.cd_min_s)
	# 走位：太近後撤、太遠靠近、舒適距離橫移
	enemy._reposition(.02, Vector3.FORWARD * 3, 3, false)
	_check(enemy.velocity.dot(Vector3.FORWARD) < 0, "玩家靠近時拉開距離")
	enemy._reposition(.02, Vector3.FORWARD * 26, 26, false)
	_check(enemy.velocity.dot(Vector3.FORWARD) > 0, "超出射程時靠近")
	enemy._reposition(.02, Vector3.FORWARD * ai.pref_m, ai.pref_m, false)
	var v: Vector3 = enemy.velocity
	_check(absf(v.x) > absf(v.z), "在舒適距離繞著玩家橫移")
	world.child_entered_tree.disconnect(capture)
	for shot in shots:
		shot.queue_free()
	# 同時拉弓的上限
	var squad: Array = []
	for i in 3:
		var e = world.spawn_enemy("H02", Vector3(-10 + i, 0, 2), false)
		e.ai.attack_chance = 1.0
		squad.append(e)
	squad[0]._rstate = "aim"
	squad[1]._rstate = "aim"
	squad[2]._aim_cd = 0.0
	squad[2]._behaviour(.02, flat, 12)
	_check(squad[2]._rstate == "move", "已有 %d 名遠程在拉弓時，其他人先走位" % int(Data.cfg("ai_ranged_max_aiming")))
	for e in squad:
		e.queue_free()


func _check_cover_tactics(world, player) -> void:
	# 第一房的中央路障佔 x=28..30、z=-3..3。
	var original: Vector3 = player.global_position
	world.set_physics_process(false)
	player.set_physics_process(false)
	world.current = 0
	player.global_position = Vector3(33,.1,0)
	var archer = world.spawn_enemy("H02",Vector3(26,0,0),false)
	archer._aim_cd = 0
	archer.ai.attack_chance = 1.0
	await _frames(3)
	_check(not archer._clear_shot() and archer._rstate == "move" and archer.velocity.slide(Vector3.UP).length() > .1, "隔著路障先換位，不原地拉弓")
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
	var held: Array = Game.weapons.duplicate(true)
	Game.weapons = [null, null]  # 已持有的武器不會出現在悟道碑，先清空再看整個池
	for rarity in Data.rarity_order:
		allowed.append_array(Game._pool(rarity,"W",{})[0])
	Game.weapons = held
	allowed.sort()
	_check(allowed==["W001","W007","W301"],"此版本只開放太刀、弓、大劍")
	var old: Array = Game.weapons.duplicate(true)
	Game.weapons[0] = {"id":"W007","lv":1}
	Game.weapons[1] = {"id":"W301","lv":1}
	Game.active_weapon = 0
	Game.recompute()
	var bow = player.weapon_models[0]
	var greatsword = player.weapon_models[1]
	_check(bow.visible and not greatsword.visible, "同時只拿主武器，副武器收起")
	var events: Array = []
	bow.attack(.8,1,func(i): events.append("bow%d"%i))
	await _frames(8)
	_check(events.is_empty() and bow.arrow.visible,"蓄力尚未放箭")
	_check(bow.loader.visible and bow.loader.position.distance_to(bow.arrow.position)<.001,"搭箭時副手夾住箭尾")
	Game.recompute()
	_check(player.weapon_models[0] == bow,"刷新屬性保留進行中的動作")
	player.request_switch()
	await _frames(2)
	_check(Game.active_weapon == 0 and bow.visible, "出招途中按切換，等動作做完")
	await _frames(19)
	_check(bow.flex_mesh.get_blend_shape_value(0)>.95 and bow.arrow.visible and bow.loader.position.distance_to(bow.arrow.position)<.001,"滿弓時弓身變形且箭尾仍在指間")
	await _frames(28)
	_check(events.count("bow0")==1 and events.size()==1,"一箭只觸發一次")
	for i in 60:
		if Game.active_weapon == 1:
			break
		await get_tree().physics_frame
	_check(Game.active_weapon == 1 and greatsword.visible and not bow.visible, "動作結束後換成副武器")
	_check(player.swap_t > 0.0, "切換後有收出時間")
	var count: int = player.attack_count
	player._attack(0)
	_check(player.attack_count == count, "收起的主武器不能出招")
	player.cooldowns = [0.0, 0.0]
	player.set_physics_process(true)
	Input.action_press("attack_1")
	await _frames(2)
	_check(player.attack_count == count, "收出時間內按攻擊不出招")
	await _frames(int(Data.cfg("weapon_swap_s") * 60.0) + 2)
	Input.action_release("attack_1")
	_check(player.attack_count == count + 1, "收出時間過後副武器出招")
	await _frames(90)
	Game.weapons[1] = null
	Game.active_weapon = 0
	Game.recompute()
	player.request_switch(1)
	_check(player.switch_request == -9 and not Game.switch_weapon(1), "副武器格是空的不能切換")
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
	_check(e._flash_meshes[0].material_overlay == e._flash and e._flash.albedo_color.a > .5 and e._flash.albedo_color.g > .9, "受擊立即閃白")
	await _frames(3)
	var light: float = e._impact_pivot.position.dot(right)
	_check(e._flash.albedo_color.a > .3, "閃白後轉紅淡出")
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
