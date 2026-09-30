extends SubViewportContainer

## A live, slowly turning 3D view of the player's own ship for the Ship
## Upgrades screen (it used to show a picture of the old hull). The ship is
## built by the same ShipAssembler call as PlayerShip, in its own little world
## with a key and rim light, so it never touches the game scene.

const TURN_SPEED := 0.25  # rad/s

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
	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.position = Vector3(0, 3.0, 11.5)
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


func _process(delta: float) -> void:
	if _pivot != null and is_visible_in_tree():
		_pivot.rotate_y(TURN_SPEED * delta)
