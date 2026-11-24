extends Node
## 角色模型近照：檢查兵器握法與各招式的姿勢。
## xvfb-run godot --path . --rendering-driver opengl3 res://tests/ModelCapture.tscn -- <輸出資料夾> [char_id] [trail]
## 第三個參數給 trail：實際播放每一招並畫刀光，在每一下判定瞬間截圖（請加 --fixed-fps 60）
func _ready():
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/mc"
	var cid: String = args[1] if args.size() > 1 else "nangong"
	var root := get_tree().root
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#2a2e33")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 40, 0)
	root.add_child(sun)
	var m = preload("res://scripts/fighter_model.gd").new()
	root.add_child(m)
	m.setup(cid, String(Data.characters[cid].weapon_id))
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.fov = 40
	cam.current = true
	if args.size() > 2 and args[2] == "trail":
		await _trail_shots(m, cam, cid, out)
		get_tree().quit()
		return
	var shots: Array = [[m.idle, 0.5]]
	for mid in Data.moves:
		var mv: Dictionary = Data.moves[mid]
		if mv.char_id != cid:
			continue
		var a: Animation = m.anim.get_animation(m.clip(mv.anim))
		var k: float = (a.length - float(mv.anim_from_s)) / float(mv.duration_s)
		shots.append([mv.anim, float(mv.anim_from_s) + (float(mv.duration_s) * .5 if mv.hits.is_empty() else float(mv.hits[0].time_s)) * k, mv.name_zh, mid])
	var i := 0
	for s in shots:
		m.hold(s[0], s[1])
		for view in [["side", Vector3(4.2, 1.2, 0.0)], ["front", Vector3(0.0, 1.2, -4.2)]]:
			cam.position = view[1]
			cam.look_at(Vector3(0, 1.0, 0))
			for f in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%02d_%s_%s.png" % [out, i, s[3] if s.size() > 3 else "idle", view[0]])
		i += 1
	print("saved ", i)
	get_tree().quit()


## 依 move_runner 的規則播放招式並畫刀光；每一下判定時從斜後方截一張。
func _trail_shots(m, cam: Camera3D, cid: String, out: String) -> void:
	cam.position = Vector3(2.6, 2.0, 3.2)
	cam.look_at(Vector3(0, 1.0, 0))
	var n := 0
	for mid in Data.moves:
		var mv: Dictionary = Data.moves[mid]
		if mv.char_id != cid or mv.hits.is_empty() or not m.has(mv.anim):
			continue
		var melee: Array = mv.hits.filter(func(h): return String(h.shape) != "proj")
		if melee.is_empty():
			continue
		m.play(m.idle, 1.0, 0.0, 0.0, true)
		for f in 10:
			await get_tree().process_frame
		var a: Animation = m.anim.get_animation(m.clip(mv.anim))
		var aspeed := clampf((a.length - float(mv.anim_from_s)) / float(mv.duration_s), 0.4, 4.0)
		m.play(mv.anim, aspeed, float(mv.anim_from_s), 0.06, true)
		var first := maxf(0.0, float(melee[0].time_s) - float(Data.feel.blade_trail_lead_s))
		var last := float(melee[melee.size() - 1].time_s) + float(Data.feel.blade_trail_tail_s)
		m.swing_trail(first, last - first, Color(mv.fx_tint))
		var t := 0.0
		var k := 0
		while t < float(mv.duration_s) and k < melee.size():
			await get_tree().process_frame
			t += 1.0 / 60.0
			if t >= float(melee[k].time_s):
				await RenderingServer.frame_post_draw
				root_shot("%s/trail_%s_%d.png" % [out, mid, k + 1])
				k += 1
				n += 1
	print("trail shots ", n)


func root_shot(path: String) -> void:
	get_tree().root.get_texture().get_image().save_png(path)
