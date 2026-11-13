extends Node
## 配樂（自動載入 Music）：依 data/music.csv 播放，兩個播放器交叉淡入淡出。
## key 是 "menu" 或地圖 id；沒有設定的 key 會把目前的音樂淡出。

var current := ""
var players: Array[AudioStreamPlayer] = []
var _active := 0
var _tweens: Array = [null, null]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		p.bus = "Music"
		add_child(p)
		players.append(p)


func active_player() -> AudioStreamPlayer:
	return players[_active]


func play(key: String) -> void:
	if key == current:
		return
	current = key
	var fade := 1.5
	var old := players[_active]
	if not Data.music.has(key):
		_fade(_active, -80.0, fade, true)
		return
	var row: Dictionary = Data.music[key]
	fade = float(row.fade_s)
	var stream = load(row.file)
	if stream == null:
		push_error("找不到配樂：" + str(row.file))
		return
	if stream is AudioStreamOggVorbis:
		stream.loop = true
		stream.loop_offset = float(row.loop_offset_s)
	_active = 1 - _active
	var p := players[_active]
	p.stream = stream
	p.volume_db = -40.0
	p.play()
	_fade(_active, float(row.volume_db), fade, false)
	if old.playing:
		_fade(1 - _active, -80.0, fade, true)


func _fade(i: int, to_db: float, secs: float, stop_after: bool) -> void:
	if _tweens[i]:
		_tweens[i].kill()
	var t := create_tween()
	t.tween_property(players[i], "volume_db", to_db, secs)
	if stop_after:
		t.tween_callback(players[i].stop)
	_tweens[i] = t
