extends Node3D
## 以握點為根的第一人稱動作。每個節拍回呼一次，左右手不共用 Tween。
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
var lash: MeshInstance3D
var mate: Node3D
var timeline: Tween
var alternating := false
var home: Vector3
var top := Vector3.ZERO
var bottom := Vector3.ZERO

func setup(wid: String, slot: int) -> void:
	id = wid
	hand = 1.0 if slot == 0 else -1.0
	var packed := load("res://assets/models/weapons/%s.glb" % id) as PackedScene
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
	if id == "W007":
		var mesh: MeshInstance3D = art.find_children("*","MeshInstance3D",true,false)[0]
		# 直接從最外端的頂點取平均，弓梢位置跟隨校正後的模型。
		var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var high := -INF
		var low := INF
		for v in vertices:
			var y: float = to_local(mesh.to_global(v)).y
			high = maxf(high,y)
			low = minf(low,y)
		var n := Vector2i.ZERO
		for v in vertices:
			var pt := to_local(mesh.to_global(v))
			if pt.y >= high-.018:
				top += pt
				n.x += 1
			if pt.y <= low+.018:
				bottom += pt
				n.y += 1
		top /= maxi(1,n.x)
		bottom /= maxi(1,n.y)
		for i in 2:
			var strand := Bow.rod(.003,.003,Color("#eadbb9"))
			add_child(strand)
			string.append(strand)
		arrow = Bow.make_arrow()
		add_child(arrow)
		arrow.scale = Vector3.ONE*.76
	if id == "W201":
		mate = packed.instantiate()
		art.add_child(mate)
		mate.position = Vector3(-.10*hand,.035,-.045)
		mate.rotation_degrees = Vector3(3,-14*hand,12*hand)
	_pose(Vector3.ZERO,Vector3.ZERO)
	_string_pose(0,true)

func _add_grip() -> void:
	var wrist := Vector3(.020*hand,-.055,.06)
	var cuff := Bow.rod(.062,.051,Color("#343242"))
	add_child(cuff)
	Bow.span(cuff,wrist+Vector3(.07*hand,-.12,.22),wrist)
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

func launch_position() -> Vector3:
	if arrow:
		return arrow.to_global(Vector3.FORWARD*Bow.LENGTH)
	return to_global(Vector3.FORWARD*(.30 if id=="W303" else .16))

func _pose(deg: Vector3, offset: Vector3) -> void:
	var r: Vector3 = REST[id] + deg
	rotation_degrees = Vector3(r.x,r.y*hand,r.z*hand)
	position = home + Vector3(offset.x*hand,offset.y,offset.z)

func _string_pose(draw: float, loaded: bool) -> void:
	if arrow == null:
		return
	var tail := (top+bottom)*.5 + Vector3(0,0,.065 + draw*.29)
	Bow.span(string[0],top,tail)
	Bow.span(string[1],bottom,tail)
	arrow.position = tail
	arrow.visible = loaded

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
		"W007":
			wind = Vector3(-3,6,6)
			end = Vector3(4,8,13)
			prep = Vector3(-.11,.04,-.09)
			thrust = prep + Vector3(.015,.015,.05)
		"W103","W203","W303":
			wind = Vector3(-6,7,0)
			end = Vector3(9,7,-4)
			prep = Vector3(-.08,.04,-.08)
			thrust = prep + Vector3(.01,.02,.06)
	var t := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	timeline = t
	t.set_trans(Tween.TRANS_SINE)
	_key(t,wind,prep,seconds*first*.68)
	if arrow:
		t.parallel().tween_method(func(v:float): _string_pose(v,true),0.0,1.0,seconds*first*.68)
	_key(t,end,thrust,seconds*first*.32)
	if lash:
		t.parallel().tween_method(func(v:float): lash.set_blend_shape_value(0,v),0.0,1.0,seconds*first*.32)
	if mate:
		t.parallel().tween_property(mate,"rotation_degrees:y",32*hand,seconds*first*.32)
	t.tween_callback(impact.bind(0))
	if arrow:
		t.tween_callback(_string_pose.bind(0,false))
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
	t.tween_callback(_string_pose.bind(0,true))
