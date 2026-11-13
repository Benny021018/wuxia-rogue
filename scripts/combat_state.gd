class_name CombatState
extends RefCounted
## 角色戰鬥狀態（玩家與敵人共用）。六種狀態：
##   正常　　可操控
##   受擊　　硬直時間內無法操控
##   倒地　　無法操控；再被打到就浮空；時間到沒被打 → 起身無敵 → 正常
##   霸體　　照樣受傷、吃頓幀，但不進入受擊；可操控。帶「破霸體」的招式才打得斷
##   無敵　　可操控，打不到
##   浮空　　無法操控；被打會再往上彈（逐次衰減）；碰到地板 → 起身無敵 → 正常
## 數值在 data/combat_state_config.csv；每一下攻擊的硬直、浮空高度、是否浮空、
## 是否破霸體、是否擊倒在 data/move_hits.csv。
## 這個類別只管狀態與計時；位移（浮空的垂直速度）由擁有者依 apply_hit() 的結果套用。

signal changed(from: int, to: int)

enum S { NORMAL, HIT, DOWN, ARMOR, INVINCIBLE, AIR }
const NAMES := ["正常", "受擊", "倒地", "霸體", "無敵", "浮空"]

var base := S.NORMAL          # 只會是 NORMAL、HIT、DOWN、AIR
var t := 0.0                  # 受擊／倒地剩餘時間，或浮空已經過的時間
var inv_t := 0.0              # 無敵剩餘時間
var armor_t := 0.0            # 招式或增益給的霸體剩餘時間
var armor_always := false     # 常駐霸體（精英、首領）
var armor_broken_t := 0.0     # 常駐霸體被破除後的空窗
var hitstun_mult := 1.0       # 硬直倍率（精英、首領較短）
var juggle := 0               # 這次浮空已經被追打幾下
var _last := S.NORMAL


static func cfg(key: String) -> float:
	return float(Data.combat_state.get(key, 0.0))


func has_armor() -> bool:
	return armor_t > 0.0 or (armor_always and armor_broken_t <= 0.0)


## 對外的六選一狀態
func state() -> int:
	if inv_t > 0.0 and base == S.NORMAL:
		return S.INVINCIBLE
	if base == S.NORMAL and has_armor():
		return S.ARMOR
	return base


func state_name() -> String:
	return NAMES[state()]


func can_act() -> bool:
	return base == S.NORMAL


func hittable() -> bool:
	return inv_t <= 0.0


func give_armor(sec: float) -> void:
	armor_t = maxf(armor_t, sec)
	_emit()


func give_invincible(sec: float) -> void:
	inv_t = maxf(inv_t, sec)
	_emit()


## 套用一下攻擊。hit 來自 move_hits.csv（hitstun_s、launch、launch_h_m、break_armor、knockdown）。
## 回傳 {taken, absorbed, launch_v, state}：
##   taken     有沒有打中（無敵時 false，不受傷）
##   absorbed  被霸體吃掉（受傷但不改變狀態）
##   launch_v  > 0 表示擁有者要把垂直速度設成這個值（公尺／秒）
func apply_hit(hit: Dictionary) -> Dictionary:
	var out := {"taken": false, "absorbed": false, "launch_v": 0.0, "state": state()}
	if not hittable():
		return out
	out.taken = true
	var launch := int(hit.get("launch", 0)) == 1
	var h := float(hit.get("launch_h_m", 0.0))
	if base == S.DOWN:
		# 倒地被打 → 浮空
		out.launch_v = _launch(maxf(h if launch else 0.0, cfg("down_hit_launch_h_m")))
	elif base == S.AIR:
		# 浮空追打：往上彈，高度逐次衰減
		juggle += 1
		var pop := (h if launch else cfg("air_hit_pop_h_m")) * pow(cfg("juggle_decay"), juggle)
		if pop >= cfg("juggle_min_h_m"):
			out.launch_v = _launch(pop, false)
	else:
		if has_armor():
			if int(hit.get("break_armor", 0)) != 1:
				out.absorbed = true
				out.state = state()
				return out
			armor_t = 0.0
			if armor_always:
				armor_broken_t = cfg("armor_break_s")
		if launch and h > 0.0:
			out.launch_v = _launch(h)
		elif int(hit.get("knockdown", 0)) == 1:
			base = S.DOWN
			t = cfg("hit_down_time_s")
		else:
			var stun := float(hit.get("hitstun_s", 0.0)) * hitstun_mult
			if stun > 0.0:
				base = S.HIT
				t = maxf(t if base == S.HIT else 0.0, stun)
	_emit()
	out.state = state()
	return out


func _launch(height: float, reset := true) -> float:
	if reset or base != S.AIR:
		juggle = 0 if base != S.AIR else juggle
	base = S.AIR
	t = 0.0
	return sqrt(2.0 * cfg("air_gravity") * height)


## 每幀呼叫。on_floor：擁有者目前是否站在地上。
func tick(delta: float, on_floor: bool) -> void:
	inv_t = maxf(0.0, inv_t - delta)
	armor_t = maxf(0.0, armor_t - delta)
	armor_broken_t = maxf(0.0, armor_broken_t - delta)
	match base:
		S.HIT:
			t -= delta
			if t <= 0.0:
				base = S.NORMAL
		S.DOWN:
			t -= delta
			if t <= 0.0:
				_get_up()
		S.AIR:
			t += delta
			if on_floor and t >= cfg("air_min_time_s"):
				_get_up()
	_emit()


func _get_up() -> void:
	base = S.NORMAL
	t = 0.0
	juggle = 0
	inv_t = maxf(inv_t, cfg("getup_invincible_s"))


func reset() -> void:
	base = S.NORMAL
	t = 0.0
	inv_t = 0.0
	armor_t = 0.0
	armor_broken_t = 0.0
	juggle = 0
	_emit()


func _emit() -> void:
	var s := state()
	if s != _last:
		var old := _last
		_last = s
		changed.emit(old, s)
