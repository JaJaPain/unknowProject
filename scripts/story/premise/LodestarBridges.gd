extends RefCounted

## The Hidden Hand wants what's at the Lodestar (campaign spine plan, section
## 3; bridges approved by Abe 2026-10-05): each Lodestar hosts some of the
## Hidden Hand's goals, with an authored line on why that person needs that
## place. Data: data/content/lodestar_bridges.json.

const PATH := "res://data/content/lodestar_bridges.json"

static var _cache: Dictionary = {}


static func _all() -> Dictionary:
	if _cache.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_cache = (parsed as Dictionary).get("bridges", {})
	return _cache


## The goal ids this Lodestar hosts ([] for an unknown Lodestar: any goal).
static func goals_for(lodestar_id: String) -> Array:
	return (_all().get(lodestar_id, {}) as Dictionary).keys()


## Why this goal needs this place ("" if the pair has no bridge).
static func bridge(lodestar_id: String, goal_id: String) -> String:
	return str((_all().get(lodestar_id, {}) as Dictionary).get(goal_id, ""))
