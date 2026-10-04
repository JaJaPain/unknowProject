extends RefCounted

## Scan Composition (Abe, playtest 2026-10-04 findings 6 and 8): a pulse from
## the ship reads the ore in every ordinary rock within range, and the
## overview then names each one by it ("Water ice asteroid"). Unscanned rocks
## read "Asteroid". Red rocks (tech-grade seams) can't be read; a survey drone
## finds out what's in them. Mining a rock also tells you what it is.

const WorldScale := preload("res://scripts/domain/WorldScale.gd")
const OreTypes := preload("res://scripts/economy/OreTypes.gd")

## How far the pulse reaches (world units; 80 m as the player reads it).
## A rule of thumb, not a count (Abe, playtest 2026-10-04 c: "the 10 or so
## asteroids near the ship, not half the belt... a reasonable bubble so the
## player has to scan and move"). A start-system belt has a rock every ~70
## units along its arc, so this takes in about ten.
const RANGE := 400.0
## Scanned rocks stay on the overview out to here, past the usual rock
## sensor range, so what the scan found can be picked from the list.
const LIST_RANGE := RANGE * 1.25
## The key (C for Composition).
const KEY := KEY_C
## Seconds before the scanner can pulse again.
const COOLDOWN_S := 10.0  # Abe, 2026-10-04
const META := "ore_scanned"


static func is_scanned(rock: Node) -> bool:
	return rock != null and bool(rock.get_meta(META, false))


static func mark(rock: Node) -> void:
	if rock != null:
		rock.set_meta(META, true)


## "Water ice asteroid" once scanned (or mined), "Asteroid" before.
static func name_for(rock: Node) -> String:
	if not is_scanned(rock):
		return "Asteroid"
	var ore := str(rock.get("ore_type"))
	if ore.is_empty() or ore == "<null>":
		ore = "silicate"
	return "%s asteroid" % OreTypes.display(ore)


## Scans every rock within RANGE of `from`. Returns {"radius": the bubble's
## reach, "touched": the rocks it covers, "ores": {ore: count},
## "rocks": n read, "seams": n red rocks it couldn't read, "new": n not known
## before}.
static func scan(from: Vector3, rocks: Array) -> Dictionary:
	var ores := {}
	var read := 0
	var seams := 0
	var fresh := 0
	var touched: Array = []
	for rock in rocks:
		if rock == null or not is_instance_valid(rock) or not (rock is Node3D):
			continue
		if (rock as Node3D).global_position.distance_to(from) > RANGE:
			continue
		touched.append(rock)
		if rock.is_in_group("tech_seam_asteroid") or bool(rock.get("tech_seam")):
			seams += 1
			continue
		if not is_scanned(rock):
			fresh += 1
		mark(rock)
		read += 1
		var ore := str(rock.get("ore_type"))
		if ore.is_empty() or ore == "<null>":
			ore = "silicate"
		ores[ore] = int(ores.get(ore, 0)) + 1
	return {"ores": ores, "rocks": read, "seams": seams, "new": fresh, "radius": RANGE, "touched": touched}


## The feed line for a scan: "Scan: 14 rocks · 2 water ice, 5 ferrite,
## 7 silicate". Rarer ores first (OreTypes.ICON_ORDER is cheap to dear, so
## it's walked backwards); silicate always last.
static func summary(result: Dictionary) -> String:
	var rocks := int(result.get("rocks", 0))
	var seams := int(result.get("seams", 0))
	if rocks == 0 and seams == 0:
		return "Scan: no rocks within %s." % WorldScale.label(RANGE)
	var parts: Array[String] = []
	var ores: Dictionary = result.get("ores", {})
	var order: Array = OreTypes.ICON_ORDER.duplicate()
	order.reverse()
	order.erase("silicate")
	order.append("silicate")
	for ore in ores.keys():
		if not order.has(ore):
			order.push_front(ore)
	for ore in order:
		if ores.has(ore):
			parts.append("%d %s" % [int(ores[ore]), OreTypes.display(ore).to_lower()])
	var text := "Scan: %d rock%s" % [rocks, "" if rocks == 1 else "s"]
	if not parts.is_empty():
		text += " · " + ", ".join(parts)
	if seams > 0:
		text += " · %d tech-grade seam%s unreadable (send a survey drone, G)" % [seams, "" if seams == 1 else "s"]
	return text + "."
