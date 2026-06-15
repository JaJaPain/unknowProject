extends Node3D

signal system_changed(system_id: String, arrival_gate_id: String)
signal startup_load_completed(save_loaded: bool)

const ARRIVAL_COOLDOWN_SECONDS := 2.5
const JUMP_ENTRY_DURATION := 3.2
const JUMP_EXIT_DURATION := 0.9
const SAVE_VERSION := SaveMigrator.CURRENT_VERSION
const SAVE_PATH := "user://savegame.json"
const NPC_SHIP_SCENE := preload("res://scenes/npc_ship.tscn")
const CampaignSlotRegistryType := preload(
	"res://scripts/persistence/CampaignSlotRegistry.gd"
)
const CampaignCheckpointStoreType := preload(
	"res://scripts/persistence/CampaignCheckpointStore.gd"
)
const CampaignChronicleStoreType := preload(
	"res://scripts/persistence/CampaignChronicleStore.gd"
)

@onready var system_container: Node3D = $SystemContainer
@onready var player: CharacterBody3D = $PlayerShip
@onready var transition_fx: CanvasLayer = $JumpTransitionFX

var transition_in_progress: bool = false
var jump_request_pending: bool = false
var arrival_cooldown_until_msec: int = 0
var system_states: Dictionary = {}
var last_arrival_gate_id: String = ""
var startup_save_loaded: bool = false
var startup_load_finished: bool = false
var scene_ready_msec: int = 0
var system_registry: SystemRegistry
var campaign_slot_registry: CampaignSlotRegistry
var campaign_checkpoint_store: CampaignCheckpointStore
var campaign_chronicle_store: CampaignChronicleStore
var active_campaign_slot_id: String = ""
var restoring_safe_checkpoint: bool = false
var last_autosave_notification_key: String = ""
var last_autosave_notification_msec: int = 0

func _ready() -> void:
	scene_ready_msec = Time.get_ticks_msec()
	system_registry = SystemRegistry.load_default()
	if not system_registry.is_valid():
		push_error(
			"[GameRoot] System registry is invalid: %s" %
			system_registry.validation.summary()
		)
		get_tree().quit(1)
		return
	var start_definition := system_registry.get_system("system.start")
	var start_scene := system_registry.load_scene("system.start")
	if start_definition == null or start_scene == null:
		push_error("[GameRoot] Registered starting system could not be loaded.")
		get_tree().quit(1)
		return
	var system_root := start_scene.instantiate() as Node3D
	if system_root == null:
		push_error("[GameRoot] Registered starting system has an invalid root.")
		get_tree().quit(1)
		return
	system_container.add_child(system_root)
	GlobalState.active_system_root = system_root
	GlobalState.current_system_id = start_definition.legacy_id
	QuestManager.quest_completed.connect(_on_quest_completed_chronicle)
	QuestManager.quest_abandoned.connect(_on_quest_abandoned_chronicle)
	if "--performance-baseline" in OS.get_cmdline_user_args():
		call_deferred("_run_performance_baseline")
	elif "--core-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_core_smoke_test")
	elif "--services-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_services_smoke_test")
	elif "--mission-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_mission_smoke_test")
	elif "--combat-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_combat_smoke_test")
	elif "--economy-smoke-test" in OS.get_cmdline_user_args():
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
	var identity_validation := _validate_persistent_entities(
		get_active_system_root()
	)
	if not identity_validation.is_valid():
		push_error(
			"[GameRoot] Cannot leave system with invalid persistent identities: %s"
			% JSON.stringify(identity_validation.to_dict())
		)
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
	var runtime_system_id := system_registry.runtime_system_id(
		destination_system_id
	)
	var runtime_gate_id := system_registry.runtime_gate_id(arrival_gate_id)
	var packed_system := system_registry.load_scene(destination_system_id)
	if not packed_system:
		jump_request_pending = false
		push_warning("[GameRoot] Unknown destination system '%s'." % destination_system_id)
		return
	if runtime_system_id.is_empty() or runtime_gate_id.is_empty():
		jump_request_pending = false
		push_warning(
			"[GameRoot] Destination system or arrival gate is not registered."
		)
		return

	var new_system := packed_system.instantiate() as Node3D
	var arrival_gate := _find_gate_in_tree(new_system, runtime_gate_id)
	if not arrival_gate:
		new_system.free()
		jump_request_pending = false
		push_error("[GameRoot] Destination gate '%s' was not found in '%s'." % [
			runtime_gate_id, runtime_system_id
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
	if not _capture_current_system_state():
		push_error("[GameRoot] System state capture failed during gate travel.")
	GlobalState.active_target = null
	GlobalState.active_system_entities.clear()

	var old_system := get_active_system_root()
	GlobalState.active_system_root = null
	if old_system and is_instance_valid(old_system):
		old_system.queue_free()
		await get_tree().process_frame

	system_container.add_child(new_system)
	GlobalState.active_system_root = new_system
	GlobalState.current_system_id = runtime_system_id
	await get_tree().process_frame
	_restore_system_state(runtime_system_id, new_system)

	var arrival_transform: Transform3D = arrival_gate.call("get_arrival_transform")
	player.global_transform = arrival_transform
	last_arrival_gate_id = runtime_gate_id

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
	request_safe_checkpoint("gate_arrival", arrival_gate)
	system_changed.emit(runtime_system_id, runtime_gate_id)

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
	if not entity:
		return
	var validation := _validate_persistent_entities(get_active_system_root())
	if not validation.is_valid():
		push_error(
			"[GameRoot] Refusing state update with invalid identities: %s" %
			JSON.stringify(validation.to_dict())
		)
		return
	var entity_result := WorldIdentity.validate_node(entity, true)
	if not entity_result.is_valid():
		push_error(
			"[GameRoot] Refusing invalid persistent entity state: %s" %
			JSON.stringify(entity_result.to_dict())
		)
		return
	var entity_id := str(entity.call("get_world_id"))
	var state: Dictionary = system_states.get(GlobalState.current_system_id, {})
	var entities: Dictionary = state.get("entities", {})
	entities[entity_id] = WorldIdentity.state_envelope(entity)
	state["entities"] = entities
	system_states[GlobalState.current_system_id] = state

func _capture_current_system_state() -> bool:
	var system_root := get_active_system_root()
	if not system_root:
		return false
	var persistent_entities := _get_persistent_entities(system_root)
	var validation := WorldIdentity.validate_collection(
		persistent_entities,
		true
	)
	if not validation.is_valid():
		push_error(
			"[GameRoot] Persistent entity validation failed: %s" %
			JSON.stringify(validation.to_dict())
		)
		return false
	var state: Dictionary = system_states.get(GlobalState.current_system_id, {})
	var entities: Dictionary = state.get("entities", {})
	for entity: Node in persistent_entities:
		var entity_id := str(entity.call("get_world_id"))
		entities[entity_id] = WorldIdentity.state_envelope(entity)
	state["entities"] = entities
	system_states[GlobalState.current_system_id] = state
	return true

func _get_persistent_entities(system_root: Node3D) -> Array:
	var entities: Array = []
	if system_root == null:
		return entities
	for entity in get_tree().get_nodes_in_group(
		WorldIdentity.STATEFUL_GROUP
	):
		if is_instance_valid(entity) and system_root.is_ancestor_of(entity):
			entities.append(entity)
	return entities

func _validate_persistent_entities(system_root: Node3D) -> ValidationResult:
	var result := WorldIdentity.validate_collection(
		_get_world_identity_entities(system_root),
		false
	)
	result.merge(WorldIdentity.validate_collection(
		_get_persistent_entities(system_root),
		true
	), "stateful")
	return result

func _get_world_identity_entities(system_root: Node3D) -> Array:
	var entities: Array = []
	if system_root == null:
		return entities
	for entity in get_tree().get_nodes_in_group(
		WorldIdentity.IDENTITY_GROUP
	):
		if is_instance_valid(entity) and system_root.is_ancestor_of(entity):
			entities.append(entity)
	return entities

func _restore_system_state(system_id: String, system_root: Node3D) -> void:
	var state: Dictionary = system_states.get(system_id, {})
	var entities: Dictionary = state.get("entities", {})
	if entities.is_empty():
		return
	var restored_ids: Dictionary = {}
	for entity in get_tree().get_nodes_in_group(
		WorldIdentity.STATEFUL_GROUP
	):
		if is_instance_valid(entity) and system_root.is_ancestor_of(entity) and entity.has_method("get_world_id"):
			var entity_id: String = entity.get_world_id()
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
	var prepared := _capture_prepared_runtime_state()
	if not bool(prepared.get("ok", false)):
		push_warning(
			"[GameRoot] Save preparation failed: %s" %
			prepared.get("error", "unknown error")
		)
		return false
	if not SaveMigrator.write_current(SAVE_PATH, prepared["data"]):
		push_warning("[GameRoot] Could not write save file.")
		return false
	return true

func request_autosave() -> bool:
	return save_game()


func request_safe_checkpoint(
	source_reason: String,
	safe_entity: Node = null
) -> bool:
	if restoring_safe_checkpoint:
		return true
	if transition_in_progress or jump_request_pending:
		return false
	if player == null or not is_instance_valid(player) \
			or bool(player.get("destroyed")):
		return false
	var prepared := _capture_prepared_runtime_state()
	if not bool(prepared.get("ok", false)):
		return false
	if not _ensure_campaign_checkpoint_store(prepared["data"]):
		push_warning("[GameRoot] Campaign checkpoint store is unavailable.")
		_notify_checkpoint_failure()
		return false
	_sync_checkpoint_chronicle_context()
	var safe_location := _safe_location_for(source_reason, safe_entity)
	if safe_location.is_empty():
		push_warning("[GameRoot] Safe checkpoint location is unavailable.")
		_notify_checkpoint_failure()
		return false
	var captured := campaign_checkpoint_store.capture_autosave(
		prepared["data"],
		safe_location,
		source_reason
	)
	if not bool(captured.get("ok", false)):
		push_warning(
			"[GameRoot] Campaign checkpoint failed: %s" %
			captured.get("error", "unknown error")
		)
		if not bool(captured.get("coalesced", false)):
			_notify_checkpoint_failure()
		return false
	if not SaveMigrator.write_current(SAVE_PATH, prepared["data"]):
		push_warning(
			"[GameRoot] Campaign checkpoint saved, but the compatibility save could not be updated."
		)
	if campaign_slot_registry != null:
		campaign_slot_registry.update_checkpoint_summary(
			active_campaign_slot_id,
			str(captured.get("checkpoint_id", "")),
			source_reason,
			str(safe_location.get("system_id", "")),
			true
		)
	_notify_autosave_success(source_reason, safe_location)
	return true


func get_manual_checkpoint_status() -> Dictionary:
	if player == null or not is_instance_valid(player):
		return _manual_checkpoint_blocked(
			"player_unavailable",
			"The player ship is unavailable."
		)
	if bool(player.get("destroyed")):
		return _manual_checkpoint_blocked(
			"player_dead",
			"Manual saving is unavailable while the ship is destroyed."
		)
	if transition_in_progress or jump_request_pending:
		return _manual_checkpoint_blocked(
			"jump_in_progress",
			"Manual saving is unavailable during jump travel."
		)
	if campaign_checkpoint_store == null:
		_initialize_campaign_registry()
	if campaign_checkpoint_store == null \
			or not campaign_checkpoint_store.is_valid():
		return _manual_checkpoint_blocked(
			"no_campaign",
			"No campaign checkpoint store is available."
		)
	if campaign_checkpoint_store.is_transaction_active():
		return _manual_checkpoint_blocked(
			"transaction_active",
			"Another campaign save is already in progress."
		)
	if not campaign_checkpoint_store.has_active_safe_checkpoint():
		return _manual_checkpoint_blocked(
			"no_safe_checkpoint",
			"Reach a station or jumpgate before creating a manual checkpoint."
		)
	return {
		"available": true,
		"block_code": "",
		"block_reason": "",
		"manual": campaign_checkpoint_store.list_manual_checkpoints(),
	}


func request_manual_checkpoint(
	slot_index: int,
	display_name: String,
	overwrite: bool = false,
	refresh_if_docked: bool = true
) -> Dictionary:
	var status := get_manual_checkpoint_status()
	if not bool(status.get("available", false)):
		var blocked := {
			"ok": false,
			"block_code": status.get("block_code", ""),
			"error": status.get("block_reason", "Manual save is unavailable."),
		}
		_notify_system_warning(str(blocked["error"]))
		return blocked
	if refresh_if_docked and bool(player.get("is_docked")):
		var ui := GlobalState.get_ui_manager()
		var station: Node = ui.get("current_station") if ui else null
		if station == null or not is_instance_valid(station):
			return {
				"ok": false,
				"block_code": "dock_unavailable",
				"error": "The current dock could not be identified.",
			}
		if not request_safe_checkpoint("dock", station):
			return {
				"ok": false,
				"block_code": "dock_refresh_failed",
				"error": "The docked safe checkpoint could not be refreshed.",
			}
	var copied := campaign_checkpoint_store.copy_active_to_manual(
		slot_index,
		display_name,
		overwrite
	)
	if bool(copied.get("ok", false)):
		GlobalState.emit_chatter(
			"SYSTEM",
			"Manual checkpoint \"%s\" saved." %
				copied.get("display_name", "Manual Checkpoint"),
			Color(0.0, 0.9, 0.9)
		)
	elif not bool(copied.get("requires_overwrite", false)):
		_notify_checkpoint_failure()
	return copied


func load_manual_checkpoint(slot_index: int) -> bool:
	if transition_in_progress or jump_request_pending:
		return false
	if campaign_checkpoint_store == null:
		_initialize_campaign_registry()
	if campaign_checkpoint_store == null:
		return false
	var restored := campaign_checkpoint_store.runtime_state_from_manual(
		slot_index
	)
	if not bool(restored.get("ok", false)):
		return false
	if campaign_chronicle_store == null:
		_initialize_campaign_chronicle()
	if campaign_chronicle_store == null:
		return false
	var branched := campaign_chronicle_store.branch_from_checkpoint({
		"id": restored.get("checkpoint_id", ""),
		"timeline_id": restored.get("timeline_id", ""),
		"chronicle_head_event_id":
			restored.get("chronicle_head_event_id", ""),
	})
	if not bool(branched.get("ok", false)):
		_notify_system_warning(
			"The selected checkpoint could not start a new timeline."
		)
		return false
	_reopen_campaign_checkpoint_store()
	_sync_checkpoint_chronicle_context()
	return await _apply_campaign_checkpoint_state(restored)


func rename_manual_checkpoint(
	slot_index: int,
	display_name: String
) -> Dictionary:
	if campaign_checkpoint_store == null:
		_initialize_campaign_registry()
	if campaign_checkpoint_store == null:
		return {"ok": false, "error": "Campaign storage is unavailable."}
	var renamed := campaign_checkpoint_store.rename_manual_checkpoint(
		slot_index,
		display_name
	)
	if not bool(renamed.get("ok", false)):
		_notify_system_warning(str(renamed.get("error", "")))
	return renamed


func get_campaign_ui_state() -> Dictionary:
	if campaign_slot_registry == null:
		_initialize_campaign_registry()
	if campaign_slot_registry == null:
		return {
			"ok": false,
			"error": "Campaign storage is unavailable.",
			"slots": [],
			"selected_slot_id": "",
			"manual": [],
		}
	return {
		"ok": true,
		"slots": campaign_slot_registry.enumerate_slots(),
		"selected_slot_id": campaign_slot_registry.selected_slot_id,
		"manual":
			campaign_checkpoint_store.list_manual_checkpoints()
			if campaign_checkpoint_store != null
			else [],
	}


func create_campaign_in_slot(
	slot_id: String,
	display_name: String
) -> Dictionary:
	var prepared := _capture_prepared_runtime_state()
	if not bool(prepared.get("ok", false)):
		return {
			"ok": false,
			"error": prepared.get(
				"error",
				"Current gameplay state could not start a campaign."
			),
		}
	if campaign_slot_registry == null:
		_initialize_campaign_registry()
	if campaign_slot_registry == null:
		return {"ok": false, "error": "Campaign storage is unavailable."}
	var created := campaign_slot_registry.create_campaign(
		slot_id,
		display_name,
		"prototype-phase-2",
		prepared["data"],
		system_registry
	)
	if not bool(created.get("ok", false)):
		_notify_system_warning(str(created.get("error", "")))
		return created
	active_campaign_slot_id = slot_id
	var slot_path := "%s/%s" % [
		campaign_slot_registry.root_path,
		slot_id,
	]
	campaign_checkpoint_store = CampaignCheckpointStoreType.open(slot_path)
	_initialize_campaign_chronicle()
	GlobalState.emit_chatter(
		"SYSTEM",
		"Campaign \"%s\" created." %
			created.get("slot", {}).get("display_name", "Campaign"),
		Color(0.0, 0.9, 0.9)
	)
	return created


func select_and_load_campaign(slot_id: String) -> Dictionary:
	if campaign_slot_registry == null:
		_initialize_campaign_registry()
	if campaign_slot_registry == null:
		return {"ok": false, "error": "Campaign storage is unavailable."}
	var selected := campaign_slot_registry.select_campaign(slot_id)
	if not bool(selected.get("ok", false)):
		_notify_system_warning(str(selected.get("error", "")))
		return selected
	active_campaign_slot_id = slot_id
	var slot_path := "%s/%s" % [
		campaign_slot_registry.root_path,
		slot_id,
	]
	campaign_checkpoint_store = CampaignCheckpointStoreType.open(slot_path)
	if not campaign_checkpoint_store.is_valid():
		var invalid_store_failure := {
			"ok": false,
			"error": "The selected campaign could not be loaded.",
		}
		_notify_system_warning(invalid_store_failure["error"])
		return invalid_store_failure
	_initialize_campaign_chronicle()
	if campaign_chronicle_store == null \
			or not await _load_campaign_checkpoint():
		var failure := {
			"ok": false,
			"error": "The selected campaign could not be loaded.",
		}
		_notify_system_warning(failure["error"])
		return failure
	return selected


func rename_campaign_slot(
	slot_id: String,
	display_name: String
) -> Dictionary:
	if campaign_slot_registry == null:
		_initialize_campaign_registry()
	if campaign_slot_registry == null:
		return {"ok": false, "error": "Campaign storage is unavailable."}
	var renamed := campaign_slot_registry.rename_campaign(
		slot_id,
		display_name
	)
	if not bool(renamed.get("ok", false)):
		_notify_system_warning(str(renamed.get("error", "")))
	return renamed


func delete_campaign_slot(slot_id: String) -> Dictionary:
	if campaign_slot_registry == null:
		_initialize_campaign_registry()
	if campaign_slot_registry == null:
		return {"ok": false, "error": "Campaign storage is unavailable."}
	var deleted := campaign_slot_registry.delete_campaign(slot_id)
	if not bool(deleted.get("ok", false)):
		_notify_system_warning(str(deleted.get("error", "")))
		return deleted
	if active_campaign_slot_id == slot_id:
		active_campaign_slot_id = ""
		campaign_checkpoint_store = null
		campaign_chronicle_store = null
	GlobalState.emit_chatter(
		"SYSTEM",
		"Campaign slot deleted.",
		Color(0.0, 0.9, 0.9)
	)
	return deleted


func _notify_autosave_success(
	source_reason: String,
	safe_location: Dictionary
) -> void:
	var key := "%s|%s|%s" % [
		source_reason,
		safe_location.get("station_id", ""),
		safe_location.get("gate_id", ""),
	]
	var now := Time.get_ticks_msec()
	if key == last_autosave_notification_key \
			and now - last_autosave_notification_msec < 1000:
		return
	last_autosave_notification_key = key
	last_autosave_notification_msec = now
	GlobalState.emit_chatter(
		"SYSTEM",
		"Campaign checkpoint saved.",
		Color(0.0, 0.9, 0.9)
	)


func _notify_checkpoint_failure() -> void:
	_notify_system_warning(
		"Checkpoint could not be saved. Your previous save is still safe."
	)


func _notify_system_warning(message: String) -> void:
	var clean_message := message
	if clean_message.contains("user://") \
			or clean_message.contains(":\\") \
			or clean_message.contains(":/"):
		clean_message = "The requested campaign action could not be completed."
	GlobalState.emit_chatter(
		"SYSTEM WARNING",
		clean_message,
		Color(1.0, 0.45, 0.3)
	)


func _manual_checkpoint_blocked(
	code: String,
	reason: String
) -> Dictionary:
	return {
		"available": false,
		"block_code": code,
		"block_reason": reason,
		"manual":
			campaign_checkpoint_store.list_manual_checkpoints()
			if campaign_checkpoint_store != null
			else [],
	}


func _capture_prepared_runtime_state() -> Dictionary:
	if not _capture_current_system_state():
		return {
			"ok": false,
			"error": "Persistent entity identity validation failed.",
		}
	var quest_state := QuestManager.capture_active_quest()
	if QuestManager.is_quest_active() and quest_state.is_empty():
		return {
			"ok": false,
			"error": "Mission validation failed: %s" %
				QuestManager.last_validation_error,
		}
	return SaveMigrator.prepare_for_save({
		"version": SAVE_VERSION,
		"current_system_id": GlobalState.current_system_id,
		"arrival_gate_id": last_arrival_gate_id,
		"player": _capture_player_state(),
		"global": _capture_global_state(),
		"quest": quest_state,
		"systems": system_states.duplicate(true),
	}, system_registry)


func _initialize_campaign_registry() -> void:
	campaign_slot_registry = CampaignSlotRegistryType.open()
	if campaign_slot_registry == null \
			or not campaign_slot_registry.is_valid():
		campaign_slot_registry = null
		return
	active_campaign_slot_id = campaign_slot_registry.selected_slot_id
	if active_campaign_slot_id.is_empty():
		return
	var slot_path := "%s/%s" % [
		campaign_slot_registry.root_path,
		active_campaign_slot_id,
	]
	campaign_checkpoint_store = CampaignCheckpointStoreType.open(slot_path)
	if not campaign_checkpoint_store.is_valid():
		push_warning(
			"[GameRoot] Selected campaign checkpoint is unavailable: %s" %
			campaign_checkpoint_store.validation.summary()
		)
		campaign_checkpoint_store = null
		campaign_chronicle_store = null
		return
	_initialize_campaign_chronicle()


func _ensure_campaign_checkpoint_store(
	prepared_runtime_state: Dictionary
) -> bool:
	if campaign_checkpoint_store != null \
			and campaign_checkpoint_store.is_valid():
		return true
	if campaign_slot_registry == null:
		_initialize_campaign_registry()
	if campaign_slot_registry == null:
		return false
	if not campaign_slot_registry.selected_slot_id.is_empty():
		active_campaign_slot_id = campaign_slot_registry.selected_slot_id
	else:
		active_campaign_slot_id = campaign_slot_registry.first_empty_slot_id()
		if active_campaign_slot_id.is_empty():
			return false
		var created := campaign_slot_registry.create_campaign(
			active_campaign_slot_id,
			"Shiny's Campaign",
			"prototype-phase-2",
			prepared_runtime_state,
			system_registry
		)
		if not bool(created.get("ok", false)):
			push_warning(
				"[GameRoot] Campaign creation failed: %s" %
				created.get("error", "unknown error")
			)
			active_campaign_slot_id = ""
			return false
	var slot_path := "%s/%s" % [
		campaign_slot_registry.root_path,
		active_campaign_slot_id,
	]
	campaign_checkpoint_store = CampaignCheckpointStoreType.open(slot_path)
	if not campaign_checkpoint_store.is_valid():
		return false
	_initialize_campaign_chronicle()
	return campaign_chronicle_store != null


func _initialize_campaign_chronicle() -> void:
	campaign_chronicle_store = null
	if campaign_slot_registry == null or active_campaign_slot_id.is_empty():
		return
	var slot_path := "%s/%s" % [
		campaign_slot_registry.root_path,
		active_campaign_slot_id,
	]
	var opened := CampaignChronicleStoreType.open(slot_path)
	if not opened.is_valid():
		push_warning(
			"[GameRoot] Campaign chronicle is unavailable: %s" %
				opened.validation.summary()
		)
		return
	campaign_chronicle_store = opened
	_sync_checkpoint_chronicle_context()
	_import_legacy_quest_history()


func _reopen_campaign_checkpoint_store() -> void:
	if campaign_slot_registry == null or active_campaign_slot_id.is_empty():
		return
	var slot_path := "%s/%s" % [
		campaign_slot_registry.root_path,
		active_campaign_slot_id,
	]
	campaign_checkpoint_store = CampaignCheckpointStoreType.open(slot_path)


func _sync_checkpoint_chronicle_context() -> void:
	if campaign_checkpoint_store == null \
			or campaign_chronicle_store == null:
		return
	campaign_checkpoint_store.set_chronicle_context(
		campaign_chronicle_store.current_timeline_id(),
		campaign_chronicle_store.current_head_event_id()
	)


func _import_legacy_quest_history() -> void:
	if campaign_chronicle_store == null \
			or campaign_checkpoint_store == null:
		return
	var active := campaign_checkpoint_store.runtime_state_from_active()
	if not bool(active.get("ok", false)):
		return
	var history_text := ""
	if FileAccess.file_exists(QuestManager.HISTORY_FILE_PATH):
		history_text = FileAccess.get_file_as_string(
			QuestManager.HISTORY_FILE_PATH
		)
	var imported := campaign_chronicle_store.import_legacy_quest_history(
		history_text,
		str(active.get("checkpoint_id", ""))
	)
	if bool(imported.get("ok", false)):
		_sync_checkpoint_chronicle_context()


func _append_quest_chronicle_event(
	event_type: String,
	outcome: String
) -> void:
	if campaign_chronicle_store == null \
			or campaign_checkpoint_store == null \
			or QuestManager.active_quest.is_empty():
		return
	var active := campaign_checkpoint_store.runtime_state_from_active()
	if not bool(active.get("ok", false)):
		return
	var quest := QuestManager.active_quest
	var appended := campaign_chronicle_store.append_event(
		event_type,
		[campaign_chronicle_store.campaign["id"]],
		{
			"title": quest.get("title", ""),
			"objective_type": quest.get("objective_type", ""),
			"faction": quest.get("faction", ""),
			"outcome": outcome,
		},
		str(active.get("checkpoint_id", ""))
	)
	if bool(appended.get("ok", false)):
		_sync_checkpoint_chronicle_context()


func _on_quest_completed_chronicle() -> void:
	_append_quest_chronicle_event("mission_completed", "completed")


func _on_quest_abandoned_chronicle() -> void:
	_append_quest_chronicle_event("mission_abandoned", "abandoned")


func _safe_location_for(
	source_reason: String,
	safe_entity: Node
) -> Dictionary:
	var system_id := str(
		system_registry.resolve_system_id(GlobalState.current_system_id)
	)
	if source_reason in ["dock", "undock"]:
		if safe_entity == null or not is_instance_valid(safe_entity) \
				or not safe_entity.has_method("get_world_id"):
			return {}
		return {
			"type": "docked",
			"system_id": system_id,
			"station_id": str(safe_entity.call("get_world_id")),
		}
	if source_reason == "gate_arrival":
		if safe_entity == null or not is_instance_valid(safe_entity) \
				or not safe_entity.has_method("get_world_id"):
			return {}
		return {
			"type": "gate_arrival",
			"system_id": system_id,
			"gate_id": str(safe_entity.call("get_world_id")),
		}
	return {}


func _load_campaign_checkpoint() -> bool:
	var restored := campaign_checkpoint_store.runtime_state_from_active()
	return await _apply_campaign_checkpoint_state(restored)


func _apply_campaign_checkpoint_state(restored: Dictionary) -> bool:
	if not bool(restored.get("ok", false)):
		push_warning(
			"[GameRoot] Campaign checkpoint could not be loaded: %s" %
			restored.get("error", "unknown error")
		)
		return false
	var safe_location: Dictionary = restored.get(
		"safe_location",
		{}
	).duplicate(true)
	var encoded: Dictionary = restored.get("state", {}).duplicate(true)
	encoded["version"] = SAVE_VERSION
	encoded["current_system_id"] = safe_location.get(
		"system_id",
		"system.start"
	)
	encoded["arrival_gate_id"] = (
		safe_location.get("gate_id", "")
		if safe_location.get("type", "") == "gate_arrival"
		else ""
	)
	var decoded := SaveMigrator.decode_for_runtime(encoded, system_registry)
	if not bool(decoded.get("ok", false)):
		push_warning(
			"[GameRoot] Campaign checkpoint decode failed: %s" %
			decoded.get("error", "unknown error")
		)
		return false
	restoring_safe_checkpoint = true
	await _apply_save_data(decoded["data"])
	await _restore_safe_location(safe_location)
	restoring_safe_checkpoint = false
	return true


func _restore_safe_location(safe_location: Dictionary) -> void:
	var location_type := str(safe_location.get("type", "initial"))
	if location_type == "initial":
		player.is_docked = false
		return
	var entity_id := str(
		safe_location.get(
			"station_id" if location_type == "docked" else "gate_id",
			""
		)
	)
	var entity := _find_world_entity(entity_id)
	if entity == null:
		push_warning(
			"[GameRoot] Safe location entity '%s' was not found." % entity_id
		)
		return
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	player.nav_mode = "MANUAL"
	if location_type == "gate_arrival":
		player.global_transform = entity.call("get_arrival_transform")
		last_arrival_gate_id = str(entity.get("gate_id"))
		player.is_docked = false
		return
	var docking_position: Vector3 = entity.global_position
	if entity.has_method("get_docking_position"):
		docking_position = entity.call(
			"get_docking_position",
			player.global_position
		)
	player.global_position = docking_position
	player.is_docked = true
	var ui := GlobalState.get_ui_manager()
	if ui and ui.has_method("toggle_dock_menu") \
			and not bool(ui.get("dock_panel").visible):
		ui.call("toggle_dock_menu", entity, false)


func _find_world_entity(entity_id: String) -> Node3D:
	for entity in GlobalState.active_system_entities:
		if entity is Node3D and is_instance_valid(entity) \
				and entity.has_method("get_world_id") \
				and str(entity.call("get_world_id")) == entity_id:
			return entity
	return null

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var loaded := SaveMigrator.load_for_runtime(
		SAVE_PATH,
		system_registry
	)
	if not bool(loaded.get("ok", false)):
		push_warning(
			"[GameRoot] Save could not be loaded: %s" %
			loaded.get("error", "unknown error")
		)
		return false
	if bool(loaded.get("migrated", false)):
		print(
			"[GameRoot] Save migrated to version %d. Backup: %s" % [
				SAVE_VERSION,
				loaded.get("backup_path", ""),
			]
		)
	await _apply_save_data(loaded["data"])
	return true

func delete_savegame() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func _load_startup_save() -> void:
	await get_tree().process_frame
	_initialize_campaign_registry()
	if campaign_checkpoint_store != null \
			and campaign_checkpoint_store.is_valid():
		startup_save_loaded = await _load_campaign_checkpoint()
	else:
		startup_save_loaded = await load_game()
		var prepared := _capture_prepared_runtime_state()
		if bool(prepared.get("ok", false)):
			_ensure_campaign_checkpoint_store(prepared["data"])
	startup_load_finished = true
	startup_load_completed.emit(startup_save_loaded)

func _is_valid_save_data(data: Variant) -> bool:
	return SaveMigrator.validate_current(
		data,
		system_registry
	).is_valid()

func _apply_save_data(data: Dictionary) -> void:
	system_states = data.get("systems", {}).duplicate(true)
	last_arrival_gate_id = str(data.get("arrival_gate_id", ""))
	_apply_global_state(data.get("global", {}))
	if not QuestManager.restore_active_quest(data.get("quest", {})):
		push_warning("[GameRoot] Save mission state failed validation during restore.")
		return
	var target_system_id := str(data.get("current_system_id", "start_system"))
	if target_system_id != GlobalState.current_system_id:
		await _load_system_without_transition(target_system_id)
	else:
		_restore_system_state(target_system_id, get_active_system_root())
	_apply_player_state(data.get("player", {}))
	var ui := GlobalState.get_ui_manager()
	if ui:
		ui.call_deferred("refresh_overview")
		if ui.has_method("refresh_restored_state"):
			ui.call_deferred("refresh_restored_state")

func _load_system_without_transition(system_id: String) -> void:
	var runtime_system_id := system_registry.runtime_system_id(system_id)
	var packed_system := system_registry.load_scene(system_id)
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
	GlobalState.current_system_id = runtime_system_id
	await get_tree().process_frame
	_restore_system_state(runtime_system_id, new_system)

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
	var loaded_upgrades: Dictionary = state.get(
		"upgrades",
		GlobalState.current_upgrades
	).duplicate(true)
	for system_name in GlobalState.current_upgrades.keys():
		var fallback: Dictionary = GlobalState.current_upgrades[system_name]
		var loaded: Dictionary = loaded_upgrades.get(system_name, fallback)
		loaded_upgrades[system_name] = {
			"tier": int(loaded.get("tier", fallback["tier"])),
			"path": str(loaded.get("path", fallback["path"])),
		}
	GlobalState.current_upgrades = loaded_upgrades
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
	GlobalState.current_upgrades["power"] = {"tier": 2, "path": "standard"}
	GlobalState.current_upgrades["engine"] = {"tier": 2, "path": "speed"}
	GlobalState.player_storage_ore = 77.0
	GlobalState.apply_upgrade_stats()

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
	player.rotate_y(PI)
	if get_jump_block_reason(outbound_gate) != "Align the ship with the jumpgate.":
		_fail_jump_smoke_test("Misaligned jump was not rejected.")
		return
	_position_player_for_gate_test(outbound_gate)
	if get_jump_block_reason(outbound_gate) != "" or not request_gate_jump(outbound_gate):
		_fail_jump_smoke_test("Could not request outbound jump.")
		return
	await get_tree().process_frame
	if not transition_in_progress \
			or player.is_physics_processing() \
			or player.is_processing_unhandled_input():
		_fail_jump_smoke_test("Player controls were not locked during the jump transition.")
		return
	await system_changed
	if GlobalState.current_system_id != "test_system":
		_fail_jump_smoke_test("Outbound jump loaded the wrong system.")
		return
	if not player.is_physics_processing() or not player.is_processing_unhandled_input():
		_fail_jump_smoke_test("Player controls were not restored after arrival.")
		return
	if not is_equal_approx(player.get("health"), starting_health) or not is_equal_approx(player.get("current_shield"), starting_shield):
		_fail_jump_smoke_test("Player health or shield changed during travel.")
		return
	if int(GlobalState.current_upgrades["engine"]["tier"]) != 2 \
			or not is_equal_approx(GlobalState.engine_speed_mult, 1.2) \
			or not is_equal_approx(GlobalState.player_storage_ore, 77.0):
		_fail_jump_smoke_test("Upgrade or station-storage state changed during outbound travel.")
		return

	var return_gate := _find_gate(get_active_system_root(), "test_to_start")
	if not return_gate:
		_fail_jump_smoke_test("Return gate was not found.")
		return
	if not _verify_gate_arrival_checkpoint(return_gate):
		return
	var expected_arrival: Vector3 = return_gate.call("get_arrival_transform").origin
	if player.global_position.distance_to(expected_arrival) > 0.1:
		_fail_jump_smoke_test("Player did not arrive at the paired gate marker.")
		return
	var camera_pivot := player.get_node_or_null("CameraPivot") as Node3D
	if not camera_pivot or camera_pivot.global_position.distance_to(player.global_position) > 0.1:
		_fail_jump_smoke_test("Camera pivot did not follow the player across the system change.")
		return
	if not _verify_generated_test_system(return_gate):
		return
	player.global_position = expected_arrival
	player.call("_clear_avoidance_state")

	_position_player_for_gate_test(return_gate)
	if get_jump_block_reason(return_gate) != "Gate drive is recalibrating after arrival.":
		_fail_jump_smoke_test("Arrival cooldown did not prevent an immediate return jump.")
		return
	arrival_cooldown_until_msec = 0
	if not request_gate_jump(return_gate):
		_fail_jump_smoke_test("Could not request return jump.")
		return
	await system_changed
	if GlobalState.current_system_id != "start_system":
		_fail_jump_smoke_test("Return jump loaded the wrong system.")
		return
	var start_arrival_gate := _find_gate(
		get_active_system_root(),
		"start_to_test"
	)
	if start_arrival_gate == null \
			or not _verify_gate_arrival_checkpoint(start_arrival_gate):
		return
	if not is_equal_approx(player.get("health"), starting_health) or not is_equal_approx(player.get("current_shield"), starting_shield):
		_fail_jump_smoke_test("Player state changed on the return jump.")
		return
	if int(GlobalState.current_upgrades["engine"]["tier"]) != 2 \
			or not is_equal_approx(GlobalState.engine_speed_mult, 1.2) \
			or not is_equal_approx(GlobalState.player_storage_ore, 77.0):
		_fail_jump_smoke_test("Upgrade or station-storage state changed on the return jump.")
		return

	if "--save-smoke-test" in OS.get_cmdline_user_args():
		if not await _run_save_smoke_assertions():
			return

	print("[JumpSmokeTest] PASS: two-way travel and player runtime state verified.")
	delete_savegame()
	get_tree().quit(0)


func _verify_gate_arrival_checkpoint(arrival_gate: Node3D) -> bool:
	if campaign_checkpoint_store == null:
		_fail_jump_smoke_test(
			"Gate arrival did not open a campaign checkpoint store."
		)
		return false
	var checkpoint := campaign_checkpoint_store.runtime_state_from_active()
	if not bool(checkpoint.get("ok", false)) \
			or checkpoint.get("source_reason", "") != "gate_arrival" \
			or checkpoint.get("safe_location", {}).get("gate_id", "") \
				!= arrival_gate.get_world_id():
		_fail_jump_smoke_test(
			"Gate arrival did not create the expected safe checkpoint."
		)
		return false
	return true


func _verify_generated_test_system(return_gate: Node3D) -> bool:
	var system_root := get_active_system_root()
	if (
		not system_root.has_method("get_generation_seed")
		or int(system_root.call("get_generation_seed")) != 4172026
	):
		_fail_jump_smoke_test("Generated system seed was missing or unstable.")
		return false

	var planets: Array = system_root.call("get_generated_planets")
	var stations: Array = system_root.call("get_generated_stations")
	var asteroid_count := 0
	for asteroid in get_tree().get_nodes_in_group("asteroid"):
		if system_root.is_ancestor_of(asteroid):
			asteroid_count += 1
	if planets.size() != 3 or stations.size() != 3 or asteroid_count != 64:
		_fail_jump_smoke_test(
			"Generated system contents were incomplete. planets=%d stations=%d asteroids=%d" % [
				planets.size(),
				stations.size(),
				asteroid_count,
			]
		)
		return false

	var identity_validation := _validate_persistent_entities(system_root)
	if not identity_validation.is_valid():
		_fail_jump_smoke_test(
			"Generated system identities were invalid: %s" %
			JSON.stringify(identity_validation.to_dict())
		)
		return false

	for planet in planets:
		var body := planet as Node3D
		var physical_radius: float = player.call("_get_obstacle_radius", body)
		var navigation_radius := float(
			body.get_meta("navigation_clearance_radius", 0.0)
		)
		if navigation_radius <= physical_radius:
			_fail_jump_smoke_test(
				"Generated planet '%s' lacks a valid navigation envelope." %
				body.name
			)
			return false

	player.global_position = return_gate.call("get_arrival_transform").origin
	player.call("_clear_avoidance_state")
	for station in stations:
		var destination := station as Node3D
		var arrived := false
		for step in range(5000):
			var navigation: Dictionary = player.call(
				"_get_autopilot_avoidance",
				destination.global_position,
				destination
			)
			var steer_target: Vector3 = navigation.get(
				"steer_target",
				destination.global_position
			)
			var direction := steer_target - player.global_position
			if direction.length() > 0.01:
				player.global_position += direction.normalized() * minf(
					8.0,
					direction.length()
				)
			if player.global_position.distance_to(
				destination.global_position
			) < 100.0:
				arrived = true
				break
		if not arrived:
			_fail_jump_smoke_test(
				"Autopilot could not reach generated station '%s'; remaining=%.1f blocker=%d." % [
					destination.name,
					player.global_position.distance_to(destination.global_position),
					int(player.get("avoidance_obstacle_id")),
				]
			)
			return false
		player.call("_clear_avoidance_state")

	var ring_target := system_root.get_node_or_null(
		"Halcyon_Ring_20"
	) as Node3D
	if ring_target == null:
		_fail_jump_smoke_test("Generated Halcyon ring target was unavailable.")
		return false
	var parent_planet = ring_target.get("navigation_parent")
	if not parent_planet is Node3D:
		_fail_jump_smoke_test(
			"Generated ring target lacks its parent celestial relationship."
		)
		return false
	var ring_planet := parent_planet as Node3D
	var planet_navigation_radius := float(
		ring_planet.get_meta("navigation_clearance_radius", 0.0)
	)
	var alternate_ring_target := system_root.get_node_or_null(
		"Halcyon_Ring_21"
	) as Node3D
	if alternate_ring_target == null:
		_fail_jump_smoke_test(
			"Generated alternate Halcyon ring target was unavailable."
		)
		return false

	GlobalState.active_target = return_gate
	player.nav_mode = "JUMP_APPROACH"
	player.staged_jump_gate_id = return_gate.get_instance_id()
	player.set("avoidance_obstacle_id", ring_planet.get_instance_id())
	player.set("avoidance_waypoint", return_gate.global_position)
	GlobalState.active_target = ring_target
	if (
		player.staged_jump_gate_id != 0
		or int(player.get("avoidance_obstacle_id")) != 0
		or player.get("avoidance_waypoint") != Vector3.ZERO
		or player.target_position != null
		or player.nav_mode != "APPROACH"
	):
		_fail_jump_smoke_test(
			"Switching from the gate to a ring asteroid retained stale navigation state."
		)
		return false
	player.target_position = ring_target.global_position
	player.call(
		"_get_autopilot_avoidance",
		ring_target.global_position,
		ring_target
	)
	GlobalState.active_target = alternate_ring_target
	if (
		int(player.get("avoidance_obstacle_id")) != 0
		or player.get("avoidance_waypoint") != Vector3.ZERO
		or player.target_position != null
	):
		_fail_jump_smoke_test(
			"Rapid asteroid switching retained the previous target's route."
		)
		return false
	var switched_navigation: Dictionary = player.call(
		"_get_autopilot_avoidance",
		alternate_ring_target.global_position,
		alternate_ring_target
	)
	var switched_steer_target: Vector3 = switched_navigation.get(
		"steer_target",
		alternate_ring_target.global_position
	)
	if (
		switched_steer_target.distance_to(return_gate.global_position)
		< switched_steer_target.distance_to(alternate_ring_target.global_position)
		and not bool(switched_navigation.get("is_avoiding", false))
	):
		_fail_jump_smoke_test(
			"Rapid asteroid switching steered back toward the return gate."
		)
		return false

	var switch_origin := ring_planet.global_position + Vector3(
		0.0,
		0.0,
		planet_navigation_radius + 300.0
	)
	var front_target: Node3D = null
	var rear_target: Node3D = null
	var best_front_dot := -INF
	var best_rear_dot := INF
	var forward := Vector3.RIGHT
	for asteroid in get_tree().get_nodes_in_group("asteroid"):
		if (
			not asteroid is Node3D
			or not system_root.is_ancestor_of(asteroid)
			or asteroid.get("navigation_parent") != ring_planet
		):
			continue
		var asteroid_body := asteroid as Node3D
		var direction := (
			asteroid_body.global_position - switch_origin
		).normalized()
		var facing_dot := direction.dot(forward)
		if facing_dot > best_front_dot:
			best_front_dot = facing_dot
			front_target = asteroid_body
		if facing_dot < best_rear_dot:
			best_rear_dot = facing_dot
			rear_target = asteroid_body
	if (
		front_target == null
		or rear_target == null
		or best_front_dot < 0.35
		or best_rear_dot > -0.35
	):
		_fail_jump_smoke_test(
			"Could not find front and rear asteroids for target-switch testing."
		)
		return false

	player.global_position = switch_origin
	player.call("_clear_avoidance_state")
	GlobalState.active_target = front_target
	player.nav_mode = "APPROACH"
	player.target_position = front_target.global_position
	var front_navigation: Dictionary = player.call(
		"_get_autopilot_avoidance",
		front_target.global_position,
		front_target
	)
	var old_waypoint: Vector3 = front_navigation.get(
		"steer_target",
		front_target.global_position
	)
	if old_waypoint.distance_to(player.global_position) < 20.0:
		_fail_jump_smoke_test(
			"Front target did not create an in-transit waypoint."
		)
		return false

	GlobalState.active_target = rear_target
	if (
		player.target_position != null
		or player.get("avoidance_waypoint") != Vector3.ZERO
		or int(player.get("avoidance_obstacle_id")) != 0
	):
		_fail_jump_smoke_test(
			"Rear target switch did not immediately cancel the forward waypoint."
		)
		return false
	var rear_navigation: Dictionary = player.call(
		"_get_autopilot_avoidance",
		rear_target.global_position,
		rear_target
	)
	var rear_steer_target: Vector3 = rear_navigation.get(
		"steer_target",
		rear_target.global_position
	)
	var rear_direction := (
		rear_steer_target - player.global_position
	).normalized()
	var old_direction := (
		old_waypoint - player.global_position
	).normalized()
	if (
		rear_direction.dot(
			(rear_target.global_position - player.global_position).normalized()
		) <= rear_direction.dot(old_direction)
	):
		_fail_jump_smoke_test(
			"First steering update after rear target switch still favored the old waypoint."
		)
		return false
	player.nav_mode = "MANUAL"
	GlobalState.active_target = null

	var target_radial := (
		ring_target.global_position - ring_planet.global_position
	).normalized()
	player.global_position = ring_planet.global_position \
		- target_radial * (planet_navigation_radius + 260.0)
	player.call("_clear_avoidance_state")
	var ring_planet_id := ring_planet.get_instance_id()
	var ring_planet_engagements := 0
	var ring_bypass_sign := 0.0
	var previous_ring_obstacle_id := 0
	var minimum_ring_planet_distance := player.global_position.distance_to(
		ring_planet.global_position
	)
	var reached_ring_target := false
	for step in range(3000):
		# The destination is not stationary. Advance it during the route test so
		# the bypass must follow the ring instead of solving a frozen snapshot.
		ring_target.call("_physics_process", 1.0 / 60.0)
		var navigation: Dictionary = player.call(
			"_get_autopilot_avoidance",
			ring_target.global_position,
			ring_target
		)
		var current_obstacle_id: int = player.get("avoidance_obstacle_id")
		if (
			current_obstacle_id == ring_planet_id
			and previous_ring_obstacle_id != ring_planet_id
		):
			ring_planet_engagements += 1
			ring_bypass_sign = float(player.get("avoidance_orbit_sign"))
		previous_ring_obstacle_id = current_obstacle_id
		var steer_target: Vector3 = navigation.get(
			"steer_target",
			ring_target.global_position
		)
		var direction := steer_target - player.global_position
		if direction.length() > 0.01:
			player.global_position += direction.normalized() * minf(
				6.0,
				direction.length()
			)
		minimum_ring_planet_distance = minf(
			minimum_ring_planet_distance,
			player.global_position.distance_to(ring_planet.global_position)
		)
		if player.global_position.distance_to(ring_target.global_position) < 60.0:
			reached_ring_target = true
			break

	var expected_ring_direction := signf(float(ring_target.get("orbit_speed")))
	if (
		ring_planet_engagements > 0
		and not is_equal_approx(ring_bypass_sign, expected_ring_direction)
	):
		_fail_jump_smoke_test(
			"Ring-target bypass did not travel with the asteroid orbit. expected=%.0f actual=%.0f" % [
				expected_ring_direction,
				ring_bypass_sign,
			]
		)
		return false

	var ring_planet_physical_clearance: float = player.call(
		"_get_obstacle_radius",
		ring_planet
	) + maxf(
		100.0,
		float(player.call("_get_obstacle_radius", ring_planet)) * 0.15
	)
	if (
		not reached_ring_target
		or ring_planet_engagements > 1
		or minimum_ring_planet_distance < ring_planet_physical_clearance
	):
		_fail_jump_smoke_test(
			"Generated ring-target route failed. reached=%s engagements=%d minimum=%.1f required=%.1f remaining=%.1f" % [
				str(reached_ring_target),
				ring_planet_engagements,
				minimum_ring_planet_distance,
				ring_planet_physical_clearance,
				player.global_position.distance_to(ring_target.global_position),
			]
		)
		return false

	var halcyon_watch: Node3D = null
	for station in stations:
		if station is Node3D and str(station.get("world_id")) \
				== "station.test.halcyon_watch":
			halcyon_watch = station as Node3D
			break
	if halcyon_watch == null:
		_fail_jump_smoke_test("Generated Halcyon Watch was unavailable.")
		return false

	var station_radial := (
		halcyon_watch.global_position - ring_planet.global_position
	).normalized()
	var occlusion_asteroid: Node3D = null
	var lowest_radial_dot := INF
	for asteroid in get_tree().get_nodes_in_group("asteroid"):
		if (
			not asteroid is Node3D
			or not system_root.is_ancestor_of(asteroid)
			or asteroid.get("navigation_parent") != ring_planet
		):
			continue
		var asteroid_body := asteroid as Node3D
		var asteroid_radial := (
			asteroid_body.global_position - ring_planet.global_position
		).normalized()
		var radial_dot := asteroid_radial.dot(station_radial)
		if radial_dot < lowest_radial_dot:
			lowest_radial_dot = radial_dot
			occlusion_asteroid = asteroid_body
	if occlusion_asteroid == null or lowest_radial_dot > -0.85:
		_fail_jump_smoke_test(
			"Could not find a ring asteroid opposite Halcyon Watch."
		)
		return false

	# Reproduce the player workflow: fly to a ring asteroid, then immediately
	# select the outpost hidden behind its parent planet.
	player.global_position = occlusion_asteroid.global_position \
		+ (
			occlusion_asteroid.global_position
			- ring_planet.global_position
		).normalized() * 55.0
	player.call("_clear_avoidance_state")
	if bool(player.call("is_navigation_target_visible", halcyon_watch)):
		_fail_jump_smoke_test(
			"Occluded Halcyon Watch was incorrectly visible from '%s'." %
			occlusion_asteroid.name
		)
		return false

	var station_planet_engagements := 0
	var previous_station_obstacle_id := 0
	var starting_full_lap_reassessments: int = player.get(
		"avoidance_full_lap_reassessments"
	)
	var minimum_station_planet_distance := player.global_position.distance_to(
		ring_planet.global_position
	)
	var reached_occluded_station := false
	for step in range(4000):
		var navigation: Dictionary = player.call(
			"_get_autopilot_avoidance",
			halcyon_watch.global_position,
			halcyon_watch
		)
		var current_obstacle_id: int = player.get("avoidance_obstacle_id")
		if (
			current_obstacle_id == ring_planet_id
			and previous_station_obstacle_id != ring_planet_id
		):
			station_planet_engagements += 1
		previous_station_obstacle_id = current_obstacle_id
		var steer_target: Vector3 = navigation.get(
			"steer_target",
			halcyon_watch.global_position
		)
		var direction := steer_target - player.global_position
		if direction.length() > 0.01:
			player.global_position += direction.normalized() * minf(
				6.0,
				direction.length()
			)
		minimum_station_planet_distance = minf(
			minimum_station_planet_distance,
			player.global_position.distance_to(ring_planet.global_position)
		)
		if player.global_position.distance_to(
			halcyon_watch.global_position
		) < 100.0:
			reached_occluded_station = true
			break
	if (
		not reached_occluded_station
		or station_planet_engagements > 1
		or minimum_station_planet_distance < ring_planet_physical_clearance
		or int(player.get("avoidance_full_lap_reassessments")) \
			> starting_full_lap_reassessments
	):
		_fail_jump_smoke_test(
			"Occluded asteroid-to-outpost route failed. asteroid=%s reached=%s engagements=%d minimum=%.1f required=%.1f remaining=%.1f" % [
				occlusion_asteroid.name,
				str(reached_occluded_station),
				station_planet_engagements,
				minimum_station_planet_distance,
				ring_planet_physical_clearance,
				player.global_position.distance_to(halcyon_watch.global_position),
			]
		)
		return false
	player.call("_clear_avoidance_state")
	return true

func _run_core_smoke_test() -> void:
	await get_tree().process_frame
	var ui := GlobalState.get_ui_manager()
	var system_root := get_active_system_root()
	if not ui or not system_root or not player or player.destroyed:
		_fail_core_smoke_test("Playable scene references were unavailable.")
		return
	var identity_validation := _validate_persistent_entities(system_root)
	if not identity_validation.is_valid():
		_fail_core_smoke_test(
			"World identity validation failed: %s" %
			JSON.stringify(identity_validation.to_dict())
		)
		return

	if ui.get("campaign_panel") == null \
			or ui.get("campaign_slots_vbox") == null \
			or ui.get("campaign_manual_vbox") == null:
		_fail_core_smoke_test(
			"Campaign manager UI was not constructed."
		)
		return
	GlobalState.paused = true
	ui.call("_open_campaign_manager")
	if not bool(ui.get("campaign_panel").visible) \
			or ui.get("campaign_slots_vbox").get_child_count() != 4:
		_fail_core_smoke_test(
			"Campaign manager did not render exactly three campaign slots."
		)
		return
	ui.call("_close_campaign_manager")
	var checkpoint_messages: Array[String] = []
	var capture_checkpoint_message := func(
		sender: String,
		message: String,
		_color: Color
	) -> void:
		if sender == "SYSTEM" and message == "Campaign checkpoint saved.":
			checkpoint_messages.append(message)
	GlobalState.system_chatter_received.connect(capture_checkpoint_message)
	_notify_autosave_success(
		"dock",
		{
			"station_id": "station.test.notification",
			"gate_id": "",
		}
	)
	_notify_autosave_success(
		"dock",
		{
			"station_id": "station.test.notification",
			"gate_id": "",
		}
	)
	GlobalState.system_chatter_received.disconnect(
		capture_checkpoint_message
	)
	if checkpoint_messages.size() != 1:
		_fail_core_smoke_test(
			"Duplicate autosave notifications were not suppressed."
		)
		return

	GlobalState.paused = false
	player.is_docked = false
	player.nav_mode = "MANUAL"
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0
	var initial_position := player.global_position
	player.double_click_move(initial_position + Vector3(0.0, 0.0, -80.0))
	GlobalState.paused = true
	player.call("_physics_process", 0.25)
	if player.global_position.distance_to(initial_position) > 0.01 \
			or not is_equal_approx(player.current_speed, 0.0):
		_fail_core_smoke_test("Pause did not stop player movement.")
		return
	GlobalState.paused = false
	player.call("_physics_process", 0.25)
	if player.global_position.distance_to(initial_position) <= 0.01 \
			or player.current_speed <= 0.0:
		_fail_core_smoke_test("Manual fly-to movement did not resume after pause.")
		return

	var camera := player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if not camera:
		_fail_core_smoke_test("Player camera was unavailable.")
		return
	var original_zoom := camera.position.z
	var zoom_event := InputEventMouseButton.new()
	zoom_event.button_index = MOUSE_BUTTON_WHEEL_UP
	zoom_event.pressed = true
	player.call("_unhandled_input", zoom_event)
	if camera.position.z >= original_zoom:
		_fail_core_smoke_test("Camera zoom input did not respond.")
		return

	var station := GlobalState.get_primary_station()
	if not station:
		_fail_core_smoke_test("Primary station was unavailable for targeting.")
		return
	ui.overview_collapsed = false
	ui.call("update_overview_list", [station])
	await get_tree().process_frame
	var target_button: Button = null
	for child in ui.overview_list.get_children():
		if child is Button:
			target_button = child
			break
	if not target_button:
		_fail_core_smoke_test("Overview did not create a target row.")
		return
	target_button.emit_signal("pressed")
	if GlobalState.active_target != station:
		_fail_core_smoke_test("Overview row did not select the intended target.")
		return

	var approach_event := InputEventAction.new()
	approach_event.action = "override_approach"
	approach_event.pressed = true
	player.call("_unhandled_input", approach_event)
	if player.nav_mode != "APPROACH":
		_fail_core_smoke_test("Approach override did not engage.")
		return
	var orbit_event := InputEventAction.new()
	orbit_event.action = "override_orbit"
	orbit_event.pressed = true
	player.call("_unhandled_input", orbit_event)
	if player.nav_mode != "ORBIT":
		_fail_core_smoke_test("Orbit override did not replace approach mode.")
		return

	print("[CoreSmokeTest] PASS: startup, campaign UI, save notifications, pause, movement, camera, targeting, and navigation overrides verified.")
	delete_savegame()
	get_tree().quit(0)

func _run_performance_baseline() -> void:
	await get_tree().process_frame
	var ui := GlobalState.get_ui_manager()
	var playable_deadline := Time.get_ticks_msec() + 60000
	while ui \
			and ui.get("loading_panel") != null \
			and is_instance_valid(ui.get("loading_panel")) \
			and Time.get_ticks_msec() < playable_deadline:
		await get_tree().create_timer(0.05).timeout
	var playable_ready_msec := Time.get_ticks_msec()

	GlobalState.paused = false
	player.is_docked = false
	player.nav_mode = "MANUAL"
	player.velocity = Vector3.ZERO
	player.current_speed = 0.0

	var results := {
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"renderer": RenderingServer.get_current_rendering_method(),
		"display_server": DisplayServer.get_name(),
		"resolution": [
			DisplayServer.window_get_size().x,
			DisplayServer.window_get_size().y,
		],
		"processor": OS.get_processor_name(),
		"logical_processors": OS.get_processor_count(),
		"scene_ready_ms": scene_ready_msec,
		"playable_ready_ms": playable_ready_msec,
		"save_bytes": FileAccess.get_file_as_bytes(SAVE_PATH).size() \
			if FileAccess.file_exists(SAVE_PATH) else 0,
		"samples": [],
	}

	var station := GlobalState.get_primary_station()
	if station:
		player.global_position = station.global_position + Vector3(0.0, 20.0, 180.0)
		player.look_at(station.global_position, Vector3.UP)
		player.sync_camera_to_ship()
		results["samples"].append(await _capture_performance_sample("station", 3.0))

	var asteroid: Node3D = null
	for candidate in get_tree().get_nodes_in_group("asteroid"):
		if candidate is Node3D and get_active_system_root().is_ancestor_of(candidate):
			asteroid = candidate
			break
	if asteroid:
		player.global_position = asteroid.global_position + Vector3(0.0, 12.0, 90.0)
		player.look_at(asteroid.global_position, Vector3.UP)
		player.sync_camera_to_ship()
		results["samples"].append(await _capture_performance_sample("asteroid_field", 3.0))

	var hostile: Node3D = null
	for candidate in get_tree().get_nodes_in_group("ship"):
		if candidate is Node3D \
				and candidate != player \
				and get_active_system_root().is_ancestor_of(candidate) \
				and candidate.get("faction") in ["aurelia", "vanguard"]:
			hostile = candidate
			break
	if hostile:
		player.global_position = hostile.global_position + Vector3(0.0, 0.0, 45.0)
		player.look_at(hostile.global_position, Vector3.UP)
		player.sync_camera_to_ship()
		GlobalState.active_target = hostile
		player.nav_mode = "ATTACK"
		results["samples"].append(await _capture_performance_sample("combat", 3.0))

	print("[PerformanceBaseline] " + JSON.stringify(results))
	get_tree().quit(0)

func _capture_performance_sample(label: String, duration_seconds: float) -> Dictionary:
	var fps_values: Array[float] = []
	var process_ms_values: Array[float] = []
	var physics_ms_values: Array[float] = []
	await get_tree().create_timer(2.0).timeout
	var deadline := Time.get_ticks_msec() + int(duration_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		fps_values.append(Performance.get_monitor(Performance.TIME_FPS))
		process_ms_values.append(
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		)
		physics_ms_values.append(
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		)
	return {
		"label": label,
		"fps_avg": _average_float_values(fps_values),
		"fps_min": _minimum_float_value(fps_values),
		"frame_process_ms_avg": _average_float_values(process_ms_values),
		"physics_ms_avg": _average_float_values(physics_ms_values),
		"godot_static_memory_bytes": OS.get_static_memory_usage(),
		"render_video_memory_bytes": int(
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
		),
		"texture_memory_bytes": int(
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
		),
		"draw_calls": int(
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		),
		"rendered_objects": int(
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	}

func _average_float_values(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / values.size()

func _minimum_float_value(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var minimum := values[0]
	for value in values:
		minimum = minf(minimum, value)
	return minimum

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
		if not ui or not ui.dock_panel.visible:
			_fail_dock_smoke_test("Dock UI did not open for '%s'." % station.name)
			return
		await get_tree().process_frame
		if not FileAccess.file_exists(SAVE_PATH):
			_fail_dock_smoke_test("Docking at '%s' did not create an autosave." % station.name)
			return
		if campaign_checkpoint_store == null:
			_fail_dock_smoke_test(
				"Docking at '%s' did not open a campaign checkpoint store." %
				station.name
			)
			return
		var dock_checkpoint := campaign_checkpoint_store.runtime_state_from_active()
		if not bool(dock_checkpoint.get("ok", false)) \
				or dock_checkpoint.get("source_reason", "") != "dock" \
				or dock_checkpoint.get("safe_location", {}).get(
					"station_id",
					""
				) != station.get_world_id():
			_fail_dock_smoke_test(
				"Docking at '%s' did not create the expected safe checkpoint." %
					station.name
			)
			return
		var dock_checkpoint_id := str(
			dock_checkpoint.get("checkpoint_id", "")
		)
		var docked_credits := GlobalState.player_credits
		GlobalState.player_credits += 777
		player.is_docked = false
		ui.dock_panel.visible = false
		if not await _load_campaign_checkpoint():
			_fail_dock_smoke_test(
				"Dock checkpoint for '%s' could not be restored." %
					station.name
			)
			return
		await get_tree().process_frame
		var restored_checkpoint := (
			campaign_checkpoint_store.runtime_state_from_active()
		)
		if GlobalState.player_credits != docked_credits \
				or not player.is_docked \
				or not ui.dock_panel.visible \
				or restored_checkpoint.get("checkpoint_id", "") \
					!= dock_checkpoint_id:
			_fail_dock_smoke_test(
				"Dock checkpoint restoration failed or replaced its source for '%s'." %
					station.name
			)
			return
		GlobalState.player_credits = docked_credits + 222
		var docked_manual := request_manual_checkpoint(
			1,
			"Docked Station Visit",
			true
		)
		var docked_manual_state := (
			campaign_checkpoint_store.runtime_state_from_manual(1)
		)
		if not bool(docked_manual.get("ok", false)) \
				or int(
					docked_manual_state.get("state", {}).get(
						"global",
						{}
					).get("credits", 0)
				) != docked_credits + 222:
			_fail_dock_smoke_test(
				"Docked manual checkpoint did not refresh station changes for '%s': result=%s credits=%d expected=%d." % [
					station.name,
					JSON.stringify(docked_manual),
					int(
						docked_manual_state.get("state", {}).get(
							"global",
							{}
						).get("credits", -1)
					),
					docked_credits + 222,
				]
			)
			return
		if ui.has_method("undock_player"):
			ui.undock_player()
		await get_tree().process_frame
		if player.is_docked \
				or player.nav_mode != "MANUAL" \
				or ui.dock_panel.visible:
			_fail_dock_smoke_test("Undocking did not restore flight state for '%s'." % station.name)
			return
		var undock_checkpoint := (
			campaign_checkpoint_store.runtime_state_from_active()
		)
		if not bool(undock_checkpoint.get("ok", false)) \
				or undock_checkpoint.get("source_reason", "") != "undock" \
				or undock_checkpoint.get("safe_location", {}).get(
					"station_id",
					""
				) != station.get_world_id():
			_fail_dock_smoke_test(
				"Undocking from '%s' did not create the expected safe checkpoint." %
					station.name
			)
			return

	var checkpoint_before_death := (
		campaign_checkpoint_store.runtime_state_from_active()
	)
	player.destroyed = true
	var death_checkpoint_created := request_safe_checkpoint(
		"dock",
		stations[0]
	)
	player.destroyed = false
	var checkpoint_after_death := (
		campaign_checkpoint_store.runtime_state_from_active()
	)
	if death_checkpoint_created \
			or checkpoint_after_death.get("checkpoint_id", "") \
				!= checkpoint_before_death.get("checkpoint_id", ""):
		_fail_dock_smoke_test(
			"Destroyed player state replaced the last safe checkpoint."
		)
		return

	print("[DockSmokeTest] PASS: dock and undock safe checkpoints, UI, and flight restoration verified for all active-system dockables.")
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
	obstacle.set_meta("navigation_clearance_radius", 430.0)
	obstacle.global_position = Vector3(10250.0, 0.0, 10000.0)
	var visibility_target := StaticBody3D.new()
	visibility_target.name = "AutopilotVisibilityTarget"
	var target_collision := CollisionShape3D.new()
	var target_sphere := SphereShape3D.new()
	target_sphere.radius = 10.0
	target_collision.shape = target_sphere
	visibility_target.add_child(target_collision)
	get_active_system_root().add_child(visibility_target)
	visibility_target.global_position = Vector3(10800.0, 0.0, 10000.0)
	await get_tree().physics_frame
	player.global_position = Vector3(9700.0, 0.0, 10000.0)
	if bool(player.call("_has_clear_navigation_line", visibility_target)):
		visibility_target.queue_free()
		obstacle.queue_free()
		player.global_transform = original_transform
		_fail_autopilot_smoke_test(
			"Planet-blocked target was incorrectly reported as visible."
		)
		return
	player.global_position = Vector3(9700.0, 0.0, 10400.0)
	visibility_target.global_position = Vector3(10800.0, 0.0, 10400.0)
	if not bool(player.call("is_target_physically_visible", visibility_target)) \
			or bool(player.call("is_navigation_target_visible", visibility_target)):
		visibility_target.queue_free()
		obstacle.queue_free()
		player.global_transform = original_transform
		_fail_autopilot_smoke_test(
			"Physical visibility and navigation clearance were not separated."
		)
		return
	visibility_target.global_position = Vector3(10800.0, 0.0, 10000.0)
	player.global_position = Vector3(10000.0, 0.0, 10350.0)
	player.call("_clear_avoidance_state")
	var obstruction_notices_before: int = player.get(
		"navigation_obstruction_notice_count"
	)
	var route_clear_notices_before: int = player.get(
		"navigation_route_clear_notice_count"
	)
	var planet_result: Dictionary = player.call(
		"_get_autopilot_avoidance",
		Vector3(10500.0, 0.0, 10350.0),
		null
	)
	if not bool(planet_result.get("is_avoiding", false)) \
			or planet_result.get("obstacle") != obstacle:
		var calculated_radius: float = player.call("_get_obstacle_radius", obstacle)
		var calculated_margin: float = player.call("_get_obstacle_safety_margin", obstacle)
		visibility_target.queue_free()
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
	if (
		int(player.get("navigation_obstruction_notice_count"))
			!= obstruction_notices_before + 1
		or not str(player.get("last_navigation_status_message")).contains(
			"Direct route obstructed"
		)
	):
		visibility_target.queue_free()
		obstacle.queue_free()
		player.global_transform = original_transform
		_fail_autopilot_smoke_test(
			"Planet avoidance did not emit one official obstruction notice."
		)
		return

	var destination := Vector3(10800.0, 0.0, 10000.0)
	player.global_position = Vector3(9700.0, 0.0, 10000.0)
	player.call("_clear_avoidance_state")
	var required_clearance: float = player.call("_get_obstacle_radius", obstacle) \
		+ player.call("_get_obstacle_safety_margin", obstacle)
	var minimum_distance := player.global_position.distance_to(obstacle.global_position)
	for step in range(500):
		var simulated: Dictionary = player.call(
			"_get_autopilot_avoidance",
			destination,
			null
		)
		var steer_target: Vector3 = simulated.get("steer_target", destination)
		var move_direction := steer_target - player.global_position
		if move_direction.length() > 0.01:
			player.global_position += move_direction.normalized() * minf(
				8.0,
				move_direction.length()
			)
		minimum_distance = minf(
			minimum_distance,
			player.global_position.distance_to(obstacle.global_position)
		)
		if player.global_position.distance_to(destination) < 10.0:
			break
	if minimum_distance < required_clearance \
			or player.global_position.distance_to(destination) >= 10.0:
		var final_position := player.global_position
		var remaining_distance := final_position.distance_to(destination)
		var final_waypoint: Vector3 = player.get("avoidance_waypoint")
		var final_sign: float = player.get("avoidance_orbit_sign")
		visibility_target.queue_free()
		obstacle.queue_free()
		player.global_transform = original_transform
		_fail_autopilot_smoke_test(
			"Repeated planet avoidance did not maintain clearance. minimum=%.1f required=%.1f remaining=%.1f position=%s waypoint=%s sign=%.1f" % [
				minimum_distance,
				required_clearance,
				remaining_distance,
				str(final_position),
				str(final_waypoint),
				final_sign,
			]
		)
		return
	if (
		int(player.get("navigation_obstruction_notice_count"))
			!= obstruction_notices_before + 1
		or int(player.get("navigation_route_clear_notice_count"))
			!= route_clear_notices_before + 1
		or str(player.get("last_navigation_status_message")) != (
			"NAVIGATION: Obstruction cleared. Resuming direct course."
		)
	):
		visibility_target.queue_free()
		obstacle.queue_free()
		player.global_transform = original_transform
		_fail_autopilot_smoke_test(
			"Planet avoidance notices repeated or failed to report route clearance. obstruction=%d expected=%d clear=%d expected_clear=%d status=%s" % [
				int(player.get("navigation_obstruction_notice_count")),
				obstruction_notices_before + 1,
				int(player.get("navigation_route_clear_notice_count")),
				route_clear_notices_before + 1,
				str(player.get("last_navigation_status_message")),
			]
		)
		return

	visibility_target.queue_free()
	obstacle.queue_free()
	await get_tree().process_frame

	var rocky_planet := get_active_system_root().get_node_or_null(
		"RockyPlanet"
	) as Node3D
	var gas_giant := get_active_system_root().get_node_or_null(
		"GasGiant"
	) as Node3D
	var kova_station := get_active_system_root().get_node_or_null(
		"KovaStation"
	) as Node3D
	var iron_reach := get_active_system_root().get_node_or_null(
		"IronReachOutpost"
	) as Node3D
	if (
		rocky_planet == null
		or gas_giant == null
		or kova_station == null
		or iron_reach == null
	):
		player.global_transform = original_transform
		_fail_autopilot_smoke_test(
			"Real planets or outposts were unavailable."
		)
		return

	var planet_to_station := (
		kova_station.global_position - rocky_planet.global_position
	).normalized()
	player.global_position = rocky_planet.global_position \
		- planet_to_station * 900.0
	player.call("_clear_avoidance_state")
	if bool(player.call("is_navigation_target_visible", kova_station)):
		player.global_transform = original_transform
		_fail_autopilot_smoke_test(
			"Real Kova route was reported visible through Rocky Planet."
		)
		return

	var rocky_id := rocky_planet.get_instance_id()
	var rocky_engagements := 0
	var previous_avoidance_id := 0
	var live_asteroid_collision_layers := {}
	for candidate in get_tree().get_nodes_in_group("asteroid"):
		if candidate is CollisionObject3D \
				and get_active_system_root().is_ancestor_of(candidate):
			var collision_object := candidate as CollisionObject3D
			live_asteroid_collision_layers[
				collision_object.get_instance_id()
			] = collision_object.collision_layer
			collision_object.collision_layer = 0
	await get_tree().physics_frame
	var real_minimum_distance := player.global_position.distance_to(
		rocky_planet.global_position
	)
	for step in range(1200):
		var simulated: Dictionary = player.call(
			"_get_autopilot_avoidance",
			kova_station.global_position,
			kova_station
		)
		var current_avoidance_id: int = player.get("avoidance_obstacle_id")
		if current_avoidance_id == rocky_id \
				and previous_avoidance_id != rocky_id:
			rocky_engagements += 1
		previous_avoidance_id = current_avoidance_id
		var steer_target: Vector3 = simulated.get(
			"steer_target",
			kova_station.global_position
		)
		var move_direction := steer_target - player.global_position
		if move_direction.length() > 0.01:
			player.global_position += move_direction.normalized() * minf(
				6.0,
				move_direction.length()
			)
		real_minimum_distance = minf(
			real_minimum_distance,
			player.global_position.distance_to(rocky_planet.global_position)
		)
		if player.global_position.distance_to(kova_station.global_position) < 12.0:
			break

	var rocky_clearance: float = player.call(
		"_get_obstacle_radius",
		rocky_planet
	) + player.call("_get_obstacle_safety_margin", rocky_planet)
	if (
		rocky_engagements != 1
		or real_minimum_distance < rocky_clearance
		or player.global_position.distance_to(kova_station.global_position) >= 12.0
		or not bool(player.call("is_target_physically_visible", kova_station))
	):
		var real_final_position := player.global_position
		var real_remaining := real_final_position.distance_to(
			kova_station.global_position
		)
		player.global_transform = original_transform
		player.call("_clear_avoidance_state")
		_fail_autopilot_smoke_test(
			"Real Kova route failed. engagements=%d minimum=%.1f required=%.1f remaining=%.1f position=%s" % [
				rocky_engagements,
				real_minimum_distance,
				rocky_clearance,
				real_remaining,
				str(real_final_position),
			]
		)
		return

	player.global_position = kova_station.global_position
	player.call("_clear_avoidance_state")
	var celestial_engagements := {}
	var last_celestial_id := 0
	var kova_route_minimums := {
		rocky_planet.get_instance_id(): player.global_position.distance_to(
			rocky_planet.global_position
		),
		gas_giant.get_instance_id(): player.global_position.distance_to(
			gas_giant.global_position
		),
	}
	var kova_route_minimum_positions := {}
	var kova_route_minimum_states := {}
	var station_arrival_distance := 100.0
	for step in range(2400):
		var simulated: Dictionary = player.call(
			"_get_autopilot_avoidance",
			iron_reach.global_position,
			iron_reach
		)
		var current_obstacle := simulated.get("obstacle") as Node3D
		var current_celestial_id := 0
		if current_obstacle != null and current_obstacle.is_in_group("celestial"):
			current_celestial_id = current_obstacle.get_instance_id()
			if current_celestial_id != last_celestial_id:
				celestial_engagements[current_celestial_id] = int(
					celestial_engagements.get(current_celestial_id, 0)
				) + 1
		last_celestial_id = current_celestial_id

		var steer_target: Vector3 = simulated.get(
			"steer_target",
			iron_reach.global_position
		)
		var move_direction := steer_target - player.global_position
		if move_direction.length() > 0.01:
			player.global_position += move_direction.normalized() * minf(
				6.0,
				move_direction.length()
			)
		for celestial in [rocky_planet, gas_giant]:
			var celestial_id: int = celestial.get_instance_id()
			var current_distance := player.global_position.distance_to(
				celestial.global_position
			)
			if current_distance < float(kova_route_minimums[celestial_id]):
				kova_route_minimums[celestial_id] = current_distance
				kova_route_minimum_positions[celestial_id] = player.global_position
				kova_route_minimum_states[celestial_id] = {
					"obstacle_id": player.get("avoidance_obstacle_id"),
					"exit_index": player.get("avoidance_exit_index"),
					"exits_visited": player.get("avoidance_exits_visited"),
					"waypoint": player.get("avoidance_waypoint"),
				}
		if (
			player.global_position.distance_to(iron_reach.global_position)
			< station_arrival_distance
		):
			break

	var kova_route_failed := (
		player.global_position.distance_to(iron_reach.global_position)
		>= station_arrival_distance
	)
	for celestial in [rocky_planet, gas_giant]:
		var celestial_id: int = celestial.get_instance_id()
		var celestial_clearance: float = player.call(
			"_get_navigation_clearance_for_destination",
			celestial,
			iron_reach.global_position,
			iron_reach
		)
		if (
			int(celestial_engagements.get(celestial_id, 0)) > 1
			or float(kova_route_minimums[celestial_id]) < celestial_clearance
		):
			kova_route_failed = true
	if kova_route_failed:
		var route_remaining := player.global_position.distance_to(
			iron_reach.global_position
		)
		var final_avoidance_id: int = player.get("avoidance_obstacle_id")
		var final_obstacle_name := "none"
		var final_route_position := player.global_position
		if final_avoidance_id != 0:
			var final_obstacle := instance_from_id(final_avoidance_id)
			if final_obstacle is Node:
				final_obstacle_name = (final_obstacle as Node).name
		player.global_transform = original_transform
		player.call("_clear_avoidance_state")
		_fail_autopilot_smoke_test(
			"Kova-to-Iron-Reach route failed. engagements=%s minimums=%s min_positions=%s min_states=%s remaining=%.1f blocker=%s position=%s" % [
				str(celestial_engagements),
				str(kova_route_minimums),
				str(kova_route_minimum_positions),
				str(kova_route_minimum_states),
				route_remaining,
				final_obstacle_name,
				str(final_route_position),
			]
		)
		return

	for instance_id: Variant in live_asteroid_collision_layers:
		var asteroid_object := instance_from_id(int(instance_id))
		if asteroid_object is CollisionObject3D:
			(asteroid_object as CollisionObject3D).collision_layer = int(
				live_asteroid_collision_layers[instance_id]
			)

	player.global_transform = original_transform
	player.call("_clear_avoidance_state")
	print("[AutopilotSmokeTest] PASS: asteroid avoidance, visibility, planet circles, and multi-planet routes verified.")
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

func _run_combat_smoke_test() -> void:
	await get_tree().process_frame
	var phase := int(Engine.get_meta("combat_smoke_phase", 0))
	if phase == 1:
		Engine.remove_meta("combat_smoke_phase")
		var restarted_ui := GlobalState.get_ui_manager()
		var restarted_death_panel = restarted_ui.get("death_panel") if restarted_ui else null
		if player.destroyed \
				or not is_equal_approx(player.health, player.max_health) \
				or GlobalState.player_credits != 50 \
				or QuestManager.is_quest_active() \
				or restarted_death_panel == null \
				or restarted_death_panel.visible:
			_fail_combat_smoke_test("Restarting from death did not create a fresh game.")
			return
		print("[CombatSmokeTest] PASS: hostility, projectiles, damage, rewards, reputation, quest progress, death, and restart verified.")
		delete_savegame()
		get_tree().quit(0)
		return

	GlobalState.paused = false
	GlobalState.reset_for_restart()
	GlobalState.player = player
	QuestManager.active_quest = {}

	var npc_scene := load("res://scenes/npc_ship.tscn") as PackedScene
	var projectile_scene := load("res://scenes/projectile.tscn") as PackedScene
	if not npc_scene or not projectile_scene:
		_fail_combat_smoke_test("Combat scenes could not be loaded.")
		return

	var test_npc := npc_scene.instantiate()
	test_npc.persistent_id = "entity.test.combat.primary"
	test_npc.name = "CombatSmokeTarget"
	test_npc.faction = "aurelia"
	test_npc.ship_role = "Gunner"
	get_active_system_root().add_child(test_npc)
	test_npc.global_position = Vector3(25.0, 0.0, 180.0)
	await get_tree().process_frame

	# Major factions with ordinary hostility should stand down in a station
	# safe zone, then acquire the player once both ships move outside it.
	GlobalState.active_system_entities = [test_npc]
	GlobalState.reputations["aurelia"] = -20.0
	player.global_position = Vector3(0.0, 0.0, 180.0)
	test_npc.target = null
	test_npc.call("_physics_process", 0.016)
	if test_npc.target != null:
		_fail_combat_smoke_test("A major-faction ship attacked inside the safe zone.")
		return

	player.global_position = Vector3(1000.0, 0.0, 1000.0)
	test_npc.global_position = Vector3(1040.0, 0.0, 1000.0)
	test_npc.target = null
	test_npc.call("_physics_process", 0.016)
	if test_npc.target != player:
		_fail_combat_smoke_test("A hostile major-faction ship did not engage outside the safe zone.")
		return

	# Extremely poor standing overrides station protection.
	player.global_position = Vector3(0.0, 0.0, 180.0)
	test_npc.global_position = Vector3(25.0, 0.0, 180.0)
	GlobalState.reputations["aurelia"] = -50.0
	test_npc.target = null
	test_npc.call("_physics_process", 0.016)
	if test_npc.target != player:
		_fail_combat_smoke_test("Sworn hostility did not override safe-zone protection.")
		return

	# Same-faction projectiles must be ignored. Player projectiles must apply
	# their damage and the immediate reputation penalty.
	test_npc.target = null
	test_npc.health = 40.0
	GlobalState.reputations["aurelia"] = -20.0
	var friendly_projectile := projectile_scene.instantiate()
	friendly_projectile.faction = "aurelia"
	friendly_projectile.damage = 8.0
	get_active_system_root().add_child(friendly_projectile)
	friendly_projectile.call("_on_body_entered", test_npc)
	if not is_equal_approx(test_npc.health, 40.0):
		_fail_combat_smoke_test("Friendly projectile damaged a same-faction ship.")
		return
	friendly_projectile.queue_free()

	var player_projectile := projectile_scene.instantiate()
	player_projectile.faction = "player"
	player_projectile.damage = 8.0
	get_active_system_root().add_child(player_projectile)
	player_projectile.call("_on_body_entered", test_npc)
	if not is_equal_approx(test_npc.health, 32.0) \
			or not is_equal_approx(float(GlobalState.reputations["aurelia"]), -22.0):
		_fail_combat_smoke_test("Player projectile damage or hit reputation penalty was incorrect.")
		return

	QuestManager.active_quest = {
		"title": "Combat Smoke Contract",
		"objective_type": "KILL_SHIPS",
		"target_faction": "aurelia",
		"current_count": 0,
		"count_required": 1,
	}
	var credits_before_kill := GlobalState.player_credits
	var vanguard_rep_before := float(GlobalState.reputations["vanguard"])
	var destroyed_pool_before := GlobalState.destroyed_ships_pool
	test_npc.call("take_damage", 1000.0, "player")
	var wreck_found := false
	for wreck in get_tree().get_nodes_in_group("wreckage"):
		if wreck.name.begins_with(test_npc.name):
			wreck_found = true
			break
	if not bool(test_npc.destroyed) \
			or GlobalState.player_credits != credits_before_kill + 15 \
			or GlobalState.destroyed_ships_pool != destroyed_pool_before + 1 \
			or test_npc in GlobalState.active_system_entities \
			or not wreck_found \
			or not is_equal_approx(float(GlobalState.reputations["aurelia"]), -44.0) \
			or not is_equal_approx(
				float(GlobalState.reputations["vanguard"]),
				vanguard_rep_before + 10.0
			) \
			or int(QuestManager.active_quest.get("current_count", 0)) != 1:
		_fail_combat_smoke_test("Kill rewards, reputation, or quest progress were incorrect.")
		return

	# Player damage consumes shields first, spills excess into hull, and fatal
	# damage opens the real death panel.
	GlobalState.shield_capacity = 10.0
	player.current_shield = 10.0
	player.health = 100.0
	player.call("take_damage", 15.0, "aurelia")
	if not is_equal_approx(player.current_shield, 0.0) \
			or not is_equal_approx(player.health, 95.0):
		_fail_combat_smoke_test("Player shields did not absorb damage before hull.")
		return
	player.call("take_damage", 1000.0, "aurelia")
	var ui := GlobalState.get_ui_manager()
	var death_panel = ui.get("death_panel") if ui else null
	if not bool(player.destroyed) \
			or death_panel == null \
			or not is_instance_valid(death_panel) \
			or not death_panel.visible:
		_fail_combat_smoke_test("Fatal player damage did not show the death screen.")
		return

	Engine.set_meta("combat_smoke_phase", 1)
	ui.call("_restart_game")

func _run_mission_smoke_test() -> void:
	await get_tree().process_frame
	GlobalState.paused = false
	GlobalState.reset_for_restart()
	GlobalState.player = player
	QuestManager.active_quest = {}

	var fallback_holder := {
		"quest": {},
		"called": false,
	}
	LLMInterface.last_history_text = ""
	LLMInterface.request_start_time = Time.get_ticks_msec()
	LLMInterface.active_callback = func(quest_data: Dictionary, is_fallback: bool) -> void:
		fallback_holder["quest"] = quest_data
		fallback_holder["called"] = is_fallback
	LLMInterface.call("_trigger_fallback")
	var fallback_result: Dictionary = fallback_holder["quest"]
	if not bool(fallback_holder["called"]) \
			or fallback_result.is_empty() \
			or not fallback_result.has("objective") \
			or not fallback_result.has("choices"):
		_fail_mission_smoke_test("Local fallback did not produce a playable contract.")
		return
	var fallback_objective: Dictionary = fallback_result["objective"]
	var fallback_type := str(fallback_objective.get("type", ""))
	var fallback_dialogue := str(fallback_result.get("dialogue", ""))
	if fallback_type == "DELIVER_ORE" \
			and not fallback_dialogue.contains(str(int(fallback_objective["amount_required"]))):
		_fail_mission_smoke_test("Fallback ore dialogue did not match its objective amount.")
		return
	if fallback_type == "KILL_SHIPS" \
			and not fallback_dialogue.contains(str(int(fallback_objective["count_required"]))):
		_fail_mission_smoke_test("Fallback kill dialogue did not match its objective count.")
		return

	var mismatched_quest := {
		"title": "Number Reconciliation",
		"faction": "zenith",
		"agent_name": "Director Voss",
		"dialogue": "Deliver 30 m3 of ore to the station.",
		"objective": {
			"type": "DELIVER_ORE",
			"amount_required": 80.0,
			"reward_credits": 100,
		},
		"choices": [],
	}
	LLMInterface.call("_validate_quest_data", mismatched_quest)
	if not is_equal_approx(float(mismatched_quest["objective"]["amount_required"]), 30.0) \
			or not str(mismatched_quest["dialogue"]).contains("30"):
		_fail_mission_smoke_test("Generated briefing and objective numbers were not reconciled.")
		return

	var accept_choice := {
		"text": "Accepted.",
		"consequence": {
			"credits_immediate": 10,
			"reputation_change": {"zenith": 2.0},
			"reward_credits_multiplier": 1.0,
		},
	}
	var credits_before_rejection := GlobalState.player_credits
	var zenith_before_rejection := float(GlobalState.reputations["zenith"])
	var invalid_offer := mismatched_quest.duplicate(true)
	invalid_offer["objective"] = {
		"type": "PICKUP_SPECIAL",
		"target_outpost": "kova",
		"reward_credits": 500,
	}
	if QuestManager.accept_quest(invalid_offer, accept_choice) \
			or QuestManager.is_quest_active() \
			or GlobalState.player_credits != credits_before_rejection \
			or not is_equal_approx(
				float(GlobalState.reputations["zenith"]),
				zenith_before_rejection
			):
		_fail_mission_smoke_test(
			"Malformed mission acceptance changed player or mission state."
		)
		return

	QuestManager.accept_quest(mismatched_quest, accept_choice)
	if not QuestManager.is_quest_active() \
			or QuestManager.active_quest.get("objective_type", "") != "DELIVER_ORE" \
			or not is_equal_approx(float(QuestManager.active_quest["amount_required"]), 30.0) \
			or GlobalState.player_credits != 60 \
			or not is_equal_approx(float(GlobalState.reputations["zenith"]), 52.0):
		_fail_mission_smoke_test("Mission acceptance did not apply objective and choice consequences.")
		return

	GlobalState.add_ore(12.0)
	if not is_equal_approx(QuestManager.deliver_partial(12.0), 12.0) \
			or not is_equal_approx(float(QuestManager.active_quest["partial_delivered"]), 12.0) \
			or GlobalState.cargo_type != GlobalState.CargoType.EMPTY:
		_fail_mission_smoke_test("Partial ore delivery did not bank progress correctly.")
		return
	GlobalState.add_ore(18.0)
	if not QuestManager.is_quest_completed():
		_fail_mission_smoke_test("Ore mission did not become complete at the required total.")
		return
	var credits_before_completion := GlobalState.player_credits
	QuestManager.complete_quest()
	if QuestManager.is_quest_active() \
			or GlobalState.player_credits != credits_before_completion + 100 \
			or GlobalState.cargo_type != GlobalState.CargoType.EMPTY:
		_fail_mission_smoke_test("Final ore delivery did not pay and clear the mission.")
		return

	var kill_offer := {
		"title": "Kill Progress",
		"faction": "vanguard",
		"agent_name": "Captain Dask",
		"dialogue": "Destroy two Reavers ships.",
		"objective": {
			"type": "KILL_SHIPS",
			"target_faction": "reavers",
			"count_required": 2,
			"reward_credits": 50,
		},
		"choices": [],
	}
	if not QuestManager.accept_quest(kill_offer, accept_choice):
		_fail_mission_smoke_test("Valid kill mission was rejected.")
		return
	GlobalState.ship_destroyed.emit("reavers")
	GlobalState.ship_destroyed.emit("reavers")
	if not QuestManager.is_quest_completed() \
			or int(QuestManager.active_quest["current_count"]) != 2:
		_fail_mission_smoke_test("Kill mission progress did not reach completion.")
		return
	QuestManager.complete_quest()

	var abandon_offer := {
		"title": "Abandonment Test",
		"faction": "aurelia",
		"agent_name": "Liaison Ryn",
		"dialogue": "Deliver ten cubic meters of ore.",
		"objective": {
			"type": "DELIVER_ORE",
			"amount_required": 10.0,
			"reward_credits": 25,
		},
		"choices": [],
	}
	if not QuestManager.accept_quest(abandon_offer, {
		"text": "Accepted.",
		"consequence": {},
	}):
		_fail_mission_smoke_test("Valid abandonment mission was rejected.")
		return
	var aurelia_before_abandon := float(GlobalState.reputations["aurelia"])
	QuestManager.abandon_quest()
	if QuestManager.is_quest_active() \
			or not is_equal_approx(
				float(GlobalState.reputations["aurelia"]),
				aurelia_before_abandon - 3.0
			):
		_fail_mission_smoke_test("Mission abandonment did not apply the approved small penalty.")
		return

	var pickup_offer := {
		"title": "Pickup Validation",
		"faction": "zenith",
		"agent_name": "Jenna Kross",
		"dialogue": "Retrieve the Plasma Coupler from Kova Station.",
		"objective": {
			"type": "PICKUP_SPECIAL",
			"part_name": "Plasma Coupler",
			"target_outpost": "kova",
			"target_outpost_display": "Kova Station",
			"target_npc": "Cassen Vane",
			"destination": "Grease Monkeys",
			"reward_credits": 75,
		},
		"choices": [],
	}
	if not QuestManager.accept_quest(pickup_offer, {
		"text": "Accepted.",
		"consequence": {},
	}):
		_fail_mission_smoke_test("Valid pickup mission was rejected.")
		return
	QuestManager.active_quest["picked_up"] = true
	GlobalState.accept_special("Wrong Part", "Test", "Kova", "Grease Monkeys")
	var credits_before_wrong_part := GlobalState.player_credits
	var zenith_before_wrong_part := float(GlobalState.reputations["zenith"])
	QuestManager.complete_quest()
	if not QuestManager.is_quest_active() \
			or GlobalState.player_credits != credits_before_wrong_part \
			or not is_equal_approx(
				float(GlobalState.reputations["zenith"]),
				zenith_before_wrong_part
			):
		_fail_mission_smoke_test("Wrong pickup cargo granted mission rewards.")
		return
	GlobalState.clear_cargo()
	GlobalState.accept_special("Plasma Coupler", "Test", "Kova", "Grease Monkeys")
	QuestManager.complete_quest()
	if QuestManager.is_quest_active() \
			or GlobalState.player_credits != credits_before_wrong_part + 75 \
			or GlobalState.cargo_type != GlobalState.CargoType.EMPTY:
		_fail_mission_smoke_test("Correct pickup cargo did not complete cleanly.")
		return

	var non_kaelen_line := SpeechService.prepare_text(
		"Shiny, your cargo is ready.",
		"voice.jenna_kross.v1"
	)
	var kaelen_line := SpeechService.prepare_text(
		"Shiny, your cargo is ready.",
		"voice.kaelen.v1"
	)
	if non_kaelen_line != "Indy, your cargo is ready." \
			or kaelen_line != "Shiny, your cargo is ready.":
		_fail_mission_smoke_test("Speaker naming guard did not preserve Indy and Shiny rules.")
		return

	var ui := GlobalState.get_ui_manager()
	if not ui:
		_fail_mission_smoke_test("UIManager was unavailable for dialogue resilience test.")
		return
	ui.agent_dialogue_label.text = "Readable fallback dialogue."
	SpeechService._simulate_failed_request_for_test()
	if SpeechService.is_requesting \
			or ui.agent_dialogue_label.text != "Readable fallback dialogue.":
		_fail_mission_smoke_test("TTS failure disrupted readable dialogue or left the request stuck.")
		return

	print("[MissionSmokeTest] PASS: fallback, objective consistency, acceptance, progress, completion, abandonment, pickup validation, naming, and TTS resilience verified.")
	delete_savegame()
	get_tree().quit(0)

func _fail_mission_smoke_test(message: String) -> void:
	push_error("[MissionSmokeTest] FAIL: " + message)
	delete_savegame()
	get_tree().quit(1)

func _run_services_smoke_test() -> void:
	await get_tree().process_frame
	GlobalState.paused = false
	GlobalState.reset_for_restart()
	GlobalState.player = player
	QuestManager.active_quest = {}

	var ui := GlobalState.get_ui_manager()
	var system_root := get_active_system_root()
	var main_station := GlobalState.get_primary_station()
	var iron_reach: Node3D = null
	var kova: Node3D = null
	for station in get_tree().get_nodes_in_group("station"):
		if station is Node3D and system_root.is_ancestor_of(station):
			if station.name == "IronReachOutpost":
				iron_reach = station
			elif station.name == "KovaStation":
				kova = station
	if not ui or not main_station or not iron_reach or not kova:
		_fail_services_smoke_test(
			"Required station or UI nodes were unavailable. ui=%s main=%s iron=%s kova=%s" % [
				str(ui != null),
				str(main_station != null),
				str(iron_reach != null),
				str(kova != null),
			]
		)
		return

	# Full and partial repair paths must charge exactly two credits per hull point.
	player.health = 70.0
	GlobalState.player_credits = 100
	ui.call("_repair_ship")
	if not is_equal_approx(player.health, 100.0) or GlobalState.player_credits != 40:
		_fail_services_smoke_test("Full repair did not restore hull and charge correctly.")
		return
	player.health = 70.0
	GlobalState.player_credits = 20
	ui.call("_repair_ship")
	if not is_equal_approx(player.health, 80.0) or GlobalState.player_credits != 0:
		_fail_services_smoke_test("Partial repair did not use all affordable credits correctly.")
		return

	# The maintenance display and purchase path must both include station ore.
	GlobalState.reset_for_restart()
	GlobalState.player = player
	GlobalState.player_credits = 2000
	GlobalState.player_storage_ore = 250.0
	ui.current_station = main_station
	ui.current_submenu = ui.DockSubmenu.MAINTENANCE
	ui.call("_render_dock_submenu")
	ui.call("_refresh_upgrade_ui")
	if not ui.su_ore_bank_lbl.text.contains("Power Draw: 300 / 300 MW"):
		_fail_services_smoke_test("Upgrade panel did not show current power use.")
		return
	ui.call("_attempt_upgrade", "power", "standard")
	ui.call("_attempt_upgrade", "engine", "speed")
	if int(GlobalState.current_upgrades["power"]["tier"]) != 2 \
			or int(GlobalState.current_upgrades["engine"]["tier"]) != 2 \
			or not is_equal_approx(GlobalState.player_storage_ore, 50.0):
		_fail_services_smoke_test("Stored ore could not fund valid upgrades through the UI.")
		return

	if not save_game():
		_fail_services_smoke_test("Could not save upgraded service state.")
		return
	GlobalState.player_storage_ore = 0.0
	GlobalState.current_upgrades = {
		"weapons": {"tier": 1, "path": "base"},
		"engine": {"tier": 1, "path": "base"},
		"shields": {"tier": 1, "path": "base"},
		"mining": {"tier": 1, "path": "base"},
		"cargo": {"tier": 1, "path": "base"},
		"power": {"tier": 1, "path": "base"},
	}
	GlobalState.apply_upgrade_stats()
	if not await load_game() \
			or not is_equal_approx(GlobalState.player_storage_ore, 50.0) \
			or int(GlobalState.current_upgrades["power"]["tier"]) != 2 \
			or int(GlobalState.current_upgrades["engine"]["tier"]) != 2 \
			or not is_equal_approx(GlobalState.engine_speed_mult, 1.2):
		_fail_services_smoke_test("Storage or upgrades did not survive save and reload.")
		return

	# Outposts expose gossip and pickup routing, but not station commerce,
	# agents, maintenance, repair, or upgrades.
	ui.current_station = iron_reach
	ui.current_submenu = ui.DockSubmenu.SERVICES
	ui.call("_render_dock_submenu")
	if ui.sell_btn.visible \
			or ui.agent_service_btn.visible \
			or ui.maintenance_bay_btn.visible \
			or ui.repair_btn.visible \
			or ui.ship_upgrades_btn.visible \
			or not ui.hear_gossip_btn.visible:
		_fail_services_smoke_test("Outpost service restrictions were not rendered correctly.")
		return

	var gossip_holder := {"flavor": {}}
	var capture_gossip := func(flavor: Dictionary) -> void:
		gossip_holder["flavor"] = flavor
	GlobalState.npc_flavor_spoken.connect(capture_gossip, CONNECT_ONE_SHOT)
	ui.call("_on_hear_gossip_pressed")
	var flavor: Dictionary = gossip_holder["flavor"]
	if flavor.is_empty() \
			or str(flavor.get("line", "")).is_empty() \
			or str(flavor.get("voice_profile_id", "")).is_empty():
		_fail_services_smoke_test("Hear Gossip did not emit display and voice data.")
		return
	if not ui.dock_message_slot.visible \
			or ui.dock_message_line.text != GlobalState.apply_tone_guard(
				str(flavor["line"]),
				str(flavor["voice_profile_id"])
			):
		_fail_services_smoke_test("Outpost gossip was not displayed in the dock UI.")
		return

	QuestManager.active_quest = {
		"title": "Services Pickup",
		"faction": "neutral",
		"agent_name": "Jenna Kross",
		"objective_type": "PICKUP_SPECIAL",
		"target_outpost": "kova",
		"target_outpost_display": "Kova Station",
		"target_npc": "Cassen Vane",
		"part_name": "Sensor Calibration Kit",
		"destination": "Grease Monkeys",
		"picked_up": false,
		"reward_credits": 200,
		"reward_credits_multiplier": 1.0,
		"choice_text_selected": "I'll take it.",
	}
	GlobalState.clear_cargo()
	ui.current_station = iron_reach
	ui.call("_on_test_pickup_part_pressed")
	if bool(QuestManager.active_quest["picked_up"]) \
			or GlobalState.cargo_type != GlobalState.CargoType.EMPTY:
		_fail_services_smoke_test("Pickup succeeded at the wrong outpost.")
		return
	ui.current_station = kova
	ui.call("_on_test_pickup_part_pressed")
	if not bool(QuestManager.active_quest["picked_up"]) \
			or GlobalState.cargo_type != GlobalState.CargoType.SPECIAL \
			or GlobalState.cargo_special.get("name", "") != "Sensor Calibration Kit":
		_fail_services_smoke_test("Assigned outpost did not load the pickup cargo.")
		return

	var credits_before_delivery := GlobalState.player_credits
	ui.current_station = main_station
	ui.current_submenu = ui.DockSubmenu.MAINTENANCE
	ui.call("_on_deliver_part_pressed")
	if QuestManager.is_quest_active() \
			or GlobalState.cargo_type != GlobalState.CargoType.EMPTY \
			or GlobalState.player_credits != credits_before_delivery + 200:
		_fail_services_smoke_test("Returning the assigned part did not complete and pay the mission.")
		return

	print("[ServicesSmokeTest] PASS: repairs, upgrade UI, stored ore, persistence, outpost restrictions, gossip, and pickup routing verified.")
	delete_savegame()
	get_tree().quit(0)

func _fail_services_smoke_test(message: String) -> void:
	push_error("[ServicesSmokeTest] FAIL: " + message)
	delete_savegame()
	get_tree().quit(1)

func _fail_combat_smoke_test(message: String) -> void:
	if Engine.has_meta("combat_smoke_phase"):
		Engine.remove_meta("combat_smoke_phase")
	push_error("[CombatSmokeTest] FAIL: " + message)
	delete_savegame()
	get_tree().quit(1)

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

func _fail_core_smoke_test(message: String) -> void:
	push_error("[CoreSmokeTest] FAIL: " + message)
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
	var safe_source := campaign_checkpoint_store.runtime_state_from_active()
	if not bool(safe_source.get("ok", false)):
		_fail_jump_smoke_test("Manual save test has no active safe checkpoint.")
		return false
	var safe_source_credits := int(
		safe_source.get("state", {}).get("global", {}).get("credits", 0)
	)
	var safe_source_location: Dictionary = safe_source.get(
		"safe_location",
		{}
	)
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
	if int(GlobalState.current_upgrades["engine"]["tier"]) != 2 \
			or not is_equal_approx(GlobalState.engine_speed_mult, 1.2) \
			or not is_equal_approx(GlobalState.player_storage_ore, 77.0):
		_fail_jump_smoke_test("Upgrade or station-storage state did not restore.")
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

	var live_flight_position := player.global_position + Vector3(
		325.0,
		40.0,
		-210.0
	)
	player.global_position = live_flight_position
	GlobalState.player_credits = 9876
	var manual_status := get_manual_checkpoint_status()
	if not bool(manual_status.get("available", false)):
		_fail_jump_smoke_test(
			"Manual checkpoint was unexpectedly blocked: %s" %
				manual_status.get("block_reason", "")
		)
		return false
	var manual_saved := request_manual_checkpoint(
		0,
		"Flight Safety Copy",
		true
	)
	if not bool(manual_saved.get("ok", false)):
		_fail_jump_smoke_test(
			"Manual checkpoint could not be created: %s" %
				manual_saved.get("error", "")
		)
		return false
	var original_timeline_id := campaign_chronicle_store.current_timeline_id()
	var discarded_event := campaign_chronicle_store.append_event(
		"save_smoke_discarded_future",
		[campaign_chronicle_store.campaign.get("id", "")],
		{"purpose": "verify checkpoint branch filtering"},
		str(safe_source.get("checkpoint_id", ""))
	)
	if not bool(discarded_event.get("ok", false)):
		_fail_jump_smoke_test(
			"Save test could not append its discarded-future event."
		)
		return false
	_sync_checkpoint_chronicle_context()
	var manual_state := campaign_checkpoint_store.runtime_state_from_manual(0)
	if int(
		manual_state.get("state", {}).get("global", {}).get("credits", -1)
	) != safe_source_credits:
		_fail_jump_smoke_test(
			"In-flight manual save captured live credits instead of safe state."
		)
		return false
	GlobalState.player_credits = 2
	player.global_position += Vector3(500.0, 0.0, 500.0)
	if not await load_manual_checkpoint(0):
		_fail_jump_smoke_test("Manual checkpoint could not be loaded.")
		return false
	if campaign_chronicle_store.current_timeline_id() == original_timeline_id:
		_fail_jump_smoke_test(
			"Loading an older manual checkpoint did not create a timeline branch."
		)
		return false
	var current_branch := campaign_chronicle_store.current_branch_events()
	if not bool(current_branch.get("ok", false)):
		_fail_jump_smoke_test("The branched chronicle could not be queried.")
		return false
	for event in current_branch.get("events", []):
		if event.get("event_type", "") == "save_smoke_discarded_future":
			_fail_jump_smoke_test(
				"The discarded future remained visible on the new branch."
			)
			return false
	var safe_gate := _find_world_entity(
		str(safe_source_location.get("gate_id", ""))
	)
	if safe_gate == null \
			or GlobalState.player_credits != safe_source_credits \
			or player.global_position.distance_to(
				safe_gate.call("get_arrival_transform").origin
			) > 0.1 \
			or player.global_position.distance_to(live_flight_position) < 1.0:
		_fail_jump_smoke_test(
			"Manual checkpoint restored live flight state instead of the safe gate."
		)
		return false
	player.destroyed = true
	var dead_status := get_manual_checkpoint_status()
	player.destroyed = false
	if bool(dead_status.get("available", true)) \
			or dead_status.get("block_code", "") != "player_dead":
		_fail_jump_smoke_test(
			"Destroyed player did not receive the manual-save block reason."
		)
		return false
	print("[SaveSmokeTest] PASS: legacy save, manual safe-copy restore, chronicle branching, and validation verified.")
	return true
