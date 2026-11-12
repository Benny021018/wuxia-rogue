extends Node3D
## 支援手的局部原點是拇指與食指夾住箭尾的位置。
const Shapes := preload("res://scripts/archer_bow.gd")
var sleeve: MeshInstance3D
var wrist: MeshInstance3D
var side: float

func setup(weapon_side: float) -> void:
	side = -weapon_side
	sleeve = Shapes.rod(.068,.044,Color("#393044"))
	wrist = Shapes.rod(.045,.036,Color("#895f45"))
	get_parent().add_child(sleeve)
	get_parent().add_child(wrist)
	var palm := FX.sphere(.046,Color("#78503c"))
	add_child(palm)
	palm.position = Vector3(side*.038,-.016,.026)
	palm.scale = Vector3(.87,.72,1.20)
	for i in 4:
		var knuckle := Vector3(side*.048,-.003-i*.012,.008+i*.004)
		var joint := Vector3(side*.016,.016-i*.013,-.018+i*.007)
		_digit(knuckle,joint,.012)
		_digit(joint,Vector3(side*.003,.003-i*.011,-.012+i*.008),.010)
	_digit(Vector3(side*.040,-.025,.008),Vector3(side*.009,-.014,-.013),.014)

func _digit(start: Vector3, end: Vector3, radius: float) -> void:
	var joint := Shapes.rod(radius,radius*.84,Color("#bb8664"))
	add_child(joint)
	Shapes.span(joint,start,end)

func place(grasp: Vector3, elbow: Vector3, shown: bool) -> void:
	visible = shown
	sleeve.visible = shown
	wrist.visible = shown
	if shown:
		position = grasp
		var cuff := grasp + Vector3(side*.065,-.045,.085)
		Shapes.span(sleeve,elbow,cuff)
		Shapes.span(wrist,cuff,grasp+Vector3(side*.040,-.02,.038))
