extends SceneTree

const LibraryType := preload("res://scripts/story/premise/PremiseCardLibrary.gd")
const Arcs := preload("res://scripts/story/premise/ArcEngine.gd")
const Hand := preload("res://scripts/story/premise/HiddenHand.gd")
const Show := preload("res://scripts/story/premise/Showrunner.gd")
const Casting := preload("res://scripts/story/premise/PremiseCasting.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var fixture := build_fixture()
	_test_request(fixture)
	_test_parse(fixture)
	if _failures.is_empty():
		print("[PASS] Showrunner tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## A campaign that is ready to lock: twelve real cards in twelve systems, one
## person recurring in three of them, every thread seen. Shared with the live test.
static func build_fixture() -> Dictionary:
	var lib = LibraryType.new()
	lib.load_from_dir()
	var s := Hand.begin_season(Arcs.empty_state(), 31, 0, Hand.method_coverage(lib))
	var method := str(Hand.main_story(s)["method"])
	var picked: Array = []
	for card_id in lib.ids():
		var card: Dictionary = lib.get_card(card_id)
		var carries := false
		for t in card.get("loose_threads", []):
			if method in t.get("can_carry_methods", []):
				carries = true
		if carries and picked.size() < 12:
			picked.append(card)
	var world := {"system_display": "Vessa", "main_station": {"id": "system.v", "display": "Vessa Main"},
		"outposts": [{"id": "outpost.a", "display": "Iron Reach"}], "factions": [{"id": "faction.generated.g", "display_name": "The Tessin Guild", "spawn_key": "g"}],
		"hostile_factions": ["reavers"], "known_npcs": []}
	for i in picked.size():
		var card: Dictionary = picked[i]
		var cast := Casting.cast_card(card, world, 100 + i, "arc.%04d" % (i + 1))
		if i < 3:
			# Make the same person recur: overwrite the first person role.
			for role in card.get("roles", []):
				if str(role.get("kind", "")) == "person":
					cast[str(role["id"])] = {"kind": "person", "entity_id": "npc.recurring", "display_name": "Oren Vask", "archetype": str(role.get("archetype", ""))}
					break
		var started := Arcs.start_arc(s, card, "system.v%d" % i, cast, i)
		s = started["state"]
		s = Hand.seed_threads(s, card, started["arc_id"], 31)
		s = Hand.mark_arc_threads_seen(s, started["arc_id"], i)
	# By lock time these stories have played out (a suspect in a live story waits).
	for arc_id in (s["arcs"] as Dictionary).keys():
		s["arcs"][arc_id]["status"] = "resolved"
	return {"state": s, "library": lib, "names": {"system.v0": "Vessa", "system.v1": "Kora", "system.v2": "Tessin", "system.v3": "Harrow"}}


func _test_request(fixture: Dictionary) -> void:
	var s: Dictionary = fixture["state"]
	_check(Hand.ready_to_lock(s), "the fixture should be ready to lock (seen %d, traces %d, candidates %d)" % [
		Hand.seen_threads(s).size(), Hand.seen_trace_count(s), Hand.candidates(s).size()])
	var req := Show.build_request(s, fixture["library"], fixture["names"])
	var prompt := str(req["prompt"])
	_check(prompt.contains("Oren Vask") and prompt.contains("npc.recurring"), "the prompt lists candidates by id and name")
	_check(not prompt.contains("{role:"), "no unfilled placeholders in the prompt")
	_check(load("res://scripts/story/ReservedTopics.gd").is_clean(prompt), "the prompt must not touch reserved topics")
	_check(req["model"] == "qwen3:8b" and int(req["keep_alive"]) == 0, "story passes use the large model and unload it right after")


func _answer(candidate: String, thread_ids: Array, truth: String = "") -> String:
	var links: Array = []
	for tid in thread_ids:
		links.append({"thread_id": tid, "explanation": "It was part of the same quiet scheme."})
	return JSON.stringify({"candidate_id": candidate,
		"truth": truth if not truth.is_empty() else "Oren Vask has been buying up the lanes through front companies and debts nobody can trace back to him.",
		"links": links, "next_beats": ["A ledger surfaces.", "A witness talks.", "The pilot corners him."]})


func _test_parse(fixture: Dictionary) -> void:
	var s: Dictionary = fixture["state"]
	var seen := Hand.seen_threads(s).map(func(t): return str(t["id"]))
	var good := Show.parse_response(_answer("npc.recurring", seen.slice(0, Hand.LOCK_MIN_TRACES)), s)
	_check(bool(good["ok"]), "a good answer should pass: %s" % good["reason"])
	var locked := Hand.lock(s, good["choice"], 50)
	_check(bool(locked["ok"]) and Hand.main_story(locked["state"])["lock"]["source"] == "showrunner", "a checked answer locks the story")
	_check(Show.parse_response(_answer("npc.made_up", seen.slice(0, Hand.LOCK_MIN_TRACES)), s)["reason"] == "unknown_candidate", "an invented person is refused")
	_check(Show.parse_response(_answer("npc.recurring", seen.slice(0, 1)), s)["reason"] == "explains_too_little", "too few links are refused")
	_check(Show.parse_response(_answer("npc.recurring", ["th.9999", "th.9998", "th.9997"]), s)["reason"] == "explains_too_little", "links to unseen threads don't count")
	var reserved := _answer("npc.recurring", seen.slice(0, Hand.LOCK_MIN_TRACES), "Oren Vask secretly came from another universe and has been steering everyone here for years now.")
	_check(Show.parse_response(reserved, s)["reason"] == "reserved_topic", "a reserved topic in the answer is refused")
	_check(Show.parse_response("not json at all", s)["reason"] == "not_json", "garbage is refused")
	_check(bool(Show.parse_response(_answer("npc.recurring|Oren Vask", seen.slice(0, Hand.LOCK_MIN_TRACES)), s)["ok"]), "an id with the name attached is accepted")
	_check(Show.parse_response(_answer("Oren Vask", seen.slice(0, Hand.LOCK_MIN_TRACES)), s)["choice"].get("entity_id") == "npc.recurring", "an exact display name maps to the id")
	_check(Show.parse_response(_answer("npc.recurring_but_not", seen.slice(0, Hand.LOCK_MIN_TRACES)), s)["reason"] == "unknown_candidate", "a near-miss id is still refused")
