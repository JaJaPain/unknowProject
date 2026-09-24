extends SceneTree

const LibraryType := preload("res://scripts/story/premise/PremiseCardLibrary.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_real_deck_loads_completely()
	_test_bad_cards_are_skipped_not_fatal()
	_test_helpers()
	if _failures.is_empty():
		print("[PASS] Premise card library tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_real_deck_loads_completely() -> void:
	var library = LibraryType.new()
	var result = library.load_from_dir()
	_check(result.is_valid(), "real deck failed to load: %s" % result.summary())
	_check(library.size() >= 100, "expected 100+ approved cards, got %d" % library.size())
	_check(library.skipped.is_empty(), "approved cards were skipped: %s" % str(library.skipped))
	for card_id in library.ids():
		_check(card_id.begins_with("premise."), "odd card id %s" % card_id)


func _minimal_card(card_id: String) -> Dictionary:
	return {
		"id": card_id, "schema_version": 1, "scale": "personal",
		"roles": [{"id": "asker", "kind": "person"}, {"id": "dock", "kind": "place"}],
		"beats": [{"n": 1, "function": "setup", "missions": [
			{"verb": "delivery_courier", "requester": "asker", "target": "dock",
			 "outcome_tags": ["delivered"], "routes": {"delivered": "resolution:good"}}]}],
		"resolutions": [{"id": "good"}, {"id": "bad"}],
		"default_resolution": "bad",
	}


func _test_bad_cards_are_skipped_not_fatal() -> void:
	var good := _minimal_card("premise.good")
	var bad_verb := _minimal_card("premise.bad_verb")
	bad_verb["beats"][0]["missions"][0]["verb"] = "board_the_ship"
	var bad_default := _minimal_card("premise.bad_default")
	bad_default["default_resolution"] = "nowhere"
	var no_routes := _minimal_card("premise.no_routes")
	no_routes["beats"][0]["missions"][0].erase("routes")
	var library = LibraryType.new()
	var result = library.load_from_array([good, bad_verb, bad_default, no_routes, good.duplicate(true), "junk"])
	_check(library.size() == 1 and library.has_card("premise.good"), "only the good card should load, got %s" % str(library.ids()))
	_check(str(library.skipped.get("premise.bad_verb", "")).contains("unsupported verb"), "bad verb not reported")
	_check(str(library.skipped.get("premise.bad_default", "")).contains("default_resolution"), "bad default not reported")
	_check(str(library.skipped.get("premise.no_routes", "")).contains("routes"), "missing routes not reported")
	_check(result.is_valid(), "skipped cards must be warnings, not errors")
	_check(result.warnings.size() >= 4, "expected warnings for skipped cards")


func _test_helpers() -> void:
	var card := _minimal_card("premise.helpers")
	_check(LibraryType.role(card, "dock").get("kind") == "place", "role() lookup failed")
	_check(LibraryType.beat(card, 1).get("function") == "setup", "beat() lookup failed")
	_check(LibraryType.resolution(card, "bad").get("id") == "bad", "resolution() lookup failed")
	_check(LibraryType.beat(card, 9).is_empty(), "missing beat should be empty")
