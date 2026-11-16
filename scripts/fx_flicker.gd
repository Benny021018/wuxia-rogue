extends OmniLight3D
## 火盆火光閃動

var _base := 0.0
var _t := 0.0

func _ready() -> void:
	_base = light_energy
	_t = randf() * 10.0

func _process(delta: float) -> void:
	_t += delta
	light_energy = _base * (0.85 + 0.15 * sin(_t * 13.0) * sin(_t * 7.3 + 1.0))
