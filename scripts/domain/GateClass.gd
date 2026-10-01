extends RefCounted

## Gate classes and the Ship Rating (docs/core_loop_plan_2026_10_01.md,
## Section 2). PURE rules: no scene, no autoloads, so every number is testable.
##
## - A gate's class comes from the depth of the system it leads to.
## - Each class needs a Ship Rating: the sum of the upgradeable systems' tiers,
##   where a system counts for at most two tiers above the weakest one (Abe:
##   one upgrade path alone must never carry the ship forward).
## - Class II also needs Shields Mk II (the tutorial rung).
## - Back is always open; going deeper always checks (Abe).
## - There is no last class: past the table, classes and ratings continue by
##   formula (Abe: never fully upgraded, a never-ending story).

## The systems that count. (Storage, sensors and power have no upgrade tree.)
const RATED_SYSTEMS := ["weapons", "engine", "shields", "mining", "cargo"]
## A system counts for at most this many tiers above the weakest.
const BREADTH_LEAD := 2

## [max depth, class] for the hand-tuned early ladder.
const DEPTH_BANDS := [[2, 1], [4, 2], [6, 3], [9, 4], [12, 5], [15, 6]]
## Rating each class needs (class 1 is a stock ship).
const RATING_BY_CLASS := {1: 5, 2: 6, 3: 8, 4: 11, 5: 15, 6: 20}
## Past the table: each further class is this many systems deeper...
const DEPTH_PER_EXTRA_CLASS := 3
## ...and needs this much more rating.
const RATING_PER_EXTRA_CLASS := 5

const ROMAN := ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]


static func class_for_depth(depth: int) -> int:
	if depth < 0:
		return 1
	for band in DEPTH_BANDS:
		if depth <= int(band[0]):
			return int(band[1])
	var last_depth := int(DEPTH_BANDS[-1][0])
	var last_class := int(DEPTH_BANDS[-1][1])
	return last_class + int(ceil(float(depth - last_depth) / DEPTH_PER_EXTRA_CLASS))


static func rating_for_class(gate_class: int) -> int:
	if RATING_BY_CLASS.has(gate_class):
		return int(RATING_BY_CLASS[gate_class])
	var top := int(RATING_BY_CLASS.keys().max())
	if gate_class < 1:
		return int(RATING_BY_CLASS[1])
	return int(RATING_BY_CLASS[top]) + RATING_PER_EXTRA_CLASS * (gate_class - top)


static func class_name_of(gate_class: int) -> String:
	return ROMAN[gate_class] if gate_class < ROMAN.size() else str(gate_class)


## Tier of each rated system from GlobalState.current_upgrades' shape.
static func tiers_of(upgrades: Dictionary) -> Dictionary:
	var out := {}
	for sys in RATED_SYSTEMS:
		var info = upgrades.get(sys, {})
		out[sys] = maxi(1, int(info.get("tier", 1)) if info is Dictionary else 1)
	return out


static func weakest_tier(tiers: Dictionary) -> int:
	var low := 1 << 30
	for sys in RATED_SYSTEMS:
		low = mini(low, int(tiers.get(sys, 1)))
	return low


## The Ship Rating: each system's tier, capped at weakest + BREADTH_LEAD.
static func ship_rating(tiers: Dictionary) -> int:
	var cap := weakest_tier(tiers) + BREADTH_LEAD
	var total := 0
	for sys in RATED_SYSTEMS:
		total += mini(int(tiers.get(sys, 1)), cap)
	return total


## The weakest system's id when it is what holds the rating back (some other
## system is over the cap), else "".
static func limiting_system(tiers: Dictionary) -> String:
	var low := weakest_tier(tiers)
	var capped := false
	for sys in RATED_SYSTEMS:
		if int(tiers.get(sys, 1)) > low + BREADTH_LEAD:
			capped = true
	if not capped:
		return ""
	for sys in RATED_SYSTEMS:
		if int(tiers.get(sys, 1)) == low:
			return sys
	return ""


## What a gate into a system `dest_depth` deep wants from a ship flying out of
## a system `from_depth` deep. "" when the ship may go.
## Returns {"ok": bool, "class": int, "needs_rating": int, "rating": int,
## "needs_shields_mk2": bool}.
static func check(from_depth: int, dest_depth: int, tiers: Dictionary) -> Dictionary:
	var gate_class := class_for_depth(dest_depth)
	var rating := ship_rating(tiers)
	var needs := rating_for_class(gate_class)
	var result := {"ok": true, "class": gate_class, "needs_rating": needs, "rating": rating, "needs_shields_mk2": false}
	# Back (or sideways) is always open.
	if dest_depth >= 0 and from_depth >= 0 and dest_depth <= from_depth:
		return result
	if gate_class >= 2 and int(tiers.get("shields", 1)) < 2:
		result["ok"] = false
		result["needs_shields_mk2"] = true
	if rating < needs:
		result["ok"] = false
	return result
