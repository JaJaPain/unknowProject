extends SceneTree

const DefinitionType := preload(
	"res://scripts/domain/MissionDefinition.gd"
)
const AdapterType := preload(
	"res://scripts/domain/MissionAdapter.gd"
)

var _failures: Array[String] = []


func _initialize() -> void:
	_test_ore_offer()
	_test_kill_offer()
	_test_pickup_offer()
	_test_timed_offer()
	_test_malformed_offers()
	_test_legacy_runtime_state()
	_test_invalid_runtime_state()

	if _failures.is_empty():
		print("[PASS] Mission contract tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_ore_offer() -> void:
	var adapted := AdapterType.build_active_state(
		_offer(
			"Ore Run",
			"zenith",
			"Director Voss",
			{
				"type": "DELIVER_ORE",
				"amount_required": 30.0,
				"reward_credits": 120,
			}
		),
		_choice(10, {"zenith": 2.0}, 1.0, 1.25),
		"mission.runtime.ore_test",
		"start_system"
	)
	_expect(
		adapted["validation"].is_valid(),
		"Valid ore offer failed validation."
	)
	var state: Dictionary = adapted["state"]
	_expect(
		state.get("objective_type") == "DELIVER_ORE"
			and is_equal_approx(float(state.get("amount_required")), 30.0)
			and int(state.get("reward_credits")) == 120
			and is_equal_approx(
				float(state.get("reward_credits_multiplier")),
				1.25
			),
		"Ore offer did not produce the compatible runtime shape."
	)


func _test_kill_offer() -> void:
	var adapted := AdapterType.build_active_state(
		_offer(
			"Patrol Sweep",
			"vanguard",
			"Captain Dask",
			{
				"type": "KILL_SHIPS",
				"target_faction": "reavers",
				"count_required": 3,
				"reward_credits": 200,
			}
		),
		_choice(0, {}, 1.5, 1.0),
		"mission.runtime.kill_test",
		"start_system"
	)
	_expect(
		adapted["validation"].is_valid(),
		"Valid kill offer failed validation."
	)
	var state: Dictionary = adapted["state"]
	_expect(
		state.get("objective_type") == "KILL_SHIPS"
			and state.get("target_faction") == "reavers"
			and int(state.get("count_required")) == 4
			and int(state.get("current_count")) == 0,
		"Kill offer did not apply its combat multiplier correctly."
	)


func _test_pickup_offer() -> void:
	var adapted := AdapterType.build_active_state(
		_offer(
			"Coupler Retrieval",
			"neutral",
			"Jenna Kross",
			{
				"type": "PICKUP_SPECIAL",
				"target_outpost": "kova",
				"target_outpost_display": "Kova Station",
				"target_npc": "Cassen Vane",
				"part_name": "Plasma Coupler",
				"destination": "Grease Monkeys",
				"reward_credits": 75,
			}
		),
		_choice(0, {}, 1.0, 1.0),
		"mission.runtime.pickup_test",
		"start_system"
	)
	_expect(
		adapted["validation"].is_valid(),
		"Valid pickup offer failed validation."
	)
	var definition = adapted["definition"]
	var state: Dictionary = adapted["state"]
	_expect(
		str(definition.giver_npc_id) == "npc.jenna_kross"
			and state.get("target_outpost") == "kova"
			and state.get("part_name") == "Plasma Coupler"
			and not bool(state.get("picked_up")),
		"Pickup offer lost stable giver or objective fields."
	)


func _test_timed_offer() -> void:
	var offer := _offer(
		"Urgent Parts Run",
		"neutral",
		"Jenna Kross",
		{
			"type": "PICKUP_SPECIAL",
			"target_outpost": "iron_reach",
			"target_outpost_display": "Outpost Iron Reach",
			"target_npc": "Alaric Venn",
			"part_name": "Sealed Actuator",
			"destination": "Grease Monkeys",
			"reward_credits": 225,
		}
	)
	offer["timing"] = {
		"timed": true,
		"urgent": true,
		"duration_minutes": 180,
		"expiration_policy": "expire",
		"urgent_reward_multiplier": 1.5,
	}
	var adapted := AdapterType.build_active_state(
		offer,
		_choice(0, {}, 1.0, 1.0),
		"mission.runtime.timed_test",
		"start_system",
		480
	)
	_expect(
		adapted["validation"].is_valid(),
		"Valid timed offer failed validation."
	)
	var state: Dictionary = adapted["state"]
	_expect(
		bool(state.get("is_timed", false))
			and bool(state.get("is_urgent", false))
			and int(state.get("accepted_time_minutes", 0)) == 480
			and int(state.get("deadline_time_minutes", 0)) == 660
			and is_equal_approx(
				float(state.get("urgent_reward_multiplier", 0.0)),
				1.5
			),
		"Timed offer did not produce campaign-time deadline metadata."
	)


func _test_malformed_offers() -> void:
	var bad_type := _offer(
		"Impossible",
		"zenith",
		"Director Voss",
		{"type": "LAND_ON_PLANET", "reward_credits": 10}
	)
	_expect(
		not DefinitionType.new().load_from_offer(bad_type).is_valid(),
		"Unsupported objective type was accepted."
	)

	var missing_pickup := _offer(
		"Missing Cargo",
		"neutral",
		"Jenna Kross",
		{
			"type": "PICKUP_SPECIAL",
			"target_outpost": "kova",
			"reward_credits": 10,
		}
	)
	_expect(
		not DefinitionType.new().load_from_offer(missing_pickup).is_valid(),
		"Incomplete pickup objective was accepted."
	)

	var negative_reward := _offer(
		"Debt Trap",
		"zenith",
		"Director Voss",
		{
			"type": "DELIVER_ORE",
			"amount_required": 10,
			"reward_credits": -50,
		}
	)
	_expect(
		not DefinitionType.new().load_from_offer(negative_reward).is_valid(),
		"Negative mission reward was accepted."
	)

	var bad_timing := _offer(
		"Broken Timer",
		"zenith",
		"Director Voss",
		{
			"type": "DELIVER_ORE",
			"amount_required": 10,
			"reward_credits": 50,
		}
	)
	bad_timing["timing"] = {
		"timed": true,
		"duration_minutes": 0,
	}
	_expect(
		not DefinitionType.new().load_from_offer(bad_timing).is_valid(),
		"Timed mission without positive duration was accepted."
	)


func _test_legacy_runtime_state() -> void:
	var normalized := AdapterType.normalize_legacy_state({
		"title": "Legacy Ore",
		"faction": "zenith",
		"objective_type": "DELIVER_ORE",
		"amount_required": 40.0,
		"partial_delivered": 11.0,
	})
	_expect(
		AdapterType.validate_active_state(normalized).is_valid(),
		"Valid legacy runtime state did not normalize."
	)
	_expect(
		str(normalized.get("runtime_id", "")).begins_with("mission.legacy.")
			and str(normalized.get("definition_id", "")).begins_with(
				"mission.offer."
			)
			and int(normalized.get("mission_schema_version", 0)) == 1,
		"Legacy runtime state did not receive typed identity metadata."
	)


func _test_invalid_runtime_state() -> void:
	var invalid := AdapterType.normalize_legacy_state({
		"title": "Broken",
		"faction": "zenith",
		"objective_type": "DELIVER_ORE",
		"amount_required": 0.0,
	})
	_expect(
		not AdapterType.validate_active_state(invalid).is_valid(),
		"Malformed active mission state was accepted."
	)


func _offer(
	title: String,
	faction: String,
	agent_name: String,
	objective: Dictionary
) -> Dictionary:
	return {
		"title": title,
		"faction": faction,
		"agent_name": agent_name,
		"dialogue": "Contract briefing.",
		"objective": objective,
		"choices": [],
	}


func _choice(
	credits: int,
	reputation: Dictionary,
	combat_multiplier: float,
	reward_multiplier: float
) -> Dictionary:
	return {
		"text": "Accepted.",
		"consequence": {
			"credits_immediate": credits,
			"reputation_change": reputation,
			"combat_multiplier": combat_multiplier,
			"reward_credits_multiplier": reward_multiplier,
			"dialogue_response": "Proceed.",
		},
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
