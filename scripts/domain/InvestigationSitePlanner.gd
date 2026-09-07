class_name InvestigationSitePlanner
extends RefCounted

## Places the two sites for an investigation contract (plan P2).
##
## PURE and seeded: the caller supplies stations, gates and the navigation
## keep-out records, and the same seed always yields the same placement. That
## matters because a mission may be re-placed at acceptance and must reproduce
## its own layout rather than reroll into a different one.
##
## Hazards arrive in the SAME shape TangentNavigator consumes --
## {center, radius, physical} -- deliberately. Deriving a second planet-radius
## formula here is how a mission site ends up inside a planet the autopilot
## politely refuses to fly through.
##
## When nothing fits, this reports `no_safe_sites` and the shape goes unused.
## It never shrinks its own margins to force a placement: a site wedged inside a
## hazard is worse than a contract that was never offered.

## Distance band for the primary site from its anchor station.
const PRIMARY_MIN := 2000.0
const PRIMARY_MAX := 4000.0
## Distance band for the verification site from the primary.
const VERIFICATION_MIN := 1000.0
const VERIFICATION_MAX := 2000.0
## Clearance beyond a keep-out sphere before a site is considered safe.
const HAZARD_MARGIN := 300.0
## Sites must not crowd anything the player already navigates to.
const STRUCTURE_CLEARANCE := 800.0
## Candidate attempts per anchor station before moving to the next one.
const MAX_ATTEMPTS := 32
## The search circle the player is given, and how far its centre may be offset
## from the primary so the site is not simply at the middle of the marker.
const SEARCH_RADIUS := 1500.0
const SEARCH_CENTER_OFFSET_MAX := 900.0
## Sites sit roughly in the system plane, with mild vertical spread.
const VERTICAL_SPREAD := 0.18


## Returns {ok:true, sites:[primary, verification], search_center, search_radius,
## anchor_station_id} or {ok:false, reason:"no_safe_sites"}.
static func plan_sites(
	seed_value: int,
	stations: Array,
	hazards: Array,
	gates: Array = []
) -> Dictionary:
	if stations.is_empty():
		return {"ok": false, "reason": "no_stations"}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Each station is tried once, in a stable order, so a failure is reproducible
	# and reportable rather than dependent on iteration luck.
	for station in stations:
		if not station is Dictionary:
			continue
		var anchor: Vector3 = (station as Dictionary).get("position", Vector3.ZERO)
		var placed := _place_for_anchor(rng, anchor, hazards, stations, gates)
		if bool(placed.get("ok", false)):
			placed["anchor_station_id"] = str((station as Dictionary).get("id", ""))
			return placed
	return {"ok": false, "reason": "no_safe_sites"}


static func _place_for_anchor(
	rng: RandomNumberGenerator,
	anchor: Vector3,
	hazards: Array,
	stations: Array,
	gates: Array
) -> Dictionary:
	for _attempt in MAX_ATTEMPTS:
		var primary := anchor + _offset(rng, PRIMARY_MIN, PRIMARY_MAX)
		if not is_position_safe(primary, hazards, stations, gates):
			continue
		for _second in MAX_ATTEMPTS:
			var verification := primary + _offset(rng, VERIFICATION_MIN, VERIFICATION_MAX)
			if not is_position_safe(verification, hazards, stations, gates):
				continue
			# The search circle is offset from the primary so the marker does not
			# simply point at the answer.
			var centre := primary + _offset(rng, 0.0, SEARCH_CENTER_OFFSET_MAX)
			return {
				"ok": true,
				"sites": [
					_site("primary", primary),
					_site("verification", verification),
				],
				"search_center": [centre.x, centre.y, centre.z],
				"search_radius": SEARCH_RADIUS,
			}
	return {"ok": false, "reason": "no_safe_sites"}


static func _site(role: String, position: Vector3) -> Dictionary:
	return {
		"role": role,
		"position": [position.x, position.y, position.z],
		# Hidden until sensor range; the primary scan promotes the verification
		# site. Codes and owners are filled in by the offer builder, not here --
		# placement must never touch mission truth.
		"reveal_state": "hidden",
	}


static func _offset(rng: RandomNumberGenerator, min_d: float, max_d: float) -> Vector3:
	var angle := rng.randf_range(0.0, TAU)
	var distance := rng.randf_range(min_d, max_d)
	var vertical := rng.randf_range(-VERTICAL_SPREAD, VERTICAL_SPREAD)
	return Vector3(cos(angle), vertical, sin(angle)).normalized() * distance


## A position is safe when it clears every navigation keep-out sphere by
## HAZARD_MARGIN and is not crowding a station or gate.
##
## Hazard radius is read from the record, never recomputed. The autopilot and
## this planner must agree on where a body ends, or the game will place a site
## somewhere the ship correctly refuses to go.
static func is_position_safe(
	position: Vector3,
	hazards: Array,
	stations: Array,
	gates: Array = []
) -> bool:
	for raw in hazards:
		if not raw is Dictionary:
			continue
		var hazard: Dictionary = raw
		var centre: Vector3 = hazard.get("center", Vector3.ZERO)
		var radius := float(hazard.get("radius", 0.0))
		if position.distance_to(centre) < radius + HAZARD_MARGIN:
			return false
	for group in [stations, gates]:
		for raw in group:
			var point: Vector3 = _point_of(raw)
			if position.distance_to(point) < STRUCTURE_CLEARANCE:
				return false
	return true


static func _point_of(raw: Variant) -> Vector3:
	if raw is Dictionary:
		return (raw as Dictionary).get("position", Vector3.ZERO)
	if raw is Vector3:
		return raw
	return Vector3.ZERO
