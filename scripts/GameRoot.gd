extends Node3D

signal system_changed(system_id: String, arrival_gate_id: String)

const SYSTEM_SCENES: Dictionary = {
	"start_system": preload("res://scenes/systems/system_start.tscn"),
	"test_system": preload("res://scenes/systems/system_test.tscn"),
}
const ARRIVAL_COOLDOWN_SECONDS := 2.5
const JUMP_ENTRY_DURATION := 3.2
const JUMP_EXIT_DURATION := 0.9
const SAVE_VERSION := 1
const SAVE_PATH := "user://savegame.json"
const NPC_SHIP_SCENE := preload("res://scenes/npc_ship.tscn")

@onready var system_container: Node3D = $SystemContainer
@onready var player: CharacterBody3D = $PlayerShip
@onready var transition_fx: CanvasLayer = $JumpTransitionFX

var transition_in_progress: bool = false
var jump_request_pending: bool = false
var arrival_cooldown_until_msec: int = 0
var system_states: Dictionary = {}
var last_arrival_gate_id: String = ""

func _ready() -> void:
	var system_root := system_container.get_child(0) as Node3D
	GlobalState.active_system_root = system_root
	GlobalState.current_system_id = "start_system"
	if "--economy-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_economy_smoke_test")
	elif "--autopilot-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_autopilot_smoke_test")
	elif "--restart-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_restart_smoke_test")
	elif "--dock-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_dock_smoke_test")
	elif "--jump-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_jump_smoke_test")
	elif "--no-save-load" not in OS.get_cmdline_user_args():
		call_deferred("_load_startup_save")

func get_active_system_root() -> Node3D:
	return GlobalState.get_system_root()

func can_begin_jump() -> bool:
	return not transition_in_progress and not jump_request_pending and Time.get_ticks_msec() >= arrival_cooldown_until_msec

func get_jump_block_reason(gate: Node3D) -> String:
	if not gate or not is_instance_valid(gate) or not gate.is_in_group("jumpgate"):
		return "No valid jumpgate selected."
	if transition_in_progress or jump_request_pending:
		return "Jump sequence already in progress."
	if Time.get_ticks_msec() < arrival_cooldown_until_msec:
		return "Gate drive is recalibrating after arrival."
	if not player or not is_instance_valid(player) or player.get("destroyed"):
		return "Ship is not flight capable."
	if player.get("is_docked"):
		return "Undock before activating a jumpgate."
	if GlobalState.active_target != gate:
		return "Target the jumpgate before activation."
	if not gate.call("is_player_in_activation_range"):
		return "Move within jump range before activation."
	var to_gate := (gate.global_position - player.global_position).normalized()
	var ship_forward := -player.global_transform.basis.z.normalized()
	if ship_forward.dot(to_gate) < cos(deg_to_rad(12.0)):
		return "Align the ship with the jumpgate."
	return ""

func request_gate_jump(gate: Node3D) -> bool:
	if get_jump_block_reason(gate) != "":
		return false
	var destination_system: String = gate.get("destination_system_id")
	var destination_gate: String = gate.get("destination_gate_id")
	if destination_system == "" or destination_gate == "":
		push_warning("[GameRoot] Jumpgate is missing destination metadata.")
		return false
	jump_request_pending = true
	call_deferred("_change_system", destination_system, destination_gate)
	return true

func _change_system(destination_system_id: String, arrival_gate_id: String) -> void:
	if transition_in_progress:
		jump_request_pending = false
		return
	var packed_system := SYSTEM_SCENES.get(destination_system_id) as PackedScene
	if not packed_system:
		jump_request_pending = false
		push_warning("[GameRoot] Unknown destination system '%s'." % destination_system_id)
		return

	var new_system := packed_system.instantiate() as Node3D
	var arrival_gate := _find_gate_in_tree(new_system, arrival_gate_id)
	if not arrival_gate:
		new_system.free()
		jump_request_pending = false
		push_error("[GameRoot] Destination gate '%s' was not found in '%s'." % [
			arrival_gate_id, destination_system_id
		])
		return

	jump_request_pending = false
	transition_in_progress = true
	_prepare_player_for_system_change()
	var source_gate := GlobalState.active_target
	var camera := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	var original_fov := camera.fov if camera else 70.0
	var effect_duration := 0.05 if DisplayServer.get_name() == "headless" else JUMP_ENTRY_DURATION
	if source_gate and is_instance_valid(source_gate) and source_gate.has_method("begin_jump_charge"):
		source_gate.begin_jump_charge(effect_duration)
		create_tween().tween_property(player, "global_position", source_gate.global_position, effect_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	AudioManager.play_jump_spool()
	if camera:
		create_tween().tween_property(camera, "fov", min(original_fov + 24.0, 120.0), effect_duration)
	await transition_fx.play_entry(effect_duration)
	AudioManager.play_jump_transit()
	_capture_current_system_state()
	GlobalState.active_target = null
	GlobalState.active_system_entities.clear()

	var old_system := get_active_system_root()
	GlobalState.active_system_root = null
	if old_system and is_instance_valid(old_system):
		old_system.queue_free()
		await get_tree().process_frame

	system_container.add_child(new_system)
	GlobalState.active_system_root = new_system
	GlobalState.current_system_id = destination_system_id
	await get_tree().process_frame
	_restore_system_state(destination_system_id, new_system)

	var arrival_transform: Transform3D = arrival_gate.call("get_arrival_transform")
	player.global_transform = arrival_transform
	last_arrival_gate_id = arrival_gate_id

	if player.has_method("sync_camera_to_ship"):
		player.sync_camera_to_ship()
	if camera:
		camera.fov = original_fov
	await transition_fx.hold_covered(1 if DisplayServer.get_name() == "headless" else 2)
	AudioManager.play_jump_arrival()
	await transition_fx.play_exit(0.05 if DisplayServer.get_name() == "headless" else JUMP_EXIT_DURATION)
	_prepare_player_after_system_change()
	arrival_cooldown_until_msec = Time.get_ticks_msec() + int(ARRIVAL_COOLDOWN_SECONDS * 1000.0)
	transition_in_progress = false
	system_changed.emit(destination_system_id, arrival_gate_id)
	save_game()

	var ui := GlobalState.get_ui_manager()
	if ui and ui.has_method("refresh_overview"):
		ui.call_deferred("refresh_overview")

func _find_gate(system_root: Node3D, gate_id: String) -> Node3D:
	for gate in get_tree().get_nodes_in_group("jumpgate"):
		if gate is Node3D and system_root.is_ancestor_of(gate) and gate.get("gate_id") == gate_id:
			return gate as Node3D
	return null

func _find_gate_in_tree(node: Node, gate_id: String) -> Node3D:
	if node is Node3D and node.is_in_group("jumpgate") and node.get("gate_id") == gate_id:
		return node as Node3D
	for child in node.get_children():
		var found := _find_gate_in_tree(child, gate_id)
		if found:
			return found
	return null

func _prepare_player_for_system_change() -> void:
	player.set("nav_mode", "MANUAL")
	player.set("target_position", null)
	player.set("is_aligning", false)
	player.velocity = Vector3.ZERO
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)

func _prepare_player_after_system_change() -> void:
	player.velocity = Vector3.ZERO
	player.set("current_speed", 0.0)
	player.set("target_position", null)
	player.set("nav_mode", "MANUAL")
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)

func record_persistent_entity_state(entity: Node) -> void:
	if not entity or not entity.has_method("get_persistent_id") or not entity.has_method("capture_state"):
		return
	var entity_id: String = entity.get_persistent_id()
	if entity_id == "":
		return
	var state: Dictionary = system_states.get(GlobalState.current_system_id, {})
	var entities: Dictionary = state.get("entities", {})
	entities[entity_id] = entity.capture_state()
	state["entities"] = entities
	system_states[GlobalState.current_system_id] = state

func _capture_current_system_state() -> void:
	var system_root := get_active_system_root()
	if not system_root:
		return
	var state: Dictionary = system_states.get(GlobalState.current_system_id, {})
	var entities: Dictionary = state.get("entities", {})
	for entity in get_tree().get_nodes_in_group("persistent_entity"):
		if is_instance_valid(entity) and system_root.is_ancestor_of(entity):
			if entity.has_method("get_persistent_id") and entity.has_method("capture_state"):
				var entity_id: String = entity.get_persistent_id()
				if entity_id != "":
					entities[entity_id] = entity.capture_state()
	state["entities"] = entities
	system_states[GlobalState.current_system_id] = state

func _restore_system_state(system_id: String, system_root: Node3D) -> void:
	var state: Dictionary = system_states.get(system_id, {})
	var entities: Dictionary = state.get("entities", {})
	if entities.is_empty():
		return
	var restored_ids: Dictionary = {}
	for entity in get_tree().get_nodes_in_group("persistent_entity"):
		if is_instance_valid(entity) and system_root.is_ancestor_of(entity) and entity.has_method("get_persistent_id"):
			var entity_id: String = entity.get_persistent_id()
			if entities.has(entity_id) and entity.has_method("restore_state"):
				entity.restore_state(entities[entity_id])
				restored_ids[entity_id] = true
	for entity_id in entities.keys():
		if restored_ids.has(entity_id):
			continue
		var entity_state: Dictionary = entities[entity_id]
		if entity_state.get("type", "") == "mission_ship" and not bool(entity_state.get("destroyed", false)):
			var npc := NPC_SHIP_SCENE.instantiate()
			npc.name = entity_id
			npc.persistent_id = entity_id
			npc.faction = str(entity_state.get("faction", "zenith"))
			npc.ship_role = str(entity_state.get("ship_role", "Gunner"))
			npc.set_meta("is_quest_target", true)
			npc.add_to_group("persistent_entity")
			system_root.add_child(npc)
			npc.restore_state(entity_state)

func save_game() -> bool:
	_capture_current_system_state()
	var save_data := {
		"version": SAVE_VERSION,
		"current_system_id": GlobalState.current_system_id,
		"arrival_gate_id": last_arrival_gate_id,
		"player": _capture_player_state(),
		"global": _capture_global_state(),
		"quest": QuestManager.active_quest.duplicate(true),
		"systems": system_states.duplicate(true),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_warning("[GameRoot] Could not open save file for writing.")
		return false
	file.store_string(JSON.stringify(save_data))
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if not _is_valid_save_data(parsed):
		push_warning("[GameRoot] Save file is missing, malformed, or unsupported.")
		return false
	await _apply_save_data(parsed)
	return true

func delete_savegame() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func _load_startup_save() -> void:
	await get_tree().process_frame
	await load_game()

func _is_valid_save_data(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	if int(data.get("version", -1)) != SAVE_VERSION:
		return false
	if not SYSTEM_SCENES.has(str(data.get("current_system_id", ""))):
		return false
	return data.get("player", null) is Dictionary \
		and data.get("global", null) is Dictionary \
		and data.get("quest", null) is Dictionary \
		and data.get("systems", null) is Dictionary

func _apply_save_data(data: Dictionary) -> void:
	system_states = data.get("systems", {}).duplicate(true)
	last_arrival_gate_id = str(data.get("arrival_gate_id", ""))
	_apply_global_state(data.get("global", {}))
	QuestManager.active_quest = data.get("quest", {}).duplicate(true)
	var target_system_id := str(data.get("current_system_id", "start_system"))
	if target_system_id != GlobalState.current_system_id:
		await _load_system_without_transition(target_system_id)
	else:
		_restore_system_state(target_system_id, get_active_system_root())
	_apply_player_state(data.get("player", {}))
	var ui := GlobalState.get_ui_manager()
	if ui:
		ui.call_deferred("refresh_overview")

func _load_system_without_transition(system_id: String) -> void:
	var packed_system := SYSTEM_SCENES.get(system_id) as PackedScene
	if not packed_system:
		return
	GlobalState.active_target = null
	GlobalState.active_system_entities.clear()
	var old_system := get_active_system_root()
	GlobalState.active_system_root = null
	if old_system:
		old_system.queue_free()
		await get_tree().process_frame
	var new_system := packed_system.instantiate() as Node3D
	system_container.add_child(new_system)
	GlobalState.active_system_root = new_system
	GlobalState.current_system_id = system_id
	await get_tree().process_frame
	_restore_system_state(system_id, new_system)

func _capture_player_state() -> Dictionary:
	return {
		"health": player.get("health"),
		"shield": player.get("current_shield"),
		"position": [player.global_position.x, player.global_position.y, player.global_position.z],
		"rotation": [player.global_rotation.x, player.global_rotation.y, player.global_rotation.z],
	}

func _apply_player_state(state: Dictionary) -> void:
	player.set("max_health", GlobalState.player_max_health)
	player.set("health", clampf(float(state.get("health", GlobalState.player_max_health)), 0.0, GlobalState.player_max_health))
	player.set("current_shield", clampf(float(state.get("shield", GlobalState.shield_capacity)), 0.0, GlobalState.shield_capacity))
	var saved_position: Array = state.get("position", [])
	if saved_position.size() == 3:
		player.global_position = Vector3(float(saved_position[0]), float(saved_position[1]), float(saved_position[2]))
	var saved_rotation: Array = state.get("rotation", [])
	if saved_rotation.size() == 3:
		player.global_rotation = Vector3(float(saved_rotation[0]), float(saved_rotation[1]), float(saved_rotation[2]))

func _capture_global_state() -> Dictionary:
	return {
		"credits": GlobalState.player_credits,
		"cargo": GlobalState.cargo,
		"cargo_type": GlobalState.cargo_type,
		"cargo_special": GlobalState.cargo_special.duplicate(true),
		"storage_ore": GlobalState.player_storage_ore,
		"upgrades": GlobalState.current_upgrades.duplicate(true),
		"reputations": GlobalState.reputations.duplicate(true),
		"faction_kills": GlobalState.faction_kills.duplicate(true),
	}

func _apply_global_state(state: Dictionary) -> void:
	GlobalState.player_credits = int(state.get("credits", 50))
	GlobalState.current_upgrades = state.get("upgrades", GlobalState.current_upgrades).duplicate(true)
	GlobalState.apply_upgrade_stats()
	GlobalState.player_storage_ore = float(state.get("storage_ore", 0.0))
	GlobalState.cargo_type = int(state.get("cargo_type", GlobalState.CargoType.EMPTY))
	GlobalState.cargo_special = state.get("cargo_special", {}).duplicate(true)
	GlobalState.cargo = float(state.get("cargo", 0.0))
	GlobalState.reputations = state.get("reputations", GlobalState.reputations).duplicate(true)
	GlobalState.faction_kills = state.get("faction_kills", GlobalState.faction_kills).duplicate(true)
	GlobalState.cargo_changed.emit(GlobalState.cargo)

func _run_jump_smoke_test() -> void:
	await get_tree().process_frame
	GlobalState.paused = false
	var starting_health: float = min(73.0, player.get("max_health"))
	var starting_shield: float = min(17.0, GlobalState.shield_capacity)
	player.set("health", starting_health)
	player.set("current_shield", starting_shield)

	var outbound_gate := _find_gate(get_active_system_root(), "start_to_test")
	if not outbound_gate:
		_fail_jump_smoke_test("Outbound gate was not found.")
		return
	var approach_position: Vector3 = outbound_gate.call("get_approach_position")
	if approach_position.distance_to(outbound_gate.global_position) < 200.0:
		_fail_jump_smoke_test("Gate approach marker is too close for a clean alignment.")
		return
	GlobalState.active_target = outbound_gate
	player.global_position = approach_position + outbound_gate.global_transform.basis.x.normalized() * 120.0
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	player.nav_mode = "JUMP_APPROACH"
	player.call("_physics_process", 0.016)
	if player.target_position == null \
			or (player.target_position as Vector3).distance_to(approach_position) > 0.1:
		_fail_jump_smoke_test(
			"Jump autopilot did not stage at the gate approach marker. expected=%s actual=%s staged=%d" % [
				str(approach_position),
				str(player.target_position),
				player.staged_jump_gate_id,
			]
		)
		return
	player.nav_mode = "MANUAL"
	GlobalState.active_target = outbound_gate
	if get_jump_block_reason(outbound_gate) != "Move within jump range before activation.":
		_fail_jump_smoke_test("Out-of-range jump was not rejected.")
		return
	_position_player_for_gate_test(outbound_gate)
	if get_jump_block_reason(outbound_gate) != "" or not request_gate_jump(outbound_gate):
		_fail_jump_smoke_test("Could not request outbound jump.")
		return
	await system_changed
	if GlobalState.current_system_id != "test_system":
		_fail_jump_smoke_test("Outbound jump loaded the wrong system.")
		return
	if not is_equal_approx(player.get("health"), starting_health) or not is_equal_approx(player.get("current_shield"), starting_shield):
		_fail_jump_smoke_test("Player health or shield changed during travel.")
		return

	var return_gate := _find_gate(get_active_system_root(), "test_to_start")
	if not return_gate:
		_fail_jump_smoke_test("Return gate was not found.")
		return
	var expected_arrival: Vector3 = return_gate.call("get_arrival_transform").origin
	if player.global_position.distance_to(expected_arrival) > 0.1:
		_fail_jump_smoke_test("Player did not arrive at the paired gate marker.")
		return
	var camera_pivot := player.get_node_or_null("CameraPivot") as Node3D
	if not camera_pivot or camera_pivot.global_position.distance_to(player.global_position) > 0.1:
		_fail_jump_smoke_test("Camera pivot did not follow the player across the system change.")
		return

	arrival_cooldown_until_msec = 0
	_position_player_for_gate_test(return_gate)
	if not request_gate_jump(return_gate):
		_fail_jump_smoke_test("Could not request return jump.")
		return
	await system_changed
	if GlobalState.current_system_id != "start_system":
		_fail_jump_smoke_test("Return jump loaded the wrong system.")
		return
	if not is_equal_approx(player.get("health"), starting_health) or not is_equal_approx(player.get("current_shield"), starting_shield):
		_fail_jump_smoke_test("Player state changed on the return jump.")
		return

	if "--save-smoke-test" in OS.get_cmdline_user_args():
		if not await _run_save_smoke_assertions():
			return

	print("[JumpSmokeTest] PASS: two-way travel and player runtime state verified.")
	delete_savegame()
	get_tree().quit(0)

func _run_dock_smoke_test() -> void:
	await get_tree().process_frame
	GlobalState.paused = false
	var system_root := get_active_system_root()
	var stations: Array[Node3D] = []
	for candidate in get_tree().get_nodes_in_group("station"):
		if candidate is Node3D and system_root.is_ancestor_of(candidate):
			stations.append(candidate)
	if stations.is_empty():
		_fail_dock_smoke_test("No dockable stations were found.")
		return

	for station in stations:
		var docking_position: Vector3 = station.global_position
		if station.has_method("get_docking_position"):
			docking_position = station.get_docking_position(player.global_position)
		var approach_direction := (docking_position - station.global_position).normalized()
		if approach_direction.length_squared() < 0.001:
			approach_direction = Vector3.FORWARD
		player.global_position = docking_position + approach_direction * 28.0
		player.look_at(docking_position, Vector3.UP)
		player.sync_camera_to_ship()
		player.velocity = Vector3.ZERO
		player.current_speed = 0.0
		GlobalState.active_target = station
		player.nav_mode = "DOCK"

		for frame in range(240):
			await get_tree().physics_frame
			if player.is_docked:
				break
		if not player.is_docked:
			var final_docking_position: Vector3 = station.get_docking_position(player.global_position) \
				if station.has_method("get_docking_position") else station.global_position
			_fail_dock_smoke_test(
				"Docking did not complete for '%s': remaining=%.2f speed=%.2f mode=%s stuck=%.2f." % [
					station.name,
					player.global_position.distance_to(final_docking_position),
					player.current_speed,
					player.nav_mode,
					player.dock_stuck_timer,
				]
			)
			return

		var ui := GlobalState.get_ui_manager()
		if ui and ui.has_method("undock_player"):
			ui.undock_player()
		await get_tree().process_frame

	print("[DockSmokeTest] PASS: all active-system dockables completed approach and docking.")
	delete_savegame()
	get_tree().quit(0)

func _run_restart_smoke_test() -> void:
	await get_tree().process_frame
	var ui := GlobalState.get_ui_manager()
	if not ui:
		_fail_restart_smoke_test("UIManager was not found.")
		return

	var loading_deadline_msec := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < loading_deadline_msec:
		var panel = ui.get("loading_panel")
		if panel == null or not is_instance_valid(panel):
			break
		await get_tree().create_timer(0.05).timeout

	var loading_panel = ui.get("loading_panel")
	if loading_panel != null and is_instance_valid(loading_panel):
		_fail_restart_smoke_test("Loading screen did not complete.")
		return

	var phase := int(Engine.get_meta("restart_smoke_phase", 0))
	if phase == 0:
		Engine.set_meta("restart_smoke_phase", 1)
		ui.call("_restart_game")
		return

	Engine.remove_meta("restart_smoke_phase")
	print("[RestartSmokeTest] PASS: restarted scene adopted warm service state and completed loading.")
	delete_savegame()
	get_tree().quit(0)

func _run_autopilot_smoke_test() -> void:
	await get_tree().process_frame
	var original_transform := player.global_transform
	var obstacle := StaticBody3D.new()
	obstacle.name = "AutopilotSmokeObstacle"
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = 8.0
	collision.shape = sphere
	obstacle.add_child(collision)
	get_active_system_root().add_child(obstacle)

	player.global_position = Vector3(10000.0, 0.0, 10000.0)
	obstacle.global_position = Vector3(10200.0, 0.0, 10000.0)
	obstacle.add_to_group("asteroid")
	var asteroid_result: Dictionary = player.call(
		"_get_autopilot_avoidance",
		Vector3(10400.0, 0.0, 10000.0),
		null
	)
	if not bool(asteroid_result.get("is_avoiding", false)) \
			or asteroid_result.get("obstacle") != obstacle:
		obstacle.queue_free()
		player.global_transform = original_transform
		_fail_autopilot_smoke_test("Asteroid directly on route was not avoided.")
		return

	obstacle.remove_from_group("asteroid")
	obstacle.add_to_group("celestial")
	sphere.radius = 300.0
	obstacle.global_position = Vector3(10250.0, 0.0, 10000.0)
	player.global_position = Vector3(10000.0, 0.0, 10350.0)
	player.call("_clear_avoidance_state")
	var planet_result: Dictionary = player.call(
		"_get_autopilot_avoidance",
		Vector3(10500.0, 0.0, 10350.0),
		null
	)
	if not bool(planet_result.get("is_avoiding", false)) \
			or planet_result.get("obstacle") != obstacle:
		var calculated_radius: float = player.call("_get_obstacle_radius", obstacle)
		var calculated_margin: float = player.call("_get_obstacle_safety_margin", obstacle)
		obstacle.queue_free()
		player.global_transform = original_transform
		_fail_autopilot_smoke_test(
			"Planet safety envelope was not enforced. radius=%.1f margin=%.1f result=%s" % [
				calculated_radius,
				calculated_margin,
				str(planet_result),
			]
		)
		return

	obstacle.queue_free()
	player.global_transform = original_transform
	player.call("_clear_avoidance_state")
	print("[AutopilotSmokeTest] PASS: asteroid route avoidance and planet safety clearance verified.")
	delete_savegame()
	get_tree().quit(0)

func _run_economy_smoke_test() -> void:
	await get_tree().process_frame
	GlobalState.paused = false
	GlobalState.reset_for_restart()
	GlobalState.player = player

	var asteroid: Node = null
	for candidate in get_tree().get_nodes_in_group("asteroid"):
		if get_active_system_root().is_ancestor_of(candidate):
			asteroid = candidate
			break
	if not asteroid:
		_fail_economy_smoke_test("No asteroid was available for mining.")
		return

	asteroid.set("resources", 25.0)
	GlobalState.mining_yield = 7.0
	asteroid.call("mine")
	if GlobalState.cargo_type != GlobalState.CargoType.ORE \
			or not is_equal_approx(GlobalState.cargo, 7.0) \
			or not is_equal_approx(float(asteroid.get("resources")), 18.0):
		_fail_economy_smoke_test("Mining did not transfer ore into cargo correctly.")
		return

	GlobalState.cargo = GlobalState.cargo_max - 2.0
	asteroid.call("mine")
	if not is_equal_approx(GlobalState.cargo, GlobalState.cargo_max) \
			or not is_equal_approx(float(asteroid.get("resources")), 16.0):
		_fail_economy_smoke_test("Mining did not top off cargo at its exact capacity.")
		return
	asteroid.call("mine")
	if not is_equal_approx(GlobalState.cargo, GlobalState.cargo_max) \
			or not is_equal_approx(float(asteroid.get("resources")), 16.0):
		_fail_economy_smoke_test("A full cargo hold accepted additional ore.")
		return

	GlobalState.clear_cargo()
	if not GlobalState.accept_special(
		"Economy Test Part",
		"Regression cargo",
		"Test Outpost",
		"Main Station"
	):
		_fail_economy_smoke_test("Could not load special cargo for exclusivity test.")
		return
	asteroid.call("mine")
	if GlobalState.cargo_type != GlobalState.CargoType.SPECIAL \
			or not is_equal_approx(float(asteroid.get("resources")), 16.0):
		_fail_economy_smoke_test("Mining replaced special cargo or consumed asteroid resources.")
		return

	GlobalState.clear_cargo()
	GlobalState.add_ore(20.0)
	if not GlobalState.deposit_ore(20.0) \
			or not is_equal_approx(GlobalState.player_storage_ore, 20.0) \
			or GlobalState.cargo_type != GlobalState.CargoType.EMPTY:
		_fail_economy_smoke_test("Station ore storage did not receive deposited cargo.")
		return

	GlobalState.add_ore(12.0)
	var credits_before_sale := GlobalState.player_credits
	var ui := GlobalState.get_ui_manager()
	if not ui:
		_fail_economy_smoke_test("UIManager was not available for the ore sale.")
		return
	ui.call("_sell_ore")
	if GlobalState.player_credits != credits_before_sale + 12 \
			or GlobalState.cargo_type != GlobalState.CargoType.EMPTY:
		_fail_economy_smoke_test("Selling ore did not update credits and clear cargo.")
		return

	GlobalState.player_credits = 2000
	GlobalState.player_storage_ore = 250.0
	if not GlobalState.purchase_upgrade("power", "standard") \
			or int(GlobalState.current_upgrades["power"]["tier"]) != 2 \
			or not is_equal_approx(GlobalState.power_capacity, 350.0):
		_fail_economy_smoke_test("A valid powerplant upgrade did not apply.")
		return
	if not GlobalState.purchase_upgrade("engine", "speed") \
			or int(GlobalState.current_upgrades["engine"]["tier"]) != 2 \
			or not is_equal_approx(GlobalState.engine_speed_mult, 1.2):
		_fail_economy_smoke_test("A valid engine upgrade did not apply.")
		return

	GlobalState.power_capacity = GlobalState.get_current_power_draw()
	GlobalState.player_credits = 10000
	GlobalState.player_storage_ore = 10000.0
	var credits_before_rejection := GlobalState.player_credits
	if GlobalState.purchase_upgrade("mining", "rapid") \
			or GlobalState.player_credits != credits_before_rejection \
			or int(GlobalState.current_upgrades["mining"]["tier"]) != 1:
		_fail_economy_smoke_test("An over-budget upgrade was accepted or charged resources.")
		return

	print("[EconomySmokeTest] PASS: mining, cargo limits, storage, sale, and upgrades verified.")
	delete_savegame()
	get_tree().quit(0)

func _fail_economy_smoke_test(message: String) -> void:
	push_error("[EconomySmokeTest] FAIL: " + message)
	delete_savegame()
	get_tree().quit(1)

func _fail_autopilot_smoke_test(message: String) -> void:
	push_error("[AutopilotSmokeTest] FAIL: " + message)
	delete_savegame()
	get_tree().quit(1)

func _fail_restart_smoke_test(message: String) -> void:
	if Engine.has_meta("restart_smoke_phase"):
		Engine.remove_meta("restart_smoke_phase")
	push_error("[RestartSmokeTest] FAIL: " + message)
	delete_savegame()
	get_tree().quit(1)

func _fail_dock_smoke_test(message: String) -> void:
	push_error("[DockSmokeTest] FAIL: " + message)
	delete_savegame()
	get_tree().quit(1)

func _position_player_for_gate_test(gate: Node3D) -> void:
	GlobalState.active_target = gate
	player.global_position = gate.global_position + gate.global_transform.basis.z.normalized() * 80.0
	player.look_at(gate.global_position, Vector3.UP)
	player.velocity = Vector3.ZERO

func _fail_jump_smoke_test(message: String) -> void:
	push_error("[JumpSmokeTest] FAIL: " + message)
	delete_savegame()
	get_tree().quit(1)

func _run_save_smoke_assertions() -> bool:
	var asteroid: Node = null
	for candidate in get_tree().get_nodes_in_group("asteroid"):
		if get_active_system_root().is_ancestor_of(candidate):
			asteroid = candidate
			break
	if not asteroid:
		_fail_jump_smoke_test("Save test could not find an asteroid.")
		return false

	GlobalState.player_credits = 4321
	GlobalState.cargo_type = GlobalState.CargoType.ORE
	GlobalState.cargo = 27.0
	QuestManager.active_quest = {
		"title": "Save Test Contract",
		"objective_type": "DELIVER_ORE",
		"amount_required": 40.0,
		"partial_delivered": 11.0,
		"faction": "zenith",
	}
	asteroid.set("resources", 123.0)
	record_persistent_entity_state(asteroid)
	if not save_game():
		_fail_jump_smoke_test("Save file could not be written.")
		return false

	GlobalState.player_credits = 1
	GlobalState.cargo = 0.0
	GlobalState.cargo_type = GlobalState.CargoType.EMPTY
	QuestManager.active_quest = {}
	asteroid.set("resources", 299.0)
	if not await load_game():
		_fail_jump_smoke_test("Save file could not be loaded.")
		return false
	if GlobalState.player_credits != 4321 or not is_equal_approx(GlobalState.cargo, 27.0):
		_fail_jump_smoke_test("Global player state did not restore.")
		return false
	if QuestManager.active_quest.get("title", "") != "Save Test Contract":
		_fail_jump_smoke_test("Quest state did not restore.")
		return false
	if not is_equal_approx(float(asteroid.get("resources")), 123.0):
		_fail_jump_smoke_test("Asteroid state did not restore.")
		return false
	if _is_valid_save_data({"version": SAVE_VERSION}) or _is_valid_save_data({
		"version": SAVE_VERSION + 1,
		"current_system_id": "start_system",
		"player": {},
		"global": {},
		"quest": {},
		"systems": {},
	}):
		_fail_jump_smoke_test("Malformed or unsupported save data was accepted.")
		return false
	print("[SaveSmokeTest] PASS: player, quest, system state, and validation verified.")
	return true
