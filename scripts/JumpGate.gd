extends StaticBody3D

@export var gate_id: String = ""
@export var world_id: String = ""
@export var display_name: String = "HYPERGATE"
@export var destination_system_id: String = ""
@export var destination_gate_id: String = ""
@export var destination_display_name: String = "UNKNOWN SYSTEM"
@export var activation_range: float = 130.0
@export var model_scale: float = 0.5

@onready var model_anchor: Node3D = $ModelAnchor
@onready var arrival_marker: Marker3D = $ArrivalMarker
@onready var approach_marker: Marker3D = $ApproachMarker
@onready var portal_surface: MeshInstance3D = $PortalSurface
@onready var gate_light: OmniLight3D = $GateLight

var portal_material: ShaderMaterial
var charge_tween: Tween
var knowledge_state: String = "known"

func _ready() -> void:
	add_to_group("jumpgate")
	add_to_group(WorldIdentity.IDENTITY_GROUP)
	if world_id.is_empty():
		push_error("[JumpGate] Missing explicit world ID for gate '%s'." % gate_id)
	if not GlobalState.active_system_entities.has(self):
		GlobalState.active_system_entities.append(self)
	_center_and_scale_model()
	portal_material = portal_surface.get_active_material(0).duplicate() as ShaderMaterial
	portal_surface.material_override = portal_material
	_set_portal_charge(0.0)
	_apply_knowledge_state()
	if GateDiscovery:
		GateDiscovery.gate_state_changed.connect(_on_gate_state_changed)
	GlobalState.entities_changed.emit()

func _process(delta: float) -> void:
	if charge_tween and charge_tween.is_running():
		return
	var pulse := 0.82 + sin(Time.get_ticks_msec() * 0.004) * 0.12
	portal_surface.scale = Vector3.ONE * pulse
	gate_light.light_energy = 4.5 + pulse * 1.5
	portal_surface.rotation.z += delta * 0.12

func _exit_tree() -> void:
	GlobalState.active_system_entities.erase(self)

func get_arrival_transform() -> Transform3D:
	return arrival_marker.global_transform

func get_approach_position() -> Vector3:
	return approach_marker.global_position

func get_world_id() -> String:
	return world_id

func get_world_type_id() -> String:
	return "entity_type.gate"

func is_player_in_activation_range() -> bool:
	var player := GlobalState.player
	return player != null and is_instance_valid(player) and global_position.distance_to(player.global_position) <= activation_range

func is_jump_allowed() -> bool:
	return knowledge_state == "known"

func request_jump() -> bool:
	if not is_jump_allowed():
		return false
	var game_root := get_tree().current_scene
	if not game_root or not game_root.has_method("request_gate_jump"):
		return false
	return game_root.request_gate_jump(self)

func begin_jump_charge(duration: float = 1.0) -> void:
	if charge_tween and charge_tween.is_valid():
		charge_tween.kill()
	charge_tween = create_tween().set_parallel(true)
	charge_tween.tween_property(gate_light, "light_energy", 18.0, duration)
	charge_tween.tween_property(portal_surface, "scale", Vector3.ONE * 1.35, duration)
	if portal_material:
		charge_tween.tween_method(Callable(self, "_set_portal_charge"), 0.0, 1.0, duration)

func _set_portal_charge(value: float) -> void:
	if portal_material:
		portal_material.set_shader_parameter("charge", value)

func _center_and_scale_model() -> void:
	var model_root := model_anchor.get_child(0) as Node3D
	if not model_root:
		push_warning("[JumpGate] Missing hypergate model instance for gate '%s'." % gate_id)
		return
	model_root.scale = Vector3.ONE * model_scale

	var meshes: Array[MeshInstance3D] = []
	_find_meshes(model_root, meshes)
	if meshes.is_empty():
		push_warning("[JumpGate] Hypergate model contains no meshes.")
		return

	var combined := AABB()
	var first := true
	for mesh in meshes:
		var relative := model_root.global_transform.affine_inverse() * mesh.global_transform
		var mesh_aabb := relative * mesh.get_aabb()
		if first:
			combined = mesh_aabb
			first = false
		else:
			combined = combined.merge(mesh_aabb)

	model_root.position = -combined.get_center() * model_scale

func _find_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		_find_meshes(child, meshes)


func _apply_knowledge_state() -> void:
	var game_root := get_tree().current_scene
	if game_root and game_root.has_method("get_gate_knowledge_state"):
		knowledge_state = game_root.get_gate_knowledge_state(world_id)
	else:
		knowledge_state = "known"

	match knowledge_state:
		"unknown":
			visible = false
		"rumored":
			visible = false
		"hidden":
			visible = true
			_apply_dim_visual()
		"blocked":
			visible = true
			_apply_blocked_visual()
		"damaged":
			visible = true
			_apply_damaged_visual()
		"known":
			visible = true


func _apply_dim_visual() -> void:
	if portal_material:
		portal_material.set_shader_parameter("charge", 0.0)
	if gate_light:
		gate_light.light_energy = 1.5


func _apply_blocked_visual() -> void:
	if portal_material:
		portal_material.set_shader_parameter("charge", 0.0)
	if gate_light:
		gate_light.light_color = Color(0.9, 0.2, 0.2)
		gate_light.light_energy = 3.0


func _apply_damaged_visual() -> void:
	if portal_material:
		portal_material.set_shader_parameter("charge", 0.15)
	if gate_light:
		gate_light.light_color = Color(1.0, 0.6, 0.1)
		gate_light.light_energy = 2.5


func _on_gate_state_changed(
	changed_gate_id: String,
	_old_state: String,
	_new_state: String
) -> void:
	if changed_gate_id == world_id:
		_apply_knowledge_state()
		GlobalState.entities_changed.emit()
