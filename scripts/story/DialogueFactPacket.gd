class_name DialogueFactPacket
extends RefCounted

## The compact packet handed to the small model for ONE slice of speech.
##
## The failure this exists to prevent: asking one response to invent the economy,
## solve the quest mechanics, write six branches and roleplay the whole cast.
## A packet is one speaker, one purpose, and only the facts that speaker knows
## and may say out loud.
##
## Private facts are not included and then guarded -- they are never put in the
## prompt at all. Withholding is cheaper and far more reliable than detecting a
## leak after the fact.

const ContractType := preload("res://scripts/domain/QuestCausalContract.gd")

const PACKET_VERSION := 1

## How many previously-spoken phrases to show as "do not start this way again".
## Enough to break a habitual opening, small enough not to crowd the prompt.
const MAX_RECENT_PHRASES := 4

## Hard ceiling on facts in one packet. Past this the model stops writing a line
## and starts writing a summary of the briefing.
const MAX_FACTS := 6


## `speaker` is the existing speaker card. `purpose` is a DialogueFieldContract
## purpose. `options` may carry:
##   question_text     -- the player's actual question, for an answer slice
##   opening_text      -- the accepted opening, so an answer cannot contradict it
##   recent_phrases    -- Array[String] of openings this speaker recently used
##   known_fact_ids    -- restrict disclosure to what the speaker has learned
##   attitude          -- immediate mood, with a reason
static func build(
	contract_source: Variant,
	speaker: Dictionary,
	purpose: String,
	options: Dictionary = {}
) -> Dictionary:
	var contract: Dictionary = ContractType.normalize(contract_source)
	var facts := _disclosable_facts(contract, purpose, options)
	return {
		"version": PACKET_VERSION,
		"purpose": str(purpose).strip_edges(),
		"speaker": _speaker_block(speaker),
		"addressing": str(options.get("addressing", "the pilot they are hiring")),
		"wants_right_now": _wants_right_now(contract, purpose),
		"attitude": str(options.get("attitude", "")).strip_edges(),
		"facts": facts,
		"fact_ids": _fact_ids(facts),
		"question_text": str(options.get("question_text", "")).strip_edges(),
		"preceding_line": str(options.get("opening_text", "")).strip_edges(),
		"required_fact_ids": _required_fact_ids(contract, purpose, facts),
		"recent_phrases": _recent_phrases(options.get("recent_phrases", [])),
		"contract_id": str(contract.get("id", "")),
		"contract_revision": int(contract.get("revision", 0)),
	}


## The protected cast keep their existing soul projection; this only records
## WHICH guidance applies, it never rewrites or paraphrases it.
static func _speaker_block(speaker: Dictionary) -> Dictionary:
	return {
		"name": str(speaker.get("name", "")).strip_edges(),
		"role": str(speaker.get("role", "")).strip_edges(),
		"voice_profile_id": str(speaker.get("voice_profile_id", "")).strip_edges(),
		"voice_guidance": str(speaker.get("voice_guidance", "")).strip_edges(),
		"soul_state": str(speaker.get("soul_state", "")).strip_edges(),
		"faction_id": str(speaker.get("faction_id", "")).strip_edges(),
	}


static func _wants_right_now(contract: Dictionary, purpose: String) -> String:
	match str(purpose):
		"opening":
			return "get this pilot to take the job"
		"answer":
			return "answer the question they actually asked, then stop"
		"outcome", "callback":
			return "acknowledge what happened without re-briefing it"
		_:
			return "be understood"


## Only facts that are PUBLIC in the contract, and -- when the caller supplies a
## knowledge snapshot -- only the ones this speaker has actually learned.
static func _disclosable_facts(
	contract: Dictionary,
	purpose: String,
	options: Dictionary
) -> Array[Dictionary]:
	var public_facts := ContractType.public_facts(contract)
	var known := _string_array(options.get("known_fact_ids", []))
	var question := str(options.get("question_text", "")).strip_edges()
	var ordered := _ordered_fact_ids(contract, purpose, public_facts, question)
	var selected: Array[Dictionary] = []
	for fact_id in ordered:
		if selected.size() >= MAX_FACTS:
			break
		if not known.is_empty() and fact_id not in known:
			continue
		var fact: Dictionary = public_facts[fact_id]
		selected.append({"id": fact_id, "text": str(fact.get("text", ""))})
	return selected


## Order the disclosable facts so the cap trims the LEAST useful.
##
## When there is an actual question, facts that bear on that question come
## first, regardless of the generic purpose ordering. The failure this prevents
## is the one the integration review named: the fact that actually answers the
## player gets truncated away because six unrelated facts were inserted before
## it, and the writer then cannot answer with grounding it was never given.
static func _ordered_fact_ids(
	contract: Dictionary,
	purpose: String,
	public_facts: Dictionary,
	question: String
) -> Array[String]:
	var priority := _priority_fact_ids(contract, purpose)
	var candidates: Array[String] = []
	for fact_id in priority:
		if public_facts.has(fact_id) and fact_id not in candidates:
			candidates.append(fact_id)
	for fact_id in public_facts.keys():
		if str(fact_id) not in candidates:
			candidates.append(str(fact_id))
	if question.is_empty():
		return candidates

	# Stable rank: question relevance first, then the purpose order that already
	# placed these. Ties keep their original position so the result stays
	# deterministic -- writer and validator must derive the same packet.
	var question_words := _distinctive_words(question)
	var scored: Array[Dictionary] = []
	for index in range(candidates.size()):
		var fact_id: String = candidates[index]
		var fact: Variant = public_facts.get(fact_id, {})
		var text := str((fact as Dictionary).get("text", "")) if fact is Dictionary else ""
		scored.append({
			"id": fact_id,
			"index": index,
			"score": _question_overlap(text, question_words),
		})
	scored.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_score := int(left["score"])
		var right_score := int(right["score"])
		if left_score != right_score:
			return left_score > right_score
		return int(left["index"]) < int(right["index"])
	)
	var ordered: Array[String] = []
	for entry in scored:
		ordered.append(str(entry["id"]))
	return ordered


## How many of the question's distinctive words this fact actually contains.
## A count, not a ratio: a long fact that covers three of the asked-about words
## is more use than a short one that happens to cover its only word.
static func _question_overlap(text: String, question_words: Array[String]) -> int:
	if text.is_empty() or question_words.is_empty():
		return 0
	var lower := text.to_lower()
	var hits := 0
	for word in question_words:
		if lower.contains(word):
			hits += 1
	return hits


## Shared with the quality gate's notion of a content word. Deliberately crude:
## this only ORDERS facts, it never removes one, so a miss costs position rather
## than grounding.
static func _distinctive_words(text: String) -> Array[String]:
	var stop_words := [
		"the", "a", "an", "and", "or", "but", "of", "to", "in", "on", "at", "for",
		"with", "is", "are", "was", "were", "be", "been", "it", "its", "that",
		"this", "they", "them", "their", "there", "has", "have", "had", "not",
		"will", "can", "cannot", "from", "into", "out", "up", "down", "own",
		"what", "why", "how", "who", "when", "does", "do", "did", "you", "your",
		"about", "just", "then", "than", "some", "any", "all", "get", "got",
		"ask", "tell", "say", "me", "my", "i", "we", "us", "if", "so",
	]
	var words: Array[String] = []
	for raw_word in text.to_lower().split(" ", false):
		var word := str(raw_word).strip_edges()
		for punctuation in [".", ",", ";", ":", "'s", "\"", "'", "!", "?", ")", "("]:
			word = word.trim_suffix(punctuation).trim_prefix(punctuation)
		if word.length() < 4 or word in stop_words or word in words:
			continue
		words.append(word)
	return words


## Which facts matter most for THIS purpose, so the cap trims the least useful
## rather than whatever the dictionary happened to order last.
static func _priority_fact_ids(contract: Dictionary, purpose: String) -> Array[String]:
	var fields: Array
	match str(purpose):
		"opening":
			fields = [
				"problem_fact_ids",
				"why_this_action_fact_ids",
				"why_player_fact_ids",
				"urgency_fact_ids",
			]
		"answer":
			fields = [
				"why_this_action_fact_ids",
				"problem_fact_ids",
				"urgency_fact_ids",
				"reward_source_fact_ids",
				"why_player_fact_ids",
			]
		_:
			fields = ["problem_fact_ids", "why_this_action_fact_ids"]
	var ordered: Array[String] = []
	for field in fields:
		for fact_id in _string_array(contract.get(field, [])):
			if fact_id not in ordered:
				ordered.append(fact_id)
	return ordered


## Facts the line MUST actually state. Kept deliberately small: an opening that
## has to hit five required facts stops being speech and becomes a manifest.
static func _required_fact_ids(
	contract: Dictionary,
	purpose: String,
	facts: Array[Dictionary]
) -> Array[String]:
	var available: Array[String] = _fact_ids(facts)
	var required: Array[String] = []
	if str(purpose) != "opening":
		return required
	for field in ["problem_fact_ids", "why_this_action_fact_ids"]:
		for fact_id in _string_array(contract.get(field, [])):
			if fact_id in available and fact_id not in required:
				required.append(fact_id)
				break
		if required.size() >= 2:
			break
	return required


static func _fact_ids(facts: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for fact in facts:
		var fact_id := str(fact.get("id", "")).strip_edges()
		if not fact_id.is_empty() and fact_id not in ids:
			ids.append(fact_id)
	return ids


static func _recent_phrases(value: Variant) -> Array[String]:
	var phrases := _string_array(value)
	while phrases.size() > MAX_RECENT_PHRASES:
		phrases.remove_at(0)
	return phrases


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array):
		return result
	for item in (value as Array):
		var text := str(item).strip_edges()
		if not text.is_empty() and text not in result:
			result.append(text)
	return result


## Render the packet as prompt text. Writing guidance deliberately does NOT
## prescribe slang, filler, swearing, stumbles or jokes as a universal "human"
## style -- that produces every NPC doing the same comedian voice. It asks for
## plain spoken language and lets the speaker's own guidance supply character.
static func prompt_block(packet: Dictionary) -> String:
	var lines: Array[String] = []
	var speaker: Dictionary = packet.get("speaker", {})
	var name := str(speaker.get("name", "")).strip_edges()
	if not name.is_empty():
		lines.append("You are %s." % name)
	var role := str(speaker.get("role", "")).strip_edges()
	if not role.is_empty():
		lines.append("Role: %s" % role)
	var guidance := str(speaker.get("voice_guidance", "")).strip_edges()
	if not guidance.is_empty():
		lines.append("Voice: %s" % guidance)
	lines.append("You are speaking to %s." % str(packet.get("addressing", "the pilot")))
	lines.append("Right now you want to %s." % str(packet.get("wants_right_now", "be understood")))
	var attitude := str(packet.get("attitude", "")).strip_edges()
	if not attitude.is_empty():
		lines.append("Your mood: %s" % attitude)

	var facts: Array = packet.get("facts", [])
	if not facts.is_empty():
		lines.append("")
		lines.append("What you know and may say:")
		for raw_fact in facts:
			if not (raw_fact is Dictionary):
				continue
			lines.append("- [%s] %s" % [
				str((raw_fact as Dictionary).get("id", "")),
				str((raw_fact as Dictionary).get("text", "")),
			])

	var required: Array = packet.get("required_fact_ids", [])
	if not required.is_empty():
		lines.append("")
		lines.append("Your line must actually state: %s" % ", ".join(required))

	var preceding := str(packet.get("preceding_line", "")).strip_edges()
	if not preceding.is_empty():
		lines.append("")
		lines.append("You already said: \"%s\"" % preceding)
		lines.append("Do not repeat it or contradict it.")

	var question := str(packet.get("question_text", "")).strip_edges()
	if not question.is_empty():
		lines.append("")
		lines.append("They asked: \"%s\"" % question)
		lines.append("Answer that question. Do not answer a different one.")

	var recent: Array = packet.get("recent_phrases", [])
	if not recent.is_empty():
		lines.append("")
		lines.append("You have recently opened with these. Do not reuse them:")
		for phrase in recent:
			lines.append("- %s" % str(phrase))

	lines.append("")
	lines.append("Write it as one person talking to another:")
	lines.append("- Plain spoken language. Concrete nouns. Contractions where natural.")
	lines.append("- One clear thought first; extra detail only if it earns its place.")
	lines.append("- Do not list the facts back. Say what a person in this position would say.")
	lines.append("- Do not invent people, places, numbers, deadlines or dangers.")
	lines.append("- Do not perform. No forced jokes, no slang you were not given, no verbal tics.")
	return "\n".join(lines)


## Stable identity of a packet's PUBLIC content.
##
## Writer and validator must be looking at the same facts. Rather than passing a
## mutable dictionary between them and hoping, both derive the packet from the
## same immutable inputs and compare this fingerprint. A mismatch means the
## world moved between dispatch and response, which is exactly the condition the
## existing stale-response guard already refuses to publish.
##
## Deliberately excludes recent_phrases and attitude: those are writing nudges
## that do not change what is true, and letting them shift the fingerprint would
## invalidate in-flight slices for no reason.
static func fingerprint(packet: Dictionary) -> String:
	var facts: Array = []
	for raw_fact in (packet.get("facts", []) as Array):
		if not (raw_fact is Dictionary):
			continue
		facts.append("%s=%s" % [
			str((raw_fact as Dictionary).get("id", "")),
			str((raw_fact as Dictionary).get("text", "")),
		])
	var basis := "|".join([
		"v%d" % int(packet.get("version", 0)),
		str(packet.get("purpose", "")),
		str(packet.get("contract_id", "")),
		"r%d" % int(packet.get("contract_revision", 0)),
		str(packet.get("question_text", "")),
		str(packet.get("preceding_line", "")),
		",".join(facts),
		",".join(_string_array(packet.get("required_fact_ids", []))),
	])
	return basis.sha256_text().substr(0, 24)
