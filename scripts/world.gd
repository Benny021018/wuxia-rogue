extends Node3D
## 世界：依 data/zones.json 搭出灰盒地圖（與「地圖區域設計參考」畫布同一份配置），
## 並管理區域流程：鎖陣 → 分波出怪 → 破陣 → 悟道碑 → 下一區 → 換圖

signal zone_locked(stage: int, title: String)
signal zone_cleared(stage: int)
signal boss_appeared(enemy: Node)
signal map_entered(map_index: int)
signal run_won
signal enemies_changed(count: int)

const ENEMY := preload("res://scripts/enemy.gd")
const HAZARD := preload("res://scripts/hazard.gd")
const GATE_MODEL := preload("res://assets/models/greenwood/Gate.glb")
const PALISADE_MODEL := preload("res://assets/models/greenwood/palisade.glb")
const PLATFORM_MODEL := preload("res://assets/models/greenwood/platform.glb")
const CAMP_ART := {
	"拒馬":[PALISADE_MODEL,Vector3(6,3,2)], "":[preload("res://assets/models/greenwood/cover.glb"),Vector3(6,3,1.5)],
	"板車":[preload("res://assets/models/greenwood/cart.glb"),Vector3(3,1.2,2)],
	"貨箱":[preload("res://assets/models/greenwood/crate.glb"),Vector3(2,1.2,2)],
	"箭樓":[PLATFORM_MODEL,Vector3(7,1,7)], "擂台":[preload("res://assets/models/greenwood/ring.glb"),Vector3(4,1,4)],
	"交椅":[preload("res://assets/models/greenwood/ring.glb"),Vector3(4,1,4)],
	"二樓迴廊":[preload("res://assets/models/greenwood/gallery.glb"),Vector3(6,1,2)],
	"石階（高台）":[preload("res://assets/models/greenwood/stairs.glb"),Vector3(3,1,4)]
}
const CAMP_CHAIR := preload("res://assets/models/greenwood/throne.glb")
const CAMP_BRAZIER := preload("res://assets/models/greenwood/brazier.glb")
const CAMP_STELE := preload("res://assets/models/greenwood/shrine.glb")
const SMITH_PROP := preload("res://assets/models/npc/Smith.glb")         # tools/build_rest_stops.py
const MERCHANT_PROP := preload("res://assets/models/npc/Merchant.glb")
const STALL_SIZE := Vector3(3.2, 2.6, 2.2)
const DROP_MODELS := {"W001": preload("res://assets/models/weapons/Tachi.glb"),
	"W007": preload("res://assets/models/weapons/W007.glb"), "W301": preload("res://assets/models/weapons/W301.glb")}
const CORRIDOR := 14.0
const WALL_H := 4.0
const SPAWN_RATE := 0.12
const THEMES := {
	"greenwood": {"floor": Color(0.36, 0.3, 0.24), "wall": Color(0.45, 0.32, 0.22), "fog": Color(0.5, 0.38, 0.28), "ambient": Color(0.75, 0.62, 0.5), "sky": Color(0.25, 0.14, 0.1)},
	"darkmoon": {"floor": Color(0.2, 0.26, 0.22), "wall": Color(0.25, 0.35, 0.22), "fog": Color(0.22, 0.3, 0.32), "ambient": Color(0.5, 0.6, 0.65), "sky": Color(0.04, 0.06, 0.09)},
	"corpse_sect": {"floor": Color(0.3, 0.31, 0.28), "wall": Color(0.4, 0.4, 0.36), "fog": Color(0.35, 0.42, 0.36), "ambient": Color(0.55, 0.62, 0.58), "sky": Color(0.06, 0.09, 0.08)},
	"heavenly_demon": {"floor": Color(0.18, 0.12, 0.12), "wall": Color(0.3, 0.12, 0.12), "fog": Color(0.35, 0.08, 0.08), "ambient": Color(0.65, 0.42, 0.42), "sky": Color(0.08, 0.02, 0.02)},
}

var player
var map_index := 0
var map_id := "greenwood"
var level_root: Node3D
var env: WorldEnvironment
var rooms: Array = []          # 每個區域的資料
var current := -1              # 目前所在 rooms 索引
var state := "idle"            # idle / fighting / cleared
var spawn_queue: Array = []    # [enemy_id, pos, wave]
var spawn_t := 0.0
var wave := 0
var wave_alive := 0
var wave_size := 0
var corpses: Array = []
var hazards: Array = []
var portal_x := 0.0
var shrine_node: Node3D
var shrine_room := -1
var smith_node: Node3D           # 休息區的鐵匠（stages.csv 的 rest_stop）
var merchant_node: Node3D        # 休息區的商人
var drops: Array = []            # 地上的掉落武器（meta "item"）


func _ready() -> void:
	add_to_group("world")
	env = WorldEnvironment.new()
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	add_child(sun)


# ------------------------------------------------------------------ 建圖
func build_map(index: int) -> void:
	map_index = index
	map_id = Data.map_order[index]
	_clear_dynamic()
	if level_root:
		level_root.queue_free()
	level_root = Node3D.new()
	add_child(level_root)
	_apply_env()
	rooms = []
	var theme: Dictionary = THEMES[map_id]
	var x := 0.0
	_corridor(x - CORRIDOR, x, theme)
	var first_stage := index * 5 + 1
	for z in 5:
		var stage := first_stage + z
		var lay: Dictionary = Data.zones[str(stage)]
		var r := _build_room(stage, lay, x, theme)
		rooms.append(r)
		x += float(lay.w)
		_corridor(x, x + CORRIDOR, theme)
		x += CORRIDOR
	# 出口傳送陣（最後一區之後）
	portal_x = x - 4.0
	var portal := FX.cylinder(1.6, 0.2, Color(0.3, 0.9, 0.7), 2.0)
	level_root.add_child(portal)
	portal.position = Vector3(portal_x, 0.1, 0)
	FX.play(portal, portal.global_position + Vector3.UP, &"portal", 2.25, 2.0)
	var pl := FX.label3d("前往下一處" if index < 3 else "離開天魔殿", 72, Color(0.6, 1, 0.85))
	level_root.add_child(pl)
	pl.position = Vector3(portal_x, 2.5, 0)
	current = -1
	state = "idle"
	player.global_position = Vector3(-CORRIDOR + 3.0, 0.2, 0)
	player.yaw = -PI / 2.0
	player.rotation.y = player.yaw
	map_entered.emit(index)


func _apply_env() -> void:
	var th: Dictionary = THEMES[map_id]
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = th.sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = th.ambient
	e.ambient_light_energy = 0.9
	e.fog_enabled = true
	e.fog_light_color = th.fog
	e.fog_density = 0.018
	if map_id == "greenwood":
		e.background_mode = Environment.BG_SKY
		e.sky = Sky.new()
		var mountain_sky := ShaderMaterial.new()
		mountain_sky.shader = preload("res://assets/greenwood/ridges.gdshader")
		e.sky.sky_material = mountain_sky
		e.fog_light_color = Color(0.38, 0.46, 0.43)
		e.fog_density = 0.01
		e.fog_sky_affect = 0.12
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	env.environment = e


func _static_box(size: Vector3, pos: Vector3, color: Color, model: PackedScene = null) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	sb.add_child(col)
	if model:
		var art: Node3D = model.instantiate()
		art.position.y = -size.y / 2.0
		if model == GATE_MODEL:
			art.rotation.y = -PI / 2.0
		sb.add_child(art)
	else:
		var box := FX.box(size, color)
		if map_id == "greenwood":
			box.material_override = preload("res://assets/greenwood/surfaces.tres")
		sb.add_child(box)
	level_root.add_child(sb)
	sb.position = pos
	return sb


func _camp_block(label: String, extent: Vector3, base: Vector3, tint: Color) -> void:
	var spec: Array = CAMP_ART.get(label,[]) if map_id == "greenwood" else []
	var body := _static_box(extent,base+Vector3.UP*extent.y*.5,tint,spec[0] if spec else null)
	if spec:
		var visual := body.get_child(1) as Node3D
		visual.scale = extent / Vector3(spec[1])


func _static_cyl(radius: float, h: float, pos: Vector3, color: Color) -> void:
	var sb := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = h
	col.shape = shape
	sb.add_child(col)
	sb.add_child(FX.cylinder(radius, h, color))
	level_root.add_child(sb)
	sb.position = pos + Vector3(0, h / 2.0, 0)


func _corridor(x0: float, x1: float, theme: Dictionary) -> void:
	var length_m := x1 - x0
	var cx := (x0 + x1) / 2.0
	_static_box(Vector3(length_m, 0.2, 6.0), Vector3(cx, -0.1, 0), theme.floor.darkened(0.15))
	_static_box(Vector3(length_m, WALL_H, 0.5), Vector3(cx, WALL_H / 2.0, -3.25), theme.wall)
	_static_box(Vector3(length_m, WALL_H, 0.5), Vector3(cx, WALL_H / 2.0, 3.25), theme.wall)
	var torch := OmniLight3D.new()
	torch.light_color = Color(1.0, 0.7, 0.4)
	torch.omni_range = 9.0
	torch.light_energy = 1.2
	level_root.add_child(torch)
	torch.position = Vector3(cx, 3.0, 0)


func _build_room(stage: int, lay: Dictionary, x0: float, theme: Dictionary) -> Dictionary:
	var w := float(lay.w)
	var h := float(lay.h)
	var half := h / 2.0
	var cx := x0 + w / 2.0
	_static_box(Vector3(w, 0.2, h), Vector3(cx, -0.1, 0), theme.floor)
	# 北、南牆
	_static_box(Vector3(w + 0.5, WALL_H, 0.5), Vector3(cx, WALL_H / 2.0, -half - 0.25), theme.wall)
	_static_box(Vector3(w + 0.5, WALL_H, 0.5), Vector3(cx, WALL_H / 2.0, half + 0.25), theme.wall)
	# 西、東牆（中央留 6m 門洞，與走廊同寬）
	var seg := half - 3.0
	for wx in [x0, x0 + w]:
		_static_box(Vector3(0.5, WALL_H, seg), Vector3(wx, WALL_H / 2.0, -3.0 - seg / 2.0), theme.wall)
		_static_box(Vector3(0.5, WALL_H, seg), Vector3(wx, WALL_H / 2.0, 3.0 + seg / 2.0), theme.wall)
	var gate_art := GATE_MODEL if map_id == "greenwood" else null
	var gate_in := _static_box(Vector3(0.6, WALL_H, 6.0), Vector3(x0, WALL_H / 2.0, 0), Color(0.75, 0.2, 0.15), gate_art)
	var gate_out := _static_box(Vector3(0.6, WALL_H, 6.0), Vector3(x0 + w, WALL_H / 2.0, 0), Color(0.75, 0.2, 0.15), gate_art)
	_set_gate(gate_in, false)
	var r := {"stage": stage, "x0": x0, "w": w, "h": h, "gate_in": gate_in, "gate_out": gate_out,
		"spawns": {}, "elites": [], "boss": Vector3.ZERO, "shrine": Vector3(x0 + w - 4.0, 0, 4.0)}
	var nav := preload("res://scripts/room_routes.gd").new(Rect2(x0,-half,w,h))
	r["navigation"] = nav
	var row: Dictionary = Data.stage_row(stage)
	var title := FX.label3d("第%d區・%s" % [stage, row.area_zh], 96, Color(0.95, 0.9, 0.75))
	level_root.add_child(title)
	title.position = Vector3(x0 - 1.0, 3.6, 0)
	for el in lay.elements:
		var k: String = el.kind
		var ex := float(el.x)
		var ey := float(el.y)
		if k in ["spawn", "elite", "boss", "shrine"]:
			var p := Vector3(x0 + ex, 0.2, ey - half)
			match k:
				"spawn":
					var wv := int(el.wave)
					if not r.spawns.has(wv):
						r.spawns[wv] = []
					r.spawns[wv].append(p)
				"elite": r.elites.append(p)
				"boss": r.boss = p
				"shrine": r.shrine = p
			continue
		var ew := float(el.w)
		var eh := float(el.h)
		var label: String = el.label
		var c := Vector3(x0 + ex + ew / 2.0, 0, ey + eh / 2.0 - half)
		if k in ["cover","high","round","tree"]:
			var extent := Vector2(ew,eh)
			if k == "round":
				extent = Vector2.ONE * minf(ew,eh)
			elif k == "tree":
				extent = Vector2.ONE
			nav.blocks.append(Rect2(Vector2(c.x,c.z)-extent/2,extent))
		match k:
			"cover":
				var tall := 1.2 if (ew < 3.0 and eh < 3.0) or label in ["棺", "板車", "草堆", "香爐"] else 3.0
				_camp_block(label,Vector3(ew,tall,eh),c,theme.wall.lightened(.15))
			"high":
				_camp_block(label,Vector3(ew,1.0,eh),c,Color(.55,.47,.33))
				if map_id == "greenwood" and label == "交椅":
					var chair := CAMP_CHAIR.instantiate() as Node3D
					level_root.add_child(chair)
					chair.position = c + Vector3.UP
			"round":
				var big := maxf(ew, eh) >= 8.0
				_static_cyl(minf(ew, eh) / 2.0, 8.0 if big else 1.4, c, Color(0.35, 0.3, 0.22) if big else theme.wall.lightened(0.1))
			"tree":
				_static_cyl(0.5, 6.0, c, Color(0.3, 0.22, 0.15))
				var crown := FX.sphere(maxf(ew, eh) / 2.0 + 0.5, Color(0.18, 0.3, 0.16))
				level_root.add_child(crown)
				crown.position = c + Vector3(0, 6.0, 0)
			"grass":
				var g := FX.box(Vector3(ew, 1.0, eh), Color(0.35, 0.45, 0.2, 0.55))
				level_root.add_child(g)
				g.position = c + Vector3(0, 0.5, 0)
			"dark":
				var d := FX.box(Vector3(ew, 0.05, eh), Color(0.05, 0.05, 0.06))
				level_root.add_child(d)
				d.position = c + Vector3(0, 0.03, 0)
			"light":
				var l := OmniLight3D.new()
				l.light_color = Color(1.0, 0.65, 0.3)
				l.omni_range = 7.0
				l.light_energy = 2.0
				level_root.add_child(l)
				l.position = c + Vector3(0, 2.5, 0)
				var fl := FX.sphere(0.2, Color(1, 0.6, 0.2), 4.0)
				level_root.add_child(fl)
				fl.position = c + Vector3(0, 2.2, 0)
			"poison":
				if "屍堆" in label:
					var pile := FX.box(Vector3(ew, 0.6, eh), Color(0.3, 0.33, 0.25))
					level_root.add_child(pile)
					pile.position = c + Vector3(0, 0.3, 0)
					corpses.append(c)
				elif "藥鼎" in label:
					_static_cyl(1.2, 1.4, c, Color(0.25, 0.3, 0.2))
					_permanent_hazard(c, maxf(ew, eh) / 2.0 + 1.0, stage, Color(0.35, 0.7, 0.2, 0.3))
			"danger":
				if "斷崖" in label:
					var cliff := FX.box(Vector3(ew, 0.05, eh), Color(0.02, 0.02, 0.02))
					level_root.add_child(cliff)
					cliff.position = c + Vector3(0, 0.03, 0)
					_permanent_hazard(c, minf(ew, eh) / 2.0, stage, Color(0.1, 0.0, 0.0, 0.0), 3.0, &"")
				elif "血池" in label or ew <= 2.5:
					if map_id == "greenwood":
						var basket := CAMP_BRAZIER.instantiate() as Node3D
						level_root.add_child(basket)
						basket.position = c
					var fire := FX.cylinder(minf(ew, eh) / 2.0, 0.8, Color(0.75, 0.05, 0.05) if "血池" in label else Color(0.9, 0.35, 0.1), 2.5)
					level_root.add_child(fire)
					fire.position = c + Vector3(0, 0.72 if map_id == "greenwood" else 0.4, 0)
					if map_id == "greenwood": fire.scale = Vector3(.53,.38,.53)
					_permanent_hazard(c, minf(ew, eh) / 2.0 + 0.5, stage, Color(1, 0.4, 0.1, 0.2), 1.5, &"" if "血池" in label else &"campfire")
	return r


func _permanent_hazard(c: Vector3, radius: float, stage: int, color: Color, mult := 0.5, clip: StringName = &"poison-cloud") -> void:
	var hz := HAZARD.new()
	level_root.add_child(hz)
	hz.position = Vector3(c.x, 0, c.z)
	hz.configure(radius, Data.cfg("base_enemy_dmg") * pow(Data.cfg("enemy_dmg_growth"), stage - 1) * mult, -1.0, true, color, clip)


func _set_gate(g: StaticBody3D, closed: bool) -> void:
	g.visible = closed
	for c in g.get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", not closed)


func _clear_dynamic() -> void:
	for c in get_children():
		if c.is_in_group("player") or c == env or c is DirectionalLight3D or c == level_root:
			continue
		c.queue_free()
	corpses = []
	hazards = []
	spawn_queue = []
	shrine_node = null
	smith_node = null
	merchant_node = null
	drops = []


# ------------------------------------------------------------------ 區域流程
func _physics_process(delta: float) -> void:
	if player == null or rooms.is_empty():
		return
	var px: float = player.global_position.x
	var pz: float = player.global_position.z
	match state:
		"idle", "cleared":
			var next := current + 1
			if next < rooms.size():
				var r: Dictionary = rooms[next]
				if px > r.x0 + 2.0 and absf(pz) < r.h / 2.0:
					_lock(next)
			elif px > portal_x - 1.5:
				state = "leaving"
				if map_index < Data.map_order.size() - 1:
					build_map(map_index + 1)
				else:
					run_won.emit()
		"fighting":
			_process_spawns(delta)
	for d in drops:
		if is_instance_valid(d):
			d.get_child(0).rotate_y(delta * 1.2)
			# 靠近時改看比較面板，名牌收起來免得擋住畫面
			d.get_meta("label").visible = d.global_position.distance_to(player.global_position) > 3.5


func _lock(i: int) -> void:
	current = i
	state = "fighting"
	var r: Dictionary = rooms[i]
	Game.stage = r.stage
	_set_gate(r.gate_in, true)
	for n in [shrine_node, smith_node, merchant_node]:
		if n and is_instance_valid(n):
			n.queue_free()
	shrine_node = null
	smith_node = null
	merchant_node = null
	var row: Dictionary = Data.stage_row(r.stage)
	var rep: Dictionary = Data.report_row(r.stage)
	var total := int(rep.minions)
	var waves := maxi(1, int(rep.waves))
	var mix := _mix(row.minion_mix)
	spawn_queue = []
	for wv in range(1, waves + 1):
		var n := total / waves + (1 if wv <= total % waves else 0)
		var pts: Array = r.spawns.get(wv, [])
		if pts.is_empty():
			for k in r.spawns:
				pts += r.spawns[k]
		if pts.is_empty():
			pts = [Vector3(r.x0 + r.w - 3.0, 0.2, 0)]
		for j in n:
			var p: Vector3 = pts[j % pts.size()] + Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
			spawn_queue.append([_pick(mix), p, wv])
	var elites: Array = Array(String(row.elites).split("|", false))
	for j in elites.size():
		var ep: Vector3 = r.elites[j % r.elites.size()] if not r.elites.is_empty() else Vector3(r.x0 + r.w * 0.7, 0.2, 0)
		spawn_queue.push_front([elites[j], ep, 1])
	if row.boss != "":
		spawn_enemy(row.boss, r.boss, true)
	wave = 0
	wave_alive = 0
	wave_size = 0
	_next_wave()
	Sfx.play("zone_lock")
	Feel.shake(0.22)
	zone_locked.emit(r.stage, "%s・%s" % [Data.maps[map_id].name_zh, row.area_zh])


func _mix(s: String) -> Array:
	var out: Array = []
	for part in s.split("|"):
		var kv := part.split(":")
		out.append([kv[0], float(kv[1])])
	return out


func _pick(mix: Array) -> String:
	var total := 0.0
	for m in mix:
		total += m[1]
	var x := randf() * total
	for m in mix:
		x -= m[1]
		if x <= 0.0:
			return m[0]
	return mix[0][0]


func _next_wave() -> void:
	wave += 1
	wave_size = 0
	for q in spawn_queue:
		if q[2] == wave:
			wave_size += 1
	wave_alive = wave_size


func _process_spawns(delta: float) -> void:
	spawn_t -= delta
	if spawn_t <= 0.0:
		spawn_t = SPAWN_RATE
		for i in spawn_queue.size():
			if spawn_queue[i][2] == wave:
				var q = spawn_queue[i]
				spawn_queue.remove_at(i)
				FX.play(self, q[1] + Vector3(0, 0.5, 0), &"poof", 1.3, 0.3, Color(0.95, 0.62, 0.5))
				spawn_enemy(q[0], q[1], false)
				break
	var pending_this_wave := spawn_queue.any(func(q): return q[2] == wave)
	if not pending_this_wave and spawn_queue.size() > 0 and wave_alive <= ceili(wave_size * 0.2):
		_next_wave()
	var alive := get_tree().get_nodes_in_group("enemies").size()
	enemies_changed.emit(alive + spawn_queue.size())
	if spawn_queue.is_empty() and alive == 0:
		_clear_zone()


func _clear_zone() -> void:
	state = "cleared"
	var r: Dictionary = rooms[current]
	_set_gate(r.gate_out, false)
	Sfx.play("zone_clear")
	Sfx.play("gate_open", r.gate_out.global_position)
	Game.on_zone_cleared()
	if r.stage < Data.stages.size():
		shrine_node = Node3D.new()
		add_child(shrine_node)
		shrine_node.global_position = r.shrine
		var pillar: Node3D = CAMP_STELE.instantiate()
		shrine_node.add_child(pillar)
		pillar.global_position.y = 0.0
		pillar.rotation.y = PI / 2.0
		FX.play(shrine_node, pillar.global_position + Vector3.UP, &"magic-circle-cast", 2.5, 0.8)
		Sfx.play("shrine_appear", r.shrine)
		var lab := FX.label3d("悟道碑\n［F］參悟", 64, Color(0.7, 1, 0.85))
		lab.position.y = 3.3
		shrine_node.add_child(lab)
		shrine_room = current
		if String(Data.stage_row(r.stage).get("rest_stop", "0")) == "1":
			_spawn_rest_stop(r.shrine)
	for h in hazards:
		if is_instance_valid(h):
			h.queue_free()
	hazards = []
	zone_cleared.emit(r.stage)


func near_shrine() -> bool:
	return _near(shrine_node, 3.0)


func near_smith() -> bool:
	return _near(smith_node, 3.2)


func near_merchant() -> bool:
	return _near(merchant_node, 3.2)


func _near(n: Node3D, r: float) -> bool:
	return n != null and is_instance_valid(n) and n.global_position.distance_to(player.global_position) < r


func _spawn_rest_stop(shrine_pos: Vector3) -> void:
	## 休息區：悟道碑旁邊擺鐵匠與商人，商人重新上架
	var r: Dictionary = rooms[0]
	for room in rooms:
		if shrine_pos.x >= room.x0 and shrine_pos.x <= room.x0 + room.w:
			r = room
	var smith_at := _stall_spot(r, shrine_pos, [])
	smith_node = _rest_npc(SMITH_PROP, smith_at, "鐵匠\n［F］強化／重鑄", Color(1.0, 0.62, 0.3))
	merchant_node = _rest_npc(MERCHANT_PROP, _stall_spot(r, shrine_pos, [smith_at]), "商人\n［F］購買武學", Color(0.95, 0.85, 0.5))
	Game.restock_merchant()


func _stall_spot(r: Dictionary, near: Vector3, taken: Array) -> Vector3:
	## 在悟道碑附近找一塊放得下攤位的空地：由近到遠，留在房間內、不擋中央通道，
	## 不與障礙物、悟道碑或已放的攤位重疊
	var space := get_world_3d().direct_space_state
	var probe := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = STALL_SIZE + Vector3(0.8, -0.4, 0.8)
	probe.shape = box
	probe.collision_mask = 1
	var half_h: float = r.h / 2.0
	var cands: Array = []
	for dx in range(-int(r.w), int(r.w) + 1):
		for dz in range(-10, 11, 2):
			var p := Vector3(near.x + dx, 0.0, near.z + dz)
			if p.x - STALL_SIZE.x / 2.0 < r.x0 + 1.0 or p.x + STALL_SIZE.x / 2.0 > r.x0 + r.w - 1.0:
				continue
			if absf(p.z) + STALL_SIZE.z / 2.0 > half_h - 0.6 or absf(p.z) - STALL_SIZE.z / 2.0 < 3.5:
				continue
			var d := Vector2(p.x - near.x, p.z - near.z).length()
			if d < 4.0:
				continue
			cands.append([d, p])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for c in cands:
		var p: Vector3 = c[1]
		if taken.any(func(t): return absf(t.x - p.x) < STALL_SIZE.x + 1.2 and absf(t.z - p.z) < STALL_SIZE.z + 1.0):
			continue
		probe.transform = Transform3D(Basis(), p + Vector3.UP * (STALL_SIZE.y / 2.0 + 0.3))
		if space.intersect_shape(probe, 1).is_empty():
			return p
	return near + Vector3(0, 0, -4.0 * signf(near.z if near.z != 0.0 else 1.0))


func _rest_npc(model: PackedScene, pos: Vector3, title: String, color: Color) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	var prop: Node3D = model.instantiate()
	n.add_child(prop)
	prop.rotation.y = PI if pos.z > 0.0 else 0.0   # 模型正面朝 +Z；轉向房間中央
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = STALL_SIZE
	shape.shape = box
	shape.position.y = STALL_SIZE.y / 2.0
	body.add_child(shape)
	n.add_child(body)
	var lab := FX.label3d(title, 56, color)
	lab.position.y = 3.4
	n.add_child(lab)
	return n


# ------------------------------------------------------------------ 掉落武器
func spawn_drop(pos: Vector3, item: Dictionary) -> Node3D:
	var row: Dictionary = Data.weapons[item.id]
	var col := UIKit.TEAL.lerp(UIKit.BONE, 0.3)
	var d := Node3D.new()
	add_child(d)
	d.global_position = Vector3(pos.x, 0.0, pos.z)
	Sfx.play("loot_drop", d.global_position)
	var spin := Node3D.new()
	spin.position.y = 0.9
	d.add_child(spin)
	if DROP_MODELS.has(item.id):
		var m: Node3D = DROP_MODELS[item.id].instantiate()
		m.rotation_degrees = Vector3(0, 0, 70)
		spin.add_child(m)
	var beam := FX.cylinder(0.05, 2.4, Color(col, 0.55), 2.0)
	beam.position.y = 1.2
	d.add_child(beam)
	var lab := FX.label3d("%s　詞條 %d" % [row.name_zh, item.get("affixes", []).size()], 40, col)
	lab.position.y = 2.1
	d.add_child(lab)
	d.set_meta("item", item)
	d.set_meta("label", lab)
	drops.append(d)
	return d


func nearest_drop(radius: float) -> Node3D:
	var best: Node3D = null
	var best_d := radius
	for d in drops:
		if is_instance_valid(d):
			var dist: float = d.global_position.distance_to(player.global_position)
			if dist <= best_d:
				best = d
				best_d = dist
	return best


func take_drop(d: Node3D) -> Dictionary:
	drops.erase(d)
	var item: Dictionary = d.get_meta("item")
	d.queue_free()
	return item


# ------------------------------------------------------------------ 給敵人用的介面
func spawn_enemy(id: String, pos: Vector3, _is_boss: bool):
	var e := ENEMY.new()
	e.setup(id, Game.stage, self, pos)
	add_child(e)
	return e


func boss_spawned(e) -> void:
	Sfx.play("boss_appear")
	Feel.shake(float(Data.feel.shake_boom))
	boss_appeared.emit(e)


signal enemy_defeated(id: String)
signal telegraph(pos: Vector3, radius: float, duration: float)

func warn_area(pos: Vector3, radius: float, duration: float) -> void:
	FX.warn_circle(self,pos,radius,duration)
	telegraph.emit(pos,radius,duration)


func on_enemy_died(e) -> void:
	enemy_defeated.emit(e.eid)
	var item := Game.roll_weapon_drop(String(Data.enemies[e.eid].rank))
	if not item.is_empty():
		spawn_drop(e.global_position, item)
	corpses.append(e.global_position)
	if corpses.size() > 40:
		corpses.pop_front()
	if state == "fighting":
		wave_alive -= 1


func take_corpse_near(p: Vector3, r: float) -> Vector3:
	for i in corpses.size():
		if corpses[i].distance_to(p) <= r:
			var c: Vector3 = corpses[i]
			corpses.remove_at(i)
			return c
	return Vector3.INF


func enemies_near(p: Vector3, r: float) -> Array:
	var out: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if absf(e.global_position.x - p.x) <= r and absf(e.global_position.z - p.z) <= r:
			out.append(e)
	return out


func track_hazard(h) -> void:
	hazards.append(h)
