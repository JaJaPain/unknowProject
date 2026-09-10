extends Node

const DEFAULT_PROFILE := &"voice.neutral.v1"
const KAELEN_PROFILE := &"voice.kaelen.v1"
const NOVA_PROFILE := &"voice.nova.v1"
const LATENCY_FILLER_WORDS := ["um", "oh", "well", "ahh"]
const LATENCY_FILLER_WAIT_REASONS := [
	"llm",
	"llm_generation",
	"tts",
	"tts_cache",
	"tts_ready",
]
const LATENCY_FILLER_MIN_QUIET_SECONDS := 0.35
const LATENCY_FILLER_MAX_WAIT_SECONDS := 2.5
# Ambient lines waiting for the current speaker to finish. Small on purpose:
# see play_ambient.
const AMBIENT_QUEUE_MAX := 3
# How often the queue re-checks whether it can move, and how long a queued line
# may wait before it is dropped as stale.
const AMBIENT_DRAIN_POLL_S := 0.25
const AMBIENT_QUEUE_STALE_MS := 20000
var _ambient_queue: Array[Dictionary] = []
var _ambient_drain_accum := 0.0

signal cache_queue_completed()
signal speech_connection_attempt(attempt: int)
signal speech_connection_established()
# Fires when a spoken clip finishes playing. A clean public re-expose of the
# audio player's native `finished`, so callers can time things off "she stopped
# talking" (e.g. fade N.O.V.A.'s portrait, sequence the cold-open).
signal playback_finished()
# Fires when a line passed to play_ambient() ACTUALLY starts playing, which is
# not the same moment it was handed over — it may have queued behind another
# speaker first. Anything that decorates a line while it is spoken (N.O.V.A.'s
# talking portrait, the station welcome hold) must key off this rather than off
# the emit, or it will attach itself to whoever is talking right now instead.
signal ambient_line_started(text: String)

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


var has_pending_cache_work: bool:
	get:
		return provider.has_pending_cache_work()


var is_requesting: bool:
	get:
		return provider.is_requesting()


func _ready() -> void:
	TTSInterface.cache_queue_completed.connect(cache_queue_completed.emit)
	TTSInterface.tts_connection_attempt.connect(speech_connection_attempt.emit)
	TTSInterface.tts_connection_established.connect(speech_connection_established.emit)
	_precache_latency_filler_clips()
	# Deferred: TTSInterface.audio_player is created in its own _ready, which may
	# run after this one depending on autoload order.
	call_deferred("_connect_playback_finished")


func _connect_playback_finished() -> void:
	var ap = TTSInterface.audio_player
	if ap and is_instance_valid(ap) and not ap.finished.is_connected(_on_playback_finished):
		ap.finished.connect(_on_playback_finished)


func _on_playback_finished() -> void:
	playback_finished.emit()
	_drain_ambient_queue()


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
):
	var profile_id := resolve_voice_profile(voice_profile)
	var prepared := prepare_text(text, profile_id)
	if prepared.is_empty():
		return "empty"
	return provider.cache(prepared, profile_id, speed_override)


func stop() -> void:
	_sequential_queue.clear()
	_sequential_active = false
	_sequential_line_started = Callable()
	_sequential_total_lines = 0
	_ambient_queue.clear()
	provider.stop()


## True while a line is being fetched or is actually sounding. Covers both,
## because TTS is asynchronous: between the request going out and audio starting
## the player is silent but very much still busy.
func is_busy() -> bool:
	if provider.is_requesting():
		return true
	var ap = TTSInterface.audio_player
	return ap != null and is_instance_valid(ap) and ap.playing


## Speak a line that ARRIVED UNBIDDEN — N.O.V.A.'s observations, Kaelen's quiet
## moments, ambient chatter. These queue behind whatever is already talking
## instead of cutting it off.
##
## Why this exists: one game event can trigger two speakers. Combat ending fires
## both a post-combat N.O.V.A. line and a quiet-moment beat, and provider.play()
## is a hard cut, so the second line truncated the first mid-sentence.
##
## Player-INITIATED speech still uses play() and still cuts in — when the player
## clicks something, the response to that click is what they want to hear, and
## making them wait out an ambient line would feel unresponsive.
func play_ambient(text: String, voice_profile: Variant = DEFAULT_PROFILE) -> bool:
	if text.strip_edges().is_empty():
		return false
	if _sequential_active or is_busy():
		# Dropped rather than stacked past the cap. A backlog would arrive long
		# after the moment it was reacting to, which reads worse than silence.
		if _ambient_queue.size() >= AMBIENT_QUEUE_MAX:
			return false
		_ambient_queue.append({
			"text": text,
			"voice": voice_profile,
			"queued_ms": Time.get_ticks_msec(),
		})
		return true
	play(text, voice_profile)
	ambient_line_started.emit(text)
	return true


## True while ambient lines are still waiting for their turn. Callers that hold
## something open "until she stops talking" need this: without it they release
## on the CURRENT speaker's playback_finished, which may be someone else
## entirely and may land before the queued line has even begun.
func has_pending_ambient() -> bool:
	return not _ambient_queue.is_empty()


## Polled as well as signal-driven, and this is not belt-and-braces — the
## signal alone is NOT sufficient. `finished` only fires when a clip actually
## plays to the end. A TTS request that fails at the HTTP layer clears
## is_requesting without ever producing audio, and provider.stop() does not emit
## `finished` either. Draining only from the signal therefore meant one failed
## line could wedge the queue forever, and every later ambient line — every
## N.O.V.A. observation, every Kaelen quiet moment — would be silently
## swallowed for the rest of the session.
##
## Polling makes the signal a latency optimisation instead of the only path out.
func _process(delta: float) -> void:
	if _ambient_queue.is_empty():
		_ambient_drain_accum = 0.0
		return
	_ambient_drain_accum += delta
	if _ambient_drain_accum < AMBIENT_DRAIN_POLL_S:
		return
	_ambient_drain_accum = 0.0
	_drain_ambient_queue()


func _drain_ambient_queue() -> void:
	if _ambient_queue.is_empty() or _sequential_active or is_busy():
		return
	# Drop anything that waited so long it is no longer commenting on anything
	# the player still remembers doing.
	var now := Time.get_ticks_msec()
	while not _ambient_queue.is_empty():
		var entry: Dictionary = _ambient_queue.pop_front()
		if now - int(entry.get("queued_ms", now)) > AMBIENT_QUEUE_STALE_MS:
			continue
		var started_text := str(entry.get("text", ""))
		play(started_text, entry.get("voice", DEFAULT_PROFILE))
		ambient_line_started.emit(started_text)
		return


func prepare_text(text: String, voice_profile: Variant) -> String:
	var profile_id := resolve_voice_profile(voice_profile)
	var clean_text := TTSInterface.clean_dialogue_text(text.strip_edges())
	var guarded := GlobalState.apply_tone_guard(clean_text, str(profile_id))
	# Only Kaelen names the player. Everyone else addresses them directly but
	# never by nickname -- implied, not stated. This runs on EVERY prepared line
	# rather than only on follow-ups, which is where the "Indy ... Indy ... Indy"
	# paragraphs were getting through.
	if not GlobalState.is_kaelen_voice(str(profile_id)):
		guarded = GlobalState.strip_player_address(guarded)
	return guarded


func prepare_followup_text(text: String, voice_profile: Variant) -> String:
	var profile_id := resolve_voice_profile(voice_profile)
	# prepare_text already strips every non-Kaelen address, so a follow-up needs
	# nothing extra. Kept as a distinct entry point for its callers.
	return prepare_text(text, profile_id)


# Hard stop on hesitation clips, owned here rather than at a call site.
#
# The loading-screen gate used to live in one UIManager helper, which meant any
# other caller of play_latency_filler_clip silently bypassed it. Filler is a
# POLICY about when the game may make a non-semantic noise, so it belongs with
# the service that makes the noise -- the same reasoning that moved the ambient
# queue's exit condition off a single signal.
var _latency_filler_suppressed: bool = false
var _latency_filler_suppress_reason: String = ""


func set_latency_filler_suppressed(suppressed: bool, reason: String = "") -> void:
	_latency_filler_suppressed = suppressed
	_latency_filler_suppress_reason = reason.strip_edges() if suppressed else ""


func is_latency_filler_suppressed() -> bool:
	return _latency_filler_suppressed


func latency_filler_clip_request(
	speaker_id: String,
	voice_profile: Variant,
	wait_reason: String,
	quiet_seconds: float,
	required_text_ready: bool,
	word_index: int = 0
) -> Dictionary:
	var profile_id := resolve_voice_profile(voice_profile)
	var clean_speaker := speaker_id.strip_edges().to_lower()
	var clean_reason := wait_reason.strip_edges().to_lower()
	if _latency_filler_suppressed:
		return _filler_rejected("suppressed:%s" % _latency_filler_suppress_reason)
	if required_text_ready:
		return _filler_rejected("required_text_ready")
	if quiet_seconds < LATENCY_FILLER_MIN_QUIET_SECONDS:
		return _filler_rejected("quiet_window_too_short")
	if quiet_seconds > LATENCY_FILLER_MAX_WAIT_SECONDS:
		return _filler_rejected("wait_too_long_for_filler")
	if not LATENCY_FILLER_WAIT_REASONS.has(clean_reason):
		return _filler_rejected("not_llm_or_tts_wait")
	if not _is_latency_filler_speaker(clean_speaker, profile_id):
		return _filler_rejected("speaker_not_allowed")
	var word := str(LATENCY_FILLER_WORDS[
		abs(word_index) % LATENCY_FILLER_WORDS.size()
	])
	var speaker_key := "nova" if profile_id == NOVA_PROFILE else "kaelen"
	return {
		"ok": true,
		"word": word,
		"clip_id": "latency_filler.%s.%s" % [speaker_key, word],
		"speaker_id": clean_speaker,
		"voice_profile_id": str(profile_id),
		"source": "prerecorded_latency_filler",
		"semantic_content": false,
		"may_replace_required_text": false,
		"advances_state": false,
		"reveals_facts": false,
		"counts_as_generated_line": false,
	}


func play_latency_filler_clip(
	speaker_id: String,
	voice_profile: Variant,
	wait_reason: String,
	quiet_seconds: float,
	required_text_ready: bool,
	word_index: int = 0
) -> Dictionary:
	var request := latency_filler_clip_request(
		speaker_id,
		voice_profile,
		wait_reason,
		quiet_seconds,
		required_text_ready,
		word_index
	)
	if not bool(request.get("ok", false)):
		return request
	var profile_id := resolve_voice_profile(request.get("voice_profile_id", voice_profile))
	var word := str(request.get("word", "")).strip_edges()
	if word.is_empty():
		return _filler_rejected("empty_filler_word")
	var player_ready := TTSInterface.audio_player != null \
		and is_instance_valid(TTSInterface.audio_player)
	if player_ready:
		provider.play(word, profile_id)
	else:
		request["playback_skipped"] = true
		request["skip_reason"] = "audio_player_unavailable"
	GenerationDiagnostics.record_content_source(
		"latency_filler",
		"prerecorded_latency_filler",
		"SpeechService",
		{
			"clip_id": str(request.get("clip_id", "")),
			"speaker_id": str(request.get("speaker_id", "")),
			"voice_profile_id": str(profile_id),
			"wait_reason": wait_reason.strip_edges().to_lower(),
		}
	)
	return request


func _precache_latency_filler_clips() -> void:
	for profile in [KAELEN_PROFILE, NOVA_PROFILE]:
		for word in LATENCY_FILLER_WORDS:
			provider.cache(str(word), profile)


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
var _sequential_line_started: Callable = Callable()
var _sequential_total_lines: int = 0


func play_sequential(
	lines: Array[String],
	voice_profile: Variant = KAELEN_PROFILE,
	line_started: Callable = Callable()
) -> void:
	_sequential_queue = lines.duplicate()
	_sequential_voice = resolve_voice_profile(voice_profile)
	_sequential_active = true
	_sequential_line_started = line_started
	_sequential_total_lines = lines.size()
	if not TTSInterface.audio_player.finished.is_connected(_on_sequential_finished):
		TTSInterface.audio_player.finished.connect(_on_sequential_finished)
	_play_next_sequential()


func _play_next_sequential() -> void:
	if _sequential_queue.is_empty():
		_sequential_active = false
		_sequential_line_started = Callable()
		_sequential_total_lines = 0
		return
	var next_line := _sequential_queue.pop_front() as String
	var line_index := _sequential_total_lines - _sequential_queue.size()
	if _sequential_line_started.is_valid():
		_sequential_line_started.call(line_index, _sequential_total_lines)
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


func _filler_rejected(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"semantic_content": false,
		"may_replace_required_text": false,
		"advances_state": false,
		"reveals_facts": false,
		"counts_as_generated_line": false,
	}


func _is_latency_filler_speaker(speaker_id: String, profile_id: StringName) -> bool:
	if profile_id == KAELEN_PROFILE:
		return speaker_id.contains("kaelen")
	if profile_id == NOVA_PROFILE:
		return speaker_id.contains("nova") or speaker_id.contains("n.o.v.a")
	return false


func _simulate_failed_request_for_test() -> void:
	TTSInterface.is_requesting = true
	TTSInterface.call(
		"_on_request_completed",
		HTTPRequest.RESULT_CANT_CONNECT,
		0,
		PackedStringArray(),
		PackedByteArray()
	)
