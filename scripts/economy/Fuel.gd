extends RefCounted

## Fuel (Abe, 2026-09-26): hydrogen for the gate drive and the boost. Mined
## water ice is refined into it at a station; stations also sell it, at a
## higher price. Flying inside a system is free. An empty tank stops jumps
## only, so the captain can always mine ice, refine it, and leave.
##
## PURE numbers and rules; GlobalState holds the tank.

const TANK_MAX := 100.0
## A jump costs more the further out its destination is (gate depth).
const JUMP_BASE := 8.0
const JUMP_PER_DEPTH := 2.0
const JUMP_MAX := 20.0
const BOOST_COST := 2.0
## One m³ of water ice refines into this much fuel, for this fee per unit.
const FUEL_PER_ICE := 1.0
const REFINE_FEE := 0.5
## Buying fuel outright at a station.
const BUY_PRICE := 3.0


static func jump_cost(destination_depth: int) -> float:
	if destination_depth < 0:
		return JUMP_BASE
	return minf(JUMP_MAX, JUMP_BASE + JUMP_PER_DEPTH * float(destination_depth))


## Fuel from refining `ice` m³ into a tank holding `fuel`: [fuel_gained, ice_used, fee].
static func refine(ice: float, fuel: float) -> Array:
	var room := maxf(0.0, TANK_MAX - fuel)
	var gained := minf(ice * FUEL_PER_ICE, room)
	var used := gained / FUEL_PER_ICE
	return [gained, used, int(ceil(gained * REFINE_FEE))]


## Filling up with bought fuel, limited by credits: [fuel_bought, cost].
static func buy_to_full(fuel: float, credits: int) -> Array:
	var room := maxf(0.0, TANK_MAX - fuel)
	var affordable := floorf(float(credits) / BUY_PRICE)
	var bought := minf(room, affordable)
	return [bought, int(ceil(bought * BUY_PRICE))]
