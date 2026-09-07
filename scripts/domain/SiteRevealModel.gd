class_name SiteRevealModel
extends RefCounted

## What the overview is allowed to show about a system object (plan P2).
##
## PURE: distance, sensor tier and object size in, display state out.
##
## The point is that small things are FOUND, not listed. A fresh system should
## not hand the player a to-do list of every wreck in it -- that turns
## exploration into errand-running.
##
## But that rule only makes sense for small objects. A planet or a station is
## visible across a system by eye, and pretending sensors are needed to notice a
## planet would be absurd, so LARGE objects are never hidden at all.
##
## Small objects that have been scanned drop off again at a LARGER range than
## they were detected at. The gap is deliberate hysteresis: without it, an object
## sitting exactly at sensor range flickers on and off as the ship drifts.

const SIZE_LARGE := "large"   ## Planets, moons, stations: never hidden.
const SIZE_SMALL := "small"   ## Ships, wrecks, containers, anomalies.

## Groups whose objects are landmarks. Jump gates are included deliberately: a
## gate is how the player LEAVES, and a route that vanishes because you drifted
## away from it is a navigation failure, not an atmosphere win.
const LARGE_GROUPS := ["station", "celestial", "jumpgate"]

const TIER_RANGES := {
	"basic": 600.0,
	"improved": 900.0,
	"advanced": 1200.0,
}
const DEFAULT_TIER := "basic"

## Distance over which a contact fades in, so it resolves out of the noise
## rather than popping into existence.
const FADE_UNITS := 50.0

## A known small object survives out to this multiple of sensor range before it
## drops off. Detect at 600, lose at 1200.
const DROP_RANGE_MULTIPLIER := 2.0

## Mission-relevant ships are detected further out than ordinary traffic. This is
## a playability concession, not a fiction: hunting one specific hull through a
## system full of identical contacts is tedium, not difficulty. A FEEL VALUE --
## expect to tune it in playtest.
const MISSION_RANGE_MULTIPLIER := 1.5

const STATE_HIDDEN := "hidden"
const STATE_CONTACT := "contact"
const STATE_IDENTIFIED := "identified"

const CONTACT_LABEL := "Signal contact"


## Size class for an entity, from its groups. Takes plain strings rather than a
## Node so the classification is testable without a running scene.
static func size_class_for_groups(groups: Array) -> String:
	for group in groups:
		if str(group) in LARGE_GROUPS:
			return SIZE_LARGE
	return SIZE_SMALL


## Sensor range for a tier. An unknown tier falls back to basic rather than to
## zero -- a typo in a ship definition should weaken sensors, not blind them.
static func range_for_tier(tier: String) -> float:
	if TIER_RANGES.has(tier):
		return float(TIER_RANGES[tier])
	return float(TIER_RANGES[DEFAULT_TIER])


## Range at which an object is first detected. Mission ships get a bonus so the
## player is not hunting one hull among identical contacts.
static func detection_range(tier: String, is_mission_target: bool = false) -> float:
	var base := range_for_tier(tier)
	return base * MISSION_RANGE_MULTIPLIER if is_mission_target else base


## Range at which an already-known small object finally drops off the overview.
static func drop_range_for_tier(tier: String, is_mission_target: bool = false) -> float:
	return detection_range(tier, is_mission_target) * DROP_RANGE_MULTIPLIER


## Display state for one object. Returns {state, label, alpha, targetable}.
static func reveal_for(
	distance: float,
	tier: String,
	is_scanned: bool,
	site_name: String = "",
	size_class: String = SIZE_SMALL,
	is_mission_target: bool = false
) -> Dictionary:
	if size_class == SIZE_LARGE:
		# Planets and stations are landmarks. They are how a player orients
		# themselves in a system, so they are never hidden and never fade.
		return _shown(STATE_IDENTIFIED, site_name if not site_name.is_empty() else "Unknown body", 1.0)
	var sensor_range := detection_range(tier, is_mission_target)
	if is_scanned:
		# Known small object: keep it out to the drop range, then let it go.
		if distance > drop_range_for_tier(tier, is_mission_target):
			return _hidden()
		return _shown(STATE_IDENTIFIED, site_name if not site_name.is_empty() else CONTACT_LABEL, 1.0)
	if distance > sensor_range:
		return _hidden()
	# Inside sensor range but not yet scanned: an unidentified contact, fading in
	# over the last stretch of approach.
	var closed := sensor_range - distance
	var alpha := clampf(closed / FADE_UNITS, 0.0, 1.0) if FADE_UNITS > 0.0 else 1.0
	# Targetable as soon as it is detected, so the player can fly at a faint
	# contact -- chasing a smudge is the good part.
	return _shown(STATE_CONTACT, CONTACT_LABEL, alpha)


static func _hidden() -> Dictionary:
	return {"state": STATE_HIDDEN, "label": "", "alpha": 0.0, "targetable": false}


static func _shown(state: String, label: String, alpha: float) -> Dictionary:
	return {"state": state, "label": label, "alpha": alpha, "targetable": true}
