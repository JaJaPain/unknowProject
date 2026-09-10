extends SceneTree

# Selection is where "fresh" quietly stops being fresh. These pin the three rules
# that prevent it: retire on SHOWN, no immediate replay across a pool change, and
# a cycle that survives a save.

const SelectorType := preload("res://scripts/domain/InvestigationSelector.gd")

var _failures: Array[String] = []
const FOUR := [
	"mission_shape.competing_claims",
	"mission_shape.survey_discrepancy",
	"mission_shape.transmitter_lure",
	"mission_shape.unstable_archive",
]


func _initialize() -> void:
	# A GDScript parse failure still lets the rest of a suite print [PASS]: this
	# suite printed PASS over a "function not found" error. Prove the module is
	# really callable by exercising the whole path once before asserting.
	var smoke: Dictionary = SelectorType.empty_state(1)
	var smoke_offer: Dictionary = SelectorType.publish(smoke, FOUR, "smoke")
	if smoke_offer.is_empty() or str(smoke_offer.get("shape_id", "")).is_empty():
		push_error("[FAIL] InvestigationSelector did not compile or publish.")
		quit(1)
		return
	_test_repeated_opens_return_the_same_offer()
	_test_shape_retires_when_shown_not_when_accepted()
	_test_reservation_does_not_burn_a_shape()
	_test_pool_change_does_not_replay_immediately()
	_test_cycle_survives_a_save()
	if _failures.is_empty():
		print("[PASS] Investigation selector tests")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


# Opening the panel twice must not roll a different contract at the player.
func _test_repeated_opens_return_the_same_offer() -> void:
	var state: Dictionary = SelectorType.empty_state(1234)
	var first: Dictionary = SelectorType.publish(state, FOUR, "offer.a")
	var again: Dictionary = SelectorType.publish(state, FOUR, "offer.a")
	_expect(not first.is_empty(), "First publish should yield an offer.")
	_expect(
		str(first.get("shape_id", "")) == str(again.get("shape_id", "")),
		"Re-opening must return the same shape, got %s then %s" % [
			str(first.get("shape_id")), str(again.get("shape_id"))
		]
	)
	_expect(
		int(first.get("seed", 0)) == int(again.get("seed", -1)),
		"Re-opening must return the same seed, or the mission truth would change."
	)


# A declined offer the player already read is not new content.
func _test_shape_retires_when_shown_not_when_accepted() -> void:
	var state: Dictionary = SelectorType.empty_state(99)
	var seen: Dictionary = {}
	for i in range(FOUR.size()):
		var offer: Dictionary = SelectorType.publish(state, FOUR, "offer.%d" % i)
		var shape := str(offer.get("shape_id", ""))
		_expect(
			not seen.has(shape),
			"Shape %s was offered twice inside one cycle." % shape
		)
		seen[shape] = true
		# Declined, never accepted -- it must still be retired.
		SelectorType.release(state, "offer.%d" % i)
	_expect(
		seen.size() == FOUR.size(),
		"A full cycle should show every shape once, saw %d." % seen.size()
	)


# Preparation ahead of display must not consume a shape the player never saw.
func _test_reservation_does_not_burn_a_shape() -> void:
	var state: Dictionary = SelectorType.empty_state(7)
	var reserved: Dictionary = SelectorType.reserve(state, FOUR, "offer.r")
	_expect(not reserved.is_empty(), "Reservation should yield a candidate.")
	_expect(
		not bool(reserved.get("published", true)),
		"A reservation is not yet published."
	)
	_expect(
		str(state.get("last_shape_id", "")) == "",
		"Reserving must not retire anything -- the player has seen nothing."
	)
	# Publishing the reservation keeps its seed, so prepared content stays valid.
	var published: Dictionary = SelectorType.publish(state, FOUR, "offer.r")
	_expect(
		int(published.get("seed", 0)) == int(reserved.get("seed", -1)),
		"Publishing must keep the reserved seed, or prepared content is wasted."
	)
	_expect(
		str(state.get("last_shape_id", "")) == str(published.get("shape_id", "")),
		"Publishing retires the shape campaign-wide."
	)


# A changed eligible set starts a different cycle, so the bag alone cannot stop
# an immediate replay. last_shape_id is what does.
func _test_pool_change_does_not_replay_immediately() -> void:
	var state: Dictionary = SelectorType.empty_state(31337)
	var first: Dictionary = SelectorType.publish(state, FOUR, "offer.1")
	var shown := str(first.get("shape_id", ""))
	# A smaller eligible set that still contains the shape just shown.
	var narrowed := [shown, "mission_shape.unstable_archive"]
	if shown == "mission_shape.unstable_archive":
		narrowed = [shown, "mission_shape.survey_discrepancy"]
	var second: Dictionary = SelectorType.publish(state, narrowed, "offer.2")
	_expect(
		str(second.get("shape_id", "")) != shown,
		"A pool change must not immediately replay '%s'." % shown
	)
	# With only one eligible shape left, repeating is unavoidable and allowed --
	# the guarantee is explicitly not made across differing sets.
	var single: Dictionary = SelectorType.publish(state, [shown], "offer.3")
	_expect(
		str(single.get("shape_id", "")) == shown,
		"With one eligible shape it must still be offered rather than nothing."
	)


# A checkpoint must restore the cycle, not reshuffle and re-offer what was seen.
func _test_cycle_survives_a_save() -> void:
	var state: Dictionary = SelectorType.empty_state(555)
	var before: Array[String] = []
	for i in range(2):
		var offer: Dictionary = SelectorType.publish(state, FOUR, "offer.%d" % i)
		before.append(str(offer.get("shape_id", "")))
		SelectorType.release(state, "offer.%d" % i)
	# Round-trip through JSON exactly as a save would.
	var restored: Dictionary = JSON.parse_string(JSON.stringify(state))
	_expect(restored != null, "Selection state must survive a JSON round trip.")
	var after: Array[String] = []
	for i in range(2, 4):
		var offer: Dictionary = SelectorType.publish(restored, FOUR, "offer.%d" % i)
		after.append(str(offer.get("shape_id", "")))
	for shape in after:
		_expect(
			not before.has(shape),
			"'%s' was replayed after a reload; the cycle did not restore." % shape
		)
	_expect(
		after.size() == 2 and after[0] != after[1],
		"The restored cycle should keep handing out fresh shapes, got %s" % str(after)
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
