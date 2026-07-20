extends Control

# Forward travel seen through three depth bands. The main stars emerge from the
# centred vanishing point like nearby roadside lights. Two outer bands begin
# already far to either side, like house lights beyond the road, and sweep past
# on the same perspective without ever crossing the loading copy.
const ROAD_STAR_COUNT := 11
const OUTER_MID_STAR_COUNT := 18
const OUTER_FAR_STAR_COUNT := 24

var _road_stars: Array[Dictionary] = []
var _outer_mid_stars: Array[Dictionary] = []
var _outer_far_stars: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _vanishing_target: Control = null


func set_vanishing_target(target: Control) -> void:
	_vanishing_target = target


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 40319
	_seed_band(_road_stars, ROAD_STAR_COUNT, "road")
	_seed_band(_outer_mid_stars, OUTER_MID_STAR_COUNT, "outer_mid")
	_seed_band(_outer_far_stars, OUTER_FAR_STAR_COUNT, "outer_far")
	queue_redraw()


func _process(delta: float) -> void:
	_move_band(_road_stars, delta, "road")
	_move_band(_outer_mid_stars, delta, "outer_mid")
	_move_band(_outer_far_stars, delta, "outer_far")
	queue_redraw()


func _seed_band(stars: Array[Dictionary], count: int, band: String) -> void:
	for star_index in range(count):
		stars.append(_new_star(band, true))


func _new_star(band: String, initially_visible: bool = false) -> Dictionary:
	var angle := _rng.randf_range(0.0, TAU)
	var depth_min := 0.04
	var depth_max := 0.36
	var speed := 0.85
	var trail := 0.115
	var alpha := 0.8
	var width := 1.4
	match band:
		"road":
			# Nearby roadside stars are the main motion, emerging near the
			# road's vanishing point and expanding quickly past the player.
			depth_min = 0.05
			depth_max = 0.50 if initially_visible else 0.10
			speed = _rng.randf_range(0.66, 1.08)
			trail = _rng.randf_range(0.08, 0.16)
			alpha = _rng.randf_range(0.46, 0.82)
			width = _rng.randf_range(1.0, 1.9)
		"outer_mid":
			# This ring starts well outside the centre: mid-distance house lights.
			depth_min = 0.37
			depth_max = 0.78
			speed = _rng.randf_range(0.30, 0.52)
			trail = _rng.randf_range(0.026, 0.060)
			alpha = _rng.randf_range(0.25, 0.52)
			width = _rng.randf_range(0.7, 1.15)
		"outer_far":
			# The farthest ring is subtle and slow: lights much farther off-road.
			depth_min = 0.60
			depth_max = 0.98
			speed = _rng.randf_range(0.12, 0.28)
			trail = _rng.randf_range(0.008, 0.026)
			alpha = _rng.randf_range(0.12, 0.32)
			width = _rng.randf_range(0.5, 0.8)
	return {
		"direction": Vector2(cos(angle), sin(angle)),
		"depth": _rng.randf_range(depth_min, depth_max),
		"reset_depth": depth_min,
		"speed": speed,
		"trail": trail,
		"alpha": alpha,
		"width": width,
	}


func _move_band(stars: Array[Dictionary], delta: float, band: String) -> void:
	for index in stars.size():
		var star: Dictionary = stars[index]
		star["depth"] = float(star["depth"]) + float(star["speed"]) * delta
		if float(star["depth"]) > 1.10:
			star = _new_star(band)
		stars[index] = star


func _draw() -> void:
	_draw_band(_outer_far_stars, Color(0.45, 0.68, 0.92))
	_draw_band(_outer_mid_stars, Color(0.52, 0.78, 1.0))
	_draw_band(_road_stars, Color(0.66, 0.91, 1.0))


func _draw_band(stars: Array[Dictionary], base_color: Color) -> void:
	var viewport_size := get_viewport_rect().size
	var centre := viewport_size * 0.5
	if _vanishing_target != null and is_instance_valid(_vanishing_target):
		# Lock the visual origin to the loading bar itself. The bar is deliberately
		# opaque, so the rough first pixels of each streak stay hidden beneath it.
		centre = get_global_transform().affine_inverse() * \
			_vanishing_target.get_global_rect().get_center()
	var radius := viewport_size.length() * 0.70
	for star in stars:
		var depth := float(star["depth"])
		var trail_start := maxf(float(star["reset_depth"]), depth - float(star["trail"]))
		var direction: Vector2 = star["direction"]
		var color := base_color
		color.a = float(star["alpha"]) * lerpf(0.45, 1.0, minf(depth, 1.0))
		var start := centre + direction * radius * trail_start * trail_start
		var finish := centre + direction * radius * depth * depth
		draw_line(start, finish, color, float(star["width"]), true)
