class_name PremiseWorldSnapshot
extends RefCounted

## Captures the live game into the plain `world` dictionary the premise
## classes read (see PremiseCasting / PremiseMissionComposer / PremiseDirector).
##
## This is the ONLY premise file that reads the running game. Everything it
## returns is data; nothing downstream touches GlobalState or the scene tree.
## Missing pieces degrade to safe defaults (a story simply has fewer options).

const BoardBuilderType := preload("res://scripts/domain/PublicBoardOfferBuilder.gd")


static func capture(now_minute: int) -> Dictionary:
	var gs: Node = _global_state()
	var system_id := str(gs.get("current_system_id")) if gs != null else "start_system"
	var config = BoardBuilderType._current_system_config()
	var world := {
		"system_id": system_id,
		"system_display": str(config.system_name) if config != null else system_id,
		"system_seed": int(config.seed_value) if config != null else 0,
		"star_type": str(config.star_type) if config != null else "yellow",
		"is_first_system": _is_home(),
		"post_tutorial": _post_tutorial(),
		# Card investigations are not yet wired to the live scan system.
		"investigation_fallback": true,
		"main_station": {"id": system_id, "display": "the main station"},
		"outposts": [],
		"factions": [],
		"hostile_factions": [],
		"known_npcs": [],
		"store_items": [],
	}
	if gs == null:
		return world

	# Main station display, if the primary station is loaded.
	if gs.has_method("get_primary_station"):
		var station = gs.call("get_primary_station")
		if station != null and "display_name" in station and not str(station.display_name).is_empty():
			world["main_station"]["display"] = str(station.display_name)

	# Docks: only places a delivery can actually be handed over at (the board
	# refuses deliveries without a verified recipient at the destination).
	var outposts: Array = []
	for outpost in gs.call("get_current_pickup_outposts"):
		if outpost is Dictionary and not (gs.call("get_delivery_recipient", str(outpost.get("id", ""))) as Dictionary).is_empty():
			outposts.append({"id": str(outpost["id"]), "display": str(outpost.get("display", outpost["id"]))})
	world["outposts"] = outposts

	if config != null and config.story_pack is Dictionary:
		for agenda in config.story_pack.get("faction_agendas", []):
			if agenda is Dictionary and not str(agenda.get("faction_id", "")).is_empty():
				var faction_id := str(agenda["faction_id"])
				# Ships spawn under the LEGACY key (faction_weights); the canonical id
				# is only for identity. A faction with no spawn key here can't be a
				# combat target, so casting falls back to a hostile faction.
				var spawn_key := ""
				for legacy in config.faction_id_lookup.keys():
					if str(config.faction_id_lookup[legacy]) == faction_id and config.faction_weights.has(legacy):
						spawn_key = str(legacy)
						break
				(world["factions"] as Array).append({"id": faction_id, "display_name": str(agenda.get("faction_name", faction_id)), "spawn_key": spawn_key})

	for key in gs.call("get_current_system_minor_factions"):
		(world["hostile_factions"] as Array).append(str(key))

	var item: Dictionary = BoardBuilderType._store_purchase_item(now_minute)
	if not item.is_empty():
		(world["store_items"] as Array).append(item)
	return world


static func _is_home() -> bool:
	var gs := _global_state()
	return gs != null and bool(gs.call("is_current_system_home"))


static func _post_tutorial() -> bool:
	var loop := Engine.get_main_loop()
	if loop == null or not loop is SceneTree:
		return false
	var story = (loop as SceneTree).root.get_node_or_null("StoryManager")
	if story == null or not "story_state" in story:
		return false
	return bool((story.story_state as Dictionary).get("first_contract_handed_in", false))


static func _global_state() -> Node:
	var loop := Engine.get_main_loop()
	if loop == null or not loop is SceneTree:
		return null
	return (loop as SceneTree).root.get_node_or_null("GlobalState")
