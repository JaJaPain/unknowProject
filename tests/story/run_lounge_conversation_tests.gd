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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
