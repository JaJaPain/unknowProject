extends SceneTree

const LedgerType := preload("res://scripts/story/NarrativeFingerprintLedger.gd")
var _failures: Array[String] = []


func _initialize() -> void:
	_test_exact_duplicate_is_rejected()
	_test_near_duplicate_is_rejected()
	_test_distinct_line_passes()
	_test_round_trip_keeps_history()
	if _failures.is_empty():
		print("[PASS] Narrative fingerprint ledger tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_exact_duplicate_is_rejected() -> void:
	var ledger = LedgerType.new()
	ledger.register("This coffee has gone cold again.", "lounge")
	_expect(str(ledger.inspect("This coffee has gone cold again!", "lounge").get("reason", "")) == "exact_duplicate", "Punctuation-only repeat must be exact duplicate.")


func _test_near_duplicate_is_rejected() -> void:
	var ledger = LedgerType.new()
	ledger.register("This coffee has gone cold again at the station bar.", "lounge")
	_expect(str(ledger.inspect("That coffee has gone cold again at the station bar.", "lounge").get("reason", "")) == "near_duplicate", "Near-repeat must report near_duplicate.")


func _test_distinct_line_passes() -> void:
	var ledger = LedgerType.new()
	ledger.register("This coffee has gone cold again at the station bar.", "lounge")
	_expect(bool(ledger.inspect("Patrols are holding freighters for a second manifest check.", "lounge").get("ok", false)), "Distinct subject matter must pass.")


func _test_round_trip_keeps_history() -> void:
	var ledger = LedgerType.new()
	ledger.register("The relay went dark before the gate cleared.", "lounge", {"contact": "npc.test"})
	var restored = LedgerType.new()
	restored.load_dict(ledger.to_dict())
	_expect(str(restored.inspect("The relay went dark before the gate cleared.", "lounge").get("reason", "")) == "exact_duplicate", "Persisted ledger lost exact history.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
