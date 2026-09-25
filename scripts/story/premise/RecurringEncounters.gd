extends RefCounted

## The recurring cast in person (vision plan 3.6 and 4.5): now and then, a
## little while after the captain arrives in a system, someone from an
## earlier story finds them.
##   bitter  -> they hail, then come at the captain in their own ship. Destroy
##              it and the feud is over for good (their fate becomes "dead",
##              and the factions hear of it); get away and it goes on.
##   warm    -> they hail to repay the captain: credits, or a survey drone.
## Hand-written lines, filled with their name and where the two last met.
##
## Not every arrival: a quiet stretch between encounters, and the same person
## not again for a long while.
##
## PURE and seeded; the encounter log lives in the premise director's state.

const RC := preload("res://scripts/story/premise/RecurringCast.gd")

const CHANCE := 0.3
## Arrivals between any two encounters, and between two with the same person.
const MIN_ARRIVALS_BETWEEN := 3
const MIN_ARRIVALS_SAME_PERSON := 8
const GIFT_CREDITS := Vector2i(120, 260)
const GIFT_DRONE_CHANCE := 0.3

const LINES := {
	"bitter": [
		"{name}. Remember me? You should. {where_sentence} I've been looking for you ever since.",
		"There you are. {where_sentence} No contract to hide behind this time, just you and me.",
		"You cost me everything. {where_sentence} I told myself if I ever saw your ship again, I'd end it.",
	],
	"warm": [
		"Captain, it's {name}. {where_sentence} I never thanked you properly. Here, take this.",
		"{name} here. I owe you from before. {where_sentence} This should help.",
		"Good to see your ship again. {where_sentence} I've been holding something for you.",
	],
}
const WHERE := {
	"bitter": "After what happened in {where}, did you think I'd just go away?",
	"warm": "What you did in {where} turned it around for me.",
}


static func empty_log() -> Dictionary:
	return {"arrivals": 0, "last_arrival": -100, "met": {}}


## Counts an arrival and maybe picks someone to show up. Returns
## {log, encounter}; encounter is {} when nobody does. `system_names` maps
## system ids to display names.
static func on_arrival(state: Dictionary, log: Dictionary, system_names: Dictionary, seed_value: int) -> Dictionary:
	var next := log.duplicate(true) if not log.is_empty() else empty_log()
	next["arrivals"] = int(next.get("arrivals", 0)) + 1
	var n := int(next["arrivals"])
	if n - int(next.get("last_arrival", -100)) < MIN_ARRIVALS_BETWEEN:
		return {"log": next, "encounter": {}}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("encounter|%d|%d" % [seed_value, n])
	if rng.randf() >= CHANCE:
		return {"log": next, "encounter": {}}
	var people := RC.people(state)
	var busy := RC.busy_ids(state)
	var pool: Array = []
	var met: Dictionary = next.get("met", {})
	for pid in people.keys():
		var p: Dictionary = people[pid]
		var attitude := str(p.get("attitude", ""))
		if attitude not in ["bitter", "warm"] or busy.has(pid):
			continue
		if n - int(met.get(pid, -100)) < MIN_ARRIVALS_SAME_PERSON:
			continue
		pool.append(pid)
	if pool.is_empty():
		return {"log": next, "encounter": {}}
	pool.sort()
	var pid: String = pool[rng.randi() % pool.size()]
	var p: Dictionary = people[pid]
	var attitude := str(p["attitude"])
	var last: Dictionary = (p["appearances"] as Array).back()
	var where := str(system_names.get(str(last.get("system_id", "")), ""))
	var where_sentence := str(WHERE[attitude]).replace("{where}", where) if not where.is_empty() else ""
	var lines: Array = LINES[attitude]
	var line := str(lines[rng.randi() % lines.size()]).replace("{name}", str(p["display_name"])).replace("{where_sentence}", where_sentence)
	met[pid] = n
	next["met"] = met
	next["last_arrival"] = n
	var encounter := {"person_id": pid, "display_name": str(p["display_name"]), "attitude": attitude,
		"line": line.replace("  ", " ").strip_edges(), "where": where}
	if attitude == "warm":
		if rng.randf() < GIFT_DRONE_CHANCE:
			encounter["gift"] = {"item": "survey_drone"}
		else:
			encounter["gift"] = {"credits": rng.randi_range(GIFT_CREDITS.x, GIFT_CREDITS.y)}
	return {"log": next, "encounter": encounter}


## What the feud's end does to the story state: their fate becomes "dead"
## (they will not come back) and a deed is left. Returns the new state.
static func feud_ended(state: Dictionary, person_id: String, display_name: String, system_id: String) -> Dictionary:
	var next := state.duplicate(true)
	var fates: Dictionary = next.get("fates", {})
	var list: Array = (fates.get(person_id, []) as Array).duplicate()
	list.append("dead")
	fates[person_id] = list
	next["fates"] = fates
	if not next.get("deeds") is Array:
		next["deeds"] = []
	(next["deeds"] as Array).append({"tag": "killed_old_enemy", "system_id": system_id,
		"public_summary": "%s came after a pilot over an old grudge, and did not fly home." % display_name})
	return next
