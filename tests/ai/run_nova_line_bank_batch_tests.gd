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
	_test_shared_sentence_rejection()
	_test_duplicate_closer_rejection()

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


# Regression from a real live-fire batch: the small model welded one stock tail
# onto beat after beat -- "Good thing you didn't take the long way." closed six
# lines, on beats as unrelated as hull_critical and docked. Every one of them
# passed exact-match dedupe because the opening clauses differed, so the bank
# would have accepted N.O.V.A. saying the same thing all campaign.
func _test_shared_sentence_rejection() -> void:
	var expected := [
		"combat_victory_clean_1",
		"combat_victory_battered_1",
		"hull_critical_1",
		"docked_1",
		"welcome_back_1",
	]
	var raw := "
".join([
		"{",
		"  \"combat_victory_clean_1\": \"Hull's intact. Good thing you didn't take the long way.\",",
		"  \"combat_victory_battered_1\": \"Hull's bleeding. Good thing you didn't take the long way.\",",
		# Curly apostrophe: normalization must still see the same sentence.
		"  \"hull_critical_1\": \"Hull's failing. Good thing you didn’t take the long way.\",",
		# Em-dash instead of a period, same tail welded on.
		"  \"docked_1\": \"Clamps engaged—good thing you didn't take the long way.\",",
		"  \"welcome_back_1\": \"You're back. I kept your seat warm, Captain.\"",
		"}",
	])
	var parsed: Dictionary = _llm.parse_nova_line_bank_batch(raw, expected)
	var lines: Array = parsed.get("lines", [])
	_expect(
		lines.size() == 2,
		"Only the first tail-sharing line and the distinct line should survive, got %d." % lines.size()
	)
	var texts: Array = []
	for line in lines:
		texts.append(str((line as Dictionary).get("text", "")))
	_expect(
		texts.size() == 2 and texts[1] == "You're back. I kept your seat warm, Captain.",
		"The distinct line must be kept: %s" % str(texts)
	)
	var reasons: Array = []
	for entry in (parsed.get("rejected", []) as Array):
		reasons.append(str((entry as Dictionary).get("reason", "")))
	_expect(
		reasons.count("duplicate_sentence") == 3,
		"Expected 3 duplicate_sentence rejections, got %s" % str(reasons)
	)
	# A short shared fragment is NOT repetition -- terse status openings have to
	# stay reusable across beats or ordinary batches would gut themselves.
	var terse := "
".join([
		"{",
		"  \"combat_victory_clean_1\": \"Hull's intact. Nothing to report, Captain.\",",
		"  \"docked_1\": \"Hull's intact. Clamps engaged, and I am staying put.\"",
		"}",
	])
	var terse_parsed: Dictionary = _llm.parse_nova_line_bank_batch(
		terse, ["combat_victory_clean_1", "docked_1"]
	)
	_expect(
		(terse_parsed.get("lines", []) as Array).size() == 2,
		"A two-word shared opening must not be treated as a duplicate sentence."
	)


# Also from a live batch: three lines closed with "Still flying." and two with
# "Stay calm.". Both are under the shared-sentence word floor, but a repeated
# closer is what a player actually hears as repetition. Shared OPENINGS must
# stay legal, or ordinary terse batches would gut themselves.
func _test_duplicate_closer_rejection() -> void:
	var expected := [
		"combat_victory_clean_1",
		"combat_victory_battered_1",
		"hull_critical_1",
	]
	var raw := "
".join([
		"{",
		"  \"combat_victory_clean_1\": \"Hull's intact. Still flying.\",",
		"  \"combat_victory_battered_1\": \"Hull's cracked. Still flying.\",",
		"  \"hull_critical_1\": \"Hull's failing. Stay calm, Captain.\"",
		"}",
	])
	var parsed: Dictionary = _llm.parse_nova_line_bank_batch(raw, expected)
	var lines: Array = parsed.get("lines", [])
	_expect(
		lines.size() == 2,
		"The second line sharing a closer should drop, got %d lines." % lines.size()
	)
	var reasons: Array = []
	for entry in (parsed.get("rejected", []) as Array):
		reasons.append(str((entry as Dictionary).get("reason", "")))
	_expect(
		reasons == ["duplicate_closer"],
		"Expected one duplicate_closer rejection, got %s" % str(reasons)
	)
	# A shared opening with distinct closers is fine.
	var openings := "
".join([
		"{",
		"  \"combat_victory_clean_1\": \"Hull's intact. Nothing to report.\",",
		"  \"combat_victory_battered_1\": \"Hull's intact. I want a refit.\"",
		"}",
	])
	var opening_parsed: Dictionary = _llm.parse_nova_line_bank_batch(
		openings, ["combat_victory_clean_1", "combat_victory_battered_1"]
	)
	_expect(
		(opening_parsed.get("lines", []) as Array).size() == 2,
		"A shared opening with distinct closers must be accepted."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
