extends RefCounted

## Pure P3 pressure reducer (plan P3). Owned by StoryManager; no scene access,
## no wall clock, no model text. One activity step is exactly one committed
## terminal outcome for an accepted, non-tutorial mission. Opening or declining
## offers, docking, scans, objective readiness, pause, dialogue, visits and
## callback delivery are not pressure steps.
##
## Mutating entry points return {ok, changed, state, deltas, reason} over a pure
## copy: callers commit the returned state before showing anything derived from
## it. A missing field in an old save means uninitialized; malformed existing
## data is a recoverable load error, never a silent reset.

const Validation := preload("res://scripts/domain/ValidationResult.gd")

const STATE_VERSION := 1
const CATALOG_PATH := "res://data/content/local_pressure_tracks.json"
const CATALOG_VERSION := 1
const MAX_ACTIVE_TRACKS := 2
const MAX_RETAINED_TRACKS := 6
const MAX_LEVEL := 3
const STEPS_TO_ESCALATE := 2
const COOLDOWN_STEPS := 4
const RECENT_FAMILY_WINDOW := 4
const TERMINAL_STATES := ["completed", "abandoned", "failed", "expired"]


static func empty_state(seed_value: int) -> Dictionary:
	return {
		"version": STATE_VERSION,
		"activity_step": 0,
		"rng_state": absi(seed_value) & 0x7FFFFFFF,
		"tracks": [],
		"applied_outcome_ids": [],
		"recent_accepted_families": [],
		"kind_recency": {},
	}


static func load_catalog(path: String = CATALOG_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "missing_pressure_catalog"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "unreadable_pressure_catalog"}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {"ok": false, "reason": "invalid_pressure_catalog"}
	return parse_catalog(parsed)


static func parse_catalog(raw: Dictionary) -> Dictionary:
	if int(raw.get("version", 0)) != CATALOG_VERSION:
		return {"ok": false, "reason": "unsupported_pressure_catalog_version"}
	if not raw.get("kinds") is Array or (raw["kinds"] as Array).is_empty():
		return {"ok": false, "reason": "empty_pressure_catalog"}
	var kinds: Dictionary = {}
	for entry: Variant in raw["kinds"]:
		if not entry is Dictionary:
			return {"ok": false, "reason": "invalid_pressure_kind"}
		var kind: Dictionary = entry
		var id := str(kind.get("id", ""))
		if id.is_empty() or kinds.has(id):
			return {"ok": false, "reason": "invalid_pressure_kind_id"}
		if not kind.get("shape_ids_by_level") is Dictionary:
			return {"ok": false, "reason": "invalid_pressure_shape_levels"}
		for level in range(1, MAX_LEVEL + 1):
			if not kind["shape_ids_by_level"].get(str(level)) is Array:
				return {"ok": false, "reason": "invalid_pressure_shape_levels"}
		for list_field in ["completed_deltas", "terminal_deltas", "payout_modifiers"]:
			if not kind.get(list_field) is Array:
				return {"ok": false, "reason": "invalid_pressure_rule_list"}
		kinds[id] = kind.duplicate(true)
	return {"ok": true, "kinds": kinds, "order": kinds.keys()}


static func validate(value: Dictionary) -> ValidationResult:
	var result := Validation.new()
	if value.is_empty():
		return result # Additive: an old campaign has no pressure state yet.
	if int(value.get("version", 0)) != STATE_VERSION:
		result.add_error("unsupported_local_pressure_version", "Unsupported local pressure version.")
		return result
	for int_field in ["activity_step", "rng_state"]:
		if not _is_non_negative_int(value.get(int_field, -1)):
			result.add_error("invalid_local_pressure_counter", "Field '%s' must be a non-negative integer." % int_field, int_field)
	for array_field in ["tracks", "applied_outcome_ids", "recent_accepted_families"]:
		if not value.get(array_field) is Array:
			result.add_error("invalid_local_pressure_array", "Field '%s' must be an array." % array_field, array_field)
	if not value.get("kind_recency", {}) is Dictionary:
		result.add_error("invalid_local_pressure_recency", "Field 'kind_recency' must be an object.", "kind_recency")
	if not result.is_valid():
		return result
	for raw: Variant in value["applied_outcome_ids"]:
		if str(raw).is_empty():
			result.add_error("invalid_local_pressure_outcome_id", "Applied outcome IDs must be non-empty.")
	var ids: Dictionary = {}
	var active := 0
	if (value["tracks"] as Array).size() > MAX_RETAINED_TRACKS:
		result.add_error("too_many_local_pressure_tracks", "Retained more than %d pressure tracks." % MAX_RETAINED_TRACKS, "tracks")
	var active_kinds: Dictionary = {}
	for raw: Variant in value["tracks"]:
		if not raw is Dictionary:
			result.add_error("invalid_local_pressure_track", "Track entries must be objects.", "tracks")
			continue
		var track: Dictionary = raw
		for text_field in ["id", "kind", "system_id", "station_id", "faction_id", "desire_id", "cause_id"]:
			if str(track.get(text_field, "")).is_empty():
				result.add_error("invalid_local_pressure_track_binding", "Track field '%s' is empty." % text_field, "tracks")
		var id := str(track.get("id", ""))
		if ids.has(id):
			result.add_error("duplicate_local_pressure_track", "Duplicate pressure track ID.", "tracks")
		ids[id] = true
		var level := int(track.get("level", -1))
		if level < 0 or level > MAX_LEVEL:
			result.add_error("invalid_local_pressure_level", "Pressure level out of range.", "tracks")
		var untouched := int(track.get("untouched_steps", -1))
		if untouched < 0 or untouched >= STEPS_TO_ESCALATE:
			result.add_error("invalid_local_pressure_untouched", "Untouched step count out of range.", "tracks")
		for counter_field in ["cooldown_until_step", "revision", "last_active_step"]:
			if not _is_non_negative_int(track.get(counter_field, -1)):
				result.add_error("invalid_local_pressure_track_counter", "Track field '%s' must be a non-negative integer." % counter_field, "tracks")
		if is_active(track):
			active += 1
			if active_kinds.has(str(track.get("kind", ""))):
				result.add_error("duplicate_active_local_pressure_kind", "Two active tracks share a kind.", "tracks")
			active_kinds[str(track.get("kind", ""))] = true
	if active > MAX_ACTIVE_TRACKS:
		result.add_error("too_many_active_local_pressures", "More than %d active pressure tracks." % MAX_ACTIVE_TRACKS, "tracks")
	return result


static func is_active(track: Dictionary) -> bool:
	return int(track.get("level", 0)) > 0 and int(track.get("cooldown_until_step", 0)) == 0


## Fill pending slots from validated local causes. Called on normal system entry
## and board preparation, never from apply_outcome: eligibility needs a world.
## context = {post_tutorial_unlocked, campaign_seed, catalog, candidates:[...]}
## A candidate is {kind, system_id, station_id, faction_id, desire_id, cause_id}
## and must already have been checked against its own campaign/system by the
## caller. Nothing here derives a binding from a display name.
static func refresh_slots(saved: Dictionary, context: Dictionary) -> Dictionary:
	var opened := _open(saved, int(context.get("campaign_seed", 0)))
	if not bool(opened.get("ok", false)):
		return opened
	var state: Dictionary = opened["state"]
	if not bool(context.get("post_tutorial_unlocked", false)):
		# No active track may exist before the tutorial-completion latch.
		return _result(false, state, [], "tutorial_locked")
	var catalog: Dictionary = context.get("catalog", {})
	if not bool(catalog.get("ok", false)):
		return _result(false, state, [], str(catalog.get("reason", "missing_pressure_catalog")))
	var step := int(state["activity_step"])
	var deltas: Array = []
	var changed := false
	# A resolved track whose cooldown has expired releases its slot; the record
	# stays until pruning so its recency and last outcome remain inspectable.
	for track: Dictionary in state["tracks"]:
		if int(track.get("cooldown_until_step", 0)) > 0 and step >= int(track["cooldown_until_step"]):
			track["cooldown_until_step"] = 0
			track["resolved"] = true
			deltas.append({"kind": "cooldown_expired", "pressure_id": str(track["id"]), "track_kind": str(track["kind"])})
			changed = true
	var bound_causes: Dictionary = {}
	for track: Dictionary in state["tracks"]:
		bound_causes[str(track.get("cause_id", ""))] = true
	while _active_tracks(state).size() < MAX_ACTIVE_TRACKS:
		var chosen := _choose_candidate(state, context, catalog, bound_causes)
		if chosen.is_empty():
			break
		state["tracks"].append(chosen)
		bound_causes[str(chosen["cause_id"])] = true
		state["kind_recency"][str(chosen["kind"])] = step
		deltas.append({"kind": "track_activated", "pressure_id": str(chosen["id"]), "track_kind": str(chosen["kind"]),
			"system_id": str(chosen["system_id"]), "level": int(chosen["level"])})
		changed = true
	if _active_tracks(state).size() < MAX_ACTIVE_TRACKS:
		# "Two" is a maximum. A missing slot stays pending rather than inventing
		# a faction, copying a tutorial identity or publishing an unbacked job.
		deltas.append({"kind": "slot_pending", "active": _active_tracks(state).size()})
	if changed:
		_prune_tracks(state)
	return _result(changed, state, deltas, "" if changed else "no_eligible_cause")


static func _choose_candidate(state: Dictionary, context: Dictionary, catalog: Dictionary, bound_causes: Dictionary) -> Dictionary:
	var active_kinds: Dictionary = {}
	for track: Dictionary in _active_tracks(state):
		active_kinds[str(track["kind"])] = true
	var eligible: Array = []
	for raw: Variant in context.get("candidates", []):
		if not raw is Dictionary:
			continue
		var candidate: Dictionary = raw
		var kind := str(candidate.get("kind", ""))
		if not catalog["kinds"].has(kind) or active_kinds.has(kind):
			continue
		if not bool(catalog["kinds"][kind].get("runtime_eligible", false)):
			continue
		var incomplete := false
		for field in ["system_id", "station_id", "faction_id", "desire_id", "cause_id"]:
			if str(candidate.get(field, "")).is_empty():
				incomplete = true
		if incomplete or bound_causes.has(str(candidate.get("cause_id", ""))):
			continue # A fulfilled or retired cause is not a fresh reason.
		eligible.append(candidate)
	if eligible.is_empty():
		return {}
	# Least-recently-active eligible kind first; a never-active kind counts as
	# least recent. Stable candidate order breaks equal recency before the RNG.
	var recency: Dictionary = state["kind_recency"]
	eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := int(recency.get(str(a["kind"]), -1))
		var rb := int(recency.get(str(b["kind"]), -1))
		if ra != rb:
			return ra < rb
		return str(a["cause_id"]) < str(b["cause_id"]))
	var best := int(recency.get(str(eligible[0]["kind"]), -1))
	var tied: Array = []
	for candidate: Dictionary in eligible:
		if int(recency.get(str(candidate["kind"]), -1)) == best:
			tied.append(candidate)
	var picked: Dictionary = tied[_next_random(state, tied.size())]
	return {
		"id": _track_id(state, picked),
		"kind": str(picked["kind"]),
		"system_id": str(picked["system_id"]),
		"station_id": str(picked["station_id"]),
		"faction_id": str(picked["faction_id"]),
		"desire_id": str(picked["desire_id"]),
		"cause_id": str(picked["cause_id"]),
		"level": 1,
		"untouched_steps": 0,
		"cooldown_until_step": 0,
		"revision": 1,
		"last_outcome_id": "",
		"last_active_step": int(state["activity_step"]),
		"resolved": false,
	}


static func _track_id(state: Dictionary, candidate: Dictionary) -> String:
	var seed_text := "%s|%s|%s|%d" % [candidate["kind"], candidate["system_id"], candidate["cause_id"], int(state["activity_step"])]
	return "pressure.%s" % seed_text.sha256_text().substr(0, 24)


static func _active_tracks(state: Dictionary) -> Array:
	var result: Array = []
	for track: Dictionary in state["tracks"]:
		if is_active(track):
			result.append(track)
	return result


static func _prune_tracks(state: Dictionary) -> void:
	var tracks: Array = state["tracks"]
	if tracks.size() <= MAX_RETAINED_TRACKS:
		return
	var keep: Array = []
	var history: Array = []
	for track: Dictionary in tracks:
		if is_active(track) or int(track.get("cooldown_until_step", 0)) > 0:
			keep.append(track)
		else:
			history.append(track)
	history.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("last_active_step", 0)) > int(b.get("last_active_step", 0)))
	for track: Dictionary in history:
		if keep.size() >= MAX_RETAINED_TRACKS:
			break
		keep.append(track)
	# Recency survives pruning in kind_recency, so a dropped record cannot make
	# its kind look never-active to the next replacement draw.
	state["tracks"] = keep


## Commit one terminal outcome. The outcome is code-owned: no UI-supplied payout,
## verification flag or consequence sentence reaches this function.
static func apply_outcome(saved: Dictionary, outcome: Dictionary, context: Dictionary = {}) -> Dictionary:
	var opened := _open(saved, int(context.get("campaign_seed", 0)))
	if not bool(opened.get("ok", false)):
		return opened
	var state: Dictionary = opened["state"]
	var catalog: Dictionary = context.get("catalog", load_catalog())
	if not bool(catalog.get("ok", false)):
		return _result(false, state, [], str(catalog.get("reason", "missing_pressure_catalog")))
	var checked := _check_outcome(outcome)
	if not bool(checked.get("ok", false)):
		return _result(false, state, [], str(checked["reason"]), false)
	if bool(outcome.get("tutorial", false)):
		return _result(false, state, [], "tutorial_excluded")
	var outcome_id := str(outcome["id"])
	var mission_id := str(outcome["mission_id"])
	if outcome_id in state["applied_outcome_ids"]:
		return _result(false, state, [], "duplicate_outcome")
	for raw: Variant in state["applied_outcome_ids"]:
		# Different terminal suffixes must not bypass idempotency.
		if str(raw).begins_with("%s:" % mission_id):
			return _result(false, state, [], "conflicting_terminal_outcome", false)
	var bound := _bound_track(state, outcome)
	var deltas: Array = []
	var delta := 0
	if not bound.is_empty():
		delta = _delta_for(catalog["kinds"][str(bound["kind"])], outcome)
	var step := int(state["activity_step"]) + 1
	state["activity_step"] = step
	state["applied_outcome_ids"].append(outcome_id)
	for track: Dictionary in state["tracks"]:
		if not is_active(track):
			continue # Cooldown entries do not escalate.
		var before := int(track["level"])
		if not bound.is_empty() and str(track["id"]) == str(bound["id"]) and delta != 0:
			# Apply the bound delta first and do not also escalate from
			# inactivity on the same event; either direction resets the count.
			track["level"] = clampi(before + delta, 0, MAX_LEVEL)
			track["untouched_steps"] = 0
		else:
			var untouched := int(track["untouched_steps"]) + 1
			if untouched >= STEPS_TO_ESCALATE:
				track["level"] = mini(before + 1, MAX_LEVEL)
				untouched = 0
			track["untouched_steps"] = untouched
		track["last_active_step"] = step
		state["kind_recency"][str(track["kind"])] = step
		if not bound.is_empty() and str(track["id"]) == str(bound["id"]):
			track["last_outcome_id"] = outcome_id
		if int(track["level"]) != before:
			track["revision"] = int(track["revision"]) + 1
			deltas.append({"kind": "level_changed", "pressure_id": str(track["id"]), "track_kind": str(track["kind"]),
				"from": before, "to": int(track["level"]), "revision": int(track["revision"]), "outcome_id": outcome_id})
		if int(track["level"]) == 0:
			# Cooldown counts resolved jobs from here; the resolving event is
			# already counted in activity_step and is not counted again.
			track["cooldown_until_step"] = step + COOLDOWN_STEPS
			deltas.append({"kind": "track_resolved", "pressure_id": str(track["id"]), "track_kind": str(track["kind"]),
				"cooldown_until_step": step + COOLDOWN_STEPS})
	if bound.is_empty():
		deltas.append({"kind": "unbound_activity", "outcome_id": outcome_id, "step": step})
	_prune_tracks(state)
	return _result(true, state, deltas, "")


static func _check_outcome(outcome: Dictionary) -> Dictionary:
	if not outcome is Dictionary or outcome.is_empty():
		return {"ok": false, "reason": "invalid_outcome"}
	var mission_id := str(outcome.get("mission_id", ""))
	var terminal := str(outcome.get("terminal_state", ""))
	if mission_id.is_empty() or terminal not in TERMINAL_STATES:
		return {"ok": false, "reason": "invalid_terminal_outcome"}
	if str(outcome.get("id", "")) != "%s:%s" % [mission_id, terminal]:
		return {"ok": false, "reason": "invalid_outcome_id"}
	return {"ok": true}


static func _bound_track(state: Dictionary, outcome: Dictionary) -> Dictionary:
	var pressure_id := str(outcome.get("pressure_id", ""))
	if pressure_id.is_empty():
		return {}
	for track: Dictionary in state["tracks"]:
		if str(track["id"]) == pressure_id and is_active(track):
			return track
	return {} # A retired, resolved or unknown reference advances inactivity only.


static func _delta_for(kind: Dictionary, outcome: Dictionary) -> int:
	var completed := str(outcome.get("terminal_state", "")) == "completed"
	var rules: Array = kind.get("completed_deltas", []) if completed else kind.get("terminal_deltas", [])
	for raw: Variant in rules:
		if not raw is Dictionary:
			continue
		var rule: Dictionary = raw
		var matched := true
		if rule.has("outcome_tag") and str(rule["outcome_tag"]) != str(outcome.get("outcome_tag", "")):
			matched = false
		if rule.has("terminal_state") and str(rule["terminal_state"]) != str(outcome.get("terminal_state", "")):
			matched = false
		if rule.has("relief") and bool(rule["relief"]) != bool(outcome.get("relief", false)):
			matched = false
		if matched:
			return int(rule.get("delta", 0))
	return int(kind.get("completed_default_delta", 0)) if completed else int(kind.get("terminal_default_delta", 0))


## Constraints for at most one pressure card per active local track. Builders
## still validate every referenced shape, station, recipient and payment; a
## constraint is permission to consider work, never proof it can be published.
static func offer_constraints(saved: Dictionary, system_id: String, context: Dictionary = {}) -> Array:
	var state: Dictionary = saved.duplicate(true) if not saved.is_empty() else empty_state(0)
	if not validate(state).is_valid():
		return []
	var catalog: Dictionary = context.get("catalog", load_catalog())
	if not bool(catalog.get("ok", false)):
		return []
	var constraints: Array = []
	for track: Dictionary in _active_tracks(state):
		if str(track["system_id"]) != system_id:
			continue
		var kind: Dictionary = catalog["kinds"].get(str(track["kind"]), {})
		if kind.is_empty() or not bool(kind.get("runtime_eligible", false)):
			continue
		var level := int(track["level"])
		var shapes: Array = (kind["shape_ids_by_level"].get(str(level), []) as Array).duplicate()
		var modifier := _max_modifier(kind, level, "*")
		var branch_modifiers: Dictionary = {}
		for raw: Variant in kind.get("payout_modifiers", []):
			if raw is Dictionary and int((raw as Dictionary).get("level", 0)) == level:
				var branch := str((raw as Dictionary).get("branch_id", "*"))
				if branch != "*":
					branch_modifiers[branch] = _max_modifier(kind, level, branch)
		constraints.append({
			"pressure_id": str(track["id"]),
			"pressure_revision": int(track["revision"]),
			"kind": str(track["kind"]),
			"system_id": str(track["system_id"]),
			"station_id": str(track["station_id"]),
			"faction_id": str(track["faction_id"]),
			"desire_id": str(track["desire_id"]),
			"cause_id": str(track["cause_id"]),
			"level_at_offer": level,
			"preferred_shape_ids": shapes,
			"ore_relief": bool(kind.get("ore_relief", false)),
			"forced_forged": bool(kind.get("forced_forged", false)),
			"payout_numerator": int(modifier["numerator"]),
			"payout_denominator": int(modifier["denominator"]),
			"branch_modifiers": branch_modifiers,
			"public_label": str(kind.get("public_label", "")),
			"display_name": str(kind.get("display_name", "")),
			"escalates_after": STEPS_TO_ESCALATE - int(track["untouched_steps"]),
		})
	constraints.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["pressure_id"]) < str(b["pressure_id"]))
	return constraints


## Modifiers never stack: take the applicable maximum for the branch, comparing
## the branch rule, the wildcard rule and the unmodified 1/1 baseline.
static func _max_modifier(kind: Dictionary, level: int, branch_id: String) -> Dictionary:
	var best := {"numerator": 1, "denominator": 1}
	for raw: Variant in kind.get("payout_modifiers", []):
		if not raw is Dictionary:
			continue
		var rule: Dictionary = raw
		if int(rule.get("level", 0)) != level:
			continue
		var rule_branch := str(rule.get("branch_id", "*"))
		if rule_branch != "*" and rule_branch != branch_id:
			continue
		var num := int(rule.get("numerator", 1))
		var den := maxi(1, int(rule.get("denominator", 1)))
		if num * int(best["denominator"]) > int(best["numerator"]) * den:
			best = {"numerator": num, "denominator": den}
	return best


## Snapshot an integer payout at publication. Callers store the result; nothing
## reapplies a modifier at settlement.
static func snapshot_payout(base_credits: int, numerator: int, denominator: int) -> int:
	if denominator <= 0:
		return base_credits
	return int(floor(float(base_credits) * float(numerator) / float(denominator)))


## Pacing cap over the last four ACCEPTED discretionary families. Appending the
## candidate must not make more than two of that family in the resulting four.
static func may_offer_family(saved: Dictionary, family: String) -> bool:
	var recent: Array = saved.get("recent_accepted_families", []) if saved is Dictionary else []
	var retained: Array = recent.slice(maxi(0, recent.size() - (RECENT_FAMILY_WINDOW - 1)))
	var count := 1
	for raw: Variant in retained:
		if str(raw) == family:
			count += 1
	return count <= 2


static func record_accepted_family(saved: Dictionary, family: String) -> Dictionary:
	var opened := _open(saved, 0)
	if not bool(opened.get("ok", false)):
		return opened
	var state: Dictionary = opened["state"]
	if family.is_empty():
		return _result(false, state, [], "empty_family")
	var recent: Array = state["recent_accepted_families"]
	recent.append(family)
	while recent.size() > RECENT_FAMILY_WINDOW:
		recent.pop_front()
	return _result(true, state, [{"kind": "family_recorded", "family": family}], "")


static func _open(saved: Dictionary, seed_value: int) -> Dictionary:
	if saved == null or saved.is_empty():
		return {"ok": true, "changed": false, "state": empty_state(seed_value), "deltas": [], "reason": ""}
	var result := validate(saved)
	if not result.is_valid():
		# Malformed existing data is a recoverable load error, not a reset.
		return {"ok": false, "changed": false, "state": saved.duplicate(true), "deltas": [],
			"reason": str(result.errors[0].get("code", "invalid_local_pressures"))}
	var state := saved.duplicate(true)
	for field in ["tracks", "applied_outcome_ids", "recent_accepted_families"]:
		if not state.get(field) is Array:
			state[field] = []
	if not state.get("kind_recency", {}) is Dictionary:
		state["kind_recency"] = {}
	return {"ok": true, "changed": false, "state": state, "deltas": [], "reason": ""}


static func _result(changed: bool, state: Dictionary, deltas: Array, reason: String, ok: bool = true) -> Dictionary:
	return {"ok": ok, "changed": changed, "state": _persistable(state), "deltas": deltas, "reason": reason}


static func _next_random(state: Dictionary, bound: int) -> int:
	# Deterministic and JSON-safe so a save/load reproduces the same draw.
	var value := (int(state.get("rng_state", 0)) * 1103515245 + 12345) & 0x7FFFFFFF
	state["rng_state"] = value
	return (value / 65536) % maxi(1, bound)


static func _is_non_negative_int(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var numeric := float(value)
	return numeric >= 0.0 and is_equal_approx(numeric, floorf(numeric))


static func _persistable(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))
