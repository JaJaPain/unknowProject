class_name LocalModelGateway
extends RefCounted

const OLLAMA_GENERATE_URL := "http://127.0.0.1:11434/api/generate"
const OLLAMA_TAGS_URL := "http://127.0.0.1:11434/api/tags"

const DEFAULT_SMALL_MODEL := "qwen2.5:3b-instruct-q4_K_M"
const DEFAULT_LARGE_MODEL := "gemma4:12b"

const SMALL_DIALOGUE_MODELS: Array[String] = [
	"qwen2.5:3b-instruct-q4_K_M",
	"qwen2.5:3b-instruct",
	"qwen2.5:3b",
	"qwen3:3b",
	"qwen2.5:1.5b-instruct-q4_K_M",
	"qwen2.5:1.5b-instruct",
	"qwen2.5:1.5b",
	"qwen2.5-coder:7b",
	"qwen3:8b",
]

const LARGE_STORY_MODELS: Array[String] = [
	"gemma4:12b",
	"gemma4:latest",
	"qwen3.6:35b-a3b",
	"qwen3:14b",
	"qwen3:8b",
]

const CAPABILITY_PROFILES := {
	"quest_dialogue": "small_dialogue",
	"mechanic_line": "small_dialogue",
	"station_contact_line": "small_dialogue",
	"gossip": "small_dialogue",
	"public_board": "small_dialogue",
	"pickup_handoff": "small_dialogue",
	"kaelen_line": "small_dialogue",
	"campaign_bible": "large_story",
	"faction_batch": "large_story",
	"system_story_pack": "large_story",
	"story_horizon": "large_story",
}

const REQUEST_TIMEOUTS := {
	"quest_dialogue": 15.0,
	"mechanic_line": 8.0,
	"station_contact_line": 8.0,
	"gossip": 8.0,
	"public_board": 8.0,
	"pickup_handoff": 8.0,
	"kaelen_line": 8.0,
	"campaign_bible": 60.0,
	"faction_batch": 45.0,
	"system_story_pack": 60.0,
	"story_horizon": 60.0,
}


static func model_for_capability(
	capability: String,
	active_small_model: String = "",
	active_large_model: String = ""
) -> String:
	var profile := profile_for_capability(capability)
	if profile == "large_story":
		return active_large_model if not active_large_model.is_empty() else DEFAULT_LARGE_MODEL
	return active_small_model if not active_small_model.is_empty() else DEFAULT_SMALL_MODEL


static func select_installed_model(
	installed_names: Array,
	capability: String = "quest_dialogue"
) -> String:
	var preferred := preferred_models_for_capability(capability)
	for preferred_model in preferred:
		if preferred_model in installed_names:
			return preferred_model
	for installed_model in installed_names:
		var clean := str(installed_model)
		if clean.contains("qwen"):
			return clean
	for installed_model in installed_names:
		var clean := str(installed_model)
		if clean.contains("gemma"):
			return clean
	if not installed_names.is_empty():
		return str(installed_names[0])
	return ""


static func preferred_models_for_capability(capability: String) -> Array[String]:
	if profile_for_capability(capability) == "large_story":
		return LARGE_STORY_MODELS.duplicate()
	return SMALL_DIALOGUE_MODELS.duplicate()


static func profile_for_capability(capability: String) -> String:
	var clean := capability.strip_edges()
	return str(CAPABILITY_PROFILES.get(clean, "small_dialogue"))


static func request_timeout(capability: String) -> float:
	return float(REQUEST_TIMEOUTS.get(capability.strip_edges(), 8.0))


static func generation_body(
	capability: String,
	prompt: String,
	active_small_model: String,
	response_format: String = "json",
	options: Dictionary = {},
	active_large_model: String = ""
) -> Dictionary:
	var body := {
		"model": model_for_capability(capability, active_small_model, active_large_model),
		"prompt": prompt,
		"stream": false,
		"options": options.duplicate(true),
	}
	if not response_format.strip_edges().is_empty():
		body["format"] = response_format
	return body


static func diagnostics_context(capability: String, selected_model: String) -> Dictionary:
	return {
		"capability": capability,
		"profile": profile_for_capability(capability),
		"model": selected_model,
	}
