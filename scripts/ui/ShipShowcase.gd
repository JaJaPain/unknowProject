extends SubViewportContainer

## A live, slowly turning 3D view of the player's own ship for the Ship
## Upgrades screen (it used to show a picture of the old hull). The ship is
## built by the same ShipAssembler call as PlayerShip, in its own little world
## with a key and rim light, so it never touches the game scene.

const TURN_SPEED := 0.25  # rad/s
## How far back the camera sits (set before adding to the tree).
var camera_distance := 11.5

var _pivot: Node3D


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	add_child(viewport)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.3, 0.38)
	e.ambient_light_energy = 1.1
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	env.environment = e
	viewport.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.7, 0.6, 0.0)
	key.light_energy = 2.2
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(-0.3, 3.4, 0.0)
	rim.light_color = Color(0.45, 0.7, 1.0)
	rim.light_energy = 1.1
	viewport.add_child(rim)
	_pivot = Node3D.new()
	_pivot.rotation.y = 2.2  # open on a three-quarter view, not nose-on
	viewport.add_child(_pivot)
	var model: Node3D = ShipAssembler.build_special(0)  # the player's hull (PlayerShip)
	if model != null:
		_pivot.add_child(model)
		_fit(model)
		_add_thrusters(model)
	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.position = Vector3(0, camera_distance * 0.26, camera_distance)
	viewport.add_child(cam)
	cam.look_at(Vector3.ZERO)


## Centre the model and scale it to a fixed size so any hull frames the same.
func _fit(model: Node3D) -> void:
	var box := AABB()
	var first := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		if m.mesh == null:
			continue
		var local := (model.global_transform.affine_inverse() * m.global_transform) * m.get_aabb()
		box = local if first else box.merge(local)
		first = false
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest < 0.01:
		return
	var s := 7.5 / longest
	model.scale = Vector3.ONE * s
	model.position = -box.get_center() * s


var _launching := false
## The ship's own engine plumes (ThrusterBank, as PlayerShip uses): a soft
## idle glow while it turns, full burn with boost when it launches (Abe).
var _thrusters: Node = null
var _throttle := 0.12
var _boosting := false


func _add_thrusters(model: Node3D) -> void:
	var points: Array[Node3D] = []
	_find_thruster_points(model, points)
	if points.is_empty():
		# Same fallback sockets PlayerShip uses for hulls without markers.
		for x in [-1.4, 1.4]:
			var socket := Marker3D.new()
			socket.position = Vector3(x, -0.1, 4.7)
			socket.set_meta("thruster_radius", 0.55)
			model.add_child(socket)
			points.append(socket)
	_thrusters = load("res://scripts/visuals/ThrusterBank.gd").new()
	add_child(_thrusters)
	_thrusters.setup(points, Color(0.18, 0.72, 1.0), 1.0)


func _find_thruster_points(node: Node, out: Array[Node3D]) -> void:
	var lower := str(node.name).to_lower()
	if node is Marker3D and (lower.begins_with("engine_") or lower.begins_with("thruster_") 			or lower.begins_with("exhaust_") or lower.begins_with("nozzle_")):
		out.append(node as Node3D)
	for child in node.get_children():
		_find_thruster_points(child, out)


## Title-screen launch: the ship swings its nose away from the camera and
## boosts off into the distance (about `duration` seconds).
func launch(duration: float = 1.1) -> void:
	if _pivot == null:
		return
	_launching = true
	_boosting = true
	var burn := create_tween()
	burn.tween_property(self, "_throttle", 1.0, duration * 0.3)
	var tween := create_tween()
	# Face away (the hull's nose is -Z, so a yaw of 0 points it into the screen).
	var yaw := snappedf(_pivot.rotation.y, TAU)
	tween.tween_property(_pivot, "rotation:y", yaw, duration * 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_pivot, "position", Vector3(0.0, -36.4, -140.0), duration * 0.65).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	await tween.finished


func _process(delta: float) -> void:
	if _thrusters != null:
		_thrusters.update_intensity(_throttle, _boosting)
	if _pivot != null and is_visible_in_tree() and not _launching:
		_pivot.rotate_y(TURN_SPEED * delta)
