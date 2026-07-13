class_name LoungeIntentSelector
extends RefCounted

# Phase 9: code-owned selection of the player's lounge question intents.
# The model never invents the player's side — these {id, text} intents feed
# LoungeConversation.build_bundle_prompt verbatim. Story-driven questions
# (rumored knowledge gaps, delivered rumors, the player's current stake,
# a warm-contact callback) always beat generic friendly/pushback/odd
# filler; generics only pad the list up to the minimum.
#
# A player can only ask about what they have actually heard: knowledge gaps
# are RUMORED facts (heard, unverified). Unknown facts never become
# questions.

const MIN_INTENTS := 2
const MAX_INTENTS := 3

const GENERIC_INTENTS: Array = [
	{"id": "generic:friendly", "text": "How's the station treating you?"},
	{"id": "generic:pushback", "text": "This place always this lively?"},
	{"id": "generic:odd", "text": "What's the worst drink here?"},
]


# context keys (all optional, all code-supplied):
#   knowledge_gaps: [{fact_id, state, alias}] — only rumored entries count
#   delivered_rumors: [{rumor_id, summary}]
#   mission_label: String — the player's current public mission beat
#   relationship: {warmth_tier: String, met_before: bool}
static func select_intents(
	context: Dictionary,
	max_intents: int = MAX_INTENTS
) -> Array:
	var cap: int = clampi(max_intents, 1, MAX_INTENTS)
	var intents: Array = []
	var seen_ids: Dictionary = {}

	# 1. Rumored knowledge gaps: the player heard something and can chase it.
	var gaps: Array = context.get("knowledge_gaps", []) \
		if context.get("knowledge_gaps", []) is Array else []
	for raw_gap in gaps:
		if intents.size() >= cap:
			break
		if not raw_gap is Dictionary:
			continue
		var gap: Dictionary = raw_gap
		if str(gap.get("state", "")) != KnowledgeLedger.STATE_RUMORED:
			continue
		var fact_id := str(gap.get("fact_id", "")).strip_edges()
		var alias := str(gap.get("alias", "")).strip_edges()
		if fact_id.is_empty() or alias.is_empty():
			continue
		var id := "gap:%s" % fact_id
		if seen_ids.has(id):
			continue
		seen_ids[id] = true
		intents.append({
			"id": id,
			"text": "I keep hearing about %s. What's the real story?" % alias,
			"source": "knowledge_gap",
			"anchors": anchor_tokens(alias),
		})

	# 2. Delivered rumors: follow up on something someone actually said.
	var rumors: Array = context.get("delivered_rumors", []) \
		if context.get("delivered_rumors", []) is Array else []
	for raw_rumor in rumors:
		if intents.size() >= cap:
			break
		if not raw_rumor is Dictionary:
			continue
		var rumor: Dictionary = raw_rumor
		var rumor_id := str(rumor.get("rumor_id", "")).strip_edges()
		var summary := str(rumor.get("summary", "")).strip_edges()
		if rumor_id.is_empty() or summary.is_empty():
			continue
		var id := "rumor:%s" % rumor_id
		if seen_ids.has(id):
			continue
		seen_ids[id] = true
		intents.append({
			"id": id,
			"text": "Someone mentioned %s. You know anything about that?" % summary,
			"source": "delivered_rumor",
			"anchors": anchor_tokens(summary),
		})

	# 3. Current stake: the player's live job gives a natural local angle.
	var mission_label := str(context.get("mission_label", "")).strip_edges()
	if intents.size() < cap and not mission_label.is_empty():
		intents.append({
			"id": "stake:mission",
			"text": "I'm working a job — %s. Anything local I should know?"
				% mission_label,
			"source": "current_stake",
			"anchors": anchor_tokens(mission_label),
		})

	# 4. Warm contact callback: a personal beat beats generic filler.
	var relationship: Dictionary = context.get("relationship", {}) \
		if context.get("relationship", {}) is Dictionary else {}
	if intents.size() < cap \
			and bool(relationship.get("met_before", false)) \
			and str(relationship.get("warmth_tier", "")) in ["warm", "friend"]:
		intents.append({
			"id": "warm:callback",
			"text": "Good to see you again. Anything change since last time?",
			"source": "relationship",
			"anchors": [],
		})

	# 5. Generic filler ONLY pads to the minimum — never displaces a story
	# question, never appears when enough story questions exist. Generic
	# small talk has no anchors: any in-character answer fits it.
	for raw_generic in GENERIC_INTENTS:
		if intents.size() >= MIN_INTENTS:
			break
		var generic: Dictionary = (raw_generic as Dictionary).duplicate(true)
		generic["anchors"] = []
		intents.append(generic)

	return intents


const _ANCHOR_STOPWORDS: Dictionary = {
	"the": true, "that": true, "this": true, "with": true, "from": true,
	"about": true, "some": true, "what": true, "them": true, "they": true,
	"were": true, "been": true, "have": true, "will": true, "your": true,
	"missing": true, "new": true,
}


# Distinctive topic tokens from the phrase a question was built around.
# Used to check an NPC answer actually addresses its paired question.
static func anchor_tokens(phrase: String) -> Array:
	var tokens: Array = []
	for raw_word in phrase.to_lower().split(" ", false):
		var word := ""
		for character in raw_word:
			if character.to_lower() != character.to_upper() \
					or character.is_valid_int():
				word += character
		if word.length() < 4 or _ANCHOR_STOPWORDS.has(word):
			continue
		if not tokens.has(word):
			tokens.append(word)
	return tokens
