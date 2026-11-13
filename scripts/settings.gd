extends Node
## 遊戲設定（自動載入 Settings）：音量、滑鼠靈敏度、打擊感開關、全螢幕。
## 預設值與範圍在 data/settings_config.csv；玩家改過的值存在 user://settings.cfg。

signal changed(key: String)

const PATH := "user://settings.cfg"
const BUSES := {"music_volume": "Music", "sfx_volume": "SFX"}

var values := {}
var save_enabled := true      # 冒煙測試會關掉，避免寫入玩家的設定檔


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	for key in Data.settings_order:
		values[key] = float(Data.settings_cfg[key].default)
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for key in values:
			if cf.has_section_key("settings", key):
				values[key] = clampf(float(cf.get_value("settings", key)), lo(key), hi(key))
	for key in values:
		_apply(key)


func lo(key: String) -> float:
	return float(Data.settings_cfg[key].min)


func hi(key: String) -> float:
	return float(Data.settings_cfg[key].max)


func step(key: String) -> float:
	return float(Data.settings_cfg[key].step)


func is_toggle(key: String) -> bool:
	return lo(key) == 0.0 and hi(key) == 1.0 and step(key) == 1.0


func get_value(key: String) -> float:
	return float(values.get(key, 0.0))


func on(key: String) -> bool:
	return get_value(key) >= 0.5


func set_value(key: String, v: float) -> void:
	v = clampf(snappedf(v, step(key)), lo(key), hi(key))
	if is_equal_approx(get_value(key), v):
		return
	values[key] = v
	_apply(key)
	changed.emit(key)
	save()


func reset_defaults() -> void:
	for key in Data.settings_order:
		set_value(key, float(Data.settings_cfg[key].default))


func save() -> void:
	if not save_enabled:
		return
	var cf := ConfigFile.new()
	for key in values:
		cf.set_value("settings", key, values[key])
	cf.save(PATH)


static func to_db(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v)


func _apply(key: String) -> void:
	match key:
		"master_volume":
			AudioServer.set_bus_volume_db(0, to_db(get_value(key)))
			AudioServer.set_bus_mute(0, get_value(key) <= 0.001)
		"music_volume", "sfx_volume":
			var i := AudioServer.get_bus_index(BUSES[key])
			AudioServer.set_bus_volume_db(i, to_db(get_value(key)))
			AudioServer.set_bus_mute(i, get_value(key) <= 0.001)
		"fullscreen":
			if DisplayServer.get_name() != "headless":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on(key) else DisplayServer.WINDOW_MODE_WINDOWED)
