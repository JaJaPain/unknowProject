extends SceneTree

# The whole conversation bundle used to be one request: opening plus a label and
# a response for EVERY intent. One malformed field discarded all of it, including
# the parts that were fine, and the retry paid for the good work again. These pin
# the slicing that replaces it.

const CompilerType := preload("res://scripts/story/MissionConversationCompiler.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var smoke: Array = CompilerType.plan_slices(_plan(1))
	if smoke.is_empty():
		push_error("[FAIL] MissionConversationCompiler did not compile or slice.")
		quit(1)
		return
	_test_opening_is_always_first()
	_test_intents_are_batched_within_the_cap()
	_test_slice_keys_drop_the_machine_owned_labels()
	_test_validated_slices_are_never_overwritten()
	_test_missing_keys_asks_only_for_what_is_absent()
	_test_slice_prompt_asks_for_one_thing_only()
	if _failures.is_empty():
		print("[PASS] Conversation slicing tests")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _plan(intent_count: int) -> Dictionary:
	var intents: Array = []
	for i in range(intent_count):
		intents.append({
			"id": "intent_%d" % i,
			"kind": "question",
			"label": "Ask about the cargo %d" % i,
			"answer_anchors": [],
		})
	return {"intents": intents}


func _test_opening_is_always_first() -> void:
	# If only one slice ever completes it should be the opening: it is what the
	# player sees before anything else.
	for count in [0, 1, 5]:
		var slices: Array = CompilerType.plan_slices(_plan(count))
		_expect(not slices.is_empty(), "There should always be at least an opening slice.")
		_expect(
			str((slices[0] as Dictionary).get("kind", "")) == CompilerType.SLICE_OPENING,
			"The first slice must be the opening (intents=%d)." % count
		)


func _test_intents_are_batched_within_the_cap() -> void:
	var slices: Array = CompilerType.plan_slices(_plan(5))
	var seen: Array[String] = []
	for i in range(1, slices.size()):
		var slice: Dictionary = slices[i]
		var ids: Array = slice.get("intent_ids", [])
		# Asserted against a LITERAL, not the constant. Comparing a value to the
		# constant that produced it is a tautology: mutation testing showed it
		# passed happily with the cap raised to 99, which is the whole behaviour
		# this test exists to prevent.
		_expect(
			ids.size() <= 2,
			"A slice must not exceed 2 intents, got %d" % ids.size()
		)
		for id in ids:
			_expect(str(id) not in seen, "Intent '%s' appears in two slices." % str(id))
			seen.append(str(id))
	# Every intent must be covered exactly once, or a conversation ships with a
	# button that has no answer behind it.
	_expect(seen.size() == 5, "All 5 intents should be covered exactly once, got %d" % seen.size())
	# 5 intents at 2 per slice is 3 intent slices plus the opening. Pinning the
	# COUNT is what actually detects a cap change.
	_expect(
		slices.size() == 4,
		"5 intents should produce 1 opening + 3 intent slices, got %d slices" % slices.size()
	)


func _test_slice_keys_drop_the_machine_owned_labels() -> void:
	# Button labels come from the code-approved intent list, which already has
	# them. Asking a model to restate a label it was handed spends inference to
	# introduce a chance of getting it wrong.
	var slices: Array = CompilerType.plan_slices(_plan(2))
	var opening_keys: Array = CompilerType.required_output_keys_for_slice(slices[0])
	_expect(opening_keys == ["opening"], "The opening slice asks for exactly the opening.")

	var intent_keys: Array = CompilerType.required_output_keys_for_slice(slices[1])
	_expect(not intent_keys.is_empty(), "An intent slice should ask for responses.")
	for key in intent_keys:
		_expect(
			not str(key).ends_with("_player"),
			"A slice must not ask for a machine-owned button label, got '%s'" % str(key)
		)
		_expect(str(key).ends_with("_response"), "Intent slices ask for responses, got '%s'" % str(key))

	# The legacy whole-bundle path still carries labels, so old bundles stay
	# readable.
	var legacy: Array = CompilerType.required_output_keys(_plan(2))
	var has_player := false
	for key in legacy:
		if str(key).ends_with("_player"):
			has_player = true
	_expect(has_player, "The legacy bundle contract must keep *_player for old data.")


func _test_validated_slices_are_never_overwritten() -> void:
	# This is what makes a partial failure cheap: work that already passed
	# validation stays, and a later response has no standing to replace it.
	var bundle := CompilerType.merge_slice({}, {"opening": "Good. You came."})
	bundle = CompilerType.merge_slice(bundle, {"intent_0_response": "The cargo is late."})
	_expect(str(bundle["opening"]) == "Good. You came.", "The opening should survive a later merge.")

	var overwritten := CompilerType.merge_slice(bundle, {"opening": "Something else entirely."})
	_expect(
		str(overwritten["opening"]) == "Good. You came.",
		"An accepted slice must NOT be replaced by a later response."
	)
	# Empty text never displaces real text either.
	var blanked := CompilerType.merge_slice(bundle, {"intent_0_response": "   "})
	_expect(
		str(blanked["intent_0_response"]) == "The cargo is late.",
		"Blank text must not overwrite an accepted line."
	)


func _test_missing_keys_asks_only_for_what_is_absent() -> void:
	# A repair should pay for the missing field, not the conversation.
	var plan := _plan(2)
	var bundle := CompilerType.merge_slice({}, {
		"opening": "You again.",
		"intent_0_response": "It went badly.",
	})
	var missing: Array = CompilerType.missing_keys(bundle, plan)
	_expect(
		missing == ["intent_1_response"],
		"Only the genuinely absent response should be requested, got %s" % str(missing)
	)
	var complete := CompilerType.merge_slice(bundle, {"intent_1_response": "Ask me later."})
	_expect(
		CompilerType.missing_keys(complete, plan).is_empty(),
		"A complete bundle should report nothing missing."
	)


func _test_slice_prompt_asks_for_one_thing_only() -> void:
	# Two sets of output instructions is how a model ends up answering the wrong
	# question, so the slice prompt REPLACES the output section rather than
	# appending to it.
	var plan := _plan(3)
	var slices: Array = CompilerType.plan_slices(plan)
	var opening_prompt: String = CompilerType.build_slice_prompt({}, {}, plan, slices[0], "")
	_expect(
		opening_prompt.count("OUTPUT:") == 1,
		"A slice prompt must contain exactly one OUTPUT section, got %d" % opening_prompt.count("OUTPUT:")
	)
	_expect(
		opening_prompt.contains("Do not write answers to any intent"),
		"The opening slice must say it wants only the opening."
	)
	var intent_prompt: String = CompilerType.build_slice_prompt({}, {}, plan, slices[1], "")
	_expect(
		intent_prompt.contains("Do not write the pilot button labels"),
		"An intent slice must say the labels are code-owned."
	)
	_expect(
		intent_prompt.count("OUTPUT:") == 1,
		"An intent slice prompt must contain exactly one OUTPUT section."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
