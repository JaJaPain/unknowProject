extends RefCounted

## The season climax's connect-the-dots (campaign spine plan, section 12; Abe,
## 2026-10-05): before the showdown at the Lodestar, N.O.V.A. walks through
## real clues the Captain saw, then opens a channel to Kaelen herself; Kaelen
## puts it together, catches the Captain listening, and snaps back to broker.
##
## Fixed-cast canon (director-only): WE NEVER ADMIT ANYTHING (Abe). No line
## says they know each other, how, or why; it's all tone (she calls without
## asking, "You were right" implies an earlier talk without saying so). Nothing
## afterwards refers back to it: no follow-up line, wiki entry, database line,
## recap or log. Every line has a mundane reading. Full version once per
## campaign; later seasons get the short one. Every line here is hand-authored (never a model), for Abe's
## review against the canon; the secret-leak test scans this file.

const MAX_CARDS := 5

## The connecting line for each Hidden Hand method. {name}: the culprit.
## DRAFT, for Abe's review.
const METHOD_LINES := {
	"debt_leverage": "A debt, bought and called in. {name} held the note.",
	"sabotage": "Not an accident. {name} arranged it.",
	"forged_records": "Forged paperwork. {name}'s hand.",
	"cornering_a_market": "Someone buying up the supply, quietly. {name}.",
	"blackmail": "Someone who couldn't say no. {name} made sure of it.",
	"impersonation": "Someone wearing another's name. It was {name}.",
	"manufactured_crisis": "A crisis made to order. {name} ordered it.",
	"proxy_violence": "Hired hands. {name} paid them.",
	"slow_infiltration": "One of {name}'s people, placed long before we arrived.",
	"information_control": "We only heard what {name} wanted us to hear.",
	"bribery": "Money in the right pocket. {name}'s money.",
	"false_flag": "Blame laid at the wrong door. {name} laid it.",
}

## The scene's spoken lines. Approved by Abe 2026-10-05. {name}: the culprit;
## {lodestar}: the Lodestar's title; {bridge}: the season's approved bridge.
const NOVA_OPEN := "I kept everything, Captain. Every odd detail. Look."
## As she lays the cards down; the method's line lands on the last one.
const CONNECTORS := ["It started here.", "Then this.", "And this.", "This too."]
const NOVA_STOP := "...Wait."
## Full version (once per campaign): she calls Kaelen herself.
const FULL := [
	["nova_comms", "Kaelen. It's {name}. You were right."],
	["kaelen", "I'm always right. Show me."],
	["kaelen", "There it is. {bridge}"],
	["kaelen", "...Shiny. Didn't see you there. Well. Now you know what you're flying into."],
	["nova", "Ready when you are, Captain."],
]
## Later seasons: they've learned to be careful.
const SHORT := [
	["nova_comms", "Kaelen. {name}."],
	["kaelen", "I see it. {bridge} Go on, Shiny. Finish it."],
	["nova", "Ready when you are, Captain."],
]


## The clues to show: real traces the Captain saw and the reveal linked,
## pinned first, then spread across systems, shown in the order found.
## `threads`: PremiseDirector.main_story_threads() after the reveal.
static func pick_clues(threads: Array, max_cards: int = MAX_CARDS) -> Array:
	var linked := threads.filter(func(t): return t.has("explanation") and bool(t.get("trace", false)))
	if linked.size() < 3:
		# Too few real traces (a reveal forced at the Lodestar): any linked note.
		linked = threads.filter(func(t): return t.has("explanation"))
	var pinned := linked.filter(func(t): return bool(t.get("pinned", false)))
	var rest := linked.filter(func(t): return not bool(t.get("pinned", false)))
	var picked: Array = pinned.slice(0, max_cards)
	var systems := {}
	for t in picked:
		systems[str(t.get("system", ""))] = true
	# A spread of systems first, then whatever is left.
	for pass_n in 2:
		for t in rest:
			if picked.size() >= max_cards:
				break
			if picked.has(t):
				continue
			if pass_n == 0 and systems.has(str(t.get("system", ""))):
				continue
			picked.append(t)
			systems[str(t.get("system", ""))] = true
	picked.sort_custom(func(a, b): return int(a.get("seen_minute", 0)) < int(b.get("seen_minute", 0)))
	return picked


## The whole scene as steps: [{who, text, card?}]. who: "nova" (cockpit),
## "nova_comms" (her on the channel), "kaelen" (on comms), "card".
static func build(threads: Array, name: String, method: String, bridge: String, lodestar: String, first_time: bool) -> Array:
	var clues := pick_clues(threads)
	if clues.is_empty() or name.is_empty():
		return []
	var link := str(METHOD_LINES.get(method, "{name}. Again.")).replace("{name}", name)
	var steps: Array = [{"who": "nova", "text": NOVA_OPEN}]
	for i in clues.size():
		var c: Dictionary = clues[i]
		var last := i == clues.size() - 1
		var said := link if last else str(CONNECTORS[mini(i, CONNECTORS.size() - 1)])
		steps.append({"who": "card", "text": said, "card": {
			"where": " · ".join([str(c.get("system", "")), str(c.get("story", ""))].filter(func(s): return not str(s).is_empty())),
			"detail": str(c.get("text", "")), "link": link if last else ""}})
	steps.append({"who": "nova", "text": NOVA_STOP})
	for line in (FULL if first_time else SHORT):
		var text := str(line[1]).replace("{name}", name).replace("{lodestar}", lodestar).replace("{bridge}", bridge).strip_edges()
		steps.append({"who": str(line[0]), "text": text})
	return steps
