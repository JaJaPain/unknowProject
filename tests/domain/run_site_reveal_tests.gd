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
	_test_scanned_sites_are_never_lost()
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


func _test_scanned_sites_are_never_lost() -> void:
	var far_but_known: Dictionary = RevealType.reveal_for(9000.0, "basic", true, "Derelict Hauler")
	_expect(
		str(far_but_known["state"]) == RevealType.STATE_IDENTIFIED,
		"A scanned site must stay visible at any range, got %s" % str(far_but_known["state"])
	)
	_expect(
		str(far_but_known["label"]) == "Derelict Hauler",
		"A scanned site should show its real name, got '%s'" % str(far_but_known["label"])
	)
	_expect(
		is_equal_approx(float(far_but_known["alpha"]), 1.0),
		"A scanned site must not fade with distance."
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
