class_name QuestCausalContract
extends RefCounted

## Versioned, code-owned explanation of WHY a quest exists.
##
## The model may propose draft world details, but a contract only becomes
## authoritative after `QuestPlausibilityValidator` binds its claims to
## mechanics the game can actually enact. Dialogue expresses this record; it
## never creates it. See docs/plan_campaign_uniqueness_and_dialogue_quality.md
## section 4.

const ValidationResultType := preload("res://scripts/domain/ValidationResult.gd")

const CONTRACT_VERSION := 1

const VISIBILITY_PUBLIC := "public"
const VISIBILITY_PRIVATE := "private"
const VISIBILITIES := [VISIBILITY_PUBLIC, VISIBILITY_PRIVATE]

const ID_PATTERN := "^[A-Za-z0-9_.:-]+$"

const STRING_FIELDS := [
	"id",
	"campaign_id",
	"system_id",
	"requester_id",
	"beneficiary_id",
	"desire_id",
	"triggering_event_id",
	"semantic_signature",
]

## Fields whose values must look like stable identifiers.
const ID_FIELDS := [
	"id",
	"campaign_id",
	"system_id",
	"requester_id",
	"beneficiary_id",
	"desire_id",
	"triggering_event_id",
]

const FACT_ID_ARRAY_FIELDS := [
	"problem_fact_ids",
	"public_fact_ids",
	"private_fact_ids",
	"why_this_action_fact_ids",
	"why_player_fact_ids",
	"urgency_fact_ids",
	"reward_source_fact_ids",
]

const EFFECT_ID_ARRAY_FIELDS := [
	"completion_effect_ids",
	"failure_effect_ids",
]

const DICTIONARY_FIELDS := [
	"objective_binding",
	"recipient_binding",
	"facts",
	"semantic_tokens",
]

const ARRAY_OF_DICT_FIELDS := [
	"branch_contracts",
]

static var _id_regex: RegEx


static func empty() -> Dictionary:
	var contract := {"revision": 0, "contract_version": CONTRACT_VERSION}
	for field in STRING_FIELDS:
		contract[field] = ""
	for field in FACT_ID_ARRAY_FIELDS:
		contract[field] = []
	for field in EFFECT_ID_ARRAY_FIELDS:
		contract[field] = []
	for field in DICTIONARY_FIELDS:
		contract[field] = {}
	for field in ARRAY_OF_DICT_FIELDS:
		contract[field] = []
	return contract


static func allowed_fields() -> Array[String]:
	var fields: Array[String] = ["revision", "contract_version"]
	for group in [
		STRING_FIELDS,
		FACT_ID_ARRAY_FIELDS,
		EFFECT_ID_ARRAY_FIELDS,
		DICTIONARY_FIELDS,
		ARRAY_OF_DICT_FIELDS,
	]:
		for field in group:
			fields.append(str(field))
	return fields


static func is_present(source: Variant) -> bool:
	if not (source is Dictionary):
		return false
	var contract: Dictionary = source
	return not str(contract.get("id", "")).strip_edges().is_empty()


## Coerce any saved/legacy shape into the current contract layout. Unknown keys
## are dropped rather than trusted; missing keys take safe empty defaults so an
## older save never fails to load.
static func normalize(source: Variant) -> Dictionary:
	var contract := empty()
	if not (source is Dictionary):
		return contract
	var raw: Dictionary = source
	contract["revision"] = maxi(0, int(raw.get("revision", 0)))
	contract["contract_version"] = CONTRACT_VERSION
	for field in STRING_FIELDS:
		contract[field] = str(raw.get(field, "")).strip_edges()
	for field in FACT_ID_ARRAY_FIELDS + EFFECT_ID_ARRAY_FIELDS:
		contract[field] = _string_array(raw.get(field, []))
	contract["objective_binding"] = _normalize_binding(raw.get("objective_binding", {}))
	contract["recipient_binding"] = _normalize_binding(raw.get("recipient_binding", {}))
	contract["facts"] = _normalize_facts(raw.get("facts", {}))
	contract["semantic_tokens"] = _normalize_tokens(raw.get("semantic_tokens", {}))
	contract["branch_contracts"] = _normalize_branches(raw.get("branch_contracts", []))
	if contract["semantic_signature"].is_empty():
		contract["semantic_signature"] = semantic_signature(contract)
	return contract


## Structural tokens only: plain lowercase string values, no nesting, no prose.
static func _normalize_tokens(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var out: Dictionary = {}
	for key: Variant in (value as Dictionary):
		var token: Variant = (value as Dictionary)[key]
		if token is Dictionary or token is Array:
			continue
		out[str(key)] = str(token).strip_edges().to_lower()
	return out


static func _normalize_binding(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var binding: Dictionary = (value as Dictionary).duplicate(true)
	for key in binding.keys():
		if binding[key] is String:
			binding[key] = str(binding[key]).strip_edges()
	return binding


static func _normalize_facts(value: Variant) -> Dictionary:
	var facts := {}
	if not (value is Dictionary):
		return facts
	for raw_key in (value as Dictionary).keys():
		var fact_id := str(raw_key).strip_edges()
		if fact_id.is_empty():
			continue
		var raw_fact: Variant = (value as Dictionary)[raw_key]
		var text := ""
		var visibility := VISIBILITY_PUBLIC
		var kind := ""
		if raw_fact is Dictionary:
			var fact: Dictionary = raw_fact
			text = str(fact.get("text", "")).strip_edges()
			visibility = str(fact.get("visibility", VISIBILITY_PUBLIC)).strip_edges().to_lower()
			kind = str(fact.get("kind", "")).strip_edges()
		else:
			text = str(raw_fact).strip_edges()
		if visibility not in VISIBILITIES:
			visibility = VISIBILITY_PUBLIC
		facts[fact_id] = {"id": fact_id, "text": text, "visibility": visibility, "kind": kind}
	return facts


static func _normalize_branches(value: Variant) -> Array:
	var branches: Array = []
	if not (value is Array):
		return branches
	for raw_branch in (value as Array):
		if not (raw_branch is Dictionary):
			continue
		var branch: Dictionary = raw_branch
		var branch_id := str(branch.get("id", "")).strip_edges()
		if branch_id.is_empty():
			continue
		branches.append({
			"id": branch_id,
			"action_id": str(branch.get("action_id", "")).strip_edges(),
			"eligibility_predicates": _string_array(branch.get("eligibility_predicates", [])),
			"motivation_fact_ids": _string_array(branch.get("motivation_fact_ids", [])),
			"public_information_fact_ids": _string_array(
				branch.get("public_information_fact_ids", [])
			),
			"costs": (branch.get("costs", {}) as Dictionary).duplicate(true) \
				if branch.get("costs", {}) is Dictionary else {},
			"effect_ids": _string_array(branch.get("effect_ids", [])),
			"outcome_id": str(branch.get("outcome_id", "")).strip_edges(),
			"distinct_from_branch_ids": _string_array(
				branch.get("distinct_from_branch_ids", [])
			),
		})
	return branches


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array):
		return result
	for item in (value as Array):
		var text := str(item).strip_edges()
		if not text.is_empty() and text not in result:
			result.append(text)
	return result


## Structural validation only: shapes, types and ID spelling. Whether the
## contract is PLAUSIBLE -- real cargo, reachable place, supported effect -- is
## QuestPlausibilityValidator's job.
static func validate(source: Variant, path_prefix: String = "causal_contract") -> ValidationResult:
	var result := ValidationResultType.new()
	if not (source is Dictionary):
		result.add_error(
			"invalid_causal_contract",
			"Causal contract must be an object.",
			path_prefix
		)
		return result
	var contract: Dictionary = source
	if int(contract.get("contract_version", CONTRACT_VERSION)) > CONTRACT_VERSION:
		result.add_error(
			"unsupported_causal_contract_version",
			"Causal contract version %d is newer than this build supports." % int(
				contract.get("contract_version", 0)
			),
			"%s.contract_version" % path_prefix
		)
	for field in STRING_FIELDS:
		if not contract.has(field):
			continue
		if not contract[field] is String:
			result.add_error(
				"invalid_causal_contract_type",
				"Causal contract field '%s' must be a string." % field,
				"%s.%s" % [path_prefix, field]
			)
			continue
		if field in ID_FIELDS:
			_validate_id_text(str(contract[field]), "%s.%s" % [path_prefix, field], result)
	for field in FACT_ID_ARRAY_FIELDS + EFFECT_ID_ARRAY_FIELDS:
		_validate_id_array(contract, field, path_prefix, result)
	for field in DICTIONARY_FIELDS:
		if contract.has(field) and not contract[field] is Dictionary:
			result.add_error(
				"invalid_causal_contract_type",
				"Causal contract field '%s' must be an object." % field,
				"%s.%s" % [path_prefix, field]
			)
	_validate_facts(contract, path_prefix, result)
	_validate_branches(contract, path_prefix, result)
	return result


static func _validate_id_array(
	contract: Dictionary,
	field: String,
	path_prefix: String,
	result: ValidationResult
) -> void:
	if not contract.has(field):
		return
	var path := "%s.%s" % [path_prefix, field]
	if not contract[field] is Array:
		result.add_error(
			"invalid_causal_contract_type",
			"Causal contract field '%s' must be an array." % field,
			path
		)
		return
	var values: Array = contract[field]
	for index in range(values.size()):
		if not values[index] is String:
			result.add_error(
				"invalid_causal_contract_type",
				"Causal contract field '%s' may only contain strings." % field,
				"%s.%d" % [path, index]
			)
			continue
		_validate_id_text(str(values[index]), "%s.%d" % [path, index], result)


static func _validate_facts(
	contract: Dictionary,
	path_prefix: String,
	result: ValidationResult
) -> void:
	var raw_facts: Variant = contract.get("facts", {})
	if not (raw_facts is Dictionary):
		return
	for raw_key in (raw_facts as Dictionary).keys():
		var fact_id := str(raw_key)
		var path := "%s.facts.%s" % [path_prefix, fact_id]
		_validate_id_text(fact_id, path, result)
		var fact: Variant = (raw_facts as Dictionary)[raw_key]
		if not (fact is Dictionary):
			result.add_error(
				"invalid_causal_contract_fact",
				"Fact '%s' must be an object." % fact_id,
				path
			)
			continue
		var entry: Dictionary = fact
		if str(entry.get("text", "")).strip_edges().is_empty():
			result.add_error(
				"empty_causal_contract_fact",
				"Fact '%s' has no text." % fact_id,
				"%s.text" % path
			)
		if str(entry.get("visibility", "")) not in VISIBILITIES:
			result.add_error(
				"invalid_causal_contract_fact_visibility",
				"Fact '%s' must be public or private." % fact_id,
				"%s.visibility" % path
			)


static func _validate_branches(
	contract: Dictionary,
	path_prefix: String,
	result: ValidationResult
) -> void:
	var raw_branches: Variant = contract.get("branch_contracts", [])
	if not (raw_branches is Array):
		if contract.has("branch_contracts"):
			result.add_error(
				"invalid_causal_contract_type",
				"Causal contract field 'branch_contracts' must be an array.",
				"%s.branch_contracts" % path_prefix
			)
		return
	var seen_ids: Dictionary = {}
	var branches: Array = raw_branches
	for index in range(branches.size()):
		var path := "%s.branch_contracts.%d" % [path_prefix, index]
		if not branches[index] is Dictionary:
			result.add_error(
				"invalid_causal_contract_branch",
				"Branch contract must be an object.",
				path
			)
			continue
		var branch: Dictionary = branches[index]
		var branch_id := str(branch.get("id", "")).strip_edges()
		if branch_id.is_empty():
			result.add_error(
				"invalid_causal_contract_branch",
				"Branch contract requires an id.",
				"%s.id" % path
			)
			continue
		_validate_id_text(branch_id, "%s.id" % path, result)
		if seen_ids.has(branch_id):
			result.add_error(
				"duplicate_causal_contract_branch",
				"Branch contract id '%s' appears more than once." % branch_id,
				"%s.id" % path
			)
		seen_ids[branch_id] = true
		if str(branch.get("action_id", "")).strip_edges().is_empty():
			result.add_error(
				"unsupported_branch_action",
				"Branch '%s' has no action_id, so nothing would happen if chosen." % branch_id,
				"%s.action_id" % path
			)


static func _validate_id_text(
	value: String,
	path: String,
	result: ValidationResult
) -> void:
	if value.is_empty():
		return
	if value != value.strip_edges():
		result.add_error(
			"invalid_causal_contract_id",
			"Causal contract IDs cannot have leading or trailing whitespace.",
			path
		)
		return
	if _get_id_regex().search(value) == null:
		result.add_error(
			"invalid_causal_contract_id",
			"Causal contract IDs may only use letters, numbers, underscore, dot, colon or dash.",
			path
		)


static func _get_id_regex() -> RegEx:
	if _id_regex == null:
		_id_regex = RegEx.new()
		if _id_regex.compile(ID_PATTERN) != OK:
			push_error("[QuestCausalContract] Failed to compile ID pattern.")
	return _id_regex


## A name-free fingerprint of the causal SHAPE of this quest, so two campaigns
## that renamed the nouns of the same story still collide. Deliberately excludes
## display names, quantities and prose: those are the decoration, not the story.
static func semantic_signature(source: Variant) -> String:
	if not (source is Dictionary):
		return ""
	var contract: Dictionary = source
	var objective: Dictionary = contract.get("objective_binding", {}) \
		if contract.get("objective_binding", {}) is Dictionary else {}
	var recipient: Dictionary = contract.get("recipient_binding", {}) \
		if contract.get("recipient_binding", {}) is Dictionary else {}
	var parts: Array[String] = [
		"motive=%s" % _signature_token(contract.get("desire_id", "")),
		"event=%s" % _signature_token(contract.get("triggering_event_id", "")),
		"verb=%s" % str(objective.get("type", "")).to_lower(),
		"capability=%s" % str(objective.get("capability_id", "")).to_lower(),
		"beneficiary=%s" % _beneficiary_relation(contract),
		"recipient=%s" % str(recipient.get("role", "")).to_lower(),
		"evidence=%d" % (contract.get("problem_fact_ids", []) as Array).size(),
		"consequence=%s" % _signature_effects(contract.get("completion_effect_ids", [])),
	]
	return "|".join(parts).sha256_text().substr(0, 16)


const SIGNATURE_VERSION := 2


## Version 2: normalized semantic tokens from validated structured facts.
##
## Returns "v2:<hash>" so an incomparable v1 signature is never silently treated
## as fresh proven content -- a caller comparing versions must see the mismatch.
## Falls back to the v1 signature (prefixed "v1:") when a contract predates the
## structured tokens.
static func semantic_signature_v2(source: Variant) -> String:
	if not (source is Dictionary):
		return ""
	var contract: Dictionary = source
	var tokens: Variant = contract.get("semantic_tokens", {})
	if not tokens is Dictionary or (tokens as Dictionary).is_empty():
		var legacy := semantic_signature(contract)
		return "" if legacy.is_empty() else "v1:%s" % legacy
	var t: Dictionary = tokens
	var objective: Dictionary = contract.get("objective_binding", {}) 		if contract.get("objective_binding", {}) is Dictionary else {}
	var recipient: Dictionary = contract.get("recipient_binding", {}) 		if contract.get("recipient_binding", {}) is Dictionary else {}
	var parts: Array[String] = [
		"goal=%s" % str(t.get("goal", "none")),
		"need=%s" % str(t.get("need", "none")),
		"obstacle=%s" % str(t.get("obstacle", "none")),
		"event=%s" % str(t.get("event", "none")),
		"verb=%s" % str(t.get("verb", "")),
		"capability=%s" % str(objective.get("capability_id", "")).to_lower(),
		"resolution=%s" % str(t.get("resolution", "none")),
		"evidence=%s" % str(t.get("evidence_pattern", "none")),
		"beneficiary=%s" % _beneficiary_relation(contract),
		"recipient=%s" % str(recipient.get("role", "")).to_lower(),
		"consequence=%s" % _signature_effects(contract.get("completion_effect_ids", [])),
	]
	return "v2:%s" % "|".join(parts).sha256_text().substr(0, 16)


## Two signatures are comparable only when they share a version. Comparing
## across versions proves nothing, so it must not count as proven novelty.
static func signatures_comparable(a: String, b: String) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	return a.split(":", false)[0] == b.split(":", false)[0]


## Requester and beneficiary being the same party is a different story from
## working on someone else's behalf, so the RELATION is signed, not the IDs.
static func _beneficiary_relation(contract: Dictionary) -> String:
	var requester := str(contract.get("requester_id", "")).strip_edges()
	var beneficiary := str(contract.get("beneficiary_id", "")).strip_edges()
	if beneficiary.is_empty() or beneficiary == requester:
		return "self"
	return "third_party"


## Desire and event IDs carry a campaign-specific suffix (a seed hash). Keep the
## kind, drop the instance, or every campaign trivially looks unique.
static func _signature_token(value: Variant) -> String:
	var text := str(value).strip_edges().to_lower()
	if text.is_empty():
		return "none"
	var pieces := text.split(".", false)
	if pieces.size() <= 1:
		return text
	# desire.<scope>.f0 -> desire; cause.<desire>.<intent> -> cause.<intent>
	if pieces.size() >= 3:
		return "%s.%s" % [str(pieces[0]), str(pieces[pieces.size() - 1])]
	return str(pieces[0])


static func _signature_effects(value: Variant) -> String:
	if not (value is Array):
		return "none"
	var kinds: Array[String] = []
	for item in (value as Array):
		var text := str(item).strip_edges().to_lower()
		if text.is_empty():
			continue
		var kind := str(text.split(".", false)[0]) if text.contains(".") else text
		if kind not in kinds:
			kinds.append(kind)
	if kinds.is_empty():
		return "none"
	kinds.sort()
	return ",".join(kinds)


## Facts this speaker may say out loud. Private motive stays out of dialogue
## packets entirely -- withholding it at the prompt is cheaper and safer than
## detecting a leak afterwards.
static func public_facts(source: Variant) -> Dictionary:
	return _facts_with_visibility(source, VISIBILITY_PUBLIC)


static func private_facts(source: Variant) -> Dictionary:
	return _facts_with_visibility(source, VISIBILITY_PRIVATE)


static func _facts_with_visibility(source: Variant, visibility: String) -> Dictionary:
	var selected := {}
	if not (source is Dictionary):
		return selected
	var facts: Variant = (source as Dictionary).get("facts", {})
	if not (facts is Dictionary):
		return selected
	for fact_id in (facts as Dictionary).keys():
		var fact: Variant = (facts as Dictionary)[fact_id]
		if not (fact is Dictionary):
			continue
		if str((fact as Dictionary).get("visibility", VISIBILITY_PUBLIC)) == visibility:
			selected[str(fact_id)] = (fact as Dictionary).duplicate(true)
	return selected


static func fact_text(source: Variant, fact_id: String) -> String:
	if not (source is Dictionary):
		return ""
	var facts: Variant = (source as Dictionary).get("facts", {})
	if not (facts is Dictionary):
		return ""
	var fact: Variant = (facts as Dictionary).get(fact_id, {})
	if not (fact is Dictionary):
		return ""
	return str((fact as Dictionary).get("text", ""))


## Every referenced fact must exist in the contract's own fact table. A dangling
## reference means something claimed support it does not have.
static func missing_fact_ids(source: Variant) -> Array[String]:
	var missing: Array[String] = []
	if not (source is Dictionary):
		return missing
	var contract: Dictionary = source
	var facts: Dictionary = contract.get("facts", {}) \
		if contract.get("facts", {}) is Dictionary else {}
	for field in FACT_ID_ARRAY_FIELDS:
		for fact_id in _string_array(contract.get(field, [])):
			if not facts.has(fact_id) and fact_id not in missing:
				missing.append(fact_id)
	for raw_branch in (contract.get("branch_contracts", []) as Array):
		if not (raw_branch is Dictionary):
			continue
		var branch: Dictionary = raw_branch
		for field in ["motivation_fact_ids", "public_information_fact_ids"]:
			for fact_id in _string_array(branch.get(field, [])):
				if not facts.has(fact_id) and fact_id not in missing:
					missing.append(fact_id)
	return missing
