extends AnimatableBody3D

@export var max_resources: float = 300.0
@export var persistent_id: String = ""
var resources: float = 300.0
var destroyed: bool = false

# Orbiting variables
var orbit_center: Vector3 = Vector3.ZERO
var orbit_radius: float = 0.0
var orbit_speed: float = 0.0
var current_angle: float = 0.0
var orbit_y: float = 0.0
var is_orbiting: bool = false
var navigation_parent: Node3D = null
var _tumble_axis: Vector3 = Vector3.UP
var _tumble_speed: float = 0.0
var _mesh: MeshInstance3D = null
var _bob_amp1: float = 0.0
var _bob_freq1: float = 0.0
var _bob_phase1: float = 0.0
var _bob_amp2: float = 0.0
var _bob_freq2: float = 0.0
var _bob_phase2: float = 0.0
var _bob_time: float = 0.0

func _ready():
	add_to_group("asteroid")
	add_to_group(WorldIdentity.IDENTITY_GROUP)
	add_to_group("persistent_entity")
	if persistent_id == "":
		push_error("[Asteroid] Missing explicit persistent ID for '%s'." % name)
	resources = max_resources
	var r_scale = randf_range(0.85, 1.4)
	scale = Vector3(r_scale, r_scale, r_scale)
	_mesh = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if _mesh:
		AsteroidModels.apply_random_model(_mesh, persistent_id.hash())
	var rng := RandomNumberGenerator.new()
	rng.seed = persistent_id.hash()
	_tumble_axis = Vector3(
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0),
	).normalized()
	_tumble_speed = rng.randf_range(0.05, 0.25)
	_bob_amp1 = rng.randf_range(3.0, 6.0)
	_bob_freq1 = rng.randf_range(0.08, 0.2)
	_bob_phase1 = rng.randf_range(0.0, TAU)
	_bob_amp2 = rng.randf_range(1.5, 3.5)
	_bob_freq2 = rng.randf_range(0.15, 0.4)
	_bob_phase2 = rng.randf_range(0.0, TAU)

func _physics_process(delta: float):
	if destroyed or GlobalState.paused:
		return
	_bob_time += delta
	if is_orbiting:
		current_angle += orbit_speed * delta
		var x = orbit_center.x + cos(current_angle) * orbit_radius
		var z = orbit_center.z + sin(current_angle) * orbit_radius
		var y_offset = sin(_bob_time * _bob_freq1 + _bob_phase1) * _bob_amp1 \
			+ sin(_bob_time * _bob_freq2 + _bob_phase2) * _bob_amp2
		global_position = Vector3(x, orbit_y + y_offset, z)
	if _mesh and _tumble_speed > 0.0:
		_mesh.rotate(_tumble_axis, _tumble_speed * delta)

func mine():
	if destroyed: return

	# Refuse to mine if the hold is carrying a special cargo item (e.g. a
	# part the mechanic gave us). The hold is mutually exclusive — ore
	# and special cargo cannot coexist.
	if not GlobalState.can_accept_ore():
		return

	# Calculate how much space is left in player's cargo
	var space_left = GlobalState.cargo_max - GlobalState.cargo
	if space_left <= 0.0:
		return

	# Mined amount is the minimum of:
	# 1. Player's mining yield
	# 2. Remaining asteroid resources
	# 3. Space left in cargo (Top-off logic!)
	var amount_to_mine = min(GlobalState.mining_yield, resources)
	amount_to_mine = min(amount_to_mine, space_left)

	if amount_to_mine > 0.0:
		var added = GlobalState.add_ore(amount_to_mine)
		resources -= added
		
		# Visual/text popups could be spawned here
		
		if resources <= 0.0:
			deplete()

func deplete():
	destroyed = true
	_record_persistent_state()
	AudioManager.play_explosion(global_position)
	# Remove from entities list if it was targeted
	if GlobalState.active_target == self:
		GlobalState.active_target = null
	queue_free()

func get_persistent_id() -> String:
	return get_world_id()

func get_world_id() -> String:
	return persistent_id

func get_world_type_id() -> String:
	return "entity_type.asteroid"

func get_state_schema_version() -> int:
	return 1

func capture_state() -> Dictionary:
	return {
		"type": "asteroid",
		"resources": resources,
		"destroyed": destroyed,
	}

func restore_state(state: Dictionary) -> void:
	resources = clampf(float(state.get("resources", max_resources)), 0.0, max_resources)
	destroyed = bool(state.get("destroyed", false)) or resources <= 0.0
	if destroyed:
		queue_free()

func _record_persistent_state() -> void:
	var game_root := get_tree().current_scene
	if game_root and game_root.has_method("record_persistent_entity_state"):
		game_root.record_persistent_entity_state(self)
