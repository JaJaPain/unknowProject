extends CanvasLayer

## The drone maze on screen: first person through the drone's camera, in its
## own small 3D world, with a HUD (countdown, hull, haul, scanner arrow). The
## game is paused while the captain flies the drone (the ship holds station);
## this layer keeps processing.
##
## Controls: W/S or Up/Down throttle, A/D or Left/Right turn, E extract,
## R recall. Emits `finished(outcome, state)` once.

const Maze := preload("res://scripts/story/activities/DroneMazeModel.gd")
const BUMP_SOUND := "res://assets/assets/CombatWheel/soundfxs/hull_impact.wav"
const WALL_HEIGHT := 1.2
const TARGET_COLORS := {"mineral": Color(0.3, 0.95, 1.0), "salvage": Color(1.0, 0.6, 0.2), "recorder": Color(1.0, 0.2, 0.15)}

signal finished(outcome_id: String, state: Dictionary)

var state: Dictionary = {}
var _viewport: SubViewport
var _camera: Camera3D
var _target_nodes: Dictionary = {}
var _hud_time: Label
var _hud_hull: Label
var _hud_haul: Label
var _hud_prompt: Label
var _arrow: Label
var _flash: ColorRect
var _shake := 0.0
var _done := false
var _paused_by_us := false
var _bump_player: AudioStreamPlayer


func begin(seed_value: int, kind: String, with_recorder: bool) -> void:
	state = Maze.start(seed_value, kind, with_recorder)
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_world()
	_build_hud()
	if is_inside_tree() and not get_tree().paused:
		get_tree().paused = true
		_paused_by_us = true
	_sync_camera()


# --- the world ----------------------------------------------------------------

func _build_world() -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.world_3d = World3D.new()
	container.add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.12, 0.12, 0.14)
	env.ambient_light_energy = 0.35
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.02, 0.03)
	env.fog_density = 0.18
	env.glow_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var grid: Array = state["grid"]
	var wall_mat := _wall_material(str(state["kind"]))
	var walls := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(1.0, WALL_HEIGHT, 1.0)
	box.material = wall_mat
	mm.mesh = box
	var tiles: Array[Vector2i] = []
	for y in grid.size():
		for x in str(grid[y]).length():
			if not Maze.is_open(grid, x, y) and _touches_open(grid, x, y):
				tiles.append(Vector2i(x, y))
	mm.instance_count = tiles.size()
	for i in tiles.size():
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(tiles[i].x + 0.5, WALL_HEIGHT * 0.5, tiles[i].y + 0.5)))
	walls.multimesh = mm
	_viewport.add_child(walls)
	var w := float(str(grid[0]).length())
	var h := float(grid.size())
	for y_level in [0.0, WALL_HEIGHT]:
		var plane := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(w, h)
		pm.material = wall_mat
		plane.mesh = pm
		plane.position = Vector3(w * 0.5, y_level, h * 0.5)
		if y_level > 0.0:
			plane.rotation.x = PI  # ceiling faces down
		_viewport.add_child(plane)

	for t in state["targets"]:
		var node := _target_node(str(t["kind"]))
		node.position = Vector3(float(t["tile"][0]) + 0.5, 0.0, float(t["tile"][1]) + 0.5)
		_viewport.add_child(node)
		_target_nodes[str(t["id"])] = node

	_camera = Camera3D.new()
	_camera.fov = 78.0
	_camera.near = 0.05
	_camera.far = 30.0
	_viewport.add_child(_camera)
	_camera.current = true
	var lamp := SpotLight3D.new()
	lamp.spot_range = 7.0
	lamp.spot_angle = 38.0
	lamp.light_energy = 2.6
	lamp.light_color = Color(1.0, 0.95, 0.85)
	lamp.shadow_enabled = true
	_camera.add_child(lamp)
	var glow := OmniLight3D.new()
	glow.omni_range = 1.6
	glow.light_energy = 0.35
	_camera.add_child(glow)


static func _touches_open(grid: Array, x: int, y: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		if Maze.is_open(grid, x + d.x, y + d.y):
			return true
	return false


## Rock for an asteroid, dark plating for a wreck; both from noise, no files.
static func _wall_material(kind: String) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.035 if kind == "asteroid" else 0.08
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	var normal := NoiseTexture2D.new()
	normal.noise = noise
	normal.as_normal_map = true
	normal.seamless = true
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.normal_enabled = true
	mat.normal_texture = normal
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.6, 0.6, 0.6)
	if kind == "asteroid":
		mat.albedo_color = Color(0.45, 0.4, 0.36)
		mat.roughness = 0.95
	else:
		mat.albedo_color = Color(0.3, 0.33, 0.36)
		mat.metallic = 0.7
		mat.roughness = 0.5
	return mat


## A crystal cluster, a salvage crate, or a blinking recorder, built from
## primitive meshes and glowing so the headlight finds them.
static func _target_node(kind: String) -> Node3D:
	var root := Node3D.new()
	var color: Color = TARGET_COLORS.get(kind, Color.WHITE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	if kind == "mineral":
		mat.metallic = 0.3
		mat.roughness = 0.15
		for i in 5:
			var shard := MeshInstance3D.new()
			var prism := CylinderMesh.new()
			prism.top_radius = 0.0
			prism.bottom_radius = 0.06 + 0.03 * (i % 3)
			prism.height = 0.35 + 0.12 * (i % 3)
			prism.radial_segments = 6
			prism.material = mat
			shard.mesh = prism
			var a := TAU * i / 5.0
			shard.position = Vector3(cos(a) * 0.12, prism.height * 0.5, sin(a) * 0.12)
			shard.rotation = Vector3(sin(a) * 0.4, a, cos(a) * 0.4)
			root.add_child(shard)
	else:
		var crate := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3(0.3, 0.22, 0.24) if kind == "recorder" else Vector3(0.4, 0.3, 0.4)
		var body := StandardMaterial3D.new()
		body.albedo_color = Color(0.2, 0.2, 0.22)
		body.metallic = 0.6
		cube.material = body
		crate.mesh = cube
		crate.position.y = cube.size.y * 0.5
		root.add_child(crate)
		var stripe := MeshInstance3D.new()
		var band := BoxMesh.new()
		band.size = Vector3(cube.size.x + 0.01, 0.04, cube.size.z + 0.01)
		band.material = mat
		stripe.mesh = band
		stripe.position.y = cube.size.y * 0.6
		root.add_child(stripe)
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 1.4
	light.light_energy = 0.8
	light.position.y = 0.3
	light.name = "Glow"
	root.add_child(light)
	return root


# --- the HUD ------------------------------------------------------------------

func _build_hud() -> void:
	var hud := Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1.0, 0.1, 0.05, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_flash)
	var top := HBoxContainer.new()
	top.position = Vector2(24, 18)
	top.add_theme_constant_override("separation", 36)
	hud.add_child(top)
	_hud_time = _hud_label(top, 24)
	_hud_hull = _hud_label(top, 24)
	_hud_haul = _hud_label(top, 24)
	_arrow = Label.new()
	_arrow.text = "▲"
	_arrow.add_theme_font_size_override("font_size", 40)
	_arrow.add_theme_color_override("font_color", Color(0.4, 1.0, 0.85, 0.85))
	_arrow.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_arrow.position = Vector2(-14, 70)
	_arrow.pivot_offset = Vector2(14, 26)
	hud.add_child(_arrow)
	_hud_prompt = _hud_label(hud, 22)
	_hud_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hud_prompt.position = Vector2(-160, -120)
	var help := _hud_label(hud, 16)
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(24, -40)
	help.text = "W/S throttle   A/D turn   E extract   R recall the drone"


func _hud_label(parent: Control, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.9))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(label)
	return label


# --- running ------------------------------------------------------------------

func _process(delta: float) -> void:
	if _done or state.is_empty():
		return
	var throttle := _axis(KEY_W, KEY_UP) - _axis(KEY_S, KEY_DOWN)
	var turn := _axis(KEY_D, KEY_RIGHT) - _axis(KEY_A, KEY_LEFT)
	state = Maze.step(state, delta, throttle, turn)
	if bool(state.get("bumped", false)):
		_shake = 0.25
		_flash.color.a = 0.35
		_play_bump()
	_shake = maxf(0.0, _shake - delta)
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 1.2)
	_sync_camera()
	_update_hud()
	if bool(state["done"]):
		_finish()


func _axis(a: Key, b: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b) else 0.0


func _input(event: InputEvent) -> void:
	if _done or not event is InputEventKey:
		return
	var key := event as InputEventKey
	# The drone has the controls; nothing reaches the ship.
	get_viewport().set_input_as_handled()
	if not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_E:
		var before := Maze.extracted_count(state)
		state = Maze.extract(state)
		if Maze.extracted_count(state) > before:
			_hide_extracted()
			if bool(state["done"]):
				_finish()
	elif key.physical_keycode == KEY_R:
		state = Maze.recall(state)
		_finish()


func _sync_camera() -> void:
	if _camera == null:
		return
	var a := float(state["heading"])
	var jitter := Vector3(randf() - 0.5, randf() - 0.5, 0.0) * _shake * 0.12
	_camera.position = Vector3(float(state["pos"][0]), WALL_HEIGHT * 0.45, float(state["pos"][1])) + jitter
	_camera.rotation = Vector3(0.0, -a - PI * 0.5, 0.0)
	var t := Time.get_ticks_msec() / 1000.0
	for id in _target_nodes:
		var node: Node3D = _target_nodes[id]
		node.rotation.y = t * 0.6
		var glow := node.get_node_or_null("Glow") as OmniLight3D
		if glow != null:
			glow.light_energy = 0.6 + 0.3 * sin(t * 5.0)


func _hide_extracted() -> void:
	for t in state["targets"]:
		if bool(t["extracted"]) and _target_nodes.has(str(t["id"])):
			(_target_nodes[str(t["id"])] as Node3D).visible = false


func _update_hud() -> void:
	var left := float(state["time_left"])
	_hud_time.text = "SIGNAL %d:%02d" % [int(left) / 60, int(left) % 60]
	_hud_time.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3) if left < 15.0 else Color(0.75, 1.0, 0.9))
	_hud_hull.text = "HULL " + "■".repeat(maxi(0, int(state["hull"]))) + "□".repeat(maxi(0, int(state["hull_max"]) - int(state["hull"])))
	_hud_haul.text = "HAUL %d/%d" % [Maze.extracted_count(state), (state["targets"] as Array).size()]
	var ping := Maze.scanner(state)
	_arrow.visible = not ping.is_empty()
	if not ping.is_empty():
		_arrow.rotation = float(ping["bearing"])
	var reach := Maze.target_in_reach(state)
	_hud_prompt.text = "" if reach.is_empty() else "E  extract the %s" % _noun(str(reach["kind"]))


static func _noun(kind: String) -> String:
	return {"mineral": "crystal seam", "salvage": "salvage", "recorder": "flight recorder"}.get(kind, kind)


func _play_bump() -> void:
	if _bump_player == null:
		_bump_player = AudioStreamPlayer.new()
		_bump_player.stream = load(BUMP_SOUND)
		_bump_player.volume_db = -6.0
		_bump_player.pitch_scale = 0.6
		add_child(_bump_player)
	_bump_player.play()


func _finish() -> void:
	if _done:
		return
	_done = true
	if _paused_by_us and is_inside_tree():
		get_tree().paused = false
	finished.emit(Maze.outcome(state), state)
	queue_free()
