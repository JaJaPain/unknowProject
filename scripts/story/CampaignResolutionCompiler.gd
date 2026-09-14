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
## Version 2 adds the `collection_satisfied` predicate and typed interests. A v1
## plan keeps its ORIGINAL predicates and is never silently reinterpreted; it is
## marked `legacy_resolution` for diagnostics instead. No new v1 plan is written.
const PLAN_VERSION_V2 := 2
const SUPPORTED_PLAN_VERSIONS := [PLAN_VERSION, PLAN_VERSION_V2]
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
## v2 only. Proves that ONE persisted collection contract was actually
## delivered, scoped by collection ID, faction, system and recipient. It does
## NOT prove the faction's broad goal.
const KIND_COLLECTION := "collection_satisfied"
const PREDICATE_KINDS := [KIND_EFFECT, KIND_DESIRE, KIND_FACT]
const PREDICATE_KINDS_V2 := [KIND_EFFECT, KIND_DESIRE, KIND_FACT, KIND_COLLECTION]
const CLOSING_DESIRE_STATES := ["satisfied", "failed"]

## Exactly three. The first two are existing investigation receipts; the third is
## the delivery receipt from the collection contract work.
const COMPLETION_KINDS_V2 := [
	Outcome.EFFECT_VERIFIED_SURVEY,
	Outcome.EFFECT_RECORDER_PRESERVED,
	Outcome.EFFECT_ITEM_DELIVERED,
]


static func plan_version(plan: Dictionary) -> int:
	return int(plan.get("version", 0))


static func is_legacy_plan(plan: Dictionary) -> bool:
	return plan_version(plan) == PLAN_VERSION and not plan.is_empty()


static func empty_plan() -> Dictionary:
	return {}


## Structural validation only: shape, closed vocabularies, no duplicates. This
## does NOT prove the plan's references exist — `bind` does that.
static func validate(plan: Dictionary) -> ValidationResult:
	var result := Validation.new()
	if plan.is_empty():
		return result # Additive: a campaign without a plan is not an error.
	var version := plan_version(plan)
	if version not in SUPPORTED_PLAN_VERSIONS:
		result.add_error("unsupported_resolution_version", "Unsupported resolution plan version.")
		return result
	if str(plan.get("id", "")).is_empty():
		result.add_error("missing_resolution_id", "A resolution plan needs an ID.", "id")
	if str(plan.get("status", "")) not in STATUSES:
		result.add_error("invalid_resolution_status", "Unsupported resolution plan status.", "status")
	for array_field in ["premise_fact_ids", "interests", "alternatives"]:
		if not plan.get(array_field) is Array:
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
		if version == PLAN_VERSION_V2:
			# A v2 interest names the collection it is about, where it happens
			# and who must receive it. A prose phrase is not a collection ID.
			for field in ["collection_id", "station_id", "recipient_id"]:
				if str(interest.get(field, "")).is_empty():
					result.add_error("unbound_resolution_interest", "A v2 interest is missing its collection binding.", "interests")
			if str(interest.get("completion_kind", "")) not in COMPLETION_KINDS_V2:
				result.add_error("unsupported_completion_kind", "A v2 interest must cite an implemented completion kind.", "interests")
		if not interest.get("supported_effect_ids") is Array:
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
			result.merge(_validate_predicate(raw_predicate, version), "alternatives")
		if not alternative.get("public_fact_ids", []) is Array:
			result.add_error("invalid_public_fact_ids", "public_fact_ids must be an array.", "alternatives")
	return result


static func _validate_predicate(raw: Variant, version: int = PLAN_VERSION) -> ValidationResult:
	var result := Validation.new()
	if not raw is Dictionary:
		result.add_error("invalid_predicate", "A predicate must be an object.")
		return result
	var predicate: Dictionary = raw
	var kind := str(predicate.get("kind", ""))
	var allowed: Array = PREDICATE_KINDS_V2 if version == PLAN_VERSION_V2 else PREDICATE_KINDS
	if kind not in allowed:
		# No freeform code, expression strings or numeric scores. A v1 plan also
		# never gains a v2 predicate by reinterpretation.
		result.add_error("unsupported_predicate_kind", "Unsupported predicate kind.")
		return result
	match kind:
		KIND_COLLECTION:
			if str(predicate.get("collection_id", "")).is_empty():
				result.add_error("unbound_collection_predicate", "A collection predicate needs a collection ID.")
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
	# A v1 plan keeps its ORIGINAL predicates. It is marked for diagnostics, not
	# reinterpreted: silently upgrading it would change what the campaign is
	# being judged against after the fact.
	if is_legacy_plan(bound):
		bound["legacy_resolution"] = true
	if str(bound["status"]) == STATUS_RESOLVED:
		return {"ok": true, "changed": false, "plan": bound, "reason": "already_resolved"}
	if str(bound["status"]) == STATUS_ACTIVE:
		return {"ok": true, "changed": false, "plan": bound, "reason": "already_active"}
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
	var interest_collections: Dictionary = {}
	for raw: Variant in bound["interests"]:
		interest_desires["%s|%s" % [(raw as Dictionary)["system_id"], (raw as Dictionary)["desire_id"]]] = true
		var collection_id := str((raw as Dictionary).get("collection_id", ""))
		if not collection_id.is_empty():
			interest_collections[collection_id] = raw
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
				KIND_COLLECTION:
					# Each collection ID must belong to a persisted accepted
					# contract or a validated available opportunity. A prose
					# phrase that happens to look like an ID is not one.
					if str(predicate["collection_id"]) not in context.get("collection_ids", []):
						return {"ok": false, "reason": "unknown_collection_reference"}
					if not interest_collections.has(str(predicate["collection_id"])):
						return {"ok": false, "reason": "collection_not_an_interest"}
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
			# Positive effect/fact predicates may all hold together. Only opposite
			# terminal states of the same desire prove mutual exclusion.
			var exclusive := false
			for left: Dictionary in a["all_of"]:
				for right: Dictionary in b["all_of"]:
					if left.get("kind") == KIND_DESIRE and right.get("kind") == KIND_DESIRE and left.get("system_id") == right.get("system_id") and left.get("desire_id") == right.get("desire_id") and left.get("state") != right.get("state"):
						exclusive = true
			if not exclusive:
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
		# No implemented effect kind currently establishes irreversible loss.
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
	var interests_by_collection: Dictionary = {}
	for raw: Variant in plan.get("interests", []):
		if raw is Dictionary and not str((raw as Dictionary).get("collection_id", "")).is_empty():
			interests_by_collection[str((raw as Dictionary)["collection_id"])] = raw
	for raw: Variant in plan["alternatives"]:
		var alternative: Dictionary = raw
		var satisfied := true
		for raw_predicate: Variant in alternative["all_of"]:
			if not _predicate_holds(raw_predicate, committed, progress, known, interests_by_collection):
				satisfied = false
				break
		if not satisfied:
			continue
		return {"ok": true, "resolved": true, "record": _record(plan, alternative, world)}
	return {"ok": true, "resolved": false, "reason": "conditions_unmet"}


static func _predicate_holds(raw: Variant, committed: Array, progress: Dictionary, known: Array,
		interests_by_collection: Dictionary = {}) -> bool:
	var predicate: Dictionary = raw
	match str(predicate["kind"]):
		KIND_COLLECTION:
			return _collection_receipt_matches(str(predicate["collection_id"]), progress,
				interests_by_collection.get(str(predicate["collection_id"]), {}))
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


## A collection predicate holds only when a COMMITTED receipt matches its
## interest on every axis that identifies it: the collection, the faction, the
## system and the recipient who actually took delivery. A recorder handed to a
## different verified owner does not satisfy the requester's claim, and a survey
## filed with the wrong certification does not satisfy a verified-evidence
## milestone.
static func _collection_receipt_matches(collection_id: String, progress: Dictionary,
		interest: Variant) -> bool:
	if collection_id.is_empty() or not interest is Dictionary:
		return false
	var bound: Dictionary = interest
	var expected_kind := str(bound.get("completion_kind", ""))
	for receipt: Dictionary in Ledger.fulfilled_collection_receipts(progress):
		if str(receipt.get("collection_id", "")) != collection_id:
			continue
		if str(receipt.get("faction_id", "")) != str(bound.get("faction_id", "")):
			continue
		if str(receipt.get("system_id", "")) != str(bound.get("system_id", "")):
			continue
		if str(receipt.get("recipient_id", "")) != str(bound.get("recipient_id", "")):
			continue
		if not str(bound.get("station_id", "")).is_empty() 				and str(receipt.get("destination_station_id", "")) != str(bound.get("station_id", "")):
			continue
		if expected_kind != Outcome.EFFECT_ITEM_DELIVERED:
			continue
		return true
	# The two investigation completion kinds are proved by their own committed
	# effect on the interest's desire, not by a delivery receipt.
	if expected_kind in [Outcome.EFFECT_VERIFIED_SURVEY, Outcome.EFFECT_RECORDER_PRESERVED]:
		return _investigation_receipt_matches(bound, expected_kind, progress)
	return false


static func _investigation_receipt_matches(interest: Dictionary, expected_kind: String,
		progress: Dictionary) -> bool:
	var key := Ledger.key_for(str(interest.get("system_id", "")), str(interest.get("faction_id", "")),
		str(interest.get("desire_id", "")))
	var entries: Dictionary = progress.get("entries", {}) if progress is Dictionary else {}
	var entry: Dictionary = entries.get(key, {}) if entries.get(key, {}) is Dictionary else {}
	for raw: Variant in entry.get("records", []):
		if raw is Dictionary and str((raw as Dictionary).get("kind", "")) == expected_kind:
			return true
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
		var key := Ledger.key_for(str(interest["system_id"]), str(interest["faction_id"]), str(interest["desire_id"]))
		var entry: Dictionary = progress.get("entries", {}).get(key, {})
		for effect_id: String in entry.get("achieved_effect_ids", []):
			if effect_id in committed and effect_id not in achieved:
				achieved.append(effect_id)
		if Ledger.is_satisfied(progress, str(interest["system_id"]), str(interest["faction_id"]), str(interest["desire_id"])):
			closed = true
		if not closed:
			unresolved.append(str(interest["id"]))
	# Provenance is what actually DECIDED this ending: the outcomes that produced
	# the matching receipts, not every unrelated job the player took on the way.
	var deciding: Array = []
	for raw: Variant in plan["interests"]:
		var interest: Dictionary = raw
		var key := Ledger.key_for(str(interest["system_id"]), str(interest["faction_id"]), str(interest["desire_id"]))
		var entry: Dictionary = progress.get("entries", {}).get(key, {}) 			if progress.get("entries", {}) is Dictionary else {}
		var from_records := false
		for raw_record: Variant in entry.get("records", []):
			if not raw_record is Dictionary:
				continue
			var record: Dictionary = raw_record
			if str(record.get("effect_id", "")) not in achieved:
				continue
			from_records = true
			var outcome_id := str(record.get("outcome_id", ""))
			if not outcome_id.is_empty() and outcome_id not in deciding:
				deciding.append(outcome_id)
		if from_records:
			continue
		# An entry with no per-effect record still names the outcomes that
		# advanced THIS interest. Those are scoped; unrelated campaign missions
		# never appear because only plan interests are walked.
		for raw_outcome: Variant in entry.get("source_outcome_ids", []):
			var source_id := str(raw_outcome)
			if not source_id.is_empty() and source_id not in deciding:
				deciding.append(source_id)
	deciding.sort()
	# A summary may only cite facts the knowledge ledger actually knows.
	var public_facts: Array = []
	for fact_id: Variant in (alternative.get("public_fact_ids", []) as Array):
		if str(fact_id) in world.get("known_fact_ids", []):
			public_facts.append(str(fact_id))
	return {
		"plan_id": str(plan["id"]),
		"alternative_id": str(alternative["id"]),
		"result": str(alternative["result"]),
		"source_outcome_ids": deciding,
		"achieved_effect_ids": achieved,
		"unresolved_interest_ids": unresolved,
		"known_fact_ids": public_facts,
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
		lines.append("Confirmed evidence records: %d." % achieved.size())
	var unresolved: Array = record.get("unresolved_interest_ids", [])
	if not unresolved.is_empty():
		lines.append("Still open: %d interest(s)." % unresolved.size())
	lines.append("Decided by %d committed mission outcome(s)." % (record.get("source_outcome_ids", []) as Array).size())
	return lines
