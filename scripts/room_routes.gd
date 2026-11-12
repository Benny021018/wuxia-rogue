extends RefCounted
## 每個房間依碰撞物建立二維走道；同體型敵人共用 A* 格網。
var bounds: Rect2
var blocks: Array[Rect2] = []
var grids := {}

func _init(floor_bounds: Rect2) -> void:
	bounds = floor_bounds

func clear(a: Vector2, b: Vector2, radius: float) -> bool:
	for block in blocks:
		var r := block.grow(radius)
		if r.has_point(a) and not r.has_point(b):
			# 隊友可能把敵人推進安全邊距；允許從最近的一面離開。
			var gaps := [a.x-r.position.x,r.end.x-a.x,a.y-r.position.y,r.end.y-a.y]
			var outward: Vector2 = [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN][gaps.find(gaps.min())]
			if (b-a).dot(outward) > 0:
				continue
		var slab := AABB(Vector3(r.position.x,-1,r.position.y), Vector3(r.size.x,2,r.size.y))
		if slab.intersects_segment(Vector3(a.x,0,a.y),Vector3(b.x,0,b.y)) != null:
			return false
	return true

func _grid(radius: float) -> AStarGrid2D:
	if grids.has(radius):
		return grids[radius]
	var grid := AStarGrid2D.new()
	var inner := bounds.grow(-radius)
	var lo := Vector2i(inner.position.ceil())
	var hi := Vector2i(inner.end.floor())
	grid.region = Rect2i(lo,hi-lo+Vector2i.ONE)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for block in blocks:
		var r := block.grow(radius)
		var a := Vector2i(r.position.ceil())
		var b := Vector2i(r.end.floor())
		var cells := Rect2i(a,b-a+Vector2i.ONE).intersection(grid.region)
		if cells.has_area():
			grid.fill_solid_region(cells)
	grids[radius] = grid
	return grid

func _open_cell(grid: AStarGrid2D, pos: Vector2) -> Vector2i:
	var center := Vector2i(pos.round()).clamp(grid.region.position,grid.region.end-Vector2i.ONE)
	if not grid.is_point_solid(center):
		return center
	# 目標可能站在高台上，改走到最近的可通行邊緣。
	var best := center
	var distance := INF
	for x in range(grid.region.position.x,grid.region.end.x):
		for y in range(grid.region.position.y,grid.region.end.y):
			var cell := Vector2i(x,y)
			var d := pos.distance_squared_to(Vector2(cell))
			if d < distance and not grid.is_point_solid(cell):
				best = cell
				distance = d
	return best

func route(a: Vector2, b: Vector2, radius: float) -> PackedVector2Array:
	var grid := _grid(radius)
	return grid.get_point_path(_open_cell(grid,a),_open_cell(grid,b),true)
