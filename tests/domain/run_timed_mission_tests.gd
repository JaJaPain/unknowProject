extends SceneTree

const ClockType := preload("res://scripts/time/CampaignClock.gd")
const AdapterType := preload("res://scripts/domain/MissionAdapter.gd")
const DefinitionType := preload("res://scripts/domain/MissionDefinition.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_timed_metadata_round_trip()
	_test_untimed_mission_has_no_timing()
	_test_deadline_from_accepted_time()
	_test_urgent_reward_multiplier()
	_test_expiration_clears_active_state()
	_test_expiration_clears_special_cargo()
	_test_expiration_clears_courier_cargo()
	_test_expiration_preserves_purchase_inventory()
	_test_no_expiration_before_deadline()
	_test_remaining_time_counts_down()
	_test_zero_duration_rejected()
	_test_negative_duration_rejected()

	if _failures.is_empty():
		print("[PASS] Timed mission tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_timed_metadata_round_trip() -> void:
	var adapted := _build_timed_ore(480, 180, true, 1.5)
	_expect(
		adapted["validation"].is_valid(),
		"timed_metadata: valid timed offer was rejected."
	)
	var state: Dictionary = adapted["state"]
	_expect(
		bool(state.get("is_timed", false))
			and bool(state.get("is_urgent", false))
			and int(state.get("accepted_time_minutes", 0)) == 480
			and int(state.get("deadline_time_minutes", 0)) == 660
			and int(state.get("expires_after_minutes", 0)) == 180
			and str(state.get("expiration_policy", "")) == "expire"
			and is_equal_approx(
				float(state.get("urgent_reward_multiplier", 0.0)), 1.5
			),
		"timed_metadata: timed fields did not round-trip through adaptation."
	)


func _test_untimed_mission_has_no_timing() -> void:
	var offer := _ore_offer(40.0, 120)
	var adapted := AdapterType.build_active_state(
		offer, _accept_choice(), "mission.runtime.untimed", "start_system", 480
	)
	_expect(adapted["validation"].is_valid(), "untimed: offer was rejected.")
	var state: Dictionary = adapted["state"]
	_expect(
		not bool(state.get("is_timed", false))
			and not bool(state.get("is_urgent", false))
			and int(state.get("accepted_time_minutes", 0)) == 0
			and int(state.get("deadline_time_minutes", 0)) == 0
			and int(state.get("expires_after_minutes", 0)) == 0,
		"untimed: mission without timing block still produced timed fields."
	)


func _test_deadline_from_accepted_time() -> void:
	var early := _build_timed_ore(100, 60, false, 1.0)
	var late := _build_timed_ore(900, 60, false, 1.0)
	_expect(
		int(early["state"].get("deadline_time_minutes", 0)) == 160
			and int(late["state"].get("deadline_time_minutes", 0)) == 960,
		"deadline: deadline did not equal accepted_time + duration."
	)


func _test_urgent_reward_multiplier() -> void:
	var urgent := _build_timed_ore(480, 120, true, 2.0)
	var state: Dictionary = urgent["state"]
	var base := int(state.get("reward_credits", 0))
	var multiplier := float(state.get("urgent_reward_multiplier", 1.0))
	var expected_payout := int(round(float(base) * multiplier))
	_expect(
		is_equal_approx(multiplier, 2.0) and expected_payout == base * 2,
		"urgent_reward: urgent multiplier did not produce double payout."
	)


func _test_expiration_clears_active_state() -> void:
	var clock := ClockType.new()
	clock.restore_state({"total_minutes": 480})

	var offer := _ore_offer(20.0, 60)
	offer["timing"] = {
		"timed": true,
		"urgent": true,
		"duration_minutes": 10,
		"expiration_policy": "expire",
		"urgent_reward_multiplier": 1.5,
	}
	var adapted := AdapterType.build_active_state(
		offer, _accept_choice(), "mission.runtime.expire_test",
		"start_system", clock.total_minutes
	)
	_expect(adapted["validation"].is_valid(), "expiration_clear: offer rejected.")
	var state: Dictionary = adapted["state"]
	var deadline := int(state.get("deadline_time_minutes", 0))
	_expect(
		deadline == 490,
		"expiration_clear: deadline was not 490 (got %d)." % deadline
	)
	_expect(
		clock.total_minutes < deadline,
		"expiration_clear: clock already past deadline before advance."
	)
	clock.advance_minutes(10)
	_expect(
		clock.total_minutes >= deadline,
		"expiration_clear: clock did not reach deadline after advance."
	)


func _test_expiration_clears_special_cargo() -> void:
	var offer := _pickup_offer()
	offer["timing"] = {
		"timed": true,
		"duration_minutes": 1,
		"expiration_policy": "expire",
	}
	var adapted := AdapterType.build_active_state(
		offer, _accept_choice(), "mission.runtime.cargo_expire",
		"start_system", 480
	)
	_expect(
		adapted["validation"].is_valid(),
		"cargo_expire: timed pickup offer was rejected."
	)
	_expect(
		int(adapted["state"].get("deadline_time_minutes", 0)) == 481,
		"cargo_expire: deadline was not 481."
	)


func _test_expiration_clears_courier_cargo() -> void:
	var qm = root.get_node("QuestManager")
	var clock = root.get_node("CampaignClock")
	var gs = root.get_node("GlobalState")
	qm.reset_for_restart()
	clock.restore_state({"total_minutes": 480})
	gs.clear_cargo()

	var offer := _courier_offer()
	offer["timing"] = {
		"timed": true,
		"duration_minutes": 1,
		"expiration_policy": "expire",
	}
	_expect(
		qm.accept_quest(offer, _accept_choice()),
		"courier_expire: timed courier offer was rejected."
	)
	_expect(
		int(gs.cargo_type) == int(gs.CargoType.SPECIAL)
			and str(gs.cargo_special.get("name", "")) == "Sealed Evidence Tube",
		"courier_expire: courier cargo was not loaded on acceptance."
	)
	clock.advance_minutes(1)
	qm.check_active_quest_expiration()
	_expect(
		not qm.is_quest_active()
			and int(gs.cargo_type) == int(gs.CargoType.EMPTY)
			and gs.cargo_special.is_empty(),
		"courier_expire: expiration did not clear active mission and courier cargo."
	)


func _test_expiration_preserves_purchase_inventory() -> void:
	var qm = root.get_node("QuestManager")
	var clock = root.get_node("CampaignClock")
	var gs = root.get_node("GlobalState")
	qm.reset_for_restart()
	clock.restore_state({"total_minutes": 480})
	var previous_inventory = gs.inventory
	gs.inventory = gs.PlayerInventoryScript.new()
	gs.inventory.add("data_chip", 2)

	var offer := _purchase_offer()
	offer["timing"] = {
		"timed": true,
		"duration_minutes": 1,
		"expiration_policy": "expire",
	}
	_expect(
		qm.accept_quest(offer, _accept_choice()),
		"purchase_expire: timed purchase-delivery offer was rejected."
	)
	clock.advance_minutes(1)
	qm.check_active_quest_expiration()
	_expect(
		not qm.is_quest_active()
			and int(gs.inventory.get_quantity("data_chip")) == 2,
		"purchase_expire: expiration should clear mission without consuming inventory."
	)
	gs.inventory = previous_inventory


func _test_no_expiration_before_deadline() -> void:
	var clock := ClockType.new()
	clock.restore_state({"total_minutes": 480})
	var offer := _ore_offer(20.0, 60)
	offer["timing"] = {
		"timed": true,
		"duration_minutes": 120,
		"expiration_policy": "expire",
	}
	var adapted := AdapterType.build_active_state(
		offer, _accept_choice(), "mission.runtime.no_expire",
		"start_system", clock.total_minutes
	)
	_expect(adapted["validation"].is_valid(), "no_expire: offer rejected.")
	clock.advance_minutes(60)
	_expect(
		clock.total_minutes < int(adapted["state"].get("deadline_time_minutes", 0)),
		"no_expire: clock surpassed deadline with only half the duration elapsed."
	)


func _test_remaining_time_counts_down() -> void:
	var adapted := _build_timed_ore(480, 120, false, 1.0)
	var state: Dictionary = adapted["state"]
	var deadline := int(state.get("deadline_time_minutes", 0))
	var remaining_at_start := deadline - 480
	var remaining_after_30 := deadline - 510
	_expect(
		remaining_at_start == 120 and remaining_after_30 == 90,
		"remaining_time: countdown arithmetic was wrong."
	)


func _test_zero_duration_rejected() -> void:
	var offer := _ore_offer(20.0, 60)
	offer["timing"] = {"timed": true, "duration_minutes": 0}
	_expect(
		not DefinitionType.new().load_from_offer(offer).is_valid(),
		"zero_duration: timed mission with zero duration was accepted."
	)


func _test_negative_duration_rejected() -> void:
	var offer := _ore_offer(20.0, 60)
	offer["timing"] = {"timed": true, "duration_minutes": -30}
	_expect(
		not DefinitionType.new().load_from_offer(offer).is_valid(),
		"negative_duration: timed mission with negative duration was accepted."
	)


func _ore_offer(amount: float, reward: int) -> Dictionary:
	return {
		"title": "Test Ore",
		"faction": "zenith",
		"agent_name": "Director Voss",
		"dialogue": "Deliver ore.",
		"objective": {
			"type": "DELIVER_ORE",
			"amount_required": amount,
			"reward_credits": reward,
		},
		"choices": [],
	}


func _pickup_offer() -> Dictionary:
	return {
		"title": "Timed Pickup",
		"faction": "neutral",
		"agent_name": "Jenna Kross",
		"dialogue": "Retrieve the part.",
		"objective": {
			"type": "PICKUP_SPECIAL",
			"target_outpost": "kova",
			"target_outpost_display": "Kova Station",
			"target_npc": "Cassen Vane",
			"part_name": "Sealed Actuator",
			"destination": "Grease Monkeys",
			"reward_credits": 75,
		},
		"choices": [],
	}


func _courier_offer() -> Dictionary:
	return {
		"title": "Timed Courier",
		"faction": "neutral",
		"agent_name": "Public Board",
		"dialogue": "Carry the package.",
		"objective": {
			"type": "DELIVERY_COURIER",
			"item_name": "Sealed Evidence Tube",
			"origin_station_id": "station.start.main",
			"origin_display": "Main Station",
			"destination_station_id": "station.start.kova",
			"destination_display": "Kova Station",
			"reward_credits": 160,
		},
		"choices": [],
	}


func _purchase_offer() -> Dictionary:
	return {
		"title": "Timed Purchase",
		"faction": "neutral",
		"agent_name": "Public Board",
		"dialogue": "Buy the part and deliver it.",
		"objective": {
			"type": "PURCHASE_DELIVERY",
			"item_id": "data_chip",
			"item_name": "Data Chip",
			"quantity_required": 2,
			"store_station_id": "station.start.main",
			"store_display": "Main Station",
			"destination_station_id": "station.start.kova",
			"destination_display": "Kova Station",
			"reward_credits": 180,
		},
		"choices": [],
	}


func _build_timed_ore(
	current_time: int,
	duration: int,
	urgent: bool,
	multiplier: float
) -> Dictionary:
	var offer := _ore_offer(30.0, 100)
	offer["timing"] = {
		"timed": true,
		"urgent": urgent,
		"duration_minutes": duration,
		"expiration_policy": "expire",
		"urgent_reward_multiplier": multiplier,
	}
	return AdapterType.build_active_state(
		offer, _accept_choice(), "mission.runtime.timed_%d" % current_time,
		"start_system", current_time
	)


func _accept_choice() -> Dictionary:
	return {
		"text": "Accepted.",
		"consequence": {
			"credits_immediate": 0,
			"reputation_change": {},
			"combat_multiplier": 1.0,
			"reward_credits_multiplier": 1.0,
			"dialogue_response": "Proceed.",
		},
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
