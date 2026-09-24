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


static func generate(system_id: String, seed_value: int, star_type: String, is_first_system: bool = false) -> Dictionary:
	var profile := {"system_id": system_id, "quirks": [], "states": []}
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
	return profile


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
