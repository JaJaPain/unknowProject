extends SceneTree

## The lifecycle seam: a contract is revalidated at acceptance, docking and
## turn-in, against a REAL world snapshot. A job posted honestly can become
## impossible before the player gets there.
##
## Missions with no contract are legacy-compatible: they keep their saved terms
## and are governed by the existing delivery guards, never by today's rules.

const SnapshotType := preload("res://scripts/domain/QuestWorldSnapshot.gd")
const ValidatorType := preload("res://scripts/domain/QuestPlausibilityValidator.gd")
const ContractType := preload("res://scripts/domain/QuestCausalContract.gd")
const Fixtures := preload("res://tests/fixtures/QuestContractFixtures.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_legacy_missions_are_not_checked()
	_test_contract_is_found_in_either_location()
	_test_snapshot_omits_what_it_cannot_resolve()
	_test_stage_is_reported_back()

	if _failures.is_empty():
		print("[PASS] Quest lifecycle validation tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


## Every mission accepted before contracts existed. These must pass straight
## through with `checked:false` -- not merely "ok", but explicitly NOT JUDGED, so
## a caller cannot mistake "we did not look" for "we approved".
func _test_legacy_missions_are_not_checked() -> void:
	for legacy in [
		{},
		{"objective_type": "DELIVERY_COURIER", "destination_station_id": "outpost.somewhere"},
		{"narrative_metadata": {"cause_id": "cause.legacy"}},
		{"narrative_metadata": {"causal_contract": {}}},
	]:
		var report := SnapshotType.check_mission(
			legacy, ValidatorType.STAGE_ACCEPTANCE
		)
		_expect(
			bool(report["ok"]) and not bool(report["checked"]),
			"A legacy mission was judged against contract rules it predates."
		)
		_expect(
			(report["issue_codes"] as Array).is_empty(),
			"A legacy mission reported issue codes."
		)


## The contract lives inside narrative_metadata, but older saved shapes put it
## at the top level. Both must be found, or a real mission would silently become
## "legacy" and skip its own checks.
func _test_contract_is_found_in_either_location() -> void:
	var contract := ContractType.normalize(Fixtures.courier_one_path())
	var nested := {
		"objective_type": "DELIVERY_COURIER",
		"narrative_metadata": {"causal_contract": contract},
	}
	var flat := {
		"objective_type": "DELIVERY_COURIER",
		"causal_contract": contract,
	}
	for mission in [nested, flat]:
		var report := SnapshotType.check_mission(
			mission, ValidatorType.STAGE_ACCEPTANCE
		)
		_expect(
			bool(report["checked"]),
			"A mission carrying a real contract was treated as legacy and skipped."
		)


## The snapshot must report only what it can actually resolve. Inventing a
## capability list or a requester balance turns "we do not know" into "we
## checked", which manufactures both false passes and false rejections.
func _test_snapshot_omits_what_it_cannot_resolve() -> void:
	var snapshot := SnapshotType.build("")
	for invented in ["capabilities", "requester_funds", "player_credits"]:
		_expect(
			not snapshot.has(invented),
			"The world snapshot invented '%s' rather than leaving it unknown." % invented
		)
	# With no destination named, residents are UNKNOWN, not empty. An empty list
	# would mean "nobody is there", which is a delivery failure.
	_expect(
		not snapshot.has("residents"),
		"The snapshot claimed to know who was present without being told where."
	)
	# ...and that distinction must actually change the validator's answer.
	var contract := Fixtures.courier_one_path()
	var unknown_roster := ValidatorType.check(contract, {}, ValidatorType.STAGE_TURN_IN)
	_expect(
		bool(unknown_roster.get("ok", false)),
		"An unknown roster produced a finding instead of staying unknown."
	)
	var deserted := ValidatorType.check(
		contract, {"residents": []}, ValidatorType.STAGE_TURN_IN
	)
	_expect(
		"recipient_not_present" in deserted.get("issue_codes", []),
		"An explicitly empty roster did not fail the delivery presence check."
	)


func _test_stage_is_reported_back() -> void:
	var contract := ContractType.normalize(Fixtures.courier_one_path())
	for stage in [
		ValidatorType.STAGE_ACCEPTANCE,
		ValidatorType.STAGE_DOCKING,
		ValidatorType.STAGE_TURN_IN,
	]:
		var report := SnapshotType.check_mission(
			{"narrative_metadata": {"causal_contract": contract}}, stage
		)
		_expect(
			str(report.get("stage", "")) == stage,
			"The lifecycle report did not say which stage it ran at."
		)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
