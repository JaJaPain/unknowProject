extends SceneTree

# A dialogue FIELD is the smallest unit worth preparing. These pin the three
# things the contract exists to prevent, each of which the current bundle
# approach allows:
#   - one bad response discarding good siblings
#   - a stale line spoken with full confidence after the world moved on
#   - an unbounded repair loop turning one bad line into a hang

const ContractType := preload("res://scripts/story/DialogueFieldContract.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var smoke: Dictionary = ContractType.make_request("m1", "kaelen", "opening", ["greeting"])
	if smoke.is_empty() or not smoke.has("max_words_per_field"):
		push_error("[FAIL] DialogueFieldContract did not compile or build.")
		quit(1)
		return
	_test_budgets_follow_purpose()
	_test_request_validation_rejects_the_expensive_mistakes()
	_test_prepared_must_answer_the_request_that_asked()
	_test_length_budget_is_enforced_both_ways()
	_test_stale_context_is_refused()
	_test_attempts_are_bounded()
	_test_line_identity_is_situation_specific()
	if _failures.is_empty():
		print("[PASS] Dialogue field contract tests")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _req(purpose: String = "opening", options: Dictionary = {}) -> Dictionary:
	var base := {
		"context_fingerprint": "fp-1",
		"fact_ids": ["f1"],
		"facts": [{"id": "f1", "text": "The hauler never arrived.", "revision": 1}],
	}
	for k in options:
		base[k] = options[k]
	return ContractType.make_request("mission_7", "kaelen", purpose, ["greeting"], base)


func _test_budgets_follow_purpose() -> void:
	# An opening line and a one-word availability check are not the same kind of
	# utterance, so the budget comes from the purpose rather than the caller.
	_expect(
		ContractType.max_words_for("opening") > ContractType.max_words_for("availability"),
		"An opening should get more words than an availability check."
	)
	_expect(
		int(_req("opening")["max_words_per_field"]) == ContractType.MAX_WORDS_ROOMY,
		"An opening request should carry the roomy word budget."
	)
	_expect(
		int(_req("callback")["max_chars_per_field"]) == ContractType.MAX_CHARS_TIGHT,
		"A callback should carry the tight char budget."
	)


func _test_request_validation_rejects_the_expensive_mistakes() -> void:
	_expect(bool(ContractType.validate_request(_req())["ok"]), "A well-formed request should validate.")

	# A fact referenced but not supplied: the model will invent one, confidently.
	var missing := _req("opening", {"fact_ids": ["f1", "f_ghost"]})
	var r: Dictionary = ContractType.validate_request(missing)
	_expect(
		not bool(r["ok"]) and str(r["reason"]).begins_with("fact_not_supplied"),
		"A referenced-but-unsupplied fact must be refused, got %s" % str(r)
	)

	# No fingerprint means the line can never be invalidated, so it would be
	# served stale forever.
	var nofp := _req("opening", {"context_fingerprint": ""})
	_expect(
		str(ContractType.validate_request(nofp)["reason"]) == "missing_context_fingerprint",
		"A request without a fingerprint must be refused."
	)

	var bad_purpose := ContractType.make_request(
		"m", "k", "monologue", ["x"], {"context_fingerprint": "fp"}
	)
	_expect(
		str(ContractType.validate_request(bad_purpose)["reason"]).begins_with("unknown_purpose"),
		"An unknown purpose must be refused rather than defaulted."
	)

	# More than two fields is a bundle again, which is what this replaces.
	var too_many := ContractType.make_request(
		"m", "k", "opening", ["a", "b", "c"], {"context_fingerprint": "fp"}
	)
	_expect(
		str(ContractType.validate_request(too_many)["reason"]).begins_with("too_many_fields"),
		"Three fields is a bundle, not a field request."
	)

	var too_many_mem := _req("opening", {"memory_ids": ["m1", "m2", "m3"]})
	_expect(
		str(ContractType.validate_request(too_many_mem)["reason"]).begins_with("too_many_memories"),
		"More than two memories is the old copy-the-whole-world behaviour."
	)


func _test_prepared_must_answer_the_request_that_asked() -> void:
	# A line can be perfectly well formed and still answer a question nobody
	# asked, which is why the PAIR is validated rather than the field alone.
	var req := _req()
	var ok := ContractType.make_prepared(req, "greeting", "Cargo is late. That is your problem now.")
	_expect(bool(ContractType.validate_prepared(ok, req)["ok"]), "A matching prepared field should validate.")

	var wrong_field := ContractType.make_prepared(req, "farewell", "Safe flying.")
	_expect(
		str(ContractType.validate_prepared(wrong_field, req)["reason"]).begins_with("field_not_requested"),
		"A field nobody requested must be refused."
	)

	var wrong_speaker := ContractType.make_prepared(req, "greeting", "Hello.")
	wrong_speaker["speaker_id"] = "nova"
	_expect(
		str(ContractType.validate_prepared(wrong_speaker, req)["reason"]) == "speaker_mismatch",
		"A line attributed to the wrong speaker must be refused -- that is a canon leak."
	)


func _test_length_budget_is_enforced_both_ways() -> void:
	var req := _req("availability")
	var words := PackedStringArray()
	for i in range(ContractType.MAX_WORDS_TIGHT + 5):
		words.append("word")
	var wordy := ContractType.make_prepared(req, "greeting", " ".join(words))
	_expect(
		str(ContractType.validate_prepared(wordy, req)["reason"]).begins_with("too_many_words"),
		"An over-long line must be refused on words."
	)

	# Chars as well as words: a model can satisfy a word count with very long
	# words and still overflow the panel it has to fit in.
	var long_word := ""
	for i in range(ContractType.MAX_CHARS_TIGHT + 20):
		long_word += "x"
	var chary := ContractType.make_prepared(req, "greeting", long_word)
	_expect(
		str(ContractType.validate_prepared(chary, req)["reason"]).begins_with("too_many_chars"),
		"A single enormous word must be refused on characters."
	)


func _test_stale_context_is_refused() -> void:
	var req := _req()
	var prepared := ContractType.make_prepared(req, "greeting", "Still waiting on that hauler.")
	_expect(
		ContractType.is_still_applicable(prepared, "fp-1"),
		"A prepared line should apply while the world matches."
	)
	_expect(
		not ContractType.is_still_applicable(prepared, "fp-2"),
		"Once the world moves on the line must stop applying."
	)

	var moved := req.duplicate(true)
	moved["context_fingerprint"] = "fp-2"
	_expect(
		str(ContractType.validate_prepared(prepared, moved)["reason"]) == "stale_context",
		"A line prepared for an older world state must be refused, not spoken."
	)

	# Delivered and retired lines never come back, whatever the fingerprint says.
	for spent in ["delivered", "retired", "failed"]:
		var used := prepared.duplicate(true)
		used["status"] = spent
		_expect(
			not ContractType.is_still_applicable(used, "fp-1"),
			"A '%s' line must not be reusable." % spent
		)


func _test_attempts_are_bounded() -> void:
	# An unbounded repair loop is how a local model turns one bad line into a
	# hang, which is a failure mode this codebase has already seen.
	var req := _req()
	var over := ContractType.make_prepared(
		req, "greeting", "Fine.", {"attempt_count": ContractType.MAX_ATTEMPTS + 1}
	)
	_expect(
		str(ContractType.validate_prepared(over, req)["reason"]).begins_with("attempt_count_out_of_range"),
		"Attempts beyond the cap must be refused."
	)
	var zero := ContractType.make_prepared(req, "greeting", "Fine.", {"attempt_count": 0})
	_expect(
		str(ContractType.validate_prepared(zero, req)["reason"]).begins_with("attempt_count_out_of_range"),
		"A zero attempt count is incoherent and must be refused."
	)


func _test_line_identity_is_situation_specific() -> void:
	# The same words prepared for a different situation are a DIFFERENT line, or
	# consumption and retirement records cannot be trusted later.
	var a := ContractType.line_id_for("m1", "greeting", "fp-1", "Same words.")
	var b := ContractType.line_id_for("m1", "greeting", "fp-2", "Same words.")
	var c := ContractType.line_id_for("m2", "greeting", "fp-1", "Same words.")
	_expect(a != b, "A different world state must give a different line id.")
	_expect(a != c, "A different owner must give a different line id.")
	_expect(
		a == ContractType.line_id_for("m1", "greeting", "fp-1", "Same words."),
		"The same inputs must give a stable id."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
