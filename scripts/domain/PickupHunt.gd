extends RefCounted

## Board pickups as a lounge hunt (Abe, playtest 2026-10-03): the job names the
## outpost, not the person. In its lounge you work out who has the item and
## talk it out of them, with very dry humour (it's a board job).
##
## - Ask someone who doesn't have it: a deflection; sometimes they point at
##   who does.
## - Ask the one who has it: they deny it (with a tell), then hedge, then hand
##   it over on the third ask. A drink bought for them counts as an ask.
##
## Lines: a large authored pool in data/content/pickup_hunt_lines.json (Abe:
## big and hand-written beats small or model-written). Each pool is a shuffled
## deck: every ask draws a random line, and none repeats until the whole pool
## has been used (decks are kept in story_state, so across hunts too).
##
## Pure: the state is dictionaries kept in StoryManager.story_state
## (STATE_KEY -> {mission key: {asks: {npc: n}, hinted: bool}}; DECKS_KEY ->
## {pool: [line indices left]}).

const STATE_KEY := "pickup_hunt"
const DECKS_KEY := "pickup_hunt_decks"
const LINES_PATH := "res://data/content/pickup_hunt_lines.json"
## Asks it takes to talk the holder round (a drink counts as one).
const ASKS_TO_HAND_OVER := 3
## How often a bystander points at the holder (always by the third bystander
## asked, so the hunt never stalls).
const HINT_CHANCE := 0.5
const POOL_NAMES := ["deflect", "hint", "deny", "tell", "hedge", "give"]

## Used only if the data file can't be read.
const FALLBACK := {
	"deflect": ["I own a mug and a grudge. Neither is your {part}."],
	"hint": ["Try {holder}. They've been guarding that bag like it pays rent."],
	"deny": ["Never heard of it. Lovely word, though."],
	"tell": ["(Their hand drifts to the bag under the table.)"],
	"hedge": ["You're persistent. That's either a virtue or a symptom."],
	"give": ["Fine. Take it. It hums when it's lonely. That's normal. Probably."],
}

static var _pools: Dictionary = {}


## Every pool, from the data file (fallback lines if it can't be read).
static func pools() -> Dictionary:
	if _pools.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(LINES_PATH))
		for name in POOL_NAMES:
			var lines = parsed.get(name) if parsed is Dictionary else null
			_pools[name] = lines if lines is Array and not (lines as Array).is_empty() else FALLBACK[name]
	return _pools


## The hunt's state for one job (created on first use).
static func state_for(story_state: Dictionary, mission_key: String) -> Dictionary:
	var all = story_state.get(STATE_KEY)
	if not all is Dictionary:
		all = {}
		story_state[STATE_KEY] = all
	if not (all as Dictionary).has(mission_key):
		all[mission_key] = {"asks": {}, "bystanders": 0, "hinted": false}
	return all[mission_key]


## The shuffled decks, kept in story_state.
static func decks_for(story_state: Dictionary) -> Dictionary:
	var decks = story_state.get(DECKS_KEY)
	if not decks is Dictionary:
		decks = {}
		story_state[DECKS_KEY] = decks
	return decks


## A random line from `pool`: dealt from a shuffled deck, reshuffled when it
## runs out, so nothing repeats until every line has had its turn.
static func draw(decks: Dictionary, pool: String) -> String:
	var lines: Array = pools()[pool]
	var deck: Array = decks.get(pool, [])
	# A deck from an older, shorter pool is dealt out fresh.
	deck = deck.filter(func(i): return int(i) < lines.size())
	if deck.is_empty():
		deck = range(lines.size())
		deck.shuffle()
	var index := int(deck.pop_back())
	decks[pool] = deck
	return str(lines[index])


## Ask `npc` about the item. `roll` 0..1 for the bystander hint; lines come
## from `decks`. Returns {line, handed_over}.
static func ask(s: Dictionary, npc: String, holder: String, part: String, roll: float, decks: Dictionary) -> Dictionary:
	var asks: Dictionary = s["asks"]
	var n := int(asks.get(npc, 0)) + 1
	asks[npc] = n
	var holder_short := preload("res://scripts/domain/QuestNextStep.gd").person_name(holder)
	if npc != holder:
		s["bystanders"] = int(s["bystanders"]) + 1
		var give_hint := not bool(s["hinted"]) and (roll < HINT_CHANCE or int(s["bystanders"]) >= 3)
		if n > 1 and bool(s["hinted"]):
			give_hint = true  # asked again: they repeat where to look
		if give_hint:
			s["hinted"] = true
			return {"line": _fill(draw(decks, "hint"), part, holder_short), "handed_over": false}
		return {"line": _fill(draw(decks, "deflect"), part, holder_short), "handed_over": false}
	if n >= ASKS_TO_HAND_OVER:
		return {"line": _fill(draw(decks, "give"), part, holder_short), "handed_over": true}
	if n == ASKS_TO_HAND_OVER - 1:
		return {"line": _fill(draw(decks, "hedge"), part, holder_short), "handed_over": false}
	var deny := _fill(draw(decks, "deny"), part, holder_short)
	return {"line": "%s %s" % [deny, draw(decks, "tell")], "handed_over": false}


## Who the player knows has it (named by a bystander, or caught in a tell),
## for the tracker. "" while they don't.
static func suspect(s: Dictionary, holder: String) -> String:
	if bool(s.get("hinted", false)) or int((s.get("asks", {}) as Dictionary).get(holder, 0)) > 0:
		return holder
	return ""


## A drink for the holder softens them by one ask.
static func drink(s: Dictionary, npc: String, holder: String) -> void:
	if npc != holder:
		return
	var asks: Dictionary = s["asks"]
	asks[npc] = mini(int(asks.get(npc, 0)) + 1, ASKS_TO_HAND_OVER - 1)


static func _fill(line: String, part: String, holder: String) -> String:
	return line.replace("{part}", part).replace("{holder}", holder)
