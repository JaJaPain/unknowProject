extends SceneTree

const BankType := preload("res://scripts/story/FallbackLineBank.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_create_bank_caps_at_target_and_marks_fallbacks()
	_test_create_bank_preserves_per_line_kinds()
	_test_consume_marks_used_and_counts_fallback_usage()
	_test_generated_lines_replace_used_fallback_slots()
	_test_generated_lines_do_not_overfill_full_unused_bank()
	_test_empty_bank_reports_no_line()
	_test_consumed_lines_are_retired_for_the_campaign()
	_test_generated_lines_can_carry_their_own_kinds()

	if _failures.is_empty():
		print("[PASS] Fallback line bank tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_create_bank_caps_at_target_and_marks_fallbacks() -> void:
	var bank := BankType.create_bank("nova", "startup_navigation", _numbered_lines(24), 20)
	var entries: Array = bank.get("entries", [])
	_expect(entries.size() == 20, "Fallback bank should cap entries at target size 20.")
	_expect(
		int(bank.get("target_size", 0)) == 20
			and str(bank.get("speaker_key", "")) == "nova"
			and str(bank.get("line_kind", "")) == "startup_navigation",
		"Fallback bank did not preserve identity metadata."
	)
	for raw_entry in entries:
		var entry: Dictionary = raw_entry
		_expect(
			str(entry.get("source", "")) == "fallback"
				and bool(entry.get("is_fallback", false))
				and not bool(entry.get("used", false)),
			"Initial bank entries must be unused fallback lines."
		)


func _test_create_bank_preserves_per_line_kinds() -> void:
	var bank := BankType.create_bank("kaelen", "agent_handoff", [
		{"kind": "first_system_arrival", "text": "Welcome to the new system."},
		"Ask the expensive question.",
	], 20)
	var entries: Array = bank.get("entries", [])
	_expect(
		entries.size() == 2
			and str((entries[0] as Dictionary).get("kind", "")) == "first_system_arrival"
			and str((entries[1] as Dictionary).get("kind", "")) == "agent_handoff",
		"Fallback bank did not preserve per-line kinds."
	)
	var consumed: Dictionary = BankType.consume(bank, "first_system_arrival")
	var line: Dictionary = consumed.get("line", {})
	_expect(
		bool(consumed.get("ok", false))
			and str(line.get("text", "")) == "Welcome to the new system.",
		"Preferred-kind consume did not select the first-system-arrival line."
	)


func _test_consume_marks_used_and_counts_fallback_usage() -> void:
	var bank := BankType.create_bank("kaelen", "agent_handoff", [
		"First fallback.",
		"Second fallback.",
	], 20)
	var consumed: Dictionary = BankType.consume(bank, "agent_handoff")
	_expect(bool(consumed.get("ok", false)), "Expected consume to return a line.")
	var next_bank: Dictionary = consumed.get("bank", {})
	var line: Dictionary = consumed.get("line", {})
	_expect(
		bool(line.get("used", false))
			and int(line.get("use_count", 0)) == 1
			and BankType.fallback_use_count(next_bank) == 1
			and BankType.available_count(next_bank) == 1,
		"Consuming fallback line did not mark usage correctly."
	)


func _test_generated_lines_replace_used_fallback_slots() -> void:
	var bank := BankType.create_bank("nova", "startup_navigation", [
		"Fallback one.",
		"Fallback two.",
		"Fallback three.",
	], 20)
	var consumed: Dictionary = BankType.consume(bank)
	var replacement: Dictionary = BankType.replace_used_with_generated(
		consumed.get("bank", {}),
		["Generated better line.", "Fallback two."],
		"llm"
	)
	var next_bank: Dictionary = replacement.get("bank", {})
	var entries: Array = next_bank.get("entries", [])
	_expect(
		int(replacement.get("replacements", 0)) == 1
			and BankType.generated_replacement_count(next_bank) == 1
			and entries.size() == 3,
		"Generated replacement should replace one used slot without growing past existing entries."
	)
	var replaced: Dictionary = entries[0]
	_expect(
		str(replaced.get("text", "")) == "Generated better line."
			and str(replaced.get("source", "")) == "llm"
			and not bool(replaced.get("is_fallback", true))
			and not bool(replaced.get("used", true)),
		"Generated replacement was not installed as fresh non-fallback content."
	)


func _test_generated_lines_do_not_overfill_full_unused_bank() -> void:
	var bank := BankType.create_bank(
		"kaelen",
		"agent_handoff",
		_numbered_lines(24),
		20
	)
	var replacement: Dictionary = BankType.replace_used_with_generated(
		bank,
		["Generated line without a used slot."],
		"llm"
	)
	var next_bank: Dictionary = replacement.get("bank", {})
	var entries: Array = next_bank.get("entries", [])
	_expect(
		int(replacement.get("replacements", 0)) == 0
			and entries.size() == 20
			and BankType.generated_replacement_count(next_bank) == 0,
		"Generated lines should not overfill a full fallback bank with no used slots."
	)


func _test_empty_bank_reports_no_line() -> void:
	var bank := BankType.create_bank("kaelen", "agent_handoff", [], 20)
	var consumed: Dictionary = BankType.consume(bank)
	_expect(
		not bool(consumed.get("ok", true))
			and str(consumed.get("status", "")) == "fallback_bank_empty",
		"Empty fallback bank should report fallback_bank_empty."
	)


# Campaign retirement: once a line is consumed, no later refill may re-offer
# its text, even after its slot has been recycled by a replacement.
func _test_consumed_lines_are_retired_for_the_campaign() -> void:
	var bank := BankType.create_bank("nova", "system_arrival", _numbered_lines(3), 3)
	var consumed: Dictionary = BankType.consume(bank)
	_expect(bool(consumed.get("ok", false)), "Retirement test consume failed.")
	var after_consume: Dictionary = consumed.get("bank", {})
	var spoken_text := str((consumed.get("line", {}) as Dictionary).get("text", ""))
	_expect(
		BankType.is_retired(after_consume, spoken_text),
		"Consumed line was not recorded in the retirement ledger."
	)

	# Recycle the used slot with a fresh generated line...
	var replaced: Dictionary = BankType.replace_used_with_generated(
		after_consume, ["A brand new observation."], "llm"
	)
	var recycled: Dictionary = replaced.get("bank", {})
	_expect(
		int(replaced.get("replacements", 0)) == 1,
		"Fresh generated line should fill the used slot."
	)
	# ...then try to sneak the retired text back in: it must be refused even
	# though the text no longer occupies any slot.
	var retread: Dictionary = BankType.replace_used_with_generated(
		BankType.consume(recycled).get("bank", {}),
		[spoken_text, "Another new observation."],
		"llm"
	)
	var final_bank: Dictionary = retread.get("bank", {})
	var texts: Array = []
	for raw_entry in (final_bank.get("entries", []) as Array):
		texts.append(str((raw_entry as Dictionary).get("text", "")))
	_expect(
		int(retread.get("replacements", 0)) == 1
			and not texts.has(spoken_text)
			and texts.has("Another new observation."),
		"Retired line text was re-offered after its slot was recycled."
	)


# A generated batch can span several categories: {kind, text} entries keep
# their own kind, plain strings inherit the bank's line_kind.
func _test_generated_lines_can_carry_their_own_kinds() -> void:
	var bank := BankType.create_bank(
		"nova", "system_arrival", ["Old line one.", "Old line two."], 4
	)
	var consumed: Dictionary = BankType.consume(bank)
	var replaced: Dictionary = BankType.replace_used_with_generated(
		consumed.get("bank", {}),
		[
			{"kind": "boost_again_quickly", "text": "Boost again? Bold."},
			"Plain string keeps the bank kind.",
		],
		"llm_nova_bank"
	)
	_expect(
		int(replaced.get("replacements", 0)) == 2,
		"Both generated lines should land (one slot + one append)."
	)
	var kinds_by_text: Dictionary = {}
	for raw_entry in ((replaced.get("bank", {}) as Dictionary).get("entries", []) as Array):
		var entry: Dictionary = raw_entry
		kinds_by_text[str(entry.get("text", ""))] = str(entry.get("kind", ""))
	_expect(
		str(kinds_by_text.get("Boost again? Bold.", "")) == "boost_again_quickly",
		"Dictionary line did not keep its own kind."
	)
	_expect(
		str(kinds_by_text.get("Plain string keeps the bank kind.", ""))
			== "system_arrival",
		"Plain string line did not inherit the bank line_kind."
	)


func _numbered_lines(count: int) -> Array[String]:
	var lines: Array[String] = []
	for i in range(count):
		lines.append("Fallback line %02d." % i)
	return lines


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
