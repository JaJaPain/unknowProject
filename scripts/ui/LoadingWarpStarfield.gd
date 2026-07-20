extends Control

# Lightweight 2D warp field for the startup screen. Each star moves away from
# the screen centre, making the loading copy feel like the vanishing point.
const STAR_COUNT := 42
const MAX_ACTIVE_STARS := 7
const MIN_SPEED := 0.72
const MAX_SPEED := 1.20

var _stars: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 40319
	for star_index in range(STAR_COUNT):
		_stars.append(_new_star(true, star_index < 4))
	queue_redraw()


func _process(delta: float) -> void:
	var active_count := 0
	for star in _stars:
		if bool(star["active"]):
			active_count += 1
	for index in _stars.size():
		var star: Dictionary = _stars[index]
		if bool(star["active"]):
			star["depth"] = float(star["depth"]) + float(star["speed"]) * delta
			if float(star["depth"]) > 1.08:
				star = _new_star(false)
				active_count -= 1
		else:
			star["delay"] = float(star["delay"]) - delta
			if float(star["delay"]) <= 0.0 and active_count < MAX_ACTIVE_STARS:
				star["active"] = true
				star["depth"] = _rng.randf_range(0.10, 0.18)
				active_count += 1
		_stars[index] = star
	queue_redraw()


func _new_star(initial: bool, active: bool = false) -> Dictionary:
	var angle := _rng.randf_range(0.0, TAU)
	return {
		"direction": Vector2(cos(angle), sin(angle)),
		"depth": _rng.randf_range(0.18, 0.72) if initial and active else 0.0,
		"speed": _rng.randf_range(MIN_SPEED, MAX_SPEED),
		"brightness": _rng.randf_range(0.42, 0.86),
		"active": active,
		"delay": _rng.randf_range(0.12, 1.35),
	}


func _draw() -> void:
	# Viewport size is used deliberately: this control lives inside a styled
	# Panel, whose inherited content rectangle is smaller than the full window.
	# The vanishing point must stay under the centred loading copy.
	var viewport_size := get_viewport_rect().size
	var centre := viewport_size * 0.5
	var radius := viewport_size.length() * 0.70
	for star in _stars:
		if not bool(star["active"]):
			continue
		var depth := float(star["depth"])
		# Keep the immediate centre calm for readability. The streak becomes
		# visible as it accelerates outward across one side of the screen.
		var previous_depth := maxf(0.15, depth - float(star["speed"]) * 0.11)
		var direction: Vector2 = star["direction"]
		var brightness := float(star["brightness"])
		var alpha := brightness * lerpf(0.26, 0.86, depth)
		var color := Color(0.54, 0.84, 1.0, alpha)
		var start := centre + direction * radius * previous_depth * previous_depth
		var finish := centre + direction * radius * depth * depth
		draw_line(start, finish, color, lerpf(0.8, 2.0, depth), true)
