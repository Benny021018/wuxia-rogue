extends Node
## 兩人 ENet listen server。主機執行戰鬥，客機預測自己的輸入並以已確認序號校正。
signal closed
const PORT := 28570
const DISCOVERY := 28571
const PROTOCOL := "wuxia-lan/3"
const PLAYER := preload("res://scripts/player.gd")
const WORLD := preload("res://scripts/world.gd")
const BUILD := preload("res://scripts/game.gd")
var layer := CanvasLayer.new()
var panel := Control.new()
var backdrop: Control
var address := LineEdit.new()
var rooms_found := ItemList.new()
var browser := Control.new()
var room := Control.new()
var empty_rooms: Label
var last_seen := {}
var modes := OptionButton.new()
var heroes := OptionButton.new()
var status: Label
var ready_button: Button
var discover := PacketPeerUDP.new()
var beacon_time := 0.0
var remote_id := 0
var selection := ""
var guest_selection := ""
var prepared := false
var match_mode := ""
var world
var fighters: Array = []
var local_slot := 0
var lives := [0, 0]
var countdown := 0.0
var epoch := 0
var ended := false
var tick := 0
var ack := 0
var processed_action := 0
var sent_action := 0
var predicted_positions := {}
var mirrors := {}
var missiles := {}
var fields := {}
var rest_stop := false
var rest_panel := VBoxContainer.new()
var snapshot_time := 0.0
var pending_deaths := [false,false]
var hud
var remote_start := Vector3.ZERO
var remote_target := Vector3.ZERO
var remote_display := Vector3.ZERO
var remote_angle := 0.0
var remote_start_angle := 0.0
var remote_target_angle := 0.0
var blend_elapsed := 0.0
var blend_duration := 0.0
var guest_build
var continue_ready := [false,false]
var reward_choices := [[],[]]
var reward_buttons := VBoxContainer.new()
var waiting_rewards := false
var round_active := false
var match_menu = preload("res://scripts/ui/screens.gd").new()

func _ready() -> void:
	add_child(reward_buttons)
	add_child(rest_panel)
	reward_buttons.theme = UIKit.theme()
	rest_panel.theme = UIKit.theme()
	add_child(layer)
	layer.layer = 18
	layer.add_child(match_menu)
	match_menu.hide()
	match_menu.theme = UIKit.theme()
	match_menu.network_match = true
	match_menu.resume.connect(_close_match_menu)
	match_menu.to_menu.connect(leave)
	panel.theme = UIKit.theme()
	backdrop = UIKit.backdrop("res://assets/ui/greenwood_pass.webp")
	layer.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := UIKit.overlay(.65)
	backdrop.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -600
	panel.offset_top = -320
	panel.offset_right = 600
	panel.offset_bottom = 320
	var frame := TextureRect.new()
	frame.texture = preload("res://assets/ui/lan-room.svg")
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(frame)
	_room_control(UIKit.menu_lettering(preload("res://assets/ui/multiplayer-title.svg")),52,23,350,86)
	panel.add_child(browser)
	panel.add_child(room)
	browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	room.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	room.hide()
	_room_control(UIKit.label("區網房間列表",30),48,172,640,52,browser)
	_room_control(rooms_found,48,232,654,239,browser)
	rooms_found.fixed_icon_size = Vector2i(24,24)
	rooms_found.add_theme_font_size_override("font_size",24)
	rooms_found.item_selected.connect(func(i): address.text = rooms_found.get_item_metadata(i))
	rooms_found.item_activated.connect(func(i):
		address.text = rooms_found.get_item_metadata(i)
		join_room())
	empty_rooms = UIKit.label("尚未找到房間",23,UIKit.GREY,HORIZONTAL_ALIGNMENT_CENTER)
	empty_rooms.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room_control(empty_rooms,64,300,620,78,browser)
	_room_control(UIKit.button("建立房間",host),738,184,410,62,browser)
	address.placeholder_text = "房主區網 IP"
	_room_control(address,738,284,410,58,browser)
	_room_control(UIKit.button("加入房間",join_room),738,370,410,62,browser)
	_room_control(UIKit.label("房間玩法",26),48,174,500,52,room)
	_room_control(UIKit.label("選擇角色",26),738,174,410,52,room)
	modes.add_item("合作闖關")
	modes.add_item("擂台單挑・三命")
	_room_control(modes,48,245,654,64,room)
	modes.item_selected.connect(_mode_selected)
	for id in Data.char_order:
		heroes.add_item(Data.characters[id].name_zh)
	_room_control(heroes,738,245,410,64,room)
	ready_button = UIKit.button("準備",ready_up)
	_room_control(ready_button,738,370,410,62,room)
	status = UIKit.label("正在搜尋同一區網內的房間",22)
	_room_control(status,48,504,830,114)
	_room_control(UIKit.button("返回主選單",leave,24,220,62),926,532,220,62)
	discover.bind(DISCOVERY)
	multiplayer.peer_connected.connect(_connected)
	multiplayer.peer_disconnected.connect(_disconnected)
	multiplayer.server_disconnected.connect(_server_lost)
	multiplayer.connection_failed.connect(_failed)

func _room_control(control: Control, x: float, y: float, width: float, height: float, parent: Control = null) -> void:
	(parent if parent else panel).add_child(control)
	control.position = Vector2(x,y)
	control.size = Vector2(width,height)

func _mode_selected(index: int) -> void:
	if local_slot == 0 and not prepared:
		match_mode = "coop" if index == 0 else "duel"
		if remote_id:
			_room.rpc_id(remote_id,match_mode,PROTOCOL)

func _enter_room() -> void:
	browser.hide()
	room.show()
	modes.disabled = local_slot == 1 or prepared
	ready_button.disabled = remote_id == 0 or prepared

func host() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, 1, 3) != OK:
		status.text = "建立失敗，請確認連線埠可用"
		return
	multiplayer.multiplayer_peer = peer
	match_mode = "coop" if modes.selected == 0 else "duel"
	_enter_room()
	discover.close()
	discover.set_broadcast_enabled(true)
	status.text = "等待另一名玩家加入　" + str(Array(IP.get_local_addresses()).filter(func(ip): return "." in ip and ip != "127.0.0.1"))

func join_room() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	if not address.text.strip_edges().is_valid_ip_address():
		status.text = "請輸入房主區網 IP"
		return
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address.text.strip_edges(), PORT, 3) != OK:
		status.text = "無法連線"
		return
	local_slot = 1
	multiplayer.multiplayer_peer = peer
	status.text = "正在連線…"

func _connected(id: int) -> void:
	remote_id = id
	if multiplayer.is_server():
		_enter_room()
		_room.rpc_id(id, match_mode, PROTOCOL)
	status.text = "已連線，選擇角色後按準備"

@rpc("authority","reliable")
func _room(kind: String, protocol: String) -> void:
	if protocol != PROTOCOL:
		_finish("遊戲版本不相容")
		return
	match_mode = kind
	modes.select(0 if kind == "coop" else 1)
	_enter_room()

func ready_up() -> void:
	if remote_id == 0 or match_mode.is_empty() or prepared or ended:
		return
	selection = Data.char_order[heroes.selected]
	prepared = true
	modes.disabled = true
	heroes.disabled = true
	ready_button.disabled = true
	status.text = "已準備，等待對方"
	if local_slot == 1:
		_guest_ready.rpc_id(1, selection)
	else:
		_try_start()

@rpc("any_peer","reliable")
func _guest_ready(id: String) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == remote_id and world == null and Data.characters.has(id):
		modes.disabled = true
		guest_selection = id
		_try_start()

func _try_start() -> void:
	if prepared and guest_selection != "" and world == null:
		_begin.rpc(match_mode,selection,guest_selection)

@rpc("authority","call_local","reliable")
func _begin(kind: String, first: String, second: String) -> void:
	match_mode = kind
	panel.hide()
	backdrop.hide()
	world = WORLD.new()
	world.allow_drops = false
	add_child(world)
	var ids := [first,second]
	for i in 2:
		var build = Game if i == local_slot else BUILD.new()
		if build != Game:
			add_child(build)
		build.new_run(ids[i], "", kind == "duel")
		var p = PLAYER.new()
		p.build = build
		p.network_driven = i != local_slot
		p.input_enabled = false
		p.predicted = local_slot == 1
		world.add_child(p)
		fighters.append(p)
		p.set_process_unhandled_input(i == local_slot)
		p.cam.current = i == local_slot
		p.died.connect(_record_death.bind(i))
		build.leveled_up.connect(func(_level): p.level_up_heal())
		if i == 0 and local_slot == 0:
			p.skill_cue.connect(func(id,pos,span,finisher): _remote_cue.rpc_id(remote_id,epoch,id,pos,span,finisher))
	fighters[local_slot].cam.current = true
	world.player = fighters[0]
	guest_build = fighters[1].build
	if kind == "duel":
		_arena()
		Music.play("duel")
		for i in 2:
			fighters[i].opponent = fighters[1-i]
			if local_slot == 0:
				fighters[i].duel_hit.connect(_broadcast_hit.bind(i))
			lives[i] = int(CombatState.cfg("lan_lives"))
	else:
		world.build_map(0)
		Music.play(Data.map_order[0])
		fighters[1].position = fighters[0].position + Vector3.BACK
		fighters[1].yaw = fighters[0].yaw
		world.enemy_defeated.connect(guest_build.add_kill)
		if local_slot == 0:
			world.telegraph.connect(func(pos,r,seconds): _warning.rpc_id(remote_id,pos,r,seconds))
		world.zone_locked.connect(_lock)
		world.zone_cleared.connect(_clear)
		world.run_won.connect(func(): _end_match("合作通關"))
		world.map_entered.connect(_map_entered)
	world.set_physics_process(local_slot == 0 and kind == "coop")
	hud = preload("res://scripts/ui/hud.gd").new()
	hud.player = fighters[local_slot]
	hud.theme = UIKit.theme()
	layer.add_child(hud)
	layer.move_child(hud, 0)
	if kind == "duel":
		hud.set_opponent(fighters[1-local_slot])
	else:
		if local_slot == 0:
			world.enemies_changed.connect(hud.set_enemies)
		world.boss_appeared.connect(hud.set_boss)
	rest_panel.reparent(layer,false)
	rest_panel.position = Vector2(500,110)
	reward_buttons.reparent(layer,false)
	reward_buttons.position = Vector2(48,110)
	fighters[1-local_slot].set_physics_process(local_slot == 0)
	_round_reset()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _map_entered(_index: int) -> void:
	Music.play(Data.map_order[_index])
	var spawn: Vector3 = world.player.position
	for i in 2:
		fighters[i].position = spawn + Vector3.BACK * i
		fighters[i].yaw = -PI/2
		fighters[i].rotation.y = -PI/2
	blend_duration = 0.0
	predicted_positions.clear()

func _arena() -> void:
	world.map_id = "greenwood"
	world._apply_env()
	world.map_id = "duel"
	world.level_root = Node3D.new()
	world.add_child(world.level_root)
	var side := CombatState.cfg("lan_arena_half")
	world._static_box(Vector3(2*side,.5,2*side),Vector3.DOWN*.25,Color.SLATE_GRAY)
	for sign_value in [-1,1]:
		world._static_box(Vector3(.4,1.4,2*side),Vector3(sign_value*side,.7,0),Color.GRAY)
		world._static_box(Vector3(2*side,1.4,.4),Vector3(0,.7,sign_value*side),Color.GRAY)
		world._static_box(Vector3(.45,2.4,4),Vector3(sign_value*side*.6,1.2,0),Color.DARK_SLATE_GRAY)
	for i in range(-2,3):
		for along_x in [true,false]:
			var seam := FX.box(Vector3(2*side,.008,.025) if along_x else Vector3(.025,.008,2*side),Color("#444c53"))
			world.level_root.add_child(seam)
			seam.position = Vector3(0,.004,i*side/3) if along_x else Vector3(i*side/3,.004,0)
	var line := FX.box(Vector3(2*side,.012,.09),UIKit.TEAL)
	world.level_root.add_child(line)

func _round_reset() -> void:
	epoch += 1
	round_active = false
	countdown = CombatState.cfg("lan_round_delay")
	pending_deaths = [false,false]
	blend_duration = 0.0
	predicted_positions.clear()
	for i in 2:
		var p = fighters[i]
		p.runner = preload("res://scripts/move_runner.gd").new()
		p.runner.setup(p,p.build.char_id)
		p.hp = p.build.max_hp()
		p.cs.reset()
		p.invuln_t = 0
		p.shield = 0
		p.velocity = Vector3.ZERO
		p.net_axis = Vector2.ZERO
		p.dash_t = 0
		p.dash_cd = 0
		p.net_dash = false
		p.net_jump = false
		p.hit_guard = 0
		p.duel_poison_left = 0
		p.duel_poison = 0
		p.input_enabled = false
		if match_mode == "duel":
			p.position = Vector3(0,.15,(1 if i == 0 else -1)*CombatState.cfg("lan_spawn_gap")*.5)
			p.yaw = 0 if i == 0 else PI
		p.rotation.y = p.yaw
		p.body_yaw = p.yaw
	for n in world.get_children() + world.level_root.get_children():
		if n.get_script() in [preload("res://scripts/projectile.gd"),preload("res://scripts/hidden_weapon_field.gd")]:
			n.free()

func _record_death(slot: int) -> void:
	if round_active and local_slot == 0:
		pending_deaths[slot] = true

func _check_deaths() -> void:
	if ended or local_slot != 0 or not round_active:
		return
	pending_deaths = [false,false]
	if match_mode == "coop":
		if fighters[0].dead and fighters[1].dead:
			_end_match("合作闖關失敗")
		return
	for i in 2:
		if fighters[i].dead:
			lives[i] -= 1
	if lives == [0,0]:
		lives = [1,1]
	elif lives.min() == 0:
		_end_match("房主勝出" if lives[0] > 0 else "客方勝出")
		return
	_reset_event.rpc(lives)

@rpc("authority","call_local","reliable")
func _reset_event(remaining: Array) -> void:
	lives = remaining.duplicate()
	_round_reset()

func _lock(_stage: int, _title: String) -> void:
	var r: Dictionary = world.rooms[world.current]
	for p in fighters:
		if p.position.x < r.x0+1:
			p.position = Vector3(r.x0+2,.2,0)
	guest_build.stage = _stage

func _clear(stage: int) -> void:
	if local_slot != 0:
		return
	guest_build.on_zone_cleared()
	for i in 2:
		var p = fighters[i]
		if p.dead:
			p.hp = p.build.max_hp()
			p.cs.reset()
			p.position = world.player.position + Vector3.BACK
		p.net_axis = Vector2.ZERO
		var opts: Array = []
		if p.build.take_draw():
			opts = p.build.wheel_roll(p.build.wheel_spin())
		reward_choices[i] = opts
	rest_stop = String(Data.stage_row(stage).rest_stop) == "1"
	if rest_stop:
		guest_build.restock_merchant()
	_sync_build.rpc_id(remote_id,_progress(guest_build),rest_stop)
	continue_ready = [false,false]
	waiting_rewards = true
	world.set_physics_process(false)
	_reward_ui(reward_choices[0])
	_reward_ui.rpc_id(remote_id,reward_choices[1])

@rpc("authority","reliable")
func _reward_ui(options: Array) -> void:
	waiting_rewards = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	fighters[local_slot].input_enabled = false
	for c in reward_buttons.get_children():
		c.queue_free()
	for i in options.size():
		var opt: Dictionary = options[i]
		reward_buttons.add_child(UIKit.button(str(Game.describe(opt).get("title",opt.id)),_pick.bind(i)))
	_rest_menu()
	if options.is_empty():
		reward_buttons.add_child(UIKit.button("繼續闖關",_pick.bind(-1)))

func _pick(index: int) -> void:
	for c in rest_panel.get_children():
		rest_panel.remove_child(c)
		c.queue_free()
	if local_slot == 0:
		_choose(0,index)
	else:
		_guest_pick.rpc_id(1,index)
	for c in reward_buttons.get_children():
		c.queue_free()

@rpc("any_peer","reliable")
func _guest_pick(index: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == remote_id:
		_choose(1,index)

func _choose(slot: int,index: int) -> void:
	if not waiting_rewards or continue_ready[slot]:
		return
	var choices: Array = reward_choices[slot]
	if index >= 0 and index < choices.size():
		fighters[slot].build.choose(choices[index])
	elif not choices.is_empty():
		return
	continue_ready[slot] = true
	if slot == 1:
		_sync_build.rpc_id(remote_id,_progress(guest_build),rest_stop)
	if not choices.is_empty() and fighters[slot].build.take_draw():
		continue_ready[slot] = false
		var build = fighters[slot].build
		reward_choices[slot] = build.wheel_roll(build.wheel_spin())
		if slot == 0:
			_reward_ui.call_deferred(reward_choices[slot])
		else:
			_reward_ui.rpc_id(remote_id,reward_choices[slot])
		return
	if continue_ready == [true,true]:
		_continue.rpc()

@rpc("authority","call_local","reliable")
func _continue() -> void:
	waiting_rewards = false
	world.set_physics_process(local_slot == 0)
	_sync_local_controls()

func _process(delta: float) -> void:
	if ended:
		return
	if world == null:
		beacon_time -= delta
		if local_slot == 0 and not match_mode.is_empty() and remote_id == 0 and beacon_time <= 0:
			discover.set_dest_address("255.255.255.255", DISCOVERY)
			discover.put_packet((PROTOCOL + "|" + match_mode).to_utf8_buffer())
			beacon_time = 1
		elif discover.is_bound() and discover.get_available_packet_count() > 0:
			var parts := discover.get_packet().get_string_from_utf8().split("|")
			var ip := discover.get_packet_ip()
			if parts.size() == 2 and parts[0] == PROTOCOL and parts[1] in ["coop","duel"]:
				_record_room(ip,parts[1])
		for i in range(rooms_found.item_count-1,-1,-1):
			var ip: String = rooms_found.get_item_metadata(i)
			if Time.get_ticks_msec()-int(last_seen[ip]) > 4000:
				last_seen.erase(ip)
				rooms_found.remove_item(i)
		empty_rooms.visible = rooms_found.item_count == 0
		return
	var p = fighters[local_slot]
	var other = fighters[1-local_slot]
	blend_elapsed += delta
	if blend_duration > 0.0:
		var progress := Engine.get_physics_interpolation_fraction() if local_slot == 0 else clampf(blend_elapsed / blend_duration, 0.0, 1.0)
		remote_display = remote_start.lerp(remote_target, progress)
		remote_angle = lerp_angle(remote_start_angle, remote_target_angle, progress)
		other.model.global_position = remote_display
		other.model.rotation.y = remote_angle
	if match_mode == "duel":
		hud.set_zone("問劍坪　命數 %d：%d" % [lives[local_slot], lives[1-local_slot]])
	else:
		hud.set_zone("%s・第 %d 區" % [Data.maps[world.map_id].name_zh, maxi(1,world.current+1)])
	if match_mode == "coop" and p.dead and not other.dead:
		other.cam.current = true
		if local_slot == 1:
			other.rotation.y = other.body_yaw
	else:
		p.cam.current = true
	if countdown > 0:
		hud.set_hint("開戰倒數 %d" % ceili(countdown))
	elif p.dead:
		hud.set_hint("觀戰中")
	else:
		hud.set_hint("")

# 碰撞與命中使用模擬位置，模型在畫面更新時移向最新樣本。
func _remote_sample(pos: Vector3, angle: float, interval: float) -> void:
	if blend_duration <= 0.0 or remote_target.distance_to(pos) > CombatState.cfg("lan_snap_distance_m"):
		remote_display = pos
		remote_angle = angle
	elif local_slot == 0:
		remote_display = remote_target
		remote_angle = remote_target_angle
	remote_start = remote_display
	remote_start_angle = remote_angle
	remote_target = pos
	remote_target_angle = angle
	blend_elapsed = 0.0
	blend_duration = interval

func _record_room(ip: String, kind: String) -> void:
	var caption := "%s    ·    %s" % ["合作闖關" if kind == "coop" else "擂台單挑",ip]
	if last_seen.has(ip):
		for i in rooms_found.item_count:
			if rooms_found.get_item_metadata(i) == ip:
				rooms_found.set_item_text(i,caption)
				break
	else:
		rooms_found.add_item(caption)
		rooms_found.set_item_metadata(rooms_found.item_count-1,ip)
	last_seen[ip] = Time.get_ticks_msec()
	empty_rooms.hide()

func _physics_process(delta: float) -> void:
	if world == null or ended:
		return
	if local_slot == 0 and pending_deaths.has(true):
		_check_deaths()
		if ended:
			return
	if countdown > 0:
		countdown = maxf(countdown-delta,0)
		if countdown == 0:
			round_active = true
			_sync_local_controls()
	if local_slot == 0:
		_remote_sample(fighters[1].position, fighters[1].body_yaw, delta)
		if match_mode == "coop":
			world.player = fighters[0]
			if fighters[0].dead or (not fighters[1].dead and fighters[1].position.x > fighters[0].position.x):
				world.player = fighters[1]
			for e in get_tree().get_nodes_in_group("enemies"):
				var nearest = fighters[1] if fighters[0].dead else fighters[0]
				if not fighters[1].dead and e.position.distance_squared_to(fighters[1].position) < e.position.distance_squared_to(nearest.position):
					nearest = fighters[1]
				e.player = nearest
		snapshot_time -= delta
		if snapshot_time <= 0 and remote_id:
			snapshot_time = 1.0 / CombatState.cfg("lan_snapshot_hz")
			_send_snapshot()
	elif round_active and not waiting_rewards:
		tick += 1
		var p = fighters[1]
		predicted_positions[tick] = p.position
		if predicted_positions.size() > 180:
			predicted_positions.erase(predicted_positions.keys()[0])
		var axis := Vector2.ZERO if match_menu.visible else Input.get_vector("move_left","move_right","move_forward","move_back")
		_motion.rpc_id(1,epoch,tick,axis,p.yaw,p.pitch)

func _input(event: InputEvent) -> void:
	if world == null or ended:
		return
	if event.is_action_pressed("pause"):
		if match_menu.visible:
			_close_match_menu()
		else:
			layer.move_child(match_menu,-1)
			match_menu.show_pause()
			_sync_local_controls()
		get_viewport().set_input_as_handled()
		return
	if match_menu.visible or local_slot != 1 or not round_active or waiting_rewards:
		return
	for action in PLAYER.ACTIONS + ["dash","jump"]:
		if event.is_action_pressed(action):
			sent_action += 1
			_action.rpc_id(1,epoch,sent_action,action,fighters[1].yaw,fighters[1].pitch)

func _close_match_menu() -> void:
	match_menu.hide_all()
	_sync_local_controls()

func _sync_local_controls() -> void:
	fighters[local_slot].input_enabled = round_active and not waiting_rewards and not match_menu.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if waiting_rewards or match_menu.visible else Input.MOUSE_MODE_CAPTURED

func _guest_input(round_id: int) -> bool:
	return world != null and multiplayer.is_server() and multiplayer.get_remote_sender_id() == remote_id and round_id == epoch and round_active and not ended and not waiting_rewards and not fighters[1].dead

@rpc("any_peer","call_remote","unreliable_ordered",1)
func _motion(round_id: int, serial: int, axis: Vector2, yaw: float, pitch: float) -> void:
	if not _guest_input(round_id) or serial <= ack or not axis.is_finite() or not is_finite(yaw) or not is_finite(pitch):
		return
	ack = serial
	var p = fighters[1]
	p.net_axis = axis.limit_length()
	p.yaw = yaw
	p.rotation.y = yaw
	p.pitch = clampf(pitch,-1.2,.7)
	p.pivot.rotation.x = p.pitch

@rpc("any_peer","call_remote","reliable",2)
func _action(round_id: int, number: int, action: String, yaw: float, pitch: float) -> void:
	if not _guest_input(round_id) or not is_finite(yaw) or not is_finite(pitch):
		return
	processed_action = number
	var p = fighters[1]
	p.yaw = yaw
	p.rotation.y = yaw
	p.pivot.rotation.x = clampf(pitch,-1.2,.7)
	if action == "dash":
		p.net_dash = true
	elif action == "jump":
		p.net_jump = true
	elif action in PLAYER.ACTIONS:
		p.use(action)

func _broadcast_hit(damage: float, crit: bool, weight: float, slot: int) -> void:
	_duel_impact.rpc(epoch, slot, damage, crit, weight, fighters[slot].dead)


@rpc("authority","call_local","reliable")
func _duel_impact(round_id: int, slot: int, damage: float, crit: bool, weight: float, killed: bool) -> void:
	if ended or epoch != round_id:
		return
	var target = fighters[slot]
	var center: Vector3 = target.hit_center() + target.model.global_position - target.global_position
	var toward: Vector3 = center.direction_to(fighters[1-slot].hit_center())
	var contact := center + toward * float(target.hit_radius)
	target.model.flash_hit()
	FX.play(world, contact, &"crit-hit" if crit else &"hit-spark", 1.55 if crit else 0.76, 0.24 if crit else 0.14)
	FX.burst(world, contact, (toward + Vector3.UP).normalized(), UIKit.BONE, int(Data.feel.particles_crit if crit else Data.feel.particles_hit))
	if Settings.on("damage_numbers") and damage > 0:
		FX.damage_number(world, center + Vector3.UP * 0.6, ceili(damage), crit, UIKit.EMBER if crit else UIKit.BONE)
	Sfx.hit(weight, crit, killed, damage == 0)
	Feel.impact(weight, crit, killed)
	if slot == local_slot and damage > 0:
		Sfx.play("player_hurt")
		Feel.player_hurt.emit(clampf(damage / target.build.max_hp() * 5.0, 0.3, 1.0))


func _send_snapshot() -> void:
	var actors := []
	for p in fighters:
		actors.append({
			"pos": p.position, "velocity": p.velocity, "yaw": p.body_yaw,
			"hp": p.hp, "shield": p.shield, "state": p.cs.base, "state_left": p.cs.t,
			"rage": p.runner.rage, "clip": p.model.current, "invincible": p.cs.inv_t, "armor": p.cs.armor_t, "invuln": p.invuln_t, "demon": p.demon_t,
			"cooldowns": p.runner.cds, "move_id": p.runner.move.get("move_id",""), "time": p.runner.t,
			"fired": p.runner.fired, "combo": p.runner.combo, "speed": p.runner.speed,
			"dir": p.runner.dir, "pitch": p.model.rotation.x, "clip_time": p.model.anim.current_animation_position if p.model.anim.is_playing() else 0.0,
			"clip_speed": p.model.anim.speed_scale,
		})
	var shots := {}
	for n in world.get_children():
		if n.get_script() == preload("res://scripts/projectile.gd") and n.caster != fighters[1]:
			shots[n.get_instance_id()] = [n.position,n.direction,n.from_player]
	var areas := {}
	for n in get_tree().get_nodes_in_group("combat_fields"):
		if n.get_parent() == world:
			areas[n.get_instance_id()] = [n.position,n.radius,false]
		elif n.get_script() == preload("res://scripts/hidden_weapon_field.gd") and n.player != fighters[1]:
			areas[n.get_instance_id()] = [n.position,n.radius,n.trap]
	var mobs := {}
	for e in get_tree().get_nodes_in_group("enemies"):
		mobs[e.get_instance_id()] = [e.eid,e.position,e.rotation.y,e.hp,e._pose.rotation.x,e._anim.current_animation if e._anim else ""]
	_snapshot.rpc_id(remote_id,epoch,ack,processed_action,actors,mobs,shots,areas,world.map_index,world.current,world.state)

@rpc("authority","call_remote","unreliable_ordered",1)
func _snapshot(round_id: int, serial: int, confirmed_action: int, actors: Array, mobs: Dictionary, shots: Dictionary, areas: Dictionary, map: int, room: int, state: String) -> void:
	if ended or world == null or round_id != epoch:
		return
	if match_mode == "coop":
		if world.map_index != map:
			mirrors.clear()
			missiles.clear()
			fields.clear()
			world.build_map(map)
		for i in world.rooms.size():
			var r: Dictionary = world.rooms[i]
			if r.gate_in.visible != (i <= room):
				world._set_gate(r.gate_in, i <= room)
			var sealed: bool = i > room or (i == room and state == "fighting")
			if r.gate_out.visible != sealed:
				world._set_gate(r.gate_out, sealed)
		Game.stage = maxi(1,map*5+room+1)
		world.current = room
		hud.set_enemies(mobs.size())
	for i in 2:
		var p = fighters[i]
		var actor: Dictionary = actors[i]
		if i == 0:
			p.position = actor.pos
			_remote_sample(actor.pos, actor.yaw, 1.0 / CombatState.cfg("lan_snapshot_hz"))
			p.body_yaw = actor.yaw
			p.model.rotation.x = actor.pitch
			var clip := String(actor.clip)
			if clip.ends_with("@hold"):
				p.model.hold(clip.trim_suffix("@hold"), 0.83 if actor.state == CombatState.S.DOWN else 0.0)
			elif p.model.has(clip):
				p.model.play(clip,actor.clip_speed)
				if absf(p.model.anim.current_animation_position - float(actor.clip_time)) > .12:
					p.model.anim.seek(actor.clip_time,true)
		elif predicted_positions.has(serial):
			var error: Vector3 = actor.pos - predicted_positions[serial]
			if error.length() > .08:
				p.position += error
				for seq in predicted_positions.keys():
					if seq > serial:
						predicted_positions[seq] += error
			for seq in predicted_positions.keys():
				if seq <= serial:
					predicted_positions.erase(seq)
		elif serial == 0 or p.position.distance_to(actor.pos) > 2:
			p.position = actor.pos
		if i == local_slot and confirmed_action == sent_action:
			p.runner.cds = actor.cooldowns.duplicate()
			if p.runner.move.get("move_id","") != actor.move_id:
				if actor.move_id == "":
					p.runner.interrupt()
				else:
					var mv: Dictionary = Data.moves[actor.move_id]
					p.runner.move = mv
					p.runner.t = actor.time
					p.runner.fired = actor.fired
					p.runner.speed = actor.speed
					p.runner.dir = actor.dir
					var source: Animation = p.model.anim.get_animation(p.model.clip(mv.anim))
					var rate := (source.length-float(mv.anim_from_s))/float(mv.duration_s)
					p.model.play(mv.anim,rate*p.runner.speed,float(mv.anim_from_s)+rate*p.runner.t,0,true)
			p.runner.combo = actor.combo
		p.hp = actor.hp
		p.shield = actor.shield
		p.cs.base = actor.state
		p.cs.t = actor.state_left
		p.cs.inv_t = actor.invincible
		p.cs.armor_t = actor.armor
		p.invuln_t = actor.invuln
		p.demon_t = actor.demon
		p.model.set_defense(p.cs.state() == CombatState.S.ARMOR, p.damage_immune())
		p.runner.rage = actor.rage
		if p.cs.base == CombatState.S.AIR and i == 0:
			p.model.rotation.x = CombatState.airborne_pitch()
		if i == local_slot and p.cs.base == CombatState.S.AIR:
			p.velocity.y = actor.velocity.y
	for id in fields.keys():
		if not areas.has(id):
			fields[id].queue_free()
			fields.erase(id)
	for id in areas:
		if not fields.has(id):
			var area: Array = areas[id]
			var ring := FX.cylinder(area[1],.06,Color("#a074c66a") if area[2] else Color("#87bc656a"),.45)
			world.level_root.add_child(ring)
			ring.position = area[0]
			fields[id] = ring
			if not area[2]:
				FX.play(ring,ring.global_position+Vector3.UP*.55,&"poison-cloud",float(area[1])*1.5,1.2)
	for id in missiles.keys():
		if not shots.has(id):
			missiles[id].queue_free()
			missiles.erase(id)
	for id in shots:
		var shot: Array = shots[id]
		if not missiles.has(id):
			var beam := FX.box(Vector3(.07,.07,.6),UIKit.VIOLET if shot[2] else UIKit.EMBER,1.8)
			world.level_root.add_child(beam)
			missiles[id] = beam
		missiles[id].position = shot[0]
		var direction: Vector3 = shot[1]
		if absf(direction.y) < .99:
			missiles[id].basis = Basis.looking_at(direction)
	for id in mirrors.keys():
		if not mobs.has(id):
			mirrors[id].queue_free()
			mirrors.erase(id)
	for id in mobs:
		var a: Array = mobs[id]
		var e = mirrors.get(id)
		if e == null:
			e = world.spawn_enemy(a[0],a[1],false)
			e.set_physics_process(false)
			mirrors[id] = e
		e.position = a[1]
		e.rotation.y = a[2]
		e.hp = a[3]
		e._pose.rotation.x = a[4]
		if e._anim and a[5] != "" and e._anim.current_animation != a[5]:
			e._anim.play(a[5])

@rpc("authority","reliable")
func _warning(pos: Vector3, radius: float, duration: float) -> void:
	if world != null and not ended:
		FX.warn_circle(world,pos,radius,duration)

func _end_match(message: String) -> void:
	if not ended and multiplayer.is_server():
		_finish.rpc(message)

@rpc("authority","call_local","reliable")
func _finish(message: String) -> void:
	ended = true
	if hud:
		hud.hide()
	match_menu.hide_all()
	if world:
		world.process_mode = Node.PROCESS_MODE_DISABLED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.show()
	backdrop.show()
	for c in panel.get_children():
		c.hide()
	panel.get_child(0).show()
	status.show()
	status.text = message
	panel.get_child(-1).show()
	if reward_buttons.is_inside_tree():
		reward_buttons.hide()
		rest_panel.hide()

func _disconnected(_id: int) -> void:
	remote_id = 0
	if not ended and is_inside_tree():
		_finish("對方已離開房間")

func _server_lost() -> void:
	_disconnected(1)

func _failed() -> void:
	_finish("連線失敗，請確認 IP 與房主狀態")

func leave() -> void:
	discover.close()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	closed.emit()


@rpc("authority","unreliable", "call_remote", 2)
func _remote_cue(round_id: int, id: String, pos: Vector3, span: float, finisher: bool) -> void:
	if world == null or round_id != epoch or ended:
		return
	var m: Dictionary = Data.moves[id]
	FX.play(world,pos,&"ground-slam" if finisher else StringName(m.fx_clip),span,.24,Color(m.fx_tint))
	Sfx.play("aoe_boom" if finisher else String(m.strike_sfx),pos)

const PROGRESS_FIELDS := ["stage","level","realm","gold","zhenqi","acu_open","acu_fails","martial","martial_order","weapons","merchant_stock","kills"]
func _progress(build) -> Dictionary:
	var values := {}
	for key in PROGRESS_FIELDS:
		values[key] = build.get(key)
	return values

@rpc("authority","reliable")
func _sync_build(values: Dictionary, has_shop: bool) -> void:
	for key in PROGRESS_FIELDS:
		Game.set(key,values[key])
	Game.recompute()
	rest_stop = has_shop
	if waiting_rewards and rest_panel.get_child_count() > 0:
		_rest_menu()

func _rest_menu() -> void:
	for c in rest_panel.get_children():
		rest_panel.remove_child(c)
		c.queue_free()
	var meridians := OptionButton.new()
	for mid in Data.meridian_order:
		meridians.add_item(str(Data.meridians[mid].name_zh))
	rest_panel.add_child(meridians)
	rest_panel.add_child(UIKit.button("衝穴　真氣 %d／%d" % [Game.zhenqi,Game.break_cost()],func(): _purchase("break",meridians.selected)))
	if rest_stop:
		rest_panel.add_child(UIKit.button("淬煉　%d 銀兩" % Game.upgrade_cost(0),_purchase.bind("forge",0)))
		for i in Game.merchant_stock.size():
			var item: Dictionary = Game.merchant_stock[i]
			if not item.sold:
				rest_panel.add_child(UIKit.button("%s　%d 銀兩" % [Data.martial[item.id].name_zh,Game.martial_price(item.id)],_purchase.bind("buy",i)))

func _purchase(op: String, index: int) -> void:
	if local_slot == 0:
		_transact(0,op,index)
	else:
		_guest_purchase.rpc_id(1,op,index)

@rpc("any_peer","reliable")
func _guest_purchase(op: String, index: int) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == remote_id:
		_transact(1,op,index)

func _transact(slot: int, op: String, index: int) -> void:
	if not waiting_rewards or continue_ready[slot]:
		return
	var build = fighters[slot].build
	if op == "break" and index >= 0 and index < Data.meridian_order.size():
		build.try_break(Data.meridian_order[index])
	elif rest_stop and op == "forge":
		build.upgrade_weapon(0)
	elif rest_stop and op == "buy" and index >= 0 and index < build.merchant_stock.size():
		build.buy_martial(index)
	if slot == 0:
		_rest_menu()
	else:
		_sync_build.rpc_id(remote_id,_progress(build),rest_stop)
