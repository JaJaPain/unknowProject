class_name LoungeConversation
extends RefCounted

# Lounge Social Layer, Phase L1 (docs/plan_lounge_social_layer.md).
# Pure protocol layer for two-way lounge conversations: prompt building and
# response parsing only — no scene access, no network, fully unit-testable.
# UIManager owns the turn state; LLMInterface owns transport; code owns all
# consequences. The model ONLY writes dialogue text.
#
# Output protocol is FLAT four-key JSON ({"line","r1","r2","r3"}) — nested
# shapes and freeform both proven broken on qwen3:4b (see
# AmbientChatGenerator.build_prompt live-fire note, 2026-07-04).

const AmbientChatType := preload("res://scripts/story/AmbientChatGenerator.gd")

# Opener + up to 2 player replies, then the NPC winds it down. Bar chats are
# short; leaving them wanting more beats a model running out of ideas.
const MAX_TURNS := 3

const LINE_MIN := 4
const LINE_MAX := 220
const REPLY_MIN := 2
const REPLY_MAX := 60


static func _shared_rules(npc: Dictionary, flavor_block: String) -> Array:
	var flavor_section := ""
	if not flavor_block.strip_edges().is_empty():
		flavor_section = (
			"Campaign flavor (background mood only — never quote or summarize it):\n"
			+ flavor_block.strip_edges() + "\n"
		)
	return [
		"You are writing one side of a casual bar conversation in a space trading",
		"game, PG-13, dry and slightly dark humor welcome.",
		"",
		"The speaker: %s, a %s, at the station lounge %s." % [
			str(npc.get("name", "a local")),
			str(npc.get("role", "station regular")),
			str(npc.get("station", "on this station")),
		],
		"Mood: %s. Affiliation: %s." % [
			str(npc.get("mood", "neutral")),
			str(npc.get("faction", "independent")),
		],
		str(npc.get("extra", "")),
		"",
		flavor_section,
		"Rules:",
		"- The speaker talks TO the pilot sitting next to them. Casual, specific, human.",
		"- Never use the pilot's name. No narration, no stage directions, no meta.",
		"- No new lore inventions: no new faction names, no new station names.",
		"- r1-r3 are SHORT things the PILOT could say back (under 8 words each),",
		"  plain voice, tonally distinct: one friendly or curious, one dry pushback,",
		"  the third can be odd or funny. Set r3 to \"\" for only two options.",
		"",
		"Return only JSON with exactly these four string keys and nothing else:",
		"{\"line\": \"what the speaker says\", \"r1\": \"...\", \"r2\": \"...\", \"r3\": \"...\"}",
	]


static func build_opener_prompt(
	npc: Dictionary,
	flavor_block: String,
	approach_instruction: String = ""
) -> String:
	var lines := _shared_rules(npc, flavor_block)
	var opener_note := (
		"Write the speaker's OPENING remark to the pilot — the kind of thing a "
		+ "regular says to whoever sits down next to them. Under 30 words."
	)
	if not approach_instruction.strip_edges().is_empty():
		# Phase L3 hook: the NPC sought the player out and opens with intent.
		opener_note = approach_instruction.strip_edges()
	lines.insert(lines.size() - 3, "")
	lines.insert(lines.size() - 3, opener_note)
	return "\n".join(lines)


static func build_reply_prompt(
	npc: Dictionary,
	flavor_block: String,
	transcript: String,
	player_reply: String,
	turns_left: int
) -> String:
	var lines := _shared_rules(npc, flavor_block)
	var continue_note := (
		"Conversation so far:\n%s\nThe pilot just said: \"%s\"\n" % [transcript, player_reply.strip_edges()]
		+ "Write the speaker's natural response. Under 30 words."
	)
	if turns_left <= 0:
		continue_note += (
			" This is the LAST exchange: the speaker wraps up naturally (finishes "
			+ "their drink, spots someone, gets back to work). Set r1, r2, and r3 "
			+ "ALL to \"\"."
		)
	lines.insert(lines.size() - 3, "")
	lines.insert(lines.size() - 3, continue_note)
	return "\n".join(lines)


# Parses one turn's flat JSON into {ok, line, replies, reason}. Empty reply
# slots are dropped (a wind-down turn legitimately has none). The NPC line is
# required; self-tags and wrapping quotes are stripped like ambient chat.
static func parse_turn(inner_json_text: String, npc_name: String = "") -> Dictionary:
	var parser := JSON.new()
	if parser.parse(inner_json_text.strip_edges()) != OK:
		return {"ok": false, "reason": "inner_parse_failed"}
	var data: Variant = parser.get_data()
	if not data is Dictionary:
		return {"ok": false, "reason": "not_an_object"}
	var normalized := {}
	for key in (data as Dictionary).keys():
		normalized[str(key).strip_edges().to_lower()] = (data as Dictionary)[key]
	var line := str(normalized.get("line", "")).strip_edges()
	line = AmbientChatType._strip_speaker_prefix(line, npc_name, "")
	if line.length() < LINE_MIN or line.length() > LINE_MAX:
		return {"ok": false, "reason": "bad_line_length"}
	var replies: Array = []
	for slot in ["r1", "r2", "r3"]:
		var reply := str(normalized.get(slot, "")).strip_edges()
		reply = reply.trim_prefix("\"").trim_suffix("\"").strip_edges()
		if reply.length() < REPLY_MIN or reply.length() > REPLY_MAX:
			continue
		replies.append(reply)
	return {"ok": true, "line": line, "replies": replies}


static func classify_player_stance(reply_text: String) -> String:
	var clean := reply_text.strip_edges()
	if clean.is_empty():
		return "unknown"
	var lower := clean.to_lower()
	if lower.contains("why") \
			or lower.contains("what") \
			or lower.contains("how") \
			or lower.contains("?") \
			or lower.contains("tell me") \
			or lower.contains("explain"):
		return "curious"
	if lower.contains("no") \
			or lower.contains("not") \
			or lower.contains("prove") \
			or lower.contains("wrong") \
			or lower.contains("seriously") \
			or lower.contains("come on"):
		return "pushback"
	if lower.contains("thanks") \
			or lower.contains("appreciate") \
			or lower.contains("fair") \
			or lower.contains("agreed"):
		return "warm"
	if lower.contains("ha") \
			or lower.contains("funny") \
			or lower.contains("joke") \
			or lower.contains("other guy") \
			or lower.contains("cheap"):
		return "dry"
	return "engaged"


# ── Phase L5a: agent social checks ───────────────────────────────────────────
# How a faction agent receives the player at a given reputation. Pure and
# code-owned: the model gets context_line as flavor; the NUMBERS never come
# from the model. Gentle by design — social texture, not a rep farm.
static func agent_disposition(rep: float) -> Dictionary:
	var tier: String = GlobalState.reputation_tier(rep)
	match tier:
		"sworn enemy":
			return {
				"tier": tier, "refuses": true,
				"context_line": "",
				"completion_rep": 0.0, "bail_rep": 0.0, "lead_chance": 0.0,
			}
		"hostile", "unfriendly":
			return {
				"tier": tier, "refuses": false,
				"context_line": (
					"The speaker's faction reads this pilot as %s — openly cold, " % tier
					+ "professional at best; any thaw must be earned inside the conversation."
				),
				"completion_rep": 2.0, "bail_rep": -0.5, "lead_chance": 0.05,
			}
		"friendly", "trusted", "allied":
			return {
				"tier": tier, "refuses": false,
				"context_line": (
					"The speaker's faction reads this pilot as %s — relaxed, candid, " % tier
					+ "the good chair gets pulled out."
				),
				"completion_rep": 1.0, "bail_rep": -0.25, "lead_chance": 0.3,
			}
		_:
			# wary / neutral / cordial — the workaday middle.
			return {
				"tier": tier, "refuses": false,
				"context_line": (
					"The speaker's faction reads this pilot as %s — polite, measured, " % tier
					+ "keeping score without saying so."
				),
				"completion_rep": 1.5, "bail_rep": -0.5, "lead_chance": 0.15,
			}


# ── Phase 9: pre-generated exchange bundles ──────────────────────────────────
# One model call prepares the whole exchange up front: opener, one NPC answer
# per code-approved player intent, and a natural close. Reply clicks then
# consume prepared text — the model is never consulted mid-conversation.
# Flat one-level JSON only (same qwen3 constraint as parse_turn).

const OPENER_MIN := 4
const OPENER_MAX := 220
const ANSWER_MIN := 4
const ANSWER_MAX := 220
const CLOSE_MIN := 4
const CLOSE_MAX := 160
const BUNDLE_MAX_INTENTS := 3
const _BAD_LOUNGE_OPENER_PREFIXES: Array = [
	"hey", "listen", "pilot,", "pilot's question", "so, you're asking",
	"you're asking", "i've got the latest", "another one",
]


# `intents`: 2-3 code-approved player questions, [{id, text}]. Code owns the
# questions; the model only writes the opener, each paired answer, and the
# close. Extra intents beyond BUNDLE_MAX_INTENTS are ignored.
static func build_bundle_prompt(
	npc: Dictionary,
	flavor_block: String,
	intents: Array
) -> String:
	var flavor_section := ""
	if not flavor_block.strip_edges().is_empty():
		flavor_section = (
			"Campaign flavor (background mood only — never quote or summarize it):\n"
			+ flavor_block.strip_edges() + "\n"
		)
	var clean_intents := bundle_intents(intents)
	var continuity_notes := str(npc.get("extra", "")).strip_edges()
	var lines: Array = [
		"You are writing one side of a casual bar conversation in a space trading",
		"game, PG-13, dry and slightly dark humor welcome.",
		"",
		"The speaker: %s, a %s, at the station lounge %s." % [
			str(npc.get("name", "a local")),
			str(npc.get("role", "station regular")),
			str(npc.get("station", "on this station")),
		],
		"Mood: %s. Affiliation: %s." % [
			str(npc.get("mood", "neutral")),
			str(npc.get("faction", "independent")),
		],
		"",
		flavor_section,
		"The pilot sitting next to them may ask these questions:",
	]
	if not continuity_notes.is_empty():
		lines.append("Continuity notes: use these subtly; never recite them as a recap.")
		lines.append(continuity_notes)
		lines.append("")
	for i in range(clean_intents.size()):
		lines.append("Q%d: \"%s\"" % [i + 1, str(clean_intents[i].get("text", ""))])
		var answer_anchors: Array = clean_intents[i].get("answer_anchors", []) \
			if clean_intents[i].get("answer_anchors", []) is Array else []
		if not answer_anchors.is_empty():
			lines.append("Required answer words for Q%d: %s." % [
				i + 1, ", ".join(answer_anchors)
			])
	var opener_anchors: Array[String] = _bundle_intent_anchors(clean_intents)
	if not opener_anchors.is_empty():
		lines.append("Topic words the opener must naturally name: %s." % ", ".join(opener_anchors))
	lines.append("")
	lines.append("Write:")
	lines.append(
		"- opener: the speaker's OPENING remark to the pilot — the kind of thing"
	)
	lines.append(
		"  a regular says to whoever sits down next to them. Under 30 words."
	)
	for i in range(clean_intents.size()):
		lines.append(
			"- a%d: the speaker's direct answer to Q%d. It must actually answer"
			% [i + 1, i + 1]
		)
		lines.append(
			"  that question, in character, with one concrete observation or personal"
		)
		lines.append("  angle. Under 35 words.")
	lines.append(
		"- close: the speaker wrapping up naturally afterwards (finishes their"
	)
	lines.append(
		"  drink, spots someone, gets back to work). Under 25 words."
	)
	lines.append("")
	lines.append("Rules:")
	lines.append(
		"- The speaker talks TO the pilot. It must sound like a normal spontaneous"
	)
	lines.append("  conversation, not an interview, quest briefing, dialogue menu, or terminal.")
	lines.append(
		"- Give the opener a small human observation, complaint, or joke that leaves"
	)
	lines.append("  room for the pilot to reply; do not open by listing services or asking a survey question.")
	lines.append("- Never open with \"Hey, listen\", \"Listen\", or a close variation. It sounds like an interruption, not lounge conversation.")
	lines.append("- Do not begin by repeating or announcing the pilot's question. Do not use a bare \"Hey\" opener.")
	if not opener_anchors.is_empty():
		lines.append(
			"- The opener must naturally include at least one Topic word above. A generic drink, weather, or greeting opener is not enough."
		)
	lines.append("- Only discuss the supplied topic. Never invent ship names, people, colonies, planets, companies, dates, disasters, or prior events as facts.")
	lines.append(
		"- The close must feel like a believable end to a short chat, not a stock"
	)
	lines.append("  sign-off. It should work after any one of the possible answers.")
	lines.append(
		"- If continuity notes say the pilot is known, make that recognition feel"
	)
	lines.append("  incidental. Do not summarize their relationship or repeat a previous conversation.")
	lines.append(
		"- Never use the pilot's name. No narration, no stage directions, no meta."
	)
	lines.append(
		"- No new lore inventions: no new faction names, no new station names."
	)
	lines.append("")
	var keys: Array = ["\"opener\": \"...\""]
	for i in range(clean_intents.size()):
		keys.append("\"a%d\": \"...\"" % (i + 1))
	keys.append("\"close\": \"...\"")
	lines.append(
		"Return only JSON with exactly these string keys and nothing else:"
	)
	lines.append("{%s}" % ", ".join(keys))
	return "\n".join(lines)


# Normalizes an intents array to at most BUNDLE_MAX_INTENTS well-formed
# {id, text} entries, dropping blanks.
static func bundle_intents(intents: Array) -> Array:
	var clean: Array = []
	for raw_intent in intents:
		if not raw_intent is Dictionary:
			continue
		var intent: Dictionary = raw_intent
		var text := str(intent.get("text", "")).strip_edges()
		var id := str(intent.get("id", "")).strip_edges()
		if text.is_empty() or id.is_empty():
			continue
		var anchors: Array = intent.get("anchors", []) \
			if intent.get("anchors", []) is Array else []
		var answer_anchors: Array = intent.get("answer_anchors", []) \
			if intent.get("answer_anchors", []) is Array else []
		clean.append({
			"id": id,
			"text": text,
			"anchors": anchors.duplicate(),
			"answer_anchors": answer_anchors.duplicate(),
		})
		if clean.size() >= BUNDLE_MAX_INTENTS:
			break
	return clean


# The reviewer sees only this candidate artifact and the code-approved player
# questions. It does not receive the writer's prompt or response context, so
# approval is a separate fresh judgement rather than self-confirmation.
static func build_bundle_review_prompt(
	npc_name: String,
	intents: Array,
	bundle: Dictionary
) -> String:
	var lines: Array = [
		"You are a strict dialogue editor for a PG-13 space trading game.",
		"Review the candidate exchange below. Approve only if every included",
		"answer directly responds to its paired question, the speaker stays in",
		"character, and there are no invented proper nouns, meta commentary,",
		"stage directions, or player dialogue written as NPC dialogue. Reject",
		"anything that reads like a dialogue menu, quest briefing, customer-service",
		"script, interview, generic greeting, or stock sign-off instead of a normal",
		"short conversation between two people.",
		"Speaker: %s." % npc_name,
		"Candidate opener: %s" % str(bundle.get("opener", "")),
	]
	var answers: Array = bundle.get("answers", []) if bundle.get("answers", []) is Array else []
	for i in range(mini(intents.size(), answers.size())):
		lines.append("Q%d: %s" % [i + 1, str((intents[i] as Dictionary).get("text", ""))])
		lines.append("A%d: %s" % [i + 1, str(answers[i])])
	lines.append("Candidate close: %s" % str(bundle.get("close", "")))
	lines.append("Return only JSON: {\"verdict\":\"approve\"} or {\"verdict\":\"reject\"}.")
	return "\n".join(lines)


static func parse_bundle_review(inner_json_text: String) -> bool:
	var parser := JSON.new()
	var candidate := inner_json_text.strip_edges()
	if parser.parse(candidate) != OK:
		# Ollama occasionally returns an otherwise complete one-field verdict
		# without its final brace. Repair only that harmless terminal omission;
		# malformed keys, values, or extra prose still fail strict JSON parsing.
		if candidate.begins_with("{") and not candidate.ends_with("}"):
			candidate += "}"
		if parser.parse(candidate) != OK:
			return false
	var data: Variant = parser.get_data()
	return data is Dictionary and str((data as Dictionary).get("verdict", "")).to_lower() == "approve"


# Parses a prepared exchange bundle. Every answer slot validates
# independently: a bad slot degrades to "" (that intent simply is not
# offered) rather than sinking the bundle. The bundle needs a valid opener,
# a valid close, and at least one valid answer.
static func parse_bundle(
	inner_json_text: String,
	npc_name: String,
	intent_count: int
) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(inner_json_text.strip_edges()) != OK:
		return {"ok": false, "reason": "inner_parse_failed"}
	var data: Variant = parser.get_data()
	if not data is Dictionary:
		return {"ok": false, "reason": "not_an_object"}
	var normalized := {}
	for key in (data as Dictionary).keys():
		normalized[str(key).strip_edges().to_lower()] = (data as Dictionary)[key]
	var opener := _clean_bundle_field(
		str(normalized.get("opener", "")), npc_name
	)
	if opener.length() < OPENER_MIN or opener.length() > OPENER_MAX:
		return {"ok": false, "reason": "bad_opener"}
	if not _is_natural_lounge_opener(opener):
		return {"ok": false, "reason": "unnatural_opener"}
	var close := _clean_bundle_field(
		str(normalized.get("close", "")), npc_name
	)
	if close.length() < CLOSE_MIN or close.length() > CLOSE_MAX:
		return {"ok": false, "reason": "bad_close"}
	var answers: Array = []
	var valid_count := 0
	var wanted: int = clampi(intent_count, 1, BUNDLE_MAX_INTENTS)
	for i in range(wanted):
		var answer := _clean_bundle_field(
			str(normalized.get("a%d" % (i + 1), "")), npc_name
		)
		if answer.length() < ANSWER_MIN or answer.length() > ANSWER_MAX \
				or answer == opener or answers.has(answer):
			answers.append("")
			continue
		answers.append(answer)
		valid_count += 1
	if valid_count < 1:
		return {"ok": false, "reason": "no_valid_answers"}
	return {
		"ok": true,
		"opener": opener,
		"answers": answers,
		"valid_answer_count": valid_count,
		"close": close,
	}


static func _clean_bundle_field(raw: String, npc_name: String) -> String:
	var clean := raw.strip_edges()
	clean = clean.trim_prefix("\"").trim_suffix("\"").strip_edges()
	return AmbientChatType._strip_speaker_prefix(clean, npc_name, "")


static func _is_natural_lounge_opener(opener: String) -> bool:
	var clean := opener.to_lower().strip_edges()
	if clean.ends_with("—") or clean.ends_with("-"):
		return false
	for prefix in _BAD_LOUNGE_OPENER_PREFIXES:
		if clean.begins_with(str(prefix)):
			return false
	return true


const _OUT_OF_CHARACTER_MARKERS: Array = [
	"as an ai",
	"language model",
	"cannot assist",
	"i can't help with",
]


# Phase 9 relevance pass, run after parse_bundle: each answer must respond
# to its paired question and stay in character. Anchored intents require at
# least one topic token in the answer; anchor-less generics accept any
# in-character reply. Failing answers degrade to "" like structural
# failures; a bundle with no relevant answers is rejected.
static func validate_bundle_answers(
	parsed: Dictionary,
	intents: Array,
	require_opener_grounding: bool = false
) -> Dictionary:
	if not bool(parsed.get("ok", false)):
		return parsed
	var clean_intents := bundle_intents(intents)
	if require_opener_grounding \
			and not _opener_hits_any_intent_anchor(
				str(parsed.get("opener", "")), clean_intents
			):
		return {"ok": false, "reason": "opener_missing_topic_anchor"}
	var answers: Array = (parsed.get("answers", []) as Array).duplicate()
	var valid_count := 0
	var requires_topic_answer := false
	var has_valid_topic_answer := false
	for i in range(answers.size()):
		var answer := str(answers[i])
		if answer.is_empty():
			continue
		var keeps := _answer_in_character(answer)
		var intent_has_anchors := false
		if keeps and i < clean_intents.size():
			var intent: Dictionary = clean_intents[i]
			var intent_anchors: Array = intent.get("answer_anchors", []) \
				if intent.get("answer_anchors", []) is Array else []
			if intent_anchors.is_empty():
				intent_anchors = intent.get("anchors", []) \
					if intent.get("anchors", []) is Array else []
			intent_has_anchors = not intent_anchors.is_empty()
			if intent_has_anchors:
				requires_topic_answer = true
				keeps = _answer_hits_anchors(answer, intent_anchors)
		if keeps:
			valid_count += 1
			if intent_has_anchors:
				has_valid_topic_answer = true
		else:
			answers[i] = ""
	if requires_topic_answer and not has_valid_topic_answer:
		return {"ok": false, "reason": "no_relevant_topic_answer"}
	if valid_count < 1:
		return {"ok": false, "reason": "no_relevant_answers"}
	var result := parsed.duplicate(true)
	result["answers"] = answers
	result["valid_answer_count"] = valid_count
	return result


static func _opener_hits_any_intent_anchor(opener: String, intents: Array) -> bool:
	var anchors := _bundle_intent_anchors(intents)
	if anchors.is_empty():
		return true
	var lower := opener.to_lower()
	for anchor in anchors:
		if lower.contains(str(anchor)):
			return true
	return false


static func _bundle_intent_anchors(intents: Array) -> Array[String]:
	var anchors: Array[String] = []
	for raw_intent in intents:
		if not raw_intent is Dictionary:
			continue
		var intent: Dictionary = raw_intent
		var opener_candidates: Array = intent.get("anchors", []) \
			if intent.get("anchors", []) is Array else []
		var answer_anchors: Array = intent.get("answer_anchors", []) \
			if intent.get("answer_anchors", []) is Array else []
		opener_candidates.append_array(answer_anchors)
		for raw_anchor in opener_candidates:
			var anchor := str(raw_anchor).strip_edges().to_lower()
			if not anchor.is_empty() and anchor not in anchors:
				anchors.append(anchor)
	return anchors


static func _answer_hits_anchors(answer: String, anchors: Array) -> bool:
	if anchors.is_empty():
		return true
	var lower := answer.to_lower()
	for anchor in anchors:
		if lower.contains(str(anchor)):
			return true
	return false


static func _answer_in_character(answer: String) -> bool:
	var lower := answer.to_lower()
	for marker in _OUT_OF_CHARACTER_MARKERS:
		if lower.contains(str(marker)):
			return false
	return true


# "NPC: ... / You: ..." block for reply prompts; only the last `keep` entries
# so a long chat can't balloon the prompt. turns: [{speaker: "npc"|"you",
# text: String}].
static func transcript_block(turns: Array, keep: int = 6) -> String:
	var start := maxi(0, turns.size() - keep)
	var lines: Array[String] = []
	for i in range(start, turns.size()):
		var turn = turns[i]
		if not turn is Dictionary:
			continue
		var who := "You" if str((turn as Dictionary).get("speaker", "")) == "you" else "NPC"
		var text := str((turn as Dictionary).get("text", "")).strip_edges()
		if not text.is_empty():
			lines.append("%s: %s" % [who, text])
	return "\n".join(lines)
