class_name MissionDirector
extends RefCounted

const MissionCapabilityRegistryType := preload(
	"res://scripts/domain/MissionCapabilityRegistry.gd"
)


static func feasible_candidates(
	packet: Dictionary,
	beat_states: Dictionary,
	local_givers: Array,
	valid_entity_ids: Array
) -> Array:
	var candidates: Array = []
	var valid_entities := {}
	for entity_id in valid_entity_ids:
		valid_entities[str(entity_id)] = true
	for beat in packet.get("beats", []):
		if not beat is Dictionary:
			continue
		var b: Dictionary = beat
		if not _beat_is_available(b, beat_states):
			continue
		for objective_type in _array_or_empty(b.get("supported_objective_types", [])):
			var objective := str(objective_type).strip_edges()
			if objective.is_empty() \
					or not MissionCapabilityRegistryType.has_type(objective):
				continue
			for giver in local_givers:
				if not giver is Dictionary:
					continue
				var g: Dictionary = giver
				var rejection := _candidate_rejection_reason(
					b,
					objective,
					g,
					valid_entities
				)
				if not rejection.is_empty():
					continue
				candidates.append(_candidate(packet, b, objective, g))
	return candidates


static func rejected_candidate_reasons(
	packet: Dictionary,
	beat_states: Dictionary,
	local_givers: Array,
	valid_entity_ids: Array
) -> Array:
	var rejections: Array = []
	var valid_entities := {}
	for entity_id in valid_entity_ids:
		valid_entities[str(entity_id)] = true
	for beat in packet.get("beats", []):
		if not beat is Dictionary:
			continue
		var b: Dictionary = beat
		if not _beat_is_available(b, beat_states):
			rejections.append({
				"beat_id": str(b.get("beat_id", "")),
				"reason": "beat_not_available",
			})
			continue
		for objective_type in _array_or_empty(b.get("supported_objective_types", [])):
			var objective := str(objective_type).strip_edges()
			if objective.is_empty() \
					or not MissionCapabilityRegistryType.has_type(objective):
				rejections.append({
					"beat_id": str(b.get("beat_id", "")),
					"objective_type": objective,
					"reason": "unsupported_objective_type",
				})
				continue
			if local_givers.is_empty():
				rejections.append({
					"beat_id": str(b.get("beat_id", "")),
					"objective_type": objective,
					"reason": "no_local_giver",
				})
				continue
			for giver in local_givers:
				if not giver is Dictionary:
					continue
				var reason := _candidate_rejection_reason(
					b,
					objective,
					giver as Dictionary,
					valid_entities
				)
				if not reason.is_empty():
					rejections.append({
						"beat_id": str(b.get("beat_id", "")),
						"objective_type": objective,
						"giver_id": str((giver as Dictionary).get("giver_id", "")),
						"reason": reason,
					})
	return rejections


static func _beat_is_available(beat: Dictionary, beat_states: Dictionary) -> bool:
	var beat_id := str(beat.get("beat_id", "")).strip_edges()
	if beat_id.is_empty():
		return false
	var state: Dictionary = beat_states.get(beat_id, {}) \
		if beat_states.get(beat_id, {}) is Dictionary else {}
	var status := str(state.get("state", "available")).strip_edges()
	return status.is_empty() or ["available", "offered"].has(status)


static func _candidate_rejection_reason(
	beat: Dictionary,
	objective_type: String,
	giver: Dictionary,
	valid_entities: Dictionary
) -> String:
	var giver_id := str(giver.get("giver_id", "")).strip_edges()
	if giver_id.is_empty():
		return "missing_giver_id"
	if not bool(giver.get("available", true)):
		return "giver_unavailable"
	var giver_objectives: Array = _array_or_empty(giver.get("objective_types", []))
	if not giver_objectives.is_empty() and not giver_objectives.has(objective_type):
		return "giver_cannot_offer_objective"
	var eligible_entities: Array = _array_or_empty(beat.get("eligible_entity_ids", []))
	if eligible_entities.is_empty():
		return "missing_eligible_entity"
	for entity_id in eligible_entities:
		if not valid_entities.has(str(entity_id)):
			return "unknown_entity:%s" % str(entity_id)
	return ""


static func _candidate(
	packet: Dictionary,
	beat: Dictionary,
	objective_type: String,
	giver: Dictionary
) -> Dictionary:
	return {
		"packet_id": str(packet.get("packet_id", "")),
		"chapter": int(packet.get("chapter", 1)),
		"beat_id": str(beat.get("beat_id", "")),
		"thread_id": str(beat.get("thread_id", "")),
		"cause_id": str(beat.get("cause_id", "")),
		"objective_type": objective_type,
		"giver_id": str(giver.get("giver_id", "")),
		"giver_display": str(giver.get("display_name", giver.get("giver_id", ""))),
		"eligible_entity_ids": _array_or_empty(beat.get("eligible_entity_ids", [])),
		"stake": str(beat.get("stake", "")),
		"disclosure_fact_ids": _array_or_empty(beat.get("disclosure_fact_ids", [])),
		"completion_fact_ids": _array_or_empty(beat.get("completion_fact_ids", [])),
		"decline_consequence": str(beat.get("decline_consequence", "")),
	}


static func _array_or_empty(value: Variant) -> Array:
	if value is Array:
		return value
	return []
