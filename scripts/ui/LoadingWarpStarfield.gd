extends Control

# Lightweight 2D warp field for the startup screen. Each star moves away from
# the screen centre, making the loading copy feel like the vanishing point.
const STAR_COUNT := 130
const MIN_SPEED := 0.36
const MAX_SPEED := 0.94

var _stars: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 40319
	for star_index in range(STAR_COUNT):
		_stars.append(_new_star(true))
	queue_redraw()


func _process(delta: float) -> void:
	for index in _stars.size():
		var star: Dictionary = _stars[index]
		star["depth"] = float(star["depth"]) + float(star["speed"]) * delta
		if float(star["depth"]) > 1.08:
			star = _new_star(false)
		_stars[index] = star
	queue_redraw()


func _new_star(initial: bool) -> Dictionary:
	var angle := _rng.randf_range(0.0, TAU)
	return {
		"direction": Vector2(cos(angle), sin(angle)),
		"depth": _rng.randf_range(0.04, 1.0) if initial else _rng.randf_range(0.01, 0.10),
		"speed": _rng.randf_range(MIN_SPEED, MAX_SPEED),
		"brightness": _rng.randf_range(0.24, 0.78),
	}


func _draw() -> void:
	var centre := size * 0.5
	var radius := size.length() * 0.62
	for star in _stars:
		var depth := float(star["depth"])
		var previous_depth := maxf(0.0, depth - float(star["speed"]) * 0.055)
		var direction: Vector2 = star["direction"]
		var brightness := float(star["brightness"])
		var alpha := brightness * lerpf(0.22, 0.92, depth)
		var color := Color(0.54, 0.84, 1.0, alpha)
		var start := centre + direction * radius * previous_depth * previous_depth
		var finish := centre + direction * radius * depth * depth
		draw_line(start, finish, color, lerpf(0.6, 1.8, depth), true)
