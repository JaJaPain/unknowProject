extends SceneTree

const MissionDirectorType := preload("res://scripts/story/MissionDirector.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_feasible_candidates_cross_available_beats_objectives_and_givers()
	_test_hard_rejects_missing_mechanics_entities_givers_and_consumed_beats()
	_test_scores_candidates_with_documented_weight_buckets()
	_test_pacing_rules_block_repetition()
	_test_repeated_mechanic_requires_three_changes()
	_test_mining_repeats_only_when_distinct_and_separated()
	_test_declined_offer_cooldowns_filter_candidates()
	_test_select_best_candidate_or_withhold_for_alternate()

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


func _test_scores_candidates_with_documented_weight_buckets() -> void:
	var candidates := [
		{
			"beat_id": "beat.alpha",
			"cause_id": "cause.raids",
			"objective_type": "KILL_SHIPS",
			"giver_id": "agent.jenna",
			"giver_display": "Jenna Kross",
			"stake": "Stop the relay raids before they spread.",
		},
		{
			"beat_id": "beat.beta",
			"cause_id": "",
			"objective_type": "DELIVERY_COURIER",
			"giver_id": "agent.voss",
			"giver_display": "Director Voss",
			"stake": "",
		},
	]
	var scored := MissionDirectorType.score_candidates(
		candidates,
		{
			"preferred_cause_ids": ["cause.raids"],
			"urgent_beat_ids": ["beat.alpha"],
			"preferred_giver_ids": ["agent.jenna"],
			"preferred_objective_types": ["KILL_SHIPS"],
			"packet_consumed_ratio": 0.5,
		},
		[
			{"objective_type": "DELIVERY_COURIER"},
			{"objective_type": "DELIVERY_COURIER"},
		]
	)
	_expect(scored.size() == 2, "Expected two scored candidates")
	_expect(
		str(scored[0].get("beat_id", "")) == "beat.alpha",
		"Highest scoring candidate should sort first"
	)
	var breakdown: Dictionary = scored[0].get("score_breakdown", {})
	_expect(
		int(breakdown.get("causal_fit", 0)) == 40,
		"Causal fit should cap at 40"
	)
	_expect(
		int(breakdown.get("beat_urgency", 0)) == 20,
		"Urgent beat should receive 20 urgency points"
	)
	_expect(
		int(breakdown.get("variety_pacing", 0)) == 20,
		"Fresh objective should receive full variety points"
	)
	_expect(
		int(breakdown.get("character_stake", 0)) == 10,
		"Preferred giver should receive 10 character-stake points"
	)
	_expect(
		int(breakdown.get("player_ship_fit", 0)) == 10,
		"Preferred objective should receive 10 player/ship-fit points"
	)
	var lower_breakdown: Dictionary = scored[1].get("score_breakdown", {})
	_expect(
		int(lower_breakdown.get("variety_pacing", 0)) < 20,
		"Repeated recent objective should lose variety points"
	)


func _test_pacing_rules_block_repetition() -> void:
	var kill_candidate := {
		"beat_id": "beat.alpha",
		"objective_type": "KILL_SHIPS",
		"premise_fingerprint": "raid-relay",
	}
	_expect(
		MissionDirectorType.pacing_rejection_reason(
			kill_candidate,
			[
				{"objective_type": "KILL_SHIPS"},
				{"objective_type": "KILL_SHIPS"},
			]
		) == "third_identical_objective_blocked",
		"Third identical objective should be blocked"
	)
	_expect(
		MissionDirectorType.pacing_rejection_reason(
			kill_candidate,
			[
				{"objective_type": "KILL_SHIPS"},
				{"objective_type": "DELIVERY_COURIER"},
				{"objective_type": "KILL_SHIPS"},
				{"objective_type": "PURCHASE_DELIVERY"},
			]
		) == "objective_overrepresented_in_last_four",
		"Objective appearing twice in last four should block another copy"
	)
	_expect(
		MissionDirectorType.pacing_rejection_reason(
			kill_candidate,
			[
				{"objective_type": "DELIVERY_COURIER", "premise_fingerprint": "raid-relay"},
			]
		) == "repeated_premise_fingerprint",
		"Repeated premise fingerprint should be blocked"
	)
	var kept := MissionDirectorType.filter_by_pacing_rules(
		[
			kill_candidate,
			{
				"beat_id": "beat.beta",
				"objective_type": "DELIVERY_COURIER",
				"premise_fingerprint": "fresh-route",
			},
		],
		[
			{"objective_type": "KILL_SHIPS"},
			{"objective_type": "KILL_SHIPS"},
		]
	)
	_expect(
		kept.size() == 1 and str(kept[0].get("objective_type", "")) == "DELIVERY_COURIER",
		"Pacing filter should keep only non-repeating alternatives"
	)


func _test_repeated_mechanic_requires_three_changes() -> void:
	var prior := {
		"objective_type": "KILL_SHIPS",
		"cause_id": "cause.raids",
		"stake": "Stop the relay raids.",
		"giver_id": "agent.jenna",
		"location_id": "outpost.red",
		"complication": "storm",
		"faction_id": "zenith",
		"disclosure_fact_ids": ["fact.a"],
		"world_consequence": "raids spread",
	}
	var too_similar := prior.duplicate(true)
	too_similar["stake"] = "Stop the relay raids before they spread."
	too_similar["premise_fingerprint"] = "new-fingerprint"
	_expect(
		MissionDirectorType.repeated_mechanic_change_count(too_similar, prior) == 1,
		"Expected only stake to differ"
	)
	_expect(
		MissionDirectorType.pacing_rejection_reason(too_similar, [prior]) \
			== "repeated_mechanic_not_differentiated",
		"Repeated mechanic with fewer than 3 changes should be blocked"
	)
	var meaningfully_changed := prior.duplicate(true)
	meaningfully_changed["stake"] = "Save the courier lane."
	meaningfully_changed["giver_id"] = "agent.voss"
	meaningfully_changed["location_id"] = "outpost.blue"
	meaningfully_changed["premise_fingerprint"] = "another-new-fingerprint"
	_expect(
		MissionDirectorType.repeated_mechanic_change_count(meaningfully_changed, prior) >= 3,
		"Expected at least 3 changed dimensions"
	)
	_expect(
		MissionDirectorType.pacing_rejection_reason(meaningfully_changed, [prior]).is_empty(),
		"Repeated mechanic with at least 3 changes should pass"
	)


func _test_mining_repeats_only_when_distinct_and_separated() -> void:
	var prior_mining := {
		"objective_type": "DELIVER_ORE",
		"cause_id": "cause.shield_shortage",
		"stake": "Keep the clinic shields online.",
		"giver_id": "agent.jenna",
		"location_id": "belt.red",
		"complication": "radiation pockets",
		"faction_id": "clinic",
		"disclosure_fact_ids": ["fact.clinic_shortage"],
		"world_consequence": "The clinic keeps treating refugees.",
		"premise_fingerprint": "clinic-shield-ore",
	}
	var same_pressure := prior_mining.duplicate(true)
	same_pressure["stake"] = "Keep the clinic shields from failing."
	same_pressure["premise_fingerprint"] = "clinic-shield-ore-followup"
	_expect(
		MissionDirectorType.pacing_rejection_reason(same_pressure, [prior_mining]) \
			== "repeated_mechanic_not_differentiated",
		"Mining repeat with fewer than 3 changed dimensions should be blocked"
	)
	var distinct_mining := prior_mining.duplicate(true)
	distinct_mining["cause_id"] = "cause.refinery_embargo"
	distinct_mining["stake"] = "Break the refinery embargo before prices spike."
	distinct_mining["giver_id"] = "agent.voss"
	distinct_mining["location_id"] = "belt.blue"
	distinct_mining["premise_fingerprint"] = "refinery-embargo-ore"
	_expect(
		MissionDirectorType.repeated_mechanic_change_count(
			distinct_mining,
			prior_mining
		) >= 3,
		"Distinct mining repeat should change at least three narrative dimensions"
	)
	_expect(
		MissionDirectorType.pacing_rejection_reason(distinct_mining, [prior_mining]).is_empty(),
		"Mining repeat with changed cause, stake, giver, and location should pass"
	)
	_expect(
		MissionDirectorType.pacing_rejection_reason(
			distinct_mining,
			[
				{"objective_type": "DELIVER_ORE", "premise_fingerprint": "ore.a"},
				{"objective_type": "DELIVERY_COURIER", "premise_fingerprint": "courier.a"},
				{"objective_type": "DELIVER_ORE", "premise_fingerprint": "ore.b"},
				{"objective_type": "KILL_SHIPS", "premise_fingerprint": "kill.a"},
			]
		) == "objective_overrepresented_in_last_four",
		"Mining should still obey the last-four separation rule"
	)


func _test_declined_offer_cooldowns_filter_candidates() -> void:
	var candidate := {
		"beat_id": "beat.alpha",
		"objective_type": "KILL_SHIPS",
		"giver_id": "agent.jenna",
	}
	var key := MissionDirectorType.declined_offer_cooldown_key(candidate)
	_expect(
		key == "beat.alpha|KILL_SHIPS|agent.jenna",
		"Unexpected decline cooldown key: %s" % key
	)
	_expect(
		MissionDirectorType.decline_cooldown_rejection_reason(
			candidate,
			{key: 200},
			150
		) == "declined_offer_on_cooldown",
		"Active declined-offer cooldown should reject candidate"
	)
	_expect(
		MissionDirectorType.decline_cooldown_rejection_reason(
			candidate,
			{key: 200},
			201
		).is_empty(),
		"Expired declined-offer cooldown should not reject candidate"
	)
	var kept := MissionDirectorType.filter_by_decline_cooldowns(
		[
			candidate,
			{
				"beat_id": "beat.beta",
				"objective_type": "DELIVERY_COURIER",
				"giver_id": "agent.jenna",
			},
		],
		{key: 200},
		150
	)
	_expect(
		kept.size() == 1 and str(kept[0].get("beat_id", "")) == "beat.beta",
		"Decline cooldown filter should keep only candidates not on cooldown"
	)


func _test_select_best_candidate_or_withhold_for_alternate() -> void:
	var selected := MissionDirectorType.select_best_candidate(
		_packet(),
		{"beat.alpha": {"state": "available"}},
		[
			{
				"giver_id": "agent.jenna",
				"display_name": "Jenna Kross",
				"objective_types": ["KILL_SHIPS", "DELIVERY_COURIER"],
				"available": true,
			},
		],
		["zenith", "outpost.red"],
		{"preferred_objective_types": ["DELIVERY_COURIER"]},
		[],
		{},
		10
	)
	_expect(bool(selected.get("ok", false)), "Selection should find a candidate")
	_expect(
		str(selected.get("candidate", {}).get("objective_type", "")) == "DELIVERY_COURIER",
		"Selection should score preferred objective first"
	)
	var withheld := MissionDirectorType.select_best_candidate(
		_packet(),
		{"beat.alpha": {"state": "available"}},
		[
			{
				"giver_id": "agent.jenna",
				"display_name": "Jenna Kross",
				"objective_types": ["KILL_SHIPS"],
				"available": true,
			},
		],
		["zenith", "outpost.red"],
		{},
		[
			{"objective_type": "KILL_SHIPS"},
			{"objective_type": "KILL_SHIPS"},
		],
		{},
		10
	)
	_expect(
		not bool(withheld.get("ok", false))
			and str(withheld.get("status", "")) == "withheld_pacing_rules"
			and bool(withheld.get("needs_alternate_beat", false)),
		"Selection should withhold when every feasible candidate violates pacing"
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
