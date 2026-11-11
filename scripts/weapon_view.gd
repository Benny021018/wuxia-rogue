extends Node3D
## 以握點為根的第一人稱動作。每個節拍回呼一次，左右手不共用 Tween。
const LoadingHand := preload("res://scripts/loading_hand.gd")
const Bow := preload("res://scripts/archer_bow.gd")
const REST := {
	"W001":Vector3(34,16,-13), "W002":Vector3(18,28,-20), "W003":Vector3(8,6,-12),
	"W004":Vector3(20,14,-7), "W005":Vector3(10,16,-5), "W006":Vector3(40,16,-15),
	"W007":Vector3(4,0,-16), "W101":Vector3(35,19,-20), "W102":Vector3(15,25,-18),
	"W103":Vector3(8,6,2), "W201":Vector3(36,15,-13), "W202":Vector3(24,18,-25),
	"W203":Vector3(10,8,10), "W204":Vector3(12,19,-8), "W301":Vector3(38,20,-14),
	"W302":Vector3(22,14,-6), "W303":Vector3(8,10,-3)}
const CONTACT := {"W001":.36,"W002":.41,"W003":.24,"W004":.31,"W005":.38,"W006":.34,"W007":.62,"W101":.48,"W102":.31,"W103":.25,"W201":.30,"W202":.42,"W203":.34,"W204":.43,"W301":.53,"W302":.29,"W303":.24}
var id: String
var hand: float
var art: Node3D
var string: Array[MeshInstance3D] = []
var arrow: Node3D
var grip_sleeve: MeshInstance3D
var grip_wrist: Vector3
var loader: LoadingHand
var lash: MeshInstance3D
var mate: Node3D
var timeline: Tween
var alternating := false
var home: Vector3
var attack_action: StringName
var saya: Node3D
var blade: Node3D
var saya_hand: LoadingHand
var flex_mesh: MeshInstance3D
var limb_extent := 0.0
var top := Vector3.ZERO
var bottom := Vector3.ZERO

func setup(wid: String, slot: int) -> void:
	id = wid
	attack_action = "attack_%d" % (slot+1)
	hand = 1.0 if slot == 0 else -1.0
	var asset := "Tachi" if id == "W001" else id
	var packed := load("res://assets/models/weapons/%s.glb" % asset) as PackedScene
	art = packed.instantiate()
	add_child(art)
	home = Vector3(.32*hand,-.23,-.49)
	if id in ["W003","W006","W103","W203"]:
		home = Vector3(.25*hand,-.19,-.45)
	if id in ["W007","W202"]:
		home = Vector3(.27*hand,-.21,-.67)
	if id == "W202":
		art.scale = Vector3.ONE*.75
		lash = art.find_children("*","MeshInstance3D",true,false)[0]
	_add_grip()
	if id in ["W007","W303"]:
		var mesh: MeshInstance3D = art.find_children("*","MeshInstance3D",true,false)[0]
		flex_mesh = mesh
		# 直接從最外端的頂點取平均，弓梢位置跟隨校正後的模型。
		var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var high := -INF
		var low := INF
		for v in vertices:
			var pt := to_local(mesh.to_global(v))
			var y := pt.y if id=="W007" else pt.x
			high = maxf(high,y)
			low = minf(low,y)
		limb_extent = maxf(absf(high),absf(low))
		var n := Vector2i.ZERO
		for v in vertices:
			var pt := to_local(mesh.to_global(v))
			var along := pt.y if id=="W007" else pt.x
			if along >= high-.012:
				top += pt
				n.x += 1
			if along <= low+.012:
				bottom += pt
				n.y += 1
		top /= maxi(1,n.x)
		bottom /= maxi(1,n.y)
		for i in 2:
			var strand := Bow.rod(.003,.003,Color("#eadbb9"))
			add_child(strand)
			string.append(strand)
	if id in ["W007","W303"]:
		loader = LoadingHand.new()
		add_child(loader)
		loader.setup(hand)
		arrow = Bow.make_arrow()
		add_child(arrow)
		arrow.scale = Vector3.ONE*(.76 if id=="W007" else .48)
	if id == "W201":
		mate = packed.instantiate()
		art.add_child(mate)
		mate.position = Vector3(-.10*hand,.035,-.045)
		mate.rotation_degrees = Vector3(3,-14*hand,12*hand)
	_pose(Vector3.ZERO,Vector3.ZERO)
	if id == "W001":
		blade = art.find_child("Blade",true,false)
		saya = art.find_child("Saya",true,false)
		saya.reparent(self,false)
		saya_hand = LoadingHand.new()
		saya.add_child(saya_hand)
		saya_hand.setup(hand)
		_tachi_pose(0.0)
	if loader:
		_rest_ammo()

func _add_grip() -> void:
	grip_wrist = Vector3(.020*hand,-.055,.06)
	grip_sleeve = Bow.rod(.068,.051,Color("#343242"))
	add_child(grip_sleeve)
	if id in ["W003","W103","W203"]:
		return
	var glove := FX.sphere(.055,Color("#684a38"))
	add_child(glove)
	glove.position = Vector3(.022*hand,-.017,.015)
	glove.scale = Vector3(.81,.88,1.35)
	for j in 3:
		var wrap := Bow.rod(.013,.011,Color("#aa7954"))
		add_child(wrap)
		var z := -.032+j*.024
		Bow.span(wrap,Vector3(-.033*hand,-.01,z),Vector3(.021*hand,.024,z+.004))

func _process(_delta: float) -> void:
	if grip_sleeve and is_visible_in_tree():
		var elbow := get_parent_node_3d().to_global(Vector3(hand*.40,-.43,-.19))
		Bow.span(grip_sleeve,to_local(elbow),grip_wrist)

func launch_position() -> Vector3:
	if arrow:
		return arrow.to_global(Vector3.FORWARD*Bow.LENGTH)
	return to_global(Vector3.FORWARD*(.30 if id=="W303" else .16))

func _pose(deg: Vector3, offset: Vector3) -> void:
	var r: Vector3 = REST[id] + deg
	rotation_degrees = Vector3(r.x,r.y*hand,r.z*hand)
	position = home + Vector3(offset.x*hand,offset.y,offset.z)

func needs_support() -> bool:
	return id in ["W001","W007","W303"]

func _tail(draw: float) -> Vector3:
	if id == "W303":
		return Vector3(0,.052,lerpf((top.z+bottom.z)*.5+.025,.11,draw))
	return (top+bottom)*.5 + Vector3(0,0,.065+draw*.29)

func _bend(draw: float) -> void:
	if not string.is_empty():
		flex_mesh.set_blend_shape_value(0,draw)
		Bow.span(string[0],_flex_tip(top,draw),_tail(draw))
		Bow.span(string[1],_flex_tip(bottom,draw),_tail(draw))

func _flex_tip(rest: Vector3, draw: float) -> Vector3:
	var axis := Vector3.UP if id=="W007" else Vector3.RIGHT
	var along := rest.dot(axis)
	var influence := pow(absf(along)/limb_extent,2)*draw
	var travel := .112 if id=="W007" else .043
	return rest + (Vector3.BACK*travel - axis*along*.12)*influence

func _rest_ammo() -> void:
	_bend(0)
	arrow.hide()
	loader.place(Vector3.ZERO,Vector3.ZERO,false)

func _hand_at(tail: Vector3, carrying: bool, tilt := 0.0) -> void:
	var camera := get_parent_node_3d()
	var elbow := to_local(camera.to_global(Vector3(-hand*.42,-.41,-.22)))
	loader.place(tail,elbow,true)
	arrow.visible = carrying
	if carrying:
		arrow.position = tail
		arrow.rotation_degrees = Vector3(tilt,tilt*.55*hand,0)

func _load_pose(progress: float) -> void:
	# 箭由畫面另一側送入，落槽後弩手撤手，弓手繼續扣弦。
	var dock := _tail(1 if id=="W303" else 0)
	var pickup := dock+Vector3(-hand*.46,-.19,.09)
	var guide := dock+Vector3(-hand*.16,.075,.015)
	if progress < .65:
		var blend := smoothstep(0,.65,progress)
		_hand_at(pickup.lerp(guide,blend),true,lerpf(24,9,blend))
	else:
		var blend := smoothstep(.65,1,progress)
		_hand_at(guide.lerp(dock,blend),true,lerpf(9,0,blend))

func _draw_pose(draw: float) -> void:
	_bend(draw)
	_hand_at(_tail(draw),true)

func _withdraw(progress: float) -> void:
	var grasp := _tail(1)
	var away := Vector3(-hand*.35,-.16,.10)
	var camera := get_parent_node_3d()
	var elbow := to_local(camera.to_global(Vector3(-hand*.42,-.41,-.22)))
	loader.place(grasp+away*progress,elbow,progress<.99)

func _fire(impact: Callable, beat: int) -> void:
	impact.call(beat)
	arrow.hide()

func _ranged_sequence(t: Tween, seconds: float, hits: int, impact: Callable) -> void:
	_rest_ammo()
	if id=="W007":
		_key(t,Vector3(-9,7,-14),Vector3(-.08,-.015,-.035),seconds*.22)
		t.parallel().tween_method(_load_pose,0.0,1.0,seconds*.22)
		_key(t,Vector3(-4,-5,12),Vector3(-.16,.07,-.13),seconds*.34)
		t.parallel().tween_method(_draw_pose,0.0,1.0,seconds*.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_interval(seconds*.10)
		t.tween_callback(_fire.bind(impact,0))
		_key(t,Vector3(2,-3,17),Vector3(-.145,.075,-.08),seconds*.07)
		t.parallel().tween_method(_bend,1.0,0.0,seconds*.04)
		t.parallel().tween_method(_withdraw,0.0,.25,seconds*.07)
		_key(t,Vector3.ZERO,Vector3.ZERO,seconds*.27)
		t.parallel().tween_method(_withdraw,.25,1.0,seconds*.19)
	else:
		var cycle := seconds/maxi(hits,1)
		for beat in hits:
			_key(t,Vector3(-13,-8,-22),Vector3(-.05,-.025,-.015),cycle*.25)
			t.parallel().tween_method(_reset_crossbow,0.0,1.0,cycle*.25)
			t.tween_method(_load_pose,0.0,1.0,cycle*.34)
			_key(t,Vector3(-7,-7,2),Vector3(-.13,.055,-.075),cycle*.18)
			t.parallel().tween_method(_withdraw,0.0,1.0,cycle*.18)
			t.tween_callback(_fire.bind(impact,beat))
			_key(t,Vector3(3,-6,4),Vector3(-.12,.068,-.029),cycle*.09)
			t.parallel().tween_method(_bend,1.0,0.0,cycle*.09)
			_key(t,Vector3.ZERO,Vector3.ZERO,cycle*.14)
	t.tween_callback(_rest_ammo)

func _reset_crossbow(progress: float) -> void:
	_bend(progress)
	_hand_at(_tail(progress),false)

## Camera-space choreography; the sheath moves separately from the sword hand.
func _tachi_pose(t: float) -> void:
	var draw := smoothstep(.08,.34,t) * (1.0-smoothstep(.73,.98,t))
	var sweep := smoothstep(.34,.50,t) * (1.0-smoothstep(.59,.73,t))
	var lift := smoothstep(0,.08,t) * (1.0-smoothstep(.98,1.0,t))
	var dock := Vector3(-.18*hand,-.23 + .035*lift,-.55)
	var rest_angle := Vector3(-12,74*hand,-15*hand)
	var dock_basis := Basis.from_euler(rest_angle * PI/180)
	var axis := dock_basis.z
	var rest_saya := Transform3D(dock_basis,dock-axis*.32*draw)
	position = dock + axis*.43*draw + Vector3(.07*hand,.13,-.09)*sweep
	rotation_degrees = rest_angle.lerp(Vector3(21,-64*hand,24*hand),sweep)
	saya.transform = transform.affine_inverse() * rest_saya
	# Reveal only the portion outside the mouth; the curved tip cannot poke through the lacquer.
	blade.visible = draw > .001
	blade.scale = Vector3(1,maxf(.001,draw*draw),maxf(.001,draw))
	blade.position.z = -.082*(1.0-draw)
	var elbow := saya.to_local(get_parent_node_3d().to_global(Vector3(-hand*.45,-.42,-.23)))
	saya_hand.place(Vector3(0,-.019,-.15),elbow,t > 0.0 and t < 1.0)

func _saber_sequence(t: Tween, seconds: float, impact: Callable) -> void:
	_tachi_pose(0.0)
	t.tween_method(_tachi_pose,0.0,.42,seconds*.42).set_trans(Tween.TRANS_LINEAR)
	t.tween_callback(impact.bind(0))
	t.tween_method(_tachi_pose,.42,1.0,seconds*.58).set_trans(Tween.TRANS_LINEAR)

func _key(t: Tween, r: Vector3, p: Vector3, sec: float) -> void:
	var rr: Vector3 = REST[id]+r
	var angle := Vector3(rr.x,rr.y*hand,rr.z*hand)
	var pos := home+Vector3(p.x*hand,p.y,p.z)
	t.tween_property(self,"rotation_degrees",angle,sec)
	t.parallel().tween_property(self,"position",pos,sec)

func attack(interval: float, hits: int, impact: Callable) -> void:
	if timeline:
		timeline.kill()
	alternating = not alternating
	art.visible = true
	var seconds := minf(interval,.85)
	var t := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	timeline = t
	t.set_trans(Tween.TRANS_SINE)
	if id in ["W007","W303"]:
		_ranged_sequence(t,seconds,hits,impact)
		return
	if id=="W001":
		_saber_sequence(t,seconds,impact)
		return
	var first: float = CONTACT[id]
	var wind := Vector3(16,-28,-18)
	var end := Vector3(-24,35,32)
	var prep := Vector3(.045,.055,.025)
	var thrust := Vector3(-.17,-.035,-.12)
	match id:
		"W002","W202":
			wind = Vector3(3,-48,-30)
			end = Vector3(-8,62,58 if id=="W202" else 27)
			thrust = Vector3(-.25,.025,-.08)
		"W003","W004","W005","W302","W204":
			wind = Vector3(8,-12,8)
			end = Vector3(-REST[id].x+3,8,-5)
			prep = Vector3(.035,-.035,.08)
			thrust = Vector3(-.13,.045,-.31 if id!="W003" else -.23)
			if id=="W204" and alternating:
				wind.y = -40
				end.y = 31
		"W101","W301":
			wind = Vector3(38,-18,-24)
			end = Vector3(-52,26,25)
			prep = Vector3(.02,.13,-.03)
			thrust = Vector3(-.17,-.14,-.18)
		"W006","W102","W201":
			wind = Vector3(18,-19,-35)
			end = Vector3(-32,40,57)
			thrust = Vector3(-.15,.04,-.17)
		"W103","W203":
			wind = Vector3(-6,7,0)
			end = Vector3(9,7,-4)
			prep = Vector3(-.08,.04,-.08)
			thrust = prep + Vector3(.01,.02,.06)
	_key(t,wind,prep,seconds*first*.68)
	_key(t,end,thrust,seconds*first*.32)
	if lash:
		t.parallel().tween_method(func(v:float): lash.set_blend_shape_value(0,v),0.0,1.0,seconds*first*.32)
	if mate:
		t.parallel().tween_property(mate,"rotation_degrees:y",32*hand,seconds*first*.32)
	t.tween_callback(impact.bind(0))
	if id=="W006":
		t.tween_callback(art.hide)
	# 針匣一次齊射，其餘多段武器逐拍回鉤、前刺或回彈。
	var pulses := hits if id in ["W201","W302","W103","W303"] else 1
	var beat := seconds*.34/maxi(1,pulses-1)
	for j in range(1,pulses):
		_key(t,wind*.65,prep,beat*.50)
		_key(t,end if id!="W201" else -end*.65,thrust,beat*.50)
		if mate:
			t.parallel().tween_property(mate,"rotation_degrees:y",-29*hand,beat*.50)
		t.tween_callback(impact.bind(j))
	var recover := seconds*(1-first)-beat*(pulses-1)
	_key(t,Vector3.ZERO,Vector3.ZERO,maxf(.001,recover))
	if lash:
		t.parallel().tween_method(func(v:float): lash.set_blend_shape_value(0,v),1.0,0.0,recover)
	if mate:
		t.parallel().tween_property(mate,"rotation_degrees:y",-14*hand,recover)
	t.tween_callback(art.show)
