extends SceneTree

const MissionDirectorType := preload("res://scripts/story/MissionDirector.gd")
const MissionCapabilityRegistryType := preload(
	"res://scripts/domain/MissionCapabilityRegistry.gd"
)

const OBJECTIVES := [
	"DELIVER_ORE",
	"KILL_SHIPS",
	"PICKUP_SPECIAL",
	"DELIVERY_COURIER",
	"PURCHASE_DELIVERY",
	"RECOVER_COMBAT_DROP",
	"TARGET_WITH_COMMS_REVERSAL",
]

var _failures: Array[String] = []


func _initialize() -> void:
	_test_deterministic_100_offer_simulation()

	if _failures.is_empty():
		print("[PASS] Story offer simulation tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_deterministic_100_offer_simulation() -> void:
	var packet := _simulation_packet(140)
	var beat_states := {}
	for beat in packet.get("beats", []):
		if not beat is Dictionary:
			continue
		beat_states[str((beat as Dictionary).get("beat_id", ""))] = {
			"state": "available",
		}
	var local_givers := [{
		"giver_id": "agent.sim",
		"display_name": "Simulation Contact",
		"objective_types": OBJECTIVES.duplicate(),
		"available": true,
	}]
	var valid_entity_ids := ["entity.valid"]
	var recent_contracts: Array = []
	var selected_objectives: Array[String] = []
	var declined_required_resolved := 0

	for i in range(100):
		var selection: Dictionary = MissionDirectorType.select_best_candidate(
			packet,
			beat_states,
			local_givers,
			valid_entity_ids,
			{
				"packet_consumed_ratio": float(i) / 100.0,
				"preferred_objective_types": OBJECTIVES.duplicate(),
				"preferred_giver_ids": ["agent.sim"],
			},
			recent_contracts,
			{},
			i * 10
		)
		_expect(
			bool(selection.get("ok", false)),
			"Simulation offer %d withheld unexpectedly: %s" % [
				i,
				str(selection.get("status", "unknown")),
			]
		)
		if not bool(selection.get("ok", false)):
			return
		var candidate: Dictionary = selection.get("candidate", {})
		var objective := str(candidate.get("objective_type", ""))
		_expect(
			MissionCapabilityRegistryType.has_type(objective),
			"Simulation selected illegal objective type: %s" % objective
		)
		selected_objectives.append(objective)
		if selected_objectives.size() >= 3:
			var last := selected_objectives.size() - 1
			_expect(
				not (
					selected_objectives[last] == selected_objectives[last - 1]
					and selected_objectives[last] == selected_objectives[last - 2]
				),
				"Simulation produced three %s offers in a row at index %d." % [
					objective,
					i,
				]
			)
		var beat_id := str(candidate.get("beat_id", ""))
		if bool(candidate.get("required", false)) and i % 13 == 0:
			beat_states[beat_id]["state"] = "declined"
			var alternate := str(candidate.get("alternate_beat_id", ""))
			if not alternate.is_empty():
				beat_states[alternate] = {
					"state": "available",
					"activated_by_decline_of": beat_id,
				}
				declined_required_resolved += 1
			else:
				beat_states[beat_id]["state"] = "failed"
				declined_required_resolved += 1
		else:
			beat_states[beat_id]["state"] = "completed"
			recent_contracts.append(candidate.duplicate(true))
			if recent_contracts.size() > 8:
				recent_contracts.pop_front()

	_expect(
		declined_required_resolved > 0,
		"Simulation did not exercise required-beat decline resolution."
	)
	for beat_id in beat_states.keys():
		var state: Dictionary = beat_states[beat_id]
		if str(state.get("state", "")) != "declined":
			continue
		_expect(
			not _beat_required(packet, str(beat_id))
				or _has_active_alternate_for_decline(beat_states, str(beat_id)),
			"Required declined beat remained unresolved: %s" % str(beat_id)
		)


func _simulation_packet(count: int) -> Dictionary:
	var beats: Array = []
	for i in range(count):
		var objective := str(OBJECTIVES[i % OBJECTIVES.size()])
		var beat_id := "beat.sim.%03d" % i
		beats.append({
			"beat_id": beat_id,
			"thread_id": "thread.sim.%02d" % (i % 9),
			"cause_id": "cause.sim.%03d" % i,
			"supported_objective_types": [objective],
			"eligible_entity_ids": ["entity.valid"],
			"location_id": "location.sim.%03d" % i,
			"faction_id": "faction.sim.%03d" % i,
			"stake": "Simulation stake %03d" % i,
			"complication": "Simulation complication %03d" % i,
			"disclosure_fact_ids": ["fact.sim.disclose.%03d" % i],
			"completion_fact_ids": ["fact.sim.complete.%03d" % i],
			"world_consequence": "Simulation world consequence %03d" % i,
			"premise_fingerprint": "sim-premise-%03d" % i,
			"required": i % 11 == 0,
			"alternate_beat_id": "beat.sim.alt.%03d" % i if i % 11 == 0 else "",
		})
		if i % 11 == 0:
			beats.append({
				"beat_id": "beat.sim.alt.%03d" % i,
				"thread_id": "thread.sim.alt.%02d" % (i % 9),
				"cause_id": "cause.sim.alt.%03d" % i,
				"supported_objective_types": [str(OBJECTIVES[(i + 1) % OBJECTIVES.size()])],
				"eligible_entity_ids": ["entity.valid"],
				"location_id": "location.sim.alt.%03d" % i,
				"faction_id": "faction.sim.alt.%03d" % i,
				"stake": "Simulation alternate stake %03d" % i,
				"complication": "Simulation alternate complication %03d" % i,
				"disclosure_fact_ids": ["fact.sim.alt.disclose.%03d" % i],
				"completion_fact_ids": ["fact.sim.alt.complete.%03d" % i],
				"world_consequence": "Simulation alternate consequence %03d" % i,
				"premise_fingerprint": "sim-alt-premise-%03d" % i,
			})
	return {
		"packet_id": "chapter_packet.simulation",
		"chapter": 1,
		"beats": beats,
	}


func _beat_required(packet: Dictionary, beat_id: String) -> bool:
	for beat in packet.get("beats", []):
		if beat is Dictionary and str((beat as Dictionary).get("beat_id", "")) == beat_id:
			return bool((beat as Dictionary).get("required", false))
	return false


func _has_active_alternate_for_decline(
	beat_states: Dictionary,
	declined_beat_id: String
) -> bool:
	for state_value in beat_states.values():
		if not state_value is Dictionary:
			continue
		var state: Dictionary = state_value
		if str(state.get("activated_by_decline_of", "")) != declined_beat_id:
			continue
		if str(state.get("state", "")) == "available":
			return true
	return false
