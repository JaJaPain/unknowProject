class_name PremiseCasting
extends RefCounted

## Fills a premise card's roles with things that exist in the world.
##
## `world` is a plain snapshot (built from GlobalState by the live adapter):
##   system_id: String, system_display: String
##   main_station: {id, display}
##   outposts: Array[{id, display}]            dockable places besides the main station
##   factions: Array[{id, display_name}]       generated factions castable here
##   hostile_factions: Array[String]           faction keys whose ships can be spawned as targets
##   known_npcs: Array[{id, display_name}]     people the player has met (for prefer_existing)
##
## Returns {role_id: {kind, entity_id, display_name, ...}}. Deterministic for a
## given seed. Every role gets a cast entry, so text placeholders always resolve.

const NameForgeType := preload("res://scripts/story/premise/NameForge.gd")


static func cast_card(card: Dictionary, world: Dictionary, seed_value: int, arc_id: String = "arc") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%s|cast" % [seed_value, str(card.get("id", ""))])
	var cast := {}
	var roles: Array = card.get("roles", [])

	# Places: prefer the stations/outposts, distinct where possible, in the order
	# the story first uses them, so a courier's origin and destination differ.
	var docks: Array = []
	for o in world.get("outposts", []):
		docks.append(o)
	var main: Dictionary = world.get("main_station", {})
	if not main.is_empty():
		docks.append(main)
	var place_order := _roles_in_use_order(card, "place")
	var used_docks := 0
	for role_id in place_order:
		var dock: Dictionary = docks[used_docks % docks.size()] if not docks.is_empty() else {"id": "start_system", "display": "the main station"}
		used_docks += 1
		cast[role_id] = {"kind": "place", "entity_id": str(dock.get("id", "")), "display_name": str(dock.get("display", dock.get("id", "")))}

	# Factions: distinct generated factions, repeating only if the card needs more.
	var factions: Array = world.get("factions", [])
	var faction_index := 0
	for role in roles:
		if str(role.get("kind", "")) != "faction":
			continue
		if factions.is_empty():
			cast[role["id"]] = {"kind": "faction", "entity_id": "faction.neutral", "display_name": _humanize(str(role["id"]))}
		else:
			var f: Dictionary = factions[faction_index % factions.size()]
			cast[role["id"]] = {"kind": "faction", "entity_id": str(f.get("id", "")), "display_name": str(f.get("display_name", f.get("id", ""))),
				"spawn_key": str(f.get("spawn_key", ""))}
		faction_index += 1

	# People: reuse someone the player knows when the card prefers it.
	var known: Array = (world.get("known_npcs", []) as Array).duplicate()
	for role in roles:
		if str(role.get("kind", "")) != "person":
			continue
		var role_id := str(role["id"])
		if str(role.get("reuse", "")) == "prefer_existing" and not known.is_empty():
			# Priority people (the main story's likely culprit) come back first, so
			# the eventual reveal has been on screen all along.
			var index := rng.randi_range(0, known.size() - 1)
			for i in known.size():
				if str(known[i].get("id", "")) in (world.get("priority_npc_ids", []) as Array):
					index = i
					break
			var pick: Dictionary = known.pop_at(index)
			cast[role_id] = {"kind": "person", "entity_id": str(pick.get("id", "")), "display_name": str(pick.get("display_name", "")),
				"archetype": str(role.get("archetype", "")), "reused": true}
		else:
			var name := NameForgeType.person_name(rng)
			cast[role_id] = {"kind": "person", "entity_id": "npc.%s.%s" % [arc_id.replace(".", "_"), role_id], "display_name": name,
				"archetype": str(role.get("archetype", "")), "reused": false}

	# Ships: belong to the faction whose role name they share, else a hostile faction.
	var hostile: Array = world.get("hostile_factions", [])
	for role in roles:
		if str(role.get("kind", "")) != "ship":
			continue
		var role_id := str(role["id"])
		var owner := _owner_faction_role(role_id, cast)
		# Combat targets must be spawnable: the owner's spawn key, else a hostile faction here.
		var faction_key := str(cast[owner].get("spawn_key", "")) if not owner.is_empty() else ""
		if faction_key.is_empty():
			faction_key = str(hostile[rng.randi_range(0, hostile.size() - 1)]) if not hostile.is_empty() else "reavers"
		cast[role_id] = {"kind": "ship", "entity_id": "ship.%s.%s" % [arc_id.replace(".", "_"), role_id],
			"display_name": NameForgeType.ship_name(rng), "faction_key": faction_key}

	# Objects: a short item name from the role id ("sample_cases" -> "sample cases").
	for role in roles:
		if str(role.get("kind", "")) != "object":
			continue
		cast[role["id"]] = {"kind": "object", "entity_id": "item.%s.%s" % [arc_id.replace(".", "_"), role["id"]],
			"display_name": _humanize(str(role["id"]))}

	# Anything left (unknown kinds) still resolves in text.
	for role in roles:
		if not cast.has(str(role.get("id", ""))):
			cast[str(role["id"])] = {"kind": str(role.get("kind", "")), "entity_id": str(role["id"]), "display_name": _humanize(str(role["id"]))}
	return cast


## Replaces {role:x}, {system} and {player} in card text.
static func fill_text(text: String, cast: Dictionary, world: Dictionary) -> String:
	var out := text
	for role_id in cast.keys():
		out = out.replace("{role:%s}" % role_id, str(cast[role_id].get("display_name", role_id)))
	out = out.replace("{system}", str(world.get("system_display", "the system")))
	out = out.replace("{player}", "the pilot")
	return out


## Place roles in the order missions first mention them as targets.
static func _roles_in_use_order(card: Dictionary, kind: String) -> Array[String]:
	var of_kind: Array[String] = []
	for role in card.get("roles", []):
		if str(role.get("kind", "")) == kind:
			of_kind.append(str(role["id"]))
	var ordered: Array[String] = []
	for beat in card.get("beats", []):
		for mission in beat.get("missions", []):
			var t := str(mission.get("target", ""))
			if t in of_kind and not t in ordered:
				ordered.append(t)
	for role_id in of_kind:
		if not role_id in ordered:
			ordered.append(role_id)
	return ordered


static func _owner_faction_role(ship_role_id: String, cast: Dictionary) -> String:
	var ship_words := ship_role_id.split("_")
	for role_id in cast.keys():
		if str(cast[role_id].get("kind", "")) != "faction":
			continue
		for word in str(role_id).split("_"):
			if word.length() >= 4 and word in ship_words:
				return str(role_id)
	return ""


static func _humanize(role_id: String) -> String:
	return role_id.replace("_", " ").strip_edges()
