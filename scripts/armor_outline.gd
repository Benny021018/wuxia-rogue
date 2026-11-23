class_name ArmorOutline
## 霸體外框（以玩家畫面為準的輪廓線，紅黃漸層來回流動）。
## 外框由八個方向的畫面偏移疊成，數值在 data/feel_config.csv 的 armor_outline_*。
## 所有角色共用同一串材質：玩家的狀態材質自己會寫遮罩，用 passes()；敵人用 with_mask()。

const DIRS := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
		Vector2(0.7071, 0.7071), Vector2(-0.7071, 0.7071), Vector2(0.7071, -0.7071), Vector2(-0.7071, -0.7071)]

static var _passes: ShaderMaterial
static var _masked: ShaderMaterial


## 只有外框（呼叫端的材質要自己在 stencil 寫 1）
static func passes() -> ShaderMaterial:
	if _passes == null:
		var feel: Dictionary = Data.feel
		var px := float(feel.armor_outline_px)
		for d in DIRS:
			var m := ShaderMaterial.new()
			m.shader = preload("res://scripts/fighter_outline.gdshader")
			m.render_priority = 1
			m.set_shader_parameter("offset_px", d * px)
			m.set_shader_parameter("color_a", Color(String(feel.armor_outline_color_a)))
			m.set_shader_parameter("color_b", Color(String(feel.armor_outline_color_b)))
			m.set_shader_parameter("cycle_s", float(feel.armor_outline_cycle_s))
			m.set_shader_parameter("band_px", float(feel.armor_outline_band_px))
			m.set_shader_parameter("sway", float(feel.armor_outline_sway))
			m.next_pass = _passes
			_passes = m
	return _passes


## 遮罩＋外框：掛在敵人的疊加材質後面
static func with_mask() -> ShaderMaterial:
	if _masked == null:
		_masked = ShaderMaterial.new()
		_masked.shader = preload("res://scripts/armor_outline.gdshader")
		_masked.next_pass = passes()
	return _masked
