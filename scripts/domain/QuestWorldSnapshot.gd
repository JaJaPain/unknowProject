class_name QuestWorldSnapshot
extends RefCounted

## The single source of world facts that `QuestPlausibilityValidator` checks a
## causal contract against, at every lifecycle stage.
##
## RULE: only report what we can actually resolve. A key that is ABSENT means
## unknown, and the validator correctly declines to find a fault from missing
## input. Supplying an invented capability list or a guessed requester balance
## would turn "we do not know" into "we checked", which is worse than not
## checking at all -- it manufactures both false passes and false rejections.
##
## Concretely: `capabilities` and `requester_funds` are NOT populated here,
## because nothing in the live game currently owns either as authoritative data.
## They are left out rather than faked. When a real registry exists, add it here
## and every stage gets it at once.

const ValidatorType := preload("res://scripts/domain/QuestPlausibilityValidator.gd")


## Build the snapshot from live autoloads. `destination_station_id` scopes the
## resident roster to the place the delivery actually has to happen.
static func build(destination_station_id: String = "") -> Dictionary:
	var snapshot := {}
	var gs := _global_state()
	if gs == null:
		return snapshot

	var system_id := ""
	if "current_system_id" in gs:
		system_id = str(gs.get("current_system_id")).strip_edges()
	if not system_id.is_empty():
		snapshot["system_id"] = system_id

	var stations := _station_ids(gs)
	if not stations.is_empty():
		snapshot["station_ids"] = stations

	var reachable := _reachable_system_ids(system_id)
	if not reachable.is_empty():
		snapshot["reachable_system_ids"] = reachable

	# Residents are only resolvable for a NAMED place. Without one we genuinely
	# do not know who is around, so the key stays absent rather than empty --
	# an empty list means "nobody is there", which is a finding, not ignorance.
	var destination := destination_station_id.strip_edges()
	if not destination.is_empty():
		snapshot["residents"] = _residents_at(gs, destination)

	return snapshot


## Residents currently at one station, in the shape the validator expects.
## Returns an EMPTY array when the place is real but unpopulated -- that is a
## delivery failure, and the validator now distinguishes it from unknown.
static func _residents_at(gs: Node, station_id: String) -> Array:
	var residents: Array = []
	if not gs.has_method("get_minor_npcs_at_outpost"):
		return residents
	for raw_name in gs.call("get_minor_npcs_at_outpost", station_id):
		var resident_name := str(raw_name).strip_edges()
		if resident_name.is_empty():
			continue
		residents.append({
			"id": "npc.%s" % resident_name.to_lower().replace(" ", "_"),
			"name": resident_name,
			"station_id": station_id,
		})
	# The primary station's own delivery contact is resolved separately and is
	# not part of the outpost roster.
	if gs.has_method("get_delivery_recipient"):
		var contact: Dictionary = gs.call("get_delivery_recipient", station_id)
		var contact_name := str(contact.get("name", "")).strip_edges()
		if not contact_name.is_empty():
			var contact_id := "npc.%s" % contact_name.to_lower().replace(" ", "_")
			var known := false
			for resident in residents:
				known = known or str((resident as Dictionary).get("id", "")) == contact_id
			if not known:
				residents.append({
					"id": contact_id,
					"name": contact_name,
					"station_id": station_id,
				})
	return residents


static func _station_ids(gs: Node) -> Array[String]:
	var ids: Array[String] = []
	if gs.has_method("get_current_pickup_outposts"):
		for raw_outpost in gs.call("get_current_pickup_outposts"):
			if not (raw_outpost is Dictionary):
				continue
			var outpost_id := str((raw_outpost as Dictionary).get("id", "")).strip_edges()
			if not outpost_id.is_empty() and outpost_id not in ids:
				ids.append(outpost_id)
	if "current_system_id" in gs:
		var system_id := str(gs.get("current_system_id")).strip_edges()
		if not system_id.is_empty() and system_id not in ids:
			ids.append(system_id)
	return ids


static func _reachable_system_ids(system_id: String) -> Array[String]:
	var reachable: Array[String] = []
	if not system_id.is_empty():
		reachable.append(system_id)
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return []
	var discovery := (loop as SceneTree).root.get_node_or_null("GateDiscovery")
	if discovery == null or not discovery.has_method("get_known_destination_ids"):
		# No authoritative route graph available: report unknown, not "nowhere".
		return []
	for raw_id in discovery.call("get_known_destination_ids"):
		var destination := str(raw_id).strip_edges()
		if not destination.is_empty() and destination not in reachable:
			reachable.append(destination)
	return reachable


static func _global_state() -> Node:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("GlobalState")


## Validate a mission's saved causal contract at one lifecycle stage.
##
## Returns {ok, checked, issue_codes}. `checked` is false when the mission
## carries no contract at all -- every mission accepted before contracts existed.
## Those are LEGACY COMPATIBLE: they keep their saved terms and are governed by
## the existing delivery guards, not by today's generation rules.
static func check_mission(
	mission_state: Dictionary,
	stage: String,
	destination_station_id: String = ""
) -> Dictionary:
	var metadata: Variant = mission_state.get("narrative_metadata", {})
	var contract: Variant = {}
	if metadata is Dictionary:
		contract = (metadata as Dictionary).get("causal_contract", {})
	if not (contract is Dictionary) or (contract as Dictionary).is_empty():
		contract = mission_state.get("causal_contract", {})
	var ContractType := load("res://scripts/domain/QuestCausalContract.gd")
	if not ContractType.is_present(contract):
		return {"ok": true, "checked": false, "issue_codes": [], "stage": stage}
	var destination := destination_station_id.strip_edges()
	if destination.is_empty():
		destination = str(mission_state.get("destination_station_id", "")).strip_edges()
	var report: Dictionary = ValidatorType.check(contract, build(destination), stage)
	return {
		"ok": bool(report.get("ok", false)),
		"checked": true,
		"issue_codes": report.get("issue_codes", []),
		"stage": stage,
	}
