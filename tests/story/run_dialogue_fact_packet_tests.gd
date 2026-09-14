extends SceneTree

## Proves the packet's question-aware selection, the property the integration
## review asked for: the fact that answers the player must not be truncated away
## because unrelated facts were inserted before it.

const PacketType := preload("res://scripts/story/DialogueFactPacket.gd")
const ContractType := preload("res://scripts/domain/QuestCausalContract.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_answering_fact_survives_the_cap()
	_test_question_ranking_is_stable_and_deterministic()
	_test_no_question_keeps_purpose_order()
	_test_private_facts_never_selected()
	_test_fingerprint_tracks_facts_not_nudges()

	if _failures.is_empty():
		print("[PASS] Dialogue fact packet tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


## A contract whose answering fact is deliberately LAST in every purpose list and
## beyond MAX_FACTS, so purpose ordering alone would drop it.
func _buried_contract() -> Dictionary:
	var facts := {}
	var problem_ids: Array[String] = []
	for index in range(PacketType.MAX_FACTS + 2):
		var fact_id := "fact.filler_%d" % index
		facts[fact_id] = {
			"text": "Unrelated background detail number %d about berth scheduling." % index,
			"visibility": "public",
			"kind": "problem",
		}
		problem_ids.append(fact_id)
	facts["fact.the_answer"] = {
		"text": "The impound order was signed by the harbourmaster and only she can lift it.",
		"visibility": "public",
		"kind": "problem",
	}
	facts["fact.secret"] = {
		"text": "They forged the original bill of lading themselves.",
		"visibility": "private",
		"kind": "motive",
	}
	problem_ids.append("fact.the_answer")
	return ContractType.normalize({
		"id": "quest.buried",
		"revision": 1,
		"requester_id": "faction.generated.x.f0",
		"desire_id": "desire.x.f0",
		"facts": facts,
		"problem_fact_ids": problem_ids,
		"public_fact_ids": problem_ids,
		"private_fact_ids": ["fact.secret"],
		"why_this_action_fact_ids": ["fact.filler_0"],
		"objective_binding": {"type": "DELIVERY_COURIER", "reward_credits": 100},
	})


func _test_answering_fact_survives_the_cap() -> void:
	var contract := _buried_contract()
	var speaker := {"name": "Halda Vresk", "role": "clerk"}

	# Without a question, the buried fact is correctly outside the cap.
	var generic := PacketType.build(contract, speaker, "answer", {})
	_expect(
		"fact.the_answer" not in (generic.get("fact_ids", []) as Array),
		"Test setup is wrong: the fact was not actually buried."
	)

	# With the question, it must be selected -- and lead.
	var targeted := PacketType.build(contract, speaker, "answer", {
		"question_text": "Who signed the impound order?",
	})
	var ids: Array = targeted.get("fact_ids", [])
	_expect(
		"fact.the_answer" in ids,
		"The fact that answers the question was truncated away: %s" % str(ids)
	)
	_expect(
		ids.size() > 0 and str(ids[0]) == "fact.the_answer",
		"The answering fact was selected but not ranked first: %s" % str(ids)
	)
	_expect(
		ids.size() <= PacketType.MAX_FACTS,
		"Question-aware selection broke the fact cap."
	)


func _test_question_ranking_is_stable_and_deterministic() -> void:
	var contract := _buried_contract()
	var speaker := {"name": "Halda Vresk", "role": "clerk"}
	var options := {"question_text": "Who signed the impound order?"}
	var first := PacketType.build(contract, speaker, "answer", options)
	var second := PacketType.build(contract, speaker, "answer", options)
	_expect(
		JSON.stringify(first) == JSON.stringify(second),
		"The same inputs produced two different packets; writer and validator could diverge."
	)
	# Equal-scoring facts must keep their original relative order, or the
	# fingerprint would wobble between dispatch and validation.
	var tie := PacketType.build(contract, speaker, "answer", {
		"question_text": "Tell me about the berth scheduling background.",
	})
	var tie_again := PacketType.build(contract, speaker, "answer", {
		"question_text": "Tell me about the berth scheduling background.",
	})
	_expect(
		str(tie.get("fact_ids", [])) == str(tie_again.get("fact_ids", [])),
		"Tied facts did not sort stably."
	)


func _test_no_question_keeps_purpose_order() -> void:
	var contract := _buried_contract()
	var speaker := {"name": "Halda Vresk", "role": "clerk"}
	var opening := PacketType.build(contract, speaker, "opening", {})
	var ids: Array = opening.get("fact_ids", [])
	_expect(
		ids.size() > 0 and str(ids[0]) == "fact.filler_0",
		"An opening with no question stopped using purpose order: %s" % str(ids)
	)


func _test_private_facts_never_selected() -> void:
	var contract := _buried_contract()
	var speaker := {"name": "Halda Vresk", "role": "clerk"}
	# Even when the question is ABOUT the secret, it must not be disclosed.
	var packet := PacketType.build(contract, speaker, "answer", {
		"question_text": "Did they forge the original bill of lading themselves?",
	})
	_expect(
		"fact.secret" not in (packet.get("fact_ids", []) as Array),
		"A private fact was selected because the question asked about it."
	)
	_expect(
		not PacketType.prompt_block(packet).to_lower().contains("forged"),
		"The private fact's text reached the rendered prompt."
	)


## The fingerprint must track what is TRUE, not the writing nudges. A changed
## recent-phrase sample must not invalidate an in-flight slice.
func _test_fingerprint_tracks_facts_not_nudges() -> void:
	var contract := _buried_contract()
	var speaker := {"name": "Halda Vresk", "role": "clerk"}
	var base := PacketType.build(contract, speaker, "answer", {
		"question_text": "Who signed the impound order?",
	})
	var nudged := PacketType.build(contract, speaker, "answer", {
		"question_text": "Who signed the impound order?",
		"recent_phrases": ["Got a job for you", "Listen up"],
		"attitude": "impatient because the shift is ending",
	})
	_expect(
		PacketType.fingerprint(base) == PacketType.fingerprint(nudged),
		"A writing nudge changed the fact fingerprint and would strand in-flight slices."
	)
	var different_question := PacketType.build(contract, speaker, "answer", {
		"question_text": "What does it pay?",
	})
	_expect(
		PacketType.fingerprint(base) != PacketType.fingerprint(different_question),
		"Two different questions produced the same packet fingerprint."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
