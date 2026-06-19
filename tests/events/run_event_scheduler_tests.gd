extends SceneTree

const EventSchedulerScript = preload("res://scripts/events/EventScheduler.gd")
const EventHistoryScript = preload("res://scripts/events/EventHistory.gd")
const EventTypeScript = preload("res://scripts/events/EventType.gd")
const EventContextScript = preload("res://scripts/events/EventContext.gd")

var _failures: Array[String] = []
var _fired_events: Array[Dictionary] = []


func _initialize() -> void:
	_test_history_record_and_query()
	_test_history_cooldown_check()
	_test_history_save_load()
	_test_scheduler_fires_eligible()
	_test_scheduler_global_cooldown()
	_test_scheduler_ignores_unapplied_events()
	_test_scheduler_type_cooldown()
	_test_scheduler_seed_determinism()
	_test_scheduler_save_restore()

	if _failures.is_empty():
		print("[PASS] Event scheduler tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _make_context(time: int = 100, system: String = "test_sys") -> EventContextScript:
	var ctx = EventContextScript.new()
	ctx.campaign_time = time
	ctx.current_system_id = system
	ctx.just_arrived = true
	return ctx


func _test_history_record_and_query() -> void:
	var h = EventHistoryScript.new()
	h.record("test_event", 100)
	_expect(h.last_time_for_type("test_event") == 100, "Should record and find event at t=100")
	_expect(h.last_time_for_type("other") == -1, "Unknown event should return -1")
	h.record("test_event", 200)
	_expect(h.last_time_for_type("test_event") == 200, "Should find most recent")


func _test_history_cooldown_check() -> void:
	var h = EventHistoryScript.new()
	h.record("test_event", 100)
	_expect(h.minutes_since("test_event", 150) == 50, "50 minutes since t=100 at t=150")
	_expect(h.minutes_since("test_event", 100) == 0, "0 minutes at same time")
	_expect(h.minutes_since("unknown", 200) == 999999, "Unknown event returns large number")
	_expect(h.count_since(90) == 1, "1 event since t=90")
	_expect(h.count_since(101) == 0, "0 events since t=101")


func _test_history_save_load() -> void:
	var h = EventHistoryScript.new()
	h.record("alpha", 50, {"bonus": 10})
	h.record("beta", 100)
	var data = h.to_dict()
	var restored = EventHistoryScript.from_dict(data)
	_expect(restored.last_time_for_type("alpha") == 50, "alpha should roundtrip")
	_expect(restored.last_time_for_type("beta") == 100, "beta should roundtrip")
	var entries = restored.get_entries()
	_expect(entries.size() == 2, "Should have 2 entries")


func _make_test_event(type_id: String, eligible: bool = true, prio: float = 1.0):
	var s = GDScript.new()
	s.source_code = """extends RefCounted

func event_type_id() -> String:
	return "%s"

func is_eligible(_ctx) -> bool:
	return %s

func priority(_ctx) -> float:
	return %f

func execute(_ctx) -> Dictionary:
	return {"type": "%s", "fired": true}
""" % [type_id, str(eligible).to_lower(), prio, type_id]
	s.reload()
	var obj = s.new()
	return obj


func _make_unapplied_test_event(type_id: String):
	var s = GDScript.new()
	s.source_code = """extends RefCounted

func event_type_id() -> String:
	return "%s"

func is_eligible(_ctx) -> bool:
	return true

func priority(_ctx) -> float:
	return 1.0

func execute(_ctx) -> Dictionary:
	return {"type": "%s", "applied": false}
""" % [type_id, type_id]
	s.reload()
	return s.new()


func _test_scheduler_fires_eligible() -> void:
	var sched = EventSchedulerScript.new()
	sched.register_event_type(_make_test_event("test_a", true), 30)
	_fired_events.clear()
	sched.event_triggered.connect(func(tid: String, details: Dictionary):
		_fired_events.append({"type": tid, "details": details})
	)
	var ctx = _make_context(100)
	sched.tick(100, ctx)
	_expect(_fired_events.size() == 1, "Should fire 1 event, got %d" % _fired_events.size())
	if _fired_events.size() > 0:
		_expect(_fired_events[0]["type"] == "test_a", "Should fire test_a")


func _test_scheduler_global_cooldown() -> void:
	var sched = EventSchedulerScript.new()
	sched.register_event_type(_make_test_event("test_b", true), 10)
	var fired_count := [0]
	sched.event_triggered.connect(func(_tid: String, _d: Dictionary):
		fired_count[0] += 1
	)
	sched.tick(100, _make_context(100))
	sched.tick(110, _make_context(110))
	sched.tick(120, _make_context(120))
	_expect(fired_count[0] == 1, "Should fire only 1 due to 30-min global cooldown, got %d" % fired_count[0])
	sched.tick(131, _make_context(131))
	_expect(fired_count[0] == 2, "Should fire again after 30-min global cooldown, got %d" % fired_count[0])


func _test_scheduler_ignores_unapplied_events() -> void:
	var sched = EventSchedulerScript.new()
	sched.register_event_type(_make_unapplied_test_event("failed_event"), 90)
	var fired_count := [0]
	sched.event_triggered.connect(func(_tid: String, _d: Dictionary):
		fired_count[0] += 1
	)
	sched.tick(100, _make_context(100))
	_expect(fired_count[0] == 0, "Unapplied events should not emit.")
	_expect(
		sched.history.last_time_for_type("failed_event") == -1,
		"Unapplied events should not be recorded in history."
	)


func _test_scheduler_type_cooldown() -> void:
	var sched = EventSchedulerScript.new()
	sched.register_event_type(_make_test_event("test_c", true), 90)
	var fired_count := [0]
	sched.event_triggered.connect(func(_tid: String, _d: Dictionary):
		fired_count[0] += 1
	)
	sched.tick(100, _make_context(100))
	_expect(fired_count[0] == 1, "First tick fires")
	sched.tick(160, _make_context(160))
	_expect(fired_count[0] == 1, "60 min later still blocked by 90-min type cooldown")
	sched.tick(200, _make_context(200))
	_expect(fired_count[0] == 2, "100 min later should fire again, got %d" % fired_count[0])


func _test_scheduler_seed_determinism() -> void:
	var results: Array[String] = []
	for _i in range(3):
		var sched = EventSchedulerScript.new()
		sched.register_event_type(_make_test_event("alpha", true, 1.0), 10)
		sched.register_event_type(_make_test_event("beta", true, 1.0), 10)
		var fired_type := [""]
		sched.event_triggered.connect(func(tid: String, _d: Dictionary):
			fired_type[0] = tid
		)
		sched.tick(100, _make_context(100, "same_system"))
		results.append(fired_type[0])
	_expect(results[0] == results[1] and results[1] == results[2],
		"Same context should produce same event: %s" % str(results))


func _test_scheduler_save_restore() -> void:
	var sched = EventSchedulerScript.new()
	sched.register_event_type(_make_test_event("test_d", true), 30)
	sched.tick(100, _make_context(100))
	sched.set_just_arrived(true)
	var state = sched.save_state()
	var sched2 = EventSchedulerScript.new()
	sched2.register_event_type(_make_test_event("test_d", true), 30)
	sched2.restore_state(state)
	_expect(sched2.history.last_time_for_type("test_d") == 100, "History should restore")
