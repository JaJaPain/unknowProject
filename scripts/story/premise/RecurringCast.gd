class_name RecurringCast
extends RefCounted

## The recurring cast (plan Section 3.6): people from earlier arcs who remember
## the pilot and come back.
##
## Nothing new is saved: a person's history is read from the arc state (the
## arcs they were cast in and the fates their stories gave them). Casting uses
## `candidates()` for roles that prefer someone the player has met; the line
## writer gets `history_note()` so a returning face brings up the past.
##
## Everything here is public: fates are the endings the player saw. Private
## truths never appear.

## These people don't come back for another job.
const GONE_FATES := ["dead", "imprisoned"]
const BITTER_FATES := ["alive_grudge", "ruined", "exposed", "fled"]
const WARM_FATES := ["alive_grateful", "owes_debt", "promoted"]
## How casting weighs a returning face: strong feelings come back more often.
const WEIGHTS := {"bitter": 3, "warm": 3, "mixed": 2, "neutral": 1}
## Third-person phrases for the line writer's brief.
const FATE_PHRASES := {
	"alive_grudge": "it went badly for them, they still blame the pilot for it, and they are not hiding it",
	"ruined": "they lost nearly everything",
	"exposed": "what they were hiding came out",
	"fled": "they ran and had to start over",
	"alive_grateful": "the pilot came through for them and they haven't forgotten",
	"owes_debt": "they still owe the pilot",
	"promoted": "they came out of it with a promotion",
	"disappeared": "they dropped out of sight for a while",
}


## person entity id -> {display_name, appearances: [{arc_id, system_id, status}], fates, attitude, busy}
static func people(state: Dictionary) -> Dictionary:
	var out := {}
	var arcs: Dictionary = state.get("arcs", {})
	var ids := arcs.keys()
	ids.sort()  # arc ids are sequential, so this is story order
	for arc_id in ids:
		var a: Dictionary = arcs[arc_id]
		if not bool(a.get("shown", false)):
			continue
		for role_id in (a.get("cast", {}) as Dictionary).keys():
			var entry: Dictionary = a["cast"][role_id]
			if str(entry.get("kind", "")) != "person":
				continue
			var eid := str(entry.get("entity_id", ""))
			var p: Dictionary = out.get(eid, {"display_name": str(entry.get("display_name", "")), "appearances": [], "busy": false})
			(p["appearances"] as Array).append({"arc_id": str(arc_id), "system_id": str(a.get("system_id", "")), "status": str(a.get("status", ""))})
			if str(a.get("status", "")) != "resolved":
				p["busy"] = true
			out[eid] = p
	for eid in out.keys():
		var fates: Array = (state.get("fates", {}) as Dictionary).get(eid, [])
		out[eid]["fates"] = fates.duplicate()
		out[eid]["attitude"] = attitude(fates)
	return out


## The feeling their LAST ending left: bitter, warm, mixed (nothing said), gone.
static func attitude(fates: Array) -> String:
	if fates.is_empty():
		return "neutral"
	var last := str(fates[fates.size() - 1])
	if last in GONE_FATES or "dead" in fates:
		return "gone"
	if last in BITTER_FATES:
		return "bitter"
	if last in WARM_FATES:
		return "warm"
	return "mixed"


## People who can be cast again: met, alive and free, not already in a live
## story. [{id, display_name, attitude, weight}], strongest feelings first.
static func candidates(state: Dictionary) -> Array:
	var out: Array = []
	var all := people(state)
	var busy := busy_ids(state)
	for eid in all.keys():
		var p: Dictionary = all[eid]
		if busy.has(eid) or str(p["attitude"]) == "gone":
			continue
		out.append({"id": eid, "display_name": str(p["display_name"]), "attitude": str(p["attitude"]),
			"weight": int(WEIGHTS.get(str(p["attitude"]), 1))})
	out.sort_custom(func(x, y): return int(x["weight"]) > int(y["weight"]) or (int(x["weight"]) == int(y["weight"]) and str(x["id"]) < str(y["id"])))
	return out


## Everyone cast in a live story, shown yet or not (two arcs can start on the
## same arrival, before either is on the board).
static func busy_ids(state: Dictionary) -> Dictionary:
	var out := {}
	var arcs: Dictionary = state.get("arcs", {})
	for arc_id in arcs.keys():
		var a: Dictionary = arcs[arc_id]
		if str(a.get("status", "")) == "resolved":
			continue
		for entry in (a.get("cast", {}) as Dictionary).values():
			if str(entry.get("kind", "")) == "person":
				out[str(entry.get("entity_id", ""))] = true
	return out


## What the pilot and this person went through before `current_arc_id`, as a
## public third-person note for the line writer. "" for a first meeting.
static func history_note(state: Dictionary, person_id: String, system_names: Dictionary, current_arc_id: String = "") -> String:
	var p: Dictionary = people(state).get(person_id, {})
	if p.is_empty():
		return ""
	var before: Array = (p["appearances"] as Array).filter(func(x): return str(x["arc_id"]) != current_arc_id)
	if before.is_empty():
		return ""
	var last: Dictionary = before[before.size() - 1]
	var where := str(system_names.get(str(last["system_id"]), ""))
	var place := (" in %s" % where) if not where.is_empty() else ""
	var fates: Array = p.get("fates", [])
	var fate := str(fates[fates.size() - 1]) if not fates.is_empty() else ""
	var times: String = ["once before", "twice before", "three times before"][mini(before.size(), 3) - 1] if before.size() <= 3 else "several times before"
	if FATE_PHRASES.has(fate):
		return "They have dealt with the pilot %s; last time%s, %s." % [times, place, FATE_PHRASES[fate]]
	return "They have dealt with the pilot %s%s." % [times, place]
