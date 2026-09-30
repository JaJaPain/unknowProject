extends SceneTree

## FixedCastRoleGuard and its use in the campaign bible and chapter plan
## validators. Fixtures are the "Toxic Debt" campaign (Abe, 2026-09-28) that
## made Kaelen the player's creditor and harasser.

var _failures := 0


func _initialize() -> void:
	var guard = load("res://scripts/story/FixedCastRoleGuard.gd")
	# Sentences.
	_expect(not guard.scan(["Player is broke, caught in a Reaver ambush, and owes Kaelen a favor she won't let go unpaid."]).is_empty(),
		"The Toxic Debt opening was not caught.")
	_expect(not guard.scan(["Repaying the debt is the only way to avoid her continued harassment."], true).is_empty(),
		"A hostile stake in a beat bound to Kaelen was not caught.")
	_expect(guard.scan(["Repaying the debt is the only way to avoid the collector's continued harassment."], false).is_empty(),
		"A debt owed to an invented NPC was rejected.")
	_expect(guard.scan(["Kaelen arranges a job to recover the ore.", "N.O.V.A. audits the air filters hourly."]).is_empty(),
		"Ordinary fixed-cast lines were rejected.")
	_expect(guard.kaelen_third_person("Shiny, Aurelia's Ryn has a job. You owe Kaelen a favor."),
		"Kaelen speaking of herself in the third person was not caught.")
	_expect(not guard.kaelen_third_person("Shiny, Aurelia's Ryn has a job. Don't make me look bad."),
		"A first-person Kaelen line was flagged.")

	# Campaign bible validator.
	var director = load("res://scripts/ai/NarrativeDirector.gd")
	var bible := {"campaign_logline": "A pilot owes a favor, and the Reaver wants it back.",
		"opening_situation": "Player is broke and owes Kaelen a favor she won't let go unpaid.",
		"core_pressure": "A ticking debt clock forces the player to take risky jobs.",
		"kaelen_angle": "She betrayed a crew long ago."}
	var result = director._validate_campaign_bible_shape(bible)
	_expect(_has_code(result, "fixed_cast_recast", "opening_situation"), "The bible validator let Kaelen be the creditor.")
	_expect(not _has_code(result, "fixed_cast_recast", "kaelen_angle"), "The bible validator checked a director-only field.")
	_expect(not _has_code(result, "fixed_cast_recast", "core_pressure"), "A debt clock with no fixed cast was rejected.")

	# Chapter plan validator.
	var chapter = load("res://scripts/ai/ChapterNarrativeDirector.gd")
	var bad := {"beats": [{"beat_id": "kaelen_introduces_debt", "eligible_entity_ids": ["npc.kaelen"],
		"stake": "Repaying the debt is the only way to avoid Kaelen's continued harassment.",
		"decline_consequence": "Kaelen will continue to demand payment through other means, including threats."}]}
	var checked = load("res://scripts/domain/ValidationResult.gd").new()
	chapter._check_fixed_cast_roles(bad, checked)
	_expect(not checked.is_valid(), "The chapter validator let a beat make Kaelen the harasser.")
	var good := {"beats": [{"beat_id": "kaelen_offers_work", "eligible_entity_ids": ["npc.kaelen"],
		"stake": "The job pays enough to cover the repairs.", "decline_consequence": "The work goes to another pilot."}]}
	var clean = load("res://scripts/domain/ValidationResult.gd").new()
	chapter._check_fixed_cast_roles(good, clean)
	_expect(clean.is_valid(), "The chapter validator rejected an ordinary Kaelen beat.")

	if _failures == 0:
		print("[PASS] Fixed-cast role guard")
	quit(1 if _failures > 0 else 0)


func _has_code(result, code: String, field: String) -> bool:
	for issue in result.errors:
		if str(issue.get("code", "")) == code and str(issue.get("path", "")) == field:
			return true
	return false


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("[FAIL] " + message)
