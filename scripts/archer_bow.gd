extends Node3D
## 左手握弓、右手扣弦；箭尾為局部原點，箭頭朝 -Z。
const RELEASE := 1.15
const FINISH := 1.80
const LENGTH := 0.76
var skeleton: Skeleton3D
var hands: Array[int] = []
var limbs: Array[MeshInstance3D] = []
var strings: Array[MeshInstance3D] = []
var arrow: Node3D

static func rod(radius: float, end_radius: float, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.height = 1
	cylinder.radial_segments = 6
	cylinder.rings = 0
	cylinder.bottom_radius = radius
	cylinder.top_radius = end_radius
	m.mesh = cylinder
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	m.material_override = mat
	return m

static func span(m: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var v := b-a
	m.transform = Transform3D(Basis(Quaternion(Vector3.UP, v.normalized())).scaled_local(Vector3(1,v.length(),1)), (a+b)*0.5)

static func make_arrow() -> Node3D:
	var root := Node3D.new()
	var shaft := rod(.012,.012,Color("#cda56b"))
	var tip := rod(.028,0,Color("#b7c4cf"))
	root.add_child(shaft)
	root.add_child(tip)
	span(shaft, Vector3.ZERO, Vector3.FORWARD*(LENGTH-.075))
	span(tip, Vector3.FORWARD*(LENGTH-.075), Vector3.FORWARD*LENGTH)
	for i in 3:
		var feather := MeshInstance3D.new()
		var fin := PrismMesh.new()
		fin.size = Vector3(.033,.086,.006)
		feather.mesh = fin
		var angle := i*TAU/3
		feather.rotation = Vector3(PI/2,0,angle)
		feather.position = Vector3(.017*cos(angle),.017*sin(angle),-.06)
		root.add_child(feather)
	return root

func bind(skel: Skeleton3D) -> void:
	skeleton = skel
	for hand in ["LeftHand","RightHand"]:
		hands.append(skel.find_bone(hand))
	for side in 2:
		for i in 4:
			var widths := [.028,.024,.019,.012,.007]
			var stick := rod(widths[i],widths[i+1],Color("#ab7946") if i else Color("#60432d"))
			add_child(stick)
			limbs.append(stick)
		var string := rod(.005,.005,Color("#e6d8b8"))
		add_child(string)
		strings.append(string)
	arrow = make_arrow()
	add_child(arrow)

func palm(i: int) -> Vector3:
	return to_local(skeleton.global_transform * skeleton.get_bone_global_pose(hands[i]) * Vector3(0,.065,0))

func pose(t: float, target: Vector3) -> void:
	var grip := palm(0)
	var hand := palm(1)
	var aim := (to_local(target)-grip).normalized()
	var back := -aim
	var up := Vector3(.11,1,0).slide(aim).normalized()
	var relaxed := grip+back*.14
	var contact := smoothstep(.12,.26,t) if t <= RELEASE else 1.0-smoothstep(RELEASE,RELEASE+.045,t)
	var nock := relaxed.lerp(hand,contact)
	var tension := clampf(((nock-grip).dot(back)-.14)/.44,0,1)
	for side in 2:
		var vertical := up * (-1.0 if side == 0 else 1.0)
		var path := [grip, grip+vertical*.13, grip+vertical*.31+back*(.02+.035*tension), grip+vertical*(.48-.035*tension)+back*(.12+.075*tension), grip+vertical*(.56-.045*tension)+back*(.14+.12*tension)]
		for i in 4:
			span(limbs[side*4+i],path[i],path[i+1])
		span(strings[side],path[4],nock)
	arrow.visible = t >= .22 and t <= RELEASE
	arrow.position = nock
	arrow.basis = Basis.looking_at((to_local(target)-nock).normalized(),Vector3.UP)

func tip_position() -> Vector3:
	return arrow.to_global(Vector3.FORWARD*LENGTH)
