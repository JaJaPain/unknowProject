extends SceneTree

# Phase 8B batch generation plumbing: label expansion, per-line validation,
# and the flat @@label parser are pure and provable headless. The HTTP call
# itself follows the same plumbing as every other LLMInterface request.

var _failures: Array[String] = []
var _llm: Node = null


func _initialize() -> void:
	_llm = root.get_node("LLMInterface")
	_test_label_expansion()
	_test_per_line_validation()
	_test_batch_parsing()

	if _failures.is_empty():
		print("[PASS] Nova line bank batch tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_label_expansion() -> void:
	var labels: Array = _llm.nova_line_bank_labels([
		{"category": "boost_again_quickly", "count": 2},
		{"category": "rough_arrival", "count": 1},
		{"category": "gate_glitch", "count": 3},        # protected: dropped
		{"category": "not_a_category", "count": 2},     # invalid: dropped
	])
	_expect(
		labels == [
			"boost_again_quickly_1",
			"boost_again_quickly_2",
			"rough_arrival_1",
		],
		"Label expansion was wrong: %s" % str(labels)
	)
	var capped: Array = _llm.nova_line_bank_labels([
		{"category": "system_arrival", "count": 8},
		{"category": "gate_transit", "count": 8},
	])
	_expect(
		capped.size() == 10,
		"Batch should cap at 10 labels, got %d." % capped.size()
	)


func _test_per_line_validation() -> void:
	_expect(
		str(_llm.validate_nova_bank_line(
			"New system. My optimism remains amber."
		)).is_empty(),
		"A normal line should validate."
	)
	_expect(
		str(_llm.validate_nova_bank_line("Nope.")) == "too_short",
		"Sub-8-char lines should be rejected."
	)
	var long_line := ""
	for i in range(20):
		long_line += "padding padding "
	_expect(
		str(_llm.validate_nova_bank_line(long_line)) == "too_long",
		"Over-160-char lines should be rejected."
	)
	_expect(
		str(_llm.validate_nova_bank_line(
			"N.O.V.A.: I have opinions about this."
		)) == "speaker_prefix",
		"Speaker-prefixed lines should be rejected."
	)
	_expect(
		str(_llm.validate_nova_bank_line(
			"Arriving at {SYSTEM_NAME} now, Captain."
		)) == "placeholder_braces",
		"Placeholder braces should be rejected."
	)
	_expect(
		str(_llm.validate_nova_bank_line(
			"Docking again? I was just telling the clamps about you."
		)).is_empty(),
		"A line with a mid-sentence question mark should validate."
	)


func _test_batch_parsing() -> void:
	var expected: Array = [
		"boost_again_quickly_1",
		"boost_again_quickly_2",
		"rough_arrival_1",
		"system_arrival_1",
	]
	# Flat JSON keyed by label, wrapped in a markdown fence the parser must
	# strip. system_arrival_1 duplicates boost_again_quickly_1's text (drops);
	# rough_arrival_1 is absent (missing_label); casing drift is tolerated.
	var raw := "\n".join([
		"```json",
		"{",
		"  \"BOOST_AGAIN_QUICKLY_1\": \"Boost again already? My engines have feelings, probably.\",",
		"  \"boost_again_quickly_2\": \"That cooldown was for both of us, Captain.\",",
		"  \"system_arrival_1\": \"Boost again already? My engines have feelings, probably.\"",
		"}",
		"```",
	])
	var parsed: Dictionary = _llm.parse_nova_line_bank_batch(raw, expected)
	var lines: Array = parsed.get("lines", [])
	var rejected: Array = parsed.get("rejected", [])
	_expect(
		lines.size() == 2,
		"Expected 2 accepted lines, got %d." % lines.size()
	)
	var kinds: Array = []
	var texts: Array = []
	for line in lines:
		kinds.append(str((line as Dictionary).get("kind", "")))
		texts.append(str((line as Dictionary).get("text", "")))
	_expect(
		kinds == ["boost_again_quickly", "boost_again_quickly"],
		"Parsed kinds were wrong: %s" % str(kinds)
	)
	_expect(
		texts[1] == "That cooldown was for both of us, Captain.",
		"Case-insensitive/second line wrong: %s" % str(texts)
	)
	var reasons: Array = []
	for entry in rejected:
		reasons.append(str((entry as Dictionary).get("reason", "")))
	_expect(
		reasons.has("missing_label") and reasons.has("duplicate_text"),
		"Rejection reasons were wrong: %s" % str(reasons)
	)
	# A non-JSON body is rejected wholesale, not silently accepted.
	var junk: Dictionary = _llm.parse_nova_line_bank_batch("not json at all", expected)
	_expect(
		(junk.get("lines", []) as Array).is_empty(),
		"Non-JSON batch body should yield no lines."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
