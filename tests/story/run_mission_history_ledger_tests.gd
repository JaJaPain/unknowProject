extends SceneTree

const MissionHistoryLedgerType := preload("res://scripts/story/MissionHistoryLedger.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_recent_agent_contracts_from_chronicle_events()
	_test_filters_non_agent_missions()

	if _failures.is_empty():
		print("[PASS] Mission history ledger tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_recent_agent_contracts_from_chronicle_events() -> void:
	var events := [
		_event(1, "timed_mission_accepted", "mission.runtime.alpha", "KILL_SHIPS", {
			"story_beat_id": "beat.alpha",
			"cause_id": "cause.raids",
			"stake": "Stop the raids.",
			"outcome_snapshot": {
				"story_candidate": {
					"premise_fingerprint": "raid-relay",
					"giver_id": "agent.jenna",
					"location_id": "outpost.red",
					"complication": "storm",
					"faction_id": "zenith",
					"disclosure_fact_ids": ["fact.a"],
					"world_consequence": "raids spread",
				},
			},
		}),
		_event(2, "timed_mission_completed", "mission.runtime.alpha", "KILL_SHIPS", {
			"story_beat_id": "beat.alpha",
			"cause_id": "cause.raids",
			"stake": "Stop the raids.",
			"outcome_snapshot": {
				"story_candidate": {
					"premise_fingerprint": "raid-relay",
					"giver_id": "agent.jenna",
				},
			},
		}),
		_event(3, "mission_accepted", "mission.runtime.beta", "DELIVERY_COURIER", {
			"story_beat_id": "beat.beta",
			"cause_id": "cause.shortage",
			"stake": "Keep the clinic stocked.",
			"outcome_snapshot": {
				"story_candidate": {
					"premise_fingerprint": "clinic-route",
					"giver_id": "agent.voss",
				},
			},
		}),
	]
	var recent := MissionHistoryLedgerType.recent_agent_contracts_from_events(events, 8)
	_expect(recent.size() == 2, "Expected one entry per runtime mission")
	_expect(
		str(recent[0].get("objective_type", "")) == "KILL_SHIPS",
		"First recent entry should preserve objective type"
	)
	_expect(
		str(recent[0].get("premise_fingerprint", "")) == "raid-relay",
		"Recent entry should carry premise fingerprint"
	)
	_expect(
		str(recent[1].get("beat_id", "")) == "beat.beta",
		"Recent entry should carry story beat id"
	)


func _test_filters_non_agent_missions() -> void:
	var events := [
		_event(1, "mission_accepted", "mission.runtime.board", "DELIVER_ORE", {}, "BOARD", true),
		_event(2, "mission_accepted", "mission.runtime.station", "PICKUP_SPECIAL", {}, "STATION", false),
		_event(3, "mission_accepted", "mission.runtime.errand", "DELIVERY_COURIER", {}, "", false, true),
		_event(4, "mission_accepted", "mission.runtime.agent", "KILL_SHIPS", {}, "AGENT", false),
	]
	var recent := MissionHistoryLedgerType.recent_agent_contracts_from_events(events, 8)
	_expect(recent.size() == 1, "Expected only agent lane mission in recent history")
	_expect(
		str(recent[0].get("objective_type", "")) == "KILL_SHIPS",
		"Filtered recent history should keep the agent mission"
	)


func _event(
	sequence: int,
	event_type: String,
	runtime_id: String,
	objective_type: String,
	metadata: Dictionary,
	source_lane: String = "AGENT",
	public_board: bool = false,
	station_errand: bool = false
) -> Dictionary:
	return {
		"event_id": "event.test.%d" % sequence,
		"event_type": event_type,
		"sequence": sequence,
		"payload": {
			"runtime_id": runtime_id,
			"objective_type": objective_type,
			"source_lane": source_lane,
			"public_board": public_board,
			"station_errand": station_errand,
			"narrative_metadata": metadata,
		},
	}
