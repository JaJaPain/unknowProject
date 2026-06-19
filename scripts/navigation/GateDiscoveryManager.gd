class_name GateDiscoveryManager
extends Node

signal gate_state_changed(gate_id: String, old_state: String, new_state: String)
signal gate_rumor_received(gate_id: String, narrative: String)

const GateDiscoveryActionType := preload(
	"res://scripts/navigation/GateDiscoveryAction.gd"
)
const GeneratedGateBuilderType := preload(
	"res://scripts/navigation/GeneratedGateBuilder.gd"
)

var _last_kaelen_offer_time: int = -1
const KAELEN_COOLDOWN_MINUTES := 60
const KAELEN_FIRST_OFFER_DELAY_MINUTES := 15


func advance_gate_state(
	gate_id: String,
	action: GateDiscoveryAction
) -> Dictionary:
	var store := _get_store()
	if store == null:
		return {"ok": false, "error": "No checkpoint store available."}

	var current_state := store.get_gate_state(gate_id)

	if not action.can_execute(current_state):
		return {
			"ok": false,
			"error": "Cannot perform %s on a gate in '%s' state." % [
				GateDiscoveryAction.ActionType.keys()[action.action_type],
				current_state,
			],
		}

	if not action.can_player_afford():
		return {"ok": false, "error": "Not enough resources."}

	if not action.meets_prerequisites():
		return {
			"ok": false,
			"error": "Prerequisites not met: %s" % action.get_prerequisite_text(),
		}

	if action.credit_cost > 0:
		GlobalState.player_credits -= action.credit_cost
		GlobalState.credits_changed.emit(GlobalState.player_credits)
	if action.ore_cost > 0:
		GlobalState.cargo = max(0, int(GlobalState.cargo) - action.ore_cost)
		GlobalState.cargo_changed.emit()

	var target_state := action.get_target_state()
	if not store.set_gate_knowledge(gate_id, target_state):
		return {"ok": false, "error": "Failed to update gate knowledge."}

	gate_state_changed.emit(gate_id, current_state, target_state)
	return {"ok": true, "old_state": current_state, "new_state": target_state}


func apply_rumor(gate_id: String, narrative: String = "") -> Dictionary:
	var store := _get_store()
	if store == null:
		return {"ok": false, "error": "No checkpoint store available."}

	var current_state := store.get_gate_state(gate_id)
	if current_state != "unknown":
		return {"ok": false, "error": "Gate already discovered."}

	if not store.set_gate_knowledge(gate_id, "rumored"):
		return {"ok": false, "error": "Failed to set gate as rumored."}

	_ensure_destination_generated(gate_id)
	gate_state_changed.emit(gate_id, "unknown", "rumored")
	gate_rumor_received.emit(gate_id, narrative)
	return {"ok": true, "gate_id": gate_id, "narrative": narrative}


func kaelen_reveal(gate_id: String, cost: int) -> Dictionary:
	var store := _get_store()
	if store == null:
		return {"ok": false, "error": "No checkpoint store available."}

	var current_state := store.get_gate_state(gate_id)
	if current_state == "known" or current_state == "unknown":
		return {"ok": false, "error": "Gate cannot be revealed by Kaelen."}

	if GlobalState.player_credits < cost:
		return {"ok": false, "error": "Not enough credits."}

	GlobalState.player_credits -= cost
	GlobalState.credits_changed.emit(GlobalState.player_credits)

	if not store.set_gate_knowledge(gate_id, "known"):
		return {"ok": false, "error": "Failed to update gate knowledge."}

	_last_kaelen_offer_time = CampaignClock.total_minutes
	gate_state_changed.emit(gate_id, current_state, "known")
	return {"ok": true, "old_state": current_state, "cost": cost}


func is_kaelen_gate_eligible() -> bool:
	if not _is_kaelen_offer_ready():
		return false
	return _has_revealable_gates()


func seed_kaelen_gate_rumor_if_ready() -> Dictionary:
	if not _is_kaelen_offer_ready():
		return {"ok": false, "error": "Kaelen gate offer is not ready."}
	if _has_revealable_gates():
		return {"ok": true, "already_revealable": true}
	var gate_ids := _unknown_gates_in_current_system()
	if gate_ids.is_empty():
		return {"ok": false, "error": "No unknown gates in the current system."}
	var gate_id: String = gate_ids[0]
	return apply_rumor(
		gate_id,
		"Kaelen's contacts flagged an uncharted hypergate route."
	)


func get_revealable_gates() -> Array[String]:
	var store := _get_store()
	if store == null:
		return []
	var output: Array[String] = []
	var all_states := store.get_all_gate_states()
	for gate_id in all_states:
		var state: String = all_states[gate_id]
		if state in ["rumored", "hidden", "blocked", "damaged"]:
			output.append(gate_id)
	return output


func get_kaelen_reveal_cost(gate_id: String) -> int:
	var store := _get_store()
	if store == null:
		return 75
	var state := store.get_gate_state(gate_id)
	match state:
		"rumored": return 75
		"hidden": return 60
		"blocked": return 50
		"damaged": return 40
	return 75


func get_gate_state(gate_id: String) -> String:
	var store := _get_store()
	if store == null:
		return "unknown"
	return store.get_gate_state(gate_id)


func ensure_destinations_for_system(system_id: String) -> void:
	var game_root := get_tree().current_scene if get_tree() else null
	if not game_root or not "system_registry" in game_root:
		return
	var registry: SystemRegistry = game_root.system_registry
	var system_def := registry.get_system(system_id)
	if system_def == null:
		return
	for gate_def: GateDefinition in system_def.gates:
		_ensure_destination_generated(str(gate_def.id))
		_sync_active_gate_target(gate_def)


func _has_revealable_gates() -> bool:
	return not get_revealable_gates().is_empty()


func _is_kaelen_offer_ready() -> bool:
	var start_minutes := CampaignClock.START_HOUR * CampaignClock.MINUTES_PER_HOUR
	if CampaignClock.total_minutes < start_minutes + KAELEN_FIRST_OFFER_DELAY_MINUTES:
		return false
	if QuestManager.get_completed_count() < 3:
		return false
	if _last_kaelen_offer_time >= 0 \
			and (CampaignClock.total_minutes - _last_kaelen_offer_time) < KAELEN_COOLDOWN_MINUTES:
		return false
	return true


func _unknown_gates_in_current_system() -> Array[String]:
	var game_root := _get_game_root()
	if game_root == null or not "system_registry" in game_root:
		return []
	var registry: SystemRegistry = game_root.system_registry
	var system_id := str(registry.resolve_system_id(GlobalState.current_system_id))
	var system_def := registry.get_system(system_id)
	if system_def == null:
		return []
	var output: Array[String] = []
	for gate_def: GateDefinition in system_def.gates:
		var gate_id := str(gate_def.id)
		if get_gate_state(gate_id) == "unknown":
			output.append(gate_id)
	return output


func _ensure_destination_generated(gate_id: String) -> void:
	var game_root := get_tree().current_scene if get_tree() else null
	if not game_root or not "system_registry" in game_root:
		return
	var registry: SystemRegistry = game_root.system_registry
	var gate_def := registry.get_gate(gate_id)
	if gate_def == null:
		return
	var dest_sys_id := str(gate_def.destination_system_id)
	if registry.has_system(dest_sys_id):
		return

	var names := CampaignSystemNames.load_or_create()
	var sys_name := names.next_name()
	var seed_val := dest_sys_id.hash()
	var frontier_factions: Array = []
	if game_root.has_method("reveal_generated_factions_for_system"):
		var revealed := game_root.reveal_generated_factions_for_system(dest_sys_id, 2)
		if bool(revealed.get("ok", false)) \
				and game_root.has_method("generated_factions_for_ids"):
			frontier_factions = game_root.generated_factions_for_ids(
				revealed.get("revealed", [])
			)
	if frontier_factions.is_empty() and game_root.has_method("revealed_generated_factions"):
		frontier_factions = game_root.revealed_generated_factions()
	var config := SystemConfig.from_seed(
		sys_name,
		dest_sys_id,
		seed_val,
		frontier_factions
	)

	var return_gate_id := str(gate_def.destination_gate_id)
	var return_gate_legacy := return_gate_id.replace(".", "_")
	var source_sys_id := str(gate_def.system_id)

	var gate_defs: Array[Dictionary] = [{
		"id": return_gate_id,
		"legacy_id": return_gate_legacy,
		"display_name": "%s Return Gate" % sys_name,
		"destination_system_id": source_sys_id,
		"destination_gate_id": gate_id,
		"initial_state": "known",
		"discovery_action": "",
		"discovery_cost": {},
		"discovery_prerequisites": [],
	}]
	gate_defs.append_array(
		GeneratedGateBuilderType.build_outbound_gate_defs(
			dest_sys_id,
			sys_name,
			config
		)
	)

	var sys_data := {
		"id": dest_sys_id,
		"legacy_id": config.legacy_id,
		"display_name": sys_name,
		"station_ids": [],
		"faction_ids": _config_faction_ids(config),
	}

	registry.set_generated_config(dest_sys_id, config)
	registry.set_generated_config(config.legacy_id, config)
	var result := registry.register_generated_system(sys_data, gate_defs)
	if not result.is_valid():
		push_warning("[GateDiscovery] Failed to register generated system: %s" % result.summary())
		return
	var store := _get_store()
	if store != null:
		store.set_gate_knowledge(return_gate_id, "known")


func _config_faction_ids(config: SystemConfig) -> Array[String]:
	var ids: Array[String] = []
	for faction_name: String in config.faction_weights.keys():
		ids.append(config.canonical_faction_id(faction_name))
	return ids


func _sync_active_gate_target(gate_def: GateDefinition) -> void:
	var game_root := get_tree().current_scene if get_tree() else null
	if not game_root or not "system_registry" in game_root:
		return
	if not game_root.has_method("get_active_system_root"):
		return
	var active_root: Node = game_root.get_active_system_root()
	if active_root == null:
		return
	var active_gate := _find_active_gate(active_root, gate_def)
	if active_gate == null:
		return
	var registry: SystemRegistry = game_root.system_registry
	var destination := registry.get_system(gate_def.destination_system_id)
	active_gate.set("destination_system_id", str(gate_def.destination_system_id))
	active_gate.set("destination_gate_id", str(gate_def.destination_gate_id))
	active_gate.set(
		"destination_display_name",
		destination.display_name if destination else "ROUTE PREPARING"
	)


func _find_active_gate(
	active_root: Node,
	gate_def: GateDefinition
) -> Node:
	for node in active_root.get_tree().get_nodes_in_group("jumpgate"):
		if not active_root.is_ancestor_of(node):
			continue
		if node.get("world_id") == str(gate_def.id) \
				or node.get("gate_id") == gate_def.legacy_id:
			return node
	return null


func _get_store() -> CampaignCheckpointStore:
	var game_root := _get_game_root()
	if game_root and game_root.has_method("get_checkpoint_store"):
		return game_root.get_checkpoint_store()
	if game_root and "campaign_checkpoint_store" in game_root:
		return game_root.campaign_checkpoint_store
	return null


func _get_game_root() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	if tree.current_scene and "system_registry" in tree.current_scene:
		return tree.current_scene
	for child in tree.root.get_children():
		if child and "system_registry" in child:
			return child
	return null
