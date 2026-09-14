extends RefCounted

## Campaign resolution plans (plan P3 deliverable D).
##
## A plan says what THIS campaign is about and what would count as having
## resolved it, in typed predicates a machine can check. The director may choose
## which of the code-provided candidate interests and effects a plan references;
## it may not invent an executable predicate, a numeric score, an expression
## string or a new effect kind. Everything here is validated against the actual
## campaign before a plan may become active.
##
## Reaching pressure level 3, or refusing a mission, is not campaign failure.

const Validation := preload("res://scripts/domain/ValidationResult.gd")
const Outcome := preload("res://scripts/domain/MissionOutcome.gd")
const Ledger := preload("res://scripts/story/DesireProgressLedger.gd")

const PLAN_VERSION := 1
const STATUS_PENDING := "pending_bindings"
const STATUS_ACTIVE := "active"
const STATUS_RESOLVED := "resolved"
const STATUSES := [STATUS_PENDING, STATUS_ACTIVE, STATUS_RESOLVED]

const RESULT_SUCCESS := "success"
const RESULT_PARTIAL := "partial"
const RESULT_FAILURE := "failure"
const RESULTS := [RESULT_SUCCESS, RESULT_PARTIAL, RESULT_FAILURE]

const KIND_EFFECT := "effect_committed"
const KIND_DESIRE := "desire_state"
const KIND_FACT := "fact_known"
const PREDICATE_KINDS := [KIND_EFFECT, KIND_DESIRE, KIND_FACT]
const CLOSING_DESIRE_STATES := ["satisfied", "failed"]


static func empty_plan() -> Dictionary:
	return {}


## Structural validation only: shape, closed vocabularies, no duplicates. This
## does NOT prove the plan's references exist — `bind` does that.
static func validate(plan: Dictionary) -> ValidationResult:
	var result := Validation.new()
	if plan.is_empty():
		return result # Additive: a campaign without a plan is not an error.
	if int(plan.get("version", 0)) != PLAN_VERSION:
		result.add_error("unsupported_resolution_version", "Unsupported resolution plan version.")
		return result
	if str(plan.get("id", "")).is_empty():
		result.add_error("missing_resolution_id", "A resolution plan needs an ID.", "id")
	if str(plan.get("status", "")) not in STATUSES:
		result.add_error("invalid_resolution_status", "Unsupported resolution plan status.", "status")
	for array_field in ["premise_fact_ids", "interests", "alternatives"]:
		if not plan.get(array_field, []) is Array:
			result.add_error("invalid_resolution_array", "A resolution plan list must be an array.", array_field)
	if not result.is_valid():
		return result
	var interest_ids: Dictionary = {}
	for raw: Variant in plan["interests"]:
		if not raw is Dictionary:
			result.add_error("invalid_resolution_interest", "Interest entries must be objects.", "interests")
			continue
		var interest: Dictionary = raw
		for field in ["id", "system_id", "faction_id", "desire_id"]:
			if str(interest.get(field, "")).is_empty():
				result.add_error("unbound_resolution_interest", "An interest is missing its binding.", "interests")
		if interest_ids.has(str(interest.get("id", ""))):
			result.add_error("duplicate_resolution_interest", "Interest IDs must be unique.", "interests")
		interest_ids[str(interest.get("id", ""))] = true
		if not interest.get("supported_effect_ids", []) is Array:
			result.add_error("invalid_supported_effects", "supported_effect_ids must be an array.", "interests")
			continue
		for effect: Variant in interest["supported_effect_ids"]:
			# Only implemented effect kinds may ever close an interest.
			if str(effect) not in Outcome.SUPPORTED_EFFECTS:
				result.add_error("unsupported_resolution_effect", "A plan references an unimplemented effect kind.", "interests")
	if (plan["alternatives"] as Array).is_empty():
		result.add_error("no_resolution_alternatives", "A plan needs at least one alternative.", "alternatives")
	var alternative_ids: Dictionary = {}
	for raw: Variant in plan["alternatives"]:
		if not raw is Dictionary:
			result.add_error("invalid_resolution_alternative", "Alternative entries must be objects.", "alternatives")
			continue
		var alternative: Dictionary = raw
		if str(alternative.get("id", "")).is_empty() or alternative_ids.has(str(alternative.get("id", ""))):
			result.add_error("invalid_alternative_id", "Alternative IDs must be present and unique.", "alternatives")
		alternative_ids[str(alternative.get("id", ""))] = true
		if str(alternative.get("result", "")) not in RESULTS:
			result.add_error("invalid_alternative_result", "Unsupported alternative result.", "alternatives")
		if not alternative.get("all_of", []) is Array or (alternative.get("all_of", []) as Array).is_empty():
			# An empty condition set would resolve instantly and mean nothing.
			result.add_error("empty_success_condition", "An alternative needs at least one predicate.", "alternatives")
			continue
		for raw_predicate: Variant in alternative["all_of"]:
			result.merge(_validate_predicate(raw_predicate), "alternatives")
		if not alternative.get("public_fact_ids", []) is Array:
			result.add_error("invalid_public_fact_ids", "public_fact_ids must be an array.", "alternatives")
	return result


static func _validate_predicate(raw: Variant) -> ValidationResult:
	var result := Validation.new()
	if not raw is Dictionary:
		result.add_error("invalid_predicate", "A predicate must be an object.")
		return result
	var predicate: Dictionary = raw
	var kind := str(predicate.get("kind", ""))
	if kind not in PREDICATE_KINDS:
		# No freeform code, expression strings or numeric scores.
		result.add_error("unsupported_predicate_kind", "Unsupported predicate kind.")
		return result
	match kind:
		KIND_EFFECT:
			if str(predicate.get("effect_id", "")).is_empty():
				result.add_error("unbound_effect_predicate", "An effect predicate needs an effect ID.")
		KIND_DESIRE:
			if str(predicate.get("desire_id", "")).is_empty() or str(predicate.get("system_id", "")).is_empty():
				result.add_error("unbound_desire_predicate", "A desire predicate needs a desire and system.")
			if str(predicate.get("state", "")) not in CLOSING_DESIRE_STATES:
				result.add_error("invalid_desire_predicate_state", "A desire predicate must test satisfied or failed.")
		KIND_FACT:
			if str(predicate.get("fact_id", "")).is_empty():
				result.add_error("unbound_fact_predicate", "A fact predicate needs a fact ID.")
	return result


## Prove every reference against the ACTUAL campaign, then activate. Until the
## generation path has created the referenced interests and reachable locations,
## the plan stays pending — we never conjure a frontier system to satisfy a
## missing reference.
## context = {desires: [{system_id, faction_id, desire_id}], station_ids: [],
##            system_ids: [], known_fact_ids: [], effect_ids: []}
static func bind(plan: Dictionary, context: Dictionary) -> Dictionary:
	var structural := validate(plan)
	if not structural.is_valid():
		return {"ok": false, "reason": str(structural.errors[0].get("code", "invalid_resolution_plan"))}
	if plan.is_empty():
		return {"ok": false, "reason": "no_resolution_plan"}
	var bound := plan.duplicate(true)
	if str(bound["status"]) == STATUS_RESOLVED:
		return {"ok": true, "changed": false, "plan": bound, "reason": "already_resolved"}
	var desires: Dictionary = {}
	for raw: Variant in context.get("desires", []):
		if raw is Dictionary:
			var d: Dictionary = raw
			# A desire ID is only valid inside its OWNING faction and system.
			desires["%s|%s|%s" % [d.get("system_id", ""), d.get("faction_id", ""), d.get("desire_id", "")]] = true
	var systems: Array = context.get("system_ids", [])
	var missing: Array = []
	for raw: Variant in bound["interests"]:
		var interest: Dictionary = raw
		var key := "%s|%s|%s" % [interest["system_id"], interest["faction_id"], interest["desire_id"]]
		if not desires.has(key):
			missing.append(str(interest["id"]))
			continue
		if not str(interest["system_id"]) in systems:
			missing.append(str(interest["id"]))
	var interest_desires: Dictionary = {}
	for raw: Variant in bound["interests"]:
		interest_desires["%s|%s" % [(raw as Dictionary)["system_id"], (raw as Dictionary)["desire_id"]]] = true
	# Every predicate must reference something this campaign can actually reach.
	for raw: Variant in bound["alternatives"]:
		var alternative: Dictionary = raw
		for raw_predicate: Variant in alternative["all_of"]:
			var predicate: Dictionary = raw_predicate
			match str(predicate["kind"]):
				KIND_DESIRE:
					if not interest_desires.has("%s|%s" % [predicate["system_id"], predicate["desire_id"]]):
						return {"ok": false, "reason": "unknown_desire_reference"}
				KIND_FACT:
					# fact_known reads the existing ledger and cannot promote itself.
					if str(predicate["fact_id"]) not in context.get("known_fact_ids", []) \
							and str(predicate["fact_id"]) not in context.get("candidate_fact_ids", []):
						return {"ok": false, "reason": "unknown_fact_reference"}
				KIND_EFFECT:
					if str(predicate["effect_id"]) not in context.get("effect_ids", []):
						return {"ok": false, "reason": "unknown_effect_reference"}
	var overlap := _overlapping_alternatives(bound["alternatives"])
	if not overlap.is_empty():
		# Do not pick the first arbitrary array element when two could both fire.
		return {"ok": false, "reason": "ambiguous_alternatives", "detail": overlap}
	for raw: Variant in bound["alternatives"]:
		var alternative: Dictionary = raw
		if str(alternative["result"]) in [RESULT_PARTIAL, RESULT_FAILURE] and not _establishes_loss(alternative):
			# A loss must be established by a committed supported effect or a
			# proven desire state, never assumed from absence.
			return {"ok": false, "reason": "unestablished_loss_alternative"}
	if not missing.is_empty():
		bound["status"] = STATUS_PENDING
		bound["pending_interest_ids"] = missing
		return {"ok": true, "changed": true, "plan": _persistable(bound), "reason": "pending_bindings"}
	bound["status"] = STATUS_ACTIVE
	bound["pending_interest_ids"] = []
	# Active predicates are frozen: later generation cannot rewrite the terms the
	# campaign is being judged against.
	bound["frozen"] = true
	return {"ok": true, "changed": true, "plan": _persistable(bound), "reason": ""}


## Two alternatives overlap when one's predicate set is a subset of the other's
## and they claim different results: both could fire from the same world.
static func _overlapping_alternatives(alternatives: Array) -> Array:
	for i in range(alternatives.size()):
		for j in range(alternatives.size()):
			if i == j:
				continue
			var a: Dictionary = alternatives[i]
			var b: Dictionary = alternatives[j]
			if str(a["result"]) == str(b["result"]):
				continue
			if _is_subset(a["all_of"], b["all_of"]):
				return [str(a["id"]), str(b["id"])]
	return []


static func _is_subset(inner: Array, outer: Array) -> bool:
	for predicate: Variant in inner:
		var found := false
		for other: Variant in outer:
			if JSON.stringify(predicate) == JSON.stringify(other):
				found = true
		if not found:
			return false
	return true


static func _establishes_loss(alternative: Dictionary) -> bool:
	for raw: Variant in alternative["all_of"]:
		var predicate: Dictionary = raw
		if str(predicate["kind"]) == KIND_EFFECT:
			return true
		if str(predicate["kind"]) == KIND_DESIRE and str(predicate["state"]) == "failed":
			return true
	return false


static func _persistable(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))


## Evaluate an ACTIVE plan against committed state. Called after every committed
## mechanical or knowledge transaction, never on panel opening or elapsed time.
## Returns {ok, resolved, record, reason}; the caller stages the record in the
## SAME checkpoint as the effects that triggered it.
## world = {committed_effect_ids: [], desire_progress: {}, known_fact_ids: [],
##          source_outcome_ids: [], activity_step: int}
static func evaluate(plan: Dictionary, world: Dictionary) -> Dictionary:
	if plan.is_empty() or str(plan.get("status", "")) != STATUS_ACTIVE:
		return {"ok": true, "resolved": false, "reason": "no_active_plan"}
	var committed: Array = world.get("committed_effect_ids", [])
	var progress: Dictionary = world.get("desire_progress", {})
	var known: Array = world.get("known_fact_ids", [])
	for raw: Variant in plan["alternatives"]:
		var alternative: Dictionary = raw
		var satisfied := true
		for raw_predicate: Variant in alternative["all_of"]:
			if not _predicate_holds(raw_predicate, committed, progress, known):
				satisfied = false
				break
		if not satisfied:
			continue
		return {"ok": true, "resolved": true, "record": _record(plan, alternative, world)}
	return {"ok": true, "resolved": false, "reason": "conditions_unmet"}


static func _predicate_holds(raw: Variant, committed: Array, progress: Dictionary, known: Array) -> bool:
	var predicate: Dictionary = raw
	match str(predicate["kind"]):
		KIND_EFFECT:
			return str(predicate["effect_id"]) in committed
		KIND_DESIRE:
			var entries: Dictionary = progress.get("entries", {}) if progress is Dictionary else {}
			for entry: Variant in entries.values():
				if not entry is Dictionary:
					continue
				var record: Dictionary = entry
				if str(record.get("desire_id", "")) != str(predicate["desire_id"]):
					continue
				if str(record.get("system_id", "")) != str(predicate["system_id"]):
					continue
				# A desire state counts only when the ledger actually proved it.
				return str(record.get("state", "")) == str(predicate["state"])
			return false
		KIND_FACT:
			return str(predicate["fact_id"]) in known
	return false


## The record keeps the factual basis of the ending: what was achieved, what was
## left open, and which outcomes produced it.
static func _record(plan: Dictionary, alternative: Dictionary, world: Dictionary) -> Dictionary:
	var committed: Array = world.get("committed_effect_ids", [])
	var achieved: Array = []
	var unresolved: Array = []
	var progress: Dictionary = world.get("desire_progress", {})
	for raw: Variant in plan["interests"]:
		var interest: Dictionary = raw
		var closed := false
		for effect_kind: Variant in interest.get("supported_effect_ids", []):
			if str(effect_kind) in committed and str(effect_kind) not in achieved:
				achieved.append(str(effect_kind))
		if Ledger.is_satisfied(progress, str(interest["system_id"]), str(interest["faction_id"]), str(interest["desire_id"])):
			closed = true
		if not closed:
			unresolved.append(str(interest["id"]))
	return {
		"plan_id": str(plan["id"]),
		"alternative_id": str(alternative["id"]),
		"result": str(alternative["result"]),
		"source_outcome_ids": (world.get("source_outcome_ids", []) as Array).duplicate(),
		"achieved_effect_ids": achieved,
		"unresolved_interest_ids": unresolved,
		"known_fact_ids": (alternative.get("public_fact_ids", []) as Array).duplicate(),
		"committed_at_step": int(world.get("activity_step", 0)),
	}


## Mark the plan resolved. Free play continues: only the resolved primary arc
## stops refilling. Unrelated optional work and accepted missions are untouched.
static func resolve(plan: Dictionary, record: Dictionary) -> Dictionary:
	var resolved := plan.duplicate(true)
	resolved["status"] = STATUS_RESOLVED
	resolved["record"] = record.duplicate(true)
	return _persistable(resolved)


## A factual summary of what the campaign actually established. No invented
## epilogue: only the committed public record.
static func summary_lines(record: Dictionary) -> Array:
	var lines: Array = []
	match str(record.get("result", "")):
		RESULT_SUCCESS: lines.append("The campaign's central interest was resolved.")
		RESULT_PARTIAL: lines.append("The campaign resolved in part; some interests remain open.")
		RESULT_FAILURE: lines.append("The campaign's central interest was lost.")
	var achieved: Array = record.get("achieved_effect_ids", [])
	if achieved.is_empty():
		lines.append("No supported effect was committed.")
	else:
		lines.append("Established: %s." % ", ".join(achieved).replace("_", " "))
	var unresolved: Array = record.get("unresolved_interest_ids", [])
	if not unresolved.is_empty():
		lines.append("Still open: %d interest(s)." % unresolved.size())
	lines.append("Decided by %d committed mission outcome(s)." % (record.get("source_outcome_ids", []) as Array).size())
	return lines
