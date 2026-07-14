extends SceneTree

# Runtime load, not const preload (autoload-ordering rule — see
# run_story_state_bible_seed_tests header).
var ConvoType: GDScript = null

var _failures: Array[String] = []


func _initialize() -> void:
	ConvoType = load("res://scripts/story/LoungeConversation.gd")
	if ConvoType == null or not ConvoType.can_instantiate():
		push_error("[FAIL] LoungeConversation.gd did not compile — suite cannot run.")
		quit(1)
		return
	_test_parse_turn()
	_test_prompt_content()
	_test_transcript_block()
	_test_player_stance_classification()
	_test_agent_disposition()
	_test_bundle_prompt_carries_code_owned_intents()
	_test_parse_bundle_degrades_per_answer()
	_test_answer_relevance_validation()
	_test_hooks_marked_heard_only_on_display()
	_test_lounge_state_keys_are_stable_ids()
	_test_refusal_mechanics_stay_code_owned()
	_test_bundle_transport_is_registered()

	if _failures.is_empty():
		print("[PASS] Lounge conversation tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_parse_turn() -> void:
	var good := JSON.stringify({
		"line": "You fly that thing docked on nine? Bold choice of paint.",
		"r1": "It was cheap.",
		"r2": "The paint stays.",
		"r3": "You should see the other guy.",
	})
	var parsed: Dictionary = ConvoType.parse_turn(good)
	_expect(bool(parsed.get("ok", false)), "Valid turn rejected: %s" % str(parsed.get("reason", "")))
	_expect((parsed.get("replies", []) as Array).size() == 3, "Valid turn lost replies.")
	# Two-option turn (empty r3) is fine.
	var two := JSON.stringify({"line": "Fees went up again.", "r1": "Again?", "r2": "Shocking.", "r3": ""})
	_expect(
		(ConvoType.parse_turn(two).get("replies", []) as Array).size() == 2,
		"Empty r3 should be dropped, not fatal."
	)
	# Wind-down turn: all replies empty, still ok with zero replies.
	var wind := JSON.stringify({"line": "Anyway. My shift calls. Try not to die out there.", "r1": "", "r2": "", "r3": ""})
	var wind_parsed: Dictionary = ConvoType.parse_turn(wind)
	_expect(
		bool(wind_parsed.get("ok", false)) and (wind_parsed.get("replies", []) as Array).is_empty(),
		"Wind-down turn (no replies) should parse ok."
	)
	# Self-tag on the line is stripped.
	var tagged := JSON.stringify({"line": "Ivet: Quiet night. Suspiciously quiet.", "r1": "Agreed.", "r2": "Define quiet.", "r3": ""})
	_expect(
		str(ConvoType.parse_turn(tagged, "Ivet").get("line", "")) == "Quiet night. Suspiciously quiet.",
		"Self-tagged NPC line should lose the name prefix."
	)
	# Rejections: junk, missing line, over-cap replies dropped.
	_expect(not bool(ConvoType.parse_turn("nope").get("ok", false)), "Junk should be rejected.")
	_expect(
		not bool(ConvoType.parse_turn(JSON.stringify({"r1": "hello"})).get("ok", false)),
		"Missing line should be rejected."
	)
	var long_reply := JSON.stringify({
		"line": "Long story short, the audit went badly.",
		"r1": "How badly are we talking here, on a scale of paperwork to airlock?",
		"r2": "Short version?",
		"r3": "",
	})
	_expect(
		(ConvoType.parse_turn(long_reply).get("replies", []) as Array).size() == 1,
		"An over-cap reply (>60 chars) should be dropped, keeping the valid one."
	)


func _test_prompt_content() -> void:
	var npc := {
		"name": "Ivet", "role": "dock controller", "mood": "tired",
		"faction": "aurelia", "station": "Meridian Deck", "extra": "",
	}
	var opener: String = ConvoType.build_opener_prompt(npc, "Campaign tone: dry, wary.")
	_expect(opener.contains("Ivet") and opener.contains("dock controller"), "Opener missing NPC identity.")
	_expect(opener.contains("Campaign tone: dry, wary."), "Opener missing flavor block.")
	_expect(opener.contains("OPENING remark"), "Opener missing the opener instruction.")
	_expect(
		opener.contains("\"line\"") and opener.contains("\"r3\"") and opener.contains("four string keys"),
		"Opener missing the flat line/r1/r2/r3 JSON spec."
	)
	_expect(opener.contains("Never use the pilot's name"), "Opener missing the no-name rule.")
	# L3 hook: an approach instruction replaces the stock opener note.
	var approach: String = ConvoType.build_opener_prompt(npc, "", "The speaker sought the pilot out to pass along a tip.")
	_expect(
		approach.contains("sought the pilot out") and not approach.contains("OPENING remark"),
		"Approach instruction should replace the stock opener note."
	)
	# Reply prompt: transcript + player line + wind-down instruction at 0 left.
	var reply: String = ConvoType.build_reply_prompt(
		npc, "", "NPC: Quiet night.\nYou: Define quiet.", "Define quiet.", 0
	)
	_expect(reply.contains("Quiet night."), "Reply prompt missing transcript.")
	_expect(reply.contains("LAST exchange"), "Reply prompt missing the wind-down instruction at 0 turns left.")
	var mid: String = ConvoType.build_reply_prompt(npc, "", "NPC: Hey.", "Hey yourself.", 1)
	_expect(not mid.contains("LAST exchange"), "Mid-conversation reply prompt must not wind down early.")


func _test_transcript_block() -> void:
	var turns := []
	for i in range(8):
		turns.append({"speaker": "npc" if i % 2 == 0 else "you", "text": "Line %d" % i})
	var block: String = ConvoType.transcript_block(turns, 6)
	_expect(
		not block.contains("Line 0") and not block.contains("Line 1") and block.contains("Line 2"),
		"transcript_block should keep only the last 6 entries."
	)
	_expect(
		block.contains("NPC: Line 2") and block.contains("You: Line 3"),
		"transcript_block speaker labels wrong."
	)


func _test_player_stance_classification() -> void:
	_expect(
		ConvoType.classify_player_stance("What happened out there?") == "curious",
		"Question reply should classify as curious."
	)
	_expect(
		ConvoType.classify_player_stance("No, prove it.") == "pushback",
		"Challenge reply should classify as pushback."
	)
	_expect(
		ConvoType.classify_player_stance("It was cheap.") == "dry",
		"Dry joke reply should classify as dry."
	)
	_expect(
		ConvoType.classify_player_stance("Fair. Thanks.") == "warm",
		"Agreeable reply should classify as warm."
	)
	_expect(
		ConvoType.classify_player_stance("I hear you.") == "engaged",
		"Plain reply should classify as engaged."
	)
	_expect(
		ConvoType.classify_player_stance("   ") == "unknown",
		"Empty reply should classify as unknown."
	)


func _test_agent_disposition() -> void:
	# Sworn enemies refuse outright — no conversation, no rep movement.
	var enemy: Dictionary = ConvoType.agent_disposition(-80.0)
	_expect(
		bool(enemy.get("refuses", false)) and float(enemy.get("completion_rep", 1.0)) == 0.0,
		"Sworn-enemy disposition should refuse with zero rep movement."
	)
	# Hostile: talkable, hard-won completion is worth the most.
	var hostile: Dictionary = ConvoType.agent_disposition(-60.0)
	_expect(
		not bool(hostile.get("refuses", true))
			and float(hostile.get("completion_rep", 0.0)) == 2.0
			and str(hostile.get("context_line", "")).contains("cold"),
		"Hostile disposition wrong: %s" % str(hostile)
	)
	# Neutral middle.
	var neutral: Dictionary = ConvoType.agent_disposition(0.0)
	_expect(
		float(neutral.get("completion_rep", 0.0)) == 1.5
			and float(neutral.get("lead_chance", 0.0)) == 0.15,
		"Neutral disposition wrong: %s" % str(neutral)
	)
	# Friends tip friends: highest lead chance, smallest rep movement.
	var allied: Dictionary = ConvoType.agent_disposition(80.0)
	_expect(
		float(allied.get("lead_chance", 0.0)) == 0.3
			and float(allied.get("completion_rep", 0.0)) == 1.0
			and float(allied.get("bail_rep", -1.0)) == -0.25,
		"Allied disposition wrong: %s" % str(allied)
	)
	# Every talkable tier ships a non-empty context line for the prompt.
	for rep in [-60.0, -10.0, 0.0, 20.0, 60.0]:
		var d: Dictionary = ConvoType.agent_disposition(rep)
		_expect(
			not str(d.get("context_line", "")).strip_edges().is_empty(),
			"Talkable disposition at rep %s missing context_line." % str(rep)
		)


# Phase 9: the bundle prompt carries the code-approved player questions
# verbatim and asks only for opener/answers/close — the model never invents
# the player's side.
func _test_bundle_prompt_carries_code_owned_intents() -> void:
	var npc := {
		"name": "Ivet Marr",
		"role": "cargo inspector",
		"station": "Kova Station",
		"mood": "tired",
		"faction": "zenith",
	}
	var intents := [
		{"id": "ask_convoy_rumor", "text": "What happened to the convoy?"},
		{"id": "ask_local_work", "text": "Anyone hiring around here?"},
		{"id": "", "text": "Malformed intent gets dropped."},
		{"id": "ask_fourth", "text": "Fourth valid intent beyond the cap."},
	]
	var prompt: String = ConvoType.build_bundle_prompt(
		npc, "", intents.slice(0, 2)
	)
	_expect(
		prompt.contains("Q1: \"What happened to the convoy?\"")
			and prompt.contains("Q2: \"Anyone hiring around here?\""),
		"Bundle prompt lost the code-owned player questions."
	)
	_expect(
		prompt.contains("\"opener\": \"...\"")
			and prompt.contains("\"a1\": \"...\"")
			and prompt.contains("\"a2\": \"...\"")
			and not prompt.contains("\"a3\": \"...\"")
			and prompt.contains("\"close\": \"...\""),
		"Bundle prompt key contract does not match the intent count."
	)
	_expect(
		prompt.contains("Ivet Marr") and prompt.contains("cargo inspector"),
		"Bundle prompt lost the NPC identity."
	)
	# Intent normalization: malformed dropped, capped at 3 valid entries.
	var clean: Array = ConvoType.bundle_intents(intents)
	_expect(
		clean.size() == 3
			and str((clean[0] as Dictionary).get("id", "")) == "ask_convoy_rumor"
			and str((clean[2] as Dictionary).get("id", "")) == "ask_fourth",
		"bundle_intents normalization was wrong: %s" % str(clean)
	)
	_expect(
		ConvoType.bundle_intents(
			intents + [{"id": "ask_fifth", "text": "Fifth intent."}]
		).size() == 3,
		"bundle_intents should cap at 3 valid intents."
	)


# Phase 9: each answer slot validates independently — a bad slot degrades to
# "" (that intent is not offered) without sinking the bundle.
func _test_parse_bundle_degrades_per_answer() -> void:
	var good := JSON.stringify({
		"opener": "You picked a strange week to drink here, pilot.",
		"a1": "Convoy went dark past the belt. Nobody's saying why out loud.",
		"a2": "Freight desk is hiring anyone with an intact hull. Low bar.",
		"close": "That's my cue. Watch the belt lanes.",
	})
	var parsed: Dictionary = ConvoType.parse_bundle(good, "Ivet Marr", 2)
	_expect(
		bool(parsed.get("ok", false))
			and int(parsed.get("valid_answer_count", 0)) == 2,
		"Valid bundle rejected: %s" % str(parsed.get("reason", ""))
	)

	# One bad answer degrades that slot only.
	var degraded := JSON.stringify({
		"opener": "You picked a strange week to drink here, pilot.",
		"a1": "x",
		"a2": "Freight desk is hiring anyone with an intact hull. Low bar.",
		"close": "That's my cue. Watch the belt lanes.",
	})
	var degraded_parsed: Dictionary = ConvoType.parse_bundle(degraded, "", 2)
	var answers: Array = degraded_parsed.get("answers", [])
	_expect(
		bool(degraded_parsed.get("ok", false))
			and answers.size() == 2
			and str(answers[0]).is_empty()
			and not str(answers[1]).is_empty(),
		"Per-answer degradation was wrong: %s" % str(degraded_parsed)
	)

	# Duplicate answers: the repeat degrades.
	var repeated := JSON.stringify({
		"opener": "Quiet night. Suspiciously quiet.",
		"a1": "Same answer twice is a lazy model.",
		"a2": "Same answer twice is a lazy model.",
		"close": "Back to work for me.",
	})
	var repeated_parsed: Dictionary = ConvoType.parse_bundle(repeated, "", 2)
	_expect(
		int(repeated_parsed.get("valid_answer_count", 0)) == 1,
		"Duplicate answer was not degraded."
	)

	# No valid answers, missing opener, junk: all fatal.
	var hollow := JSON.stringify({
		"opener": "Quiet night. Suspiciously quiet.",
		"a1": "x",
		"a2": "y",
		"close": "Back to work for me.",
	})
	_expect(
		not bool(ConvoType.parse_bundle(hollow, "", 2).get("ok", true)),
		"Bundle with zero valid answers should be rejected."
	)
	var no_opener := JSON.stringify({
		"a1": "An answer without an opener.",
		"close": "Back to work.",
	})
	_expect(
		str(ConvoType.parse_bundle(no_opener, "", 1).get("reason", ""))
			== "bad_opener",
		"Missing opener should reject the bundle."
	)
	_expect(
		not bool(ConvoType.parse_bundle("{not json", "", 2).get("ok", true)),
		"Junk bundle should be rejected."
	)

	# Self-tagged fields lose the name prefix.
	var tagged := JSON.stringify({
		"opener": "Ivet: Quiet night. Suspiciously quiet.",
		"a1": "Ivet: The convoy story is longer than your patience.",
		"close": "Ivet: Try not to die out there.",
	})
	var tagged_parsed: Dictionary = ConvoType.parse_bundle(tagged, "Ivet", 1)
	_expect(
		str(tagged_parsed.get("opener", "")).begins_with("Quiet night")
			and str((tagged_parsed.get("answers", []) as Array)[0])
				.begins_with("The convoy")
			and str(tagged_parsed.get("close", "")).begins_with("Try not"),
		"Self-tagged bundle fields should lose the name prefix."
	)


# Phase 9: an answer must respond to its paired question (anchor tokens)
# and stay in character; drifting or meta answers degrade to "".
func _test_answer_relevance_validation() -> void:
	var intents := [
		{
			"id": "gap:fact.convoy",
			"text": "I keep hearing about the missing convoy. What's the real story?",
			"anchors": ["convoy"],
		},
		{
			"id": "generic:friendly",
			"text": "How's the station treating you?",
			"anchors": [],
		},
	]
	# Relevant answer + in-character generic: both survive.
	var good := JSON.stringify({
		"opener": "You picked a strange week to drink here, pilot.",
		"a1": "The convoy went dark past the belt. Nobody says why out loud.",
		"a2": "Station treats me fine as long as I keep pouring.",
		"close": "That's my cue. Watch the belt lanes.",
	})
	var parsed: Dictionary = ConvoType.validate_bundle_answers(
		ConvoType.parse_bundle(good, "", 2), intents
	)
	_expect(
		bool(parsed.get("ok", false))
			and int(parsed.get("valid_answer_count", 0)) == 2,
		"Relevant answers were rejected: %s" % str(parsed)
	)

	# Topic drift on the anchored question degrades that slot only.
	var drifting := JSON.stringify({
		"opener": "You picked a strange week to drink here, pilot.",
		"a1": "My cousin brews terrible gin in a maintenance closet.",
		"a2": "Station treats me fine as long as I keep pouring.",
		"close": "That's my cue. Watch the belt lanes.",
	})
	var drift_parsed: Dictionary = ConvoType.validate_bundle_answers(
		ConvoType.parse_bundle(drifting, "", 2), intents
	)
	var drift_answers: Array = drift_parsed.get("answers", [])
	_expect(
		bool(drift_parsed.get("ok", false))
			and str(drift_answers[0]).is_empty()
			and not str(drift_answers[1]).is_empty(),
		"Drifting answer was not degraded: %s" % str(drift_parsed)
	)

	# Out-of-character meta breaks any slot, even a generic one.
	var meta := JSON.stringify({
		"opener": "You picked a strange week to drink here, pilot.",
		"a1": "The convoy went dark past the belt.",
		"a2": "As an AI language model I cannot pour drinks.",
		"close": "That's my cue.",
	})
	var meta_parsed: Dictionary = ConvoType.validate_bundle_answers(
		ConvoType.parse_bundle(meta, "", 2), intents
	)
	var meta_answers: Array = meta_parsed.get("answers", [])
	_expect(
		bool(meta_parsed.get("ok", false))
			and not str(meta_answers[0]).is_empty()
			and str(meta_answers[1]).is_empty(),
		"Out-of-character answer was not degraded: %s" % str(meta_parsed)
	)

	# Every answer drifting sinks the bundle.
	var hollow := JSON.stringify({
		"opener": "You picked a strange week to drink here, pilot.",
		"a1": "My cousin brews terrible gin in a maintenance closet.",
		"a2": "As an AI language model I cannot pour drinks.",
		"close": "That's my cue.",
	})
	_expect(
		not bool(ConvoType.validate_bundle_answers(
			ConvoType.parse_bundle(hollow, "", 2), intents
		).get("ok", true)),
		"A bundle with zero relevant answers should be rejected."
	)

	# Anchor tokens derive from the phrase the question was built around.
	var SelectorType: GDScript = load("res://scripts/story/LoungeIntentSelector.gd")
	var anchors: Array = SelectorType.anchor_tokens("the missing convoy, Route 9")
	_expect(
		anchors.has("convoy") and anchors.has("route") \
			and not anchors.has("the") and not anchors.has("missing"),
		"Anchor token derivation was wrong: %s" % str(anchors)
	)


# Phase 9: a hook is marked heard when its opener DISPLAYS, never while
# merely building the prompt — a failed model call must not burn the hook.
func _test_hooks_marked_heard_only_on_display() -> void:
	var file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect lounge hook-heard wiring.")
	if file == null:
		return
	var source := file.get_as_text()
	var instruction_start := source.find("func _lounge_approach_instruction")
	var instruction_end := source.find("func ", instruction_start + 10)
	var instruction_body := source.substr(
		instruction_start, instruction_end - instruction_start
	)
	_expect(
		not instruction_body.contains("record_lounge_rumor_heard")
			and instruction_body.contains("pending_hook_id"),
		"Approach instruction still marks hooks heard at prompt-build time."
	)
	var result_start := source.find("func _on_lounge_turn_result")
	var result_end := source.find("func ", result_start + 10)
	var result_body := source.substr(result_start, result_end - result_start)
	_expect(
		result_body.contains("pending_hook_id")
			and result_body.contains("record_lounge_rumor_heard"),
		"Displayed opener does not mark the tipped hook as heard."
	)


# Phase 9: warmth, cold-contact state, and once-per-dock rewards key on
# stable NPC IDs, never raw display names; the agent lead is marked heard
# inside the delayed display callback, not when scheduled.
func _test_lounge_state_keys_are_stable_ids() -> void:
	var file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect lounge state keying.")
	if file == null:
		return
	var source := file.get_as_text()
	var completion_start := source.find("func _apply_lounge_completion")
	var completion_end := source.find("func ", completion_start + 10)
	var completion_body := source.substr(
		completion_start, completion_end - completion_start
	)
	_expect(
		completion_body.contains("_stable_lounge_contact_key")
			and not completion_body.contains("contact_key = npc_name"),
		"Once-per-dock completion reward still keys on the raw display name."
	)
	# Phase 9: a completed conversation persists stance + fact IDs into the
	# NPC's structured memory through the GameRoot bridge.
	_expect(
		completion_body.contains("_record_lounge_conversation_memory")
			and source.contains("func _record_lounge_conversation_memory")
			and source.contains("classify_player_stance")
			and source.contains("record_lounge_conversation_memory"),
		"Completed conversations do not persist stance/facts to NPC memory."
	)
	var lead_start := source.find("func _deliver_agent_lead")
	var lead_end := source.find("func ", lead_start + 10)
	var lead_body := source.substr(lead_start, lead_end - lead_start)
	var record_at := lead_body.find("record_lounge_rumor_heard")
	var timer_at := lead_body.find("create_timer")
	_expect(
		record_at > timer_at and timer_at > 0,
		"Agent lead is marked heard before its delayed display."
	)


# Phase 9: whether a refusal occurs and every reputation number stay
# code-owned. The refusal short-circuit must run BEFORE any model request
# in the conversation start path, and rep deltas must come from the
# disposition dict, never from model output.
func _test_refusal_mechanics_stay_code_owned() -> void:
	var file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect refusal wiring.")
	if file == null:
		return
	var source := file.get_as_text()
	var start := source.find("func _start_lounge_conversation")
	var end := source.find("\nfunc ", start + 10)
	var body := source.substr(start, end - start)
	var refusal_at := body.find("agent_disposition.get(\"refuses\"")
	var model_at := body.find("request_lounge_conversation_turn")
	_expect(
		refusal_at > 0 and model_at > refusal_at,
		"Refusal must short-circuit before the model is ever asked."
	)
	_expect(
		source.contains("agent_disposition.get(\"completion_rep\"")
			and source.contains("disposition.get(\"bail_rep\""),
		"Reputation deltas no longer come from the code-owned disposition."
	)


# Phase 9: the bundle transport exists on the small model with a background
# timeout and enough token room for opener + answers + close.
func _test_bundle_transport_is_registered() -> void:
	var gateway: GDScript = load("res://scripts/ai/LocalModelGateway.gd")
	_expect(
		str(gateway.profile_for_capability("lounge_bundle"))
			== "small_dialogue",
		"lounge_bundle must run on the small dialogue model."
	)
	_expect(
		float(gateway.request_timeout("lounge_bundle")) == 25.0,
		"lounge_bundle needs its background prefetch timeout."
	)
	var llm_file := FileAccess.open("res://scripts/LLMInterface.gd", FileAccess.READ)
	_expect(llm_file != null, "Could not inspect bundle transport.")
	if llm_file == null:
		return
	var source := llm_file.get_as_text()
	_expect(
		source.contains("func request_lounge_exchange_bundle")
			and source.contains("\"lounge_bundle\"")
			and source.contains("\"num_predict\": 520"),
		"Bundle transport is missing or lost its five-field token budget."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
