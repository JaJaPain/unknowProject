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


func prompt_context_for(npc_id: String, max_memory_refs: int = 6) -> String:
	var clean_npc_id := npc_id.strip_edges()
	if clean_npc_id.is_empty() or not DomainIdType.is_valid(clean_npc_id, "npc"):
		return ""
	var state := state_for(clean_npc_id)
	var lines: Array[String] = []
	var relationship: Dictionary = state.get("relationship", {}) \
		if state.get("relationship", {}) is Dictionary else {}
	var rel_bits: Array[String] = []
	for field in RELATIONSHIP_FIELDS:
		var value := int(relationship.get(field, 0))
		if value != 0:
			rel_bits.append("%s %+d" % [field, value])
	if not rel_bits.is_empty():
		lines.append("Relationship: " + ", ".join(rel_bits) + ".")
	var last_stance := str(relationship.get("last_player_stance", "")).strip_edges()
	if not last_stance.is_empty() and last_stance != "unknown":
		lines.append("Last player stance: " + last_stance + ".")
	var current_stake: Dictionary = state.get("current_stake", {}) \
		if state.get("current_stake", {}) is Dictionary else {}
	var stake_text := str(
		current_stake.get("why_it_matters_to_them", "")
	).strip_edges()
	if not stake_text.is_empty():
		lines.append(
			"Current personal stake: %s Urgency %d/5." %
			[stake_text, int(current_stake.get("urgency", 0))]
		)
	var memory_summary := str(state.get("memory_summary", "")).strip_edges()
	if not memory_summary.is_empty():
		lines.append("Relevant memory: " + memory_summary)
	var refs: Array = state.get("memory_event_ids", []) \
		if state.get("memory_event_ids", []) is Array else []
	var bounded_refs: Array[String] = []
	var start := maxi(0, refs.size() - maxi(0, max_memory_refs))
	for index in range(start, refs.size()):
		var event_id := str(refs[index]).strip_edges()
		if not event_id.is_empty():
			bounded_refs.append(event_id)
	if not bounded_refs.is_empty():
		lines.append("Relevant memory refs: " + ", ".join(bounded_refs) + ".")
	if lines.is_empty():
		return ""
	return (
		"NPC STATE: Use this for tone and recall only; do not invent additional "
		+ "events or change relationship numbers. "
		+ " ".join(lines)
	)


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


func record_mission_outcome(npc_id: String, outcome: String) -> Dictionary:
	var clean_outcome := outcome.strip_edges().to_lower()
	var deltas := {}
	match clean_outcome:
		"accepted":
			deltas = {"respect": 1}
		"completed":
			deltas = {"trust": 2, "respect": 1, "warmth": 1}
		"declined":
			deltas = {"respect": -1}
		"abandoned":
			deltas = {"trust": -2, "respect": -1}
		"expired":
			deltas = {"trust": -1, "respect": -1}
		_:
			return _failure("Unsupported NPC mission outcome.")
	return update_relationship(npc_id, deltas, "mission_%s" % clean_outcome)


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


func record_memory_events(
	npc_id: String,
	events: Array,
	line_text: String = ""
) -> Dictionary:
	var event_ids: Array = []
	var relevant_events: Array = []
	for raw_event in events:
		if not (raw_event is Dictionary):
			continue
		var event_data: Dictionary = raw_event
		var subject_ids: Array = event_data.get("subject_ids", []) \
			if event_data.get("subject_ids", []) is Array else []
		if not subject_ids.is_empty() and not subject_ids.has(npc_id):
			continue
		var event_id := str(event_data.get("event_id", "")).strip_edges()
		if event_id.is_empty():
			continue
		event_ids.append(event_id)
		relevant_events.append(event_data)
	if event_ids.is_empty():
		return _failure("No structured memory events referenced this NPC.")
	return record_memory_projection(
		npc_id,
		event_ids,
		_memory_summary_from_events(relevant_events),
		line_text
	)


# Phase 9: structured lounge memory — the stance the player took and the
# fact IDs their questions surfaced. Bounded raw history (summarize later);
# the latest stance also lands on relationship.last_player_stance so
# prompt-facing consumers need no new plumbing. Invalid fact IDs are
# skipped, never fatal.
const MAX_LOUNGE_EXCHANGES := 8
const MAX_LOUNGE_FACT_IDS := 24


func record_lounge_conversation(
	npc_id: String,
	stance: String,
	fact_ids: Array
) -> Dictionary:
	var ensured := ensure_state(npc_id)
	if not bool(ensured.get("ok", false)):
		return ensured
	var state: Dictionary = ensured.get("state", {})
	var clean_stance := stance.strip_edges()
	if clean_stance.is_empty():
		clean_stance = "unknown"
	var relationship: Dictionary = state.get("relationship", {}) \
		if state.get("relationship", {}) is Dictionary else {}
	relationship["last_player_stance"] = clean_stance
	state["relationship"] = relationship
	var clean_fact_ids: Array = []
	var heard: Array = state.get("lounge_fact_ids", []).duplicate(true) \
		if state.get("lounge_fact_ids", []) is Array else []
	for raw_fact_id in fact_ids:
		var fact_id := str(raw_fact_id).strip_edges()
		if not DomainIdType.is_valid(fact_id, "fact"):
			continue
		if not clean_fact_ids.has(fact_id):
			clean_fact_ids.append(fact_id)
		if not heard.has(fact_id):
			heard.append(fact_id)
	while heard.size() > MAX_LOUNGE_FACT_IDS:
		heard.pop_front()
	state["lounge_fact_ids"] = heard
	var exchanges: Array = state.get("lounge_exchanges", []).duplicate(true) \
		if state.get("lounge_exchanges", []) is Array else []
	exchanges.append({
		"stance": clean_stance,
		"fact_ids": clean_fact_ids,
		"at_unix": int(Time.get_unix_time_from_system()),
	})
	while exchanges.size() > MAX_LOUNGE_EXCHANGES:
		exchanges.pop_front()
	state["lounge_exchanges"] = exchanges
	state["state_revision"] = int(state.get("state_revision", 0)) + 1
	state["updated_at_unix"] = int(Time.get_unix_time_from_system())
	return _upsert_state(npc_id, state, "npc_state_lounge_conversation")


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


static func _memory_summary_from_events(events: Array) -> String:
	var parts: Array[String] = []
	var start := maxi(0, events.size() - 3)
	for index in range(start, events.size()):
		var raw_event: Variant = events[index]
		if not (raw_event is Dictionary):
			continue
		var event: Dictionary = raw_event
		var payload: Dictionary = {}
		if event.get("payload", {}) is Dictionary:
			payload = event.get("payload", {}) as Dictionary
		var label: String = str(event.get("event_type", "event")).replace("_", " ")
		var summary_fields := ["title", "description", "summary"]
		for field in summary_fields:
			var candidate := str(payload.get(field, "")).strip_edges()
			if not candidate.is_empty():
				label = candidate
		if label.is_empty():
			label = str(event.get("event_type", "event")).replace("_", " ")
		parts.append(label)
	if parts.is_empty():
		return ""
	return "Recent memory: %s." % "; ".join(parts)


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
	for field in [
		"memory_event_ids",
		"line_memory_fingerprints",
		"lounge_fact_ids",
		"lounge_exchanges",
	]:
		if not state.get(field, []) is Array:
			result.add_error(
				"invalid_npc_state_array",
				"NPC state field must be an array.",
				"%s.%s" % [path, field]
			)


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
