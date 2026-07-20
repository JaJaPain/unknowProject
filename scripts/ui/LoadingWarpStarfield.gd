extends Control

# A side-window starfield for the startup screen. The ship travels forward, but
# the player is looking across the motion: bright nearby stars sweep past like
# roadside lamps, while slower distant stars provide the outer depth.
const NEAR_STAR_COUNT := 11
const MID_STAR_COUNT := 13
const FAR_STAR_COUNT := 18

var _near_stars: Array[Dictionary] = []
var _mid_stars: Array[Dictionary] = []
var _far_stars: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 40319
	_seed_layer(_near_stars, NEAR_STAR_COUNT, "near")
	_seed_layer(_mid_stars, MID_STAR_COUNT, "mid")
	_seed_layer(_far_stars, FAR_STAR_COUNT, "far")
	queue_redraw()


func _process(delta: float) -> void:
	_move_layer(_far_stars, delta, "far")
	_move_layer(_mid_stars, delta, "mid")
	_move_layer(_near_stars, delta, "near")
	queue_redraw()


func _seed_layer(stars: Array[Dictionary], count: int, layer: String) -> void:
	for star_index in range(count):
		stars.append(_new_star(layer, true))


func _new_star(layer: String, initially_visible: bool = false) -> Dictionary:
	var viewport_size := get_viewport_rect().size
	var moving_left := _rng.randf() < 0.76
	var direction := -1.0 if moving_left else 1.0
	var x := _rng.randf_range(0.0, viewport_size.x) if initially_visible \
		else (-50.0 if direction > 0.0 else viewport_size.x + 50.0)
	var y := _rng.randf_range(28.0, maxf(60.0, viewport_size.y - 28.0))
	var speed := 50.0
	var length := 1.0
	var alpha := 0.25
	var width := 0.7
	match layer:
		"near":
			speed = _rng.randf_range(260.0, 390.0)
			length = _rng.randf_range(24.0, 60.0)
			alpha = _rng.randf_range(0.46, 0.86)
			width = _rng.randf_range(1.1, 2.0)
		"mid":
			speed = _rng.randf_range(120.0, 205.0)
			length = _rng.randf_range(7.0, 19.0)
			alpha = _rng.randf_range(0.28, 0.62)
			width = _rng.randf_range(0.8, 1.35)
		"far":
			speed = _rng.randf_range(35.0, 78.0)
			length = _rng.randf_range(1.0, 4.0)
			alpha = _rng.randf_range(0.13, 0.38)
			width = _rng.randf_range(0.55, 0.9)
	return {
		"position": Vector2(x, y),
		"direction": direction,
		"speed": speed,
		"length": length,
		"alpha": alpha,
		"width": width,
		"drift": _rng.randf_range(-0.035, 0.035),
	}


func _move_layer(stars: Array[Dictionary], delta: float, layer: String) -> void:
	var viewport_size := get_viewport_rect().size
	for index in stars.size():
		var star: Dictionary = stars[index]
		var position: Vector2 = star["position"]
		position.x += float(star["direction"]) * float(star["speed"]) * delta
		position.y += float(star["drift"]) * float(star["speed"]) * delta
		star["position"] = position
		if position.x < -80.0 or position.x > viewport_size.x + 80.0 \
				or position.y < -30.0 or position.y > viewport_size.y + 30.0:
			star = _new_star(layer)
		stars[index] = star


func _draw() -> void:
	_draw_layer(_far_stars, Color(0.48, 0.70, 0.92))
	_draw_layer(_mid_stars, Color(0.56, 0.80, 1.0))
	_draw_layer(_near_stars, Color(0.68, 0.90, 1.0))


func _draw_layer(stars: Array[Dictionary], base_color: Color) -> void:
	for star in stars:
		var position: Vector2 = star["position"]
		var direction := float(star["direction"])
		var length := float(star["length"])
		var color := base_color
		color.a = float(star["alpha"])
		# Each trail points behind its motion, as if it has just swept past the
		# player. No star originates from the centred loading copy.
		var tail := position - Vector2(direction * length, 0.0)
		draw_line(tail, position, color, float(star["width"]), true)
