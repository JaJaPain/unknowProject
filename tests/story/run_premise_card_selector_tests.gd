extends SceneTree

const LibraryType := preload("res://scripts/story/premise/PremiseCardLibrary.gd")
const HistoryType := preload("res://scripts/story/premise/PremiseCardHistoryStore.gd")
const Selector := preload("res://scripts/story/premise/PremiseCardSelector.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_hard_requirements()
	_test_freshness_beats_fit()
	_test_fit_orders_equally_fresh_cards()
	_test_campaign_exclusion()
	_test_real_deck()
	if _failures.is_empty():
		print("[PASS] Premise card selector tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _card(card_id: String, extra: Dictionary = {}) -> Dictionary:
	var card := {
		"id": card_id, "schema_version": 1, "scale": "local",
		"roles": [{"id": "asker", "kind": "person"}, {"id": "dock", "kind": "place"}],
		"requirements": {"min_factions": 1},
		"accepts_seeds": [],
		"beats": [{"n": 1, "function": "setup", "missions": [
			{"verb": "delivery_courier", "requester": "asker", "target": "dock",
			 "outcome_tags": ["done"], "routes": {"done": "resolution:a"}}]}],
		"resolutions": [{"id": "a"}, {"id": "b"}], "default_resolution": "b",
	}
	card.merge(extra, true)
	return card


func _library(cards: Array):
	var lib = LibraryType.new()
	lib.load_from_array(cards)
	return lib


func _test_hard_requirements() -> void:
	var lib = _library([
		_card("premise.black_hole", {"requirements": {"min_factions": 1, "quirks_required": ["black_hole_proximity"]}}),
		_card("premise.no_pulsar", {"requirements": {"min_factions": 1, "quirks_forbidden": ["pulsar"]}}),
		_card("premise.needs_strike", {"requirements": {"min_factions": 1, "states_required": ["strike"]}}),
		_card("premise.big_cast", {"requirements": {"min_factions": 3}}),
		_card("premise.personal", {"scale": "personal"}),
	])
	var plain := {"quirks": ["pulsar"], "states": [], "faction_count": 2, "scale": "local"}
	var ids := Selector.eligible_ids(lib, plain)
	_check(ids.is_empty(), "nothing should fit a pulsar system with 2 factions: %s" % str(ids))
	var rich := {"quirks": ["black_hole_proximity"], "states": ["strike"], "faction_count": 3, "scale": ""}
	ids = Selector.eligible_ids(lib, rich)
	_check(ids.size() == 5, "every card should fit the rich situation: %s" % str(ids))
	_check(Selector.rejection(lib.get_card("premise.black_hole"), plain).contains("black_hole"), "rejection should name the missing quirk")


func _test_freshness_beats_fit() -> void:
	var lib = _library([
		_card("premise.fits_well", {"accepts_seeds": ["power_vacuum", "public_outrage"]}),
		_card("premise.fresh_plain"),
	])
	var history := HistoryType.record_shown(HistoryType.empty_history(), "premise.fits_well")
	var situation := {"faction_count": 2, "seeds": ["power_vacuum", "public_outrage"]}
	var order := Selector.pick(lib, history, situation, 5, 0)
	_check(order == ["premise.fresh_plain", "premise.fits_well"], "a fresh card must beat a well-fitting used one: %s" % str(order))


func _test_fit_orders_equally_fresh_cards() -> void:
	var lib = _library([
		_card("premise.plain_a"),
		_card("premise.seeded", {"accepts_seeds": ["grudge_against_player"]}),
		_card("premise.plain_b"),
	])
	var situation := {"faction_count": 2, "seeds": ["grudge_against_player"]}
	for seed_value in [1, 2, 3, 4]:
		var first := Selector.pick(lib, HistoryType.empty_history(), situation, seed_value, 1)
		_check(first == ["premise.seeded"], "the seeded card should lead among fresh cards (seed %d): %s" % [seed_value, str(first)])


func _test_campaign_exclusion() -> void:
	var lib = _library([_card("premise.once"), _card("premise.other")])
	var situation := {"faction_count": 2, "excluded_ids": ["premise.once"]}
	_check(Selector.pick(lib, HistoryType.empty_history(), situation, 1, 0) == ["premise.other"], "a card used in this campaign must never be drawn again")


func _test_real_deck() -> void:
	var lib = LibraryType.new()
	lib.load_from_dir()
	var situation := {"quirks": [], "states": [], "faction_count": 3, "scale": ""}
	var picks := Selector.pick(lib, HistoryType.empty_history(), situation, 11, 0)
	# About a third of the deck needs a system quirk or state (measured 2026-09-24:
	# 75 of 120 fit a plain system), so plain systems still offer plenty.
	_check(picks.size() >= 60, "most of the deck should fit an ordinary system, got %d" % picks.size())
	for card_id in picks:
		var req: Dictionary = lib.get_card(card_id).get("requirements", {})
		_check((req.get("quirks_required", []) as Array).is_empty(), "%s needs a quirk but was picked for a plain system" % card_id)
	# A dying-star system opens up cards a plain system can't offer.
	var dying := situation.duplicate()
	dying["quirks"] = ["dying_star"]
	var dying_picks := Selector.pick(lib, HistoryType.empty_history(), dying, 11, 0)
	var needs_dying := 0
	for card_id in dying_picks:
		if "dying_star" in (lib.get_card(card_id).get("requirements", {}) as Dictionary).get("quirks_required", []):
			needs_dying += 1
	_check(needs_dying >= 1, "a dying-star system should unlock dying-star cards")
