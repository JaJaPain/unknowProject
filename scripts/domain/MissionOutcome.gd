extends RefCounted

## Code-owned terminal record for an accepted mission (plan P3).
##
## Built from the actual accepted mission and its capability state, never from a
## UI-supplied payout, verification flag, consumed-item flag or model sentence.
## A caller passes the credits it actually paid; everything else is read out of
## the mission's own validated state so a panel cannot assert a better outcome
## than the one the player reached.

const Validation := preload("res://scripts/domain/ValidationResult.gd")
const CollectionContractType := preload("res://scripts/domain/CollectionContract.gd")
const TERMINAL_STATES := ["completed", "abandoned", "failed", "expired"]

## Closed set of effect kinds a committed outcome may assert. A kind listed here
## has a typed predicate proving it; prose never mints one.
const EFFECT_VERIFIED_SURVEY := "verified_survey_evidence_submitted"
const EFFECT_RECORDER_PRESERVED := "recorder_preserved_and_delivered"
const EFFECT_MARKED_ORE_DELIVERED := "marked_ore_delivered"
const EFFECT_PRESSURE_RELIEVED := "pressure_relieved"
## Proves ONE thing: the bound item reached the bound recipient at the bound
## station. Not ownership clearance, lease transfer, appeal success, survey
## filing, an assay, a route opening or a faction's capacity to pay.
const EFFECT_ITEM_DELIVERED := "item_delivered"
const SUPPORTED_EFFECTS := [
	EFFECT_VERIFIED_SURVEY,
	EFFECT_RECORDER_PRESERVED,
	EFFECT_MARKED_ORE_DELIVERED,
	EFFECT_PRESSURE_RELIEVED,
	EFFECT_ITEM_DELIVERED,
]


## `credits_paid` is what the caller actually transferred, and `at_minute` the
## committed campaign clock. Both are code-owned inputs, not player-editable.
static func build(quest: Dictionary, terminal_state: String, credits_paid: int, at_minute: int, campaign_id: String = "") -> Dictionary:
	if quest.is_empty() or terminal_state not in TERMINAL_STATES:
		return {"ok": false, "reason": "invalid_terminal_outcome"}
	var mission_id := str(quest.get("runtime_id", ""))
	if mission_id.is_empty():
		return {"ok": false, "reason": "missing_runtime_mission_id"}
	var investigation: Dictionary = quest.get("investigation", {}) if quest.get("investigation", {}) is Dictionary else {}
	var metadata: Dictionary = quest.get("narrative_metadata", {}) if quest.get("narrative_metadata", {}) is Dictionary else {}
	var raw_collection: Variant = quest.get("collection_contract", {})
	var collection: Dictionary = raw_collection if raw_collection is Dictionary else {}
	var completed := terminal_state == "completed"
	var outcome := {
		"id": "%s:%s" % [mission_id, terminal_state],
		"mission_id": mission_id,
		"campaign_id": campaign_id,
		"system_id": str(quest.get("system_id", "")),
		"pressure_id": str(quest.get("pressure_id", "")),
		"pressure_revision": int(quest.get("pressure_revision", 0)),
		"relief": bool(quest.get("pressure_relief", false)),
		"shape_id": str(investigation.get("shape_id", quest.get("shape_id", ""))),
		"objective_type": str(quest.get("objective_type", "")),
		"terminal_state": terminal_state,
		# A branch, tag or consumed item only exists once the player resolved it.
		"branch_id": str(investigation.get("branch_id", "")) if completed else "",
		"outcome_tag": str(investigation.get("outcome_tag", "")) if completed else "",
		"verified": _both_sites_scanned(investigation) if completed else false,
		"forged": bool(investigation.get("forged", false)),
		"credits_paid": maxi(0, credits_paid) if completed else 0,
		"consumable_id": str(investigation.get("consumable_id", "")) if bool(investigation.get("consumable_spent", false)) else "",
		"at_minute": maxi(0, at_minute),
		"faction_id": str(metadata.get("cause_faction_id", "")),
		"desire_id": str(metadata.get("desire_id", "")),
		"cause_id": str(metadata.get("cause_id", "")),
		"tutorial": _is_tutorial_contract(quest),
		# The collection this mission was bound to at publication, frozen. A
		# mission with no contract simply records none.
		"collection": collection.duplicate(true),
		"effects": [],
	}
	outcome["effects"] = _effects_for(outcome)
	var result := validate(outcome)
	if not result.is_valid():
		return {"ok": false, "reason": str(result.errors[0].get("code", "invalid_outcome")), "validation": result}
	return {"ok": true, "outcome": outcome}


## The starter contract is excluded from pressure and desires. It is identified
## by the same fixed shape QuestManager uses, because the accepted mission state
## does not carry the offer's tutorial flag through the adapter — relying on that
## flag alone silently let the tutorial into the pressure ledger.
static func _is_tutorial_contract(quest: Dictionary) -> bool:
	for flag in ["intro_tutorial_contract", "is_intro_tutorial"]:
		if bool(quest.get(flag, false)):
			return true
	return str(quest.get("title", "")) == "Clean and Easy" 		and str(quest.get("objective_type", "")) == "KILL_SHIPS" 		and str(quest.get("target_faction", "")) == "reavers"


## Verification means both sites were actually scanned, independently of which
## branch was chosen: "a verified report" stays distinct from an unverified one.
static func _both_sites_scanned(investigation: Dictionary) -> bool:
	var scanned: Variant = investigation.get("scanned_site_ids", [])
	if scanned is Array:
		return (scanned as Array).size() >= 2
	var evidence: Variant = investigation.get("evidence", [])
	return evidence is Array and (evidence as Array).size() >= 2


## Only a committed, typed result produces an effect. A preserved recorder does
## not assert legal ownership clearance, a certification does not file a survey
## or reopen a route, and raw ore is never an assay.
static func _effects_for(outcome: Dictionary) -> Array:
	if str(outcome["terminal_state"]) != "completed":
		return []
	var effects: Array = []
	var tag := str(outcome["outcome_tag"])
	if tag == "verified" and bool(outcome["verified"]):
		effects.append(_effect(outcome, EFFECT_VERIFIED_SURVEY))
	if tag == "preserved":
		effects.append(_effect(outcome, EFFECT_RECORDER_PRESERVED))
	if bool(outcome["relief"]) and str(outcome["objective_type"]) == "DELIVER_ORE":
		effects.append(_effect(outcome, EFFECT_MARKED_ORE_DELIVERED))
	# A bound collection contract records the delivery of ITS item, and only
	# when the mission that completed is the objective that contract declared.
	var raw_bound: Variant = outcome.get("collection", {})
	var collection: Dictionary = raw_bound if raw_bound is Dictionary else {}
	if not collection.is_empty() 			and CollectionContractType.validate(collection).is_valid() 			and CollectionContractType.objective_type_for(collection) == str(outcome["objective_type"]):
		var delivered := _effect(outcome, EFFECT_ITEM_DELIVERED)
		delivered["collection_id"] = str(collection["id"])
		delivered["item_id_or_special_name"] = str(collection["item_id_or_special_name"])
		delivered["quantity"] = int(collection["quantity"])
		delivered["destination_station_id"] = str(collection["destination_station_id"])
		# Store who ACTUALLY received it: a recorder handed to a different
		# verified owner must not satisfy the requester's claim.
		delivered["recipient_id"] = str(collection["recipient_id"])
		effects.append(delivered)
	return effects


static func _effect(outcome: Dictionary, kind: String) -> Dictionary:
	return {
		"id": "effect.%s" % ("%s|%s" % [outcome["id"], kind]).sha256_text().substr(0, 24),
		"kind": kind,
		"source_outcome_id": str(outcome["id"]),
		"system_id": str(outcome["system_id"]),
		"faction_id": str(outcome["faction_id"]),
		"desire_id": str(outcome["desire_id"]),
		"cause_id": str(outcome["cause_id"]),
	}


static func validate(value: Dictionary) -> ValidationResult:
	var result := Validation.new()
	if value.is_empty():
		result.add_error("empty_mission_outcome", "Mission outcome is empty.")
		return result
	var mission_id := str(value.get("mission_id", ""))
	var terminal := str(value.get("terminal_state", ""))
	if mission_id.is_empty():
		result.add_error("missing_runtime_mission_id", "Mission outcome has no runtime mission ID.")
	if terminal not in TERMINAL_STATES:
		result.add_error("invalid_terminal_state", "Unsupported terminal state.", "terminal_state")
	if str(value.get("id", "")) != "%s:%s" % [mission_id, terminal]:
		result.add_error("invalid_outcome_id", "Outcome ID must combine the runtime mission ID and terminal state.", "id")
	for int_field in ["credits_paid", "at_minute", "pressure_revision"]:
		var raw: Variant = value.get(int_field, -1)
		if not (raw is int or raw is float) or float(raw) < 0.0:
			result.add_error("invalid_outcome_counter", "A mission outcome counter must be a non-negative integer.", int_field)
	if terminal != "completed":
		if int(value.get("credits_paid", 0)) != 0:
			result.add_error("unpaid_terminal_outcome", "Only a completed mission pays credits.", "credits_paid")
		if not str(value.get("branch_id", "")).is_empty() or not str(value.get("outcome_tag", "")).is_empty():
			result.add_error("unresolved_terminal_branch", "An unfinished mission has no branch or outcome tag.", "branch_id")
		if value.get("effects", []) is Array and not (value["effects"] as Array).is_empty():
			result.add_error("unsupported_terminal_effect", "An unfinished mission commits no effects.", "effects")
	if not value.get("effects", []) is Array:
		result.add_error("invalid_outcome_effects", "Effects must be an array.", "effects")
		return result
	var seen: Dictionary = {}
	for raw: Variant in value["effects"]:
		if not raw is Dictionary:
			result.add_error("invalid_outcome_effect", "Effect entries must be objects.", "effects")
			continue
		var effect: Dictionary = raw
		if str(effect.get("kind", "")) not in SUPPORTED_EFFECTS:
			result.add_error("unsupported_effect_kind", "This effect kind is not implemented.", "effects")
		if str(effect.get("source_outcome_id", "")) != str(value.get("id", "")):
			result.add_error("unbound_effect", "An effect must cite the outcome that produced it.", "effects")
		if str(effect.get("id", "")).is_empty() or seen.has(str(effect.get("id", ""))):
			result.add_error("duplicate_effect", "Effect IDs must be unique.", "effects")
		seen[str(effect.get("id", ""))] = true
	return result
