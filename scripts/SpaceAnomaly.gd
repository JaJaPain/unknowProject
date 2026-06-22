extends StaticBody3D

const VALID_ITEMS := [
	"repair_kit", "shield_cell", "scanner_probe", "salvage_drone", "flare_decoy",
	"fuel_booster", "emp_charge", "target_painter", "data_chip", "kinetic_ammo",
	"thermal_ammo", "explosive_ammo", "energy_ammo", "damaged_transponder",
	"encrypted_core", "antimatter_pod",
]

var anomaly_data: Dictionary = {}
var _activated: bool = false
var _action_index: int = 0
var _mesh: MeshInstance3D = null
var _light: OmniLight3D = null
var _pulse_time: float = 0.0

const ACTIVATION_RANGE := 50.0


func _ready() -> void:
	add_to_group("anomaly")
	GlobalState.active_system_entities.append(self)
	GlobalState.entities_changed.emit()
	_build_visuals()


func _build_visuals() -> void:
	var col := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 4.0
	col.shape = sphere_shape
	add_child(col)

	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 3.0
	sm.height = 6.0
	_mesh.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	var base_color: Color = _pick_color()
	mat.emission = base_color
	mat.emission_energy_multiplier = 2.5
	mat.albedo_color = base_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.85
	_mesh.material_override = mat
	add_child(_mesh)

	_light = OmniLight3D.new()
	_light.light_color = base_color
	_light.light_energy = 3.0
	_light.omni_range = 80.0
	add_child(_light)


func _pick_color() -> Color:
	var flavor: String = str(anomaly_data.get("flavor_type", ""))
	match flavor:
		"military":  return Color(0.3, 0.6, 1.0)
		"civilian":  return Color(0.4, 1.0, 0.5)
		"pirate":    return Color(1.0, 0.3, 0.2)
		"scientific":return Color(0.9, 0.5, 1.0)
		_:           return Color(1.0, 0.85, 0.2)


func _physics_process(delta: float) -> void:
	_pulse_time += delta
	if _light:
		_light.light_energy = 2.5 + sin(_pulse_time * 2.0) * 0.8

	if _activated:
		return
	var player = GlobalState.player
	if not player or not is_instance_valid(player):
		return
	if global_position.distance_to(player.global_position) <= ACTIVATION_RANGE:
		_activate()


func _activate() -> void:
	_activated = true
	_action_index = 0
	_run_next_action()


func _run_next_action() -> void:
	var actions: Array = anomaly_data.get("actions", [])
	if _action_index >= actions.size():
		_finish()
		return
	var action: Dictionary = actions[_action_index]
	_action_index += 1
	var delay: float = float(action.get("delay", 0.0))
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_instance_valid(self):
		return
	_execute_action(action)
	_run_next_action()


func _execute_action(action: Dictionary) -> void:
	var t: String = str(action.get("type", ""))
	match t:
		"emit_chat":
			var sender: String = str(action.get("sender", "Unknown Signal"))
			var lines = action.get("lines", [])
			if lines is Array:
				for line in lines:
					GlobalState.emit_chatter(sender, str(line), Color(0.85, 0.85, 0.85))
		"grant_ore":
			var amount: float = clampf(float(action.get("amount", 10)), 0.0, 30.0)
			var added: float = GlobalState.add_ore(amount)
			if added > 0.0:
				GlobalState.emit_chatter("SYSTEM", "Salvageable material recovered: %.0f m³." % added, Color(0.0, 0.9, 0.9))
				AudioManager.play_sell_ore()
		"grant_credits":
			var amount: int = clampi(int(action.get("amount", 20)), 0, 150)
			GlobalState.player_credits += amount
			AudioManager.play_sell_ore()
			GlobalState.emit_chatter("SYSTEM", "Recovered %d SC." % amount, Color(0.0, 0.9, 0.9))
		"grant_item":
			var item_id: String = str(action.get("item_id", ""))
			if item_id in VALID_ITEMS:
				GlobalState.inventory.add(item_id, 1)
				GlobalState.emit_chatter("SYSTEM", "Item recovered: %s." % item_id.replace("_", " ").capitalize(), Color(0.0, 0.9, 0.9))
			else:
				push_warning("[SpaceAnomaly] Unknown item_id '%s' — skipped." % item_id)
		"spawn_hostiles":
			var faction: String = str(action.get("faction", "reavers"))
			var count: int = clampi(int(action.get("count", 1)), 1, 3)
			var spawn_chat: String = str(action.get("spawn_chat", ""))
			if not spawn_chat.is_empty():
				GlobalState.emit_chatter("SYSTEM", spawn_chat, Color(1.0, 0.5, 0.2))
			_spawn_hostiles(faction, count)
		"damage_player":
			var amount: float = clampf(float(action.get("amount", 5)), 0.0, 20.0)
			var p = GlobalState.player
			if p and is_instance_valid(p) and p.has_method("take_damage"):
				p.take_damage(amount, "anomaly")
				GlobalState.emit_chatter("SYSTEM", "Hull breach — %.0f damage sustained." % amount, Color(1.0, 0.5, 0.2))
		"grant_temp_buff":
			push_warning("[SpaceAnomaly] grant_temp_buff not yet implemented — skipped.")
		_:
			if not t.is_empty():
				push_warning("[SpaceAnomaly] Unknown action type '%s' — skipped." % t)


func _spawn_hostiles(faction: String, count: int) -> void:
	var system_root = GlobalState.active_system_root
	if not system_root or not is_instance_valid(system_root):
		return
	var npc_scene = load("res://scenes/npc_ship.tscn")
	if not npc_scene:
		return
	var known_factions: Array = GlobalState.MINOR_FACTIONS.keys()
	if faction not in known_factions:
		faction = known_factions[randi() % known_factions.size()]
	for i in range(count):
		var npc = npc_scene.instantiate()
		npc.faction = faction
		npc.speed = 13.0
		npc.ship_role = "Raider"
		npc.name = faction.to_upper() + "_Anomaly_" + str(randi() % 1000)
		system_root.add_child(npc)
		var angle: float = (TAU / count) * i
		npc.global_position = global_position + Vector3(cos(angle), 0.0, sin(angle)) * 120.0


func _finish() -> void:
	GlobalState.active_system_entities.erase(self)
	GlobalState.entities_changed.emit()
	# Fade out light before freeing
	if _light and is_instance_valid(_light):
		_light.light_energy = 0.0
	queue_free()
