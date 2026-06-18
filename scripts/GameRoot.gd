extends Node3D

signal system_changed(system_id: String, arrival_gate_id: String)
signal startup_load_completed(save_loaded: bool)

const ARRIVAL_COOLDOWN_SECONDS := 2.5
const JUMP_ENTRY_DURATION := 3.2
const JUMP_EXIT_DURATION := 0.9
const SAVE_VERSION := SaveMigrator.CURRENT_VERSION
const SAVE_PATH := "user://savegame.json"
const GATE_TRAVEL_MINUTES := 45
const DOCK_SERVICE_MINUTES := 10
const UNDOCK_SERVICE_MINUTES := 5
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
const CampaignKaelenMemoryStoreType := preload(
	"res://scripts/persistence/CampaignKaelenMemoryStore.gd"
)
const CampaignLegacySaveImporterType := preload(
	"res://scripts/persistence/CampaignLegacySaveImporter.gd"
)
const RuntimeTraceType := preload(
	"res://scripts/diagnostics/RuntimeTrace.gd"
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
var campaign_kaelen_memory_store: CampaignKaelenMemoryStore
var last_legacy_import_result: Dictionary = {}
var active_campaign_slot_id: String = ""
var restoring_safe_checkpoint: bool = false
var last_autosave_notification_key: String = ""
var last_autosave_notification_msec: int = 0
var pending_gate_discoveries: Array[String] = []
var event_scheduler = null
var ship_pre_generator: ShipPreGenerator = null

func _ready() -> void:
	_init_event_scheduler()
	RuntimeTraceType.begin_session()
	RuntimeTraceType.event("game", "root_ready", {
		"arguments": OS.get_cmdline_user_args(),
	})
	scene_ready_msec = Time.get_ticks_msec()
	system_registry = SystemRegistry.load_default()
	if not system_registry.is_valid():
		push_error(
			"[GameRoot] System registry is invalid: %s" %
			system_registry.validation.summary()
		)
		get_tree().quit(1)
		return
	_init_generated_system_configs()
	var start_definition := system_registry.get_system("system.start")
	if start_definition == null:
		push_error("[GameRoot] Registered starting system could not be loaded.")
		get_tree().quit(1)
		return
	var system_root := system_registry.instantiate_system("system.start")
	if system_root == null:
		push_error("[GameRoot] Registered starting system has an invalid root.")
		get_tree().quit(1)
		return
	system_container.add_child(system_root)
	GlobalState.active_system_root = system_root
	GlobalState.current_system_id = start_definition.legacy_id
	ship_pre_generator = ShipPreGenerator.new()
	ship_pre_generator.name = "ShipPreGenerator"
	ship_pre_generator.initialize(system_registry)
	add_child(ship_pre_generator)
	system_changed.connect(ship_pre_generator.on_system_entered)
	ship_pre_generator.on_system_entered(start_definition.legacy_id, "")
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
	elif "--llm-validator-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_llm_validator_smoke_test")
	elif "--combat-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_combat_smoke_test")
	elif "--station-combat-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_station_combat_smoke_test")
	elif "--economy-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_economy_smoke_test")
	elif "--autopilot-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_autopilot_smoke_test")
	elif "--restart-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_restart_smoke_test")
	elif "--death-reload-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_death_reload_smoke_test")
	elif "--multi-mission-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_multi_mission_smoke_test")
	elif "--legacy-import-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_legacy_import_smoke_test")
	elif "--public-board-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_run_public_board_smoke_test")
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
	if runtime_system_id.is_empty() or runtime_gate_id.is_empty():
		jump_request_pending = false
		push_warning(
			"[GameRoot] Destination system or arrival gate is not registered."
		)
		return

	var new_system := system_registry.instantiate_system(destination_system_id)
	if not new_system:
		jump_request_pending = false
		push_warning("[GameRoot] Unknown destination system '%s'." % destination_system_id)
		return
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
	var source_gate_id := (
		str(source_gate.call("get_world_id"))
		if source_gate != null
			and is_instance_valid(source_gate)
			and source_gate.has_method("get_world_id")
		else ""
	)
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
	CampaignClock.advance_minutes(GATE_TRAVEL_MINUTES)
	arrival_cooldown_until_msec = Time.get_ticks_msec() + int(ARRIVAL_COOLDOWN_SECONDS * 1000.0)
	transition_in_progress = false
	_queue_gate_discovery(
		source_gate_id,
		str(arrival_gate.call("get_world_id"))
	)
	if event_scheduler:
		event_scheduler.set_just_arrived(true)
	_tick_events()
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
	if not pending_gate_discoveries.is_empty() \
			and not campaign_checkpoint_store.mark_gates_known(
				pending_gate_discoveries
			):
		push_warning("[GameRoot] Gate discovery could not be recorded.")
		_notify_checkpoint_failure()
		return false
	_sync_checkpoint_chronicle_context()
	var safe_location := _safe_location_for(source_reason, safe_entity)
	if safe_location.is_empty():
		push_warning("[GameRoot] Safe checkpoint location is unavailable.")
		_notify_checkpoint_failure()
		return false
	var prior_campaign_time := CampaignClock.capture_state()
	_advance_campaign_time_for_safe_checkpoint(source_reason)
	prepared["data"]["global"]["campaign_time"] = CampaignClock.capture_state()
	var captured := campaign_checkpoint_store.capture_autosave(
		prepared["data"],
		safe_location,
		source_reason
	)
	if not bool(captured.get("ok", false)):
		CampaignClock.restore_state(prior_campaign_time)
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
	pending_gate_discoveries.clear()
	_notify_autosave_success(source_reason, safe_location)
	return true


func _advance_campaign_time_for_safe_checkpoint(source_reason: String) -> void:
	if source_reason == "dock":
		CampaignClock.advance_minutes(DOCK_SERVICE_MINUTES)
		_tick_events()
	elif source_reason == "undock":
		CampaignClock.advance_minutes(UNDOCK_SERVICE_MINUTES)
		_tick_events()


func _queue_gate_discovery(
	source_gate_id: String,
	arrival_gate_id: String
) -> void:
	for gate_id in [source_gate_id, arrival_gate_id]:
		if gate_id.is_empty() or gate_id in pending_gate_discoveries:
			continue
		pending_gate_discoveries.append(gate_id)


func get_gate_knowledge_state(gate_id: String) -> String:
	if campaign_checkpoint_store == null:
		return "unknown"
	if campaign_checkpoint_store._initial_known_gates.is_empty() and system_registry:
		campaign_checkpoint_store.set_registry_defaults(system_registry)
	return campaign_checkpoint_store.get_gate_state(gate_id)


func _refresh_gate_states() -> void:
	var system_root := get_active_system_root()
	if system_root == null:
		return
	for node in system_root.get_children():
		if node.is_in_group("jumpgate") and node.has_method("_apply_knowledge_state"):
			node._apply_knowledge_state()


func _init_generated_system_configs() -> void:
	for sys_def: SystemDefinition in system_registry.get_all_systems():
		if sys_def.scene_path != "generated":
			continue
		var sys_id := str(sys_def.id)
		if system_registry.get_generated_config(sys_id) != null:
			continue
		var seed_val: int = sys_id.hash()
		var config := SystemConfig.from_seed(sys_def.display_name, sys_id, seed_val)
		system_registry.set_generated_config(sys_id, config)
		system_registry.set_generated_config(config.legacy_id, config)


func _init_event_scheduler() -> void:
	var EventSchedulerScript = preload("res://scripts/events/EventScheduler.gd")
	var InterceptorEventScript = preload("res://scripts/events/types/InterceptorEvent.gd")
	var GateRumorEventScript = preload("res://scripts/events/types/GateRumorEvent.gd")
	event_scheduler = EventSchedulerScript.shared()
	event_scheduler.register_event_type(InterceptorEventScript.new(), 90)
	event_scheduler.register_event_type(GateRumorEventScript.new(), 120)


func _tick_events() -> void:
	if event_scheduler == null:
		return
	var EventContextScript = preload("res://scripts/events/EventContext.gd")
	var ctx = EventContextScript.new()
	ctx.campaign_time = CampaignClock.total_minutes
	ctx.current_system_id = GlobalState.current_system_id
	ctx.player_credits = GlobalState.player_credits
	ctx.reputations = GlobalState.reputations.duplicate()
	var risk_tags: Array[String] = []
	for m in QuestManager.get_mission_collection().get_all_active():
		for tag in m.data.get("risk_tags", []):
			if tag is String and tag not in risk_tags:
				risk_tags.append(tag)
	ctx.active_mission_risk_tags = risk_tags
	event_scheduler.tick(CampaignClock.total_minutes, ctx)


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
	if not _classify_kaelen_rollback(restored):
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
	var autosave := {}
	if campaign_checkpoint_store != null:
		var active := campaign_checkpoint_store.runtime_state_from_active()
		if bool(active.get("ok", false)):
			autosave = {
				"available": true,
				"source_reason": active.get("source_reason", ""),
				"safe_location": active.get("safe_location", {}),
				"created_at_unix": int(
					campaign_checkpoint_store.index.get(
						"autosave",
						{}
					).get("created_at_unix", 0)
				),
			}
	return {
		"ok": true,
		"slots": campaign_slot_registry.enumerate_slots(),
		"selected_slot_id": campaign_slot_registry.selected_slot_id,
		"legacy_import": CampaignLegacySaveImporterType.status(
			campaign_slot_registry,
			system_registry,
			SAVE_PATH
		),
		"manual":
			campaign_checkpoint_store.list_manual_checkpoints()
			if campaign_checkpoint_store != null
			else [],
		"autosave": autosave,
	}


func import_legacy_save(slot_id: String = "") -> Dictionary:
	if campaign_slot_registry == null:
		_initialize_campaign_registry()
	if campaign_slot_registry == null:
		return {"ok": false, "error": "Campaign storage is unavailable."}
	var imported := (
		CampaignLegacySaveImporterType.import_first_available(
			campaign_slot_registry,
			system_registry,
			SAVE_PATH
		)
		if slot_id.is_empty()
		else CampaignLegacySaveImporterType.import_to_slot(
			campaign_slot_registry,
			system_registry,
			slot_id,
			SAVE_PATH
		)
	)
	last_legacy_import_result = imported.duplicate(true)
	if not bool(imported.get("ok", false)):
		_notify_system_warning(str(imported.get("error", "")))
		return imported
	active_campaign_slot_id = str(imported.get("slot_id", ""))
	var slot_path := "%s/%s" % [
		campaign_slot_registry.root_path,
		active_campaign_slot_id,
	]
	campaign_checkpoint_store = CampaignCheckpointStoreType.open(slot_path)
	_initialize_campaign_chronicle()
	GlobalState.emit_chatter(
		"SYSTEM",
		"Prototype save imported into the campaign store.",
		Color(0.0, 0.9, 0.9)
	)
	return imported


func create_campaign_in_slot(
	slot_id: String,
	display_name: String
) -> Dictionary:
	var creating_fresh_campaign := Engine.has_meta(
		"creating_new_campaign"
	)
	if creating_fresh_campaign:
		QuestManager.reset_for_restart()
	var prepared := _capture_prepared_runtime_state()
	if not bool(prepared.get("ok", false)):
		return {
			"ok": false,
			"error": prepared.get(
				"error",
				"Current gameplay state could not start a campaign."
			),
		}
	if creating_fresh_campaign:
		prepared["data"]["quest"] = {}
		var opening_name := str(
			Engine.get_meta("pending_opening_campaign_name", "")
		).strip_edges()
		if not opening_name.is_empty():
			display_name = opening_name
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
	if creating_fresh_campaign:
		Engine.remove_meta("creating_new_campaign")
		if Engine.has_meta("pending_opening_campaign_name"):
			Engine.remove_meta("pending_opening_campaign_name")
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
	if Engine.has_meta("creating_new_campaign"):
		Engine.remove_meta("creating_new_campaign")
	if Engine.has_meta("pending_opening_campaign_name"):
		Engine.remove_meta("pending_opening_campaign_name")
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


func apply_opening_campaign_name(display_name: String) -> bool:
	if Engine.has_meta("creating_new_campaign"):
		Engine.set_meta(
			"pending_opening_campaign_name",
			display_name
		)
		return true
	if campaign_slot_registry == null:
		_initialize_campaign_registry()
	if campaign_slot_registry == null or active_campaign_slot_id.is_empty():
		return false
	var active_slot: Dictionary = campaign_slot_registry.get_slot(
		active_campaign_slot_id
	)
	var current_name := str(active_slot.get("display_name", ""))
	if current_name not in [
		"Shiny's Campaign",
		"Pending Campaign",
		"Campaign 1",
		"Campaign 2",
		"Campaign 3",
	]:
		return true
	var renamed := campaign_slot_registry.rename_campaign(
		active_campaign_slot_id,
		display_name
	)
	return bool(renamed.get("ok", false))


func delete_campaign_slot(slot_id: String) -> Dictionary:
	if campaign_slot_registry == null:
		_initialize_campaign_registry()
	if campaign_slot_registry == null:
		return {"ok": false, "error": "Campaign storage is unavailable."}
	var deleted_active_campaign := active_campaign_slot_id == slot_id
	var deleted := campaign_slot_registry.delete_campaign(slot_id)
	if not bool(deleted.get("ok", false)):
		_notify_system_warning(str(deleted.get("error", "")))
		return deleted
	if active_campaign_slot_id == slot_id:
		active_campaign_slot_id = ""
		campaign_checkpoint_store = null
		campaign_chronicle_store = null
		campaign_kaelen_memory_store = null
	deleted["deleted_active_campaign"] = deleted_active_campaign
	GlobalState.emit_chatter(
		"SYSTEM",
		"Campaign slot deleted.",
		Color(0.0, 0.9, 0.9)
	)
	return deleted


func reset_after_active_campaign_deleted(replacement_slot_id: String = "") -> void:
	Engine.set_meta("open_campaign_manager_after_death", true)
	Engine.set_meta("skip_campaign_load_once", true)
	Engine.set_meta("creating_new_campaign", true)
	var target_slot_id := replacement_slot_id.strip_edges()
	if target_slot_id.is_empty():
		if campaign_slot_registry == null:
			_initialize_campaign_registry()
		if campaign_slot_registry != null:
			target_slot_id = campaign_slot_registry.first_empty_slot_id()
	if not target_slot_id.is_empty():
		Engine.set_meta("pending_new_campaign_slot", target_slot_id)
	if Engine.has_meta("pending_opening_campaign_name"):
		Engine.remove_meta("pending_opening_campaign_name")
	_reset_and_reload_scene()


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
	var quest_array: Array = QuestManager.capture_all_quests()
	if QuestManager.is_quest_active() and quest_array.is_empty():
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
		"quest": quest_array,
		"board_cooldowns": QuestManager.capture_board_cooldowns(),
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
		var automatic_name := str(
			Engine.get_meta(
				"pending_opening_campaign_name",
				"Shiny's Campaign"
			)
		)
		if Engine.has_meta("creating_new_campaign"):
			QuestManager.reset_for_restart()
			prepared_runtime_state["quest"] = {}
		var created := campaign_slot_registry.create_campaign(
			active_campaign_slot_id,
			automatic_name,
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
		if Engine.has_meta("creating_new_campaign"):
			Engine.remove_meta("creating_new_campaign")
		if Engine.has_meta("pending_opening_campaign_name"):
			Engine.remove_meta("pending_opening_campaign_name")
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
	campaign_kaelen_memory_store = null
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
	var opened_memory := CampaignKaelenMemoryStoreType.open(slot_path)
	if not opened_memory.is_valid():
		push_warning(
			"[GameRoot] Kaelen memory store is unavailable: %s" %
				opened_memory.validation.summary()
		)
		campaign_chronicle_store = null
		return
	campaign_kaelen_memory_store = opened_memory
	_sync_checkpoint_chronicle_context()
	_import_legacy_quest_history()


func _classify_kaelen_rollback(restored: Dictionary) -> bool:
	if campaign_chronicle_store == null \
			or campaign_kaelen_memory_store == null:
		return false
	var head_event_id := str(
		restored.get("chronicle_head_event_id", "")
	)
	var boundary_sequence := campaign_chronicle_store.event_sequence(
		head_event_id
	)
	if boundary_sequence < 0:
		_notify_system_warning(
			"The selected checkpoint has no valid memory boundary."
		)
		return false
	var classified := campaign_kaelen_memory_store.classify_rollback(
		str(restored.get("timeline_id", "")),
		str(restored.get("checkpoint_id", "")),
		boundary_sequence
	)
	if not bool(classified.get("ok", false)):
		_notify_system_warning(
			"Timeline memory could not be reconciled with the checkpoint."
		)
		return false
	return true


func record_player_death(death_source: String = "") -> void:
	if campaign_checkpoint_store == null:
		_initialize_campaign_registry()
	if campaign_checkpoint_store == null \
			or campaign_chronicle_store == null \
			or campaign_kaelen_memory_store == null:
		return
	var active := campaign_checkpoint_store.runtime_state_from_active()
	if not bool(active.get("ok", false)):
		return
	var death_category := _death_category_for_source(death_source)
	var payload := {"death_category": death_category}
	if not death_source.is_empty():
		payload["source"] = death_source
	var appended := campaign_chronicle_store.append_event(
		"player_death",
		[campaign_chronicle_store.campaign["id"]],
		payload,
		str(active.get("checkpoint_id", ""))
	)
	if not bool(appended.get("ok", false)):
		push_warning("[GameRoot] Player death could not be recorded.")
		return
	var event: Dictionary = appended["event"]
	var summary := "Shiny's ship was destroyed."
	if death_category == "combat":
		summary = "Shiny's ship was destroyed in combat."
	elif death_category == "collision":
		summary = "Shiny's ship was destroyed in a collision."
	elif death_category == "environment":
		summary = "Shiny's ship was destroyed by an environmental hazard."
	var remembered := campaign_kaelen_memory_store.append_memory(
		"death",
		summary,
		[],
		str(event.get("timeline_id", "")),
		str(active.get("checkpoint_id", "")),
		int(event.get("sequence", -1)),
		death_category
	)
	if not bool(remembered.get("ok", false)):
		push_warning("[GameRoot] Kaelen could not retain the death memory.")
	_sync_checkpoint_chronicle_context()


func restore_latest_campaign_checkpoint_after_death() -> bool:
	if campaign_checkpoint_store == null:
		_initialize_campaign_registry()
	if campaign_checkpoint_store == null \
			or campaign_chronicle_store == null:
		return false
	var restored := campaign_checkpoint_store.runtime_state_from_active()
	if not bool(restored.get("ok", false)) \
			or not _classify_kaelen_rollback(restored):
		return false
	var branched := campaign_chronicle_store.branch_from_checkpoint({
		"id": restored.get("checkpoint_id", ""),
		"timeline_id": restored.get("timeline_id", ""),
		"chronicle_head_event_id":
			restored.get("chronicle_head_event_id", ""),
	})
	if not bool(branched.get("ok", false)):
		return false
	_reopen_campaign_checkpoint_store()
	_sync_checkpoint_chronicle_context()
	_reset_and_reload_scene()
	return true


func can_start_new_campaign() -> bool:
	if campaign_slot_registry == null:
		_initialize_campaign_registry()
	return campaign_slot_registry != null \
		and not campaign_slot_registry.first_empty_slot_id().is_empty()


func start_new_campaign_after_death() -> bool:
	if campaign_slot_registry == null:
		_initialize_campaign_registry()
	if campaign_slot_registry == null:
		return false
	var target_slot_id := campaign_slot_registry.first_empty_slot_id()
	if target_slot_id.is_empty():
		_notify_system_warning(
			"All three campaigns are occupied. Delete one to start another."
		)
		return false
	Engine.set_meta("open_campaign_manager_after_death", true)
	Engine.set_meta("skip_campaign_load_once", true)
	Engine.set_meta("creating_new_campaign", true)
	Engine.set_meta("pending_new_campaign_slot", target_slot_id)
	if Engine.has_meta("pending_opening_campaign_name"):
		Engine.remove_meta("pending_opening_campaign_name")
	_reset_and_reload_scene()
	return true


func get_kaelen_current_memories() -> Array:
	if campaign_kaelen_memory_store == null:
		return []
	return campaign_kaelen_memory_store.current_memories()


func _death_category_for_source(death_source: String) -> String:
	if death_source == "collision":
		return "collision"
	if death_source in ["environment", "self"]:
		return "environment"
	if not death_source.is_empty():
		return "combat"
	return "unknown"


func _reset_and_reload_scene() -> void:
	CampaignClock.reset_for_restart()
	LLMInterface.reset_for_restart()
	QuestManager.reset_for_restart()
	GlobalState.reset_for_restart()
	get_tree().reload_current_scene()


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
	if campaign_checkpoint_store == null \
			or not campaign_checkpoint_store.restore_map_knowledge(
				restored.get("map_knowledge", {})
			):
		push_warning(
			"[GameRoot] Campaign checkpoint map knowledge could not be restored."
		)
		return false
	pending_gate_discoveries.clear()
	var safe_location: Dictionary = restored.get(
		"safe_location",
		{}
	).duplicate(true)
	RuntimeTraceType.event("checkpoint", "restore_started", {
		"checkpoint_id": str(restored.get("checkpoint_id", "")),
		"source_system_id": GlobalState.current_system_id,
		"target_system_id": str(safe_location.get("system_id", "")),
		"safe_location": safe_location,
	})
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
	RuntimeTraceType.event("checkpoint", "restore_completed", {
		"checkpoint_id": str(restored.get("checkpoint_id", "")),
		"system_id": GlobalState.current_system_id,
		"player_position": [
			player.global_position.x,
			player.global_position.y,
			player.global_position.z,
		],
	})
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
	if Engine.has_meta("skip_campaign_load_once"):
		Engine.remove_meta("skip_campaign_load_once")
		var target_slot_id := str(
			Engine.get_meta("pending_new_campaign_slot", "")
		)
		if Engine.has_meta("pending_new_campaign_slot"):
			Engine.remove_meta("pending_new_campaign_slot")
		if not target_slot_id.is_empty():
			var created := create_campaign_in_slot(
				target_slot_id,
				"Pending Campaign"
			)
			if not bool(created.get("ok", false)):
				push_warning(
					"[GameRoot] Fresh campaign could not claim %s: %s" % [
						target_slot_id,
						created.get("error", "unknown error"),
					]
				)
		startup_save_loaded = false
		startup_load_finished = true
		_refresh_gate_states()
		startup_load_completed.emit(false)
		return
	_initialize_campaign_registry()
	if campaign_checkpoint_store != null \
			and campaign_checkpoint_store.is_valid():
		startup_save_loaded = await _load_campaign_checkpoint()
	elif FileAccess.file_exists(SAVE_PATH):
		var imported := import_legacy_save()
		if bool(imported.get("ok", false)) \
				and campaign_checkpoint_store != null:
			startup_save_loaded = await _load_campaign_checkpoint()
		else:
			push_warning(
				"[GameRoot] Campaign import was not completed: %s" %
					imported.get(
						"error",
						"Use Campaigns & Saves to review import recovery."
					)
			)
			startup_save_loaded = await load_game()
	else:
		startup_save_loaded = await load_game()
		var prepared := _capture_prepared_runtime_state()
		if bool(prepared.get("ok", false)):
			_ensure_campaign_checkpoint_store(prepared["data"])
	startup_load_finished = true
	_refresh_gate_states()
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
	var quest_source = data.get("quest", {})
	var quest_ok := false
	if quest_source is Array:
		quest_ok = QuestManager.restore_all_quests(quest_source)
	else:
		quest_ok = QuestManager.restore_active_quest(quest_source)
	if not quest_ok:
		push_warning("[GameRoot] Save mission state failed validation during restore.")
		return
	var saved_cooldowns = data.get("board_cooldowns", {})
	if saved_cooldowns is Dictionary and not saved_cooldowns.is_empty():
		QuestManager.restore_board_cooldowns(saved_cooldowns)
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
	var new_system := system_registry.instantiate_system(system_id)
	if not new_system:
		RuntimeTraceType.event("transition", "load_failed", {
			"requested_system_id": system_id,
			"source_system_id": GlobalState.current_system_id,
		})
		return
	RuntimeTraceType.event("transition", "load_started", {
		"requested_system_id": system_id,
		"runtime_system_id": runtime_system_id,
		"source_system_id": GlobalState.current_system_id,
	})
	GlobalState.active_target = null
	GlobalState.active_system_entities.clear()
	var old_system := get_active_system_root()
	GlobalState.active_system_root = null
	if old_system:
		old_system.queue_free()
		await get_tree().process_frame
	system_container.add_child(new_system)
	GlobalState.active_system_root = new_system
	GlobalState.current_system_id = runtime_system_id
	await get_tree().process_frame
	_restore_system_state(runtime_system_id, new_system)
	RuntimeTraceType.event("transition", "load_completed", {
		"runtime_system_id": GlobalState.current_system_id,
		"active_system_root": str(new_system.name),
	})

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
		"campaign_time": CampaignClock.capture_state(),
		"credits": GlobalState.player_credits,
		"cargo": GlobalState.cargo,
		"cargo_type": GlobalState.cargo_type,
		"cargo_special": GlobalState.cargo_special.duplicate(true),
		"storage_ore": GlobalState.player_storage_ore,
		"upgrades": GlobalState.current_upgrades.duplicate(true),
		"reputations": GlobalState.reputations.duplicate(true),
		"faction_kills": GlobalState.faction_kills.duplicate(true),
		"inventory": GlobalState.inventory.to_dict(),
		"store_stock": GlobalState.StoreRegistryScript.shared().save_stock_state(),
	}

func _apply_global_state(state: Dictionary) -> void:
	CampaignClock.restore_state(state.get("campaign_time", {}))
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
	var loaded_kills: Dictionary = state.get(
		"faction_kills",
		GlobalState.faction_kills
	).duplicate(true)
	for faction_name: Variant in loaded_kills.keys():
		loaded_kills[faction_name] = int(loaded_kills[faction_name])
	GlobalState.faction_kills = loaded_kills
	var inv_data: Dictionary = state.get("inventory", {})
	GlobalState.inventory = GlobalState.PlayerInventoryScript.from_dict(inv_data)
	var stock_data: Dictionary = state.get("store_stock", {})
	if not stock_data.is_empty():
		GlobalState.StoreRegistryScript.shared().restore_stock_state(stock_data)
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
	var start_time_minutes := CampaignClock.total_minutes

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
	if CampaignClock.total_minutes != start_time_minutes + GATE_TRAVEL_MINUTES:
		_fail_jump_smoke_test("Outbound jump did not advance campaign time.")
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
	if CampaignClock.total_minutes \
			!= start_time_minutes + GATE_TRAVEL_MINUTES * 2:
		_fail_jump_smoke_test("Return jump did not advance campaign time.")
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
	var arrival_gate_id := str(arrival_gate.get_world_id())
	var paired_gate_id := str(
		system_registry.resolve_gate_id(
			arrival_gate.get("destination_gate_id")
		)
	)
	var known_gate_ids: Array = checkpoint.get(
		"map_knowledge",
		{}
	).get("known_gate_ids", [])
	if arrival_gate_id not in known_gate_ids \
			or paired_gate_id not in known_gate_ids:
		_fail_jump_smoke_test(
			"Gate arrival checkpoint did not reveal both route endpoints."
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
		player.staged_jump_gate_id != return_gate.get_instance_id()
		or int(player.get("avoidance_obstacle_id"))
			!= ring_planet.get_instance_id()
		or player.get("avoidance_waypoint") != return_gate.global_position
		or player.nav_mode != "JUMP_APPROACH"
		or player.get("navigation_target") != return_gate
	):
		_fail_jump_smoke_test(
			"Selecting a ring asteroid changed the active gate route."
		)
		return false
	if not bool(player.call("begin_target_navigation", "APPROACH")) \
			or player.get("navigation_target") != ring_target \
			or player.nav_mode != "APPROACH" \
			or player.staged_jump_gate_id != 0:
		_fail_jump_smoke_test(
			"Explicit ring-target approach did not replace the gate route."
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
		player.get("navigation_target") != ring_target
		or player.nav_mode != "APPROACH"
	):
		_fail_jump_smoke_test(
			"Selecting an alternate ring target changed the commanded route."
		)
		return false
	if not bool(player.call("begin_target_navigation", "APPROACH")):
		_fail_jump_smoke_test(
			"Explicit alternate ring-target command was rejected."
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
	if not bool(player.call("begin_target_navigation", "APPROACH")):
		_fail_jump_smoke_test(
			"Explicit front-target approach was rejected."
		)
		return false
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
		player.get("navigation_target") != front_target
		or player.nav_mode != "APPROACH"
	):
		_fail_jump_smoke_test(
			"Selecting the rear target changed the forward route."
		)
		return false
	if not bool(player.call("begin_target_navigation", "APPROACH")) \
			or player.get("navigation_target") != rear_target:
		_fail_jump_smoke_test(
			"Explicit rear-target approach did not replace the forward route."
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
			or ui.get("campaign_manual_vbox") == null \
			or ui.get("campaign_load_fade") == null:
		_fail_core_smoke_test(
			"Campaign manager UI was not constructed."
		)
		return
	var load_after_death := ui.find_child(
		"LoadLastSaveButton",
		true,
		false
	)
	var new_after_death := ui.find_child(
		"StartNewCampaignButton",
		true,
		false
	)
	if load_after_death == null \
			or load_after_death.get("text") != "Load Last Save" \
			or new_after_death == null \
			or new_after_death.get("text") != "Start New Campaign":
		_fail_core_smoke_test(
			"Death screen recovery choices were not constructed."
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


func _run_death_reload_smoke_test() -> void:
	await get_tree().process_frame
	var phase := int(Engine.get_meta("death_reload_smoke_phase", 0))
	if phase == 3:
		await _load_startup_save()
		await get_tree().process_frame
		await get_tree().process_frame
		Engine.remove_meta("death_reload_smoke_phase")
		var expected_campaign_count := int(
			Engine.get_meta("death_reload_expected_campaign_count", -1)
		)
		var expected_replacement_slot := str(
			Engine.get_meta("death_reload_expected_replacement_slot", "")
		)
		Engine.remove_meta("death_reload_expected_campaign_count")
		Engine.remove_meta("death_reload_expected_replacement_slot")
		var occupied_campaigns := 0
		if campaign_slot_registry != null:
			for slot in campaign_slot_registry.enumerate_slots():
				if bool(slot.get("occupied", false)):
					occupied_campaigns += 1
		var ui := GlobalState.get_ui_manager()
		var campaign_panel_node = ui.get("campaign_panel") if ui else null
		if startup_save_loaded \
				or player == null \
				or not is_instance_valid(player) \
				or bool(player.get("destroyed")) \
				or GlobalState.player_credits != 50 \
				or QuestManager.is_quest_active() \
				or occupied_campaigns != expected_campaign_count \
				or active_campaign_slot_id != expected_replacement_slot \
				or campaign_checkpoint_store == null \
				or not campaign_checkpoint_store.is_valid() \
				or campaign_panel_node == null \
				or not campaign_panel_node.visible:
			_fail_death_reload_smoke_test(
				"Active campaign deletion did not create a fresh replacement campaign."
			)
			return
		print(
			"[DeathReloadSmokeTest] PASS: death recovery and active campaign deletion both restart into clean campaign state."
		)
		get_tree().quit(0)
		return
	if phase == 2:
		await _load_startup_save()
		await get_tree().process_frame
		await get_tree().process_frame
		var expected_campaign_count := int(
			Engine.get_meta("death_reload_expected_campaign_count", -1)
		)
		var occupied_campaigns := 0
		if campaign_slot_registry != null:
			for slot in campaign_slot_registry.enumerate_slots():
				if bool(slot.get("occupied", false)):
					occupied_campaigns += 1
		var ui := GlobalState.get_ui_manager()
		var campaign_panel_node = ui.get("campaign_panel") if ui else null
		if startup_save_loaded \
				or player == null \
				or not is_instance_valid(player) \
				or bool(player.get("destroyed")) \
				or GlobalState.player_credits != 50 \
				or QuestManager.is_quest_active() \
				or occupied_campaigns != expected_campaign_count \
				or active_campaign_slot_id.is_empty() \
				or campaign_checkpoint_store == null \
				or not campaign_checkpoint_store.is_valid() \
				or campaign_panel_node == null \
				or not campaign_panel_node.visible:
			_fail_death_reload_smoke_test(
				"New campaign recovery did not open with fresh quest state."
			)
			return
		var replacement_slot_id := active_campaign_slot_id
		var deleted := delete_campaign_slot(replacement_slot_id)
		if not bool(deleted.get("ok", false)) \
				or not bool(deleted.get("deleted_active_campaign", false)):
			_fail_death_reload_smoke_test(
				"Active campaign fixture could not be deleted."
			)
			return
		Engine.set_meta("death_reload_smoke_phase", 3)
		Engine.set_meta(
			"death_reload_expected_campaign_count",
			expected_campaign_count
		)
		Engine.set_meta(
			"death_reload_expected_replacement_slot",
			replacement_slot_id
		)
		reset_after_active_campaign_deleted(replacement_slot_id)
		return
	if phase == 1:
		await _load_startup_save()
		await get_tree().process_frame
		var expected_reversals := int(
			Engine.get_meta("death_reload_expected_reversals", -1)
		)
		var expected_death_sequence := int(
			Engine.get_meta("death_reload_memory_sequence", -1)
		)
		Engine.remove_meta("death_reload_smoke_phase")
		Engine.remove_meta("death_reload_expected_reversals")
		Engine.remove_meta("death_reload_memory_sequence")
		var ui := GlobalState.get_ui_manager()
		var death_panel_node = ui.get("death_panel") if ui else null
		if not startup_save_loaded \
				or player == null \
				or not is_instance_valid(player) \
				or bool(player.get("destroyed")) \
				or GlobalState.player_credits != 321 \
				or death_panel_node == null \
				or death_panel_node.visible \
				or campaign_kaelen_memory_store == null \
				or campaign_kaelen_memory_store.reversal_count() \
					!= expected_reversals:
			_fail_death_reload_smoke_test(
				"Living checkpoint state was not restored after death."
			)
			return
		for memory in campaign_kaelen_memory_store.current_memories():
			if int(memory.get("local_sequence", -1)) \
					== expected_death_sequence:
				_fail_death_reload_smoke_test(
					"Discarded death leaked into current memory."
				)
				return
		var discarded_death_found := false
		for memory in (
			campaign_kaelen_memory_store
			.diagnostic_discarded_memories()
		):
			if int(memory.get("local_sequence", -1)) \
					== expected_death_sequence \
					and memory.get("category", "") == "death" \
					and memory.get("death_category", "") == "combat":
				discarded_death_found = true
				break
		if not discarded_death_found:
			_fail_death_reload_smoke_test(
				"Verified death was not retained as discarded memory."
			)
			return
		player.call("take_damage", 100000.0, "aurelia")
		await get_tree().process_frame
		var occupied_before_new_campaign := 0
		for slot in campaign_slot_registry.enumerate_slots():
			if bool(slot.get("occupied", false)):
				occupied_before_new_campaign += 1
		Engine.set_meta("death_reload_smoke_phase", 2)
		Engine.set_meta(
			"death_reload_expected_campaign_count",
			occupied_before_new_campaign + 1
		)
		ui.call("_start_new_campaign_after_death")
		return

	GlobalState.paused = false
	GlobalState.player_credits = 321
	var arrival_gate: Node3D = null
	var system_root := get_active_system_root()
	for candidate in get_tree().get_nodes_in_group("jumpgate"):
		if candidate is Node3D and system_root.is_ancestor_of(candidate):
			arrival_gate = candidate as Node3D
			break
	if arrival_gate == null \
			or not request_safe_checkpoint("gate_arrival", arrival_gate):
		_fail_death_reload_smoke_test(
			"Could not create the living checkpoint fixture."
		)
		return
	var prior_reversals := campaign_kaelen_memory_store.reversal_count()
	GlobalState.player_credits = 999
	player.call("take_damage", 100000.0, "aurelia")
	await get_tree().process_frame
	var death_memory_sequence := -1
	for memory in campaign_kaelen_memory_store.current_memories():
		if memory.get("category", "") == "death":
			death_memory_sequence = maxi(
				death_memory_sequence,
				int(memory.get("local_sequence", -1))
			)
	var ui := GlobalState.get_ui_manager()
	var death_panel_node = ui.get("death_panel") if ui else null
	if ui == null \
			or death_panel_node == null \
			or not death_panel_node.visible \
			or death_memory_sequence < 0:
		_fail_death_reload_smoke_test(
			"Fatal damage did not present the death recovery screen."
		)
		return
	Engine.set_meta("death_reload_smoke_phase", 1)
	Engine.set_meta(
		"death_reload_expected_reversals",
		prior_reversals + 1
	)
	Engine.set_meta(
		"death_reload_memory_sequence",
		death_memory_sequence
	)
	ui.call("_load_last_save_after_death")


func _run_legacy_import_smoke_test() -> void:
	await get_tree().process_frame
	_initialize_campaign_registry()
	if campaign_slot_registry == null:
		_fail_legacy_import_smoke_test(
			"Campaign registry was unavailable."
		)
		return
	for slot in campaign_slot_registry.enumerate_slots():
		if bool(slot.get("occupied", false)):
			campaign_slot_registry.delete_campaign(
				str(slot.get("slot_id", ""))
			)
	var marker_path := "%s/%s" % [
		campaign_slot_registry.root_path,
		CampaignLegacySaveImporterType.MARKER_FILE,
	]
	if FileAccess.file_exists(marker_path):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(marker_path)
		)
	active_campaign_slot_id = ""
	campaign_checkpoint_store = null
	campaign_chronicle_store = null
	campaign_kaelen_memory_store = null
	GlobalState.player_credits = 7654
	var prepared := _capture_prepared_runtime_state()
	if not bool(prepared.get("ok", false)) \
			or not SaveMigrator.write_current(SAVE_PATH, prepared["data"]):
		_fail_legacy_import_smoke_test(
			"Could not create the version-2 startup fixture."
		)
		return
	var original_text := FileAccess.get_file_as_string(SAVE_PATH)
	await _load_startup_save()
	var backup_path := str(
		last_legacy_import_result.get("backup_path", "")
	)
	var imported_slot := str(
		last_legacy_import_result.get("slot_id", "")
	)
	if not startup_save_loaded \
			or GlobalState.player_credits != 7654 \
			or imported_slot != "slot_01" \
			or active_campaign_slot_id != imported_slot \
			or campaign_checkpoint_store == null \
			or not campaign_checkpoint_store.is_valid() \
			or not FileAccess.file_exists(backup_path) \
			or FileAccess.get_file_as_string(backup_path) != original_text \
			or FileAccess.get_file_as_string(SAVE_PATH) != original_text:
		_fail_legacy_import_smoke_test(
			"Startup did not resume the version-2 save from a verified campaign."
		)
		return
	campaign_slot_registry.delete_campaign(imported_slot)
	if FileAccess.file_exists(marker_path):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(marker_path)
		)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(backup_path)
		)
	delete_savegame()
	print(
		"[LegacyImportSmokeTest] PASS: startup imported and resumed the version-2 save without changing its source."
	)
	get_tree().quit(0)


func _run_autopilot_smoke_test() -> void:
	await get_tree().process_frame
	if not _verify_autopilot_control_contract():
		return
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
	print("[AutopilotSmokeTest] PASS: preflight routes, passive selection, immediate override, placement, and legacy avoidance verified.")
	delete_savegame()
	get_tree().quit(0)


func _verify_autopilot_control_contract() -> bool:
	var original_transform := player.global_transform
	var right_press := InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.pressed = true
	right_press.position = Vector2(321.0, 246.0)
	player.call("_unhandled_input", right_press)
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED \
			or player.get("rmb_press_position") != right_press.position:
		_fail_autopilot_smoke_test(
			"Right-click captured or lost the pointer before drag intent."
		)
		return false
	var right_release := InputEventMouseButton.new()
	right_release.button_index = MOUSE_BUTTON_RIGHT
	right_release.pressed = false
	right_release.position = right_press.position
	player.call("_unhandled_input", right_release)
	var stations := get_tree().get_nodes_in_group("station").filter(
		func(node: Node) -> bool:
			return node is Node3D \
				and get_active_system_root().is_ancestor_of(node)
	)
	var celestials := get_tree().get_nodes_in_group("celestial").filter(
		func(node: Node) -> bool:
			return node is Node3D \
				and get_active_system_root().is_ancestor_of(node)
	)
	if stations.size() < 2 or celestials.is_empty():
		_fail_autopilot_smoke_test(
			"Autopilot control test could not find navigation fixtures."
		)
		return false
	for station in stations:
		if player.global_position.distance_to(
			(station as Node3D).global_position
		) >= player.WORLD_PICK_DISTANCE:
			_fail_autopilot_smoke_test(
				"Station right-click range is shorter than the authored layout."
			)
			return false
	var jumpgates := get_tree().get_nodes_in_group("jumpgate").filter(
		func(node: Node) -> bool:
			return node is Node3D \
				and get_active_system_root().is_ancestor_of(node)
	)
	for jumpgate in jumpgates:
		var selection_area := (jumpgate as Node3D).get_node_or_null(
			"SelectionArea"
		) as Area3D
		if selection_area == null or selection_area.collision_layer == 0:
			_fail_autopilot_smoke_test(
				"Jumpgate center has no non-physical selection volume."
			)
			return false
	player.call("cancel_autopilot", true)
	GlobalState.active_target = stations[0]
	if not bool(player.call("begin_target_navigation", "APPROACH")):
		_fail_autopilot_smoke_test(
			"Explicit target navigation command was rejected."
		)
		return false
	var commanded_target: Node3D = player.get("navigation_target")
	GlobalState.active_target = stations[1]
	if player.get("navigation_target") != commanded_target \
			or player.get("nav_mode") != "APPROACH":
		_fail_autopilot_smoke_test(
			"Selecting another object changed the active navigation command."
		)
		return false
	var move_point := player.global_position + Vector3(240.0, 30.0, -160.0)
	player.call("double_click_move", move_point)
	if player.get("nav_mode") != "MOVE_TO_POINT" \
			or player.get("navigation_target") != null \
			or (player.get("target_position") as Vector3).distance_to(
				move_point
			) > 0.1:
		_fail_autopilot_smoke_test(
			"Point-to-move did not immediately replace the prior autopilot route."
		)
		return false
	var ui := GlobalState.get_ui_manager()
	if ui != null and ui.has_method("show_context_menu"):
		GlobalState.active_target = stations[0]
		ui.call("show_context_menu", stations[0])
		if ui.get("context_highlight_target") != stations[0]:
			_fail_autopilot_smoke_test(
				"Context-menu target did not receive a temporary highlight."
			)
			return false
		ui.call("_close_context_menu")
	for station in stations:
		for celestial in celestials:
			var clearance := float(
				celestial.get_meta("navigation_clearance_radius", 0.0)
			)
			if clearance > 0.0 \
					and (station as Node3D).global_position.distance_to(
						(celestial as Node3D).global_position
					) <= clearance:
				_fail_autopilot_smoke_test(
					"Station '%s' remains inside '%s' navigation envelope."
					% [station.name, celestial.name]
				)
				return false
	var route_planet := celestials[0] as Node3D
	var route_clearance := float(
		route_planet.get_meta("navigation_clearance_radius", 0.0)
	)
	if route_clearance <= 0.0:
		_fail_autopilot_smoke_test(
			"Planet navigation envelope is missing."
		)
		return false
	player.global_position = route_planet.global_position \
		+ Vector3(route_clearance + 260.0, 0.0, 0.0)
	var opposite_point := route_planet.global_position \
		- Vector3(route_clearance + 260.0, 0.0, 0.0)
	player.call("double_click_move", opposite_point)
	player.call("_physics_process", 0.016)
	if (player.call("get_planned_route") as Array).size() <= 1 \
			or not bool(player.call("planned_route_is_clear")):
		player.global_transform = original_transform
		_fail_autopilot_smoke_test(
			"Planet-blocked point move did not receive a validated preflight route."
		)
		return false
	player.global_transform = original_transform
	player.call("cancel_autopilot", true)
	GlobalState.active_target = null
	return true


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


func _run_llm_validator_smoke_test() -> void:
	await get_tree().process_frame
	var ore_quest := {
		"title": "Contradictory Ore Briefing",
		"faction": "vanguard",
		"agent_name": "Captain Dask",
		"player_nickname": "Indy",
		"dialogue": (
			"Destroy an Aurelia raiding party and get those raiders "
			+ "off the shipping lanes."
		),
		"objective": {
			"type": "DELIVER_ORE",
			"amount_required": 20.0,
			"reward_credits": 165,
		},
		"choices": [],
	}
	LLMInterface.call("_validate_quest_data", ore_quest)
	var ore_objective: Dictionary = ore_quest["objective"]
	if ore_objective.get("type", "") != "DELIVER_ORE" \
			or int(ore_objective.get("amount_required", 0)) != 20 \
			or not bool(ore_quest.get("objective_dialogue_rewritten", false)) \
			or str(ore_quest.get("dialogue", "")).to_lower().find("ore") == -1 \
			or str(ore_quest.get("objective_summary", "")).find("20") == -1:
		_fail_llm_validator_smoke_test(
			"Contradictory kill prose was not repaired for an ore mission."
		)
		return

	var kill_quest := {
		"title": "Contradictory Kill Briefing",
		"faction": "zenith",
		"agent_name": "Broker Kaelen",
		"player_nickname": "Shiny",
		"dialogue": "Deliver 80 m3 of silicate cargo to my dock.",
		"objective": {
			"type": "KILL_SHIPS",
			"target_faction": "aurelia",
			"count_required": 3,
			"reward_credits": 240,
		},
		"choices": [],
	}
	LLMInterface.call("_validate_quest_data", kill_quest)
	var kill_objective: Dictionary = kill_quest["objective"]
	if kill_objective.get("type", "") != "KILL_SHIPS" \
			or int(kill_objective.get("count_required", 0)) != 3 \
			or not bool(kill_quest.get("objective_dialogue_rewritten", false)) \
			or str(kill_quest.get("dialogue", "")).to_lower().find("destroy") == -1 \
			or str(kill_quest.get("objective_summary", "")).find("AURELIA") == -1:
		_fail_llm_validator_smoke_test(
			"Contradictory ore prose was not repaired for a kill mission."
		)
		return

	print("[LLMValidatorSmokeTest] PASS: requested mission type stays authoritative.")
	delete_savegame()
	get_tree().quit(0)


func _run_station_combat_smoke_test() -> void:
	await get_tree().process_frame
	GlobalState.paused = false
	GlobalState.reset_for_restart()
	GlobalState.player = player
	QuestManager.active_quest = {}

	var station := GlobalState.get_primary_station()
	var npc_scene := load("res://scenes/npc_ship.tscn") as PackedScene
	if station == null or npc_scene == null:
		_fail_station_combat_smoke_test(
			"The main station or combat ship scene could not be loaded."
		)
		return

	# JSON restores whole numbers as floats. Starting at 2.0 reproduces the
	# loaded-campaign third-kill path that previously failed in record_kill().
	GlobalState.faction_kills["aurelia"] = 2.0
	GlobalState.reputations["aurelia"] = -50.0
	player.global_position = station.global_position + Vector3(
		135.0,
		0.0,
		0.0
	)
	player.velocity = Vector3.ZERO

	var target := npc_scene.instantiate()
	target.persistent_id = "entity.test.station_combat"
	target.faction = "aurelia"
	target.ship_role = "Gunner"
	target.name = "StationCombatTarget"
	get_active_system_root().add_child(target)
	target.global_position = station.global_position + Vector3(
		170.0,
		0.0,
		0.0
	)
	target.health = minf(float(target.health), 24.0)
	await get_tree().physics_frame

	var shots_fired := 0
	var frames_waited := 0
	while is_instance_valid(target) and frames_waited < 360:
		if frames_waited % 12 == 0:
			player.look_at(target.global_position, Vector3.UP)
			player.spawn_projectile(target)
			shots_fired += 1
		await get_tree().physics_frame
		frames_waited += 1

	if is_instance_valid(target) \
			or int(GlobalState.faction_kills.get("aurelia", 0)) != 3:
		_fail_station_combat_smoke_test(
			"Station-adjacent projectile combat did not finish cleanly."
		)
		return
	print(
		"[StationCombatSmokeTest] PASS: real projectiles destroyed a loaded-state ship beside the main station (%d shots)." %
		shots_fired
	)
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
			or str(fallback_result.get("campaign_name", "")).is_empty() \
			or not fallback_result.has("objective") \
			or not fallback_result.has("choices"):
		_fail_mission_smoke_test(
			"Local fallback did not produce a named playable campaign."
		)
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

	var recovery_offer := {
		"title": "Recovery Progress",
		"faction": "neutral",
		"agent_name": "Public Board",
		"dialogue": "Recover the missing data pack from Reaver wreckage.",
		"objective": {
			"type": "RECOVER_COMBAT_DROP",
			"target_faction": "reavers",
			"count_required": 2,
			"drop_chance": 1.0,
			"item_name": "data pack",
			"turn_in_location": "main station",
			"reward_credits": 80,
		},
		"choices": [],
		"public_board": true,
		"public_board_turn_in_line": "I processed the payout. Public board work, really?",
	}
	if not QuestManager.accept_quest(recovery_offer, accept_choice):
		_fail_mission_smoke_test("Valid recovery mission was rejected.")
		return
	GlobalState.ship_destroyed.emit("reavers")
	if not QuestManager.is_quest_completed() \
			or not bool(QuestManager.active_quest.get("ship_log_recovered", false)) \
			or str(QuestManager.active_quest.get("ship_log_entry", "")).is_empty() \
			or GlobalState.cargo_type != GlobalState.CargoType.EMPTY:
		_fail_mission_smoke_test("Recovery mission did not roll a ship-log drop without cargo.")
		return
	var credits_before_recovery := GlobalState.player_credits
	QuestManager.complete_quest()
	if QuestManager.is_quest_active() \
			or GlobalState.player_credits != credits_before_recovery + 80 \
			or GlobalState.cargo_type != GlobalState.CargoType.EMPTY:
		_fail_mission_smoke_test("Recovery mission did not pay and close without cargo.")
		return

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

	var timed_pickup_offer := pickup_offer.duplicate(true)
	timed_pickup_offer["title"] = "Timed Pickup Expiration"
	timed_pickup_offer["timing"] = {
		"timed": true,
		"urgent": true,
		"duration_minutes": 1,
		"expiration_policy": "expire",
		"urgent_reward_multiplier": 1.5,
	}
	if not QuestManager.accept_quest(timed_pickup_offer, {
		"text": "Accepted.",
		"consequence": {},
	}):
		_fail_mission_smoke_test("Valid timed pickup mission was rejected.")
		return
	QuestManager.active_quest["picked_up"] = true
	GlobalState.accept_special("Plasma Coupler", "Test", "Kova", "Grease Monkeys")
	CampaignClock.advance_minutes(1)
	if QuestManager.is_quest_active() \
			or GlobalState.cargo_type != GlobalState.CargoType.EMPTY:
		_fail_mission_smoke_test("Timed mission expiration did not clear active state and matching special cargo.")
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


func _run_multi_mission_smoke_test() -> void:
	await get_tree().process_frame
	GlobalState.paused = false
	GlobalState.reset_for_restart()
	GlobalState.player = player
	QuestManager.active_quest = {}
	GlobalState.player_credits = 200
	GlobalState.reputations["zenith"] = 50.0
	GlobalState.reputations["aurelia"] = 50.0
	GlobalState.reputations["reavers"] = 50.0

	var accept_choice := {
		"text": "Accepted.",
		"consequence": {
			"credits_immediate": 0,
			"reputation_change": {},
			"reward_credits_multiplier": 1.0,
		},
	}

	var agent_kill_offer := {
		"title": "Eliminate Hostiles",
		"faction": "zenith",
		"agent_name": "Director Voss",
		"dialogue": "Destroy the raiders.",
		"objective": {
			"type": "KILL_SHIPS",
			"count_required": 2,
			"target_faction": "reavers",
			"reward_credits": 150,
		},
		"choices": [],
	}
	if not QuestManager.accept_quest(agent_kill_offer, accept_choice):
		_fail_multi_mission_smoke_test("Agent kill mission was rejected.")
		return
	if not QuestManager.is_lane_occupied("AGENT"):
		_fail_multi_mission_smoke_test("AGENT lane not occupied after accept.")
		return

	var board_ore_offer := {
		"title": "Ore Hauling Job",
		"faction": "aurelia",
		"agent_name": "Board Poster",
		"dialogue": "Deliver 20 ore.",
		"objective": {
			"type": "DELIVER_ORE",
			"amount_required": 20,
			"reward_credits": 100,
		},
		"choices": [],
		"public_board": true,
		"public_board_template_id": "DELIVER_ORE_PUBLIC",
		"public_board_turn_in_line": "Ore logged. Public board work, huh? I can smell the standards.",
		"public_board_text_is_fallback": true,
	}
	if not QuestManager.accept_quest(board_ore_offer, accept_choice):
		_fail_multi_mission_smoke_test("Board ore mission was rejected.")
		return
	if not QuestManager.is_lane_occupied("BOARD"):
		_fail_multi_mission_smoke_test("BOARD lane not occupied after accept.")
		return
	if QuestManager.get_mission_collection().size() != 2:
		_fail_multi_mission_smoke_test("Collection should have 2 missions, got %d." % QuestManager.get_mission_collection().size())
		return

	GlobalState.ship_destroyed.emit("reavers")
	GlobalState.ship_destroyed.emit("reavers")

	var col := QuestManager.get_mission_collection()
	var all_missions := col.get_all_active()
	var agent_m: Object = null
	for m in all_missions:
		if m.data.get("objective_type", "") == "KILL_SHIPS":
			agent_m = m
			break
	if agent_m == null or int(agent_m.data.get("current_count", 0)) != 2:
		_fail_multi_mission_smoke_test("Kill mission did not track 2 kills.")
		return

	col.focus(agent_m.runtime_id)
	if not QuestManager.is_quest_completed():
		_fail_multi_mission_smoke_test("Kill mission should be completed at 2/2.")
		return

	var credits_before := GlobalState.player_credits
	QuestManager.complete_quest()
	if QuestManager.is_lane_occupied("AGENT"):
		_fail_multi_mission_smoke_test("AGENT lane should be free after completion.")
		return
	if GlobalState.player_credits != credits_before + 150:
		_fail_multi_mission_smoke_test("Kill mission payout was wrong.")
		return

	if not QuestManager.is_lane_occupied("BOARD"):
		_fail_multi_mission_smoke_test("BOARD lane should still be occupied.")
		return
	if QuestManager.get_mission_collection().size() != 1:
		_fail_multi_mission_smoke_test("Collection should have 1 mission after agent complete.")
		return

	var remaining := QuestManager.get_mission_collection().get_all_active()
	if remaining.size() != 1:
		_fail_multi_mission_smoke_test("Should have exactly 1 remaining mission.")
		return
	QuestManager.get_mission_collection().focus(remaining[0].runtime_id)
	var aurelia_before := float(GlobalState.reputations["aurelia"])
	QuestManager.abandon_quest()
	if QuestManager.is_lane_occupied("BOARD"):
		_fail_multi_mission_smoke_test("BOARD lane should be free after abandon.")
		return
	if not is_equal_approx(float(GlobalState.reputations["aurelia"]), aurelia_before - 3.0):
		_fail_multi_mission_smoke_test("Abandon rep penalty was not applied.")
		return

	GlobalState.reputations["reavers"] = 50.0
	GlobalState.reputations["neutral"] = 50.0
	var comms_offer := {
		"title": "Bounty: Reaver Scouts",
		"faction": "neutral",
		"agent_name": "Anonymous",
		"dialogue": "Take out three reaver scouts.",
		"objective": {
			"type": "TARGET_WITH_COMMS_REVERSAL",
			"count_required": 3,
			"target_faction": "reavers",
			"reward_credits": 200,
			"bribe_amount": 80,
			"comms_reversal_line": "Wait — we have intel you need to hear.",
		},
		"choices": [],
		"public_board": true,
		"public_board_template_id": "TARGET_WITH_COMMS_REVERSAL",
		"public_board_turn_in_line": "Bounty confirmed. Public board, really?",
		"public_board_text_is_fallback": true,
	}
	if not QuestManager.accept_quest(comms_offer, accept_choice):
		_fail_multi_mission_smoke_test("Comms reversal mission was rejected.")
		return

	var comms_m = QuestManager.get_mission_collection().get_focused()
	var ui := GlobalState.get_ui_manager()
	if ui and QuestManager.comms_reversal_triggered.is_connected(ui._on_comms_reversal_triggered):
		QuestManager.comms_reversal_triggered.disconnect(ui._on_comms_reversal_triggered)

	GlobalState.ship_destroyed.emit("reavers")
	GlobalState.ship_destroyed.emit("reavers")
	if not bool(comms_m.data.get("comms_triggered", false)):
		_fail_multi_mission_smoke_test("Comms should trigger at kill 2 of 3.")
		return

	GlobalState.ship_destroyed.emit("reavers")
	if int(comms_m.data.get("current_count", 0)) != 2:
		_fail_multi_mission_smoke_test("Kills should be blocked during unresolved comms.")
		return

	var reavers_before := float(GlobalState.reputations.get("reavers", 50.0))
	var neutral_before := float(GlobalState.reputations.get("neutral", 50.0))
	var credits_before_bribe := GlobalState.player_credits
	QuestManager.resolve_comms_branch("accept_bribe")
	if QuestManager.is_lane_occupied("BOARD"):
		_fail_multi_mission_smoke_test("Bribe branch should have cleared the BOARD lane.")
		return
	if GlobalState.player_credits != credits_before_bribe + 80:
		_fail_multi_mission_smoke_test("Bribe payout was wrong: expected +80.")
		return
	if not is_equal_approx(float(GlobalState.reputations["neutral"]), neutral_before - 3.0):
		_fail_multi_mission_smoke_test("Issuing faction rep should drop by 3 on bribe.")
		return
	if not is_equal_approx(float(GlobalState.reputations["reavers"]), reavers_before + 2.0):
		_fail_multi_mission_smoke_test("Target faction rep should rise by 2 on bribe.")
		return

	print("[MultiMissionSmokeTest] PASS: two-lane coexistence, complete/abandon, comms reversal with bribe branch verified.")
	delete_savegame()
	get_tree().quit(0)


func _fail_multi_mission_smoke_test(message: String) -> void:
	push_error("[MultiMissionSmokeTest] FAIL: " + message)
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

	ui.current_station = main_station
	ui.current_submenu = ui.DockSubmenu.SERVICES
	ui.call("_render_dock_submenu")
	if not ui.public_board_btn.visible:
		_fail_services_smoke_test("Public contract board button was not visible at the main station.")
		return
	ui.call("_on_public_board_pressed")
	if not ui.public_board_panel.visible \
			or ui.public_board_current_offers.size() < 3:
		_fail_services_smoke_test("Public contract board did not render code-owned offers.")
		return
	ui.call("_on_public_board_offer_accept", 0)
	if not QuestManager.is_quest_active() \
			or not bool(QuestManager.active_quest.get("is_timed", false)) \
			or not bool(QuestManager.active_quest.get("is_urgent", false)) \
			or QuestManager.active_quest_payout() <= int(
				QuestManager.active_quest.get("base_reward_credits", 0)
	):
		_fail_services_smoke_test("Public board urgent posting did not create a timed active mission.")
		return
	if ui.agent_portrait_column.visible:
		_fail_services_smoke_test("Public board acceptance showed Kaelen's portrait.")
		return
	QuestManager.active_quest = {}
	if not bool(ui.public_board_current_offers[2].get("enabled", false)):
		_fail_services_smoke_test("Recovery public-board posting was still disabled.")
		return
	ui.call("_on_public_board_offer_accept", 2)
	if not QuestManager.is_quest_active() \
			or QuestManager.active_quest.get("objective_type", "") \
				!= "RECOVER_COMBAT_DROP" \
			or bool(QuestManager.active_quest.get("ship_log_recovered", false)):
		_fail_services_smoke_test("Recovery public-board posting did not create a valid active mission.")
		return
	QuestManager.active_quest["drop_chance"] = 1.0
	ui.call("_update_quest_tracker")
	if ui.quest_tracker_turn_in_btn.visible:
		_fail_services_smoke_test("Recovery board turn-in button appeared before recovery was complete.")
		return
	var recovery_payout := QuestManager.active_quest_payout()
	var recovery_required := int(
		QuestManager.active_quest.get("count_required", 0)
	)
	for _i in range(recovery_required):
		GlobalState.ship_destroyed.emit(
			str(QuestManager.active_quest.get("target_faction", "reavers"))
		)
	if not QuestManager.is_quest_completed() \
			or not bool(QuestManager.active_quest.get("ship_log_recovered", false)):
		_fail_services_smoke_test("Recovery public-board posting did not reach random-drop ship-log turn-in state.")
		return
	ui.current_station = main_station
	ui.call("_update_quest_tracker")
	if not ui.quest_tracker_turn_in_btn.visible \
			or ui.quest_tracker_turn_in_btn.disabled \
			or ui.quest_tracker_turn_in_btn.text != "Turn In To Local Agent":
		_fail_services_smoke_test("Ready board job did not expose a local-agent turn-in button.")
		return
	var credits_before_board_turn_in := GlobalState.player_credits
	ui.call("_on_quest_tracker_turn_in_pressed")
	if QuestManager.is_quest_active() \
			or GlobalState.player_credits != credits_before_board_turn_in + recovery_payout \
			or not ui.agent_panel.visible \
			or not _services_smoke_has_board_turn_in_disgust(
				str(ui.agent_dialogue_label.text)
			):
		_fail_services_smoke_test("Tracker turn-in button did not route board completion through Kaelen.")
		return
	ui.public_board_panel.visible = false
	ui.agent_panel.visible = false

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
	if str(flavor.get("line", "")).contains("Shiny") \
			and not GlobalState.is_kaelen_voice(
				str(flavor.get("voice_profile_id", ""))
			):
		_fail_services_smoke_test("Non-Kaelen gossip used Kaelen's Shiny nickname.")
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
	GlobalState.cargo = 0.0
	GlobalState.cargo_type = GlobalState.CargoType.EMPTY
	GlobalState.cargo_special = {}
	ui.current_station = iron_reach
	ui.call("_render_dock_submenu")
	if ui.ask_for_part_btn.visible:
		_fail_services_smoke_test("Wrong outpost exposed the pickup handoff button.")
		return
	ui.call("_on_ask_for_part_pressed")
	if bool(QuestManager.active_quest["picked_up"]) \
			or GlobalState.cargo_type == GlobalState.CargoType.SPECIAL:
		_fail_services_smoke_test("Pickup succeeded at the wrong outpost.")
		return
	ui.current_station = kova
	ui.call("_render_dock_submenu")
	if not ui.ask_for_part_btn.visible \
			or not ui.ask_for_part_btn.text.contains("Ask Cassen Vane for Sensor Calibration Kit"):
		_fail_services_smoke_test("Assigned outpost did not expose the pickup handoff button.")
		return
	ui.call("_on_ask_for_part_pressed")
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


func _services_smoke_has_board_turn_in_disgust(line: String) -> bool:
	var lower_line := line.to_lower()
	return lower_line.contains("public") \
			and (
				lower_line.contains("slumming")
				or lower_line.contains("grime")
				or lower_line.contains("stain")
			)


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

func _fail_station_combat_smoke_test(message: String) -> void:
	push_error("[StationCombatSmokeTest] FAIL: " + message)
	get_tree().quit(1)

func _fail_llm_validator_smoke_test(message: String) -> void:
	push_error("[LLMValidatorSmokeTest] FAIL: " + message)
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


func _fail_death_reload_smoke_test(message: String) -> void:
	if Engine.has_meta("death_reload_smoke_phase"):
		Engine.remove_meta("death_reload_smoke_phase")
	if Engine.has_meta("death_reload_expected_reversals"):
		Engine.remove_meta("death_reload_expected_reversals")
	if Engine.has_meta("death_reload_memory_sequence"):
		Engine.remove_meta("death_reload_memory_sequence")
	if Engine.has_meta("death_reload_expected_campaign_count"):
		Engine.remove_meta("death_reload_expected_campaign_count")
	if Engine.has_meta("death_reload_expected_replacement_slot"):
		Engine.remove_meta("death_reload_expected_replacement_slot")
	push_error("[DeathReloadSmokeTest] FAIL: " + message)
	get_tree().quit(1)


func _fail_legacy_import_smoke_test(message: String) -> void:
	push_error("[LegacyImportSmokeTest] FAIL: " + message)
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
	var safe_source_time := int(
		safe_source.get("state", {})
			.get("global", {})
			.get("campaign_time", {})
			.get("total_minutes", -1)
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
	CampaignClock.advance_minutes(123)
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
	CampaignClock.reset_for_restart()
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
	if CampaignClock.total_minutes != safe_source_time + 123:
		_fail_jump_smoke_test("Campaign time did not restore from save.")
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
	if int(
		manual_state.get("state", {})
			.get("global", {})
			.get("campaign_time", {})
			.get("total_minutes", -1)
	) != safe_source_time:
		_fail_jump_smoke_test(
			"In-flight manual save captured live campaign time instead of safe state."
		)
		return false
	GlobalState.player_credits = 2
	player.global_position += Vector3(500.0, 0.0, 500.0)
	await _load_system_without_transition("test_system")
	if GlobalState.current_system_id != "test_system":
		_fail_jump_smoke_test(
			"Save test could not move away from the checkpoint system."
		)
		return false
	if not await load_manual_checkpoint(0):
		_fail_jump_smoke_test("Manual checkpoint could not be loaded.")
		return false
	if GlobalState.current_system_id != "start_system":
		_fail_jump_smoke_test(
			"Manual checkpoint did not restore its saved system."
		)
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


func _run_public_board_smoke_test() -> void:
	await get_tree().process_frame
	GlobalState.paused = false
	GlobalState.reset_for_restart()
	GlobalState.player = player
	QuestManager.active_quest = {}

	var ui := GlobalState.get_ui_manager()
	var main_station := GlobalState.get_primary_station()
	if not ui or not main_station:
		_fail_public_board_smoke_test("UIManager or main station was unavailable.")
		return

	ui.current_station = main_station
	ui.current_submenu = ui.DockSubmenu.SERVICES
	ui.call("_render_dock_submenu")
	if not ui.public_board_btn.visible:
		_fail_public_board_smoke_test("Public board button was not visible.")
		return
	ui.call("_on_public_board_pressed")
	if ui.public_board_current_offers.size() < 3:
		_fail_public_board_smoke_test("Public board did not produce at least 3 offers.")
		return

	var urgent_index := -1
	for i in range(ui.public_board_current_offers.size()):
		var quest_data: Dictionary = ui.public_board_current_offers[i].get("quest_data", {})
		var timing: Dictionary = quest_data.get("timing", {})
		if bool(timing.get("urgent", false)):
			urgent_index = i
			break
	if urgent_index < 0:
		_fail_public_board_smoke_test("No urgent posting was found on the public board.")
		return

	var urgent_offer: Dictionary = ui.public_board_current_offers[urgent_index]
	var urgent_quest_data: Dictionary = urgent_offer.get("quest_data", {})
	var urgent_timing: Dictionary = urgent_quest_data.get("timing", {})
	var duration := int(urgent_timing.get("duration_minutes", 0))
	if duration <= 0:
		_fail_public_board_smoke_test("Urgent posting had no positive duration.")
		return

	var time_before_accept := CampaignClock.total_minutes
	ui.call("_on_public_board_offer_accept", urgent_index)
	if not QuestManager.is_quest_active():
		_fail_public_board_smoke_test("Accepting urgent posting did not create an active mission.")
		return
	if not bool(QuestManager.active_quest.get("is_timed", false)) \
			or not bool(QuestManager.active_quest.get("is_urgent", false)):
		_fail_public_board_smoke_test("Accepted mission is not timed or not urgent.")
		return

	var deadline := int(QuestManager.active_quest.get("deadline_time_minutes", 0))
	var remaining := QuestManager.get_active_quest_remaining_minutes()
	if remaining <= 0 or remaining > duration:
		_fail_public_board_smoke_test(
			"Remaining time was out of expected range (got %d, duration %d)." % [
				remaining, duration
			]
		)
		return

	var base_reward := int(QuestManager.active_quest.get("base_reward_credits", 0))
	var urgent_payout := QuestManager.active_quest_payout()
	if urgent_payout <= base_reward:
		_fail_public_board_smoke_test(
			"Urgent payout %d was not higher than base %d." % [
				urgent_payout, base_reward
			]
		)
		return

	CampaignClock.advance_minutes(1)
	var remaining_after := QuestManager.get_active_quest_remaining_minutes()
	if remaining_after >= remaining:
		_fail_public_board_smoke_test("Campaign time advance did not reduce remaining time.")
		return

	if QuestManager.active_quest.get("objective_type", "") == "DELIVER_ORE":
		var required := float(QuestManager.active_quest.get("amount_required", 0.0))
		GlobalState.add_ore(required)
		if not QuestManager.is_quest_completed():
			_fail_public_board_smoke_test("Ore delivery did not complete the urgent mission.")
			return
	elif QuestManager.active_quest.get("objective_type", "") == "KILL_SHIPS":
		var count := int(QuestManager.active_quest.get("count_required", 0))
		for _i in range(count):
			GlobalState.ship_destroyed.emit(
				str(QuestManager.active_quest.get("target_faction", "reavers"))
			)
		if not QuestManager.is_quest_completed():
			_fail_public_board_smoke_test("Kill progress did not complete the urgent mission.")
			return

	var credits_before := GlobalState.player_credits
	QuestManager.complete_quest()
	if QuestManager.is_quest_active():
		_fail_public_board_smoke_test("Urgent mission was not cleared after completion.")
		return
	if GlobalState.player_credits != credits_before + urgent_payout:
		_fail_public_board_smoke_test(
			"Urgent completion paid %d instead of expected %d." % [
				GlobalState.player_credits - credits_before, urgent_payout
			]
		)
		return

	QuestManager.active_quest = {}
	ui.call("_on_public_board_pressed")
	ui.call("_on_public_board_offer_accept", urgent_index)
	if not QuestManager.is_quest_active() \
			or not bool(QuestManager.active_quest.get("is_timed", false)):
		_fail_public_board_smoke_test("Second urgent accept did not create a timed mission.")
		return

	var expiration_deadline := int(
		QuestManager.active_quest.get("deadline_time_minutes", 0)
	)
	var time_to_expire := expiration_deadline - CampaignClock.total_minutes
	if time_to_expire <= 0:
		_fail_public_board_smoke_test("Already past deadline before expiration test.")
		return
	CampaignClock.advance_minutes(time_to_expire)
	if QuestManager.is_quest_active():
		_fail_public_board_smoke_test("Timed mission did not expire when deadline was reached.")
		return

	print("[PublicBoardSmokeTest] PASS: urgent accept, countdown, urgent payout, and deterministic expiration verified.")
	delete_savegame()
	get_tree().quit(0)


func _fail_public_board_smoke_test(message: String) -> void:
	push_error("[PublicBoardSmokeTest] FAIL: " + message)
	delete_savegame()
	get_tree().quit(1)
