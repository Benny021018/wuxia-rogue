extends Node
## 鎖定目標：中鍵鎖定鏡頭前方的敵人，鏡頭跟著轉、出招朝向目標；
## 甩滑鼠或滾輪換目標；目標死亡自動換下一個；太遠或被擋太久就解除。
## 數值在 data/combat_state_config.csv 的 lock_*。介面見 docs/ui-drafts/19-lock-on.svg。

var p                                   # 玩家
var target = null
var _engaged := false                   # 玩家有開鎖定（目標被釋放後 target 可能變成無效參照）
var _flick := 0.0                       # 鎖定時橫向甩滑鼠的累計量（像素）
var _flick_t := 0.0
var _flick_cd := 0.0
var _blocked_t := 0.0                   # 視線被擋住多久
var marker: Node3D                      # 頭頂菱形＋四角框（跟著目標）
var _diamond: Sprite3D
var _brackets: Sprite3D


func setup(player) -> void:
	p = player
	marker = Node3D.new()
	marker.top_level = true
	marker.visible = false
	p.add_child(marker)
	_diamond = _sprite(_diamond_tex(), 0.0075)
	marker.add_child(_diamond)
	_brackets = _sprite(_bracket_tex(), 0.01)
	marker.add_child(_brackets)


static func cfg(key: String) -> float:
	return CombatState.cfg(key)


func locked() -> bool:
	return target != null and is_instance_valid(target) and not target.dead


func toggle() -> void:
	if locked():
		release()
	else:
		target = pick(null, 0)
		_engaged = target != null
		_blocked_t = 0.0
		if target != null:
			Sfx.play("lock_on")


func release() -> void:
	target = null
	_engaged = false
	marker.visible = false


## 從候選中挑目標。side＝0：鏡頭正前方最近的；±1：從 from 的位置往右／往左找下一個（找不到就繞回另一邊最外側）
func pick(from, side: int):
	var fwd: Vector3 = p.aim_flat()
	var best = null
	var best_score := INF
	var cands: Array = candidates(side != 0)
	if side == 0:
		for e in cands:
			var to: Vector3 = e.global_position - p.global_position
			to.y = 0
			var ang := rad_to_deg(fwd.angle_to(to.normalized())) if to.length() > 0.01 else 0.0
			var score := ang / cfg("lock_cone_deg") + to.length() / cfg("lock_range_m")
			if score < best_score:
				best_score = score
				best = e
		return best
	var base := _bearing(from) if from != null and is_instance_valid(from) else 0.0
	var wrap = null
	var wrap_score := -INF
	for e in cands:
		if e == from:
			continue
		# 往右（side＝1）＝方位角變小；統一換算成「往 side 那邊轉了多少」
		var d := wrapf(base - _bearing(e), -PI, PI) * side
		if d > 0.0 and d < best_score:
			best_score = d
			best = e
		if -d > wrap_score:
			wrap_score = -d
			wrap = e
	return best if best != null else wrap


## 能鎖的敵人：活著、現形、看得到、在距離內；初次鎖定時還要在鏡頭前方的錐形內
func candidates(any_angle := false) -> Array:
	var out: Array = []
	var fwd: Vector3 = p.aim_flat()
	for e in p.targets():
		if not is_instance_valid(e) or e.dead or not e.is_inside_tree():
			continue
		if e.get("_revealed") == false:
			continue
		var to: Vector3 = e.global_position - p.global_position
		to.y = 0
		if to.length() > cfg("lock_range_m"):
			continue
		if not any_angle and to.length() > 0.01 and rad_to_deg(fwd.angle_to(to.normalized())) > cfg("lock_cone_deg"):
			continue
		if not _visible(e):
			continue
		out.append(e)
	return out


func _bearing(e) -> float:
	var to: Vector3 = e.global_position - p.global_position
	return atan2(-to.x, -to.z)


func _visible(e) -> bool:
	if not p.is_inside_tree():
		return true
	var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP * 1.4, e.hit_center(), 1)
	return p.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## 鎖定時橫向的滑鼠移動拿來換目標（一次甩過 lock_flick_px 才算）
func mouse_motion(dx: float) -> void:
	if _flick_cd > 0.0:
		return
	_flick += dx
	_flick_t = cfg("lock_flick_window_s")
	if absf(_flick) >= cfg("lock_flick_px"):
		switch(1 if _flick > 0.0 else -1)
		_flick = 0.0
		_flick_cd = cfg("lock_flick_cd_s")


func switch(side: int) -> void:
	if not locked():
		return
	var n = pick(target, side)
	if n != null and n != target:
		target = n
		_blocked_t = 0.0
		Sfx.play("lock_on")


## 每個物理幀：檢查解除條件、轉鏡頭、更新標記
func update(delta: float) -> void:
	_flick_cd = maxf(0.0, _flick_cd - delta)
	_flick_t -= delta
	if _flick_t <= 0.0:
		_flick = 0.0
	if _engaged and not locked():
		# 目標死了：自動換附近的下一個（不限角度）
		var prev_pos: Vector3 = p.global_position
		target = null
		var cands := candidates(true)
		var best = null
		var bd := INF
		for e in cands:
			var dd: float = e.global_position.distance_to(prev_pos)
			if dd < bd:
				bd = dd
				best = e
		target = best
		_engaged = best != null
		_blocked_t = 0.0
	if not _engaged:
		marker.visible = false
		return
	var to: Vector3 = target.global_position - p.global_position
	to.y = 0
	if to.length() > cfg("lock_break_m"):
		release()
		return
	_blocked_t = 0.0 if _visible(target) else _blocked_t + delta
	if _blocked_t > cfg("lock_los_s"):
		release()
		return
	# 鏡頭：水平轉向目標，俯仰對準目標胸口
	if to.length() > 0.3:
		var want_yaw := atan2(-to.x, -to.z)
		var k := 1.0 - exp(-cfg("lock_cam_turn") * delta)
		p.yaw = lerp_angle(p.yaw, want_yaw, k)
		var c: Vector3 = target.hit_center() - p.pivot.global_position
		var flat := Vector2(c.x, c.z).length()
		var want_pitch := clampf(atan2(c.y, flat) + cfg("lock_pitch_offset"), -1.0, 0.4)
		p.pitch = lerpf(p.pitch, want_pitch, k)
		p.rotation.y = p.yaw
		p.pivot.rotation.x = p.pitch
	# 標記：頭頂菱形＋包住身體的四角框（大小跟著體型）
	var top: float = target.hit_center().y - target.global_position.y
	var h: float = maxf(1.4, top * 2.0)
	if target.get("size") != null:
		h = maxf(h, 2.0 * float(target.size))
	marker.visible = true
	marker.global_position = target.global_position
	var head := h + 0.45
	var tag = target.get("_label")              # 精英、首領頭上有名字：菱形放在名字上面
	if tag != null and is_instance_valid(tag):
		head = maxf(head, tag.position.y + 0.55)
	_diamond.position.y = head
	_brackets.position.y = h * 0.5
	_brackets.pixel_size = h / 256.0 * 1.15
	var pulse := 1.0 + 0.12 * sin(Time.get_ticks_msec() / 130.0)
	_diamond.scale = Vector3.ONE * pulse


## 朝目標的水平方向（沒鎖定時＝鏡頭前方）
func flat_dir() -> Vector3:
	if not locked():
		return p.aim_flat()
	var to: Vector3 = target.global_position - p.global_position
	to.y = 0
	return to.normalized() if to.length() > 0.05 else p.aim_flat()


func _sprite(tex: Texture2D, px: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = px
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.no_depth_test = true
	s.shaded = false
	s.render_priority = 10
	return s


## 菱形：血紅填色＋墨黑描邊，外面一圈骨白細框（照 19 號稿）
static func _diamond_tex() -> Texture2D:
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := n / 2.0
	for y in n:
		for x in n:
			var d := (absf(x + 0.5 - c) + absf(y + 0.5 - c)) / c   # 0（中心）~1（菱形頂點）
			var col := Color(0, 0, 0, 0)
			if d < 0.52:
				col = UIKit.BLOOD
			elif d < 0.62:
				col = UIKit.INK
			elif d > 0.86 and d < 0.93:
				col = Color(UIKit.BONE, 0.85)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## 四角框：血紅的 L 形四角，中間鏤空
static func _bracket_tex() -> Texture2D:
	var w := 180
	var h := 256
	var arm := 34
	var t := 6
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var nx := mini(x, w - 1 - x)
			var ny := mini(y, h - 1 - y)
			var on := (nx < t and ny < arm) or (ny < t and nx < arm)
			var edge := (nx < t + 2 and ny < arm + 2) or (ny < t + 2 and nx < arm + 2)
			img.set_pixel(x, y, UIKit.BLOOD if on else (UIKit.INK if edge else Color(0, 0, 0, 0)))
	return ImageTexture.create_from_image(img)
