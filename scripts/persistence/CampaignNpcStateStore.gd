class_name CampaignNpcStateStore
extends RefCounted

const DomainIdType := preload("res://scripts/domain/DomainId.gd")
const DomainJsonType := preload("res://scripts/domain/DomainJson.gd")
const TransactionStoreType := preload(
	"res://scripts/persistence/CampaignTransactionStore.gd"
)
const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

const DOCUMENT_VERSION := 1
const STATES_PATH := "npc_states.json"
const MAX_MEMORY_EVENT_IDS := 24
const MAX_LINE_FINGERPRINTS := 32
const RELATIONSHIP_FIELDS := [
	"trust",
	"respect",
	"warmth",
	"debt",
]

var campaign_path: String
var campaign: Dictionary = {}
var data: Dictionary = {}
var validation := ValidationResultType.new()


static func open(path: String) -> RefCounted:
	var store = load("res://scripts/persistence/CampaignNpcStateStore.gd").new()
	store.campaign_path = path.trim_suffix("/")
	store._load_or_create()
	return store


func is_valid() -> bool:
	return validation.is_valid()


func state_for(npc_id: String) -> Dictionary:
	var states: Dictionary = data.get("npc_states", {}) \
		if data.get("npc_states", {}) is Dictionary else {}
	if states.get(npc_id, {}) is Dictionary:
		return (states[npc_id] as Dictionary).duplicate(true)
	return _default_npc_state(npc_id)


func ensure_state(npc_id: String) -> Dictionary:
	if not is_valid():
		return _failure("NPC state store is invalid.")
	if not DomainIdType.is_valid(npc_id, "npc"):
		return _failure("NPC ID is invalid.")
	if data.get("npc_states", {}) is Dictionary \
			and (data["npc_states"] as Dictionary).has(npc_id):
		return {"ok": true, "created": false, "state": state_for(npc_id)}
	return _upsert_state(npc_id, _default_npc_state(npc_id), "npc_state_ensure")


func update_relationship(
	npc_id: String,
	deltas: Dictionary,
	last_player_stance: String = ""
) -> Dictionary:
	var ensured := ensure_state(npc_id)
	if not bool(ensured.get("ok", false)):
		return ensured
	var state: Dictionary = ensured.get("state", {})
	var relationship: Dictionary = state.get("relationship", {}).duplicate(true)
	for field in RELATIONSHIP_FIELDS:
		if deltas.has(field):
			relationship[field] = clampi(
				int(relationship.get(field, 0)) + int(deltas.get(field, 0)),
				-10,
				10
			)
	if not last_player_stance.strip_edges().is_empty():
		relationship["last_player_stance"] = last_player_stance.strip_edges()
	state["relationship"] = relationship
	state["state_revision"] = int(state.get("state_revision", 0)) + 1
	state["updated_at_unix"] = int(Time.get_unix_time_from_system())
	return _upsert_state(npc_id, state, "npc_state_relationship")


func set_current_stake(npc_id: String, current_stake: Dictionary) -> Dictionary:
	var ensured := ensure_state(npc_id)
	if not bool(ensured.get("ok", false)):
		return ensured
	var clean := _clean_current_stake(current_stake)
	if not bool(clean.get("ok", false)):
		return clean
	var state: Dictionary = ensured.get("state", {})
	state["current_stake"] = clean.get("current_stake", {})
	state["state_revision"] = int(state.get("state_revision", 0)) + 1
	state["updated_at_unix"] = int(Time.get_unix_time_from_system())
	return _upsert_state(npc_id, state, "npc_state_current_stake")


func record_memory_projection(
	npc_id: String,
	memory_event_ids: Array,
	memory_summary: String,
	line_text: String = ""
) -> Dictionary:
	var ensured := ensure_state(npc_id)
	if not bool(ensured.get("ok", false)):
		return ensured
	var state: Dictionary = ensured.get("state", {})
	var refs: Array = state.get("memory_event_ids", []).duplicate(true)
	for event_id in memory_event_ids:
		var clean_event_id := str(event_id).strip_edges()
		if not DomainIdType.is_valid(clean_event_id, "event"):
			return _failure("Memory projection contains an invalid event ID.")
		if clean_event_id not in refs:
			refs.append(clean_event_id)
	while refs.size() > MAX_MEMORY_EVENT_IDS:
		refs.pop_front()
	state["memory_event_ids"] = refs
	state["memory_summary"] = memory_summary.strip_edges()
	if not line_text.strip_edges().is_empty():
		var fingerprints: Array = state.get("line_memory_fingerprints", []).duplicate(true)
		var fingerprint := line_text.to_lower().strip_edges().sha256_text().substr(0, 16)
		if fingerprint not in fingerprints:
			fingerprints.append(fingerprint)
		while fingerprints.size() > MAX_LINE_FINGERPRINTS:
			fingerprints.pop_front()
		state["line_memory_fingerprints"] = fingerprints
	state["state_revision"] = int(state.get("state_revision", 0)) + 1
	state["updated_at_unix"] = int(Time.get_unix_time_from_system())
	return _upsert_state(npc_id, state, "npc_state_memory_projection")


func capture_state_for_checkpoint() -> Dictionary:
	return data.duplicate(true)


func restore_state_from_checkpoint(checkpoint_state: Dictionary) -> bool:
	if checkpoint_state.is_empty():
		return false
	var restored := checkpoint_state.duplicate(true)
	var campaign_id := str(campaign.get("id", ""))
	var validation_result := _validate_data(restored, campaign_id)
	if not validation_result.is_valid():
		push_warning(
			"[CampaignNpcStateStore] Checkpoint NPC state restore rejected: %s" %
				validation_result.summary()
		)
		return false
	var committed := _commit(restored, "npc_state_checkpoint_restore")
	if not bool(committed.get("ok", false)):
		push_warning(
			"[CampaignNpcStateStore] Checkpoint NPC state restore failed: %s" %
				str(committed.get("error", "unknown error"))
		)
		return false
	data = restored
	return true


func _load_or_create() -> void:
	var campaign_result := DomainJsonType.read_object(
		"%s/campaign.json" % campaign_path
	)
	validation.merge(campaign_result["validation"], "campaign")
	if not validation.is_valid():
		return
	campaign = campaign_result["data"]
	var campaign_id := str(campaign.get("id", ""))
	if not DomainIdType.is_valid(campaign_id, "campaign"):
		validation.add_error(
			"invalid_campaign_id",
			"NPC states require a valid campaign id.",
			"campaign.id"
		)
		return
	var states_path := "%s/%s" % [campaign_path, STATES_PATH]
	if not FileAccess.file_exists(states_path):
		data = _default_document(campaign_id)
		var committed := _commit(data, "npc_state_bootstrap")
		if not bool(committed.get("ok", false)):
			validation.add_error(
				"npc_state_bootstrap_failed",
				str(committed.get("error", "NPC states could not be created.")),
				STATES_PATH
			)
		return
	var states_result := DomainJsonType.read_object(states_path)
	validation.merge(states_result["validation"], "npc_states")
	if not validation.is_valid():
		return
	data = states_result["data"]
	validation.merge(_validate_data(data, campaign_id), "npc_states")


func _commit(next_data: Dictionary, operation: String) -> Dictionary:
	return TransactionStoreType.commit_json_set(
		campaign_path,
		operation,
		{STATES_PATH: next_data},
		STATES_PATH,
		func(_path: String, value: Dictionary) -> ValidationResult:
			return _validate_data(value, str(campaign.get("id", "")))
	)


func _upsert_state(npc_id: String, state: Dictionary, operation: String) -> Dictionary:
	var next_data := data.duplicate(true)
	var states: Dictionary = next_data.get("npc_states", {}).duplicate(true) \
		if next_data.get("npc_states", {}) is Dictionary else {}
	states[npc_id] = state.duplicate(true)
	next_data["npc_states"] = states
	var committed := _commit(next_data, operation)
	if not bool(committed.get("ok", false)):
		return committed
	data = next_data
	return {"ok": true, "state": state.duplicate(true)}


static func _default_document(campaign_id: String) -> Dictionary:
	return {
		"schema_version": DOCUMENT_VERSION,
		"document_type": "campaign_npc_states",
		"campaign_id": campaign_id,
		"npc_states": {},
	}


static func _default_npc_state(npc_id: String) -> Dictionary:
	return {
		"npc_id": npc_id,
		"state_revision": 0,
		"relationship": {
			"trust": 0,
			"respect": 0,
			"warmth": 0,
			"debt": 0,
			"last_player_stance": "unknown",
			"promises": [],
		},
		"current_stake": {
			"thread_id": "",
			"why_it_matters_to_them": "",
			"urgency": 0,
		},
		"memory_event_ids": [],
		"memory_summary": "",
		"line_memory_fingerprints": [],
		"updated_at_unix": int(Time.get_unix_time_from_system()),
	}


static func _clean_current_stake(current_stake: Dictionary) -> Dictionary:
	var thread_id := str(current_stake.get("thread_id", "")).strip_edges()
	if not thread_id.is_empty() and not DomainIdType.is_valid(thread_id, "thread"):
		return _failure("Current stake thread ID is invalid.")
	return {
		"ok": true,
		"current_stake": {
			"thread_id": thread_id,
			"why_it_matters_to_them": str(
				current_stake.get("why_it_matters_to_them", "")
			).strip_edges(),
			"urgency": clampi(int(current_stake.get("urgency", 0)), 0, 5),
		},
	}


static func _validate_data(value: Dictionary, campaign_id: String) -> ValidationResult:
	var result := ValidationResultType.new()
	if int(value.get("schema_version", 0)) != DOCUMENT_VERSION:
		result.add_error(
			"invalid_npc_state_version",
			"NPC state schema version is invalid.",
			"schema_version"
		)
	if str(value.get("document_type", "")) != "campaign_npc_states":
		result.add_error(
			"invalid_npc_state_type",
			"NPC state document type is invalid.",
			"document_type"
		)
	if str(value.get("campaign_id", "")) != campaign_id:
		result.add_error(
			"npc_state_campaign_mismatch",
			"NPC states belong to a different campaign.",
			"campaign_id"
		)
	if not value.get("npc_states", {}) is Dictionary:
		result.add_error("invalid_npc_states", "NPC states must be a dictionary.", "npc_states")
		return result
	var states: Dictionary = value.get("npc_states", {})
	for npc_id in states.keys():
		if not states[npc_id] is Dictionary:
			result.add_error("invalid_npc_state", "NPC state must be an object.", "npc_states.%s" % npc_id)
			continue
		_validate_npc_state(str(npc_id), states[npc_id] as Dictionary, result)
	return result


static func _validate_npc_state(
	npc_id: String,
	state: Dictionary,
	result: ValidationResult
) -> void:
	var path := "npc_states.%s" % npc_id
	if not DomainIdType.is_valid(npc_id, "npc"):
		result.add_error("invalid_npc_id", "NPC state key is invalid.", path)
	if str(state.get("npc_id", "")) != npc_id:
		result.add_error("npc_state_id_mismatch", "NPC state key and id differ.", "%s.npc_id" % path)
	if int(state.get("state_revision", -1)) < 0:
		result.add_error("invalid_state_revision", "NPC state revision is invalid.", "%s.state_revision" % path)
	var relationship: Variant = state.get("relationship", {})
	if not relationship is Dictionary:
		result.add_error("invalid_relationship", "NPC relationship must be an object.", "%s.relationship" % path)
	else:
		for field in RELATIONSHIP_FIELDS:
			var score := int((relationship as Dictionary).get(field, 0))
			if score < -10 or score > 10:
				result.add_error(
					"invalid_relationship_score",
					"NPC relationship score is out of range.",
					"%s.relationship.%s" % [path, field]
				)
		if not (relationship as Dictionary).get("promises", []) is Array:
			result.add_error("invalid_promises", "NPC promises must be an array.", "%s.relationship.promises" % path)
	var current_stake: Variant = state.get("current_stake", {})
	if not current_stake is Dictionary:
		result.add_error("invalid_current_stake", "NPC current stake must be an object.", "%s.current_stake" % path)
	else:
		var thread_id := str((current_stake as Dictionary).get("thread_id", ""))
		if not thread_id.is_empty() and not DomainIdType.is_valid(thread_id, "thread"):
			result.add_error("invalid_stake_thread", "NPC stake thread ID is invalid.", "%s.current_stake.thread_id" % path)
	for field in ["memory_event_ids", "line_memory_fingerprints"]:
		if not state.get(field, []) is Array:
			result.add_error(
				"invalid_npc_state_array",
				"NPC state field must be an array.",
				"%s.%s" % [path, field]
			)


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
