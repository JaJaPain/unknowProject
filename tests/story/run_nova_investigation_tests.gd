extends SceneTree

## N.O.V.A. asks the captain what to do after each investigation scan, and she
## only knows what the scans observed.
##   Godot --headless --path . --script res://tests/story/run_nova_investigation_tests.gd --log-file <path>

const Lines := preload("res://scripts/story/NovaInvestigationLines.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	for recipe in ["survey_discrepancy", "competing_claims", "transmitter_lure", "unstable_archive"]:
		for pick in range(2):
			var first := Lines.decision(recipe, false, false, pick)
			_check(first.ends_with("?"), "%s asks a question after the first scan: %s" % [recipe, first])
	# Before the registry is checked she cannot know the beacon is forged.
	for pick in range(2):
		var early := Lines.decision("transmitter_lure", false, false, pick).to_lower()
		_check(not early.contains("fake") and not early.contains("forged"), "lure line knows the truth too early: %s" % early)
	_check(Lines.decision("transmitter_lure", true, false, 0).contains("forged"), "a mismatch is called out")
	_check(Lines.decision("transmitter_lure", true, true, 0).contains("genuine"), "a match is called out")
	_check(Lines.committed(true, 0) != Lines.committed(false, 0), "the ambush changes her commit line")
	_check(Lines.decision("unknown_recipe", false, false, 5) != "", "unknown recipes fall back")
	# Voiced lines: no shouting, no exclamation (F5 and Kokoro both lift it).
	var all: Array = []
	for pools: Dictionary in Lines.DECISION.values():
		for pool: Array in pools.values():
			all.append_array(pool)
	for pool in [Lines.COMMITTED, Lines.COMMITTED_AMBUSH, Lines.EXTRACTED, Lines.FILED]:
		all.append_array(pool)
	var caps := RegEx.create_from_string("\\b[A-Z]{2,}\\b")
	for line: String in all:
		_check(not line.contains("!") and caps.search(line) == null, "voiced line shouts: %s" % line)
	if _failures.is_empty():
		print("[PASS] N.O.V.A. investigation lines")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
