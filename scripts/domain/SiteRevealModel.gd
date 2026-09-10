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
const SIZE_SMALL := "small"   ## Ships, wrecks, containers.
const SIZE_TINY := "tiny"     ## Gates the player has not found yet.

## Groups whose objects are landmarks.
const LARGE_GROUPS := ["station", "celestial"]

## A gate the player KNOWS is a landmark: it is how they leave, and a route that
## vanishes because you drifted away from it is a navigation failure, not an
## atmosphere win. "blocked" and "damaged" count as known -- you still know where
## it is, you just cannot use it.
const KNOWN_GATE_STATES := ["known", "blocked", "damaged"]

## Detection and drop ranges PER OBJECT CLASS, in metres, set by Abe from play on
## 2026-09-10. These replaced a single range with a shared drop multiplier: his
## numbers are not a fixed multiple (asteroids 800->1100 is 1.375x, ships
## 1500->1900 is 1.27x), so the pairs are absolute and independent.
##
## Ships reach further than rocks on purpose. A ship is the thing that can kill
## you, so losing track of one is a different kind of problem from losing a rock.
const CLASS_RANGES := {
	"ship":     {"detect": 1500.0, "drop": 1900.0},
	"asteroid": {"detect":  800.0, "drop": 1100.0},
}
## Anything small without its own entry.
const DEFAULT_CLASS := "ship"

## Wreckage reads off the SHIP ranges and then takes a penalty (Abe, 2026-09-10).
## A wreck is a ship hull, so the ship numbers are the right starting point -- but
## it is cold and inert, so it should not be spotted as far out as a running ship.
##
## ORDER MATTERS and Abe specified it: a MISSION wreck gets the mission bonus
## FIRST, then the wreck penalty comes off that. So a mission wreck is still
## easier to find than an ordinary wreck, but never as easy as a live mission
## ship. Applying the penalty first and the bonus second gives the same product
## here, but would diverge the moment either becomes non-multiplicative -- the
## order is written down so it survives a future change.
const WRECK_RANGE_PENALTY := 0.8
const WRECK_CLASS := "wreckage"

## Tunable at runtime from the dev panel. range_scale multiplies every class at
## once, so the shape Abe tuned is preserved while the whole set moves together.
static var range_scale := 1.0
static var mission_multiplier := 1.5
static var tiny_multiplier := 0.25


## Share of normal sensor range at which an UNRESOLVED anomaly appears. Abe cut
## this by 75% (2026-09-09): an anomaly you can see across the system is a
## waypoint, not a discovery. Applied whether or not sensor reveal is on, because
## the spoiler is in the anomaly being LISTED at all.
static var anomaly_range_share := 0.25


## Detection range for an unresolved anomaly, in metres.
static func anomaly_reveal_range() -> float:
	# Anchored to the ASTEROID range, not the ship range: an anomaly is a small
	# quiet object, and tying it to the longest range in the model would undo the
	# whole point of it being a surprise find.
	return float(CLASS_RANGES["asteroid"]["detect"]) * anomaly_range_share * range_scale


## Named access to the tunables. Godot cannot reach a static var through get()/
## set() on a script class, so live tuning needs explicit accessors.
static func get_tuning(key: String) -> float:
	match key:
		"range_scale": return range_scale
		"mission_multiplier": return mission_multiplier
		"tiny_multiplier": return tiny_multiplier
		"anomaly_range_share": return anomaly_range_share
	return 0.0


static func set_tuning(key: String, value: float) -> void:
	match key:
		"range_scale": range_scale = value
		"mission_multiplier": mission_multiplier = value
		"tiny_multiplier": tiny_multiplier = value
		"anomaly_range_share": anomaly_range_share = value


## Restore every tunable to its shipped default.
static func reset_tuning() -> void:
	range_scale = 1.0
	mission_multiplier = 1.5
	tiny_multiplier = 0.25
	anomaly_range_share = 0.25


const TIER_RANGES := {
	"basic": 600.0,
	"improved": 900.0,
	"advanced": 1200.0,
}
const DEFAULT_TIER := "basic"

## Distance over which a contact fades in, so it resolves out of the noise
## rather than popping into existence.
const FADE_UNITS := 50.0

const STATE_HIDDEN := "hidden"
const STATE_CONTACT := "contact"
const STATE_IDENTIFIED := "identified"

const CONTACT_LABEL := "Signal contact"


## Size class for an entity, from its groups. Takes plain strings rather than a
## Node so the classification is testable without a running scene.
static func size_class_for_groups(groups: Array, gate_state: String = "known") -> String:
	for group in groups:
		if str(group) == "jumpgate":
			# An unfound gate is the one thing hidden harder than ordinary debris.
			return SIZE_LARGE if gate_state in KNOWN_GATE_STATES else SIZE_TINY
		if str(group) in LARGE_GROUPS:
			return SIZE_LARGE
	return SIZE_SMALL


## Sensor tier as a MULTIPLIER on the per-class ranges. Better sensors see
## proportionally further rather than replacing the tuned shape. An unknown tier
## falls back to basic rather than to zero -- a typo in a ship definition should
## weaken sensors, not blind them.
static func _tier_scale(tier: String) -> float:
	var base := float(TIER_RANGES[DEFAULT_TIER])
	if TIER_RANGES.has(tier):
		return float(TIER_RANGES[tier]) / base
	return 1.0


## Kept for callers that want a nominal range for the tier (the anomaly gate).
static func range_for_tier(tier: String) -> float:
	return float(TIER_RANGES[DEFAULT_TIER]) * _tier_scale(tier) * range_scale


## Object class for range purposes: "ship", "asteroid", or a class with no entry
## (which falls back to DEFAULT_CLASS). Separate from SIZE_* -- size decides
## whether a thing can hide at all, class decides how far away it is seen.
static func range_class_for_groups(groups: Array) -> String:
	for group in groups:
		var g := str(group)
		if g == "asteroid":
			return "asteroid"
		if g == "wreckage" or g == "salvager":
			return WRECK_CLASS
		if g == "ship":
			return "ship"
	return DEFAULT_CLASS


## Wreckage borrows the ship pair; its penalty is applied separately so the
## relationship ("a wreck is a dimmer ship") stays visible in the code.
static func _pair_for(range_class: String) -> Dictionary:
	if range_class == WRECK_CLASS:
		return CLASS_RANGES["ship"]
	return CLASS_RANGES.get(range_class, CLASS_RANGES[DEFAULT_CLASS])


## Range at which an object is first detected. Mission ships get a bonus so the
## player is not hunting one hull among identical contacts.
static func detection_range(
	tier: String,
	is_mission_target: bool = false,
	size_class: String = SIZE_SMALL,
	range_class: String = DEFAULT_CLASS
) -> float:
	var base: float = float(_pair_for(range_class)["detect"]) * range_scale * _tier_scale(tier)
	if size_class == SIZE_TINY:
		base *= tiny_multiplier
	# Mission bonus first, wreck penalty second -- Abe's order.
	if is_mission_target:
		base *= mission_multiplier
	if range_class == WRECK_CLASS:
		base *= WRECK_RANGE_PENALTY
	return base


## Range at which an already-known object finally drops off the overview. Absolute
## per class rather than a multiple of detection, because Abe's numbers are not a
## fixed ratio -- the gap is tighter on ships than on rocks.
static func drop_range_for_tier(
	tier: String,
	is_mission_target: bool = false,
	size_class: String = SIZE_SMALL,
	range_class: String = DEFAULT_CLASS
) -> float:
	var base: float = float(_pair_for(range_class)["drop"]) * range_scale * _tier_scale(tier)
	if size_class == SIZE_TINY:
		base *= tiny_multiplier
	# Mission bonus first, wreck penalty second -- Abe's order.
	if is_mission_target:
		base *= mission_multiplier
	if range_class == WRECK_CLASS:
		base *= WRECK_RANGE_PENALTY
	return base


## Display state for one object. Returns {state, label, alpha, targetable}.
static func reveal_for(
	distance: float,
	tier: String,
	is_scanned: bool,
	site_name: String = "",
	size_class: String = SIZE_SMALL,
	is_mission_target: bool = false,
	range_class: String = DEFAULT_CLASS
) -> Dictionary:
	if size_class == SIZE_LARGE:
		# Planets and stations are landmarks. They are how a player orients
		# themselves in a system, so they are never hidden and never fade.
		return _shown(STATE_IDENTIFIED, site_name if not site_name.is_empty() else "Unknown body", 1.0)
	var sensor_range := detection_range(tier, is_mission_target, size_class, range_class)
	if is_scanned:
		# Known small object: keep it out to the drop range, then let it go.
		if distance > drop_range_for_tier(tier, is_mission_target, size_class, range_class):
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
