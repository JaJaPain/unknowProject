extends RefCounted

## The Lodestar (docs/core_loop_plan_2026_10_01.md 4.1-4.2, core loop step 9):
## one place past the edge of the charts that this campaign is about reaching.
## The card is drawn from the campaign seed; its five bearings (step 10) make
## the star map's wedge narrower until the last one marks the system.
##
## State lives in StoryManager.story_state["lodestar"]:
##   {"id": card id, "known": heard the first hint, "bearings": [indices found]}
## The id is saved so a later deck change never swaps a running campaign's card.

const DECK_PATH := "res://data/content/lodestars.json"
const STATE_KEY := "lodestar"
const BEARINGS := 5
## Where it is: a Class VI system (plan 2.1).
const TARGET_DEPTH := 13
## The wedge's width on the star map by bearings found (degrees). The last
## bearing marks the system itself (0).
const WEDGE_DEGREES := [80.0, 60.0, 42.0, 28.0, 14.0, 0.0]

static var _deck: Array = []


static func deck() -> Array:
	if _deck.is_empty():
		var file := FileAccess.open(DECK_PATH, FileAccess.READ)
		if file == null:
			push_error("[Lodestar] can't read %s" % DECK_PATH)
			return []
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary and parsed.get("cards") is Array:
			_deck = parsed["cards"]
	return _deck


static func by_id(id: String) -> Dictionary:
	for card in deck():
		if str(card.get("id", "")) == id:
			return card
	return {}


## This campaign's card from its seed.
static func draw(campaign_seed: int) -> Dictionary:
	var cards := deck()
	if cards.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("lodestar:%d" % campaign_seed)
	return cards[rng.randi() % cards.size()]


## The campaign's state, creating it (card drawn, nothing known) if missing.
static func state(story_state: Dictionary, campaign_seed: int) -> Dictionary:
	var s = story_state.get(STATE_KEY)
	if not s is Dictionary or by_id(str(s.get("id", ""))).is_empty():
		s = {"id": str(draw(campaign_seed).get("id", "")), "known": false, "bearings": []}
		story_state[STATE_KEY] = s
	return s


static func card_of(s: Dictionary) -> Dictionary:
	return by_id(str(s.get("id", "")))


static func bearings_found(s: Dictionary) -> int:
	return (s.get("bearings", []) as Array).size()


## The wedge's width for this many bearings, degrees.
static func wedge_degrees(found: int) -> float:
	return float(WEDGE_DEGREES[clampi(found, 0, WEDGE_DEGREES.size() - 1)])


## Which way the wedge points on the star map (radians, 0 = right, clockwise),
## fixed per campaign. Kept off straight up, where the map's title bar sits.
static func wedge_angle(campaign_seed: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("lodestar_angle:%d" % campaign_seed)
	return deg_to_rad(rng.randf_range(-60.0, 240.0))


## Bearing `index` (0-4) becomes findable once gate class index + 2 is open.
static func bearing_class(index: int) -> int:
	return index + 2


## The latest bearing found, for the map tooltip and the HUD ("" before any).
static func last_bearing_text(s: Dictionary) -> String:
	var found: Array = s.get("bearings", [])
	var card := card_of(s)
	if found.is_empty() or card.is_empty():
		return ""
	return str(card["bearings"][int(found[-1])]["text"])


# --- Seasons, the pin and the arrival (core loop step 12, plan 4.5) ----------
#
# More state keys: "season" (1 for the first Lodestar), "start_depth" and
# "target_depth" (seasons 2+), "pinned_system" / "pinned_gate" (set when the
# last bearing marks it), "past" ([{id, season, system}], one per Lodestar
# reached; the next card is drawn from the rest of the deck).

## Credits the place gives, per season.
const REWARD_PER_SEASON := 2000
## Each later Lodestar is at least this many systems deeper than the last.
const SEASON_DEPTH_STEP := 7
## ...and at least this far past where the Captain stands when it's drawn.
const MIN_DEPTH_AHEAD := 6


static func season(s: Dictionary) -> int:
	return maxi(1, int(s.get("season", 1)))


## The depth this season's Lodestar lies at (or beyond).
static func target_depth(s: Dictionary) -> int:
	return int(s.get("target_depth", TARGET_DEPTH + SEASON_DEPTH_STEP * (season(s) - 1)))


## The gate class past which it lies, for the map ("Class VI gates").
static func target_class(s: Dictionary) -> int:
	return preload("res://scripts/domain/GateClass.gd").class_for_depth(target_depth(s))


## Can bearing `index` be found at this depth? The first season keeps step
## 10's rule (bearing N in a Class N+2 system); later seasons spread the five
## bearings evenly between where the season began and the Lodestar.
static func bearing_ready(s: Dictionary, index: int, depth: int) -> bool:
	if season(s) <= 1:
		var GateClassType := preload("res://scripts/domain/GateClass.gd")
		return GateClassType.class_for_depth(depth) >= bearing_class(index)
	return depth >= bearing_depth(s, index)


## Seasons 2+: the depth bearing `index` waits for.
static func bearing_depth(s: Dictionary, index: int) -> int:
	var start := int(s.get("start_depth", 0))
	var span := maxi(BEARINGS, target_depth(s) - 1 - start)
	return start + int(round(float(index + 1) * span / BEARINGS))


## Which way the wedge points. The first season keeps step 9's angle; each
## later one points somewhere new.
static func season_wedge_angle(campaign_seed: int, s: Dictionary) -> float:
	if season(s) <= 1:
		return wedge_angle(campaign_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("lodestar_angle:%d:%d" % [campaign_seed, season(s)])
	return deg_to_rad(rng.randf_range(-60.0, 240.0))


static func is_pinned(s: Dictionary) -> bool:
	return not str(s.get("pinned_system", "")).is_empty()


## The last bearing marks the system: choose one of the gates out of here.
## `gates`: [{gate_id, dest, dest_depth, visited, withheld}]. Deeper beats
## shallower, unvisited beats visited, a gate Kaelen is holding back is never
## chosen (its sale is her story). {} when none fits.
static func pick_pin(gates: Array, here_depth: int) -> Dictionary:
	var best := {}
	var best_score := -1
	for g in gates:
		if bool(g.get("withheld", false)) or str(g.get("dest", "")).is_empty():
			continue
		if int(g.get("dest_depth", -1)) <= here_depth:
			continue
		var score := 2 if not bool(g.get("visited", false)) else 1
		if score > best_score:
			best = g
			best_score = score
	return best


static func pin(s: Dictionary, system_id: String, gate_id: String) -> void:
	s["pinned_system"] = system_id
	s["pinned_gate"] = gate_id


## The scene the place plays when the Captain reaches it (authored per card).
static func arrival_scene(s: Dictionary) -> Dictionary:
	var scene = card_of(s).get("arrival_scene", {})
	return scene if scene is Dictionary else {}


static func reward_credits(s: Dictionary) -> int:
	return REWARD_PER_SEASON * season(s)


## Reached: the season closes and a new Lodestar is drawn further out, from
## the cards not yet reached this campaign (the deck starts over once every
## card has been). Returns the new state; it starts unheard-of.
static func next_season(story_state: Dictionary, campaign_seed: int, here_depth: int) -> Dictionary:
	var old: Dictionary = story_state.get(STATE_KEY, {})
	var past: Array = (old.get("past", []) as Array).duplicate()
	past.append({"id": str(old.get("id", "")), "season": season(old), "system": str(old.get("pinned_system", ""))})
	var used := {}
	for p in past:
		used[str(p["id"])] = true
	var pool: Array = []
	for card in deck():
		if not used.has(str(card["id"])):
			pool.append(card)
	if pool.is_empty():
		for card in deck():
			if str(card["id"]) != str(old.get("id", "")):
				pool.append(card)
	var new_season := season(old) + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("lodestar:%d:%d" % [campaign_seed, new_season])
	var card: Dictionary = pool[rng.randi() % pool.size()] if not pool.is_empty() else {}
	var target := maxi(TARGET_DEPTH + SEASON_DEPTH_STEP * (new_season - 1), here_depth + MIN_DEPTH_AHEAD)
	var fresh := {
		"id": str(card.get("id", "")), "known": false, "bearings": [], "season": new_season,
		"start_depth": here_depth, "target_depth": target, "past": past,
	}
	story_state[STATE_KEY] = fresh
	return fresh


## The gate class where bearing `index` turns up, for the log.
static func bearing_class_for(s: Dictionary, index: int) -> int:
	if season(s) <= 1:
		return bearing_class(index)
	return preload("res://scripts/domain/GateClass.gd").class_for_depth(bearing_depth(s, index))


## The Lodestars reached so far this campaign, oldest first: [{id, season, system}].
static func past(s: Dictionary) -> Array:
	var p = s.get("past", [])
	return p if p is Array else []
