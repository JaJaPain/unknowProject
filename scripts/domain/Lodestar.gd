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
