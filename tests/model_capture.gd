extends Node
## 角色模型近照：檢查兵器握法與各招式的姿勢。
## xvfb-run godot --path . --rendering-driver opengl3 res://tests/ModelCapture.tscn -- <輸出資料夾> [char_id]
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
	var shots: Array = [["Sword_Idle", 0.5]]
	for mid in Data.moves:
		var mv: Dictionary = Data.moves[mid]
		if mv.char_id != cid or mv.hits.is_empty():
			continue
		var a: Animation = m.anim.get_animation(m.clip(mv.anim))
		var k: float = (a.length - float(mv.anim_from_s)) / float(mv.duration_s)
		shots.append([mv.anim, float(mv.anim_from_s) + float(mv.hits[0].time_s) * k, mv.name_zh, mid])
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
