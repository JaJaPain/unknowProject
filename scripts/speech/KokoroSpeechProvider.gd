class_name KokoroSpeechProvider
extends RefCounted

const DEFAULT_PROFILE := &"voice.neutral.v1"


func is_ready() -> bool:
	return TTSInterface.tts_connected


func connection_attempts() -> int:
	return TTSInterface.tts_connection_attempts


func active_cache_requests() -> int:
	return TTSInterface.active_cache_requests


func has_pending_cache_work() -> bool:
	return TTSInterface.active_cache_requests > 0 or not TTSInterface.cache_queue.is_empty()


func is_requesting() -> bool:
	return TTSInterface.is_requesting


func play(text: String, voice_profile_id: StringName, speed_override: float = -1.0) -> void:
	var delivery := resolve_delivery(voice_profile_id, speed_override)
	TTSInterface.play_dialogue_audio(
		text,
		delivery["provider_voice"],
		delivery["speed"]
	)


func cache(text: String, voice_profile_id: StringName, speed_override: float = -1.0):
	var delivery := resolve_delivery(voice_profile_id, speed_override)
	return TTSInterface.cache_dialogue_audio(
		text,
		delivery["provider_voice"],
		delivery["speed"]
	)


func stop() -> void:
	TTSInterface.play_dialogue_audio("")


func resolve_delivery(
	voice_profile_id: StringName,
	speed_override: float = -1.0
) -> Dictionary:
	var registry := GameContentRegistry.shared()
	var current_id := voice_profile_id
	var visited: Dictionary = {}
	while not current_id.is_empty() and not visited.has(current_id):
		visited[current_id] = true
		var mapping := registry.provider_voice(current_id)
		if not mapping.is_empty():
			return {
				"provider_voice": str(mapping.get("provider_voice", "af_aoede")),
				"speed": (
					speed_override
					if speed_override >= 0.0
					else float(mapping.get("speed", 1.0))
				),
			}
		var profile: VoiceProfileDefinition = registry.voices.get(current_id)
		current_id = (
			profile.fallback_voice_profile_id
			if profile != null
			else StringName()
		)
	var fallback := registry.provider_voice(DEFAULT_PROFILE)
	return {
		"provider_voice": str(fallback.get("provider_voice", "af_aoede")),
		"speed": speed_override if speed_override >= 0.0 else float(fallback.get("speed", 1.0)),
	}
