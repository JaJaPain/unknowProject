extends SceneTree

## The wreck field event's rules (docs/wreck_field_event_plan_2026_10_07.md):
## when it starts, what happened there, and a clue for every scan point.

const Event := preload("res://scripts/story/WreckFieldEvent.gd")
const Field := preload("res://scripts/world/WreckField.gd")

var _failures: Array = []


func _initialize() -> void:
	_test_can_start()
	_test_kind_for()
	_test_clues()
	if _failures.is_empty():
		print("[PASS] Wreck field event")
		quit(0)
	else:
		for f in _failures:
			push_error("[FAIL] " + str(f))
		quit(1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)


func _ctx(overrides: Dictionary = {}) -> Dictionary:
	var ctx := {"started": false, "tutorial_done": true, "depth": Event.MIN_DEPTH, "visits": Event.MIN_VISITS,
		"stage": "hidden", "lodestar_id": "lighthouse", "calm": true}
	ctx.merge(overrides, true)
	return ctx


func _test_can_start() -> void:
	_check(Event.can_start(_ctx()), "starts mid-season in a deeper system")
	_check(not Event.can_start(_ctx({"started": true})), "once per campaign")
	_check(not Event.can_start(_ctx({"tutorial_done": false})), "not during the tutorial")
	_check(not Event.can_start(_ctx({"depth": Event.MIN_DEPTH - 1})), "not near home")
	_check(not Event.can_start(_ctx({"visits": Event.MIN_VISITS - 1})), "not too early")
	_check(not Event.can_start(_ctx({"stage": "revealed"})), "only while the main story is hidden (its clues count)")
	_check(not Event.can_start(_ctx({"calm": false})), "not docked or in combat")
	_check(not Event.can_start(_ctx({"lodestar_id": "quiet_war"})), "not when the Destination is the same wrecks")


func _test_kind_for() -> void:
	_check(Event.kind_for("proxy_violence", 1) == "battle", "hired guns -> a battle")
	_check(Event.kind_for("sabotage", 1) == "sabotage", "sabotage -> sabotage")
	_check(Event.kind_for("forged_records", 1) == "collision", "forged records -> a collision")
	_check(Event.kind_for("slow_infiltration", 1) == "mutiny", "infiltration -> a mutiny")
	var drawn := {}
	for seed_value in 8:
		drawn[Event.kind_for("debt_leverage", seed_value)] = true
	_check(drawn.size() == Event.KINDS.size(), "other methods draw every kind from the seed")


func _test_clues() -> void:
	for kind in Event.KINDS:
		for p in Field.SCAN_POINTS:
			var text := Event.clue(kind, str(p["id"]))
			_check(not text.is_empty(), "a clue for %s at %s" % [kind, p["id"]])
			_check(load("res://scripts/story/ReservedTopics.gd").is_clean(text), "clue clean: %s" % text)
	for line in [Event.LINE_DETECT, Event.LINE_ARRIVAL, Event.LINE_RADIATION, Event.LINE_FIRST_THREAD, Event.LINE_DONE]:
		_check(load("res://scripts/story/ReservedTopics.gd").is_clean(line), "line clean: %s" % line)
