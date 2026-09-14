class_name QuestChoicePolicy
extends RefCounted

## Decides which options and follow-up questions deserve to exist, BEFORE
## conversation planning and UI publication.
##
## Abe's direction, which overrides the older plans' fixed quotas: a quest does
## not need a branching decision, and the same why/risk/connection trio must not
## appear on every conversation. One completion path is a correct outcome, not a
## generation failure. Nothing here ever ADDS an option -- it only removes ones
## that cannot justify themselves.

const ContractType := preload("res://scripts/domain/QuestCausalContract.gd")

## Why a branch was dropped. Surfaced in diagnostics so a shortage of options is
## visible as a decision rather than as silence.
const DROP_UNSUPPORTED_ACTION := "unsupported_action"
const DROP_NO_MOTIVE := "ungrounded_motive"
const DROP_NO_PLAYER_INFORMATION := "player_cannot_know"
const DROP_INELIGIBLE := "ineligible"
const DROP_EQUIVALENT := "equivalent_to_existing"

## Why a question was dropped.
const DROP_NOTHING_TO_ADD := "opening_already_answers_it"
const DROP_NO_SUPPORTED_RISK := "no_supported_risk"
const DROP_NO_KNOWN_CONNECTION := "no_known_connection"


## Filter a contract's branch_contracts down to the ones that earn a button.
##
## `context` may carry:
##   supported_action_ids : Array  -- actions this build can actually execute
##   satisfied_predicates : Array  -- eligibility predicates currently true
##   known_fact_ids       : Array  -- what the player can know right now
##
## An empty `supported_action_ids` means the caller did not supply a whitelist,
## so action support is not second-guessed here. An empty result is valid: the
## quest simply has one completion path.
static func filter_branches(contract_source: Variant, context: Dictionary = {}) -> Dictionary:
	var contract: Dictionary = ContractType.normalize(contract_source)
	var branches: Array = contract.get("branch_contracts", [])
	var supported := _string_array(context.get("supported_action_ids", []))
	var satisfied := _string_array(context.get("satisfied_predicates", []))
	var known := _string_array(context.get("known_fact_ids", []))
	var public_facts := ContractType.public_facts(contract)
	var private_ids := ContractType.private_facts(contract).keys()

	var kept: Array[Dictionary] = []
	var dropped: Array[Dictionary] = []
	for raw_branch in branches:
		if not (raw_branch is Dictionary):
			continue
		var branch: Dictionary = raw_branch
		var reason := _branch_drop_reason(
			branch, supported, satisfied, known, public_facts, private_ids
		)
		if reason.is_empty():
			reason = _equivalence_reason(branch, kept)
		if reason.is_empty():
			kept.append(branch)
			continue
		dropped.append({
			"id": str(branch.get("id", "")),
			"action_id": str(branch.get("action_id", "")),
			"reason": reason,
		})
	return {
		"branches": kept,
		"dropped": dropped,
		# One surviving branch is not a choice -- it is just how the quest ends.
		# Publishing a single-option menu is the manufactured-dilemma smell.
		"single_path": kept.size() <= 1,
	}


static func _branch_drop_reason(
	branch: Dictionary,
	supported: Array[String],
	satisfied: Array[String],
	known: Array[String],
	public_facts: Dictionary,
	private_ids: Array
) -> String:
	var action_id := str(branch.get("action_id", "")).strip_edges()
	if action_id.is_empty():
		return DROP_UNSUPPORTED_ACTION
	if not supported.is_empty() and action_id not in supported:
		return DROP_UNSUPPORTED_ACTION
	# Eligibility is only judged when the caller told us what is currently true.
	if not satisfied.is_empty():
		for predicate in _string_array(branch.get("eligibility_predicates", [])):
			if predicate not in satisfied:
				return DROP_INELIGIBLE
	# A motive must exist AND be something the player could act on. A branch
	# motivated only by a secret is a trap, not a choice.
	var motives := _string_array(branch.get("motivation_fact_ids", []))
	if motives.is_empty():
		return DROP_NO_MOTIVE
	var visible_motive := false
	for fact_id in motives:
		if fact_id in private_ids:
			continue
		if public_facts.has(fact_id):
			visible_motive = true
			break
	if not visible_motive:
		return DROP_NO_MOTIVE
	# The player has to have enough information to understand what they are
	# picking. When the caller supplies a knowledge snapshot, honor it.
	var information := _string_array(branch.get("public_information_fact_ids", []))
	if information.is_empty():
		return DROP_NO_PLAYER_INFORMATION
	if not known.is_empty():
		var any_known := false
		for fact_id in information:
			if fact_id in known:
				any_known = true
				break
		if not any_known:
			return DROP_NO_PLAYER_INFORMATION
	return ""


## Two buttons that run the same action and record the same result are one
## button. A cost difference or a different recorded outcome makes them genuinely
## different; a different LABEL does not.
static func _equivalence_reason(branch: Dictionary, kept: Array[Dictionary]) -> String:
	var fingerprint := _branch_fingerprint(branch)
	for existing in kept:
		if _branch_fingerprint(existing) == fingerprint:
			return DROP_EQUIVALENT
	return ""


static func _branch_fingerprint(branch: Dictionary) -> String:
	var effects := _string_array(branch.get("effect_ids", []))
	effects.sort()
	var costs: Dictionary = branch.get("costs", {}) \
		if branch.get("costs", {}) is Dictionary else {}
	var cost_keys: Array = costs.keys()
	cost_keys.sort()
	var cost_parts: Array[String] = []
	for key in cost_keys:
		cost_parts.append("%s=%s" % [str(key), str(costs[key])])
	return "%s|%s|%s|%s" % [
		str(branch.get("action_id", "")),
		str(branch.get("outcome_id", "")),
		",".join(effects),
		",".join(cost_parts),
	]


## Decide which follow-up QUESTIONS are worth offering. Returns the intent ids
## that are eligible plus the reason each rejected one was dropped.
##
## `opening_text` matters: if the speaker already said why it matters, asking
## "why does this matter?" is a button that produces a restatement. That is the
## single most common way generated conversations sound robotic.
static func filter_questions(
	contract_source: Variant,
	candidate_intent_ids: Array,
	context: Dictionary = {}
) -> Dictionary:
	var contract: Dictionary = ContractType.normalize(contract_source)
	var opening := str(context.get("opening_text", "")).strip_edges()
	var eligible: Array[String] = []
	var dropped: Array[Dictionary] = []
	for raw_intent in candidate_intent_ids:
		var intent_id := str(raw_intent).strip_edges()
		if intent_id.is_empty() or intent_id in eligible:
			continue
		var reason := _question_drop_reason(intent_id, contract, opening, context)
		if reason.is_empty():
			eligible.append(intent_id)
			continue
		dropped.append({"id": intent_id, "reason": reason})
	return {"intent_ids": eligible, "dropped": dropped}


static func _question_drop_reason(
	intent_id: String,
	contract: Dictionary,
	opening: String,
	context: Dictionary
) -> String:
	match intent_id:
		"ask_why":
			# Only worth asking if there is explanation the opening did NOT give.
			# Both lists are the same question to the player -- "why this?" -- so
			# they are judged together, not one as a fallback for the other.
			var why_candidates: Array[String] = []
			for field in ["why_this_action_fact_ids", "problem_fact_ids"]:
				for fact_id in _string_array(contract.get(field, [])):
					if fact_id not in why_candidates:
						why_candidates.append(fact_id)
			var why_facts := _unspoken_facts(contract, why_candidates, opening)
			return "" if not why_facts.is_empty() else DROP_NOTHING_TO_ADD
		"ask_risk":
			# No invented danger. A risk question needs a recorded risk.
			var risk_facts := _facts_of_kind(contract, ["risk", "hazard", "uncertainty"])
			if risk_facts.is_empty() and not bool(context.get("has_supported_risk", false)):
				return DROP_NO_SUPPORTED_RISK
			return ""
		"ask_connection":
			# A connection question needs an actual connection to something the
			# player has already met, not merely a cause_id existing.
			if not bool(context.get("has_known_connection", false)):
				return DROP_NO_KNOWN_CONNECTION
			return ""
		"clarify_term", "informed_followup":
			return ""
		_:
			return ""


## Facts whose substance the opening has not already stated. Crude on purpose:
## a cheap overlap test that removes the obvious restatements without pretending
## to judge meaning. Semantic judgement belongs to the quality gate.
static func _unspoken_facts(
	contract: Dictionary,
	fact_ids: Variant,
	opening: String
) -> Array[String]:
	var remaining: Array[String] = []
	if opening.is_empty():
		return _string_array(fact_ids)
	var opening_lower := opening.to_lower()
	for fact_id in _string_array(fact_ids):
		var text := ContractType.fact_text(contract, fact_id)
		if text.is_empty():
			continue
		if not _substance_already_spoken(text, opening_lower):
			remaining.append(fact_id)
	return remaining


static func _substance_already_spoken(fact_text: String, opening_lower: String) -> bool:
	var distinctive := _distinctive_words(fact_text)
	if distinctive.is_empty():
		return false
	var hits := 0
	for word in distinctive:
		if opening_lower.contains(word):
			hits += 1
	# Most of the fact's distinctive words already present means the opening
	# covered it. A stray shared word does not.
	return float(hits) / float(distinctive.size()) >= 0.6


static func _distinctive_words(text: String) -> Array[String]:
	var stop_words := [
		"the", "a", "an", "and", "or", "but", "of", "to", "in", "on", "at", "for",
		"with", "is", "are", "was", "were", "be", "been", "it", "its", "that",
		"this", "they", "them", "their", "there", "has", "have", "had", "not",
		"will", "can", "cannot", "from", "into", "out", "up", "down", "own",
	]
	var words: Array[String] = []
	for raw_word in text.to_lower().split(" ", false):
		var word := str(raw_word).strip_edges()
		for punctuation in [".", ",", ";", ":", "'s", "\"", "'", "!", "?"]:
			word = word.trim_suffix(punctuation)
		if word.length() < 4 or word in stop_words or word in words:
			continue
		words.append(word)
	return words


## Eligibility predicates carried by a rendered branch intent, so the click-time
## recheck reads them from the same place the policy wrote them.
static func branch_predicates(intent: Dictionary) -> Array[String]:
	return _string_array(intent.get("eligibility_predicates", []))


## Does this contract actually RECORD a risk? Used by the plan builder so a risk
## question can be offered on a non-combat job that genuinely has one, without
## inventing danger for jobs that do not.
static func contract_records_risk(contract_source: Variant) -> bool:
	var contract: Dictionary = ContractType.normalize(contract_source)
	return not _facts_of_kind(contract, ["risk", "hazard", "uncertainty"]).is_empty()


static func _facts_of_kind(contract: Dictionary, kinds: Array) -> Array[String]:
	var matches: Array[String] = []
	var facts: Variant = contract.get("facts", {})
	if not (facts is Dictionary):
		return matches
	for fact_id in (facts as Dictionary).keys():
		var fact: Variant = (facts as Dictionary)[fact_id]
		if not (fact is Dictionary):
			continue
		var entry: Dictionary = fact
		if str(entry.get("visibility", "")) != ContractType.VISIBILITY_PUBLIC:
			continue
		if str(entry.get("kind", "")).strip_edges().to_lower() in kinds:
			matches.append(str(fact_id))
	return matches


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array):
		return result
	for item in (value as Array):
		var text := str(item).strip_edges()
		if not text.is_empty() and text not in result:
			result.append(text)
	return result
