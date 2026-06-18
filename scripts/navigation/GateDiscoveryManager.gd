class_name GateDiscoveryManager
extends Node

signal gate_state_changed(gate_id: String, old_state: String, new_state: String)
signal gate_rumor_received(gate_id: String, narrative: String)

const GateDiscoveryActionType := preload(
	"res://scripts/navigation/GateDiscoveryAction.gd"
)

var _last_kaelen_offer_time: int = -1
const KAELEN_COOLDOWN_MINUTES := 60


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
		GlobalState.credits_changed.emit()
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
	GlobalState.credits_changed.emit()

	if not store.set_gate_knowledge(gate_id, "known"):
		return {"ok": false, "error": "Failed to update gate knowledge."}

	_last_kaelen_offer_time = CampaignClock.total_minutes
	gate_state_changed.emit(gate_id, current_state, "known")
	return {"ok": true, "old_state": current_state, "cost": cost}


func is_kaelen_gate_eligible() -> bool:
	if CampaignClock.total_minutes < 120:
		return false
	if QuestManager.get_completed_count() < 3:
		return false
	if _last_kaelen_offer_time >= 0 \
			and (CampaignClock.total_minutes - _last_kaelen_offer_time) < KAELEN_COOLDOWN_MINUTES:
		return false
	return _has_revealable_gates()


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


func _has_revealable_gates() -> bool:
	return not get_revealable_gates().is_empty()


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
	var config := SystemConfig.from_seed(sys_name, dest_sys_id, seed_val)

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

	var sys_data := {
		"id": dest_sys_id,
		"legacy_id": config.legacy_id,
		"display_name": sys_name,
		"station_ids": [],
		"faction_ids": [],
	}

	registry.set_generated_config(dest_sys_id, config)
	registry.set_generated_config(config.legacy_id, config)
	var result := registry.register_generated_system(sys_data, gate_defs)
	if not result.is_valid():
		push_warning("[GateDiscovery] Failed to register generated system: %s" % result.summary())


func _get_store() -> CampaignCheckpointStore:
	var game_root := get_tree().current_scene if get_tree() else null
	if game_root and game_root.has_method("get_checkpoint_store"):
		return game_root.get_checkpoint_store()
	if game_root and "campaign_checkpoint_store" in game_root:
		return game_root.campaign_checkpoint_store
	return null
