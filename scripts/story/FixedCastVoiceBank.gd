class_name FixedCastVoiceBank
extends RefCounted

# Curated fixed-cast lines only. This selector never renders text or asks an
# LLM; it chooses a reviewed line whose explicit context requirements hold.
const EXAMPLE_PATH := "res://data/content/fixed_cast_voice_examples.json"


static func load_examples() -> Dictionary:
	var file := FileAccess.open(EXAMPLE_PATH, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "voice_examples_missing"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"ok": false, "reason": "voice_examples_json_invalid"}
	var root: Variant = parser.get_data()
	if not root is Dictionary:
		return {"ok": false, "reason": "voice_examples_root_invalid"}
	var examples: Variant = (root as Dictionary).get("examples", [])
	if not examples is Array:
		return {"ok": false, "reason": "voice_examples_missing_array"}
	var normalized: Array[Dictionary] = []
	for raw in examples:
		if not raw is Dictionary:
			return {"ok": false, "reason": "voice_example_invalid"}
		var example: Dictionary = raw
		for field in ["character_id", "state", "situation", "curator_decision", "line"]:
			if str(example.get(field, "")).strip_edges().is_empty():
				return {"ok": false, "reason": "voice_example_missing:%s" % field}
		var clean := example.duplicate(true)
		clean["example_id"] = _example_id(clean)
		normalized.append(clean)
	return {"ok": true, "examples": normalized}


static func select_line(
	character_id: String,
	state_id: String,
	situation: String,
	context: Dictionary,
	used_ids: Array = [],
	last_id: String = ""
) -> Dictionary:
	var loaded := load_examples()
	if not bool(loaded.get("ok", false)):
		return loaded
	var eligible: Array[Dictionary] = []
	for example in loaded.get("examples", []):
		var candidate: Dictionary = example
		if str(candidate.get("character_id", "")) != character_id \
				or str(candidate.get("state", "")) != state_id \
				or str(candidate.get("situation", "")) != situation:
			continue
		if _requirements_match(candidate, context):
			eligible.append(candidate)
	if eligible.is_empty():
		return {"ok": false, "reason": "no_curated_line"}
	var fresh: Array[Dictionary] = []
	for candidate in eligible:
		if not used_ids.has(str(candidate.get("example_id", ""))):
			fresh.append(candidate)
	var cycle_reset := fresh.is_empty()
	var pool := fresh if not fresh.is_empty() else eligible
	if pool.size() > 1 and not last_id.is_empty():
		var without_last: Array[Dictionary] = []
		for candidate in pool:
			if str(candidate.get("example_id", "")) != last_id:
				without_last.append(candidate)
		if not without_last.is_empty():
			pool = without_last
	var seed := "%s|%s|%s|%s" % [character_id, state_id, situation, str(context.get("runtime_id", ""))]
	var index := seed.sha256_text().substr(0, 8).hex_to_int() % pool.size()
	var chosen: Dictionary = pool[index]
	return {
		"ok": true,
		"line": str(chosen.get("line", "")),
		"example_id": str(chosen.get("example_id", "")),
		"cycle_reset": cycle_reset,
		"curator_decision": str(chosen.get("curator_decision", "")),
	}


# Selects the first unused reviewed entry in file order. Unlike select_line(),
# this is deliberately a true round robin: its caller persists used_ids and
# advances one line at a time until the whole pool has been heard.
static func select_round_robin_line(
	character_id: String,
	situation: String,
	context: Dictionary,
	used_ids: Array = []
) -> Dictionary:
	var loaded := load_examples()
	if not bool(loaded.get("ok", false)):
		return loaded
	var eligible: Array[Dictionary] = []
	for example in loaded.get("examples", []):
		var candidate: Dictionary = example
		if str(candidate.get("character_id", "")) != character_id \
				or str(candidate.get("situation", "")) != situation \
				or str(candidate.get("state", "")) != "evergreen":
			continue
		if _requirements_match(candidate, context):
			eligible.append(candidate)
	if eligible.is_empty():
		return {"ok": false, "reason": "no_curated_round_robin_line"}
	for candidate in eligible:
		if not used_ids.has(str(candidate.get("example_id", ""))):
			return {
				"ok": true,
				"line": str(candidate.get("line", "")),
				"example_id": str(candidate.get("example_id", "")),
				"cycle_reset": false,
				"curator_decision": str(candidate.get("curator_decision", "")),
			}
	var chosen: Dictionary = eligible[0]
	return {
		"ok": true,
		"line": str(chosen.get("line", "")),
		"example_id": str(chosen.get("example_id", "")),
		"cycle_reset": true,
		"curator_decision": str(chosen.get("curator_decision", "")),
	}


static func style_reference_block(
	character_id: String,
	state_id: String,
	situation: String,
	context: Dictionary,
	limit: int = 2
) -> String:
	var loaded := load_examples()
	if not bool(loaded.get("ok", false)):
		return ""
	var lines: Array[String] = []
	for example in loaded.get("examples", []):
		var candidate: Dictionary = example
		if str(candidate.get("character_id", "")) != character_id \
				or str(candidate.get("state", "")) != state_id \
				or str(candidate.get("situation", "")) != situation \
				or not _requirements_match(candidate, context):
			continue
		lines.append("- %s" % str(candidate.get("line", "")))
		if lines.size() >= limit:
			break
	if lines.is_empty():
		return ""
	return "Approved voice rhythm references. Do not quote, reuse, or paraphrase these lines; use only their level of specificity, dry humor, and restraint:\n" + "\n".join(lines) + "\n"


# Generation may use reviewed examples as rhythm guidance, but the player must
# never receive a line copied from that library. Reject exact matches and any
# shared run of five words; shorter overlap is ordinary character vocabulary.
static func matches_curated_line(character_id: String, situation: String, line: String) -> bool:
	var candidate := _normalized_line(line)
	if candidate.is_empty():
		return false
	var loaded := load_examples()
	if not bool(loaded.get("ok", false)):
		return false
	for example in loaded.get("examples", []):
		var reviewed: Dictionary = example
		if str(reviewed.get("character_id", "")) != character_id \
				or str(reviewed.get("situation", "")) != situation:
			continue
		var reference := _normalized_line(str(reviewed.get("line", "")))
		if reference == candidate or _shares_word_run(candidate, reference, 5):
			return true
	return false


static func _requirements_match(example: Dictionary, context: Dictionary) -> bool:
	var requirements: Array = example.get("required_context", []) if example.get("required_context", []) is Array else []
	for raw_requirement in requirements:
		var requirement := str(raw_requirement).strip_edges()
		if requirement.is_empty():
			continue
		if not bool(context.get(requirement, false)):
			return false
	return true


static func _example_id(example: Dictionary) -> String:
	return "%s.%s" % [
		str(example.get("character_id", "")),
		("%s|%s|%s" % [
			str(example.get("state", "")),
			str(example.get("situation", "")),
			str(example.get("line", "")),
		]).sha256_text().substr(0, 16),
	]


static func _normalized_line(line: String) -> String:
	var clean := line.to_lower().strip_edges()
	for punctuation in [".", ",", "!", "?", ";", ":", "'", "\"", "’", "—", "-", "…"]:
		clean = clean.replace(punctuation, " ")
	return " ".join(clean.split(" ", false))


static func _shares_word_run(candidate: String, reference: String, word_count: int) -> bool:
	var candidate_words := candidate.split(" ", false)
	var reference_words := reference.split(" ", false)
	if candidate_words.size() < word_count or reference_words.size() < word_count:
		return false
	for start in range(candidate_words.size() - word_count + 1):
		var phrase := " ".join(candidate_words.slice(start, start + word_count))
		if reference.contains(phrase):
			return true
	return false
