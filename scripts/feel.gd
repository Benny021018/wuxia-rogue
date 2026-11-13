extends Node

signal player_hurt(strength: float)     # HUD 接收：畫面邊緣紅光

## 打擊感（自動載入 Feel）：頓幀與畫面震動。數值在 data/feel_config.csv，開關在設定。
## 頓幀用 Engine.time_scale 短暫壓低時間；震動用 trauma 模型（強度＝trauma²），
## 兩者都以真實時間計算，頓幀期間震動照常衰減。

var trauma := 0.0
var _stop_until := 0
var _last_us := 0
var _seed := 0.0
var _cam: Camera3D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_us = Time.get_ticks_usec()


func k(key: String) -> float:
	return float(Data.feel.get(key, 0.0))


## 頓幀：秒數為真實時間；多段命中只延長到上限
func hitstop(sec: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	if sec <= 0.0 or not Settings.on("hitstop") or get_tree().paused:
		return
	var now := Time.get_ticks_msec()
	var end := now + int(minf(sec, k("hitstop_max_s")) * 1000.0)
	if now < _stop_until:
		end = mini(maxi(end, _stop_until + int(sec * 400.0)), now + int(k("hitstop_max_s") * 1000.0))
	_stop_until = maxi(_stop_until, end)
	Engine.time_scale = k("hitstop_scale")


func stopping() -> bool:
	return Engine.time_scale < 1.0


## 震動：amount 0～1，疊加後上限 1
func shake(amount: float) -> void:
	trauma = minf(1.0, trauma + amount * Settings.get_value("screen_shake"))


## 依命中結果決定頓幀與震動
func impact(weight: float, crit: bool, kill: bool) -> void:
	var stop := k("hitstop_light_s")
	var sh := k("shake_hit")
	if weight >= 1.5:
		stop = k("hitstop_heavy_s")
		sh = k("shake_heavy")
	if crit:
		stop = maxf(stop, k("hitstop_crit_s"))
		sh = maxf(sh, k("shake_crit"))
	if kill:
		stop = maxf(stop, k("hitstop_kill_s"))
		sh = maxf(sh, k("shake_kill"))
	hitstop(stop)
	shake(sh)


func reset() -> void:
	trauma = 0.0
	_stop_until = 0
	Engine.time_scale = 1.0
	if is_instance_valid(_cam):
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0


func _process(_delta: float) -> void:
	var now_us := Time.get_ticks_usec()
	var real := minf(0.1, (now_us - _last_us) / 1000000.0)
	_last_us = now_us
	if Engine.time_scale < 1.0 and (Time.get_ticks_msec() >= _stop_until or get_tree().paused):
		Engine.time_scale = 1.0
	var cam := get_viewport().get_camera_3d()
	if cam != _cam:
		if is_instance_valid(_cam):
			_cam.h_offset = 0.0
			_cam.v_offset = 0.0
		_cam = cam
	if not is_instance_valid(cam):
		return
	trauma = maxf(0.0, trauma - k("shake_decay") * real)
	var s := trauma * trauma
	_seed += real * 38.0
	var off := k("shake_max_offset") * s
	cam.h_offset = off * _n(_seed, 1.7)
	cam.v_offset = off * _n(_seed, 9.3)
	cam.rotation.z = deg_to_rad(k("shake_max_roll_deg")) * s * _n(_seed, 4.1)


func _n(t: float, phase: float) -> float:
	## 平滑的偽隨機（幾個不同頻率的正弦疊加），介於 −1～1
	return (sin(t * 1.0 + phase) * 0.5 + sin(t * 2.3 + phase * 2.0) * 0.3 + sin(t * 4.7 + phase * 3.0) * 0.2)
