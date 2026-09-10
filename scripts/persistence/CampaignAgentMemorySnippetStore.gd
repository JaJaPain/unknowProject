class_name CampaignAgentMemorySnippetStore
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
const MEMORY_PATH := "agent_memory_snippets.json"
const MAX_AGENTS := 256
const MAX_SNIPPETS_PER_AGENT := 8
const MAX_PROMPT_SNIPPETS := 4

var campaign_path: String
var campaign: Dictionary = {}
var data: Dictionary = {}
var validation := ValidationResultType.new()


static func open(path: String) -> RefCounted:
	var store = load(
		"res://scripts/persistence/CampaignAgentMemorySnippetStore.gd"
	).new()
	store.campaign_path = path.trim_suffix("/")
	store._load_or_create()
	return store


func is_valid() -> bool:
	return validation.is_valid()


func append_snippet(
	agent_id: String,
	display_name: String,
	faction_id: String,
	summary: String,
	tags: Array = [],
	metadata: Dictionary = {}
) -> Dictionary:
	if not is_valid():
		return _failure("Agent memory store is invalid.")
	var clean_agent_id := agent_id.strip_edges()
	var clean_display := display_name.strip_edges()
	var clean_summary := summary.strip_edges()
	if clean_agent_id.is_empty():
		return _failure("Agent id is required.")
	if clean_display.is_empty():
		return _failure("Agent display name is required.")
	if clean_summary.is_empty():
		return _failure("Agent memory summary is required.")
	var next_data := data.duplicate(true)
	var agents: Dictionary = next_data.get("agents", {}).duplicate(true)
	var agent: Dictionary = agents.get(clean_agent_id, {}).duplicate(true)
	if agent.is_empty():
		agent = {
			"agent_id": clean_agent_id,
			"display_name": clean_display,
			"faction_id": faction_id.strip_edges(),
			"next_sequence": 0,
			"snippets": [],
			"created_at_unix": int(Time.get_unix_time_from_system()),
			"updated_at_unix": int(Time.get_unix_time_from_system()),
		}
	else:
		agent["display_name"] = clean_display
		if not faction_id.strip_edges().is_empty():
			agent["faction_id"] = faction_id.strip_edges()
		agent["updated_at_unix"] = int(Time.get_unix_time_from_system())
	var fingerprint := _fingerprint(clean_summary)
	for existing in agent.get("snippets", []):
		if existing is Dictionary \
				and str(existing.get("fingerprint", "")) == fingerprint:
			return {
				"ok": true,
				"duplicate": true,
				"snippet": (existing as Dictionary).duplicate(true),
			}
	var next_sequence := int(agent.get("next_sequence", 0))
	var snippet := {
		"snippet_id": _new_id(clean_agent_id, next_sequence),
		"sequence": next_sequence,
		"summary": clean_summary,
		"tags": _clean_tags(tags),
		"metadata": metadata.duplicate(true),
		"fingerprint": fingerprint,
		"created_at_unix": int(Time.get_unix_time_from_system()),
	}
	var snippets: Array = agent.get("snippets", []).duplicate(true)
	snippets.append(snippet)
	agent["snippets"] = _bounded_snippets(snippets)
	agent["next_sequence"] = next_sequence + 1
	agents[clean_agent_id] = agent
	next_data["agents"] = _bounded_agents(agents)
	var committed := _commit(next_data, "agent_memory_append")
	if not bool(committed.get("ok", false)):
		return committed
	data = next_data
	return {"ok": true, "duplicate": false, "snippet": snippet.duplicate(true)}


func snippets_for_agent(agent_id: String, limit: int = MAX_PROMPT_SNIPPETS) -> Array:
	var clean_agent_id := agent_id.strip_edges()
	var agent: Dictionary = data.get("agents", {}).get(clean_agent_id, {})
	var snippets: Array = agent.get("snippets", []).duplicate(true)
	snippets.sort_custom(_sequence_desc)
	var output: Array = []
	for snippet in snippets:
		if snippet is Dictionary:
			output.append((snippet as Dictionary).duplicate(true))
		if output.size() >= maxi(1, limit):
			break
	return output


func prompt_context(agent_id: String, limit: int = MAX_PROMPT_SNIPPETS) -> String:
	var clean_agent_id := agent_id.strip_edges()
	var agent: Dictionary = data.get("agents", {}).get(clean_agent_id, {})
	if agent.is_empty():
		return (
			"No prior contracts with this agent are recorded yet. "
			+ "Treat the relationship as first-contact or strictly professional."
		)
	var snippets := snippets_for_agent(clean_agent_id, limit)
	if snippets.is_empty():
		return (
			"No prior contracts with this agent are recorded yet. "
			+ "Treat the relationship as first-contact or strictly professional."
		)
	var lines: Array[String] = [
		"Recent memory for %s:" % str(agent.get("display_name", clean_agent_id))
	]
	for snippet in snippets:
		lines.append("- %s" % str(snippet.get("summary", "")))
	return "\n".join(lines)


func kaelen_memory_pull(limit: int = 6) -> Array:
	var all_snippets: Array = []
	for agent in data.get("agents", {}).values():
		if not agent is Dictionary:
			continue
		for snippet in (agent as Dictionary).get("snippets", []):
			if not snippet is Dictionary:
				continue
			var copy: Dictionary = (snippet as Dictionary).duplicate(true)
			copy["agent_id"] = str(agent.get("agent_id", ""))
			copy["display_name"] = str(agent.get("display_name", ""))
			copy["faction_id"] = str(agent.get("faction_id", ""))
			all_snippets.append(copy)
	all_snippets.sort_custom(_sequence_desc)
	var output: Array = []
	for snippet in all_snippets:
		output.append((snippet as Dictionary).duplicate(true))
		if output.size() >= maxi(1, limit):
			break
	return output


func summary() -> Dictionary:
	var total := 0
	var by_agent := {}
	for agent_id in data.get("agents", {}).keys():
		var agent: Dictionary = data["agents"][agent_id]
		var count := (agent.get("snippets", []) as Array).size()
		total += count
		by_agent[str(agent_id)] = count
	return {
		"total_agents": (data.get("agents", {}) as Dictionary).size(),
		"total_snippets": total,
		"by_agent": by_agent,
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
			"Agent memory requires a valid campaign id.",
			"campaign.id"
		)
		return
	var memory_path := "%s/%s" % [campaign_path, MEMORY_PATH]
	if not FileAccess.file_exists(memory_path):
		data = _initial_data(campaign_id)
		var committed := _commit(data, "agent_memory_bootstrap")
		if not bool(committed.get("ok", false)):
			validation.add_error(
				"agent_memory_bootstrap_failed",
				str(committed.get("error", "Agent memory could not be created.")),
				MEMORY_PATH
			)
		return
	var memory_result := DomainJsonType.read_object(memory_path)
	validation.merge(memory_result["validation"], "agent_memory")
	if not validation.is_valid():
		return
	data = memory_result["data"]
	validation.merge(_validate_data(data, campaign_id), "agent_memory")


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
		"document_type": "campaign_agent_memory_snippets",
		"campaign_id": campaign_id,
		"agents": {},
	}


static func _validate_data(value: Dictionary, campaign_id: String) -> ValidationResult:
	var result := ValidationResultType.new()
	if int(value.get("schema_version", 0)) != DOCUMENT_VERSION:
		result.add_error(
			"invalid_agent_memory_version",
			"Agent memory schema version is invalid.",
			"schema_version"
		)
	if str(value.get("document_type", "")) != "campaign_agent_memory_snippets":
		result.add_error(
			"invalid_agent_memory_type",
			"Agent memory document type is invalid.",
			"document_type"
		)
	if str(value.get("campaign_id", "")) != campaign_id:
		result.add_error(
			"agent_memory_campaign_mismatch",
			"Agent memory belongs to a different campaign.",
			"campaign_id"
		)
	if not value.get("agents", {}) is Dictionary:
		result.add_error("invalid_agents", "Agent memory agents must be an object.", "agents")
		return result
	for agent_id in value.get("agents", {}).keys():
		var agent: Variant = value["agents"][agent_id]
		if not agent is Dictionary:
			result.add_error(
				"invalid_agent_memory_record",
				"Agent memory record must be an object.",
				"agents.%s" % str(agent_id)
			)
			continue
		_validate_agent(agent_id, agent, result)
	return result


static func _validate_agent(
	agent_id: Variant,
	agent: Dictionary,
	result: ValidationResult
) -> void:
	var path := "agents.%s" % str(agent_id)
	if str(agent.get("agent_id", "")) != str(agent_id):
		result.add_error("agent_id_key_mismatch", "Agent id must match its key.", path)
	if str(agent.get("display_name", "")).strip_edges().is_empty():
		result.add_error("missing_agent_display", "Agent display name is required.", path)
	if not agent.get("snippets", []) is Array:
		result.add_error("invalid_agent_snippets", "Agent snippets must be an array.", path)
		return
	for index in range((agent.get("snippets", []) as Array).size()):
		var snippet: Variant = agent["snippets"][index]
		if not snippet is Dictionary:
			result.add_error("invalid_agent_snippet", "Snippet must be an object.", "%s.snippets.%d" % [path, index])
			continue
		if str(snippet.get("summary", "")).strip_edges().is_empty():
			result.add_error("missing_snippet_summary", "Snippet summary is required.", "%s.snippets.%d.summary" % [path, index])
		if not snippet.get("tags", []) is Array:
			result.add_error("invalid_snippet_tags", "Snippet tags must be an array.", "%s.snippets.%d.tags" % [path, index])
		if not snippet.get("metadata", {}) is Dictionary:
			result.add_error("invalid_snippet_metadata", "Snippet metadata must be an object.", "%s.snippets.%d.metadata" % [path, index])


static func _bounded_agents(agents: Dictionary) -> Dictionary:
	if agents.size() <= MAX_AGENTS:
		return agents.duplicate(true)
	var keys := agents.keys()
	keys.sort()
	var output := {}
	for index in range(maxi(0, keys.size() - MAX_AGENTS), keys.size()):
		output[keys[index]] = (agents[keys[index]] as Dictionary).duplicate(true)
	return output


static func _bounded_snippets(snippets: Array) -> Array:
	var output: Array = []
	for snippet in snippets:
		if snippet is Dictionary:
			output.append((snippet as Dictionary).duplicate(true))
	output.sort_custom(_sequence_asc)
	while output.size() > MAX_SNIPPETS_PER_AGENT:
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


static func _fingerprint(source: String) -> String:
	return source.strip_edges().to_lower().sha256_text()


static func _new_id(agent_id: String, sequence: int) -> String:
	var entropy := "%s|%d|%d|%s" % [
		agent_id,
		sequence,
		Time.get_ticks_usec(),
		Crypto.new().generate_random_bytes(8).hex_encode(),
	]
	return "agent_memory.local.%s" % entropy.sha256_text().substr(0, 24)


static func _sequence_asc(left: Dictionary, right: Dictionary) -> bool:
	return int(left.get("sequence", 0)) < int(right.get("sequence", 0))


static func _sequence_desc(left: Dictionary, right: Dictionary) -> bool:
	return int(left.get("sequence", 0)) > int(right.get("sequence", 0))


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
