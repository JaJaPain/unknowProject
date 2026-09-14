class_name MissionHistoryLedger
extends RefCounted


static func recent_agent_contracts_from_events(
	events: Array,
	limit: int = 8
) -> Array:
	var by_runtime_id: Dictionary = {}
	var ordered_runtime_ids: Array[String] = []
	for event in events:
		if not event is Dictionary:
			continue
		var e: Dictionary = event
		var payload: Dictionary = e.get("payload", {}) \
			if e.get("payload", {}) is Dictionary else {}
		if not _is_agent_mission_event(e, payload):
			continue
		var runtime_id := str(payload.get("runtime_id", "")).strip_edges()
		if runtime_id.is_empty():
			runtime_id = str(e.get("event_id", "")).strip_edges()
		var entry := _entry_from_payload(payload)
		if entry.is_empty():
			continue
		entry["event_type"] = str(e.get("event_type", ""))
		entry["sequence"] = int(e.get("sequence", 0))
		if not by_runtime_id.has(runtime_id):
			ordered_runtime_ids.append(runtime_id)
		by_runtime_id[runtime_id] = entry
	var recent: Array = []
	for runtime_id in ordered_runtime_ids:
		recent.append((by_runtime_id[runtime_id] as Dictionary).duplicate(true))
	recent.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("sequence", 0)) < int(right.get("sequence", 0))
	)
	if recent.size() > limit:
		recent = recent.slice(recent.size() - limit)
	return recent


static func _is_agent_mission_event(event: Dictionary, payload: Dictionary) -> bool:
	var event_type := str(event.get("event_type", ""))
	if not event_type in [
		"mission_accepted",
		"timed_mission_accepted",
		"mission_completed",
		"timed_mission_completed",
		"mission_abandoned",
		"timed_mission_abandoned",
		"timed_mission_expired",
	]:
		return false
	if bool(payload.get("public_board", false)):
		return false
	if bool(payload.get("station_errand", false)):
		return false
	var source_lane := str(payload.get("source_lane", "AGENT")).strip_edges()
	return source_lane.is_empty() or source_lane == "AGENT"


static func _entry_from_payload(payload: Dictionary) -> Dictionary:
	var objective := str(payload.get("objective_type", "")).strip_edges()
	if objective.is_empty():
		return {}
	var metadata: Dictionary = payload.get("narrative_metadata", {}) \
		if payload.get("narrative_metadata", {}) is Dictionary else {}
	var snapshot: Dictionary = metadata.get("outcome_snapshot", {}) \
		if metadata.get("outcome_snapshot", {}) is Dictionary else {}
	var candidate: Dictionary = snapshot.get("story_candidate", {}) \
		if snapshot.get("story_candidate", {}) is Dictionary else {}
	var entry := {
		"objective_type": objective,
		"cause_id": str(metadata.get("cause_id", "")),
		"stake": str(metadata.get("stake", "")),
		"thread_id": str(metadata.get("story_thread_id", "")),
		"beat_id": str(metadata.get("story_beat_id", "")),
		"completion_fact_ids": (
			metadata.get("completion_fact_ids", []) as Array
		).duplicate(true) if metadata.get("completion_fact_ids", []) is Array else [],
	}
	for field in [
		"premise_fingerprint",
		"giver_id",
		"location_id",
		"complication",
		"faction_id",
		"world_consequence",
		"disclosure_fact_ids",
	]:
		if candidate.has(field):
			entry[field] = (
				(candidate[field] as Array).duplicate(true)
				if candidate[field] is Array else candidate[field]
			)
	return entry
