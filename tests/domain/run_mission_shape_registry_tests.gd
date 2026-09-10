extends SceneTree

# The shape catalog is executable content: a shape that half-loads would hand the
# player a contract with branches that cannot be dispatched. These tests pin that
# a broken catalog is rejected WHOLESALE rather than partially applied.

const RegistryType := preload("res://scripts/domain/MissionShapeRegistry.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_real_catalog_loads()
	_test_broken_shape_rejects_catalog()
	_test_report_branch_is_mandatory()
	_test_eligibility_filters_on_flags()
	if _failures.is_empty():
		print("[PASS] Mission shape registry tests")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _test_real_catalog_loads() -> void:
	var registry = RegistryType.new()
	var result = registry.load_from_path()
	_expect(
		result.is_valid(),
		"The shipped catalog must load: %s" % str(result.errors)
	)
	_expect(registry.loaded, "Registry should report loaded.")
	_expect(
		registry.shapes.size() == 4,
		"Expected 4 shapes, got %d." % registry.shapes.size()
	)
	# The two slice-one shapes must be present and correctly shaped.
	var survey = registry.shape_for_recipe("survey_discrepancy")
	_expect(survey != null, "survey_discrepancy shape is missing.")
	if survey != null:
		_expect(
			survey.branch_ids.has("certify_match") and survey.branch_ids.has("certify_mismatch"),
			"Survey must offer both certification branches, got %s" % str(survey.branch_ids)
		)
		_expect(not survey.can_spawn_hostile, "Survey must not spawn hostiles.")
	var lure = registry.shape_for_recipe("transmitter_lure")
	_expect(
		lure != null and lure.can_spawn_hostile,
		"The lure is the only shape allowed to spawn a hostile."
	)
	for shape in registry.shapes.values():
		if shape.recipe != "transmitter_lure":
			_expect(
				not shape.can_spawn_hostile,
				"%s must not spawn hostiles." % shape.recipe
			)


func _catalog(shape_overrides: Dictionary = {}) -> Dictionary:
	var shape := {
		"id": "mission_shape.survey_discrepancy",
		"schema_version": 1,
		"objective_type": "INVESTIGATE_SIGNAL",
		"recipe": "survey_discrepancy",
		"display_name": "Survey Discrepancy",
		"requires_second_site": true,
		"can_spawn_hostile": false,
		"branch_ids": ["report", "certify_match", "certify_mismatch"],
		"requires_flags": ["post_tutorial_unlocked"],
		"weight": 1,
	}
	for key in shape_overrides.keys():
		shape[key] = shape_overrides[key]
	return {"version": 1, "shapes": [shape]}


# A catalog with one bad shape must load NOTHING. Partially applying it would put
# an undispatchable contract in front of the player.
func _test_broken_shape_rejects_catalog() -> void:
	var registry = RegistryType.new()
	var result = registry.load_from_dict(_catalog({"recipe": "not_a_recipe"}))
	_expect(not result.is_valid(), "An unknown recipe must fail validation.")
	_expect(
		registry.shapes.is_empty() and not registry.loaded,
		"A failed catalog must leave the registry empty, not half-applied."
	)
	# A duplicate recipe makes dispatch ambiguous.
	var dup := _catalog()
	dup["shapes"] = [dup["shapes"][0], dup["shapes"][0].duplicate()]
	var dup_result = RegistryType.new().load_from_dict(dup)
	_expect(not dup_result.is_valid(), "Two shapes claiming one recipe must fail.")
	# An unsupported catalog version must not silently load.
	var versioned := _catalog()
	versioned["version"] = 99
	_expect(
		not RegistryType.new().load_from_dict(versioned).is_valid(),
		"An unsupported catalog version must fail."
	)


# "report" is the escape hatch that stops a missing consumable stranding a
# contract, so its absence is an error rather than a style warning.
func _test_report_branch_is_mandatory() -> void:
	var result = RegistryType.new().load_from_dict(
		_catalog({"branch_ids": ["certify_match", "certify_mismatch"]})
	)
	_expect(not result.is_valid(), "A shape without 'report' must be rejected.")
	var codes: Array[String] = []
	for issue in result.errors:
		codes.append(str(issue.get("code", "")))
	_expect(
		codes.has("missing_report_branch"),
		"Expected missing_report_branch, got %s" % str(codes)
	)


# Eligibility is filtered BEFORE a pool is formed. Skipping ineligible draws
# inside a cycle would silently break the no-repeat guarantee.
func _test_eligibility_filters_on_flags() -> void:
	var registry = RegistryType.new()
	registry.load_from_path()
	_expect(
		(registry.eligible_shapes({}) as Array).is_empty(),
		"No shape is eligible before the tutorial flag is set."
	)
	var unlocked: Array = registry.eligible_shapes({"post_tutorial_unlocked": true})
	_expect(
		unlocked.size() == 4,
		"All four shapes unlock post-tutorial, got %d." % unlocked.size()
	)
	# Stable ordering, so a selection cycle built from this is reproducible.
	var first_pass: Array[String] = []
	for shape in unlocked:
		first_pass.append(str(shape.id))
	var second_pass: Array[String] = []
	for shape in registry.eligible_shapes({"post_tutorial_unlocked": true}):
		second_pass.append(str(shape.id))
	_expect(first_pass == second_pass, "Eligible shape order must be stable.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
