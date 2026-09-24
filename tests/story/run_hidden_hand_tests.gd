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
	_test_candidates_draft_and_lock()
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


## Three arcs: "npc.culprit" is in all three (each leaves a trace); two other
## people appear once each. The lock must land on the culprit.
func _test_candidates_draft_and_lock() -> void:
	var s := Hand.begin_season(Arcs.empty_state(), 7, 0)
	var method := str(Hand.main_story(s)["method"])
	for i in 4:
		var card := _card_with_threads(method)
		card["id"] = "premise.c%d" % i
		var villain_id := "npc.culprit" if i < 3 else "npc.other_%d" % i
		var villain_name := "Oren Vask" if i < 3 else "Someone Else"
		var cast := {"villain": {"kind": "person", "entity_id": villain_id, "display_name": villain_name},
			"bystander": {"kind": "person", "entity_id": "npc.bystander_%d" % i, "display_name": "Bystander %d" % i},
			"dock": {"kind": "place", "entity_id": "station.x", "display_name": "Dock"}}
		var started := Arcs.start_arc(s, {"id": card["id"], "scale": "local", "beats": [{"n": 1}]}, "system.x%d" % i, cast, i)
		s = started["state"]
		s = Hand.seed_threads(s, card, started["arc_id"], 7)
		if i < 2:
			s = Hand.mark_arc_threads_seen(s, started["arc_id"], i)
	# Stories 1-3 have played out; the culprit's third is still running.
	for arc_id in ["arc.0001", "arc.0002", "arc.0004"]:
		s["arcs"][arc_id]["status"] = "resolved"
	_check(not Hand.ready_to_lock(s), "four seen threads are not enough to lock")
	s = Hand.update_draft(s)
	_check(Hand.main_story(s).get("draft_entity_id") == "npc.culprit", "the draft should already point at the culprit")
	s = Hand.mark_arc_threads_seen(s, "arc.0003", 3)
	_check(not Hand.ready_to_lock(s), "evidence from only three systems must not lock yet")
	s = Hand.mark_arc_threads_seen(s, "arc.0004", 4)
	_check(not Hand.ready_to_lock(s), "the lock waits while the prime suspect is in another live story")
	s["arcs"]["arc.0003"]["status"] = "resolved"
	_check(Hand.ready_to_lock(s), "enough threads, traces, people and systems should be ready to lock")
	var dead := s.duplicate(true)
	dead["fates"]["npc.culprit"] = ["dead"]
	_check(Hand.candidates(dead).all(func(p): return p["entity_id"] != "npc.culprit"), "the dead can't be the hidden hand")
	var ranked := Hand.candidates(s)
	_check(ranked[0]["entity_id"] == "npc.culprit", "the culprit should score highest: %s" % str(ranked[0]))
	var bad := Hand.lock(s, {"entity_id": "npc.nobody", "links": {}}, 10)
	_check(not bool(bad["ok"]) and bad["reason"] == "not_a_candidate", "locking on a stranger must be refused")
	var thin := Hand.lock(s, {"entity_id": "npc.culprit", "links": {"th.0001": "x"}}, 10)
	_check(not bool(thin["ok"]) and thin["reason"] == "explains_too_little", "a truth that explains one thread must be refused")
	var locked := Hand.lock_by_code(s, 10)
	_check(bool(locked["ok"]), "the code fallback should lock: %s" % locked["reason"])
	var story := Hand.main_story(locked["state"])
	_check(story["stage"] == "locked" and story["lock"]["entity_id"] == "npc.culprit", "the lock should name the culprit")
	_check(str(story["lock"]["truth"]).contains("Oren Vask"), "the truth should name them")
	_check(not Hand.ready_to_lock(locked["state"]), "a locked story can't lock again")
