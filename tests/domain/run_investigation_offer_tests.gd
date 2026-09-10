extends SceneTree

# Mission TRUTH is generated in code from the seed. If it could drift -- between
# runs, or under a generated label -- the evidence a player gathers would stop
# agreeing with the answer they are graded against.

const BuilderType := preload("res://scripts/domain/InvestigationOfferBuilder.gd")
const PlannerType := preload("res://scripts/domain/InvestigationSitePlanner.gd")
const RegistryType := preload("res://scripts/domain/MissionShapeRegistry.gd")

var _failures: Array[String] = []
var _registry = null


func _initialize() -> void:
	_registry = RegistryType.new()
	var load_result = _registry.load_from_path()
	if not load_result.is_valid():
		push_error("[FAIL] Shape catalog did not load; offer tests cannot run.")
		quit(1)
		return
	_test_truth_is_reproducible_from_seed()
	_test_survey_and_lure_codes()
	_test_claims_owner_only_on_verification()
	_test_archive_has_no_codes_or_owners()
	_test_budget_is_mirrored_not_invented()
	_test_failed_placement_produces_no_offer()
	if _failures.is_empty():
		print("[PASS] Investigation offer builder tests")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _shape(recipe: String) -> Dictionary:
	var definition = _registry.shape_for_recipe(recipe)
	if definition == null:
		return {}
	return {
		"id": str(definition.id),
		"recipe": definition.recipe,
		"branch_ids": definition.branch_ids,
	}


func _placement(seed_value: int = 4242) -> Dictionary:
	return PlannerType.plan_sites(
		seed_value,
		[{"id": "station.a", "position": Vector3.ZERO}],
		[]
	)


func _build(recipe: String, seed_value: int, claimants: Array = []) -> Dictionary:
	return BuilderType.build_objective(
		"m1", _shape(recipe), seed_value, _placement(), 400, "station.a", claimants
	)


func _code(objective: Dictionary, role: String) -> String:
	for site in (objective["investigation"]["sites"] as Array):
		if str(site["role"]) == role:
			return str(site["code"])
	return "<missing>"


func _owner(objective: Dictionary, role: String) -> String:
	for site in (objective["investigation"]["sites"] as Array):
		if str(site["role"]) == role:
			return str(site["owner_faction_id"])
	return "<missing>"


func _test_truth_is_reproducible_from_seed() -> void:
	var first := _build("survey_discrepancy", 9001)
	var again := _build("survey_discrepancy", 9001)
	_expect(bool(first.get("ok", false)), "Offer should build.")
	_expect(
		str(first) == str(again),
		"The same seed must produce identical mission truth."
	)
	# And different seeds must actually differ somewhere across a sample, or the
	# coin flip is not a coin flip.
	var seen: Dictionary = {}
	for s in range(40):
		var built: Dictionary = _build("survey_discrepancy", 5000 + s)
		seen[_code(built["objective"], "verification")] = true
	_expect(
		seen.size() == 2,
		"Across seeds the verification code must take both values, saw %s" % str(seen.keys())
	)


# The primary always reports A; the verification site is the coin flip. What
# equality MEANS differs by recipe, and that mapping must not drift.
func _test_survey_and_lure_codes() -> void:
	for s in range(24):
		var survey: Dictionary = _build("survey_discrepancy", 7000 + s)["objective"]
		_expect(
			_code(survey, "primary") == "A",
			"The primary always reports A, got %s" % _code(survey, "primary")
		)
		_expect(
			_code(survey, "verification") in ["A", "B"],
			"Verification code must be A or B, got %s" % _code(survey, "verification")
		)
		# A survey is never "forged" -- that concept belongs to the lure.
		_expect(
			not bool(survey["investigation"]["forged"]),
			"Only the lure carries a forged flag."
		)

		var lure: Dictionary = _build("transmitter_lure", 7000 + s)["objective"]
		var differs: bool = _code(lure, "primary") != _code(lure, "verification")
		_expect(
			bool(lure["investigation"]["forged"]) == differs,
			"A lure is forged exactly when its codes differ (seed %d)." % (7000 + s)
		)
	# Both forged and genuine lures must occur, or half the decision is dead.
	var forged_seen := {}
	for s in range(40):
		forged_seen[bool(_build("transmitter_lure", 3000 + s)["objective"]["investigation"]["forged"])] = true
	_expect(
		forged_seen.size() == 2,
		"Both forged and genuine lures must be reachable, saw %s" % str(forged_seen.keys())
	)


# The claimant is learned by TRAVELLING, so the primary must not name it.
func _test_claims_owner_only_on_verification() -> void:
	var claimants := ["faction.zenith", "faction.aurelia"]
	var seen: Dictionary = {}
	for s in range(30):
		var claims: Dictionary = _build("competing_claims", 8000 + s, claimants)["objective"]
		_expect(
			_owner(claims, "primary") == "",
			"The primary must not name an owner, got '%s'" % _owner(claims, "primary")
		)
		var owner := _owner(claims, "verification")
		_expect(
			claimants.has(owner),
			"Verification owner must be one of the claimants, got '%s'" % owner
		)
		seen[owner] = true
	_expect(
		seen.size() == 2,
		"Both claimants must be reachable across seeds, saw %s" % str(seen.keys())
	)


func _test_archive_has_no_codes_or_owners() -> void:
	var archive: Dictionary = _build("unstable_archive", 1234)["objective"]
	for role in ["primary", "verification"]:
		_expect(
			_code(archive, role) == "" and _owner(archive, role) == "",
			"The archive uses neither codes nor owners; %s had '%s'/'%s'" % [
				role, _code(archive, role), _owner(archive, role)
			]
		)
	_expect(
		not bool(archive["investigation"]["forged"]),
		"The archive is never forged."
	)


# The reward is the already-approved offer budget, mirrored. Inventing one here
# would let investigation quietly pay differently from every other contract.
func _test_budget_is_mirrored_not_invented() -> void:
	for budget in [150, 400, 1275]:
		var built = BuilderType.build_objective(
			"m1", _shape("survey_discrepancy"), 11, _placement(), budget, "station.a", []
		)
		_expect(
			int(built["objective"]["reward_credits"]) == budget,
			"Reward must mirror the supplied budget %d, got %s" % [
				budget, str(built["objective"]["reward_credits"])
			]
		)
	# A fresh objective starts unresolved, with a whole-budget payout ratio.
	var fresh: Dictionary = _build("survey_discrepancy", 12)["objective"]["investigation"]
	_expect(
		str(fresh["phase"]) == "search" and str(fresh["branch_id"]) == "",
		"A new investigation starts in search with no branch chosen."
	)
	_expect(
		int(fresh["payout_numerator"]) == 1 and int(fresh["payout_denominator"]) == 1,
		"Payout ratio defaults to the whole budget until a branch is taken."
	)


# No safe placement means no offer at all -- never an offer with nowhere to go.
func _test_failed_placement_produces_no_offer() -> void:
	var smothered = PlannerType.plan_sites(
		1, [{"id": "station.a", "position": Vector3.ZERO}],
		[{"center": Vector3.ZERO, "radius": 9000.0, "physical": 4000.0}]
	)
	var built = BuilderType.build_objective(
		"m1", _shape("survey_discrepancy"), 1, smothered, 400, "station.a", []
	)
	_expect(not bool(built.get("ok", true)), "A failed placement must not yield an offer.")
	_expect(
		str(built.get("reason", "")) == "no_safe_sites",
		"The placement failure reason must survive to the caller, got '%s'" % str(built.get("reason", ""))
	)
	_expect(not built.has("objective"), "A failed build must not hand back an objective.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
