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
	var selected := select_style_references(
		character_id,
		state_id,
		situation,
		context,
		limit
	)
	var lines: Array[String] = []
	for candidate in selected:
		lines.append("- %s" % str(candidate.get("line", "")))
	if lines.is_empty():
		return ""
	return "Approved voice rhythm references. Do not quote, reuse, or paraphrase these lines; use only their level of specificity, dry humor, and restraint:\n" + "\n".join(lines) + "\n"


# Returns a small, deterministic-but-varied reference slice. Curators should
# supply semantic_premise_tag; legacy examples use their ID as a safe unique
# fallback until they are tagged. A caller may exclude recently shown premise
# tags to keep prompts fresh across a campaign or across campaigns.
static func select_style_references(
	character_id: String,
	state_id: String,
	situation: String,
	context: Dictionary,
	limit: int = 2
) -> Array[Dictionary]:
	var loaded := load_examples()
	if not bool(loaded.get("ok", false)) or limit <= 0:
		return []
	var excluded: Dictionary = {}
	for raw_tag in context.get("excluded_premise_tags", []):
		var tag := str(raw_tag).strip_edges()
		if not tag.is_empty():
			excluded[tag] = true
	var candidates: Array[Dictionary] = []
	for example in loaded.get("examples", []):
		var candidate: Dictionary = example
		if str(candidate.get("character_id", "")) != character_id \
				or str(candidate.get("state", "")) != state_id \
				or str(candidate.get("situation", "")) != situation \
				or not _requirements_match(candidate, context):
			continue
		var tag := semantic_premise_tag(candidate)
		if excluded.has(tag):
			continue
		candidates.append(candidate)
	var seed := str(context.get("reference_seed", context.get("runtime_id", "default")))
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (seed + "|" + str(a.get("example_id", ""))).sha256_text() < (seed + "|" + str(b.get("example_id", ""))).sha256_text()
	)
	if context.has("reference_combination_index"):
		return _combination_at(
			candidates,
			mini(limit, candidates.size()),
			maxi(0, int(context.get("reference_combination_index", 0)))
		)
	var selected: Array[Dictionary] = []
	var selected_tags: Dictionary = {}
	for candidate in candidates:
		var tag := semantic_premise_tag(candidate)
		if selected_tags.has(tag):
			continue
		selected.append(candidate)
		selected_tags[tag] = true
		if selected.size() >= limit:
			break
	return selected


# Deterministic combination mode is used by persistent runtime schedulers.
# With 30 eligible, uniquely tagged examples and a three-reference prompt, it
# walks all 4,060 unordered combinations before returning to the first one.
static func reference_combination_count(example_count: int, selection_size: int) -> int:
	var n := maxi(0, example_count)
	var k := clampi(selection_size, 0, n)
	if k == 0:
		return 1
	var result := 1
	for index in range(1, k + 1):
		result = (result * (n - k + index)) / index
	return result


static func _combination_at(
	candidates: Array[Dictionary],
	selection_size: int,
	combination_index: int
) -> Array[Dictionary]:
	if selection_size <= 0 or candidates.is_empty():
		return []
	var total := reference_combination_count(candidates.size(), selection_size)
	var remaining_index := combination_index % maxi(1, total)
	var selected: Array[Dictionary] = []
	var start := 0
	for picked in range(selection_size):
		for candidate_index in range(start, candidates.size()):
			var remaining_slots := selection_size - picked - 1
			var following := candidates.size() - candidate_index - 1
			var branch_count := reference_combination_count(following, remaining_slots)
			if remaining_index < branch_count:
				selected.append(candidates[candidate_index])
				start = candidate_index + 1
				break
			remaining_index -= branch_count
	return selected


static func semantic_premise_tag(example: Dictionary) -> String:
	var tagged := str(example.get("semantic_premise_tag", "")).strip_edges()
	return tagged if not tagged.is_empty() else "legacy:%s" % _example_id(example)


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
