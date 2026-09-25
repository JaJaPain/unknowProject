extends RefCounted

## Failing forward (vision plan 4.3): a job that fails, is abandoned or runs
## out of time does not just vanish from the board. It changes the system it
## was in for a while, in a way the captain can feel and hear:
##   supply jobs     -> a shortage (store prices up), a state the radio reports;
##   security jobs   -> raiders grow bolder (more hostile ships appear);
##   information     -> the trail goes cold.
## Each also costs a little standing with whoever posted it, and puts one
## item on the system radio saying what happened.
##
## PURE: builds fallout records; the director stores and expires them, and
## GameRoot turns the active ones into the system environment.

const DEFAULT_PATH := "res://data/content/failure_fallout.json"
const FAILED_STATES := ["abandoned", "expired", "failed"]

static var _deck: Dictionary = {}


static func deck() -> Dictionary:
	if _deck.is_empty():
		var file := FileAccess.open(DEFAULT_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_deck = parsed
	return _deck


static func family_for(objective_type: String) -> String:
	var families: Dictionary = deck().get("families", {})
	for family in families.keys():
		if objective_type in (families[family].get("objective_types", []) as Array):
			return str(family)
	return ""


## The fallout of a finished mission, or {} (completed, tutorial, unknown
## type, or no system). `names`: {system, place, requester, faction} display
## names for the radio line.
static func for_mission(quest_data: Dictionary, terminal_state: String, now_minute: int, names: Dictionary) -> Dictionary:
	if terminal_state not in FAILED_STATES:
		return {}
	var objective_type := str(quest_data.get("objective_type", (quest_data.get("objective", {}) as Dictionary).get("type", "")))
	var family := family_for(objective_type)
	var system_id := str(quest_data.get("system_id", names.get("system_id", "")))
	if family.is_empty() or system_id.is_empty():
		return {}
	var spec: Dictionary = deck()["families"][family]
	var lines: Array = spec.get("radio", [])
	var runtime_id := str(quest_data.get("runtime_id", quest_data.get("title", "mission")))
	var line := str(lines[posmod(runtime_id.hash(), lines.size())]) if not lines.is_empty() else ""
	for key in ["requester", "system", "place", "faction"]:
		line = line.replace("{%s}" % key, str(names.get(key, "")).strip_edges() if not str(names.get(key, "")).strip_edges().is_empty() else _fallback(key))
	return {
		"id": "fallout:%s" % runtime_id,
		"family": family,
		"system_id": system_id,
		"state": str(spec.get("state", "")),
		"environment": (spec.get("environment", {}) as Dictionary).duplicate(),
		"standing_delta": int(spec.get("standing_delta", 0)),
		"requester_faction": str(quest_data.get("faction", "")),
		"radio": line,
		"since_minute": now_minute,
		"until_minute": now_minute + int(deck().get("duration_minutes", 480)),
	}


static func _fallback(key: String) -> String:
	match key:
		"requester":
			return "a local contact"
		"system":
			return "the system"
		"place":
			return "the station"
		"faction":
			return "raider"
	return ""


## Active fallout records for a system at `now_minute`.
static func active(records: Array, system_id: String, now_minute: int) -> Array:
	var out: Array = []
	for f in records:
		if f is Dictionary and str(f.get("system_id", "")) == system_id and int(f.get("until_minute", 0)) > now_minute:
			out.append(f)
	return out


## The environment active fallout gives a system: multipliers compound (two
## missed deliveries make things tighter than one), capped.
static func environment(records: Array) -> Dictionary:
	var env := {}
	for f in records:
		for key in (f.get("environment", {}) as Dictionary).keys():
			env[key] = minf(2.0, float(env.get(key, 1.0)) * float(f["environment"][key]))
	return env


## Records past their time, dropped (keeps saves small).
static func prune(records: Array, now_minute: int) -> Array:
	return records.filter(func(f): return f is Dictionary and int(f.get("until_minute", 0)) > now_minute)
