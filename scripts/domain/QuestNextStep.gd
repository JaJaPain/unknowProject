extends RefCounted

## What to do next for the active quest, in one plain sentence that names the
## place and the person (playtest 2026-10-03 finding 14: a pickup said "Pick
## up Unlabeled Heat Sink" and never where, or from whom, or that it was at
## an outpost; the player looked for it in the lounge).
##
## Used by the quest tracker; the smoke test checks it names real things.

## Contacts are named "<organisation> <first> <last>"; in a sentence the
## person is enough.
static func person_name(full_name: String) -> String:
	var parts := full_name.strip_edges().split(" ", false)
	if parts.size() <= 2:
		return full_name.strip_edges()
	return "%s %s" % [parts[-2], parts[-1]]


## The main station here (where board jobs and agent jobs are handed in).
static func hand_in_name() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var gs: Node = tree.root.get_node_or_null("GlobalState") if tree != null else null
	var station = gs.get_primary_station() if gs != null and gs.has_method("get_primary_station") else null
	if station != null and is_instance_valid(station):
		var display = station.get("display_name")
		if display != null and not str(display).strip_edges().is_empty():
			return str(display)
	return "the main station"


## Where a picked-up item goes, as a name: the job's destination when it's a
## real name, else the main station here (old jobs said "Grease Monkeys"
## everywhere; collection jobs store a station id).
static func destination_name(q: Dictionary) -> String:
	var where := str(q.get("destination", "")).strip_edges()
	# The mechanic's own parts runs go back to the mechanic's shop, by name.
	if bool(q.get("station_errand", false)) and not where.is_empty():
		return where
	if where.is_empty() or where == "Grease Monkeys" or (where.contains(".") and not where.contains(" ")):
		return hand_in_name()
	return where


## The lounge hunt's suspect so far ("" before anyone's been caught out).
static func hunt_suspect(q: Dictionary) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var story: Node = tree.root.get_node_or_null("StoryManager") if tree != null else null
	if story == null:
		return ""
	var all = story.story_state.get(preload("res://scripts/domain/PickupHunt.gd").STATE_KEY)
	if not all is Dictionary:
		return ""
	var key := "%s|%s|%s" % [str(q.get("title", "")), str(q.get("target_outpost", "")), str(q.get("part_name", ""))]
	var s = (all as Dictionary).get(key)
	return preload("res://scripts/domain/PickupHunt.gd").suspect(s, str(q.get("target_npc", ""))) if s is Dictionary else ""


## {text}: the next step for quest `q` (QuestManager.active_quest's shape).
static func for_quest(q: Dictionary) -> Dictionary:
	var kind := str(q.get("objective_type", ""))
	if kind == "PICKUP_SPECIAL":
		var part := str(q.get("part_name", "the package"))
		if bool(q.get("picked_up", false)):
			if bool(q.get("station_errand", false)):
				return {"text": "Bring the %s back to %s at %s (Maintenance)." % [part, str(q.get("agent_name", "the mechanic")), destination_name(q)]}
			return {"text": "Bring the %s to %s and hand it in (Talk to Agent)." % [part, destination_name(q)]}
		var outpost := str(q.get("target_outpost_display", "the outpost"))
		# Board pickups are a lounge hunt: who has it is for the player to find.
		if bool(q.get("lounge_hunt", false)):
			# Once someone's named them (or they slipped), say who to lean on.
			var suspect := hunt_suspect(q)
			if not suspect.is_empty():
				return {"text": "%s has the %s, at %s. Keep pushing them (a drink helps)." % [person_name(suspect), part, outpost]}
			return {"text": "Dock at %s (outpost). Someone in its lounge has the %s and won't just hand it over: ask around, find who, and keep pushing them." % [outpost, part]}
		var person := person_name(str(q.get("target_npc", "the contact")))
		return {"text": "Dock at %s (outpost) and ask %s for the %s: in the dock menu, or by their card in the lounge." % [outpost, person, part]}
	return {"text": ""}
