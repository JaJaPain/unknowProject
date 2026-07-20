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
	_test_fresh_bundle_review_protocol()
	_test_stranger_intel_becomes_a_real_fact()
	_test_stranger_deal_stays_code_owned_and_leak_free()
	_test_bundle_preparation_wiring()
	_test_docking_prefetches_lounge_bundles()
	_test_pending_bundle_cards_block_live_generation()
	_test_bundle_consumption_is_model_free()
	_test_keep_talking_requires_cached_second_bundle()

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
	_expect(
		str(gateway.profile_for_capability("lounge_bundle_review")) == "small_dialogue"
			and float(gateway.request_timeout("lounge_bundle_review")) == 12.0
			and source.contains("func request_lounge_exchange_bundle_review"),
		"Fresh lounge-bundle review transport is not registered."
	)


func _test_fresh_bundle_review_protocol() -> void:
	var prompt: String = ConvoType.build_bundle_review_prompt(
		"Ivet",
		[{"id": "gap:ore", "text": "What happened to the ore convoy?"}],
		{
			"opener": "The manifests have been nervous all night.",
			"answers": ["It missed its route, and nobody is saying why."],
			"close": "My shift is calling me back.",
		}
	)
	_expect(
		prompt.contains("Q1: What happened to the ore convoy?")
			and prompt.contains("Candidate opener")
			and not prompt.contains("Campaign flavor"),
		"Fresh reviewer prompt is missing the candidate/question artifact boundary."
	)
	_expect(
		ConvoType.parse_bundle_review("{\"verdict\":\"approve\"}")
			and not ConvoType.parse_bundle_review("{\"verdict\":\"reject\"}")
			and not ConvoType.parse_bundle_review("not json"),
		"Bundle reviewer approval parser is too permissive or rejects valid approval."
	)


# Phase 9: the stranger's paid intel lands in the knowledge ledger as a
# rumored fact with a real ID and public text — never a free-form string
# appended to pending_hooks.
func _test_stranger_intel_becomes_a_real_fact() -> void:
	var sm = root.get_node_or_null("StoryManager")
	_expect(sm != null, "StoryManager autoload unavailable.")
	if sm == null:
		return
	var snapshot: Dictionary = (sm.story_state as Dictionary).duplicate(true)
	var hooks_before: Array = (
		sm.story_state.get("pending_hooks", []) as Array
	).duplicate(true)
	var result: Dictionary = sm.record_stranger_intel_fact("Kova Station")
	var fact_id := str(result.get("fact_id", ""))
	_expect(
		bool(result.get("ok", false))
			and fact_id.begins_with("fact.stranger_intel."),
		"Stranger intel did not produce a real fact ID: %s" % str(result)
	)
	var states: Dictionary = sm.story_state.get("knowledge_states", {})
	var record: Dictionary = states.get(fact_id, {}) \
		if states.get(fact_id, {}) is Dictionary else {}
	_expect(
		str(record.get("state", "")) == "rumored"
			and str(record.get("public_text", "")).contains("Kova Station")
			and str(record.get("alias", "")) == "the stranger's tip",
		"Stranger intel fact record was wrong: %s" % str(record)
	)
	_expect(
		sm.story_state.get("pending_hooks", []) == hooks_before,
		"Stranger intel leaked into pending_hooks."
	)
	sm.story_state = snapshot
	# And the old free-form append is gone from the deal resolution.
	var file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect stranger deal wiring.")
	if file == null:
		return
	var source := file.get_as_text()
	_expect(
		not source.contains("hooks.append(\"a paid tip")
			and source.contains("record_stranger_intel_fact"),
		"Stranger deal still appends free-form strings to pending_hooks."
	)


# Phase 9: the stranger deal's numbers stay code-owned (roll, ask, scam,
# haggle, payouts) and the pitch prompt reads only code-owned deal fields
# plus the player-safe ambient flavor block — never story_state directly.
func _test_stranger_deal_stays_code_owned_and_leak_free() -> void:
	var file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect stranger deal wiring.")
	if file == null:
		return
	var source := file.get_as_text()
	var roll_start := source.find("func _roll_lounge_stranger")
	var roll_end := source.find("\nfunc ", roll_start + 10)
	var roll_body := source.substr(roll_start, roll_end - roll_start)
	_expect(
		roll_body.contains("\"ask\"")
			and roll_body.contains("\"is_scam\"")
			and not roll_body.contains("LLMInterface"),
		"Stranger deal terms are no longer rolled code-side."
	)
	var pitch_start := source.find("func _on_stranger_card_pressed")
	var pitch_end := source.find("\nfunc ", pitch_start + 10)
	var pitch_body := source.substr(pitch_start, pitch_end - pitch_start)
	_expect(
		not pitch_body.contains("story_state")
			and pitch_body.contains("_lounge_flavor_block"),
		"Stranger pitch prompt reads story state outside the safe flavor block."
	)
	var resolve_start := source.find("func _resolve_stranger_deal")
	var resolve_end := source.find("\nfunc ", resolve_start + 10)
	var resolve_body := source.substr(resolve_start, resolve_end - resolve_start)
	_expect(
		resolve_body.contains("spend_credits")
			and resolve_body.contains("add_credits")
			and not resolve_body.contains("LLMInterface"),
		"Stranger deal outcomes are no longer resolved code-side."
	)


# Phase 9: bundles are prepared in the background when the lounge renders,
# validated with the full parse + relevance pipeline, and cached per stable
# contact key with the session state.
func _test_bundle_preparation_wiring() -> void:
	var file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect bundle preparation wiring.")
	if file == null:
		return
	var source := file.get_as_text()
	_expect(
		source.contains("func _prepare_lounge_exchange_bundle")
			and source.contains("request_lounge_exchange_bundle")
			and source.contains("LoungeIntentSelectorType.select_intents")
			and source.contains("_lounge_intent_context"),
		"Bundle preparation does not select code-owned intents and dispatch."
	)
	var result_start := source.find("func _on_lounge_bundle_result")
	var result_end := source.find("\nfunc ", result_start + 10)
	var result_body := source.substr(result_start, result_end - result_start)
	_expect(
		result_body.contains("parse_bundle")
			and result_body.contains("validate_bundle_answers")
			and result_body.contains("record_fallback"),
		"Bundle results skip the parse/relevance pipeline or fail silently."
	)
	_expect(
		source.contains("_lounge_bundle_cache.clear()"),
		"Bundle cache is not reset with the dock session state."
	)
	# Only rumored facts feed the knowledge-gap context.
	var context_start := source.find("func _lounge_intent_context")
	var context_end := source.find("\nfunc ", context_start + 10)
	var context_body := source.substr(context_start, context_end - context_start)
	_expect(
		context_body.contains("!= \"rumored\"")
			or context_body.contains("== \"rumored\""),
		"Intent context does not restrict knowledge gaps to rumored facts."
	)


# Phase 9: a ready bundle is consumed with zero model requests — the
# conversation start prefers it, the intent press only displays prepared
# text, degraded slots are never offered, and learned gap facts land on
# the conversation for NPC memory.
# Phase 9: a card whose exchange is still being prepared must advertise that
# state before selection and block the old live-generation fallback. The
# result callback redraws the visible cards when readiness changes.
# Phase 9: the docking fade begins predictable lounge preparation and keeps
# the Lounge entry disabled during its short arrival beat.
func _test_docking_prefetches_lounge_bundles() -> void:
	var file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect lounge docking-prefetch wiring.")
	if file == null:
		return
	var source := file.get_as_text()
	var dock_fn := source.find("func toggle_dock_menu")
	var dock_end := source.find("\nfunc ", dock_fn + 10)
	var dock_body := source.substr(dock_fn, dock_end - dock_fn)
	_expect(
		dock_body.contains("_begin_lounge_dock_preparation()"),
		"A fresh dock does not start lounge bundle preparation."
	)
	var prepare_fn := source.find("func _begin_lounge_dock_preparation")
	var prepare_end := source.find("\nfunc ", prepare_fn + 10)
	var prepare_body := source.substr(prepare_fn, prepare_end - prepare_fn)
	_expect(
		prepare_body.contains("_prepare_lounge_bundles_for_docked_station()")
			and prepare_body.contains("LOUNGE_DOCK_PREPARE_SECONDS")
			and prepare_body.contains("create_timer"),
		"Docking preparation does not prefetch bundles over a bounded arrival beat."
	)
	_expect(
		source.contains("station_lounge_btn.disabled = _lounge_dock_preparation_active"),
		"The Lounge can be entered before the docking preparation window ends."
	)
	var prefetch_fn := source.find("func _prepare_lounge_bundles_for_docked_station")
	var prefetch_end := source.find("\nfunc ", prefetch_fn + 10)
	var prefetch_body := source.substr(prefetch_fn, prefetch_end - prefetch_fn)
	_expect(
		prefetch_body.contains("_lounge_bartender_card")
			and prefetch_body.contains("_lounge_station_agent_cards")
			and prefetch_body.contains("_prepare_lounge_exchange_bundle"),
		"Docking preparation does not cover predictable lounge contacts."
	)


func _test_pending_bundle_cards_block_live_generation() -> void:
	var file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect pending lounge-card wiring.")
	if file == null:
		return
	var source := file.get_as_text()
	var card_fn := source.find("func _add_lounge_contact_card")
	var card_end := source.find("\nfunc ", card_fn + 10)
	var card_body := source.substr(card_fn, card_end - card_fn)
	_expect(
		card_body.contains("_lounge_bundle_status")
			and card_body.contains("PREPARING CONVERSATION"),
		"Lounge cards do not visibly identify a pending exchange before selection."
	)
	var buttons_fn := source.find("func _add_lounge_card_buttons")
	var buttons_end := source.find("\nfunc ", buttons_fn + 10)
	var buttons_body := source.substr(buttons_fn, buttons_end - buttons_fn)
	_expect(
		buttons_body.contains("primary.disabled = true")
			and buttons_body.contains("bundle_status in [\"pending\", \"failed\"]"),
		"Pending or failed bundle cards remain actionable into a live wait."
	)
	var start_fn := source.find("func _start_lounge_conversation")
	var start_end := source.find("\nfunc ", start_fn + 10)
	var start_body := source.substr(start_fn, start_end - start_fn)
	var guard_at := start_body.find("if _lounge_bundle_supported(card)")
	var request_at := start_body.find("request_lounge_conversation_turn")
	_expect(
		guard_at >= 0 and request_at > guard_at,
		"A stale pending lounge-card input can still start live generation."
	)
	_expect(
		source.contains("func _refresh_lounge_cards_after_bundle_result")
			and source.contains("call_deferred(\"_render_station_contacts\", true)"),
		"Ready lounge bundles do not refresh their cards into an actionable state."
	)


func _test_bundle_consumption_is_model_free() -> void:
	var file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect bundle consumption wiring.")
	if file == null:
		return
	var source := file.get_as_text()
	var start_fn := source.find("func _start_lounge_conversation")
	var bundle_branch := source.find(
		"_start_lounge_bundle_conversation", start_fn
	)
	var live_request := source.find(
		"request_lounge_conversation_turn", start_fn
	)
	_expect(
		bundle_branch > start_fn and live_request > bundle_branch,
		"Conversation start does not prefer a ready bundle over a live call."
	)
	for fn_name in [
		"func _start_lounge_bundle_conversation",
		"func _on_lounge_bundle_intent_pressed",
	]:
		var fn_start := source.find(fn_name)
		var fn_end := source.find("\nfunc ", fn_start + 10)
		var body := source.substr(fn_start, fn_end - fn_start)
		_expect(
			not body.contains("LLMInterface")
				and not body.contains("request_lounge"),
			"%s must never touch the model." % fn_name
		)
	var press_start := source.find("func _on_lounge_bundle_intent_pressed")
	var press_end := source.find("\nfunc ", press_start + 10)
	var press_body := source.substr(press_start, press_end - press_start)
	_expect(
		press_body.contains("learned_fact_ids")
			and press_body.contains("_apply_lounge_completion"),
		"Intent press does not record learned facts or complete the chat."
	)
	var start_body_end := source.find(
		"\nfunc ", source.find("func _start_lounge_bundle_conversation") + 10
	)
	var start_body := source.substr(
		source.find("func _start_lounge_bundle_conversation"),
		start_body_end - source.find("func _start_lounge_bundle_conversation")
	)
	_expect(
		start_body.contains("is_empty()")
			and start_body.contains("continue"),
		"Degraded answer slots are still offered as questions."
	)


# Phase 9: one meaningful reply per bundle; "Keep talking" appears only
# for warm contacts AND only when the second bundle is already ready —
# extended conversation must never reintroduce a visible wait.
func _test_keep_talking_requires_cached_second_bundle() -> void:
	var file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	_expect(file != null, "Could not inspect keep-talking wiring.")
	if file == null:
		return
	var source := file.get_as_text()
	var start_fn := source.find("func _start_lounge_bundle_conversation")
	var start_end := source.find("\nfunc ", start_fn + 10)
	var start_body := source.substr(start_fn, start_end - start_fn)
	_expect(
		start_body.contains("_prepare_lounge_exchange_bundle"),
		"Consuming a bundle does not start preparing the second one."
	)
	var press_fn := source.find("func _on_lounge_bundle_intent_pressed")
	var press_end := source.find("\nfunc ", press_fn + 10)
	var press_body := source.substr(press_fn, press_end - press_fn)
	var warmth_at := press_body.find("warmth >= 2")
	var ready_at := press_body.find("== \"ready\"")
	var keep_at := press_body.find("Keep talking")
	_expect(
		warmth_at > 0 and ready_at > 0 and keep_at > warmth_at,
		"Keep talking is not gated on warmth plus an already-ready bundle."
	)
	_expect(
		not press_body.contains("request_lounge"),
		"Keep talking must never trigger a live model request."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
