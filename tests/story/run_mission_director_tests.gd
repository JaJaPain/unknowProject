extends SceneTree

const MissionDirectorType := preload("res://scripts/story/MissionDirector.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_feasible_candidates_cross_available_beats_objectives_and_givers()
	_test_hard_rejects_missing_mechanics_entities_givers_and_consumed_beats()

	if _failures.is_empty():
		print("[PASS] Mission director tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_feasible_candidates_cross_available_beats_objectives_and_givers() -> void:
	var candidates := MissionDirectorType.feasible_candidates(
		_packet(),
		{"beat.alpha": {"state": "available"}},
		[
			{
				"giver_id": "agent.jenna",
				"display_name": "Jenna Kross",
				"objective_types": ["KILL_SHIPS", "DELIVERY_COURIER"],
				"available": true,
			},
			{
				"giver_id": "agent.voss",
				"display_name": "Director Voss",
				"objective_types": ["KILL_SHIPS"],
				"available": true,
			},
		],
		["zenith", "outpost.red"]
	)
	_expect(candidates.size() == 3, "Expected 3 feasible candidates, got %d" % candidates.size())
	_expect(
		str(candidates[0].get("packet_id", "")) == "chapter_packet.1",
		"Candidate did not retain packet_id"
	)
	_expect(
		candidates.any(func(c): return str(c.get("objective_type", "")) == "DELIVERY_COURIER"),
		"Candidates missing DELIVERY_COURIER option"
	)
	_expect(
		candidates.any(func(c): return str(c.get("giver_id", "")) == "agent.voss"),
		"Candidates missing second eligible giver"
	)


func _test_hard_rejects_missing_mechanics_entities_givers_and_consumed_beats() -> void:
	var packet := _packet()
	packet["beats"].append({
		"beat_id": "beat.unsupported",
		"supported_objective_types": ["NOT_A_REAL_OBJECTIVE"],
		"eligible_entity_ids": ["zenith"],
		"stake": "Unsupported mechanics should not pass.",
	})
	packet["beats"].append({
		"beat_id": "beat.unknown_entity",
		"supported_objective_types": ["KILL_SHIPS"],
		"eligible_entity_ids": ["missing.entity"],
		"stake": "Missing entities should not pass.",
	})
	var candidates := MissionDirectorType.feasible_candidates(
		packet,
		{
			"beat.alpha": {"state": "completed"},
			"beat.unsupported": {"state": "available"},
			"beat.unknown_entity": {"state": "available"},
		},
		[
			{
				"giver_id": "agent.jenna",
				"objective_types": ["KILL_SHIPS"],
				"available": true,
			},
			{
				"giver_id": "agent.sleeping",
				"objective_types": ["KILL_SHIPS"],
				"available": false,
			},
		],
		["zenith"]
	)
	_expect(candidates.is_empty(), "Rejected packet should produce no candidates")
	var reasons := MissionDirectorType.rejected_candidate_reasons(
		packet,
		{
			"beat.alpha": {"state": "completed"},
			"beat.unsupported": {"state": "available"},
			"beat.unknown_entity": {"state": "available"},
		},
		[],
		["zenith"]
	)
	_expect(
		reasons.any(func(r): return str(r.get("reason", "")) == "beat_not_available"),
		"Missing rejection reason for consumed beat"
	)
	_expect(
		reasons.any(func(r): return str(r.get("reason", "")) == "unsupported_objective_type"),
		"Missing rejection reason for unsupported objective"
	)
	_expect(
		reasons.any(func(r): return str(r.get("reason", "")) == "no_local_giver"),
		"Missing rejection reason for absent giver"
	)


func _packet() -> Dictionary:
	return {
		"packet_id": "chapter_packet.1",
		"chapter": 1,
		"beats": [
			{
				"beat_id": "beat.alpha",
				"thread_id": "thread.pressure",
				"cause_id": "cause.raids",
				"supported_objective_types": ["KILL_SHIPS", "DELIVERY_COURIER"],
				"eligible_entity_ids": ["zenith", "outpost.red"],
				"stake": "Stop the relay raids before they spread.",
				"disclosure_fact_ids": ["fact.public"],
				"completion_fact_ids": ["fact.done"],
				"decline_consequence": "The raiders get a cleaner shot later.",
			},
		],
	}
