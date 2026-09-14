class_name QuestPlausibilityValidator
extends RefCounted

## Layer 1 of the causal gate: can the game ACTUALLY do what this contract
## claims? Entity bindings, real quantities, reachable places, appropriate
## recipients, supported effects. No prose judgement happens here -- fluent
## nonsense and clumsy truth are treated identically, which is the point.
##
## Layer 2 (does the action address the problem, would this person really ask)
## lives in the dialogue quality gate, because it needs a model.
##
## Re-run at publication, acceptance, docking and turn-in: the world moves
## between those moments and a binding that was valid at publication can stop
## being valid before the player arrives.

const ContractType := preload("res://scripts/domain/QuestCausalContract.gd")
const ValidationResultType := preload("res://scripts/domain/ValidationResult.gd")
const CapabilityRegistryType := preload(
	"res://scripts/domain/MissionCapabilityRegistry.gd"
)

const STAGE_PUBLICATION := "publication"
const STAGE_ACCEPTANCE := "acceptance"
const STAGE_DOCKING := "docking"
const STAGE_TURN_IN := "turn_in"
const STAGES := [STAGE_PUBLICATION, STAGE_ACCEPTANCE, STAGE_DOCKING, STAGE_TURN_IN]

## DOCUMENTATION ONLY -- the authoritative answer comes from
## MissionCapabilityRegistry, which owns the executable handlers. This list is
## kept so a reader can see the expected set at a glance; it is deliberately not
## consulted, because a second list is a second thing to forget to update.
const SUPPORTED_OBJECTIVE_TYPES_REFERENCE := [
	"DELIVER_ORE",
	"PICKUP_SPECIAL",
	"DELIVERY_COURIER",
	"PURCHASE_DELIVERY",
	"RECOVER_COMBAT_DROP",
	"KILL_SHIPS",
	"TARGET_WITH_COMMS_REVERSAL",
	"INVESTIGATE_SIGNAL",
]

## Objectives that hand a physical object to a named person. These require a
## recipient binding; everything else must NOT carry one.
const DELIVERY_OBJECTIVE_TYPES := [
	"DELIVERY_COURIER",
	"PURCHASE_DELIVERY",
]

## Effect families the reducer can record. "market_collapse" and friends are
## exactly the kind of dramatic promise this list exists to refuse.
const SUPPORTED_EFFECT_PREFIXES := [
	"offer_available",
	"offer_withdrawn",
	"reward",
	"evidence",
	"access",
	"knowledge",
	"desire_progress",
	"desire_setback",
	"relationship",
	"pressure",
	"ending_predicate",
]

## Roles a person can hold that make them a believable recipient for cargo.
## A lounge drinker is a resident; they are not a receiving dock.
const RECIPIENT_ROLES := [
	"quartermaster",
	"dockmaster",
	"broker",
	"mechanic",
	"medic",
	"clerk",
	"foreman",
	"supervisor",
	"buyer",
	"agent",
	"station_contact",
]


## `world` is a plain snapshot supplied by the caller so this stays testable
## without autoloads: {system_id, reachable_system_ids, station_ids,
## residents:[{id,name,role,station_id}], capabilities:[...], player_credits,
## requester_funds, known_fact_ids:[...], current_time_minutes}
static func validate(
	contract_source: Variant,
	world: Dictionary = {},
	stage: String = STAGE_PUBLICATION
) -> ValidationResult:
	var result := ValidationResultType.new()
	var structural := ContractType.validate(contract_source)
	result.merge(structural)
	if not structural.is_valid():
		return result
	var contract: Dictionary = ContractType.normalize(contract_source)
	_check_identity(contract, result)
	_check_fact_references(contract, result)
	_check_objective(contract, world, result)
	_check_recipient(contract, world, stage, result)
	_check_reward(contract, world, result)
	_check_effects(contract, result)
	_check_urgency(contract, result)
	return result


## Convenience for callers that only need a yes/no plus reasons to log.
static func check(
	contract_source: Variant,
	world: Dictionary = {},
	stage: String = STAGE_PUBLICATION
) -> Dictionary:
	var result := validate(contract_source, world, stage)
	var codes: Array[String] = []
	for issue in result.errors:
		var code := str(issue.get("code", ""))
		if code not in codes:
			codes.append(code)
	return {
		"ok": result.is_valid(),
		"stage": stage,
		"issue_codes": codes,
		"errors": result.errors.duplicate(true),
		"warnings": result.warnings.duplicate(true),
	}


static func _check_identity(contract: Dictionary, result: ValidationResult) -> void:
	for field in ["id", "requester_id"]:
		if str(contract.get(field, "")).strip_edges().is_empty():
			result.add_error(
				"missing_causal_contract_identity",
				"Causal contract requires '%s'." % field,
				"causal_contract.%s" % field
			)
	# A quest with no stated problem cannot explain why the action helps.
	if (contract.get("problem_fact_ids", []) as Array).is_empty():
		result.add_error(
			"missing_problem",
			"Causal contract records no problem, so no action can be said to address one.",
			"causal_contract.problem_fact_ids"
		)
	if (contract.get("why_this_action_fact_ids", []) as Array).is_empty():
		result.add_error(
			"missing_action_justification",
			"Causal contract does not explain how the objective addresses the problem.",
			"causal_contract.why_this_action_fact_ids"
		)


static func _check_fact_references(contract: Dictionary, result: ValidationResult) -> void:
	for fact_id in ContractType.missing_fact_ids(contract):
		result.add_error(
			"unsupported_fact_reference",
			"Fact '%s' is referenced but not recorded in the contract." % fact_id,
			"causal_contract.facts"
		)
	# Private facts must never be listed as public disclosure. This is the leak
	# check at its cheapest point -- before any prompt is ever built.
	var private_ids := ContractType.private_facts(contract).keys()
	for fact_id in (contract.get("public_fact_ids", []) as Array):
		if str(fact_id) in private_ids:
			result.add_error(
				"private_fact_marked_public",
				"Fact '%s' is private but listed as publicly disclosable." % str(fact_id),
				"causal_contract.public_fact_ids"
			)


static func _check_objective(
	contract: Dictionary,
	world: Dictionary,
	result: ValidationResult
) -> void:
	var binding: Dictionary = contract.get("objective_binding", {})
	if binding.is_empty():
		result.add_error(
			"missing_objective_binding",
			"Causal contract has no objective binding.",
			"causal_contract.objective_binding"
		)
		return
	var objective_type := str(binding.get("type", "")).strip_edges().to_upper()
	# Ask the REAL capability registry, not a parallel allowlist that can drift
	# from it. A type the registry does not know has no executable handler, so
	# accepting it would publish a job nothing can carry out.
	if not CapabilityRegistryType.has_type(objective_type):
		result.add_error(
			"unsupported_objective_type",
			"Objective type '%s' has no registered capability handler." % objective_type,
			"causal_contract.objective_binding.type"
		)
		return
	var capabilities := _string_array(world.get("capabilities", []))
	var capability_id := str(binding.get("capability_id", "")).strip_edges()
	if not capability_id.is_empty() \
			and not capabilities.is_empty() \
			and capability_id not in capabilities:
		result.add_error(
			"inactive_capability",
			"Objective needs capability '%s', which is not active here." % capability_id,
			"causal_contract.objective_binding.capability_id"
		)
	if binding.has("quantity"):
		var quantity := float(binding.get("quantity", 0.0))
		if quantity <= 0.0:
			result.add_error(
				"invalid_objective_quantity",
				"Objective quantity must be greater than zero.",
				"causal_contract.objective_binding.quantity"
			)
	_check_location(binding, world, result)


static func _check_location(
	binding: Dictionary,
	world: Dictionary,
	result: ValidationResult
) -> void:
	var system_id := str(binding.get("location_system_id", "")).strip_edges()
	if system_id.is_empty():
		return
	var current := str(world.get("system_id", "")).strip_edges()
	var reachable := _string_array(world.get("reachable_system_ids", []))
	# An empty reachability snapshot means the caller did not supply one; do not
	# invent a failure from missing input.
	if reachable.is_empty() and current.is_empty():
		return
	if system_id == current:
		return
	if not reachable.is_empty() and system_id not in reachable:
		result.add_error(
			"unreachable_location",
			"Objective location '%s' is not reachable from here." % system_id,
			"causal_contract.objective_binding.location_system_id"
		)
		return
	if reachable.is_empty():
		result.add_error(
			"unreachable_location",
			"Objective location '%s' is not the current system and no route is known." % system_id,
			"causal_contract.objective_binding.location_system_id"
		)


static func _check_recipient(
	contract: Dictionary,
	world: Dictionary,
	stage: String,
	result: ValidationResult
) -> void:
	var binding: Dictionary = contract.get("objective_binding", {})
	var objective_type := str(binding.get("type", "")).strip_edges().to_upper()
	var recipient: Dictionary = contract.get("recipient_binding", {})
	var needs_recipient := objective_type in DELIVERY_OBJECTIVE_TYPES
	if not needs_recipient:
		if not recipient.is_empty():
			result.add_warning(
				"unexpected_recipient_binding",
				"Objective '%s' does not deliver anything, so its recipient is ignored." % objective_type,
				"causal_contract.recipient_binding"
			)
		return
	if recipient.is_empty():
		result.add_error(
			"missing_recipient_binding",
			"Delivery objective requires a recipient binding.",
			"causal_contract.recipient_binding"
		)
		return
	var recipient_id := str(recipient.get("id", "")).strip_edges()
	if recipient_id.is_empty():
		result.add_error(
			"missing_recipient_binding",
			"Recipient binding requires a stable id.",
			"causal_contract.recipient_binding.id"
		)
	var role := str(recipient.get("role", "")).strip_edges().to_lower()
	if role not in RECIPIENT_ROLES:
		result.add_error(
			"implausible_recipient_role",
			"Role '%s' cannot plausibly accept a delivery." % role,
			"causal_contract.recipient_binding.role"
		)
	if bool(recipient.get("protected", false)):
		result.add_error(
			"protected_character_recipient",
			"A protected fixed-cast character cannot be reassigned as a delivery recipient.",
			"causal_contract.recipient_binding.id"
		)
	_check_recipient_presence(recipient, recipient_id, world, stage, result)


## Residents move. At publication we only require that the station exists; by
## docking and turn-in the named person must actually be there, or the mission
## enters a recoverable state instead of silently eating the cargo.
static func _check_recipient_presence(
	recipient: Dictionary,
	recipient_id: String,
	world: Dictionary,
	stage: String,
	result: ValidationResult
) -> void:
	var station_id := str(recipient.get("station_id", "")).strip_edges()
	var station_ids := _string_array(world.get("station_ids", []))
	if not station_ids.is_empty() and not station_id.is_empty() \
			and station_id not in station_ids:
		result.add_error(
			"unknown_recipient_station",
			"Recipient station '%s' does not exist." % station_id,
			"causal_contract.recipient_binding.station_id"
		)
	if stage not in [STAGE_DOCKING, STAGE_TURN_IN]:
		return
	# A MISSING key means the caller did not supply a roster: unknown, so no
	# finding. An explicitly EMPTY roster means nobody is there, which must fail
	# a delivery rather than passing for the same reason as unknown.
	if not world.has("residents"):
		return
	var residents: Variant = world["residents"]
	if not (residents is Array):
		result.add_error(
			"invalid_resident_snapshot",
			"Resident roster must be a list when supplied.",
			"world.residents"
		)
		return
	if (residents as Array).is_empty():
		result.add_error(
			"recipient_not_present",
			"Recipient '%s' cannot receive delivery: nobody is present at '%s'." % [
				recipient_id, station_id
			],
			"causal_contract.recipient_binding.id"
		)
		return
	for raw_resident in (residents as Array):
		if not (raw_resident is Dictionary):
			continue
		var resident: Dictionary = raw_resident
		if str(resident.get("id", "")).strip_edges() != recipient_id:
			continue
		var resident_station := str(resident.get("station_id", "")).strip_edges()
		if station_id.is_empty() or resident_station.is_empty() \
				or resident_station == station_id:
			return
		result.add_error(
			"recipient_not_present",
			"Recipient '%s' is not at '%s' right now." % [recipient_id, station_id],
			"causal_contract.recipient_binding.station_id"
		)
		return
	result.add_error(
		"recipient_not_present",
		"Recipient '%s' could not be found." % recipient_id,
		"causal_contract.recipient_binding.id"
	)


static func _check_reward(
	contract: Dictionary,
	world: Dictionary,
	result: ValidationResult
) -> void:
	var binding: Dictionary = contract.get("objective_binding", {})
	var reward := int(binding.get("reward_credits", 0))
	if reward < 0:
		result.add_error(
			"invalid_reward",
			"Reward cannot be negative.",
			"causal_contract.objective_binding.reward_credits"
		)
		return
	if reward == 0:
		return
	if (contract.get("reward_source_fact_ids", []) as Array).is_empty():
		result.add_error(
			"unfunded_reward",
			"A paid job must record where the requester's money comes from.",
			"causal_contract.reward_source_fact_ids"
		)
	# Only check affordability when the caller actually knows the funds. A
	# missing key means unknown, not broke.
	if world.has("requester_funds"):
		var funds := int(world.get("requester_funds", 0))
		if reward > funds:
			result.add_error(
				"unaffordable_reward",
				"Requester cannot pay %d credits (has %d)." % [reward, funds],
				"causal_contract.objective_binding.reward_credits"
			)


static func _check_effects(contract: Dictionary, result: ValidationResult) -> void:
	for field in ["completion_effect_ids", "failure_effect_ids"]:
		for raw_effect in (contract.get(field, []) as Array):
			var effect := str(raw_effect).strip_edges().to_lower()
			if effect.is_empty():
				continue
			if not _is_supported_effect(effect):
				result.add_error(
					"unsupported_effect",
					"Effect '%s' is not something the game can record or enact." % effect,
					"causal_contract.%s" % field
				)


static func _is_supported_effect(effect: String) -> bool:
	for prefix in SUPPORTED_EFFECT_PREFIXES:
		if effect == prefix or effect.begins_with("%s." % prefix):
			return true
	return false


## Urgency has to come from somewhere. An empty urgency list is CORRECT for an
## unhurried job -- this only rejects a deadline nobody can explain.
static func _check_urgency(contract: Dictionary, result: ValidationResult) -> void:
	var binding: Dictionary = contract.get("objective_binding", {})
	var deadline := int(binding.get("deadline_minutes", 0))
	if deadline <= 0:
		return
	if (contract.get("urgency_fact_ids", []) as Array).is_empty():
		result.add_error(
			"unexplained_deadline",
			"Objective has a deadline but records no reason for the hurry.",
			"causal_contract.urgency_fact_ids"
		)


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array):
		return result
	for item in (value as Array):
		var text := str(item).strip_edges()
		if not text.is_empty() and text not in result:
			result.append(text)
	return result
