extends SceneTree

var _failures: Array[String] = []
var _llm: Node = null


func _initialize() -> void:
	_llm = root.get_node("LLMInterface")
	_test_validation()
	_test_batch_parsing()
	_test_truncation_salvage()
	_test_cross_session_dedupe()

	if _failures.is_empty():
		print("[PASS] Taunt parse tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_validation() -> void:
	_expect(
		_llm.validate_taunt_line("I'm going to make this one hurt.").is_empty(),
		"A plain short threat must be accepted -- not every line explains itself."
	)
	_expect(
		_llm.validate_taunt_line("ENEMY: you're dead.") == "speaker_prefix",
		"A speaker label must be rejected."
	)
	_expect(
		_llm.validate_taunt_line("Pay the [amount] credits.") == "placeholder_braces",
		"Placeholder brackets must be rejected."
	)
	_expect(
		_llm.validate_taunt_line("*laughs* You're dead.") == "stage_direction",
		"Stage directions must be rejected."
	)
	_expect(
		_llm.validate_taunt_line("Die.") == "too_short",
		"A fragment must be rejected."
	)
	# Straight from a live batch: a curly apostrophe arrived as a bare "?",
	# which TTS would happily read out as a glitch.
	_expect(
		_llm.validate_taunt_line("This isn?t personal, it's policy enforcement.") 			== "corrupt_punctuation",
		"A question mark inside a word must be rejected."
	)
	# A real question, and a question mark next to punctuation, must survive.
	_expect(
		_llm.validate_taunt_line("Was it something I flew?").is_empty(),
		"A genuine question must be accepted."
	)
	_expect(
		_llm.validate_taunt_line("You want to do this? Fine. Let's go.").is_empty(),
		"A mid-line question must be accepted."
	)


func _test_batch_parsing() -> void:
	var raw := '{"lines": ["We don\'t negotiate with the cargo.", "Empty the hold.", "I am going to make this one hurt."]}'
	var parsed: Dictionary = _llm.parse_taunt_bank_batch(raw, {})
	_expect(
		(parsed.get("lines", []) as Array).size() == 3,
		"Expected 3 accepted lines, got %d." % (parsed.get("lines", []) as Array).size()
	)
	# A fenced body must still parse.
	var fenced := "```json\n" + raw + "\n```"
	_expect(
		(_llm.parse_taunt_bank_batch(fenced, {}).get("lines", []) as Array).size() == 3,
		"A markdown-fenced batch must parse."
	)
	_expect(
		(_llm.parse_taunt_bank_batch("not json", {}).get("lines", []) as Array).is_empty(),
		"A non-JSON body must yield nothing."
	)


# Straight from two live runs: generation stopped one brace short of valid
# JSON and a whole cause came back empty. Five good lines were being thrown
# away to save nothing.
func _test_truncation_salvage() -> void:
	var truncated := '{\n  "lines": [\n    "Empty the hold, or I make it happen.",\n    "Your ship is not worth the time to move.",\n    "I will make this one hurt. Then it is done."\n  ]'
	var parsed: Dictionary = _llm.parse_taunt_bank_batch(truncated, {})
	var lines: Array = parsed.get("lines", [])
	_expect(
		lines.size() == 3,
		"A batch cut before the closing brace should salvage 3 lines, got %d." % lines.size()
	)
	_expect(
		lines.size() == 3 and str(lines[0]) == "Empty the hold, or I make it happen.",
		"Salvaged text must survive intact: %s" % str(lines)
	)
	# A line cut mid-word must be DROPPED, never delivered half-said.
	var mid_word := '{"lines": ["This one is complete and safe to keep.", "This one was cut off half'
	var partial: Dictionary = _llm.parse_taunt_bank_batch(mid_word, {})
	var partial_lines: Array = partial.get("lines", [])
	_expect(
		partial_lines.size() == 1,
		"Only the closed string should survive, got %d." % partial_lines.size()
	)
	_expect(
		partial_lines.size() == 1 and not str(partial_lines[0]).contains("cut off half"),
		"A half-written line must not be delivered: %s" % str(partial_lines)
	)
	# Salvage must not resurrect junk from a body that was never the right shape.
	_expect(
		(_llm.parse_taunt_bank_batch('{"nonsense": ["a", "b"]}', {}).get("lines", []) as Array).is_empty(),
		"A body without a lines key must not be salvaged into content."
	)


# The pool spans sessions and grows for the life of the campaign, so the model
# will re-propose lines it already gave weeks ago. Dedupe has to look at what
# is already banked, not just at this batch.
func _test_cross_session_dedupe() -> void:
	var existing := {"Empty the hold, or I make it happen.": true}
	var raw := '{"lines": ["Empty the hold, or I make it happen.", "A completely different threat entirely."]}'
	var parsed: Dictionary = _llm.parse_taunt_bank_batch(raw, existing)
	var lines: Array = parsed.get("lines", [])
	_expect(
		lines.size() == 1 and str(lines[0]) == "A completely different threat entirely.",
		"An already-banked line must be rejected: %s" % str(lines)
	)
	var reasons: Array = []
	for entry in (parsed.get("rejected", []) as Array):
		reasons.append(str((entry as Dictionary).get("reason", "")))
	_expect(
		reasons.has("already_in_pool"),
		"Re-proposed lines should report already_in_pool, got %s" % str(reasons)
	)
	# Near-duplicates inside one batch are caught too (same guards as the
	# N.O.V.A. banks -- a shared closer is what reads as repetition).
	var tics := '{"lines": ["Your hold is mine now. Then it is done.", "Your ship is scrap. Then it is done."]}'
	var tic_parsed: Dictionary = _llm.parse_taunt_bank_batch(tics, {})
	_expect(
		(tic_parsed.get("lines", []) as Array).size() == 1,
		"A repeated closer inside one batch must be rejected."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
