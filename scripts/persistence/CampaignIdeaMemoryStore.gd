class_name CampaignIdeaMemoryStore
extends RefCounted

const DomainIdType := preload("res://scripts/domain/DomainId.gd")
const DomainJsonType := preload("res://scripts/domain/DomainJson.gd")
const TransactionStoreType := preload(
	"res://scripts/persistence/CampaignTransactionStore.gd"
)
const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

const DOCUMENT_VERSION := 1
const MEMORY_PATH := "idea_memory.json"
const MAX_IDEAS := 512
const MAX_PROMPT_ITEMS := 24
const ALLOWED_CATEGORIES := [
	"faction",
	"npc",
	"mission",
	"joke",
	"rumor",
	"system",
	"story_beat",
	"style_rule",
	"banned_repeat",
	"campaign_title",
	"reveal",
]
const CAMPAIGN_BIBLE_CATEGORIES := [
	"faction",
	"npc",
	"joke",
	"rumor",
	"system",
	"story_beat",
	"style_rule",
	"banned_repeat",
	"campaign_title",
	"reveal",
]

var campaign_path: String
var campaign: Dictionary = {}
var data: Dictionary = {}
var validation := ValidationResultType.new()


static func open(path: String) -> CampaignIdeaMemoryStore:
	var store := CampaignIdeaMemoryStore.new()
	store.campaign_path = path.trim_suffix("/")
	store._load_or_create()
	return store


func is_valid() -> bool:
	return validation.is_valid()


func append_idea(
	category: String,
	summary: String,
	tags: Array = [],
	fingerprint_source: String = "",
	metadata: Dictionary = {}
) -> Dictionary:
	if not is_valid():
		return _failure("Idea memory store is invalid.")
	var clean_category := category.strip_edges()
	var clean_summary := summary.strip_edges()
	if clean_category not in ALLOWED_CATEGORIES:
		return _failure("Idea category is not allowed.")
	if clean_summary.is_empty():
		return _failure("Idea summary cannot be empty.")
	var clean_tags := _clean_tags(tags)
	var fingerprint := _fingerprint(
		fingerprint_source if not fingerprint_source.strip_edges().is_empty() else clean_summary
	)
	for idea in data.get("ideas", []):
		if idea is Dictionary and str(idea.get("fingerprint", "")) == fingerprint:
			return {
				"ok": true,
				"duplicate": true,
				"idea": (idea as Dictionary).duplicate(true),
			}
	var next_sequence := int(data.get("next_sequence", 0))
	var idea := {
		"idea_id": _new_id(next_sequence),
		"sequence": next_sequence,
		"category": clean_category,
		"summary": clean_summary,
		"tags": clean_tags,
		"fingerprint": fingerprint,
		"metadata": metadata.duplicate(true),
		"created_at_unix": int(Time.get_unix_time_from_system()),
	}
	var next_data := data.duplicate(true)
	var ideas: Array = next_data.get("ideas", []).duplicate(true)
	ideas.append(idea)
	next_data["ideas"] = _bounded_ideas(ideas)
	next_data["next_sequence"] = next_sequence + 1
	var committed := _commit(next_data, "idea_memory_append")
	if not bool(committed.get("ok", false)):
		return committed
	data = next_data
	return {"ok": true, "duplicate": false, "idea": idea.duplicate(true)}


func prompt_context(
	categories: Array = [],
	tags: Array = [],
	limit: int = MAX_PROMPT_ITEMS
) -> String:
	var selected := query_ideas(categories, tags, limit)
	if selected.is_empty():
		return "No prior generated ideas recorded yet."
	var lines: Array[String] = ["Previously used ideas to avoid repeating:"]
	for idea in selected:
		lines.append(
			"- [%s] %s" %
			[str(idea.get("category", "idea")), str(idea.get("summary", ""))]
		)
	return "\n".join(lines)


func campaign_bible_prompt_context(limit: int = MAX_PROMPT_ITEMS) -> String:
	var selected := query_ideas(CAMPAIGN_BIBLE_CATEGORIES, [], limit)
	if selected.is_empty():
		return "No prior generated ideas recorded yet."
	var lines: Array[String] = [
		"Campaign-level ideas already used. Avoid repeating or lightly renaming them:",
	]
	for idea in selected:
		var category := str(idea.get("category", "idea"))
		var tag_strings: Array[String] = []
		for tag in idea.get("tags", []):
			tag_strings.append(str(tag))
		var tags := ", ".join(tag_strings)
		var suffix := "" if tags.is_empty() else " tags=%s" % tags
		lines.append(
			"- [%s]%s %s" %
			[category, suffix, str(idea.get("summary", ""))]
		)
	return "\n".join(lines)


func remember_campaign_bible(bible: Dictionary) -> Dictionary:
	if not is_valid():
		return _failure("Idea memory store is invalid.")
	var added := 0
	var duplicates := 0
	var failures: Array[String] = []
	for arc in bible.get("story_arcs", []):
		if not arc is Dictionary:
			continue
		var arc_name := str(arc.get("name", "")).strip_edges()
		var summary := "%s: %s" % [arc_name, str(arc.get("summary", "")).strip_edges()]
		var arc_result := append_idea(
			"story_beat",
			summary,
			["campaign_bible", "story_arc"],
			"story_arc|%s|%s" % [arc_name, summary],
			{"source": "campaign_bible", "arc": (arc as Dictionary).duplicate(true)}
		)
		_count_append_result(arc_result, failures)
		added += 1 if bool(arc_result.get("ok", false)) and not bool(arc_result.get("duplicate", false)) else 0
		duplicates += 1 if bool(arc_result.get("duplicate", false)) else 0
	for trail in bible.get("rumor_trails", []):
		if not trail is Dictionary:
			continue
		var trail_name := str(trail.get("name", "")).strip_edges()
		var trail_id := str(trail.get("trail_id", trail_name)).strip_edges()
		var discovery_type := str(trail.get("discovery_type", "hidden_discovery"))
		var summary := "%s (%s): %s -> %s" % [
			trail_name,
			discovery_type,
			str(trail.get("hint_theme", "")).strip_edges(),
			str(trail.get("payoff", "")).strip_edges(),
		]
		var trail_result := append_idea(
			"rumor",
			summary,
			["campaign_bible", "rumor_trail", discovery_type],
			"rumor_trail|%s" % trail_id,
			{"source": "campaign_bible", "trail": (trail as Dictionary).duplicate(true)}
		)
		_count_append_result(trail_result, failures)
		added += 1 if bool(trail_result.get("ok", false)) and not bool(trail_result.get("duplicate", false)) else 0
		duplicates += 1 if bool(trail_result.get("duplicate", false)) else 0
	for repeat in bible.get("banned_repeats", []):
		var clean_repeat := str(repeat).strip_edges()
		if clean_repeat.is_empty():
			continue
		var repeat_result := append_idea(
			"banned_repeat",
			clean_repeat,
			["campaign_bible"],
			"banned_repeat|%s" % clean_repeat
		)
		_count_append_result(repeat_result, failures)
		added += 1 if bool(repeat_result.get("ok", false)) and not bool(repeat_result.get("duplicate", false)) else 0
		duplicates += 1 if bool(repeat_result.get("duplicate", false)) else 0
	for field in ["humor_rule", "faction_reveal_rule", "story_horizon_rule"]:
		var rule := str(bible.get(field, "")).strip_edges()
		if rule.is_empty():
			continue
		var rule_result := append_idea(
			"style_rule",
			"%s: %s" % [field, rule],
			["campaign_bible", field],
			"style_rule|%s|%s" % [field, rule]
		)
		_count_append_result(rule_result, failures)
		added += 1 if bool(rule_result.get("ok", false)) and not bool(rule_result.get("duplicate", false)) else 0
		duplicates += 1 if bool(rule_result.get("duplicate", false)) else 0
	# Record the title and long-term reveal so the next campaign's similarity gate
	# (see NarrativeDirector.is_text_too_similar) and the generation prompt can
	# steer away from near-duplicates. reveal only ever feeds the large-story
	# (director-privileged) prompt via campaign_bible_prompt_context — never a
	# small-model prompt — so it does not leak the current campaign's twist.
	for field_and_category in [["campaign_title", "campaign_title"], ["long_term_reveal", "reveal"]]:
		var field := str(field_and_category[0])
		var category := str(field_and_category[1])
		var value := str(bible.get(field, "")).strip_edges()
		if value.is_empty():
			continue
		var entry_result := append_idea(
			category,
			value,
			["campaign_bible", field],
			"%s|%s" % [category, value]
		)
		_count_append_result(entry_result, failures)
		added += 1 if bool(entry_result.get("ok", false)) and not bool(entry_result.get("duplicate", false)) else 0
		duplicates += 1 if bool(entry_result.get("duplicate", false)) else 0
	return {
		"ok": failures.is_empty(),
		"added": added,
		"duplicates": duplicates,
		"errors": failures,
	}


# Returns up to `limit` recent idea summaries for one category, newest first —
# structured history for the similarity gate and lane rotation (plan §3.2/§3.3)
# instead of parsing the formatted prompt-context string.
func query_recent(category: String, limit: int = 12) -> Array:
	var summaries: Array = []
	for idea in query_ideas([category], [], limit):
		var summary := str((idea as Dictionary).get("summary", "")).strip_edges()
		if not summary.is_empty():
			summaries.append(summary)
	return summaries


func query_ideas(
	categories: Array = [],
	tags: Array = [],
	limit: int = MAX_PROMPT_ITEMS
) -> Array:
	var category_filter := _string_set(categories)
	var tag_filter := _string_set(tags)
	var matches: Array = []
	var ideas: Array = data.get("ideas", []).duplicate(true)
	ideas.sort_custom(_sequence_desc)
	for idea in ideas:
		if not idea is Dictionary:
			continue
		if not category_filter.is_empty() \
				and not category_filter.has(str(idea.get("category", ""))):
			continue
		if not tag_filter.is_empty() \
				and not _idea_has_any_tag(idea, tag_filter):
			continue
		matches.append((idea as Dictionary).duplicate(true))
		if matches.size() >= maxi(1, limit):
			break
	return matches


func summary() -> Dictionary:
	var by_category := {}
	for idea in data.get("ideas", []):
		if not idea is Dictionary:
			continue
		var category := str(idea.get("category", "unknown"))
		by_category[category] = int(by_category.get(category, 0)) + 1
	return {
		"total_ideas": (data.get("ideas", []) as Array).size(),
		"by_category": by_category,
		"next_sequence": int(data.get("next_sequence", 0)),
	}


func _load_or_create() -> void:
	var campaign_result := DomainJsonType.read_object(
		"%s/campaign.json" % campaign_path
	)
	validation.merge(campaign_result["validation"], "campaign")
	if not validation.is_valid():
		return
	campaign = campaign_result["data"]
	var campaign_id := str(campaign.get("id", ""))
	if not DomainIdType.is_valid(campaign_id, "campaign"):
		validation.add_error(
			"invalid_campaign_id",
			"Idea memory requires a valid campaign id.",
			"campaign.id"
		)
		return
	var memory_path := "%s/%s" % [campaign_path, MEMORY_PATH]
	if not FileAccess.file_exists(memory_path):
		data = _initial_data(campaign_id)
		var committed := _commit(data, "idea_memory_bootstrap")
		if not bool(committed.get("ok", false)):
			validation.add_error(
				"idea_memory_bootstrap_failed",
				str(committed.get("error", "Idea memory could not be created.")),
				MEMORY_PATH
			)
		return
	var memory_result := DomainJsonType.read_object(memory_path)
	validation.merge(memory_result["validation"], "idea_memory")
	if not validation.is_valid():
		return
	data = memory_result["data"]
	validation.merge(_validate_data(data, campaign_id), "idea_memory")
	if validation.is_valid() and not data.has("next_sequence"):
		data["next_sequence"] = (data.get("ideas", []) as Array).size()


func _commit(next_data: Dictionary, operation: String) -> Dictionary:
	return TransactionStoreType.commit_json_set(
		campaign_path,
		operation,
		{MEMORY_PATH: next_data},
		MEMORY_PATH,
		func(_path: String, value: Dictionary) -> ValidationResult:
			return _validate_data(value, str(campaign.get("id", "")))
	)


static func _initial_data(campaign_id: String) -> Dictionary:
	return {
		"schema_version": DOCUMENT_VERSION,
		"document_type": "campaign_idea_memory",
		"campaign_id": campaign_id,
		"next_sequence": 0,
		"ideas": [],
	}


static func _validate_data(value: Dictionary, campaign_id: String) -> ValidationResult:
	var result := ValidationResultType.new()
	if int(value.get("schema_version", 0)) != DOCUMENT_VERSION:
		result.add_error(
			"invalid_idea_memory_version",
			"Idea memory schema version is invalid.",
			"schema_version"
		)
	if str(value.get("document_type", "")) != "campaign_idea_memory":
		result.add_error(
			"invalid_idea_memory_type",
			"Idea memory document type is invalid.",
			"document_type"
		)
	if str(value.get("campaign_id", "")) != campaign_id:
		result.add_error(
			"idea_memory_campaign_mismatch",
			"Idea memory belongs to a different campaign.",
			"campaign_id"
		)
	if not value.get("ideas", []) is Array:
		result.add_error("invalid_ideas", "Idea memory ideas must be an array.", "ideas")
	for index in range((value.get("ideas", []) as Array).size()):
		var idea = value["ideas"][index]
		if not idea is Dictionary:
			result.add_error("invalid_idea", "Idea entry must be an object.", "ideas.%d" % index)
			continue
		if str(idea.get("category", "")) not in ALLOWED_CATEGORIES:
			result.add_error(
				"invalid_idea_category",
				"Idea category is not allowed.",
				"ideas.%d.category" % index
			)
		if str(idea.get("summary", "")).strip_edges().is_empty():
			result.add_error(
				"invalid_idea_summary",
				"Idea summary cannot be empty.",
				"ideas.%d.summary" % index
			)
	return result


static func _bounded_ideas(ideas: Array) -> Array:
	var output: Array = []
	for idea in ideas:
		if idea is Dictionary:
			output.append((idea as Dictionary).duplicate(true))
	output.sort_custom(_sequence_asc)
	while output.size() > MAX_IDEAS:
		output.pop_front()
	return output


static func _clean_tags(tags: Array) -> Array[String]:
	var result: Array[String] = []
	for tag in tags:
		var clean := str(tag).strip_edges().to_lower()
		if clean.is_empty() or clean in result:
			continue
		result.append(clean)
	return result


static func _string_set(values: Array) -> Dictionary:
	var result := {}
	for value in values:
		var clean := str(value).strip_edges().to_lower()
		if not clean.is_empty():
			result[clean] = true
	return result


static func _idea_has_any_tag(idea: Dictionary, tag_filter: Dictionary) -> bool:
	for tag in idea.get("tags", []):
		if tag_filter.has(str(tag).strip_edges().to_lower()):
			return true
	return false


static func _count_append_result(result: Dictionary, failures: Array[String]) -> void:
	if not bool(result.get("ok", false)):
		failures.append(str(result.get("error", "unknown error")))


static func _fingerprint(source: String) -> String:
	return source.strip_edges().to_lower().sha256_text()


static func _new_id(sequence: int) -> String:
	var entropy := "%d|%d|%s" % [
		sequence,
		Time.get_ticks_usec(),
		Crypto.new().generate_random_bytes(8).hex_encode(),
	]
	return "idea.local.%s" % entropy.sha256_text().substr(0, 24)


static func _sequence_asc(left: Dictionary, right: Dictionary) -> bool:
	return int(left.get("sequence", 0)) < int(right.get("sequence", 0))


static func _sequence_desc(left: Dictionary, right: Dictionary) -> bool:
	return int(left.get("sequence", 0)) > int(right.get("sequence", 0))


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
