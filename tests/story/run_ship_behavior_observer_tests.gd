extends SceneTree

# Phase 8A slice 2: ShipBehaviorObserver folds raw movement events into
# semantic events deterministically (time injected through observe()).

const ObserverType := preload("res://scripts/story/ShipBehaviorObserver.gd")
const EventsType := preload("res://scripts/story/ShipMovementEvents.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_boost_again_quickly()
	_test_changed_mind_again()
	_test_returned_to_same_station()
	_test_clean_and_rough_transits()

	if _failures.is_empty():
		print("[PASS] Ship behavior observer tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _capture(observer: Node) -> Array:
	var received: Array = []
	observer.semantic_movement_event.connect(
		func(event_id: String, context: Dictionary) -> void:
			received.append({"event_id": event_id, "context": context})
	)
	return received


func _ids(received: Array) -> Array:
	var ids: Array = []
	for entry in received:
		ids.append(str(entry["event_id"]))
	return ids


func _test_boost_again_quickly() -> void:
	var observer := ObserverType.new()
	var received := _capture(observer)
	observer.observe(EventsType.BOOST_ACTIVATED, {}, 100.0)
	observer.observe(EventsType.BOOST_ACTIVATED, {}, 165.0)
	observer.observe(EventsType.BOOST_ACTIVATED, {}, 400.0)
	observer.free()
	_expect(
		_ids(received) == ["boost_again_quickly"],
		"Quick re-boost aggregation was wrong: %s" % str(_ids(received))
	)
	if received.size() == 1:
		_expect(
			absf(
				float(
					received[0]["context"].get("seconds_since_last_boost", 0.0)
				) - 65.0
			) < 0.01,
			"Quick re-boost did not report the gap since the last boost."
		)


func _test_changed_mind_again() -> void:
	var observer := ObserverType.new()
	var received := _capture(observer)
	# Three churn events inside the window fire once, then the tally resets.
	observer.observe(
		EventsType.AUTOPILOT_RETARGETED, {"mode": "APPROACH"}, 10.0
	)
	observer.observe(EventsType.AUTOPILOT_CANCELLED, {"mode": "APPROACH"}, 20.0)
	observer.observe(EventsType.AUTOPILOT_RETARGETED, {"mode": "ORBIT"}, 30.0)
	observer.observe(EventsType.AUTOPILOT_CANCELLED, {"mode": "ORBIT"}, 40.0)
	# Spread-out changes never fire.
	observer.observe(
		EventsType.AUTOPILOT_RETARGETED, {"mode": "APPROACH"}, 200.0
	)
	observer.observe(
		EventsType.AUTOPILOT_RETARGETED, {"mode": "APPROACH"}, 300.0
	)
	observer.free()
	_expect(
		_ids(received) == ["changed_mind_again"],
		"Autopilot churn aggregation was wrong: %s" % str(_ids(received))
	)


func _test_returned_to_same_station() -> void:
	var observer := ObserverType.new()
	var received := _capture(observer)
	# First dock at Kova: no semantic event.
	observer.observe(
		EventsType.AUTOPILOT_STARTED,
		{"mode": "DOCK", "target_name": "KovaStation"},
		100.0
	)
	observer.observe(EventsType.DOCKED, {}, 110.0)
	observer.observe(EventsType.UNDOCKED, {}, 200.0)
	# Prompt return to Kova: fires.
	observer.observe(
		EventsType.AUTOPILOT_STARTED,
		{"mode": "DOCK", "target_name": "KovaStation"},
		250.0
	)
	observer.observe(EventsType.DOCKED, {}, 260.0)
	observer.observe(EventsType.UNDOCKED, {}, 300.0)
	# Different station: quiet.
	observer.observe(
		EventsType.AUTOPILOT_STARTED,
		{"mode": "DOCK", "target_name": "MainStation"},
		350.0
	)
	observer.observe(EventsType.DOCKED, {}, 360.0)
	observer.observe(EventsType.UNDOCKED, {}, 400.0)
	# Back to Main, but far outside the return window: quiet.
	observer.observe(
		EventsType.AUTOPILOT_STARTED,
		{"mode": "DOCK", "target_name": "MainStation"},
		2000.0
	)
	observer.observe(EventsType.DOCKED, {}, 2010.0)
	observer.free()
	_expect(
		_ids(received) == ["returned_to_same_station"],
		"Same-station return aggregation was wrong: %s" % str(_ids(received))
	)
	if received.size() == 1:
		_expect(
			str(received[0]["context"].get("station_name", ""))
				== "KovaStation",
			"Same-station return did not name the station."
		)


func _test_clean_and_rough_transits() -> void:
	var observer := ObserverType.new()
	var received := _capture(observer)
	# Clean transit long enough to note.
	observer.observe(EventsType.GATE_DEPARTURE, {}, 100.0)
	observer.observe(
		EventsType.SYSTEM_ARRIVAL, {"system_id": "system.test"}, 145.0
	)
	# Short hop: quiet.
	observer.observe(EventsType.GATE_DEPARTURE, {}, 200.0)
	observer.observe(
		EventsType.SYSTEM_ARRIVAL, {"system_id": "system.test"}, 205.0
	)
	# Trouble mid-transit: rough arrival even on a short hop.
	observer.observe(EventsType.GATE_DEPARTURE, {}, 300.0)
	observer.observe(EventsType.SEVERE_HULL_IMPACT, {}, 305.0)
	observer.observe(
		EventsType.SYSTEM_ARRIVAL, {"system_id": "system.rough"}, 310.0
	)
	# Arrival with no departure recorded: quiet.
	observer.observe(
		EventsType.SYSTEM_ARRIVAL, {"system_id": "system.test"}, 400.0
	)
	observer.free()
	_expect(
		_ids(received) == ["clean_long_transit", "rough_arrival"],
		"Transit aggregation was wrong: %s" % str(_ids(received))
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
