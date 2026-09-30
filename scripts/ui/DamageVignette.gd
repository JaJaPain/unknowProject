extends ColorRect

## The screen edges flash when the ship is hit: red for hull damage (scaled by
## how hard), a faint blue for shield hits; while the hull is under 30% a slow
## red pulse stays (next_level_plan P2). Mouse-transparent, over the HUD.

const LOW_HULL := 0.3

var _flash := 0.0
var _tint := Color(0.9, 0.08, 0.05)
var _t := 0.0
var _mat: ShaderMaterial


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(1, 1, 1, 1)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/damage_vignette.gdshader")
	material = _mat


func hit(fraction: float, shield: bool) -> void:
	var strength := clampf(0.3 + fraction * 2.0, 0.3, 0.8) if not shield else 0.25
	if strength >= _flash:
		_tint = Color(0.3, 0.75, 1.0) if shield else Color(0.9, 0.08, 0.05)
	_flash = maxf(_flash, strength)


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta * 1.8)
	var low := 0.0
	var ship = GlobalState.player
	if ship != null and is_instance_valid(ship) and not bool(ship.get("is_docked") == true):
		var max_h := float(ship.get("max_health")) if ship.get("max_health") != null else 100.0
		var h := float(ship.get("health")) if ship.get("health") != null else max_h
		if max_h > 0.0 and h > 0.0 and h / max_h < LOW_HULL:
			low = 0.18 + 0.14 * (0.5 + 0.5 * sin(_t * 3.2))
	var tint := _tint if _flash > low else Color(0.9, 0.08, 0.05)
	_mat.set_shader_parameter("tint", tint)
	_mat.set_shader_parameter("intensity", maxf(_flash, low))
	visible = _flash > 0.01 or low > 0.0
