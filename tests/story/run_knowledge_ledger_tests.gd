extends SceneTree

const KnowledgeLedgerType := preload("res://scripts/story/KnowledgeLedger.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_monotonic_fact_promotion_records_provenance()
	_test_fact_demotion_is_ignored()
	_test_contradiction_is_explicit_terminal_state()
	_test_invalid_fact_promotions_fail()

	if _failures.is_empty():
		print("[PASS] Knowledge ledger tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_monotonic_fact_promotion_records_provenance() -> void:
	var state := {"knowledge_revision": 0, "knowledge_states": {}}
	var ledger := KnowledgeLedgerType.new(state)
	_expect(
		ledger.state_for("fact.convoy_loss.rumor") == "unknown",
		"Unknown facts should default to unknown."
	)
	var rumored: Dictionary = ledger.promote(
		"fact.convoy_loss.rumor",
		"rumored",
		"lounge_rumor",
		76,
		"hearsay"
	)
	_expect(
		bool(rumored.get("ok", false))
			and bool(rumored.get("changed", false))
			and ledger.state_for("fact.convoy_loss.rumor") == "rumored",
		"Fact did not promote from unknown to rumored."
	)
	var known: Dictionary = ledger.promote(
		"fact.convoy_loss.rumor",
		"known",
		"npc.gen.contact_1",
		84,
		"direct"
	)
	var record: Dictionary = (
		state.get("knowledge_states", {}) as Dictionary
	).get("fact.convoy_loss.rumor", {})
	_expect(
		bool(known.get("ok", false))
			and int(state.get("knowledge_revision", 0)) == 2,
		"Knowledge revision did not increment on real promotions."
	)
	_expect(
		record.get("first_source", "") == "lounge_rumor"
			and record.get("source", "") == "npc.gen.contact_1"
			and int(record.get("learned_at_minute", -1)) == 76
			and int(record.get("updated_at_minute", -1)) == 84
			and record.get("confidence", "") == "direct",
		"Knowledge promotion did not preserve provenance correctly."
	)
	_expect(
		ledger.can_reference("fact.convoy_loss.rumor", "known")
			and not ledger.can_reference("fact.missing.secret", "rumored"),
		"Knowledge reference gating returned the wrong result."
	)


func _test_fact_demotion_is_ignored() -> void:
	var state := {"knowledge_revision": 0, "knowledge_states": {}}
	var ledger := KnowledgeLedgerType.new(state)
	ledger.promote("fact.convoy_shortage.visible", "confirmed", "mission", 90)
	var before_revision := int(state.get("knowledge_revision", 0))
	var demoted: Dictionary = ledger.promote(
		"fact.convoy_shortage.visible",
		"rumored",
		"stale_rumor",
		91
	)
	_expect(
		bool(demoted.get("ok", false))
			and not bool(demoted.get("changed", true))
			and ledger.state_for("fact.convoy_shortage.visible") == "confirmed"
			and int(state.get("knowledge_revision", 0)) == before_revision,
		"Knowledge ledger allowed a non-monotonic demotion."
	)


func _test_contradiction_is_explicit_terminal_state() -> void:
	var state := {"knowledge_revision": 0, "knowledge_states": {}}
	var ledger := KnowledgeLedgerType.new(state)
	ledger.promote("fact.convoy_loss.rumor", "known", "briefing", 10)
	var contradicted: Dictionary = ledger.promote(
		"fact.convoy_loss.rumor",
		"contradicted",
		"black_box_recording",
		120,
		"direct"
	)
	var record: Dictionary = (
		state.get("knowledge_states", {}) as Dictionary
	).get("fact.convoy_loss.rumor", {})
	_expect(
		bool(contradicted.get("changed", false))
			and ledger.state_for("fact.convoy_loss.rumor") == "contradicted"
			and record.get("previous_state", "") == "known",
		"Explicit contradiction did not record terminal contradicted state."
	)
	var repromoted: Dictionary = ledger.promote(
		"fact.convoy_loss.rumor",
		"confirmed",
		"late_claim",
		130
	)
	_expect(
		not bool(repromoted.get("changed", true))
			and ledger.state_for("fact.convoy_loss.rumor") == "contradicted",
		"Contradicted facts should not silently promote afterward."
	)


func _test_invalid_fact_promotions_fail() -> void:
	var ledger := KnowledgeLedgerType.new({"knowledge_revision": 0})
	_expect(
		not bool(ledger.promote("bad fact", "known", "test").get("ok", true)),
		"Knowledge ledger accepted an invalid fact ID."
	)
	_expect(
		not bool(
			ledger.promote("fact.valid.example", "revealed", "test").get(
				"ok",
				true
			)
		),
		"Knowledge ledger accepted an invalid state."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
