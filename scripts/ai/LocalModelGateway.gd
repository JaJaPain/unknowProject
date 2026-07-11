class_name LocalModelGateway
extends RefCounted

const OLLAMA_GENERATE_URL := "http://127.0.0.1:11434/api/generate"
const OLLAMA_TAGS_URL := "http://127.0.0.1:11434/api/tags"

const DEFAULT_SMALL_MODEL := "qwen3:4b"
const DEFAULT_LARGE_MODEL := "qwen3:8b"

# How long Ollama keeps a model resident in VRAM after a request. Ollama's default
# is "5m", so a quiet stretch mid-session unloads the model and the next line eats
# a cold reload (a top fallback cause — see logs/fallback_summary.txt). A game
# session wants the model to stay hot; "30m" covers normal play gaps.
const MODEL_KEEP_ALIVE := "30m"
# Explicit context windows — REQUIRED on every request. Ollama 0.31+ loads a
# model at its full trained context when num_ctx is absent; for qwen3 that is
# 262144, which turned the 2.3GB 4b into a 43GB allocation (66% spilled to CPU),
# timed out every small call, and deadlocked campaign-bible generation because
# the 8b could never fit beside it (root-caused 2026-07-04, the "stuck at 35%"
# bug). Keep ALL calls per profile at the SAME value so Ollama never reloads
# the model to grow the context mid-session. At these sizes both models fit in
# 16GB VRAM together: 4b@8k ~3.5GB + 8b@16k ~7GB.
const SMALL_NUM_CTX := 8192
const LARGE_NUM_CTX := 16384
# Large story generations are startup/transition jobs, not moment-to-moment
# gameplay. Unload them after each request so 8GB cards do not keep Gemma
# resident beside the small dialogue model and Godot renderer.
const LARGE_MODEL_KEEP_ALIVE := 0

const SMALL_DIALOGUE_MODELS: Array[String] = [
	"qwen3:4b",
	"qwen2.5:3b-instruct-q4_K_M",
	"qwen2.5:3b-instruct",
	"qwen2.5:3b",
	"qwen2.5:1.5b-instruct-q4_K_M",
	"qwen2.5:1.5b-instruct",
	"qwen2.5:1.5b",
	"qwen3:8b",
]

const LARGE_STORY_MODELS: Array[String] = [
	"qwen3:8b",
	"qwen3:14b",
	"gemma4:e4b",
	"gemma4:12b",
	"gemma4:latest",
	"qwen3.6:35b-a3b",
]

const CAPABILITY_PROFILES := {
	"quest_dialogue": "small_dialogue",
	"mechanic_line": "small_dialogue",
	"station_contact_line": "small_dialogue",
	"gossip": "small_dialogue",
	"background_chatter": "small_dialogue",
	"public_board": "small_dialogue",
	"pickup_handoff": "small_dialogue",
	"kaelen_line": "small_dialogue",
	"salvager_profile": "small_dialogue",
	"partial_delivery_line": "small_dialogue",
	"ambient_chat": "small_dialogue",
	"lounge_chat": "small_dialogue",
	"system_names": "large_story",
	"campaign_bible": "large_story",
	"faction_batch": "large_story",
	"system_story_pack": "large_story",
	"story_horizon": "large_story",
	"chapter_plan": "large_story",
	# Director-privileged: the prompt carries nova_memory_flicker (a director-only
	# bible secret), so this must NEVER be downgraded to the small-dialogue model.
	"nova_glitch": "large_story",
}

const REQUEST_TIMEOUTS := {
	"quest_dialogue": 15.0,
	"mechanic_line": 8.0,
	"station_contact_line": 8.0,
	"gossip": 8.0,
	"background_chatter": 12.0,
	"public_board": 8.0,
	"pickup_handoff": 8.0,
	"kaelen_line": 8.0,
	"salvager_profile": 10.0,
	"partial_delivery_line": 10.0,
	# Background beat with no player waiting on it — give the 2-4 line convo
	# room to finish rather than racing an 8s default.
	"ambient_chat": 14.0,
	# Player IS waiting on lounge turns (they just pressed a reply) — keep it
	# tighter; a slow turn falls back to the one-liner path rather than stalling.
	"lounge_chat": 12.0,
	"system_names": 30.0,
	"campaign_bible": 600.0,
	"faction_batch": 45.0,
	"system_story_pack": 60.0,
	"story_horizon": 60.0,
	"chapter_plan": 120.0,
	"nova_glitch": 60.0,
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
	var is_large := profile_for_capability(capability) == "large_story"
	body["keep_alive"] = LARGE_MODEL_KEEP_ALIVE if is_large else MODEL_KEEP_ALIVE
	# Never let Ollama fall back to the model's trained context (see
	# SMALL_NUM_CTX note). Callers may not override this per-request: a single
	# odd num_ctx forces a full model reload and reintroduces the swap thrash.
	(body["options"] as Dictionary)["num_ctx"] = LARGE_NUM_CTX if is_large else SMALL_NUM_CTX
	if not response_format.strip_edges().is_empty():
		body["format"] = response_format
	# Both default models are now Qwen3 (thinking models), for the small dialogue
	# role AND the large story role. Disable Ollama's thinking for every call so
	# the model never leaks <think> reasoning into dialogue or structured output —
	# same failure class as the gemma4 chain-of-thought leak, now handled globally.
	body["think"] = false
	return body


static func diagnostics_context(capability: String, selected_model: String) -> Dictionary:
	return {
		"capability": capability,
		"profile": profile_for_capability(capability),
		"model": selected_model,
	}
