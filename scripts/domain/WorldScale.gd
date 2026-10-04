extends RefCounted

## How big the world is (Abe, 2026-10-04): systems were cramped for the new
## kilometre-scale main stations, so the distances BETWEEN places stretch by
## one factor, the same in every system. Close-range things keep their real
## size so fights, mining and docking feel exactly as before: combat starts at
## 80, docking at 72, mining reach, weapon range, ships, rocks and stations.
##
## Abe's unit idea: a distance on screen keeps its old number, it just means
## TRAVEL times more space. "The station is 1,244 m away" is still the number
## the player saw before; the world behind it is TRAVEL times bigger. Every
## distance the player reads goes through to_display().
##
## Stretched (multiply by TRAVEL with travel()): system size, planet size and
## spacing, belt placement, station and gate placement, anomaly spots,
## investigation search areas, the Lodestar's place, the ice-free zone around
## stations, safe zones. Not stretched: everything a ship does up close.
##
## Pick the factor by looking (3, 5, 8 ... Abe chooses); travel time is held
## the same by the cruise speed (PlayerShip), which scales with it.

const TRAVEL := 5.0


## A between-places distance written at the old scale, in world units now.
static func travel(old_distance: float) -> float:
	return old_distance * TRAVEL


## A world distance as the number the player reads (Abe's relabelled metre).
static func to_display(world_distance: float) -> float:
	return world_distance / TRAVEL


## "1,014 m" under 10 km, then "12.4 km", in the player's (relabelled) metres.
static func label(world_distance: float) -> String:
	var metres := to_display(world_distance)
	if metres >= 10000.0:
		return "%.1f km" % (metres / 1000.0)
	var whole := int(round(metres))
	var text := str(whole)
	if whole >= 1000:
		text = "%d,%03d" % [whole / 1000, whole % 1000]
	return text + " m"


## A speed (world units per second) as the player reads it.
static func speed_label(world_speed: float) -> String:
	return "%d m/s" % int(round(to_display(world_speed)))
