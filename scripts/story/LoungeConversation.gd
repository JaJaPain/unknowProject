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
