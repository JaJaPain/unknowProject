extends SceneTree

const Ledger := preload("res://scripts/story/DesireProgressLedger.gd")
const Outcome := preload("res://scripts/domain/MissionOutcome.gd")

var failures: Array[String] = []

func _initialize():
	call_deferred("_run")

func _run():
	_test_open_and_progressed()
	_test_satisfaction_requires_a_predicate()
	_test_binding_and_idempotency()
	_test_validation()
	if failures.is_empty():
		print("[PASS] Desire progress: open/progressed, proven satisfaction, binding, idempotency, validation")
	else:
		for message in failures: push_error("[FAIL] " + message)
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _quest(tag: String = "verified", objective: String = "INVESTIGATE_SIGNAL") -> Dictionary:
	return {
		"runtime_id": "mission.%s.%d" % [tag, Time.get_ticks_usec()],
		"system_id": "system.local",
		"objective_type": objective,
		"narrative_metadata": {"cause_faction_id": "faction.a", "desire_id": "desire.a", "cause_id": "cause.a"},
		"investigation": {"shape_id": "mission_shape.survey_discrepancy", "branch_id": "certify_match",
			"outcome_tag": tag, "scanned_site_ids": ["site.1", "site.2"], "consumable_spent": false},
	}

func _outcome(tag: String = "verified", terminal: String = "completed") -> Dictionary:
	return Outcome.build(_quest(tag), terminal, 400, 10, "campaign.test")["outcome"]

func _entry(state: Dictionary) -> Dictionary:
	var key := Ledger.key_for("system.local", "faction.a", "desire.a")
	return state.get("entries", {}).get(key, {})

func _test_open_and_progressed() -> void:
	# A supported effect advances the interest but does not close it.
	var applied := Ledger.apply_outcome({}, _outcome("verified"))
	_expect(applied.get("ok", false) and applied.get("changed", false), "A verified survey did not project onto its desire.")
	var entry := _entry(applied["state"])
	_expect(str(entry.get("state", "")) == "progressed", "A supported effect did not advance the desire to progressed.")
	_expect(str(entry.get("satisfied_by_predicate", "")).is_empty(), "An unproven desire named a satisfying predicate.")
	_expect((entry.get("records", []) as Array).size() == 1, "The desire did not retain its effect record.")
	_expect(str(entry["records"][0]["kind"]) == Outcome.EFFECT_VERIFIED_SURVEY, "The record lost its effect kind.")
	_expect((entry.get("source_outcome_ids", []) as Array).size() == 1, "The desire did not retain its source outcome ID.")
	# A wrong answer or an abandoned job never permanently fails the desire.
	for bad in [_outcome("mistaken"), _outcome("unverified")]:
		var neutral := Ledger.apply_outcome({}, bad)
		_expect(str(_entry(neutral["state"]).get("state", "")) == "open", "A wrong or unverified answer moved the desire off open.")
	var dropped := Ledger.apply_outcome({}, _outcome("", "abandoned"))
	_expect(str(_entry(dropped["state"]).get("state", "")) != "failed", "An abandoned job permanently failed an entire desire.")

func _test_satisfaction_requires_a_predicate() -> void:
	# Without a bound predicate the interest cannot close, however good the result.
	var unproven := Ledger.apply_outcome({}, _outcome("verified"), {"satisfying_effect_ids": []})
	_expect(not Ledger.is_satisfied(unproven["state"], "system.local", "faction.a", "desire.a"),
		"A desire closed without a typed bound predicate.")
	# A preserved recorder does not automatically clear a faction's name: only the
	# predicate a resolution plan actually bound may close it.
	var wrong_predicate := Ledger.apply_outcome({}, _outcome("preserved"),
		{"satisfying_effect_ids": [Outcome.EFFECT_VERIFIED_SURVEY]})
	_expect(not Ledger.is_satisfied(wrong_predicate["state"], "system.local", "faction.a", "desire.a"),
		"An unrelated proven predicate closed a desire it does not establish.")
	_expect(str(_entry(wrong_predicate["state"]).get("state", "")) == "progressed",
		"A preserved recorder should still progress its own desire.")
	# With the exact predicate bound, the interest closes and names its proof.
	var proven := Ledger.apply_outcome({}, _outcome("preserved"),
		{"satisfying_effect_ids": [Outcome.EFFECT_RECORDER_PRESERVED]})
	_expect(Ledger.is_satisfied(proven["state"], "system.local", "faction.a", "desire.a"),
		"A bound predicate did not close its desire.")
	var entry := _entry(proven["state"])
	_expect(str(entry.get("satisfied_by_predicate", "")) == "recorder_delivered_to_verified_owner",
		"A satisfied desire did not name the predicate that proved it.")
	# A fulfilled cause is retired and must not be reposted under a new ID.
	_expect("cause.a" in Ledger.retired_cause_ids(proven["state"]), "A fulfilled cause was not retired.")
	_expect(Ledger.retired_cause_ids(unproven["state"]).is_empty(), "An unsatisfied desire retired its cause.")

func _test_binding_and_idempotency() -> void:
	# An effect may only advance the desire it was actually bound to.
	var foreign := _outcome("verified")
	(foreign["effects"][0] as Dictionary)["desire_id"] = "desire.other"
	var ignored := Ledger.apply_outcome({}, foreign)
	_expect(str(_entry(ignored["state"]).get("state", "")) == "open", "An effect advanced a desire it was not bound to.")
	# An unbound mission has no desire to project onto and fails closed quietly.
	var unbound := _outcome("verified")
	unbound["desire_id"] = ""
	var skipped := Ledger.apply_outcome({}, unbound)
	_expect(skipped.get("ok", false) and not skipped.get("changed", true), "An unbound outcome was not skipped quietly.")
	_expect(str(skipped.get("reason", "")) == "unbound_desire", "An unbound outcome reported '%s'." % skipped.get("reason", ""))
	# The same outcome cannot be counted twice.
	var outcome := _outcome("verified")
	var once := Ledger.apply_outcome({}, outcome)
	var twice := Ledger.apply_outcome(once["state"], outcome)
	_expect(not twice.get("changed", true), "A duplicate outcome was reprojected.")
	_expect(str(twice.get("reason", "")) == "duplicate_outcome", "Duplicate projection reported '%s'." % twice.get("reason", ""))
	_expect((_entry(once["state"]).get("records", []) as Array).size() == 1, "A duplicate outcome added a second record.")
	# A JSON roundtrip preserves the projection exactly.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(once["state"]))
	_expect(Ledger.validate(saved).is_valid(), "A JSON roundtrip invalidated desire progress.")
	_expect(JSON.stringify(saved) == JSON.stringify(once["state"]), "A JSON roundtrip changed desire progress.")

func _test_validation() -> void:
	_expect(Ledger.validate({}).is_valid(), "An old campaign without desire progress must validate as uninitialized.")
	_expect(not Ledger.validate({"version": 9, "entries": {}}).is_valid(), "An unsupported version was accepted.")
	var applied := Ledger.apply_outcome({}, _outcome("verified"))
	# A satisfied state with no named predicate is unproven and must be rejected.
	var unproven: Dictionary = applied["state"].duplicate(true)
	var key := Ledger.key_for("system.local", "faction.a", "desire.a")
	(unproven["entries"][key] as Dictionary)["state"] = "satisfied"
	_expect(not Ledger.validate(unproven).is_valid(), "A satisfied desire with no proving predicate passed validation.")
	# A record citing an unimplemented effect is rejected.
	var invented: Dictionary = applied["state"].duplicate(true)
	(invented["entries"][key] as Dictionary)["records"] = [{"kind": "legal_appeal_completed", "effect_id": "x", "outcome_id": "y"}]
	_expect(not Ledger.validate(invented).is_valid(), "A record citing an unimplemented effect passed validation.")
	# A key that disagrees with its own binding is rejected.
	var mismatched: Dictionary = applied["state"].duplicate(true)
	(mismatched["entries"][key] as Dictionary)["desire_id"] = "desire.renamed"
	_expect(not Ledger.validate(mismatched).is_valid(), "An entry key disagreeing with its binding passed validation.")
	# Malformed saved data is a recoverable load error, not a silent reset.
	var refused := Ledger.apply_outcome({"version": 1, "entries": "not-an-object"}, _outcome("verified"))
	_expect(not refused.get("ok", true), "Malformed desire progress was silently accepted.")
	_expect(refused["state"].get("entries") == "not-an-object", "A malformed load reset saved desire progress.")
