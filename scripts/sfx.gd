extends Node
## 音效（自動載入 Sfx）：依 data/sfx.csv 播放，2D／3D 播放器池、變體輪替、音高隨機、
## 每個音效的同時發聲上限與最短間隔。打擊音效分三層：低頻重擊＋中頻碎裂＋高頻風聲。

const POOL_2D := 20
const POOL_3D := 28

var enabled := true
var log_plays := false          # 冒煙測試用：記錄播過的 id
var played: Array = []
var _p2: Array[AudioStreamPlayer] = []
var _p3: Array[AudioStreamPlayer3D] = []
var _streams := {}              # id -> Array[AudioStream]
var _last_variant := {}
var _last_ms := {}
var _voices := {}               # id -> Array[player]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_p2.append(p)
	for i in POOL_3D:
		var q := AudioStreamPlayer3D.new()
		q.bus = "SFX"
		q.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		q.unit_size = 5.0
		q.panning_strength = 0.8
		add_child(q)
		_p3.append(q)
	get_tree().node_added.connect(_on_node_added)


# ------------------------------------------------------------------ 載入
func streams(id: String) -> Array:
	if _streams.has(id):
		return _streams[id]
	var out: Array = []
	var row: Dictionary = Data.sfx.get(id, {})
	if not row.is_empty():
		var src: String = row.source if String(row.source) != "" else id
		var n := int(Data.sfx[src].variants)
		for k in n:
			var s = load("res://assets/audio/sfx/%s_%d.wav" % [src, k + 1])
			if s:
				out.append(s)
	_streams[id] = out
	return out


# ------------------------------------------------------------------ 播放
func play(id: String, pos := Vector3.INF, vol_db := 0.0, pitch := 1.0):
	if not enabled:
		return null
	var row: Dictionary = Data.sfx.get(id, {})
	if row.is_empty():
		push_error("sfx.csv 沒有音效：" + id)
		return null
	var now := Time.get_ticks_msec()
	if now - int(_last_ms.get(id, -100000)) < int(row.min_gap_ms):
		return null
	var list := streams(id)
	if list.is_empty():
		return null
	var k := randi() % list.size()
	if list.size() > 1 and k == int(_last_variant.get(id, -1)):
		k = (k + 1) % list.size()
	_last_variant[id] = k
	_last_ms[id] = now
	var voices: Array = _voices.get(id, []).filter(func(v): return is_instance_valid(v) and v.playing)
	if voices.size() >= int(row.max_voices):
		voices[0].stop()
		voices.pop_front()
	var positional := int(row.positional) == 1 and pos.is_finite()
	var p = _take(_p3 if positional else _p2)
	p.stream = list[k]
	var pv := float(row.pitch_var)
	p.pitch_scale = maxf(0.05, float(row.pitch) * pitch * (1.0 + randf_range(-pv, pv)))
	p.volume_db = float(row.volume_db) + vol_db
	if positional:
		p.global_position = pos
		p.max_distance = float(row.max_distance_m)
	p.play()
	voices.append(p)
	_voices[id] = voices
	if log_plays:
		played.append(id)
	return p


func _take(pool: Array):
	for p in pool:
		if not p.playing:
			return p
	var oldest = pool[0]
	for p in pool:
		if p.get_playback_position() > oldest.get_playback_position():
			oldest = p
	oldest.stop()
	return oldest


## 分層打擊：weight 是武器權重（輕 0.65、一般 1、重 1.8），metal＝打在盾牌／鎧甲上
func hit(weight := 1.0, crit := false, kill := false, metal := false) -> void:
	var heavy := clampf((weight - 0.65) / 1.15, 0.0, 1.0)
	play("hit_low", Vector3.INF, lerpf(-4.0, 2.0, heavy), lerpf(1.08, 0.86, heavy))
	play("hit_mid_metal" if metal else "hit_mid_flesh", Vector3.INF, lerpf(-1.0, 1.0, heavy), lerpf(1.05, 0.92, heavy))
	play("hit_high", Vector3.INF, lerpf(0.0, -3.0, heavy))
	if crit:
		play("crit_sting")
	if kill:
		play("kill_boom", Vector3.INF, 0.0, lerpf(1.05, 0.9, heavy))


# ------------------------------------------------------------------ 所有按鈕自動掛上介面音效
func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.has_meta("sfx"):
		n.set_meta("sfx", true)
		n.pressed.connect(func(): play("ui_click"))
		n.mouse_entered.connect(func():
			if not n.disabled:
				play("ui_hover"))
