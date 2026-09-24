class_name RadioBroadcaster
extends RefCounted

## Assembles a system's radio from the story state (plan Sections 3.4, 4.6):
##   - headlines from the stories live in this system (cards' radio_hooks),
##   - the pilot's deeds from OTHER systems, arriving late and retold as rumour,
##   - news about the system itself (states and laws that arcs changed),
##   - main-story loose threads whose surface is "radio" (airing = noticed).
##
## Pure: returns items; the caller plays them (comms feed now, voiced later).
## Each item: {id, kind, text, thread_id?}. Ids are stable so a system never
## repeats the same item in one visit.

const ArcsType := preload("res://scripts/story/premise/ArcEngine.gd")
const HandType := preload("res://scripts/story/premise/HiddenHand.gd")
const CastingType := preload("res://scripts/story/premise/PremiseCasting.gd")
const DNAType := preload("res://scripts/story/premise/FactionDNA.gd")

## Minutes a deed takes to travel to another system as rumour.
const DEED_TRAVEL_MINUTES := 240
const RUMOUR_OPENERS := [
	"Heard from a hauler out of %s: ",
	"Word coming through the gate from %s: ",
	"Dockhands are passing this one around from %s: ",
	"Unconfirmed, out of %s: ",
]
const LOCAL_OPENERS := ["Around here they're saying: ", "Local talk: "]
## How a local faction takes the pilot's deed (FactionDNA.judge_deed). A shrug
## goes unsaid.
const DEED_REACTIONS := {
	"admire": [" %s are calling it the best thing they've heard all cycle.", " %s would buy that pilot a drink."],
	"approve": [" %s seem to think it was the right call.", " %s are nodding along."],
	"disapprove": [" %s aren't happy about it.", " %s say it was a mistake."],
	"condemn": [" %s are calling it a crime.", " %s want that pilot's name on a list."],
}
const STATE_NEWS := {
	"blockade": "Traffic advisory: a blockade is holding ships at the lanes into %s.",
	"quarantine": "Health notice: quarantine orders are in effect in parts of %s.",
	"shortage": "Supply desks across %s report shortages. Prices are climbing.",
	"boom": "Business is booming in %s, and everyone wants a piece of it.",
	"evacuation": "Evacuation convoys are forming up around %s.",
	"curfew": "Reminder: curfew is in force on %s stations after last shift.",
	"martial_law": "Martial law remains in effect across %s.",
	"price_spike": "Traders in %s are paying well over the usual rates this week.",
	"price_crash": "Prices have collapsed in %s. Sellers are sitting on full holds.",
	"refugee_influx": "Refugee ships keep arriving in %s faster than berths open up.",
	"lane_closed": "Lane closure: one of the main routes through %s is shut.",
	"lane_opened": "Good news for haulers: a lane through %s has reopened.",
	"power_vacuum": "Nobody seems to be in charge in %s right now, and everyone has noticed.",
	"festival": "Festival week in %s. Expect crowds at every dock.",
	"strike": "Workers in %s are on strike. Expect delays at the docks.",
	"crackdown": "Authorities in %s are cracking down. Keep your manifests clean.",
	"election": "Election season in %s. Every channel has an opinion.",
	"mourning": "%s is in mourning. Stations are flying their lights low.",
}
const LAW_NEWS := {
	"enacted": "New regulation in %s: %s now applies.",
	"repealed": "%s has dropped its %s rule.",
}


static func broadcast(state: Dictionary, library, world: Dictionary, now_minute: int) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var system_id := str(world.get("system_id", ""))
	var here := str(world.get("system_display", "this system"))
	var names: Dictionary = world.get("system_names", {})

	# Headlines from this system's live stories.
	for arc_id in ArcsType.active_arc_ids(state):
		var a := ArcsType.arc(state, arc_id)
		if str(a["system_id"]) != system_id:
			continue
		var card: Dictionary = library.get_card(str(a["card_id"]))
		var hooks: Array = card.get("radio_hooks", [])
		for i in hooks.size():
			items.append({"id": "%s:hook%d" % [arc_id, i], "kind": "headline",
				"text": CastingType.fill_text(str(hooks[i]), a["cast"], {"system_display": here})})

	# Deeds: local ones as talk, distant ones as late-arriving rumour.
	var deeds: Array = state.get("deeds", [])
	for i in deeds.size():
		var d: Dictionary = deeds[i]
		var summary := str(d.get("public_summary", ""))
		if summary.is_empty():
			continue
		var origin := str(d.get("system_id", ""))
		var text := CastingType.fill_text(summary, d.get("cast", {}), {"system_display": str(names.get(origin, "somewhere"))})
		var arc: Dictionary = ArcsType.arc(state, str(d.get("arc_id", "")))
		var when := int(arc.get("resolved_minute", now_minute))
		var reaction := deed_reaction(str(d.get("tag", "")), world.get("factions", []), i)
		if origin == system_id:
			items.append({"id": "deed%d" % i, "kind": "local_deed", "text": LOCAL_OPENERS[i % LOCAL_OPENERS.size()] + text + reaction})
		elif now_minute - when >= DEED_TRAVEL_MINUTES:
			var opener: String = RUMOUR_OPENERS[i % RUMOUR_OPENERS.size()] % str(names.get(origin, "another system"))
			items.append({"id": "deed%d" % i, "kind": "rumour", "text": opener + text + reaction})

	# News about this system: states and laws the stories changed.
	var change: Dictionary = (state.get("system_changes", {}) as Dictionary).get(system_id, {})
	for s in change.get("add", []):
		if STATE_NEWS.has(str(s)):
			items.append({"id": "state:%s" % s, "kind": "news", "text": STATE_NEWS[str(s)] % here})
	var laws: Dictionary = (state.get("system_laws", {}) as Dictionary).get(system_id, {})
	for law in laws.keys():
		var how := str(laws[law])
		if LAW_NEWS.has(how):
			var law_text := str(law).replace("_", " ")
			var text: String = LAW_NEWS[how] % [here, law_text]
			items.append({"id": "law:%s:%s" % [law, how], "kind": "news", "text": text})

	# Main-story threads that surface on the radio (airing them = the pilot hears them).
	for t in HandType.main_story(state).get("threads", []):
		if str(t.get("surface", "")) != "radio":
			continue
		var a := ArcsType.arc(state, str(t["arc_id"]))
		if str(a.get("system_id", "")) != system_id:
			continue
		items.append({"id": "thread:%s" % t["id"], "kind": "thread", "thread_id": str(t["id"]),
			"text": "Odd one to end on: " + CastingType.fill_text(str(t["detail"]), a.get("cast", {}), {"system_display": here})})
	return items


## One local faction's take on a deed, as a sentence to append ("" for a
## shrug or when the system has no factions). Factions take turns by deed.
static func deed_reaction(deed_tag: String, factions: Array, index: int) -> String:
	if factions.is_empty() or deed_tag.is_empty():
		return ""
	var f: Dictionary = factions[index % factions.size()]
	var view := DNAType.judge_deed(DNAType.for_faction(str(f.get("id", ""))), deed_tag)
	if not DEED_REACTIONS.has(view):
		return ""
	var options: Array = DEED_REACTIONS[view]
	var who := str(f.get("display_name", "some people here"))
	return str(options[index % options.size()]) % (who.left(1).to_upper() + who.substr(1))
