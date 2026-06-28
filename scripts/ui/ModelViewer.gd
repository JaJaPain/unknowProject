class_name ModelViewer
extends Control

## Reusable 3D model viewer Control. Renders a model in an isolated SubViewport
## (own World3D) with orbit-drag, scroll-zoom, and idle auto-spin. Drop it into
## any panel and call show_ship() or set_model().
##
## Built to back the sensor/ship-info panel, but model-agnostic — set_model()
## takes any Node3D.

@export var auto_rotate: bool = true
@export var auto_rotate_speed: float = 0.35          # radians/sec
@export var background_color: Color = Color(0.03, 0.04, 0.07)
@export var min_pitch_deg: float = -82.0
@export var max_pitch_deg: float = 82.0
@export var zoom_min_factor: float = 0.55            # × model size
@export var zoom_max_factor: float = 3.5
@export var camera_fov: float = 45.0

var _viewport: SubViewport
var _yaw: Node3D                                      # orbit yaw
var _pitch: Node3D                                    # orbit pitch (child of yaw)
var _camera: Camera3D
var _holder: Node3D                                   # holds the displayed model

var _model_size: float = 2.0
var _distance: float = 8.0
var _target_distance: float = 8.0
var _dragging: bool = false
var _has_model: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_rig()


func _build_rig() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Let THIS Control receive orbit/zoom input; the container must not eat it.
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_viewport)

	# Environment — flat background + soft ambient so the model always reads.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = background_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.72)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -40, 0)
	key.light_energy = 1.6
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 140, 0)
	fill.light_energy = 0.5
	_viewport.add_child(fill)

	# Orbit rig: yaw -> pitch -> camera (camera offset on +Z, looks at origin).
	_yaw = Node3D.new()
	_viewport.add_child(_yaw)
	_pitch = Node3D.new()
	_yaw.add_child(_pitch)
	_camera = Camera3D.new()
	_camera.fov = camera_fov
	_camera.current = true
	_pitch.add_child(_camera)

	_holder = Node3D.new()
	_viewport.add_child(_holder)


## Build and display a kitbash ship for the given faction/role/seed.
func show_ship(faction: String, role: String, seed_value: int = 0) -> void:
	var node := ShipAssembler.build_catalog_ship(faction, role, seed_value)
	if node == null:
		push_warning("[ModelViewer] Could not build ship %s/%s" % [faction, role])
		return
	set_model(node)


## Display an arbitrary Node3D (takes ownership; previous model is freed).
func set_model(node: Node3D) -> void:
	if _holder == null:
		_build_rig()
	for c in _holder.get_children():
		c.queue_free()
	_holder.add_child(node)
	# Recenter the model on the orbit origin.
	var box := _aabb(node)
	if box.size != Vector3.ZERO:
		node.position = -(box.position + box.size * 0.5)
		_model_size = maxf(box.size.x, maxf(box.size.y, box.size.z))
	else:
		_model_size = 2.0
	_target_distance = _frame_distance()
	_distance = _target_distance
	_camera.position = Vector3(0, 0, _distance)
	# Start on a 3/4 front-hero angle (ships face -Z, so yaw ~200° shows the bow).
	_yaw.rotation_degrees = Vector3(0, 200, 0)
	_pitch.rotation_degrees = Vector3(-18, 0, 0)        # slight top-down tilt
	_has_model = true


func clear() -> void:
	if _holder:
		for c in _holder.get_children():
			c.queue_free()
	_has_model = false


func _frame_distance() -> float:
	# Distance so the model's largest extent fits the vertical FOV with margin.
	var half_fov := deg_to_rad(camera_fov) * 0.5
	var d := (_model_size * 0.5) / maxf(tan(half_fov), 0.01)
	return d * 1.5


func _process(delta: float) -> void:
	if not _has_model:
		return
	if auto_rotate and not _dragging:
		_yaw.rotation.y += auto_rotate_speed * delta
	# Smooth zoom toward target.
	if absf(_distance - _target_distance) > 0.001:
		_distance = lerpf(_distance, _target_distance, clampf(delta * 10.0, 0.0, 1.0))
		_camera.position = Vector3(0, 0, _distance)


func _gui_input(event: InputEvent) -> void:
	if not _has_model:
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_dragging = event.pressed
				accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(-0.12)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(0.12)
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var d: Vector2 = event.relative
		_yaw.rotation.y -= d.x * 0.01
		var p := _pitch.rotation_degrees
		p.x = clampf(p.x - d.y * 0.5, min_pitch_deg, max_pitch_deg)
		_pitch.rotation_degrees = p
		accept_event()


func _zoom(amount: float) -> void:
	var lo := _model_size * zoom_min_factor
	var hi := _model_size * zoom_max_factor
	_target_distance = clampf(_target_distance * (1.0 + amount), lo, hi)


## Combined AABB of all MeshInstance3D under node, in node's local space.
func _aabb(node: Node3D) -> AABB:
	var meshes: Array = []
	_collect(node, meshes)
	var combined := AABB()
	var first := true
	for mi in meshes:
		var rel: Transform3D = node.global_transform.affine_inverse() * mi.global_transform
		var b: AABB = rel * mi.get_aabb()
		if first:
			combined = b
			first = false
		else:
			combined = combined.merge(b)
	return combined


func _collect(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect(c, out)
