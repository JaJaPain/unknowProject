extends RefCounted

## Versioned campaign-owned progress projection keyed by (system, faction, desire).
##
## This never rerolls or rewrites a GeneratedFactionDesire identity: it records
## what committed outcomes actually established about an existing desire. A
## generated textual success condition is NOT proof of an implemented effect, so
## `satisfied` and `failed` are reachable only through a typed bound predicate.
## Everything else stays `open` or `progressed`.

const Validation := preload("res://scripts/domain/ValidationResult.gd")
const Outcome := preload("res://scripts/domain/MissionOutcome.gd")

const STATE_VERSION := 1
const STATES := ["open", "progressed", "satisfied", "failed"]

## The only predicates that may close a desire. Each names the exact effect kind
## that proves that exact interest condition; an unsupported condition is left
## open rather than guessed at from its prose.
const SATISFYING_EFFECTS := {
	Outcome.EFFECT_VERIFIED_SURVEY: "survey_evidence_delivered",
	Outcome.EFFECT_RECORDER_PRESERVED: "recorder_delivered_to_verified_owner",
	Outcome.EFFECT_MARKED_ORE_DELIVERED: "marked_ore_delivered",
}


static func empty_state() -> Dictionary:
	return {"version": STATE_VERSION, "entries": {}}


static func key_for(system_id: String, faction_id: String, desire_id: String) -> String:
	if system_id.is_empty() or faction_id.is_empty() or desire_id.is_empty():
		return ""
	return "%s|%s|%s" % [system_id, faction_id, desire_id]


## Record one committed outcome. `context.satisfying_effect_ids` lists the effect
## kinds the campaign has proven close THIS desire; without that proof a success
## only advances the desire to `progressed`.
static func apply_outcome(saved: Dictionary, outcome: Dictionary, context: Dictionary = {}) -> Dictionary:
	var opened := _open(saved)
	if not bool(opened.get("ok", false)):
		return opened
	var state: Dictionary = opened["state"]
	var key := key_for(str(outcome.get("system_id", "")), str(outcome.get("faction_id", "")), str(outcome.get("desire_id", "")))
	if key.is_empty():
		# An unbound mission has no desire to project onto. Fail closed, quietly.
		return _result(false, state, [], "unbound_desire")
	var outcome_id := str(outcome.get("id", ""))
	var entries: Dictionary = state["entries"]
	var entry: Dictionary = entries.get(key, _new_entry(outcome))
	if outcome_id in entry["source_outcome_ids"]:
		return _result(false, state, [], "duplicate_outcome")
	entry["source_outcome_ids"].append(outcome_id)
	var deltas: Array = []
	var before := str(entry["state"])
	var effects: Array = outcome.get("effects", []) if outcome.get("effects", []) is Array else []
	var proven: Array = context.get("satisfying_effect_ids", []) if context.get("satisfying_effect_ids", []) is Array else []
	for raw: Variant in effects:
		if not raw is Dictionary:
			continue
		var effect: Dictionary = raw
		var kind := str(effect.get("kind", ""))
		if kind not in Outcome.SUPPORTED_EFFECTS:
			continue
		if str(effect.get("desire_id", "")) != str(outcome.get("desire_id", "")):
			continue # An effect may only advance the desire it was bound to.
		if str(effect.get("id", "")) in entry["achieved_effect_ids"]:
			continue
		entry["achieved_effect_ids"].append(str(effect.get("id", "")))
		entry["records"].append({"kind": kind, "effect_id": str(effect.get("id", "")), "outcome_id": outcome_id,
			"at_minute": int(outcome.get("at_minute", 0))})
		deltas.append({"kind": "effect_recorded", "effect_kind": kind, "effect_id": str(effect.get("id", "")), "desire_key": key})
		if entry["state"] in ["open", "progressed"]:
			# Only an explicitly proven predicate may close the interest.
			if kind in proven and SATISFYING_EFFECTS.has(kind):
				entry["state"] = "satisfied"
				entry["satisfied_by_predicate"] = str(SATISFYING_EFFECTS[kind])
			else:
				entry["state"] = "progressed"
	if effects.is_empty() and entry["state"] == "open":
		# A wrong answer or an abandoned job is not a permanent desire failure.
		entry["state"] = "open"
	entry["last_outcome_id"] = outcome_id
	entry["last_terminal_state"] = str(outcome.get("terminal_state", ""))
	entry["revision"] = int(entry["revision"]) + 1
	entries[key] = entry
	if str(entry["state"]) != before:
		deltas.append({"kind": "desire_state_changed", "desire_key": key, "from": before, "to": str(entry["state"])})
	return _result(true, state, deltas, "")


## True only when a typed bound predicate proved this exact interest condition.
static func is_satisfied(saved: Dictionary, system_id: String, faction_id: String, desire_id: String) -> bool:
	var key := key_for(system_id, faction_id, desire_id)
	if key.is_empty():
		return false
	var entry: Dictionary = saved.get("entries", {}).get(key, {}) if saved is Dictionary else {}
	return str(entry.get("state", "open")) == "satisfied"


## Causes whose exact fulfilled collection may no longer be reposted.
static func retired_cause_ids(saved: Dictionary) -> Array:
	var result: Array = []
	if not saved is Dictionary:
		return result
	for entry: Variant in saved.get("entries", {}).values():
		if not entry is Dictionary:
			continue
		if str((entry as Dictionary).get("state", "")) == "satisfied":
			var cause := str((entry as Dictionary).get("cause_id", ""))
			if not cause.is_empty() and cause not in result:
				result.append(cause)
	result.sort()
	return result


static func _new_entry(outcome: Dictionary) -> Dictionary:
	return {
		"system_id": str(outcome.get("system_id", "")),
		"faction_id": str(outcome.get("faction_id", "")),
		"desire_id": str(outcome.get("desire_id", "")),
		"cause_id": str(outcome.get("cause_id", "")),
		"state": "open",
		"satisfied_by_predicate": "",
		"records": [],
		"achieved_effect_ids": [],
		"source_outcome_ids": [],
		"last_outcome_id": "",
		"last_terminal_state": "",
		"revision": 0,
	}


static func validate(value: Dictionary) -> ValidationResult:
	var result := Validation.new()
	if value.is_empty():
		return result # Additive: an old campaign has no desire projection yet.
	if int(value.get("version", 0)) != STATE_VERSION:
		result.add_error("unsupported_desire_progress_version", "Unsupported desire progress version.")
		return result
	if not value.get("entries", {}) is Dictionary:
		result.add_error("invalid_desire_progress_entries", "Desire progress entries must be an object.", "entries")
		return result
	for key: Variant in value["entries"]:
		var raw: Variant = value["entries"][key]
		if not raw is Dictionary:
			result.add_error("invalid_desire_progress_entry", "A desire progress entry must be an object.", "entries")
			continue
		var entry: Dictionary = raw
		if key_for(str(entry.get("system_id", "")), str(entry.get("faction_id", "")), str(entry.get("desire_id", ""))) != str(key):
			result.add_error("desire_progress_key_mismatch", "Entry key disagrees with its system/faction/desire.", "entries")
		if str(entry.get("state", "")) not in STATES:
			result.add_error("invalid_desire_progress_state", "Unsupported desire progress state.", "entries")
		for array_field in ["records", "achieved_effect_ids", "source_outcome_ids"]:
			if not entry.get(array_field, []) is Array:
				result.add_error("invalid_desire_progress_array", "A desire progress list must be an array.", "entries")
		if not (entry.get("revision", -1) is int or entry.get("revision", -1) is float) or float(entry.get("revision", -1)) < 0.0:
			result.add_error("invalid_desire_progress_revision", "Desire progress revision must be a non-negative integer.", "entries")
		if str(entry.get("state", "")) == "satisfied" and str(entry.get("satisfied_by_predicate", "")).is_empty():
			result.add_error("unproven_satisfied_desire", "A satisfied desire must name the predicate that proved it.", "entries")
		for record: Variant in (entry.get("records", []) as Array if entry.get("records", []) is Array else []):
			if not record is Dictionary or str((record as Dictionary).get("kind", "")) not in Outcome.SUPPORTED_EFFECTS:
				result.add_error("unsupported_desire_progress_record", "A desire progress record cites an unimplemented effect.", "entries")
	return result


static func _open(saved: Dictionary) -> Dictionary:
	if saved == null or saved.is_empty():
		return {"ok": true, "changed": false, "state": empty_state(), "deltas": [], "reason": ""}
	var result := validate(saved)
	if not result.is_valid():
		return {"ok": false, "changed": false, "state": saved.duplicate(true), "deltas": [],
			"reason": str(result.errors[0].get("code", "invalid_desire_progress"))}
	var state := saved.duplicate(true)
	if not state.get("entries", {}) is Dictionary:
		state["entries"] = {}
	return {"ok": true, "changed": false, "state": state, "deltas": [], "reason": ""}


static func _result(changed: bool, state: Dictionary, deltas: Array, reason: String, ok: bool = true) -> Dictionary:
	return {"ok": ok, "changed": changed, "state": JSON.parse_string(JSON.stringify(state)), "deltas": deltas, "reason": reason}
