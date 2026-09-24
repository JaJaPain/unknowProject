extends SceneTree

const LibraryType := preload("res://scripts/story/premise/PremiseCardLibrary.gd")
const Arcs := preload("res://scripts/story/premise/ArcEngine.gd")
const Hand := preload("res://scripts/story/premise/HiddenHand.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_begin_season()
	_test_seeding_traces_and_decoys()
	_test_seen_and_pinned()
	_test_whole_deck_traces()
	if _failures.is_empty():
		print("[PASS] Hidden hand tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_begin_season() -> void:
	var s := Hand.begin_season(Arcs.empty_state(), 99, 10)
	var story := Hand.main_story(s)
	_check(story["stage"] == "hidden" and int(story["season"]) == 1, "a new season starts hidden, season 1")
	_check(story["motive"] in Hand.MOTIVES and story["method"] in Hand.METHODS, "motive and method from the vocabularies")
	var goal_methods: Array = []
	for g in Hand.GOALS:
		if g["id"] == story["goal_id"]:
			goal_methods = g["methods"]
	_check(story["method"] in goal_methods, "the method must serve the goal")
	var s2 := Hand.begin_season(s, 99, 20)
	_check(int(Hand.main_story(s2)["season"]) == 2, "a second season increments")
	_check(Hand.main_story(Hand.begin_season(Arcs.empty_state(), 99, 10)) == story, "same seed, same Hidden Hand")


func _card_with_threads(method: String) -> Dictionary:
	return {"id": "premise.t", "loose_threads": [
		{"id": "t_trace", "surface": "cargo", "detail": "A stamp dated after closing.", "can_carry_methods": [method]},
		{"id": "t_decoy_a", "surface": "scan", "detail": "Odd engine heat.", "can_carry_methods": ["not_this"]},
		{"id": "t_decoy_b", "surface": "radio", "detail": "A repeated call sign.", "can_carry_methods": ["nor_this"]}]}


func _test_seeding_traces_and_decoys() -> void:
	var s := Hand.begin_season(Arcs.empty_state(), 5, 0)
	var method := str(Hand.main_story(s)["method"])
	s = Hand.seed_threads(s, _card_with_threads(method), "arc.0001", 5)
	var threads := Hand.threads_for_arc(s, "arc.0001")
	_check(threads.size() == 2, "two threads per arc, got %d" % threads.size())
	var traces := threads.filter(func(t): return bool(t["trace"]))
	_check(traces.size() == 1 and traces[0]["source_thread_id"] == "t_trace", "a compatible card leaves exactly one trace")
	var none := Hand.seed_threads(s, _card_with_threads("nothing_matches"), "arc.0002", 5)
	_check(Hand.threads_for_arc(none, "arc.0002").filter(func(t): return bool(t["trace"])).is_empty(), "an incompatible card leaves only decoys")


func _test_seen_and_pinned() -> void:
	var s := Hand.begin_season(Arcs.empty_state(), 5, 0)
	s = Hand.seed_threads(s, _card_with_threads(str(Hand.main_story(s)["method"])), "arc.0001", 5)
	var tid := str(Hand.threads_for_arc(s, "arc.0001")[0]["id"])
	_check(Hand.set_pinned(s, tid, true) == s, "an unseen thread can't be pinned")
	s = Hand.mark_arc_threads_seen(s, "arc.0001", 42)
	_check(Hand.seen_threads(s).size() == 2, "showing an arc reveals its threads")
	s = Hand.set_pinned(s, tid, true)
	_check(bool(Hand.threads_for_arc(s, "arc.0001")[0]["pinned"]), "a seen thread can be pinned")


func _test_whole_deck_traces() -> void:
	# With the real deck's coverage, every drawn Hidden Hand must use a method
	# the deck can leave real evidence for.
	var lib = LibraryType.new()
	lib.load_from_dir()
	var coverage := Hand.method_coverage(lib)
	for seed_value in 200:
		var story := Hand.main_story(Hand.begin_season(Arcs.empty_state(), seed_value, 0, coverage))
		var m := str(story["method"])
		_check(int(coverage.get(m, 0)) >= Hand.MIN_METHOD_COVERAGE, "seed %d drew thinly evidenced method %s (%d threads)" % [seed_value, m, int(coverage.get(m, 0))])
