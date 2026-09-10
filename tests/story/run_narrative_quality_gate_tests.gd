extends SceneTree

# The quality gate's ONE warning type is "unexplained_reference". Before this it
# fired on every sentence-initial capital, so a session produced hundreds of
# false positives and a genuine unexplained reference was invisible among them.
# A diagnostic nobody can read is worse than no diagnostic: it costs attention
# and returns nothing.

const GateType := preload("res://scripts/story/NarrativeQualityGate.gd")
const LedgerType := preload("res://scripts/story/NarrativeFingerprintLedger.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var probe = LedgerType.new()
	if probe == null or not probe.has_method("inspect"):
		push_error("[FAIL] NarrativeFingerprintLedger did not compile.")
		quit(1)
		return
	_test_sentence_openers_do_not_warn()
	_test_real_entities_still_warn()
	_test_known_aliases_are_accepted()
	_test_mid_sentence_capitals_are_still_caught()
	if _failures.is_empty():
		print("[PASS] Narrative quality gate tests")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _warnings_for(text: String, aliases: Array = []) -> Array:
	var result: Dictionary = GateType.validate_line(text, LedgerType.new(), "test", aliases)
	return result.get("warnings", [])


func _test_sentence_openers_do_not_warn() -> void:
	# Real lines from N.O.V.A.'s pools. Every one of these used to warn purely for
	# starting a sentence with a capital letter.
	for line in [
		"Docked. Enjoy the recycled air; I certainly am.",
		"Structural integrity critical. Be clever, quickly.",
		"Clamps locked. Wake me if anything catches fire.",
		"Threat neutralized. Still in one piece.",
		"Welcome back. Nothing exploded while you were gone.",
	]:
		var w := _warnings_for(line)
		_expect(w.is_empty(), "Sentence openers should not warn: '%s' -> %s" % [line.substr(0, 34), str(w)])


func _test_real_entities_still_warn() -> void:
	# The check must still EARN its place: an unexplained proper noun mid-sentence
	# is exactly what it exists to surface.
	var w := _warnings_for("The cargo is bound for Tannhauser before the week is out.")
	_expect(
		w.size() == 1 and str(w[0]).contains("Tannhauser"),
		"An unexplained mid-sentence entity must warn, got %s" % str(w)
	)


func _test_known_aliases_are_accepted() -> void:
	# Passing the game's real names is the other half of the fix: without them
	# every faction and character warns forever.
	var line := "The cargo is bound for Greywake, and Kaelen wants it quietly."
	_expect(
		not _warnings_for(line).is_empty(),
		"Without aliases these names should warn (proving the test is live)."
	)
	_expect(
		_warnings_for(line, ["Greywake", "Kaelen"]).is_empty(),
		"Known aliases must silence the warning, got %s" % str(_warnings_for(line, ["Greywake", "Kaelen"]))
	)


func _test_mid_sentence_capitals_are_still_caught() -> void:
	# Guard the boundary: a capital after a comma is mid-sentence, not an opener.
	var w := _warnings_for("We ran, and Vashti was already gone.")
	_expect(
		w.size() == 1 and str(w[0]).contains("Vashti"),
		"A capital after a comma is mid-sentence and must warn, got %s" % str(w)
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
