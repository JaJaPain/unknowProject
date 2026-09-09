extends SceneTree

# A site should be FOUND, not listed. These pin that the overview cannot leak a
# site the player has not detected, and cannot lose one they already have.

const RevealType := preload("res://scripts/domain/SiteRevealModel.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var smoke: Dictionary = RevealType.reveal_for(10.0, "basic", false)
	if smoke.is_empty() or not smoke.has("state"):
		push_error("[FAIL] SiteRevealModel did not compile or reveal.")
		quit(1)
		return
	_test_hidden_beyond_sensor_range()
	_test_better_sensors_see_further()
	_test_contact_fades_in_and_stays_anonymous()
	_test_large_objects_are_never_hidden()
	_test_small_objects_drop_off_beyond_the_drop_range()
	_test_mission_ships_are_detected_further_out()
	_test_group_classification_protects_landmarks()
	_test_gate_visibility_follows_discovery()
	_test_anomalies_are_gated_tightly()
	_test_live_tuning_moves_real_ranges()
	_test_unknown_tier_weakens_rather_than_blinds()
	if _failures.is_empty():
		print("[PASS] Site reveal model tests")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _test_hidden_beyond_sensor_range() -> void:
	var far: Dictionary = RevealType.reveal_for(900.0, "basic", false, "Derelict Hauler")
	_expect(
		str(far["state"]) == RevealType.STATE_HIDDEN,
		"Beyond basic range should be hidden, got %s" % str(far["state"])
	)
	_expect(not bool(far["targetable"]), "A hidden site must not be targetable.")
	_expect(
		str(far["label"]).is_empty(),
		"A hidden site must leak no label, got '%s'" % str(far["label"])
	)


func _test_better_sensors_see_further() -> void:
	var distance := 800.0
	_expect(
		str(RevealType.reveal_for(distance, "basic", false)["state"]) == RevealType.STATE_HIDDEN,
		"Basic sensors should not reach 800 units."
	)
	_expect(
		str(RevealType.reveal_for(distance, "improved", false)["state"]) == RevealType.STATE_CONTACT,
		"Improved sensors should reach 800 units."
	)
	_expect(
		RevealType.range_for_tier("advanced") > RevealType.range_for_tier("improved"),
		"Sensor tiers must strictly improve."
	)


func _test_contact_fades_in_and_stays_anonymous() -> void:
	# Right at the edge it should be barely there, not popped into existence.
	var edge: Dictionary = RevealType.reveal_for(599.0, "basic", false, "Derelict Hauler")
	_expect(
		float(edge["alpha"]) > 0.0 and float(edge["alpha"]) < 0.5,
		"At the edge of range a contact should be faint, got %.2f" % float(edge["alpha"])
	)
	var closer: Dictionary = RevealType.reveal_for(500.0, "basic", false, "Derelict Hauler")
	_expect(
		is_equal_approx(float(closer["alpha"]), 1.0),
		"Past the fade distance a contact should be solid, got %.2f" % float(closer["alpha"])
	)
	# The real name is the reward for scanning, so it must not appear before then.
	for probe in [edge, closer]:
		_expect(
			str(probe["label"]) == RevealType.CONTACT_LABEL,
			"An unscanned site must stay anonymous, got '%s'" % str(probe["label"])
		)


func _test_large_objects_are_never_hidden() -> void:
	# A planet is visible across a system by eye. Requiring sensors to notice one
	# would be absurd, and landmarks are how a player orients themselves.
	for distance in [50.0, 5000.0, 500000.0]:
		var body: Dictionary = RevealType.reveal_for(
			distance, "basic", false, "Kepler IV", RevealType.SIZE_LARGE
		)
		_expect(
			str(body["state"]) == RevealType.STATE_IDENTIFIED,
			"A planet at %.0f units must stay visible, got %s" % [distance, str(body["state"])]
		)
		_expect(
			str(body["label"]) == "Kepler IV",
			"A large body should always show its name, got '%s'" % str(body["label"])
		)
		_expect(
			is_equal_approx(float(body["alpha"]), 1.0),
			"A large body must not fade at %.0f units." % distance
		)
	# It does not need scanning to be named, either.
	var station: Dictionary = RevealType.reveal_for(
		9000.0, "basic", false, "Tycho Relay", RevealType.SIZE_LARGE
	)
	_expect(bool(station["targetable"]), "A station must always be targetable.")


func _test_small_objects_drop_off_beyond_the_drop_range() -> void:
	# Hysteresis: detected at 600, kept out to 1200, gone past that. The gap
	# stops an object parked at sensor range from flickering as the ship drifts.
	var detect := RevealType.range_for_tier("basic")
	var drop := RevealType.drop_range_for_tier("basic")
	_expect(drop > detect, "The drop range must exceed the detection range.")
	var just_outside_detect: Dictionary = RevealType.reveal_for(
		detect + 100.0, "basic", true, "Derelict Hauler", RevealType.SIZE_SMALL
	)
	_expect(
		str(just_outside_detect["state"]) == RevealType.STATE_IDENTIFIED,
		"A known wreck past detection range but inside drop range must persist, got %s"
			% str(just_outside_detect["state"])
	)
	_expect(
		str(just_outside_detect["label"]) == "Derelict Hauler",
		"A known wreck should keep its name while it persists."
	)
	var beyond: Dictionary = RevealType.reveal_for(
		drop + 100.0, "basic", true, "Derelict Hauler", RevealType.SIZE_SMALL
	)
	_expect(
		str(beyond["state"]) == RevealType.STATE_HIDDEN,
		"A known wreck past the drop range must fall off, got %s" % str(beyond["state"])
	)
	_expect(
		str(beyond["label"]).is_empty(),
		"A dropped wreck must leak no label, got '%s'" % str(beyond["label"])
	)
	# Coming back re-shows it as identified: scanning is not undone by distance.
	var returned: Dictionary = RevealType.reveal_for(
		100.0, "basic", true, "Derelict Hauler", RevealType.SIZE_SMALL
	)
	_expect(
		str(returned["state"]) == RevealType.STATE_IDENTIFIED,
		"Returning to a scanned wreck must not require re-scanning, got %s" % str(returned["state"])
	)


func _test_unknown_tier_weakens_rather_than_blinds() -> void:
	# A typo in a ship definition should cost range, not remove sensors entirely.
	_expect(
		is_equal_approx(RevealType.range_for_tier("wat"), RevealType.range_for_tier("basic")),
		"An unknown sensor tier should fall back to basic."
	)
	_expect(
		str(RevealType.reveal_for(100.0, "wat", false)["state"]) == RevealType.STATE_CONTACT,
		"An unknown tier must still detect a close site."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_mission_ships_are_detected_further_out() -> void:
	# Hunting one specific hull among identical contacts is tedium, not
	# difficulty, so mission targets get detection range the player did not earn.
	var ordinary_only := RevealType.range_for_tier("basic") + 50.0
	var ordinary: Dictionary = RevealType.reveal_for(
		ordinary_only, "basic", false, "Courier", RevealType.SIZE_SMALL, false
	)
	_expect(
		str(ordinary["state"]) == RevealType.STATE_HIDDEN,
		"An ordinary ship past sensor range must stay hidden, got %s" % str(ordinary["state"])
	)
	var mission: Dictionary = RevealType.reveal_for(
		ordinary_only, "basic", false, "Courier", RevealType.SIZE_SMALL, true
	)
	_expect(
		str(mission["state"]) == RevealType.STATE_CONTACT,
		"A mission ship at the same distance must be detected, got %s" % str(mission["state"])
	)
	_expect(
		RevealType.detection_range("basic", true) > RevealType.detection_range("basic", false),
		"Mission targets must have a strictly longer detection range."
	)
	# The bonus is slight, not a system-wide reveal.
	_expect(
		RevealType.detection_range("basic", true) < RevealType.range_for_tier("basic") * 3.0,
		"The mission bonus should be slight, not a system-wide reveal."
	)
	# It carries into the drop range too, so a mission ship does not blink out
	# sooner than an ordinary one that was detected further away.
	_expect(
		RevealType.drop_range_for_tier("basic", true) > RevealType.drop_range_for_tier("basic", false),
		"The mission bonus must extend the drop range as well."
	)


func _test_group_classification_protects_landmarks() -> void:
	for large_group in ["station", "celestial"]:
		_expect(
			RevealType.size_class_for_groups([large_group, "persistent_entity"]) == RevealType.SIZE_LARGE,
			"'%s' should classify as large" % large_group
		)
	for small_group in ["ship", "wreckage", "asteroid", "anomaly", "salvager"]:
		_expect(
			RevealType.size_class_for_groups([small_group]) == RevealType.SIZE_SMALL,
			"'%s' should classify as small" % small_group
		)
	# An unknown or empty group set must not silently become a landmark.
	_expect(
		RevealType.size_class_for_groups([]) == RevealType.SIZE_SMALL,
		"An ungrouped entity should default to small, not to always-visible."
	)


func _test_gate_visibility_follows_discovery() -> void:
	# A gate you know is a landmark; a gate you have not found is the hardest
	# thing in the system to see, so a new route is discovered rather than handed
	# over on arrival.
	for known_state in ["known", "blocked", "damaged"]:
		_expect(
			RevealType.size_class_for_groups(["jumpgate"], known_state) == RevealType.SIZE_LARGE,
			"A '%s' gate should stay a landmark" % known_state
		)
	for unknown_state in ["unknown", "rumored", "hidden"]:
		_expect(
			RevealType.size_class_for_groups(["jumpgate"], unknown_state) == RevealType.SIZE_TINY,
			"A '%s' gate should be hard to find" % unknown_state
		)
	# A known gate never drops off, at any distance.
	var known_gate: Dictionary = RevealType.reveal_for(
		50000.0, "basic", false, "Ares Gate", RevealType.SIZE_LARGE
	)
	_expect(
		str(known_gate["state"]) == RevealType.STATE_IDENTIFIED,
		"A known gate must never drop off, got %s" % str(known_gate["state"])
	)
	# An unfound gate must be harder to see than ordinary debris.
	var tiny_range := RevealType.detection_range("basic", false, RevealType.SIZE_TINY)
	var small_range := RevealType.detection_range("basic", false, RevealType.SIZE_SMALL)
	_expect(
		tiny_range < small_range,
		"An unfound gate (%.0f) must be harder to detect than a wreck (%.0f)" % [tiny_range, small_range]
	)
	_expect(tiny_range > 0.0, "An unfound gate must still be findable, not impossible.")
	var far_gate: Dictionary = RevealType.reveal_for(
		small_range - 10.0, "basic", false, "Ares Gate", RevealType.SIZE_TINY
	)
	_expect(
		str(far_gate["state"]) == RevealType.STATE_HIDDEN,
		"An unfound gate at wreck-detection range must still be hidden, got %s" % str(far_gate["state"])
	)
	var close_gate: Dictionary = RevealType.reveal_for(
		tiny_range - 10.0, "basic", false, "Ares Gate", RevealType.SIZE_TINY
	)
	_expect(
		str(close_gate["state"]) == RevealType.STATE_CONTACT,
		"An unfound gate up close must appear as a contact, got %s" % str(close_gate["state"])
	)
	_expect(
		str(close_gate["label"]) == RevealType.CONTACT_LABEL,
		"An unfound gate must not name itself before it is found."
	)


func _test_live_tuning_moves_real_ranges() -> void:
	# The dev panel nudges these statics while the game runs, so a dial that does
	# not actually move a range would waste a whole playtest.
	RevealType.reset_tuning()
	var base := RevealType.detection_range("basic", false, RevealType.SIZE_SMALL)
	RevealType.set_tuning("range_scale", 0.5)
	_expect(
		RevealType.detection_range("basic", false, RevealType.SIZE_SMALL) < base,
		"Lowering range_scale must shorten detection range."
	)
	_expect(
		is_equal_approx(RevealType.get_tuning("range_scale"), 0.5),
		"get_tuning must read back what set_tuning wrote."
	)
	RevealType.set_tuning("tiny_multiplier", 0.5)
	RevealType.reset_tuning()
	_expect(
		is_equal_approx(RevealType.detection_range("basic", false, RevealType.SIZE_SMALL), base),
		"reset_tuning must restore the shipped defaults."
	)
	_expect(
		is_equal_approx(RevealType.get_tuning("unknown_key"), 0.0),
		"An unknown tuning key should read 0.0 rather than crash."
	)


func _test_anomalies_are_gated_tightly() -> void:
	# An anomaly visible across the system is a waypoint, not a discovery. This
	# gate applies whether or not sensor reveal is on, so it is the one range in
	# the model that is always live.
	RevealType.reset_tuning()
	var anomaly_range := RevealType.anomaly_reveal_range()
	var ordinary := RevealType.detection_range("basic", false, RevealType.SIZE_SMALL)
	_expect(
		anomaly_range < ordinary * 0.5,
		"An anomaly (%.0fm) must be far harder to spot than a wreck (%.0fm)"
			% [anomaly_range, ordinary]
	)
	_expect(anomaly_range > 0.0, "An anomaly must still be findable by flying near it.")
	_expect(
		is_equal_approx(anomaly_range, ordinary * 0.25),
		"Abe set anomalies to a quarter of normal range; got %.0fm of %.0fm"
			% [anomaly_range, ordinary]
	)
	# Tunable live, like the rest.
	RevealType.set_tuning("anomaly_range_share", 0.5)
	_expect(
		RevealType.anomaly_reveal_range() > anomaly_range,
		"The anomaly dial must move the real range."
	)
	RevealType.reset_tuning()
	_expect(
		is_equal_approx(RevealType.anomaly_reveal_range(), anomaly_range),
		"reset_tuning must restore the anomaly range."
	)
