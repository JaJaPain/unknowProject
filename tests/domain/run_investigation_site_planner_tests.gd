extends SceneTree

# Placement must never wedge a mission site somewhere the autopilot refuses to
# fly. It shares TangentNavigator's keep-out records rather than re-deriving
# radii, and reports failure instead of shrinking its own margins.

const PlannerType := preload("res://scripts/domain/InvestigationSitePlanner.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_places_within_bounds_and_clear_of_hazards()
	_test_same_seed_reproduces_placement()
	_test_reports_failure_rather_than_shrinking_margins()
	_test_uses_the_navigator_radius_not_a_second_formula()
	if _failures.is_empty():
		print("[PASS] Investigation site planner tests")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _station(id: String, at: Vector3) -> Dictionary:
	return {"id": id, "position": at}


func _hazard(at: Vector3, radius: float) -> Dictionary:
	return {"center": at, "radius": radius, "physical": radius * 0.5}


func _pos(site: Dictionary) -> Vector3:
	var p: Array = site["position"]
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _test_places_within_bounds_and_clear_of_hazards() -> void:
	var stations := [_station("station.a", Vector3.ZERO)]
	var hazards := [_hazard(Vector3(3000, 0, 0), 500.0)]
	var plan: Dictionary = PlannerType.plan_sites(12345, stations, hazards)
	_expect(bool(plan.get("ok", false)), "Placement should succeed with room available.")
	if not bool(plan.get("ok", false)):
		return
	var sites: Array = plan["sites"]
	_expect(sites.size() == 2, "Exactly two sites, got %d." % sites.size())
	var primary := _pos(sites[0])
	var verification := _pos(sites[1])
	var from_station := primary.distance_to(Vector3.ZERO)
	_expect(
		from_station >= PlannerType.PRIMARY_MIN - 1.0 \
			and from_station <= PlannerType.PRIMARY_MAX + 1.0,
		"Primary must sit 2000-4000 from the station, got %.0f" % from_station
	)
	var between := primary.distance_to(verification)
	_expect(
		between >= PlannerType.VERIFICATION_MIN - 1.0 \
			and between <= PlannerType.VERIFICATION_MAX + 1.0,
		"Verification must sit 1000-2000 from the primary, got %.0f" % between
	)
	for site in sites:
		_expect(
			PlannerType.is_position_safe(_pos(site), hazards, stations),
			"Every placed site must be safe: %s" % str(_pos(site))
		)
	_expect(
		float(plan.get("search_radius", 0.0)) == PlannerType.SEARCH_RADIUS,
		"Search radius should be the documented 1500."
	)
	var centre_raw: Array = plan["search_center"]
	var centre := Vector3(float(centre_raw[0]), float(centre_raw[1]), float(centre_raw[2]))
	_expect(
		centre.distance_to(primary) <= PlannerType.SEARCH_CENTER_OFFSET_MAX + 1.0,
		"The search centre is offset from the primary, not placed on it."
	)


# A mission may be re-placed at acceptance and must reproduce its own layout
# rather than reroll into a different one.
func _test_same_seed_reproduces_placement() -> void:
	var stations := [_station("station.a", Vector3.ZERO)]
	var hazards := [_hazard(Vector3(3000, 0, 0), 500.0)]
	var first: Dictionary = PlannerType.plan_sites(777, stations, hazards)
	var again: Dictionary = PlannerType.plan_sites(777, stations, hazards)
	_expect(
		str(first) == str(again),
		"The same seed must reproduce the same placement exactly."
	)
	var different: Dictionary = PlannerType.plan_sites(778, stations, hazards)
	_expect(
		str(different) != str(first),
		"A different seed should place differently."
	)


# The plan's flagged assumption: not every system may have room. When it does
# not, the shape must go unused and say so -- never quietly squeeze past a body.
func _test_reports_failure_rather_than_shrinking_margins() -> void:
	var stations := [_station("station.a", Vector3.ZERO)]
	# A hazard so large it swallows the entire placement annulus.
	var smothered := [_hazard(Vector3.ZERO, 6000.0)]
	var plan: Dictionary = PlannerType.plan_sites(4242, stations, smothered)
	_expect(
		not bool(plan.get("ok", true)),
		"With no safe space the planner must fail, not place anyway."
	)
	_expect(
		str(plan.get("reason", "")) == "no_safe_sites",
		"Failure must be reported as no_safe_sites, got '%s'." % str(plan.get("reason", ""))
	)
	_expect(
		not plan.has("sites"),
		"A failed plan must not hand back sites."
	)
	# No stations at all is a distinct, nameable failure.
	_expect(
		str(PlannerType.plan_sites(1, [], []).get("reason", "")) == "no_stations",
		"An empty station list should say so rather than report no_safe_sites."
	)
	# A second station is tried when the first is unusable.
	var two := [_station("station.a", Vector3.ZERO), _station("station.b", Vector3(40000, 0, 0))]
	var blocked_first := [_hazard(Vector3.ZERO, 6000.0)]
	var fallback: Dictionary = PlannerType.plan_sites(99, two, blocked_first)
	_expect(
		bool(fallback.get("ok", false)) \
			and str(fallback.get("anchor_station_id", "")) == "station.b",
		"An unusable first station must fall through to the next one."
	)


# The radius comes from the hazard RECORD. If placement re-derived it, a site
# could sit inside a body the autopilot correctly refuses to cross.
func _test_uses_the_navigator_radius_not_a_second_formula() -> void:
	var hazards := [_hazard(Vector3(1000, 0, 0), 900.0)]
	var stations := [_station("station.a", Vector3.ZERO)]
	# Just inside radius + margin must be rejected...
	# Stations omitted deliberately, as below: with one at the origin this probe
	# was 195 units from it and rejected by STRUCTURE_CLEARANCE, so the assertion
	# passed without ever exercising the hazard margin. A mutation removing the
	# margin entirely still passed until this was fixed.
	var just_inside := Vector3(1000.0 - (900.0 + PlannerType.HAZARD_MARGIN - 5.0), 0, 0)
	_expect(
		not PlannerType.is_position_safe(just_inside, hazards, []),
		"A point inside radius + margin must be unsafe."
	)
	# ...and just outside accepted, proving the margin is applied to the record's
	# own radius rather than to some recomputed body size.
	# No stations passed here on purpose: this assertion is about the hazard
	# radius alone, and the earlier fixture put the probe point 250 units from
	# the station, so STRUCTURE_CLEARANCE was (correctly) rejecting it and
	# masking what was being tested.
	var just_outside := Vector3(1000.0 - (900.0 + PlannerType.HAZARD_MARGIN + 50.0), 0, 0)
	_expect(
		PlannerType.is_position_safe(just_outside, hazards, []),
		"A point beyond radius + margin should be safe."
	)
	# Structures are respected too.
	_expect(
		not PlannerType.is_position_safe(
			Vector3(300, 0, 0), [], stations
		),
		"A site must not crowd a station."
	)
	_expect(
		not PlannerType.is_position_safe(
			Vector3(0, 0, 500), [], [], [Vector3(0, 0, 0)]
		),
		"A site must not crowd a gate."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
