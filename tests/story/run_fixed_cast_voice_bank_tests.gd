extends SceneTree

const VoiceBankType := preload("res://scripts/story/FixedCastVoiceBank.gd")
const StateType := preload("res://scripts/story/FixedCastStateMachine.gd")
const AttachmentType := preload("res://scripts/story/FixedCastAttachmentLedger.gd")
var _failures: Array[String] = []

func _initialize() -> void:
	var loaded: Dictionary = VoiceBankType.load_examples()
	_expect(bool(loaded.get("ok", false)), "Curated voice bank did not load: %s" % str(loaded))
	var used: Array = []
	var last_id := ""
	var seen: Dictionary = {}
	for index in range(6):
		var result: Dictionary = VoiceBankType.select_line(
			"kaelen",
			"broker_neutral",
			"public_board_turn_in",
			{"public_board": true, "low_broker_fee": true, "runtime_id": "board.%d" % index},
			used,
			last_id
		)
		_expect(bool(result.get("ok", false)), "Board line selection failed at %d: %s" % [index, str(result)])
		var chosen_id := str(result.get("example_id", ""))
		_expect(not seen.has(chosen_id), "Board selector repeated a line before exhausting its bank.")
		seen[chosen_id] = true
		used.append(chosen_id)
		last_id = chosen_id
	_expect(seen.size() == 6, "Expected all six curated board lines before a repeat.")
	var missing_context := VoiceBankType.select_line(
		"kaelen", "broker_neutral", "public_board_turn_in", {"runtime_id": "missing"}
	)
	_expect(not bool(missing_context.get("ok", false)), "Board lines must require public-board context.")
	var cycle := VoiceBankType.select_line(
		"kaelen", "broker_neutral", "public_board_turn_in",
		{"public_board": true, "low_broker_fee": true, "runtime_id": "board.cycle"}, used, last_id
	)
	_expect(bool(cycle.get("ok", false)) and bool(cycle.get("cycle_reset", false)), "Exhausted board bank should begin a non-repeating new cycle.")
	_expect(str(cycle.get("example_id", "")) != last_id, "A new board cycle must not immediately repeat the last line.")
	var check_used: Array = []
	var check_first := VoiceBankType.select_round_robin_line("kaelen", "more_work_check", {}, check_used)
	_expect(bool(check_first.get("ok", false)), "Kaelen's more-work check pool did not load.")
	for index in range(20):
		var next_check := VoiceBankType.select_round_robin_line("kaelen", "more_work_check", {}, check_used)
		_expect(bool(next_check.get("ok", false)), "More-work check line %d was unavailable." % index)
		_expect(not check_used.has(str(next_check.get("example_id", ""))), "More-work check pool repeated before its full round.")
		check_used.append(str(next_check.get("example_id", "")))
	_expect(check_used.size() == 20, "Expected a 20-line Kaelen more-work check pool.")
	var check_cycle := VoiceBankType.select_round_robin_line("kaelen", "more_work_check", {}, check_used)
	_expect(bool(check_cycle.get("cycle_reset", false)), "More-work check pool must restart only after all twenty lines are heard.")
	_expect(str(check_cycle.get("example_id", "")) == str(check_first.get("example_id", "")), "More-work check pool must restart from its first reviewed line.")
	var normal_turn_in := VoiceBankType.select_line(
		"kaelen", "quietly_relieved", "turn_in", {"runtime_id": "normal.fallback"}
	)
	_expect(bool(normal_turn_in.get("ok", false)), "A normal Kaelen turn-in should have a curated fallback line.")
	var style_block := VoiceBankType.style_reference_block(
		"kaelen", "quietly_relieved", "turn_in", {"high_payout": true, "known_tough": true}
	)
	_expect(style_block.contains("Approved voice rhythm references") and style_block.contains("Do not quote"), "Curated style references must be explicitly non-copying guidance.")
	var references := VoiceBankType.select_style_references(
		"kaelen", "quietly_relieved", "turn_in",
		{"high_payout": true, "known_tough": true, "reference_seed": "style.test"}, 2
	)
	var premise_tags: Dictionary = {}
	for reference in references:
		var tag := VoiceBankType.semantic_premise_tag(reference)
		_expect(not premise_tags.has(tag), "Style sampler selected duplicate semantic premise tags.")
		premise_tags[tag] = true
	_expect(references.size() == 2, "Style sampler should provide the requested small reference slice.")
	_expect(
		VoiceBankType.reference_combination_count(30, 3) == 4060,
		"Thirty examples sampled three at a time must expose 4,060 unique combinations."
	)
	for character_id in ["kaelen", "nova"]:
		var quiet_examples: Array[Dictionary] = []
		var quiet_tags: Dictionary = {}
		var quiet_lines: Dictionary = {}
		for raw_example in loaded.get("examples", []):
			var example: Dictionary = raw_example
			if str(example.get("character_id", "")) != character_id \
					or str(example.get("state", "")) != "evergreen" \
					or str(example.get("situation", "")) != "quiet_moment":
				continue
			quiet_examples.append(example)
			var quiet_tag := VoiceBankType.semantic_premise_tag(example)
			_expect(not quiet_tags.has(quiet_tag), "%s quiet bank reused semantic tag %s." % [character_id, quiet_tag])
			quiet_tags[quiet_tag] = true
			var quiet_line := str(example.get("line", "")).to_lower().strip_edges()
			_expect(not quiet_lines.has(quiet_line), "%s quiet bank repeated an exact line." % character_id)
			quiet_lines[quiet_line] = true
		_expect(quiet_examples.size() == 30, "%s needs exactly thirty reviewed quiet-moment references." % character_id)
		_expect(quiet_tags.size() == 30, "%s quiet bank must use thirty distinct semantic premises." % character_id)
		var quiet_slice := VoiceBankType.select_style_references(
			character_id, "evergreen", "quiet_moment",
			{"reference_seed": "%s.quiet.bank" % character_id, "reference_combination_index": 4059}, 3
		)
		_expect(quiet_slice.size() == 3, "%s quiet sampler must provide three references." % character_id)
		var quiet_slice_tags: Dictionary = {}
		for reference in quiet_slice:
			var quiet_tag := VoiceBankType.semantic_premise_tag(reference)
			_expect(not quiet_slice_tags.has(quiet_tag), "%s quiet sampler repeated a premise within one prompt." % character_id)
			quiet_slice_tags[quiet_tag] = true
	_expect(
		VoiceBankType.matches_curated_line("kaelen", "turn_in", "Clean work, Shiny. I can sleep now knowing my credits are in my account. Oh, and you got paid a little too."),
		"Exact curated Kaelen turn-in text must be detected before reaching the player."
	)
	_expect(
		VoiceBankType.matches_curated_line("kaelen", "abandonment", "You're walking away? Fine. I know how to price a loss, but who's got the invoice to send?"),
		"A generated line that reuses five reviewed words in sequence must be rejected."
	)
	_expect(
		not VoiceBankType.matches_curated_line("kaelen", "turn_in", "Clean work, Shiny. The transfer cleared and I almost approve."),
		"Fresh Kaelen wording must not be mistaken for a copied curated line."
	)
	var board_state := StateType.apply_event(
		StateType.default_ledger(), "mission_completed", {"public_board": true}, AttachmentType.default_ledger(), 1
	)
	_expect(StateType.state_for("kaelen", board_state) == "broker_neutral", "Public-board completion must use Kaelen's broker-neutral state.")
	var ui_file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	var nova_file := FileAccess.open("res://scripts/ai/Nova.gd", FileAccess.READ)
	var llm_file := FileAccess.open("res://scripts/LLMInterface.gd", FileAccess.READ)
	_expect(ui_file != null, "Could not inspect board turn-in wiring.")
	_expect(nova_file != null, "Could not inspect N.O.V.A. curated fallback wiring.")
	_expect(llm_file != null, "Could not inspect Kaelen curated style wiring.")
	if ui_file != null:
		var ui_source := ui_file.get_as_text()
		_expect(ui_source.contains("take_curated_fixed_cast_line") and ui_source.contains("curated_line_unavailable") and ui_source.contains("\"turn_in\""), "Board and normal Kaelen turn-ins do not use the curated bank with diagnosed fallbacks.")
		_expect(ui_source.contains("Any more work for me?") and ui_source.contains("take_persistent_fixed_cast_pool_line") and ui_source.contains("playback_finished") and ui_source.contains("_present_agent_board_result_when_ready") and ui_source.contains("func _on_agent_more_work_pressed") and ui_source.contains("_on_talk_to_agent_pressed()"), "Post-turn-in follow-up does not finish Kaelen's persistent check-in before delegating to the same agent offer flow as Talk to Agent.")
	if nova_file != null:
		var nova_source := nova_file.get_as_text()
		_expect(nova_source.contains("_curated_line_for_category") and nova_source.contains("_curated_line_for_situation(\"repair_warning\""), "N.O.V.A. does not use reviewed lines before stock fallbacks.")
	if llm_file != null:
		var llm_source := llm_file.get_as_text()
		_expect(llm_source.contains("FixedCastVoiceBankType.style_reference_block") and llm_source.contains("curated_style_block") and llm_source.contains("matches_curated_line") and llm_source.contains("never look ahead") and llm_source.contains("never the client or faction") and llm_source.contains("fictional_credit_adjustment") and llm_source.contains("fictional_payout_recipient") and llm_source.contains("reviewed abandonment selected"), "Kaelen's generated reactions are missing reviewed style guidance, copy protection, close-the-contract boundaries, accounting protection, payout-recipient protection, or reviewed abandonment selection.")
	if _failures.is_empty():
		print("[PASS] Fixed-cast voice bank tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
