extends SceneTree

const ChallengeBudgetType := preload("res://scripts/story/ChallengeBudget.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_ore_amount_uses_cargo_capacity_and_mining_rate()
	_test_kill_count_uses_combat_vs_enemy_strength()
	_test_budget_sets_difficulty_deadline_and_reward()
	_test_low_hull_forces_recovery_band()

	if _failures.is_empty():
		print("[PASS] Challenge budget tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_ore_amount_uses_cargo_capacity_and_mining_rate() -> void:
	var small_hold := ChallengeBudgetType.ore_amount_for_duration(30, {
		"cargo_capacity": 20.0,
		"mining_rate_per_minute": 12.0,
	})
	var large_hold := ChallengeBudgetType.ore_amount_for_duration(30, {
		"cargo_capacity": 80.0,
		"mining_rate_per_minute": 12.0,
	})
	_expect(small_hold <= 20.0, "Ore amount should respect small cargo capacity.")
	_expect(large_hold > small_hold, "Larger cargo capacity should allow larger ore jobs.")


func _test_kill_count_uses_combat_vs_enemy_strength() -> void:
	var weak_ship := ChallengeBudgetType.kill_count_for_duration(30, {
		"combat_rating": 0.75,
		"enemy_strength": 1.5,
	})
	var strong_ship := ChallengeBudgetType.kill_count_for_duration(30, {
		"combat_rating": 2.0,
		"enemy_strength": 1.0,
	})
	_expect(strong_ship > weak_ship, "Stronger combat rating should support more kills.")
	_expect(weak_ship >= 1, "Kill count should never fall below one.")


func _test_budget_sets_difficulty_deadline_and_reward() -> void:
	var budget := ChallengeBudgetType.budget_for_candidate(
		{"objective_type": "KILL_SHIPS", "urgent": true},
		{"combat_rating": 1.0, "enemy_strength": 1.0, "hull_ratio": 0.9},
		{"pressure": 3}
	)
	_expect(
		str(budget.get("difficulty_band", "")) == ChallengeBudgetType.BAND_PRESSURED,
		"Pressure/urgent candidate should be pressured."
	)
	_expect(
		int(budget.get("deadline_minutes", 0)) > int(budget.get("target_duration_minutes", 0)),
		"Pressured budget should set a deadline longer than target duration."
	)
	_expect(
		float(budget.get("reward_multiplier", 0.0)) > 1.0,
		"Pressured budget should increase reward multiplier."
	)


func _test_low_hull_forces_recovery_band() -> void:
	var budget := ChallengeBudgetType.budget_for_candidate(
		{"objective_type": "RECOVER_COMBAT_DROP"},
		{"combat_rating": 2.0, "enemy_strength": 1.0, "hull_ratio": 0.2},
		{"pressure": 5}
	)
	_expect(
		str(budget.get("difficulty_band", "")) == ChallengeBudgetType.BAND_ROUTINE,
		"Low hull should force a routine recovery band instead of punishment spiral."
	)
