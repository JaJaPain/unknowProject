extends SceneTree

# Phase 8A slice 1: raw semantic movement events. Verifies the event
# registry, the validated GlobalState channel, and the PlayerShip/GameRoot
# emitter wiring (behaviorally where a bare instance allows it, at source
# level for tree-dependent paths).

const EventsType := preload("res://scripts/story/ShipMovementEvents.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_registry_matches_phase_8a_contract()
	_test_global_state_channel_validates_event_ids()
	_test_player_ship_emits_dock_boost_evasive_hull_events()
	_test_remaining_emitters_are_wired()

	if _failures.is_empty():
		print("[PASS] Ship movement event tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_registry_matches_phase_8a_contract() -> void:
	var expected: Array[String] = [
		"boost_activated",
		"boost_rejected",
		"autopilot_started",
		"autopilot_retargeted",
		"autopilot_cancelled",
		"evasive_maneuver",
		"gate_departure",
		"system_arrival",
		"docked",
		"undocked",
		"route_replanned",
		"severe_hull_impact",
	]
	_expect(
		EventsType.all() == expected,
		"Ship movement event registry does not match the Phase 8A contract."
	)
	for event_id in expected:
		_expect(
			EventsType.is_valid(event_id),
			"Registered movement event was not valid: %s" % event_id
		)
	_expect(
		not EventsType.is_valid("player_sneezed"),
		"Unknown movement event id was accepted."
	)


func _test_global_state_channel_validates_event_ids() -> void:
	var gs = root.get_node("GlobalState")
	var received: Array = []
	var listener := func(event_id: String, context: Dictionary) -> void:
		received.append({"event_id": event_id, "context": context})
	gs.ship_movement_event.connect(listener)
	_expect(
		gs.emit_ship_movement_event(
			EventsType.BOOST_ACTIVATED,
			{"duration_seconds": 5.0}
		),
		"Valid movement event was rejected by the GlobalState channel."
	)
	_expect(
		not gs.emit_ship_movement_event("director_secret_reveal", {}),
		"Unknown movement event id passed the GlobalState channel."
	)
	gs.ship_movement_event.disconnect(listener)
	_expect(
		received.size() == 1
			and str(received[0]["event_id"]) == EventsType.BOOST_ACTIVATED
			and float(received[0]["context"].get("duration_seconds", 0.0))
				== 5.0,
		"GlobalState channel did not deliver exactly the valid event."
	)


func _test_player_ship_emits_dock_boost_evasive_hull_events() -> void:
	var gs = root.get_node("GlobalState")
	var ship_script: GDScript = load("res://scripts/PlayerShip.gd")
	var ship = ship_script.new()
	var received: Array = []
	var listener := func(event_id: String, context: Dictionary) -> void:
		received.append({"event_id": event_id, "context": context})
	gs.ship_movement_event.connect(listener)

	# Dock/undock choke point: setter emits only on change.
	ship.is_docked = true
	ship.is_docked = true
	ship.is_docked = false

	# Boost rejected while docked. (The success path plays audio, which the
	# headless AudioManager cannot do — it is covered at source level below.)
	ship.is_docked = true
	_expect(
		not ship.activate_boost(),
		"Boost unexpectedly activated while docked."
	)
	ship.is_docked = false

	# Severe hull impact: a hit at/above the fraction emits, a scratch does not.
	ship.take_damage(15.0)
	ship.take_damage(1.0)

	gs.ship_movement_event.disconnect(listener)
	ship.free()

	var ids: Array = []
	for entry in received:
		ids.append(str(entry["event_id"]))
	_expect(
		ids == [
			"docked",
			"undocked",
			"docked",
			"boost_rejected",
			"undocked",
			"severe_hull_impact",
		],
		"PlayerShip movement events did not match the expected sequence: %s"
			% str(ids)
	)
	for entry in received:
		if str(entry["event_id"]) == "boost_rejected" \
				and str(entry["context"].get("reason", "")) == "docked":
			return
	_failures.append(
		"boost_rejected while docked did not carry reason=docked."
	)


func _test_remaining_emitters_are_wired() -> void:
	var ship_file := FileAccess.open(
		"res://scripts/PlayerShip.gd", FileAccess.READ
	)
	var game_root_file := FileAccess.open(
		"res://scripts/GameRoot.gd", FileAccess.READ
	)
	_expect(
		ship_file != null and game_root_file != null,
		"Could not inspect movement event emitter wiring."
	)
	if ship_file == null or game_root_file == null:
		return
	var ship_source := ship_file.get_as_text()
	var game_root_source := game_root_file.get_as_text()
	_expect(
		ship_source.contains("ShipMovementEventsType.AUTOPILOT_RETARGETED")
			and ship_source.contains("ShipMovementEventsType.AUTOPILOT_STARTED")
			and ship_source.contains(
				"ShipMovementEventsType.AUTOPILOT_CANCELLED"
			)
			and ship_source.contains("ShipMovementEventsType.ROUTE_REPLANNED")
			and ship_source.contains(
				"ShipMovementEventsType.SEVERE_HULL_IMPACT"
			)
			and ship_source.contains("ShipMovementEventsType.BOOST_ACTIVATED")
			and ship_source.contains(
				"ShipMovementEventsType.EVASIVE_MANEUVER"
			),
		"PlayerShip is missing autopilot/boost/route/hull movement emitters."
	)
	_expect(
		game_root_source.contains("ShipMovementEventsType.GATE_DEPARTURE")
			and game_root_source.contains(
				"ShipMovementEventsType.SYSTEM_ARRIVAL"
			),
		"GameRoot is missing gate departure/system arrival emitters."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
