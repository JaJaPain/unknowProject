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
	_test_semantic_rate_limiting()
	_test_safe_context_enrichment()
	_test_movement_path_never_touches_the_model()

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


func _test_semantic_rate_limiting() -> void:
	# Per-event cooldown: a second quick re-boost inside 180s is suppressed
	# but still counted; a later one fires again.
	var observer := ObserverType.new()
	var received := _capture(observer)
	observer.observe(EventsType.BOOST_ACTIVATED, {}, 100.0)
	observer.observe(EventsType.BOOST_ACTIVATED, {}, 165.0)
	observer.observe(EventsType.BOOST_ACTIVATED, {}, 230.0)
	observer.observe(EventsType.BOOST_ACTIVATED, {}, 460.0)
	observer.observe(EventsType.BOOST_ACTIVATED, {}, 520.0)
	var snapshot: Dictionary = observer.state_snapshot()
	observer.free()
	_expect(
		_ids(received) == ["boost_again_quickly", "boost_again_quickly"],
		"Per-event cooldown did not gate repeat boost nags: %s"
			% str(_ids(received))
	)
	_expect(
		int(
			(snapshot.get("suppressed_counts", {}) as Dictionary).get(
				"boost_again_quickly", 0
			)
		) == 1,
		"Suppressed semantic event was not counted in the state snapshot."
	)

	# Global spacing: a different semantic event right after one fired is
	# suppressed, and the observer state still reflects the transit.
	var observer2 := ObserverType.new()
	var received2 := _capture(observer2)
	observer2.observe(EventsType.BOOST_ACTIVATED, {}, 100.0)
	observer2.observe(EventsType.BOOST_ACTIVATED, {}, 160.0)
	observer2.observe(EventsType.GATE_DEPARTURE, {}, 165.0)
	observer2.observe(EventsType.SEVERE_HULL_IMPACT, {}, 170.0)
	observer2.observe(
		EventsType.SYSTEM_ARRIVAL, {"system_id": "system.rough"}, 175.0
	)
	var snapshot2: Dictionary = observer2.state_snapshot()
	observer2.free()
	_expect(
		_ids(received2) == ["boost_again_quickly"],
		"Global spacing did not gate back-to-back semantic events: %s"
			% str(_ids(received2))
	)
	_expect(
		int(
			(snapshot2.get("suppressed_counts", {}) as Dictionary).get(
				"rough_arrival", 0
			)
		) == 1
			and not bool(snapshot2.get("in_transit", true)),
		"Suppressed rough arrival was not reflected in the state snapshot."
	)


func _test_safe_context_enrichment() -> void:
	var observer := ObserverType.new()
	var received := _capture(observer)
	observer.context_provider = func() -> Dictionary:
		return {
			"hull_band": "worn",
			"mission_beat": "Kova Smelter Feed (DELIVER_ORE)",
			"system_status": "new",
			"route_deviation": "in_mission_system",
			# A provider key colliding with an event field must not win.
			"seconds_since_last_boost": -1.0,
		}
	observer.observe(EventsType.GATE_DEPARTURE, {}, 50.0)
	observer.observe(EventsType.BOOST_ACTIVATED, {}, 100.0)
	observer.observe(EventsType.BOOST_ACTIVATED, {}, 165.0)
	observer.free()
	_expect(
		_ids(received) == ["boost_again_quickly"],
		"Context enrichment test emitted the wrong events: %s"
			% str(_ids(received))
	)
	if received.size() != 1:
		return
	var context: Dictionary = received[0]["context"]
	_expect(
		str(context.get("hull_band", "")) == "worn"
			and str(context.get("mission_beat", ""))
				== "Kova Smelter Feed (DELIVER_ORE)"
			and str(context.get("system_status", "")) == "new"
			and str(context.get("route_deviation", ""))
				== "in_mission_system",
		"Provider safe context was not merged onto the semantic event."
	)
	_expect(
		absf(float(context.get("seconds_since_last_boost", 0.0)) - 65.0)
			< 0.01,
		"Provider context overwrote an event-specific field."
	)
	var recent: Array = context.get("recent_actions", [])
	_expect(
		recent == ["gate_departure", "boost_activated", "boost_activated"],
		"Recent action streak was wrong: %s" % str(recent)
	)


# Phase 8A tripwire: no code in the movement-event path may call the model.
# Movement reactions must only ever consume prepared line banks (Phase 8B).
func _test_movement_path_never_touches_the_model() -> void:
	for path in [
		"res://scripts/story/ShipMovementEvents.gd",
		"res://scripts/story/ShipBehaviorObserver.gd",
	]:
		var file := FileAccess.open(path, FileAccess.READ)
		_expect(file != null, "Could not audit movement path: %s" % path)
		if file == null:
			continue
		var source := file.get_as_text()
		_expect(
			not source.contains("LLMInterface")
				and not source.contains("Ollama")
				and not source.contains("http"),
			"Movement path references the model layer: %s" % path
		)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
