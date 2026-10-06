class_name SystemProfile
extends RefCounted

## What a star system is like, as data the story systems can read (plan
## Section 3.5): its quirks (hazards that change how it plays) and its states
## (the situation there right now).
##
## Derived deterministically from values every generated system already has
## (system id, seed, star type), so no save data is needed for the base
## profile. States then change as arcs resolve; `apply_changes` returns the
## updated profile, and the arc state keeps those changes in the campaign save.
##
## The first system of a campaign (the tutorial) never gets quirks or states.
## Visual and gameplay effects for quirks come later; the vocabulary matches
## the premise-card brief so cards that require a quirk can already be drawn.

const QUIRKS: Array[String] = [
	"pulsar", "nebula", "ion_storm", "dense_debris", "dying_star",
	"black_hole_proximity", "dead_system", "gravity_tides", "relay_dark_zone",
]
const STATES: Array[String] = [
	"blockade", "quarantine", "shortage", "boom", "evacuation", "curfew", "martial_law",
	"price_spike", "price_crash", "refugee_influx", "lane_closed", "lane_opened",
	"power_vacuum", "festival", "strike", "crackdown", "election", "mourning",
]

# Base weight for every quirk, then per-star adjustments (added).
const BASE_QUIRK_WEIGHT := 2
const STAR_QUIRK_BONUS := {
	"red": {"dying_star": 5, "gravity_tides": 2, "dead_system": 2},
	"white": {"pulsar": 5, "black_hole_proximity": 2, "relay_dark_zone": 1},
	"blue": {"ion_storm": 4, "nebula": 3, "dense_debris": 1},
	"orange": {"dense_debris": 3, "gravity_tides": 2, "relay_dark_zone": 1},
	"yellow": {"nebula": 1, "dense_debris": 1},
}
# Chance (out of 100) of having 0, 1 or 2 quirks.
const QUIRK_COUNT_ODDS := [40, 45, 15]
# Starting states: quirks make some states likely; otherwise a light random draw.
const QUIRK_STATES := {
	"dying_star": ["evacuation", "price_spike"],
	"dead_system": ["shortage"],
	"relay_dark_zone": ["lane_closed"],
	"ion_storm": ["price_spike"],
}
const RANDOM_STATE_POOL: Array[String] = [
	"boom", "festival", "election", "shortage", "strike", "curfew", "mourning",
	"price_crash", "refugee_influx", "crackdown", "quarantine",
]
const RANDOM_STATE_CHANCE := 45   # percent chance of one random starting state

# Ores the belts carry (OreTypes): silicate everywhere, plus two others drawn
# by weight; star colour and quirks tilt the draw. Shares of the belt.
const ORE_BASE_WEIGHT := {"water_ice": 4, "ferrite": 5, "cuprite": 3, "thorium": 1}
const STAR_ORE_BONUS := {
	"red": {"water_ice": 3, "ferrite": 1},
	"white": {"thorium": 2, "cuprite": 1},
	"blue": {"cuprite": 2, "thorium": 1},
	"orange": {"ferrite": 3},
	"yellow": {"water_ice": 1, "cuprite": 1},
}
const QUIRK_ORE_BONUS := {
	"pulsar": {"thorium": 3}, "dying_star": {"thorium": 2}, "nebula": {"water_ice": 3},
	"dense_debris": {"ferrite": 3}, "ion_storm": {"cuprite": 2},
}
const ORE_SHARES := [0.28, 0.14]
const THORIUM_MAX_SHARE := 0.08
# Rare ore grows with distance from the start (gate jumps): early belts are
# almost all ordinary rock (Abe). Index = depth; deeper uses the last value.
const RARE_SHARE_BY_DEPTH := [0.0, 0.08, 0.15, 0.22, 0.30, 0.36, 0.42]
const THORIUM_MIN_DEPTH := 3
# Water ice refines into fuel, so every belt past the start carries at least
# this much of it, however early (a utility ore, not a rare one). Raised from
# 6% (playtest 2026-10-06 finding 12); every field also guarantees a couple
# of ice rocks (Asteroid.guaranteed_ores).
const ICE_FLOOR := 0.10
# Some systems are icy: mostly water ice, for their own flavour (Abe,
# 2026-10-06).
const ICY_SYSTEM_CHANCE := 0.15
const ICY_SHARE := 0.45


## `depth`: gate jumps from the start system (-1 = unknown: full rarity).
static func generate(system_id: String, seed_value: int, star_type: String, is_first_system: bool = false, depth: int = -1) -> Dictionary:
	var profile := {"system_id": system_id, "quirks": [], "states": [], "ores": {"silicate": 1.0}}
	if is_first_system:
		return profile
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d|system_profile" % [system_id, seed_value])

	var roll := rng.randi_range(0, 99)
	var count := 0
	var cumulative := 0
	for i in QUIRK_COUNT_ODDS.size():
		cumulative += int(QUIRK_COUNT_ODDS[i])
		if roll < cumulative:
			count = i
			break

	var quirks: Array[String] = []
	var bonus: Dictionary = STAR_QUIRK_BONUS.get(star_type, {})
	for _i in count:
		var pick := _weighted_pick(rng, bonus, quirks)
		if not pick.is_empty():
			quirks.append(pick)

	var states: Array[String] = []
	for q in quirks:
		for s in QUIRK_STATES.get(q, []):
			if rng.randi_range(0, 99) < 60 and not s in states:
				states.append(str(s))
	if rng.randi_range(0, 99) < RANDOM_STATE_CHANCE:
		var s := RANDOM_STATE_POOL[rng.randi_range(0, RANDOM_STATE_POOL.size() - 1)]
		if not s in states:
			states.append(s)
	profile["quirks"] = quirks
	profile["states"] = states
	profile["ores"] = ore_mix(system_id, seed_value, star_type, quirks, depth)
	return profile


## The belt mix: ore type -> share (sums to 1). Its own random stream, so
## adding ores changed no system's quirks or states.
static func ore_mix(system_id: String, seed_value: int, star_type: String, quirks: Array, depth: int = -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d|system_ores" % [system_id, seed_value])
	var weights := ORE_BASE_WEIGHT.duplicate()
	var star_bonus: Dictionary = STAR_ORE_BONUS.get(star_type, {})
	for ore in star_bonus:
		weights[ore] = int(weights.get(ore, 0)) + int(star_bonus[ore])
	for q in quirks:
		var qb: Dictionary = QUIRK_ORE_BONUS.get(str(q), {})
		for ore in qb:
			weights[ore] = int(weights.get(ore, 0)) + int(qb[ore])
	var mix := {"silicate": 1.0}
	for share in ORE_SHARES:
		var total := 0
		for ore in weights:
			total += int(weights[ore])
		if total <= 0:
			break
		var roll := rng.randi_range(0, total - 1)
		var pick := ""
		for ore in ORE_BASE_WEIGHT.keys():
			if not weights.has(ore):
				continue
			roll -= int(weights[ore])
			if roll < 0:
				pick = str(ore)
				break
		if pick.is_empty():
			break
		weights.erase(pick)
		var amount: float = minf(float(share), THORIUM_MAX_SHARE) if pick == "thorium" else float(share)
		mix[pick] = amount
		mix["silicate"] = float(mix["silicate"]) - amount
	var icy := rng.randf() < ICY_SYSTEM_CHANCE
	var ores := _scale_rarity(mix, depth)
	if icy and depth != 0 and float(ores.get("water_ice", 0.0)) < ICY_SHARE:
		ores["silicate"] = float(ores["silicate"]) - (ICY_SHARE - float(ores.get("water_ice", 0.0)))
		ores["water_ice"] = ICY_SHARE
	return ores


## Shrinks the rare ores to what this depth allows (silicate takes the rest);
## thorium only from THORIUM_MIN_DEPTH out.
static func _scale_rarity(mix: Dictionary, depth: int) -> Dictionary:
	# Unknown depth (-1): full rarity, still with ice for fuel.
	var at := depth if depth >= 0 else RARE_SHARE_BY_DEPTH.size() - 1
	var allowed: float = float(RARE_SHARE_BY_DEPTH[mini(at, RARE_SHARE_BY_DEPTH.size() - 1)])
	var full: float = float(RARE_SHARE_BY_DEPTH[RARE_SHARE_BY_DEPTH.size() - 1])
	var scale := allowed / full
	var out := {"silicate": 1.0}
	for ore in mix:
		if ore == "silicate" or (ore == "thorium" and at < THORIUM_MIN_DEPTH):
			continue
		var amount := float(mix[ore]) * scale
		if amount <= 0.0:
			continue
		out[ore] = amount
		out["silicate"] = float(out["silicate"]) - amount
	if at >= 1 and float(out.get("water_ice", 0.0)) < ICE_FLOOR:
		out["silicate"] = float(out["silicate"]) - (ICE_FLOOR - float(out.get("water_ice", 0.0)))
		out["water_ice"] = ICE_FLOOR
	return out


## Gate jumps from `start` to `target` over `links` (system id -> ids it has
## gates to), or -1 if unreachable.
static func gate_depth(links: Dictionary, start: String, target: String) -> int:
	if start == target:
		return 0
	var seen := {start: 0}
	var queue: Array = [start]
	while not queue.is_empty():
		var at: String = queue.pop_front()
		for next in links.get(at, []):
			var id := str(next)
			if seen.has(id):
				continue
			seen[id] = int(seen[at]) + 1
			if id == target:
				return int(seen[id])
			queue.append(id)
	return -1


## Applies a card resolution's `system_state` consequence (add/remove lists).
static func apply_changes(profile: Dictionary, add: Array, remove: Array) -> Dictionary:
	var next := profile.duplicate(true)
	var states: Array = next.get("states", [])
	for s in remove:
		states.erase(str(s))
	for s in add:
		if str(s) in STATES and not str(s) in states:
			states.append(str(s))
	next["states"] = states
	return next


static func _weighted_pick(rng: RandomNumberGenerator, bonus: Dictionary, taken: Array[String]) -> String:
	var total := 0
	for q in QUIRKS:
		if not q in taken:
			total += BASE_QUIRK_WEIGHT + int(bonus.get(q, 0))
	if total <= 0:
		return ""
	var roll := rng.randi_range(0, total - 1)
	for q in QUIRKS:
		if q in taken:
			continue
		roll -= BASE_QUIRK_WEIGHT + int(bonus.get(q, 0))
		if roll < 0:
			return q
	return ""
