extends SceneTree

const InterceptorEvt = preload("res://scripts/events/types/InterceptorEvent.gd")
const EventCtx = preload("res://scripts/events/EventContext.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_eligible_with_risk_tag()
	_test_not_eligible_without_tag()
	_test_not_eligible_without_arrival()
	_test_priority_scales_with_urgency()
	_test_faction_picks_hostile()
	_test_faction_defaults_reaver()
	_test_count_scales_with_tags()
	_test_execute_returns_details()

	if _failures.is_empty():
		print("[PASS] Interceptor event tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _make_ctx(tags: Array = [], arrived: bool = true, reps: Dictionary = {}) -> EventCtx:
	var ctx = EventCtx.new()
	ctx.campaign_time = 100
	ctx.current_system_id = "test_sys"
	ctx.just_arrived = arrived
	ctx.player_credits = 100
	ctx.reputations = reps
	for tag in tags:
		ctx.active_mission_risk_tags.append(str(tag))
	return ctx


func _test_eligible_with_risk_tag() -> void:
	var evt = InterceptorEvt.new()
	_expect(evt.is_eligible(_make_ctx(["combat_target"])), "Should be eligible with combat_target")
	_expect(evt.is_eligible(_make_ctx(["valuable_cargo"])), "Should be eligible with valuable_cargo")
	_expect(evt.is_eligible(_make_ctx(["urgent"])), "Should be eligible with urgent")


func _test_not_eligible_without_tag() -> void:
	var evt = InterceptorEvt.new()
	_expect(not evt.is_eligible(_make_ctx([])), "Should not be eligible with no tags")
	_expect(not evt.is_eligible(_make_ctx(["unknown_tag"])), "Should not be eligible with unknown tag")


func _test_not_eligible_without_arrival() -> void:
	var evt = InterceptorEvt.new()
	_expect(not evt.is_eligible(_make_ctx(["combat_target"], false)), "Should not be eligible without arrival")


func _test_priority_scales_with_urgency() -> void:
	var evt = InterceptorEvt.new()
	var base_prio = evt.priority(_make_ctx(["valuable_cargo"]))
	var urgent_prio = evt.priority(_make_ctx(["urgent"]))
	var combat_prio = evt.priority(_make_ctx(["combat_target"]))
	_expect(urgent_prio > base_prio, "Urgent should have higher priority than cargo")
	_expect(combat_prio > base_prio, "Combat target should have higher priority than cargo")


func _test_faction_picks_hostile() -> void:
	var evt = InterceptorEvt.new()
	var ctx = _make_ctx(["combat_target"], true, {"zenith": 50.0, "aurelia": -30.0})
	var result = evt.execute(ctx)
	_expect(result["faction"] == "aurelia", "Should pick most hostile faction, got %s" % result["faction"])


func _test_faction_defaults_reaver() -> void:
	var evt = InterceptorEvt.new()
	var ctx = _make_ctx(["valuable_cargo"], true, {"zenith": 50.0, "aurelia": 30.0})
	var result = evt.execute(ctx)
	_expect(result["faction"] == "reaver", "Should default to reaver when no hostile faction, got %s" % result["faction"])


func _test_count_scales_with_tags() -> void:
	var evt = InterceptorEvt.new()
	var c1 = evt.execute(_make_ctx(["valuable_cargo"]))
	var c2 = evt.execute(_make_ctx(["combat_target"]))
	var c3 = evt.execute(_make_ctx(["urgent", "combat_target"]))
	_expect(c1["count"] == 1, "Cargo only should spawn 1, got %d" % c1["count"])
	_expect(c2["count"] == 2, "Combat target should spawn 2, got %d" % c2["count"])
	_expect(c3["count"] == 3, "Urgent + combat should spawn 3, got %d" % c3["count"])


func _test_execute_returns_details() -> void:
	var evt = InterceptorEvt.new()
	var result = evt.execute(_make_ctx(["combat_target"]))
	_expect(result.has("event"), "Should have event key")
	_expect(result.has("faction"), "Should have faction key")
	_expect(result.has("count"), "Should have count key")
	_expect(result.has("system"), "Should have system key")
	_expect(result["event"] == "interceptor", "Event should be interceptor")
	_expect(result["system"] == "test_sys", "System should be test_sys")
