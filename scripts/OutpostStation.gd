extends StaticBody3D

## Dockable outpost station using a GLB model.
## These are repair-only stops — no ore selling, no upgrades, no agent.
## They serve as quest delivery/pickup locations for future contracts.
##
## NOTE: Open the Godot editor once after adding the new GLB files so Godot
## can import them. Until then, a procedural placeholder mesh is shown.

@export var display_name: String = "Outpost"
@export var world_id: String = ""
@export var station_type: String = "outpost"   # UIManager reads this to show repair-only UI
@export var model_path: String = ""            # e.g. "res://assets/space_station1.glb"
@export var model_scale: float = 5.0           # Adjust per model to match main station size
@export var minimum_docking_distance: float = 100.0

var _model_loaded: bool = false

func _ready() -> void:
	push_error("[OutpostStation] >>>>>>>>>> _ready() FIRED for: " + str(name) + " display_name=" + display_name + " <<<<<<<<<<")
	# Group membership (also declared in .tscn but explicit call is belt-and-suspenders)
	add_to_group("station")
	add_to_group(WorldIdentity.IDENTITY_GROUP)
	if world_id.is_empty():
		push_error("[OutpostStation] Missing explicit world ID for '%s'." % name)
	
	# Register in the global entity list so distance checks / NPC targeting work
	if not GlobalState.active_system_entities.has(self):
		GlobalState.active_system_entities.append(self)
	
	# Debug: confirm this runs and how many station-group nodes exist at this moment
	print("[OutpostStation] _ready(): '", display_name, "' (node: '", name, "') entered scene tree.")
	print("[OutpostStation] station group size at _ready(): ", get_tree().get_nodes_in_group("station").size())
	
	# Try loading the GLB model
	# NOTE: The parent node in main.tscn is already scaled 5x via its Transform.
	# Do NOT apply model_scale here or the model will be 25x actual size.
	if model_path != "":
		var model_scene = load(model_path)
		if model_scene:
			var model_instance = model_scene.instantiate()
			# Scale is intentionally left at Vector3.ONE — the parent node's
			# transform already provides the 5x world scale from main.tscn
			add_child(model_instance)
			_model_loaded = true
			print("[OutpostStation] GLB loaded successfully: ", model_path)
		else:
			push_warning("[OutpostStation] GLB not imported yet (%s). Using procedural fallback." % model_path)
	
	# Procedural fallback — visible until the GLB is imported and loaded
	if not _model_loaded:
		_build_fallback_mesh()
		print("[OutpostStation] Using procedural fallback mesh for '", display_name, "'")
	
	# Collision shape — box approximation (parent is already 5x scaled, so use base size)
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(30, 30, 30)
	col.shape = shape
	add_child(col)
	
	# Notify overview to refresh now that this outpost is fully set up
	GlobalState.entities_changed.emit()
	print("[OutpostStation] '", display_name, "' ready. station group now has ", get_tree().get_nodes_in_group("station").size(), " members.")

func _build_fallback_mesh() -> void:
	# Dark industrial material — distinct from the main station's metallic silver
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.22, 0.28)
	mat.roughness = 0.6
	mat.metallic = 0.9
	
	# Core tower
	var core_mesh = CylinderMesh.new()
	core_mesh.top_radius = 3.0
	core_mesh.bottom_radius = 3.5
	core_mesh.height = 20.0
	core_mesh.radial_segments = 12
	core_mesh.material = mat
	
	var core = MeshInstance3D.new()
	core.mesh = core_mesh
	core.scale = Vector3.ONE * (model_scale / 5.0)
	add_child(core)
	
	# Docking ring
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = 9.0
	ring_mesh.outer_radius = 11.0
	ring_mesh.ring_segments = 24
	ring_mesh.ring_sides = 6
	ring_mesh.material = mat
	
	var ring_node = MeshInstance3D.new()
	ring_node.name = "Ring"
	ring_node.mesh = ring_mesh
	ring_node.scale = Vector3.ONE * (model_scale / 5.0)
	add_child(ring_node)

func _exit_tree() -> void:
	# Clean up entity registration when removed from scene
	GlobalState.active_system_entities.erase(self)

func _physics_process(delta: float) -> void:
	if GlobalState.paused:
		return
	# Gentle slow rotation so the station feels alive in space
	rotate_y(0.025 * delta)

func get_docking_position(approach_position: Vector3) -> Vector3:
	var away_from_station := approach_position - global_position
	if away_from_station.length_squared() < 0.001:
		away_from_station = global_transform.basis.z
	return global_position + away_from_station.normalized() * get_docking_distance()

func get_world_id() -> String:
	return world_id

func get_world_type_id() -> String:
	return "entity_type.station"

func get_docking_distance() -> float:
	var collision := find_child("CollisionShape3D", true, false) as CollisionShape3D
	if collision and collision.shape is BoxShape3D:
		var box := collision.shape as BoxShape3D
		var world_scale := collision.global_transform.basis.get_scale().abs()
		var half_extents := box.size * 0.5 * world_scale
		var horizontal_radius := Vector2(half_extents.x, half_extents.z).length()
		return max(minimum_docking_distance, horizontal_radius + 16.0)
	return minimum_docking_distance

func dock_player() -> void:
	var ui: Node = GlobalState.get_ui_manager()
	if ui and ui.has_method("toggle_dock_menu"):
		ui.toggle_dock_menu(self)
		var game_root := get_tree().current_scene
		if game_root and game_root.has_method("save_game"):
			game_root.call_deferred("save_game")
	else:
		push_warning("[OutpostStation] dock_player(): Could not find UIManager node.")
