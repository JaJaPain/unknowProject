extends SceneTree

const Outcome := preload("res://scripts/domain/MissionOutcome.gd")

var failures: Array[String] = []

func _initialize():
	call_deferred("_run")

func _run():
	_test_identity()
	_test_code_owned_fields()
	_test_effects()
	if failures.is_empty():
		print("[PASS] Mission outcome: identity, code-owned fields, closed effect set")
	else:
		for message in failures: push_error("[FAIL] " + message)
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _quest(overrides: Dictionary = {}) -> Dictionary:
	var quest := {
		"runtime_id": "mission.runtime.1",
		"system_id": "system.local",
		"objective_type": "INVESTIGATE_SIGNAL",
		"faction": "neutral",
		"title": "Survey readings",
		"narrative_metadata": {"cause_faction_id": "faction.a", "desire_id": "desire.a", "cause_id": "cause.a"},
		"investigation": {"shape_id": "mission_shape.survey_discrepancy", "branch_id": "certify_match",
			"outcome_tag": "verified", "scanned_site_ids": ["site.1", "site.2"], "consumable_spent": false},
	}
	for key in overrides: quest[key] = overrides[key]
	return quest

func _test_identity() -> void:
	var built := Outcome.build(_quest(), "completed", 400, 120, "campaign.test")
	_expect(built.get("ok", false), "A valid completion failed to build: %s" % built.get("reason", ""))
	if not built.get("ok", false): return
	var outcome: Dictionary = built["outcome"]
	_expect(str(outcome["id"]) == "mission.runtime.1:completed", "Outcome ID is not '<runtime_mission_id>:<terminal_state>'.")
	_expect(str(outcome["campaign_id"]) == "campaign.test", "Outcome lost its campaign reference.")
	_expect(str(outcome["system_id"]) == "system.local", "Outcome lost its system reference.")
	_expect(str(outcome["desire_id"]) == "desire.a" and str(outcome["faction_id"]) == "faction.a",
		"Outcome did not read its causal metadata; it must not derive a requester from quest.faction.")
	_expect(Outcome.validate(outcome).is_valid(), "A built outcome failed its own validation.")
	# A missing runtime ID or unsupported terminal state fails closed.
	_expect(not Outcome.build(_quest({"runtime_id": ""}), "completed", 0, 0).get("ok", true), "A mission without a runtime ID built an outcome.")
	_expect(not Outcome.build(_quest(), "declined", 0, 0).get("ok", true), "'declined' is not a terminal state and must not build.")
	_expect(not Outcome.build({}, "completed", 0, 0).get("ok", true), "An empty mission built an outcome.")

func _test_code_owned_fields() -> void:
	# Branch, tag, payout and consumed item exist only once the player resolved it.
	for terminal in ["abandoned", "failed", "expired"]:
		var built := Outcome.build(_quest(), terminal, 999, 10)
		_expect(built.get("ok", false), "A %s outcome failed to build." % terminal)
		if not built.get("ok", false): continue
		var outcome: Dictionary = built["outcome"]
		_expect(int(outcome["credits_paid"]) == 0, "%s paid credits." % terminal)
		_expect(str(outcome["branch_id"]).is_empty() and str(outcome["outcome_tag"]).is_empty(),
			"%s carried a resolution branch it never reached." % terminal)
		_expect(not bool(outcome["verified"]), "%s claimed verification." % terminal)
		_expect((outcome["effects"] as Array).is_empty(), "%s committed an effect." % terminal)
	# Verification means both sites were actually scanned, not what a panel says.
	var one_site := _quest()
	one_site["investigation"]["scanned_site_ids"] = ["site.1"]
	one_site["investigation"]["verified"] = true
	var partial := Outcome.build(one_site, "completed", 200, 10)
	_expect(not bool(partial["outcome"]["verified"]), "A UI-supplied verified flag overrode the actual scan evidence.")
	# A consumed item is recorded only when the capability actually spent it.
	var spent := _quest()
	spent["investigation"]["consumable_id"] = "item.scanner_kit"
	_expect(str(Outcome.build(spent, "completed", 400, 10)["outcome"]["consumable_id"]).is_empty(),
		"An unspent consumable was recorded as consumed.")
	spent["investigation"]["consumable_spent"] = true
	_expect(str(Outcome.build(spent, "completed", 400, 10)["outcome"]["consumable_id"]) == "item.scanner_kit",
		"An actually spent consumable was not recorded.")

func _test_effects() -> void:
	# Correct certification with both sites scanned is the only survey effect.
	var verified: Array = Outcome.build(_quest(), "completed", 400, 10)["outcome"]["effects"]
	_expect(verified.size() == 1 and str(verified[0]["kind"]) == Outcome.EFFECT_VERIFIED_SURVEY,
		"A verified survey did not record its evidence effect.")
	_expect(str(verified[0]["source_outcome_id"]) == "mission.runtime.1:completed", "An effect did not cite its source outcome.")
	_expect(str(verified[0]["desire_id"]) == "desire.a", "An effect lost the desire it was bound to.")
	# An incorrect certification establishes nothing.
	var mistaken := _quest()
	mistaken["investigation"]["outcome_tag"] = "mistaken"
	_expect((Outcome.build(mistaken, "completed", 100, 10)["outcome"]["effects"] as Array).is_empty(),
		"An incorrect certification committed an effect.")
	# A report establishes nothing either, even with both sites scanned.
	var reported := _quest()
	reported["investigation"]["outcome_tag"] = "unverified"
	_expect((Outcome.build(reported, "completed", 200, 10)["outcome"]["effects"] as Array).is_empty(),
		"An unverified report committed an effect.")
	# Preserving a recorder records preservation and nothing about ownership.
	var preserved := _quest()
	preserved["investigation"]["outcome_tag"] = "preserved"
	var effects: Array = Outcome.build(preserved, "completed", 500, 10)["outcome"]["effects"]
	_expect(effects.size() == 1 and str(effects[0]["kind"]) == Outcome.EFFECT_RECORDER_PRESERVED,
		"Preserve did not record its own effect.")
	for effect: Dictionary in effects:
		_expect(str(effect["kind"]) in Outcome.SUPPORTED_EFFECTS, "An effect escaped the closed supported set.")
	# Raw ore delivery is a delivery, never an assay.
	var ore := _quest({"objective_type": "DELIVER_ORE", "pressure_relief": true, "investigation": {}})
	var ore_effects: Array = Outcome.build(ore, "completed", 300, 10)["outcome"]["effects"]
	_expect(ore_effects.size() == 1 and str(ore_effects[0]["kind"]) == Outcome.EFFECT_MARKED_ORE_DELIVERED,
		"A marked ore delivery did not record delivery.")
	for effect: Dictionary in ore_effects:
		_expect(str(effect["kind"]) != "clean_ore_assay", "Raw ore delivery asserted an assay.")
	# An unmarked ore delivery is ordinary work with no pressure effect.
	var unmarked := _quest({"objective_type": "DELIVER_ORE", "investigation": {}})
	_expect((Outcome.build(unmarked, "completed", 300, 10)["outcome"]["effects"] as Array).is_empty(),
		"An unmarked delivery committed a relief effect.")
	# Validation rejects an invented effect kind outright.
	var forged: Dictionary = Outcome.build(_quest(), "completed", 400, 10)["outcome"]
	forged["effects"] = [{"id": "effect.x", "kind": "route_reopened", "source_outcome_id": str(forged["id"])}]
	_expect(not Outcome.validate(forged).is_valid(), "An unimplemented effect kind passed validation.")
