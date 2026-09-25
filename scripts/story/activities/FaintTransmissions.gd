extends RefCounted

## What signal tuning can pull out of the static in a system.
##
## First choice: a main-story loose thread from a live arc here, one the card
## meant to be heard (surface "radio" or "dialogue") that the captain has not
## noticed yet. Overhearing it notices it, so it lands on the Loose ends board.
## Otherwise: ambient chatter, which N.O.V.A. can sell to a data broker.
##
## The speaker is one of the arc's people, voiced by their Voice DNA, but never
## named: it is an intercept, not an introduction.

const HandType := preload("res://scripts/story/premise/HiddenHand.gd")
const ArcsType := preload("res://scripts/story/premise/ArcEngine.gd")
const CastingType := preload("res://scripts/story/premise/PremiseCasting.gd")

const HEARD_SURFACES := ["radio", "dialogue"]
## Broker prices for ambient intercepts, by outcome.
const AMBIENT_PAY := {"clean": 60, "partial": 25, "assisted": 15}

## Hand-written; no model. Overheard, so mid-sentence is fine.
const AMBIENT: Array[String] = [
	"…told you the manifest says grain. It says grain because I wrote grain. Load it and stop asking.",
	"…second shift at the relay, nobody signs for anything after midnight, so that's when we move it.",
	"…if the inspector asks, the damage was a micrometeorite. Two of them. Very unlucky micrometeorites.",
	"…she paid in old scrip, the kind nobody takes anymore. I took it. Don't look at me like that.",
	"…three days out and the coolant's already cloudy. Somebody sold us recycled and called it new.",
	"…no, the other beacon. The one that isn't on any chart. Yes, that one. Meet me there.",
	"…tell my brother the debt's paid, and if he asks how, tell him not to ask how.",
	"…the patrol changes at the top of the hour, and for about four minutes nobody's watching the east lane.",
	"…I'm not saying the station master's crooked. I'm saying his ship is very new for a station master.",
	"…if you hear this, the cargo's in the third container from the left. If you're not you, forget that.",
	"…price doubled overnight. Same ore, same rock, same miners. Somebody upstream wants us to quit.",
	"…keep the channel quiet. They listen on this band. Switch to the old one after the tone.",
]


## Unheard threads here, in thread order: [{thread_id, arc_id, detail, cast}].
## `surfaces` defaults to what can be overheard; the drone maze asks for
## "wreck" threads instead (a recorder deep in a wreck).
static func thread_candidates(state: Dictionary, system_id: String, surfaces: Array = HEARD_SURFACES) -> Array:
	var out: Array = []
	for t in HandType.main_story(state).get("threads", []):
		if bool(t.get("seen", false)) or str(t.get("surface", "")) not in surfaces:
			continue
		var a := ArcsType.arc(state, str(t.get("arc_id", "")))
		if a.is_empty() or str(a.get("system_id", "")) != system_id:
			continue
		out.append({"thread_id": str(t["id"]), "arc_id": str(t["arc_id"]), "detail": str(t.get("detail", "")), "cast": a.get("cast", {})})
	return out


## The transmission to tune into here: {id, kind, text, speaker_id, thread_id?}.
## `heard_ambient` lists ambient ids already heard this campaign; when every
## ambient line is used the pool starts over.
static func pick(state: Dictionary, system_id: String, system_display: String, heard_ambient: Array, seed_value: int) -> Dictionary:
	var threads := thread_candidates(state, system_id)
	if not threads.is_empty():
		var c: Dictionary = threads[0]
		var speaker := _speaker(c["cast"], seed_value)
		return {
			"id": "thread:%s" % c["thread_id"], "kind": "thread", "thread_id": c["thread_id"],
			"text": "…" + CastingType.fill_text(str(c["detail"]), c["cast"], {"system_display": system_display}),
			"speaker_id": speaker, "speaker_name": _name_of(c["cast"], speaker),
		}
	var fresh: Array[int] = []
	for i in AMBIENT.size():
		if not heard_ambient.has("ambient:%d" % i):
			fresh.append(i)
	if fresh.is_empty():
		fresh.assign(range(AMBIENT.size()))
	var index: int = fresh[posmod(seed_value, fresh.size())]
	return {"id": "ambient:%d" % index, "kind": "ambient", "text": AMBIENT[index], "speaker_id": "intercept.%s.%d" % [system_id, index]}


static func _name_of(cast: Dictionary, entity_id: String) -> String:
	for role_id in cast.keys():
		if str(cast[role_id].get("entity_id", "")) == entity_id:
			return str(cast[role_id].get("display_name", ""))
	return ""


## One of the arc's people, chosen by seed, else an anonymous id.
static func _speaker(cast: Dictionary, seed_value: int) -> String:
	var people: Array = []
	for role_id in cast.keys():
		if str(cast[role_id].get("kind", "")) == "person":
			people.append(str(cast[role_id].get("entity_id", "")))
	people.sort()
	if people.is_empty():
		return "intercept.unknown"
	return str(people[posmod(seed_value, people.size())])
