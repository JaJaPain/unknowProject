extends RefCounted

## Board pickups as a lounge hunt (Abe, playtest 2026-10-03): the job names the
## outpost, not the person. In its lounge you work out who has the item and
## talk it out of them, with very dry humour (it's a board job).
##
## - Ask someone who doesn't have it: a deflection; sometimes they point at
##   who does.
## - Ask the one who has it: they deny it, then hedge, then hand it over on
##   the third ask. A drink bought for them counts as an ask.
##
## Pure: the state is a dictionary kept in StoryManager.story_state
## (STATE_KEY -> {mission key: {asks: {npc: n}, hinted: bool}}).

const STATE_KEY := "pickup_hunt"
## Asks it takes to talk the holder round (a drink counts as one).
const ASKS_TO_HAND_OVER := 3
## How often a bystander points at the holder (always by the third bystander
## asked, so the hunt never stalls).
const HINT_CHANCE := 0.5

const DEFLECT := [
	"I own a mug and a grudge. Neither is a {part}.",
	"If I had one, I'd be using it. Look at me. I'm overheating emotionally.",
	"No. But thank you for assuming I'm the sort of person who would.",
	"I've been asked that twice today. You're the second most hopeful.",
]
const HINT := [
	"Try {holder}. They've been guarding that bag like it pays rent.",
	"{holder} came in with something warm under their coat. I didn't ask. You should.",
	"Not me. {holder}, probably. They've been suspiciously calm.",
]
const HOLDER_DENY := [
	"A {part}? What would I want with a... no. No idea what you mean.",
	"Never heard of it. Lovely word, though.",
	"I'm just here for the ambience. Which is mostly coolant fumes.",
]
const HOLDER_HEDGE := [
	"Say I had one. Hypothetically. It would be a very sealed, very unsniffed one.",
	"You're persistent. That's either a virtue or a symptom.",
]
const HOLDER_GIVE := [
	"Fine. Take it. It hums when it's lonely. That's normal. Probably.",
	"It's yours. Don't open it, don't sniff it, don't name it. I did all three.",
	"Here. Tell whoever posted that job they owe me a drink. You can be the drink.",
]


## The hunt's state for one job (created on first use).
static func state_for(story_state: Dictionary, mission_key: String) -> Dictionary:
	var all = story_state.get(STATE_KEY)
	if not all is Dictionary:
		all = {}
		story_state[STATE_KEY] = all
	if not (all as Dictionary).has(mission_key):
		all[mission_key] = {"asks": {}, "bystanders": 0, "hinted": false}
	return all[mission_key]


## Ask `npc` about the item. `roll` 0..1 for the bystander hint, `pick` any int
## for line choice. Returns {line, handed_over}.
static func ask(s: Dictionary, npc: String, holder: String, part: String, roll: float, pick: int) -> Dictionary:
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
			return {"line": _fill(HINT[posmod(pick, HINT.size())], part, holder_short), "handed_over": false}
		return {"line": _fill(DEFLECT[posmod(pick, DEFLECT.size())], part, holder_short), "handed_over": false}
	if n >= ASKS_TO_HAND_OVER:
		return {"line": _fill(HOLDER_GIVE[posmod(pick, HOLDER_GIVE.size())], part, holder_short), "handed_over": true}
	if n == ASKS_TO_HAND_OVER - 1:
		return {"line": _fill(HOLDER_HEDGE[posmod(pick, HOLDER_HEDGE.size())], part, holder_short), "handed_over": false}
	return {"line": _fill(HOLDER_DENY[posmod(pick, HOLDER_DENY.size())], part, holder_short), "handed_over": false}


## A drink for the holder softens them by one ask.
static func drink(s: Dictionary, npc: String, holder: String) -> void:
	if npc != holder:
		return
	var asks: Dictionary = s["asks"]
	asks[npc] = mini(int(asks.get(npc, 0)) + 1, ASKS_TO_HAND_OVER - 1)


static func _fill(line: String, part: String, holder: String) -> String:
	return line.replace("{part}", part).replace("{holder}", holder)
