extends SceneTree

# The projector decides what dialogue is ALLOWED to know about a typed outcome.
# The expensive failure here is not a crash -- it is an NPC casually mentioning
# something the player was never told, which spoils a story beat in a throwaway
# bark. These pin that boundary.

const ProjectorType := preload("res://scripts/story/OutcomeReactionProjector.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var smoke: Dictionary = ProjectorType.project({"outcome_tag": "verified"})
	if smoke.is_empty() or not smoke.has("ok"):
		push_error("[FAIL] OutcomeReactionProjector did not compile or project.")
		quit(1)
		return
	_test_a_mistaken_certification_never_reaches_dialogue()
	_test_public_outcomes_project_facts()
	_test_unknown_outcomes_are_refused_not_guessed()
	_test_facts_stay_few()
	_test_payout_is_a_band_never_a_figure()
	_test_refusal_is_not_an_error()
	if _failures.is_empty():
		print("[PASS] Outcome reaction projector tests")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _test_a_mistaken_certification_never_reaches_dialogue() -> void:
	# THE important one. A mistaken certification is one the player was PAID for
	# and never corrected on -- they may not know they were wrong. An NPC
	# referencing it would tell them, by accident, in a bark.
	var result: Dictionary = ProjectorType.project({
		"outcome_tag": "mistaken",
		"owner_id": "mission_12",
		"system_name": "Frontier",
		"payout_credits": 250,
	})
	_expect(not bool(result["ok"]), "A mistaken certification must not project.")
	_expect(
		str(result["reason"]).begins_with("private_outcome"),
		"It must be refused as PRIVATE specifically, got '%s'" % str(result["reason"])
	)
	_expect((result["facts"] as Array).is_empty(), "A private outcome must leak no facts.")
	_expect((result["consequence"] as Dictionary).is_empty(), "A private outcome must leak no consequence.")
	_expect(not ProjectorType.is_public("mistaken"), "is_public must agree that it is private.")
	# And nothing about it may appear in any projected text anywhere.
	for key in ProjectorType.OUTCOME_PROJECTIONS:
		var p: Dictionary = ProjectorType.OUTCOME_PROJECTIONS[key]
		if not bool(p.get("public", false)):
			_expect(
				str(p.get("summary", "")).is_empty(),
				"A private outcome must carry no summary text at all ('%s')" % key
			)


func _test_public_outcomes_project_facts() -> void:
	for tag in ["verified", "unverified", "preserved", "liquidated", "copied", "extracted"]:
		var result: Dictionary = ProjectorType.project({
			"outcome_tag": tag, "owner_id": "m1", "system_name": "Greywake", "payout_credits": 150,
		})
		_expect(bool(result["ok"]), "'%s' should project, got '%s'" % [tag, str(result["reason"])])
		_expect(
			not (result["facts"] as Array).is_empty(),
			"'%s' should produce at least one fact." % tag
		)
		var consequence: Dictionary = result["consequence"]
		_expect(
			str(consequence.get("outcome_tag", "")) == tag,
			"The consequence must carry the tag it came from."
		)
		_expect(
			str(consequence.get("certainty", "")) in ["known", "rumoured"],
			"A public consequence needs a certainty a speaker can act on, got '%s'"
				% str(consequence.get("certainty", ""))
		)


func _test_unknown_outcomes_are_refused_not_guessed() -> void:
	# A new outcome type must be classified by a person. Guessing public/private
	# is how story leaks.
	var result: Dictionary = ProjectorType.project({"outcome_tag": "scuttled"})
	_expect(not bool(result["ok"]), "An unclassified outcome must not project.")
	_expect(
		str(result["reason"]).begins_with("unclassified_outcome"),
		"It must say it is unclassified, so someone classifies it, got '%s'" % str(result["reason"])
	)
	_expect(not ProjectorType.is_public("scuttled"), "An unknown tag must not default to public.")


func _test_facts_stay_few() -> void:
	# Narrowing is the whole point of the phase: the old builder copied every
	# tension, hook and history entry into each bark.
	var result: Dictionary = ProjectorType.project({
		"outcome_tag": "liquidated", "owner_id": "m1",
		"system_name": "Greywake", "payout_credits": 900,
	})
	_expect(
		(result["facts"] as Array).size() <= ProjectorType.MAX_FACTS,
		"Facts must stay within the cap, got %d" % (result["facts"] as Array).size()
	)


func _test_payout_is_a_band_never_a_figure() -> void:
	# An NPC quoting the player's exact credits reads as omniscient rather than
	# informed, and invites a model to do arithmetic it cannot check.
	var result: Dictionary = ProjectorType.project({
		"outcome_tag": "verified", "owner_id": "m1", "payout_credits": 1234,
	})
	for fact in result["facts"]:
		_expect(
			not str((fact as Dictionary).get("text", "")).contains("1234"),
			"No projected fact may contain the exact payout figure."
		)
	_expect(ProjectorType.payout_band(50) == "badly", "A small payout should read as badly paid.")
	_expect(ProjectorType.payout_band(900) == "well", "A large payout should read as well paid.")
	_expect(ProjectorType.payout_band(0).is_empty(), "No payout means nothing to say about pay.")


func _test_refusal_is_not_an_error() -> void:
	# A refusal is the NORMAL case for private outcomes. The caller must be able
	# to proceed with no facts rather than substituting something.
	for outcome in [{}, {"outcome_tag": ""}, {"outcome_tag": "mistaken"}]:
		var result: Dictionary = ProjectorType.project(outcome)
		_expect(result.has("facts") and result.has("consequence"),
			"A refusal must still return the full shape so callers need no special case.")
		_expect((result["facts"] as Array).is_empty(), "A refusal must carry no facts.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
