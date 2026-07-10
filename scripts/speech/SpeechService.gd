extends Node

const DEFAULT_PROFILE := &"voice.neutral.v1"
const KAELEN_PROFILE := &"voice.kaelen.v1"

signal cache_queue_completed()
signal speech_connection_attempt(attempt: int)
signal speech_connection_established()
# Fires when a spoken clip finishes playing. A clean public re-expose of the
# audio player's native `finished`, so callers can time things off "she stopped
# talking" (e.g. fade N.O.V.A.'s portrait, sequence the cold-open).
signal playback_finished()

var provider := KokoroSpeechProvider.new()
var last_interaction_time: float = 0.0
var last_interaction_name := ""


var speech_connected: bool:
	get:
		return provider.is_ready()


var connection_attempts: int:
	get:
		return provider.connection_attempts()


var active_cache_requests: int:
	get:
		return provider.active_cache_requests()


var is_requesting: bool:
	get:
		return provider.is_requesting()


func _ready() -> void:
	TTSInterface.cache_queue_completed.connect(cache_queue_completed.emit)
	TTSInterface.tts_connection_attempt.connect(speech_connection_attempt.emit)
	TTSInterface.tts_connection_established.connect(speech_connection_established.emit)
	# Deferred: TTSInterface.audio_player is created in its own _ready, which may
	# run after this one depending on autoload order.
	call_deferred("_connect_playback_finished")


func _connect_playback_finished() -> void:
	var ap = TTSInterface.audio_player
	if ap and is_instance_valid(ap) and not ap.finished.is_connected(_on_playback_finished):
		ap.finished.connect(_on_playback_finished)


func _on_playback_finished() -> void:
	playback_finished.emit()


func start_interaction(interaction_name: String) -> void:
	last_interaction_time = Time.get_ticks_msec()
	last_interaction_name = interaction_name
	GenerationDiagnostics.record_lifecycle_timestamp(
		"player_interaction",
		"interaction_clicked",
		"SpeechService",
		{"interaction_name": interaction_name}
	)
	TTSInterface.start_interaction(interaction_name)


func play(
	text: String,
	voice_profile: Variant = KAELEN_PROFILE,
	speed_override: float = -1.0
) -> void:
	if text.strip_edges().is_empty():
		provider.stop()
		return
	var profile_id := resolve_voice_profile(voice_profile)
	var prepared := prepare_text(text, profile_id)
	if prepared.is_empty():
		provider.stop()
		return
	provider.play(prepared, profile_id, speed_override)


func cache(
	text: String,
	voice_profile: Variant = KAELEN_PROFILE,
	speed_override: float = -1.0
) -> void:
	var profile_id := resolve_voice_profile(voice_profile)
	var prepared := prepare_text(text, profile_id)
	if prepared.is_empty():
		return
	provider.cache(prepared, profile_id, speed_override)


func stop() -> void:
	_sequential_queue.clear()
	_sequential_active = false
	provider.stop()


func prepare_text(text: String, voice_profile: Variant) -> String:
	var profile_id := resolve_voice_profile(voice_profile)
	var clean_text := TTSInterface.clean_dialogue_text(text.strip_edges())
	return GlobalState.apply_tone_guard(clean_text, str(profile_id))


func prepare_followup_text(text: String, voice_profile: Variant) -> String:
	var profile_id := resolve_voice_profile(voice_profile)
	var prepared := prepare_text(text, profile_id)
	if not GlobalState.is_kaelen_voice(str(profile_id)):
		prepared = GlobalState.remove_repeated_player_address(prepared)
	return prepared


func resolve_voice_profile(value: Variant) -> StringName:
	var raw := str(value)
	if raw.is_empty() or raw == "neutral":
		return KAELEN_PROFILE
	var canonical := DomainId.canonicalize(raw)
	var registry := GameContentRegistry.shared()
	if registry.voices.has(canonical):
		return canonical
	var faction := registry.faction(raw)
	if faction != null and not faction.voice_profile_id.is_empty():
		return faction.voice_profile_id
	var npc: NpcDefinition = registry.npcs.get(canonical)
	if npc != null:
		return npc.voice_profile_id
	var named_npc: NpcDefinition = registry.npc_by_name(raw)
	if named_npc != null:
		return named_npc.voice_profile_id
	for profile_id in registry.provider_voice_mappings:
		var mapping: Dictionary = registry.provider_voice_mappings[profile_id]
		if str(mapping.get("provider_voice", "")) == raw:
			return DomainId.canonicalize(profile_id)
	return DEFAULT_PROFILE


var _sequential_queue: Array[String] = []
var _sequential_voice: StringName = KAELEN_PROFILE
var _sequential_active: bool = false


func play_sequential(
	lines: Array[String],
	voice_profile: Variant = KAELEN_PROFILE
) -> void:
	_sequential_queue = lines.duplicate()
	_sequential_voice = resolve_voice_profile(voice_profile)
	_sequential_active = true
	if not TTSInterface.audio_player.finished.is_connected(_on_sequential_finished):
		TTSInterface.audio_player.finished.connect(_on_sequential_finished)
	_play_next_sequential()


func _play_next_sequential() -> void:
	if _sequential_queue.is_empty():
		_sequential_active = false
		return
	var next_line := _sequential_queue.pop_front() as String
	provider.play(prepare_text(next_line, _sequential_voice), _sequential_voice)


func _on_sequential_finished() -> void:
	if _sequential_active:
		_play_next_sequential()


func play_for_npc(text: String, npc_reference: Variant) -> void:
	play(text, resolve_voice_profile(npc_reference))


func cache_for_npc(text: String, npc_reference: Variant) -> void:
	cache(text, resolve_voice_profile(npc_reference))


func clean_dialogue_text(text: String) -> String:
	return TTSInterface.clean_dialogue_text(text)


func normalize_tts_pronunciation(text: String) -> String:
	return TTSInterface.normalize_tts_pronunciation(text)


func _simulate_failed_request_for_test() -> void:
	TTSInterface.is_requesting = true
	TTSInterface.call(
		"_on_request_completed",
		HTTPRequest.RESULT_CANT_CONNECT,
		0,
		PackedStringArray(),
		PackedByteArray()
	)
