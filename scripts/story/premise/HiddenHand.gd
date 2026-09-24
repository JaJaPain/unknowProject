class_name HiddenHand
extends RefCounted

## The campaign's main story (plan Section 3.7): a hidden actor with a motive,
## a method and a goal, whose identity is NOT decided up front. Every premise
## arc plants loose threads; some are traces of the Hidden Hand's method, the
## rest are decoys, and the player can't tell which. When enough threads have
## been seen, the story locks onto whichever known person explains the most of
## them (HiddenHandCasting / the Showrunner pass), and a reveal follows.
##
## Lives in the arc state under "main_story" so it saves and rolls back with
## the arcs. Pure static functions; every one returns a new state.

const STAGES := ["hidden", "locked", "revealed", "closed"]
const MOTIVES: Array[String] = ["revenge", "fear", "faith", "control", "greed", "protecting_someone", "ideology", "survival", "legacy", "guilt"]
const METHODS: Array[String] = ["debt_leverage", "sabotage", "forged_records", "cornering_a_market", "blackmail", "impersonation",
	"manufactured_crisis", "proxy_violence", "slow_infiltration", "information_control", "bribery", "false_flag"]

## What the Hidden Hand is after. `methods` lists methods that plausibly serve it.
const GOALS := [
	{"id": "own_the_lanes", "text": "take quiet control of the region's trade lanes", "methods": ["cornering_a_market", "bribery", "debt_leverage", "manufactured_crisis"]},
	{"id": "bury_old_crime", "text": "bury an old crime before anyone connects it to them", "methods": ["forged_records", "information_control", "proxy_violence", "blackmail"]},
	{"id": "break_a_rival", "text": "ruin one rival so completely that nobody remembers their name", "methods": ["sabotage", "false_flag", "blackmail", "impersonation"]},
	{"id": "buy_a_station", "text": "own a station outright by making it worthless first", "methods": ["manufactured_crisis", "debt_leverage", "sabotage", "cornering_a_market"]},
	{"id": "protect_a_secret_child", "text": "keep someone they love hidden and out of reach", "methods": ["impersonation", "forged_records", "information_control", "bribery"]},
	{"id": "start_a_war", "text": "push two factions into open conflict and profit from both sides", "methods": ["false_flag", "proxy_violence", "manufactured_crisis", "slow_infiltration"]},
	{"id": "rewrite_a_verdict", "text": "overturn a judgement that ruined their family", "methods": ["forged_records", "blackmail", "bribery", "information_control"]},
	{"id": "escape_a_debt", "text": "shed a debt that would otherwise follow them to the grave", "methods": ["debt_leverage", "impersonation", "forged_records", "false_flag"]},
	{"id": "keep_the_lights_on", "text": "keep a failing colony alive, whatever it costs everyone else", "methods": ["cornering_a_market", "sabotage", "bribery", "manufactured_crisis"]},
	{"id": "take_the_chair", "text": "take a seat of power that was promised to someone else", "methods": ["slow_infiltration", "blackmail", "bribery", "impersonation"]},
	{"id": "silence_a_witness", "text": "make sure one witness never testifies", "methods": ["proxy_violence", "information_control", "debt_leverage", "false_flag"]},
	{"id": "prove_them_wrong", "text": "prove a whole institution wrong, even if it breaks it", "methods": ["sabotage", "information_control", "forged_records", "manufactured_crisis"]},
]
const THREADS_PER_ARC := 2


static func main_story(state: Dictionary) -> Dictionary:
	return state.get("main_story", {})


static func is_active(state: Dictionary) -> bool:
	return not main_story(state).is_empty() and str(main_story(state).get("stage", "")) != "closed"


## Draws a fresh Hidden Hand. Called once per season (first arcs of a campaign,
## and again after a main story closes). `method_coverage` (method -> number of
## deck threads that can carry it; see method_coverage()) keeps the draw away
## from methods the deck can barely leave evidence for.
static func begin_season(state: Dictionary, seed_value: int, now_minute: int, method_coverage: Dictionary = {}) -> Dictionary:
	var next := state.duplicate(true)
	var previous: Dictionary = next.get("main_story", {})
	var season := int(previous.get("season", 0)) + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|hidden_hand|%d" % [seed_value, season])
	var goals: Array = GOALS.duplicate()
	if not method_coverage.is_empty():
		# Only goals with at least one well-evidenced method.
		goals = goals.filter(func(g): return not _usable_methods(g["methods"], method_coverage).is_empty())
		if goals.is_empty():
			goals = GOALS.duplicate()
	var goal: Dictionary = goals[rng.randi_range(0, goals.size() - 1)]
	var methods: Array = goal["methods"]
	if not method_coverage.is_empty() and not _usable_methods(methods, method_coverage).is_empty():
		methods = _usable_methods(methods, method_coverage)
	next["main_story"] = {
		"season": season, "stage": "hidden",
		"motive": MOTIVES[rng.randi_range(0, MOTIVES.size() - 1)],
		"method": str(methods[rng.randi_range(0, methods.size() - 1)]),
		"goal_id": str(goal["id"]), "goal_text": str(goal["text"]),
		"threads": [], "next_thread": 1, "lock": {}, "started_minute": now_minute,
	}
	return next


## Plants up to THREADS_PER_ARC of the card's loose threads for this arc.
## A thread that can carry the Hidden Hand's method is a trace; others are decoys.
static func seed_threads(state: Dictionary, card: Dictionary, arc_id: String, seed_value: int) -> Dictionary:
	if not is_active(state):
		return state
	var next := state.duplicate(true)
	var story: Dictionary = next["main_story"]
	var method := str(story["method"])
	var candidates: Array = (card.get("loose_threads", []) as Array).duplicate()
	if candidates.is_empty():
		return next
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%s|threads" % [seed_value, arc_id])
	# Traces first (so a compatible card really does leave evidence), then decoys.
	var traces: Array = []
	var decoys: Array = []
	for t in candidates:
		if method in (t.get("can_carry_methods", []) as Array):
			traces.append(t)
		else:
			decoys.append(t)
	_shuffle(traces, rng)
	_shuffle(decoys, rng)
	var chosen: Array = []
	if not traces.is_empty():
		chosen.append([traces[0], true])
	for t in decoys:
		if chosen.size() >= THREADS_PER_ARC:
			break
		chosen.append([t, false])
	for pair in chosen:
		var t: Dictionary = pair[0]
		(story["threads"] as Array).append({
			"id": "th.%04d" % int(story["next_thread"]), "arc_id": arc_id, "card_id": str(card.get("id", "")),
			"source_thread_id": str(t.get("id", "")), "surface": str(t.get("surface", "")),
			"detail": str(t.get("detail", "")), "methods": (t.get("can_carry_methods", []) as Array).duplicate(),
			"trace": bool(pair[1]), "seen": false, "pinned": false, "seen_minute": -1,
		})
		story["next_thread"] = int(story["next_thread"]) + 1
	return next


## The player has now seen this arc (its opening was shown): its threads are noticed.
static func mark_arc_threads_seen(state: Dictionary, arc_id: String, now_minute: int) -> Dictionary:
	if main_story(state).is_empty():
		return state
	var next := state.duplicate(true)
	for t in next["main_story"]["threads"]:
		if str(t["arc_id"]) == arc_id and not bool(t["seen"]):
			t["seen"] = true
			t["seen_minute"] = now_minute
	return next


static func set_pinned(state: Dictionary, thread_id: String, pinned: bool) -> Dictionary:
	if main_story(state).is_empty():
		return state
	var next := state.duplicate(true)
	for t in next["main_story"]["threads"]:
		if str(t["id"]) == thread_id and bool(t["seen"]):
			t["pinned"] = pinned
	return next


static func seen_threads(state: Dictionary) -> Array:
	var out: Array = []
	for t in main_story(state).get("threads", []):
		if bool(t.get("seen", false)):
			out.append(t)
	return out


static func threads_for_arc(state: Dictionary, arc_id: String) -> Array:
	var out: Array = []
	for t in main_story(state).get("threads", []):
		if str(t.get("arc_id", "")) == arc_id:
			out.append(t)
	return out


## How many loose threads in the deck can carry each method.
static func method_coverage(library) -> Dictionary:
	var counts := {}
	for card_id in library.ids():
		for thread in library.get_card(card_id).get("loose_threads", []):
			for m in thread.get("can_carry_methods", []):
				counts[str(m)] = int(counts.get(str(m), 0)) + 1
	return counts


const MIN_METHOD_COVERAGE := 5


static func _usable_methods(methods: Array, coverage: Dictionary) -> Array:
	return methods.filter(func(m): return int(coverage.get(str(m), 0)) >= MIN_METHOD_COVERAGE)


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp
