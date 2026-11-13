extends SceneTree
## 使用 --script tests/lan_integration.gd -- host|guest duel|coop，各開一個程序。
var frames := 0
var session
var attempts := 0
var checkpoint := 0
var maps_seen := 0
var saw_duel_impact := false
var saw_armor := false
var saw_invincible := false
var checked_motion := false
var initial_remote := Vector3.ZERO
var motion_frames := 0
var saw_midpoint := false
var checked_menu := false
var guest := false
var coop := false

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	guest = args[0] == "guest"
	coop = args[1] == "coop"
	var main = load("res://scripts/main.gd").new()
	root.add_child(main)
	main._open_lan()
	session = main.get_node("LanSession")
	if guest:
		session.address.text = "127.0.0.1"
		session.join_room()
	else:
		session.host()
		session.modes.select(0 if coop else 1)
		session._mode_selected(session.modes.selected)

func _process(_delta: float) -> bool:
	if session != null and session.round_active and not checked_motion:
		var distance: float = session.remote_start.distance_to(session.remote_target)
		if distance > 0.001:
			var rendered: Vector3 = session.fighters[1-session.local_slot].model.global_position
			if rendered.distance_to(session.remote_start) < distance and rendered.distance_to(session.remote_target) < distance:
				saw_midpoint = true
	return false

func _physics_process(_delta: float) -> bool:
	frames += 1
	if frames > 3600:
		push_error("局域網整合測試逾時，檢查點 %d" % checkpoint)
		quit(1)
		return false
	if session == null:
		return false
	if session.remote_id and not session.prepared and session.match_mode != "":
		if session.browser.is_visible_in_tree() or not session.heroes.is_visible_in_tree():
			push_error("進房後應可選角")
			quit(1)
			return false
		session.heroes.select(1 if guest else 0)
		session.ready_up()
	if session.world == null:
		return false
	if coop:
		maps_seen = maxi(maps_seen,session.world.map_index+1)
	if not coop:
		for p in session.fighters:
			saw_duel_impact = saw_duel_impact or p.model.flash_left > 0
			saw_armor = saw_armor or p.model.armored
			saw_invincible = saw_invincible or p.model.invincible
	if session.ended:
		if not coop and not (saw_duel_impact and saw_armor and saw_invincible):
			push_error("未顯示完整對戰回饋：受擊 %s、霸體 %s、無敵 %s" % [saw_duel_impact, saw_armor, saw_invincible])
			quit(1)
			return false
		var expected := "合作闖關失敗" if coop else "客方勝出"
		if not checked_motion or expected != session.status.text or checkpoint == 0 or (coop and maps_seen < 4):
			push_error("局域網結算錯誤：" + session.status.text)
			quit(1)
			return false
		else:
			print("LAN_PASS ",OS.get_cmdline_user_args())
		quit()
		return false
	if not session.round_active:
		return false
	if not checked_motion:
		var remote = session.fighters[1-session.local_slot]
		if motion_frames == 0:
			initial_remote = remote.position
			if not coop and not guest:
				session.fighters[0].cs.give_armor(0.5)
				session.fighters[1].cs.give_invincible(0.5)
			if session.hud.player != session.fighters[session.local_slot] or (not coop and session.hud.hp_bar.max_value != 10000):
				push_error("多人戰鬥介面或氣血上限錯誤")
				quit(1)
				return false
		motion_frames += 1
		if motion_frames < 45:
			Input.action_press("move_right")
		else:
			Input.action_release("move_right")
		if motion_frames >= 45 and saw_midpoint and remote.position.distance_to(initial_remote) > 0.5:
			checked_motion = true
		else:
			return false
	if not checked_menu:
		var esc := InputEventAction.new()
		esc.action = "pause"
		esc.pressed = true
		session._input(esc)
		var buttons = session.match_menu.find_children("*","Button",true,false)
		var guides = buttons.filter(func(b): return b.text == "操作說明")
		if guides.size() != 1 or session.fighters[session.local_slot].input_enabled or paused:
			push_error("多人對局選單狀態錯誤")
			quit(1)
			return false
		guides[0].pressed.emit()
		session._input(esc)
		if session.match_menu.visible or not session.fighters[session.local_slot].input_enabled:
			push_error("操作說明無法返回對局")
			quit(1)
			return false
		checked_menu = true
	if guest:
		if checkpoint == 0 or (not coop and frames % 15 == 0):
			var event := InputEventAction.new()
			event.action = "attack"
			event.pressed = true
			Input.parse_input_event(event)
			var release := event.duplicate() as InputEventAction
			release.pressed = false
			Input.parse_input_event(release)
			checkpoint = 1
		if coop and session.waiting_rewards and not session.reward_choices.is_empty() and checkpoint >= 1 and session.reward_buttons.get_child_count() > 0:
			session.reward_buttons.get_child(0).pressed.emit()
			checkpoint = 2
		return false
	if checkpoint == 0:
		if session.fighters[1].attack_count == 0:
			return false
		checkpoint = 1
	if coop:
		if checkpoint == 1:
			session.world._lock(0)
			session.world.spawn_queue.clear()
			var enemy = session.world.spawn_enemy("H01",session.fighters[0].position,false)
			session.fighters[1].deal(enemy,100000,false)
			checkpoint = 2
		elif checkpoint >= 2 and session.waiting_rewards and not session.continue_ready[0] and session.reward_buttons.get_child_count() > 0:
			if session.guest_build.kills < 1 or session.guest_build.gold <= 0:
				push_error("客方未取得合作擊殺獎勵")
				quit(1)
				return false
			session.reward_buttons.get_child(0).pressed.emit()
			checkpoint = 3
		elif checkpoint == 3 and not session.waiting_rewards and frames % 15 == 0:
			if session.world.map_index < 3:
				session.world.build_map(session.world.map_index+1)
			else:
				for p in session.fighters:
					p.take_damage(100000)
	else:
		# 只安排一擊可殺的測試站位；扣命必須由客方經網路送達的普攻觸發。
		if session.fighters[0].hp > 1:
			session.fighters[0].hp = 1
			session.fighters[0].position = session.fighters[1].position + session.fighters[1].aim_flat()

	return false

