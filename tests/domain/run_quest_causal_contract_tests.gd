extends SceneTree

const ContractType := preload("res://scripts/domain/QuestCausalContract.gd")
const ValidatorType := preload("res://scripts/domain/QuestPlausibilityValidator.gd")
const NarrativeMetadataType := preload("res://scripts/domain/NarrativeMetadata.gd")
const Fixtures := preload("res://tests/fixtures/QuestContractFixtures.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_one_path_courier_is_valid()
	_test_justified_investigation_is_valid()
	_test_unsupported_objective_and_effects_reject()
	_test_impossible_delivery_rejects()
	_test_protected_recipient_rejects()
	_test_private_fact_leak_rejects()
	_test_dangling_fact_reference_rejects()
	_test_unexplained_deadline_rejects()
	_test_recipient_presence_only_checked_when_docking()
	_test_normalize_is_legacy_safe()
	_test_narrative_metadata_roundtrip()
	_test_semantic_signature_ignores_names_but_not_shape()

	if _failures.is_empty():
		print("[PASS] Quest causal contract tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_one_path_courier_is_valid() -> void:
	var report := ValidatorType.check(Fixtures.courier_one_path(), Fixtures.world())
	_expect(
		bool(report["ok"]),
		"A straightforward one-path courier job was rejected: %s" % str(report["issue_codes"])
	)
	# The whole point of fixture 1: having no branches is not a defect.
	var contract := ContractType.normalize(Fixtures.courier_one_path())
	_expect(
		(contract["branch_contracts"] as Array).is_empty(),
		"Courier fixture unexpectedly carries branches."
	)
	_expect(
		(contract["urgency_fact_ids"] as Array).is_empty(),
		"Courier fixture unexpectedly invented urgency."
	)


func _test_justified_investigation_is_valid() -> void:
	var report := ValidatorType.check(Fixtures.investigation_one_choice(), Fixtures.world())
	_expect(
		bool(report["ok"]),
		"Justified investigation was rejected: %s" % str(report["issue_codes"])
	)


func _test_unsupported_objective_and_effects_reject() -> void:
	var report := ValidatorType.check(Fixtures.unsupported_contract(), Fixtures.world())
	_expect(not bool(report["ok"]), "Unsupported objective type was accepted.")
	_expect(
		"unsupported_objective_type" in report["issue_codes"],
		"Unsupported objective type was not reported."
	)
	_expect(
		"unsupported_effect" in report["issue_codes"],
		"Unsupported completion effect was not reported."
	)
	_expect(
		"unexplained_deadline" in report["issue_codes"],
		"Deadline with no recorded reason was not reported."
	)


func _test_impossible_delivery_rejects() -> void:
	var report := ValidatorType.check(Fixtures.impossible_delivery_contract(), Fixtures.world())
	_expect(not bool(report["ok"]), "Impossible delivery was accepted.")
	for code in ["unreachable_location", "implausible_recipient_role", "unknown_recipient_station", "unfunded_reward"]:
		_expect(code in report["issue_codes"], "Impossible delivery did not report '%s'." % code)


func _test_protected_recipient_rejects() -> void:
	var report := ValidatorType.check(Fixtures.protected_recipient_contract(), Fixtures.world())
	_expect(
		"protected_character_recipient" in report["issue_codes"],
		"A protected fixed-cast character was accepted as a delivery recipient."
	)


func _test_private_fact_leak_rejects() -> void:
	var report := ValidatorType.check(Fixtures.leaking_contract(), Fixtures.world())
	_expect(
		"private_fact_marked_public" in report["issue_codes"],
		"A private motive listed as public disclosure was accepted."
	)


func _test_dangling_fact_reference_rejects() -> void:
	var contract := Fixtures.courier_one_path()
	contract["why_player_fact_ids"] = ["fact.does_not_exist"]
	var report := ValidatorType.check(contract, Fixtures.world())
	_expect(
		"unsupported_fact_reference" in report["issue_codes"],
		"A reference to a fact the contract never records was accepted."
	)


func _test_unexplained_deadline_rejects() -> void:
	var contract := Fixtures.courier_one_path()
	contract["objective_binding"]["deadline_minutes"] = 45
	var report := ValidatorType.check(contract, Fixtures.world())
	_expect(
		"unexplained_deadline" in report["issue_codes"],
		"An unexplained deadline was accepted."
	)
	# ...and giving it a reason makes it legitimate again.
	contract["facts"]["fact.tide_window"] = {
		"text": "The yard loses its berth slot at the end of the shift.",
		"visibility": "public",
		"kind": "urgency",
	}
	contract["urgency_fact_ids"] = ["fact.tide_window"]
	var explained := ValidatorType.check(contract, Fixtures.world())
	_expect(
		bool(explained["ok"]),
		"A deadline with a recorded reason was still rejected: %s" % str(explained["issue_codes"])
	)


## A recipient who has wandered off is not a publication failure -- the job was
## honest when it was posted. It becomes a failure at the dock.
func _test_recipient_presence_only_checked_when_docking() -> void:
	var world: Dictionary = Fixtures.world()
	world["residents"] = [
		{
			"id": "npc.marn_dable",
			"name": "Marn Dable",
			"role": "quartermaster",
			"station_id": "station.tallow_primary",
		},
	]
	var contract := Fixtures.courier_one_path()
	var at_publication := ValidatorType.check(
		contract, world, ValidatorType.STAGE_PUBLICATION
	)
	_expect(
		bool(at_publication["ok"]),
		"A moved recipient wrongly failed at publication: %s" % str(at_publication["issue_codes"])
	)
	var at_dock := ValidatorType.check(contract, world, ValidatorType.STAGE_DOCKING)
	_expect(
		"recipient_not_present" in at_dock["issue_codes"],
		"A recipient who is not at the destination passed the docking check."
	)
	# An EXPLICITLY empty roster is not the same as an unsupplied one. Nobody
	# being there must fail a delivery; not knowing who is there must not.
	var deserted: Dictionary = Fixtures.world()
	deserted["residents"] = []
	_expect(
		"recipient_not_present" in ValidatorType.check(
			contract, deserted, ValidatorType.STAGE_DOCKING
		)["issue_codes"],
		"An empty resident roster passed the docking presence check."
	)
	var unknown_roster: Dictionary = Fixtures.world()
	unknown_roster.erase("residents")
	_expect(
		bool(ValidatorType.check(
			contract, unknown_roster, ValidatorType.STAGE_DOCKING
		)["ok"]),
		"An unsupplied resident roster was treated as proof nobody is there."
	)

	var missing_world: Dictionary = Fixtures.world()
	missing_world["residents"] = [
		{"id": "npc.someone_else", "role": "clerk", "station_id": "outpost.blacklist_yard"},
	]
	var missing := ValidatorType.check(
		contract, missing_world, ValidatorType.STAGE_TURN_IN
	)
	_expect(
		"recipient_not_present" in missing["issue_codes"],
		"A missing recipient passed the turn-in check."
	)


## Old saves predate every one of these fields. Loading one must produce an
## empty contract, not an error and not a half-populated one.
func _test_normalize_is_legacy_safe() -> void:
	for legacy in [{}, null, [], {"cause_id": "cause.legacy"}]:
		var contract := ContractType.normalize(legacy)
		_expect(
			contract.has("objective_binding") and contract.has("facts"),
			"Legacy contract normalization dropped required keys."
		)
		_expect(
			not ContractType.is_present(contract),
			"Legacy input wrongly produced a present contract."
		)
	# A partial contract keeps what it had and defaults the rest.
	var partial := ContractType.normalize({"id": "quest.partial", "requester_id": "faction.x"})
	_expect(ContractType.is_present(partial), "A partial contract was not treated as present.")
	_expect(
		(partial["branch_contracts"] as Array).is_empty()
			and (partial["facts"] as Dictionary).is_empty(),
		"A partial contract did not default its collections."
	)
	_expect(
		int(partial["contract_version"]) == ContractType.CONTRACT_VERSION,
		"Normalization did not stamp the current contract version."
	)


## The contract rides inside narrative metadata, so it travels through every
## existing save path without a second persistence system.
func _test_narrative_metadata_roundtrip() -> void:
	var contract := ContractType.normalize(Fixtures.courier_one_path())
	var metadata := NarrativeMetadataType.from_source({
		"narrative_metadata": {
			"cause_id": "cause.public_board.courier",
			"causal_contract": contract,
		},
	})
	_expect(
		ContractType.is_present(metadata.get("causal_contract", {})),
		"Narrative metadata dropped the causal contract."
	)
	var state := NarrativeMetadataType.apply_to_state({}, metadata)
	var json_text := JSON.stringify(state)
	var reloaded: Variant = JSON.parse_string(json_text)
	_expect(reloaded is Dictionary, "Causal contract state did not survive JSON.")
	var restored := NarrativeMetadataType.from_source(reloaded as Dictionary)
	var restored_contract := ContractType.normalize(restored.get("causal_contract", {}))
	_expect(
		str(restored_contract.get("id", "")) == str(contract.get("id", "")),
		"Causal contract identity did not survive a save/load roundtrip."
	)
	_expect(
		(restored_contract["facts"] as Dictionary).size() == (contract["facts"] as Dictionary).size(),
		"Causal contract facts did not survive a save/load roundtrip."
	)
	_expect(
		NarrativeMetadataType.validate_source(reloaded as Dictionary).is_valid(),
		"A roundtripped causal contract failed narrative metadata validation."
	)
	# Existing metadata with no contract at all still validates.
	_expect(
		NarrativeMetadataType.validate_source({
			"narrative_metadata": {"cause_id": "cause.legacy"},
		}).is_valid(),
		"Legacy metadata without a contract stopped validating."
	)
	# A malformed contract is caught, not silently persisted.
	_expect(
		not NarrativeMetadataType.validate_source({
			"narrative_metadata": {
				"causal_contract": {"id": "quest.bad", "problem_fact_ids": "not an array"},
			},
		}).is_valid(),
		"A malformed causal contract passed narrative metadata validation."
	)


## Renaming everything must NOT produce a new signature; changing what actually
## happens must.
func _test_semantic_signature_ignores_names_but_not_shape() -> void:
	var original := ContractType.normalize(Fixtures.courier_one_path())
	var renamed := Fixtures.courier_one_path()
	renamed["id"] = "quest.fixture.courier_renamed"
	renamed["objective_binding"]["item_name"] = "Pressure Sleeve"
	renamed["objective_binding"]["quantity"] = 6
	renamed["objective_binding"]["reward_credits"] = 910
	renamed["recipient_binding"]["name"] = "Otto Vell"
	for fact_id in (renamed["facts"] as Dictionary).keys():
		renamed["facts"][fact_id]["text"] = "Completely different wording for %s." % fact_id
	var renamed_signature := ContractType.semantic_signature(ContractType.normalize(renamed))
	_expect(
		renamed_signature == str(original["semantic_signature"]),
		"A renamed courier chain produced a different signature and would escape duplicate detection."
	)
	var different := Fixtures.investigation_one_choice()
	_expect(
		ContractType.semantic_signature(ContractType.normalize(different))
			!= str(original["semantic_signature"]),
		"A genuinely different causal shape produced the same signature."
	)
	# Working for someone else is a different story from working for yourself.
	var third_party := Fixtures.courier_one_path()
	third_party["beneficiary_id"] = "faction.generated.a1.f2"
	_expect(
		ContractType.semantic_signature(ContractType.normalize(third_party))
			!= str(original["semantic_signature"]),
		"Acting for a third party did not change the causal signature."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
