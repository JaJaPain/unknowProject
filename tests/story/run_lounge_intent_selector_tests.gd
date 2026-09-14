extends SceneTree

# Phase 9: player lounge intents are code-selected from what the player has
# actually heard; generic filler only pads below the minimum.

var SelectorType: GDScript = null

var _failures: Array[String] = []


func _initialize() -> void:
	SelectorType = load("res://scripts/story/LoungeIntentSelector.gd")
	if SelectorType == null or not SelectorType.can_instantiate():
		push_error("[FAIL] LoungeIntentSelector.gd did not compile.")
		quit(1)
		return
	_test_story_questions_displace_generics()
	_test_only_rumored_gaps_become_questions()
	_test_generics_pad_to_minimum_only()
	_test_warm_callback_beats_generics()

	if _failures.is_empty():
		print("[PASS] Lounge intent selector tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _ids(intents: Array) -> Array:
	var ids: Array = []
	for intent in intents:
		ids.append(str((intent as Dictionary).get("id", "")))
	return ids


func _test_story_questions_displace_generics() -> void:
	var intents: Array = SelectorType.select_intents({
		"knowledge_gaps": [
			{
				"fact_id": "fact.convoy.disappearance",
				"state": "rumored",
				"alias": "the missing convoy",
			},
		],
		"delivered_rumors": [
			{"rumor_id": "rumor.gate.toll", "summary": "a new gate toll"},
		],
		"mission_label": "Kova Smelter Feed (DELIVER_ORE)",
	})
	_expect(
		_ids(intents) == [
			"gap:fact.convoy.disappearance",
			"rumor:rumor.gate.toll",
			"stake:mission",
		],
		"Three story questions should fill the list, no generics: %s"
			% str(_ids(intents))
	)
	for intent in intents:
		_expect(
			not str((intent as Dictionary).get("text", "")).is_empty(),
			"Story intent missing question text."
		)
	_expect(
		str((intents[0] as Dictionary).get("text", ""))
			.contains("the missing convoy"),
		"Knowledge-gap question does not name the heard fact."
	)


func _test_only_rumored_gaps_become_questions() -> void:
	var intents: Array = SelectorType.select_intents({
		"knowledge_gaps": [
			{
				"fact_id": "fact.hidden.director",
				"state": "unknown",
				"alias": "a director secret",
			},
			{
				"fact_id": "fact.known.route",
				"state": "known",
				"alias": "the open route",
			},
		],
	})
	_expect(
		_ids(intents) == ["generic:friendly", "generic:pushback"],
		"Unheard facts must never become player questions: %s"
			% str(_ids(intents))
	)


func _test_generics_pad_to_minimum_only() -> void:
	var one_story: Array = SelectorType.select_intents({
		"delivered_rumors": [
			{"rumor_id": "rumor.dock.fees", "summary": "dock fees doubling"},
		],
	})
	_expect(
		_ids(one_story) == ["rumor:rumor.dock.fees", "generic:friendly"],
		"One story question should pad with exactly one generic: %s"
			% str(_ids(one_story))
	)
	var none: Array = SelectorType.select_intents({})
	_expect(
		_ids(none) == ["generic:friendly", "generic:pushback"],
		"No story sources should yield exactly two generics: %s"
			% str(_ids(none))
	)


func _test_warm_callback_beats_generics() -> void:
	var intents: Array = SelectorType.select_intents({
		"delivered_rumors": [
			{"rumor_id": "rumor.dock.fees", "summary": "dock fees doubling"},
		],
		"relationship": {"warmth_tier": "warm", "met_before": true},
	})
	_expect(
		_ids(intents) == ["rumor:rumor.dock.fees", "warm:callback"],
		"Warm callback should pad before generic filler: %s"
			% str(_ids(intents))
	)
	var cold: Array = SelectorType.select_intents({
		"relationship": {"warmth_tier": "cold", "met_before": true},
	})
	_expect(
		not _ids(cold).has("warm:callback"),
		"Cold contacts should not get the warm callback question."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
