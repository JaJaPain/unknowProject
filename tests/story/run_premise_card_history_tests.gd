extends SceneTree

const Store := preload("res://scripts/story/premise/PremiseCardHistoryStore.gd")
const TEST_PATH := "user://test_premise_card_history.json"

var _failures: Array[String] = []


func _initialize() -> void:
	_test_fresh_cards_come_first()
	_test_recent_cards_are_held_back()
	_test_cycle_advances_and_keeps_recency()
	_test_order_is_stable_per_seed()
	_test_save_load_and_corruption()
	if _failures.is_empty():
		print("[PASS] Premise card history tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _deck(n: int) -> Array:
	var ids: Array = []
	for i in n:
		ids.append("premise.card_%02d" % i)
	return ids


func _test_fresh_cards_come_first() -> void:
	var h := Store.empty_history()
	h = Store.record_shown(h, "premise.card_00")
	h = Store.record_shown(h, "premise.card_01")
	var order := Store.order_candidates(h, _deck(5), 7)
	_check(order.size() == 5, "all candidates must be returned")
	_check(not order.slice(0, 3).has("premise.card_00") and not order.slice(0, 3).has("premise.card_01"),
		"unused cards must come before used ones: %s" % str(order))


func _test_recent_cards_are_held_back() -> void:
	# 40 cards all used once, in order; with a window of 30, cards 0-9 are "older"
	# and 10-39 are "recent". The oldest must come first.
	var h := Store.empty_history()
	var deck := _deck(40)
	for card_id in deck:
		h = Store.record_shown(h, card_id)
	var order := Store.order_candidates(h, deck, 1)
	_check(order[0] == "premise.card_00", "the card used longest ago should come first, got %s" % order[0])
	_check(order.find("premise.card_09") < order.find("premise.card_10"), "older cards must precede the recent window")
	_check(order[order.size() - 1] == "premise.card_39", "the most recent card must come last")


func _test_cycle_advances_and_keeps_recency() -> void:
	var deck := _deck(10)
	var h := Store.empty_history()
	for i in 8:
		h = Store.record_shown(h, deck[i])
	_check(int(Store.advance_cycle_if_due(h, deck)["cycle"]) == 1, "80% used must not start a new cycle")
	h = Store.record_shown(h, deck[8])
	h = Store.advance_cycle_if_due(h, deck)
	_check(int(h["cycle"]) == 2, "90% used must start a new cycle")
	_check(not Store.used_this_cycle(h, deck[0]), "a new cycle makes every card fresh again")
	_check(Store.is_recent(h, deck[8]), "recency must survive the cycle change")
	var order := Store.order_candidates(h, deck, 3)
	# All fresh again, so every card is in the first group; the draw stays usable.
	_check(order.size() == 10, "cycle change must not lose cards")


func _test_order_is_stable_per_seed() -> void:
	var h := Store.empty_history()
	var a := Store.order_candidates(h, _deck(12), 42)
	var b := Store.order_candidates(h, _deck(12), 42)
	var c := Store.order_candidates(h, _deck(12), 43)
	_check(a == b, "the same seed must give the same order")
	_check(a != c, "a different seed should shuffle fresh cards differently")


func _test_save_load_and_corruption() -> void:
	var h := Store.record_shown(Store.empty_history(), "premise.card_00")
	var saved := Store.save_history(h, TEST_PATH)
	_check(bool(saved.get("ok", false)), "save failed: %s" % str(saved))
	var loaded := Store.load_history(TEST_PATH)
	_check(bool(loaded["ok"]) and Store.last_seq(loaded["history"], "premise.card_00") == 1, "round trip failed")
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	var broken := Store.load_history(TEST_PATH)
	_check(not bool(broken["ok"]) and (broken["history"]["used"] as Dictionary).is_empty(),
		"corrupt history must load as a fresh history")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	var missing := Store.load_history(TEST_PATH)
	_check(bool(missing["ok"]) and missing["reason"] == "missing", "a missing file is a fresh, ok history")
