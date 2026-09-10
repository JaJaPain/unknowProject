extends Node

const TTS_URL = "http://127.0.0.1:5000/tts"
const PYTHON_SETTING := "application/run/python_executable"
const PYTHON_ENV_VAR := "SPACEGAME_PYTHON"
const MAX_BACKGROUND_CACHE_REQUESTS := 2
const _TTS_HEARTBEAT_SECONDS := 30.0
var http_request: HTTPRequest
var audio_player: AudioStreamPlayer
var is_requesting: bool = false
var tts_request_time: float = 0.0

var last_interaction_time: float = 0.0
var last_interaction_name: String = ""
# Cache key shape: "<voice_id>|<text>" (changed from text-only at the
# per-NPC voice refactor). The same line spoken in two NPC voices
# caches separately. For callers that don't override the voice, we use
# the resolved Kokoro voice for the faction — so legacy "neutral"
# callers key under the resolved provider voice, which still has a unique key
# per text and matches the old behavior on the lookup side.
# (Old caller's existing cache entries on disk are NOT carried over
# since the project doesn't persist TTS cache between sessions — this
# is a one-session in-memory cache only.)
var tts_audio_cache: Dictionary = {}

# ── Pre-TTS dialogue verify (ToneGuard) ─────────────────────────────────────
# "Shiny" is Broker Kaelen's vocative for the player pilot. She uses it
# every line. Every other speaker in the game should NOT use it — it
# leaks her voice onto Jenna, minor NPCs, future quest givers, and
# anything else routed through the TTS pipeline. The LLM prompt for the
# mechanic greeting already forbids it, but a 1.5b model slips. This
# verify is the safety net that runs in BOTH play_dialogue_audio and
# cache_dialogue_audio so the cached audio file matches the text on
# screen (no audible drift between what the player sees and hears).
#
# The actual rules live on GlobalState (apply_tone_guard) so the same
# rewriting runs on the on-screen text and stays in sync.

signal cache_queue_completed()
var active_cache_requests: int = 0

signal tts_connection_attempt(attempt: int)
signal tts_connection_established()

var tts_connected: bool = false
var tts_connection_attempts: int = 0
var cache_queue: Array = []
var _tts_heartbeat_in_flight: bool = false

func start_interaction(interaction_name: String):
	last_interaction_time = Time.get_ticks_msec()
	last_interaction_name = interaction_name
	GlobalState.trace("[TRACE] [TTSInterface] start_interaction: '%s' at system time: %d ms" % [interaction_name, last_interaction_time])


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Ensure dedicated Voice bus exists in AudioServer and routes to Master
	var voice_bus_idx = AudioServer.get_bus_index("Voice")
	if voice_bus_idx == -1:
		AudioServer.add_bus()
		voice_bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(voice_bus_idx, "Voice")
	
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.timeout = 10.0
	http_request.request_completed.connect(_on_request_completed)
	
	audio_player = AudioStreamPlayer.new()
	audio_player.bus = "Voice"
	add_child(audio_player)
	audio_player.finished.connect(_on_audio_player_finished)
	
	if "--baseline-offline" in OS.get_cmdline_user_args():
		print("[TTSInterface] Baseline offline mode: service discovery disabled.")
		return

	_discover_and_verify_tts()
	_schedule_tts_heartbeat()
	
	# Pre-cache static completion and abandon messages
	cache_dialogue_audio("Pleasure doing business with you, pilot. Payout transferred and brokerage fee deducted. Check back soon.", "neutral")
	cache_dialogue_audio("Contract dumped? You're costing me credit margins. I don't forget when people waste my time.", "neutral")

# Play a line of dialogue. Legacy signature kept for the Kaelen/quest paths:
#   play_dialogue_audio(text, faction)
# Per-NPC callers use the new signature:
#   play_dialogue_audio(text, voice_id_override, speed_override)
# If `voice_id_override` is empty the faction is resolved via
# get_voice_for_faction(). Speed defaults to 1.0.
# Cache key is "<voice>|<cleaned_text>" so different voices never
# collide on the same line.
func _schedule_tts_heartbeat() -> void:
	get_tree().create_timer(_TTS_HEARTBEAT_SECONDS, true, false, true).timeout.connect(
		_run_tts_heartbeat
	)


func _run_tts_heartbeat() -> void:
	if _tts_heartbeat_in_flight:
		_schedule_tts_heartbeat()
		return
	_tts_heartbeat_in_flight = true
	var probe := HTTPRequest.new()
	add_child(probe)
	probe.timeout = 2.0
	probe.request_completed.connect(func(result, response_code, _headers, body):
		probe.queue_free()
		_tts_heartbeat_in_flight = false
		var healthy := false
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json := JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				var data: Variant = json.get_data()
				healthy = data is Dictionary and data.get("status") == "ok" \
					and data.get("pipeline_ready") == true
		if not healthy:
			tts_connected = false
			GenerationDiagnostics.record_event(
				"tts_watchdog", "heartbeat_service_down", "tts_interface", {}
			)
			_discover_and_verify_tts()
		_schedule_tts_heartbeat()
	)
	if probe.request("http://127.0.0.1:5000/health") != OK:
		probe.queue_free()
		_tts_heartbeat_in_flight = false
		tts_connected = false
		_discover_and_verify_tts()
		_schedule_tts_heartbeat()


# Pre-baked clips for authored lines, so a fight never waits on a TTS round
# trip. The manifest maps "voice|text" to a filename; keying on the pair avoids
# needing the same hashing scheme in GDScript and in the bake script.
#
# The DATA FILE remains the source of truth -- these are a derived build
# artifact. Swapping in a better TTS model means deleting the folder and
# re-running tools/bake_taunt_audio.py.
const BAKED_AUDIO_DIR := "res://assets/audio/taunts"
const BAKED_MANIFEST := "res://assets/audio/taunts/manifest.json"
var _baked_clips: Dictionary = {}
var _baked_loaded: bool = false

# ── English-only baked layers ─────────────────────────────────────────────────
# Two newer bakes, both ENGLISH ONLY and both strictly optional:
#   cast_en          F5-TTS clones of N.O.V.A. and Kaelen (their authored lines)
#   taunts_orpheus   Orpheus renders of the enemy taunt pool
#
# Abe's rule, and the reason every lookup here returns null instead of failing:
# localization CANNOT use pre-baked English audio, so the game must always be
# able to synthesize these lines live through Kokoro. A missing clip is not an
# error, it is the normal case in any non-English build. Nothing in this file may
# ever make a baked clip a hard requirement.
const CAST_AUDIO_DIR := "res://assets/audio/cast_en"
const CAST_MANIFEST := "res://assets/audio/cast_en/manifest.json"
const ORPHEUS_AUDIO_DIR := "res://assets/audio/taunts_orpheus"
const ORPHEUS_MANIFEST := "res://assets/audio/taunts_orpheus/manifest.json"

# Key building and voice identification live in a PURE module so they can be
# tested headlessly -- this file depends on autoloads and cannot be instantiated
# in a --script run, and untested lookup rules fail silently rather than loudly.
const BakedIndex = preload("res://scripts/domain/BakedAudioIndex.gd")

var _cast_clips: Dictionary = {}
var _orpheus_clips: Dictionary = {}
var _flat_loaded: Dictionary = {}


## True only when the game is actually running in English. Every baked layer is
## gated on this: serving English audio for a translated line would be worse than
## serving nothing, because the fallback path produces the right words.
func _is_english_locale() -> bool:
	return BakedIndex.is_english(TranslationServer.get_locale())


## Load a flat {key: filename} manifest once. Returns the dictionary, empty when
## the bake has not been run -- which is a normal state, not a failure.
func _load_flat_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _flat_clips(path: String, cache: String) -> Dictionary:
	if not _flat_loaded.get(cache, false):
		_flat_loaded[cache] = true
		var loaded := _load_flat_manifest(path)
		if cache == "cast":
			_cast_clips = loaded
		else:
			_orpheus_clips = loaded
		if not loaded.is_empty():
			print("[TTSInterface] %d pre-baked %s clips available." % [loaded.size(), cache])
	return _cast_clips if cache == "cast" else _orpheus_clips


## Which fixed-cast character a voice belongs to, or "" for anyone else.
## Matches on both the profile id and the raw provider voice, because callers
## reach this function through several different paths.
func _cast_character_for_voice(voice_id: String) -> String:
	return BakedIndex.cast_character_for_voice(voice_id, GlobalState.KAELEN_VOICE_ID)


## The Kokoro LEAD name out of a blend string ("am_onyx[0.7]+am_michael[0.3]"
## -> "am_onyx"). Returns "" when this is not a blend, so non-taunt voices skip
## the Orpheus layer entirely.
func _lead_voice_of(voice_id: String) -> String:
	return BakedIndex.lead_voice_of(voice_id)


## A baked N.O.V.A. or Kaelen line, or null to synthesize live.
## `character` is "nova" or "kaelen".
func cast_stream_for(character: String, clean_text: String) -> AudioStream:
	if not _is_english_locale():
		return null
	var clips := _flat_clips(CAST_MANIFEST, "cast")
	var key := BakedIndex.cast_key(character, clean_text)
	if key.is_empty():
		return null
	var name := str(clips.get(key, ""))
	if name.is_empty():
		return null
	var path := "%s/%s" % [CAST_AUDIO_DIR, name]
	if not FileAccess.file_exists(path):
		return null
	return AudioStreamWAV.load_from_file(path)


## A baked Orpheus taunt for a Kokoro lead voice, or null to fall through.
## Takes the lead NAME (e.g. "am_onyx"), not the blend string.
func orpheus_taunt_stream_for(lead_voice: String, clean_text: String) -> AudioStream:
	if not _is_english_locale():
		return null
	var voice := BakedIndex.orpheus_voice_for_lead(lead_voice)
	var key := BakedIndex.orpheus_key(voice, clean_text)
	if key.is_empty():
		return null
	var clips := _flat_clips(ORPHEUS_MANIFEST, "orpheus")
	var name := str(clips.get(key, ""))
	if name.is_empty():
		return null
	var path := "%s/%s" % [ORPHEUS_AUDIO_DIR, name]
	if not FileAccess.file_exists(path):
		return null
	return AudioStreamWAV.load_from_file(path)


func _load_baked_manifest() -> void:
	if _baked_loaded:
		return
	_baked_loaded = true
	if not FileAccess.file_exists(BAKED_MANIFEST):
		return
	var file := FileAccess.open(BAKED_MANIFEST, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary and (parsed as Dictionary).get("clips", null) is Dictionary:
		_baked_clips = (parsed as Dictionary)["clips"]
		print("[TTSInterface] %d pre-baked clips available." % _baked_clips.size())


# Returns a ready AudioStream for an authored line, or null when this line was
# never baked (a newly written line, or one edited since the last bake). Loaded
# from the file directly rather than through the import pipeline, so generated
# audio needs no editor reimport.
func baked_stream_for(
	voice_id: String,
	clean_text: String,
	speed: float = -1.0,
	pause: float = -1.0
) -> AudioStream:
	_load_baked_manifest()
	if _baked_clips.is_empty():
		return null
	# The manifest key carries the DELIVERY, not just the words. Keying on
	# voice|text alone is coarser than the file identity (the filename hashes
	# speed and pause too), so a line re-timed later would have been served its
	# old audio -- right words, wrong performance, and silent about it.
	# A miss falls through to live synthesis, which is correct, not a failure.
	var name := str(_baked_clips.get(
		"%s|%s|%.2f|%.2f" % [voice_id, clean_text, speed, pause], ""
	))
	if name.is_empty():
		return null
	var path := "%s/%s" % [BAKED_AUDIO_DIR, name]
	if not FileAccess.file_exists(path):
		return null
	return AudioStreamOggVorbis.load_from_file(path)


# Cache identity for one rendered clip. Delivery is part of the identity: the
# same words at a different speed or with a different pause are a different
# recording, and keying on voice|text alone would hand back whichever was
# rendered first.
func _delivery_cache_key(
	voice_id: String,
	clean_text: String,
	speed: float,
	pause: float,
	style: float
) -> String:
	var key := voice_id + "|" + clean_text
	if speed > 0.0:
		key += "|s%.2f" % speed
	if pause >= 0.0:
		key += "|p%.2f" % pause
	# Style was missing here and it aliases: the same words in the same voice at
	# the same speed but a different style are a different recording, and the key
	# would have handed back whichever was synthesised first.
	key += "|y%.2f" % style
	return key


func play_dialogue_audio(text: String, voice_id_override: Variant = "neutral", speed_override: float = -1.0, style_scale: float = 1.0, pause_seconds: float = -1.0):
	# Support legacy call: play_dialogue_audio(text, faction_string)
	# Detect by checking if voice_id_override is a known faction OR if
	# the caller passed a 2-arg combo. We resolve the voice from
	# either the explicit override (per-NPC) or the faction (legacy).
	var voice_id: String
	if typeof(voice_id_override) == TYPE_STRING and (voice_id_override == "" or _is_known_faction(voice_id_override)):
		var faction: String = voice_id_override
		voice_id = get_voice_for_faction(faction)
		speed_override = 1.0
	else:
		voice_id = str(voice_id_override)
		if speed_override < 0.0:
			speed_override = 1.0

	tts_request_time = Time.get_ticks_msec()

	if is_requesting:
		http_request.cancel_request()
		is_requesting = false

	if audio_player.playing:
		audio_player.stop()
		AudioManager.unduck_audio()

	text = text.strip_edges()
	# Clean up meta headers, details, options or empty spaces to avoid reading formatting
	var clean_text = clean_dialogue_text(text)
	if clean_text == "":
		GlobalState.trace("[TRACE] [TTSInterface] Cleaned text is empty, skipping speech.")
		return

	# Tone guard: rewrite speaker-voice leaks for non-Kaelen speakers so
	# "Shiny" (Kaelen's vocative) becomes "Indy" before TTS hears it.
	# Runs on the already-cleaned text. Logs a one-line trace when a
	# substitution happens so the editor console shows the swap.
	var tone_guarded: String = GlobalState.apply_tone_guard(clean_text, voice_id)
	if tone_guarded != clean_text:
		GlobalState.trace("[TRACE] [TTSInterface] Tone guard rewrote line for voice '%s': '%s' -> '%s'" % [voice_id, clean_text, tone_guarded])
		clean_text = tone_guarded
	clean_text = normalize_tts_pronunciation(clean_text)
		
	var elapsed_str = ""
	if last_interaction_time > 0.0:
		elapsed_str = " (Elapsed since '%s': %.3fs)" % [last_interaction_name, (tts_request_time - last_interaction_time) / 1000.0]
		
	var cache_key: String = _delivery_cache_key(
		voice_id, clean_text, speed_override, pause_seconds, style_scale
	)
	# A pre-baked clip beats both the memory cache and the network: it is on
	# disk, it is exactly what was approved, and it needs no TTS server at all.
	if not tts_audio_cache.has(cache_key):
		# Best available recording wins, then the network. Order is quality
		# order, and EVERY step returns null rather than failing, so the chain
		# degrades to live synthesis instead of to silence. That matters most in
		# a non-English build, where all three baked layers miss by design.
		var baked: AudioStream = cast_stream_for(
			_cast_character_for_voice(voice_id), clean_text
		)
		if baked == null:
			baked = orpheus_taunt_stream_for(_lead_voice_of(voice_id), clean_text)
		if baked == null:
			baked = baked_stream_for(
				voice_id, clean_text, speed_override, pause_seconds
			)
		if baked != null:
			tts_audio_cache[cache_key] = baked
	# Check cache first!
	if tts_audio_cache.has(cache_key):
		var stream = tts_audio_cache[cache_key]
		audio_player.stream = stream
		audio_player.play()
		AudioManager.duck_audio() # Duck background audio
		var play_now = Time.get_ticks_msec()
		var total_elapsed_str = ""
		if last_interaction_time > 0.0:
			total_elapsed_str = " (Total since '%s': %.3fs)" % [last_interaction_name, (play_now - last_interaction_time) / 1000.0]
		GlobalState.trace("[TRACE] [TTSInterface] play_dialogue_audio CACHE HIT at: %d ms%s. voice=%s. Playing immediately!%s" % [tts_request_time, elapsed_str, voice_id, total_elapsed_str])
		return
		
	GlobalState.trace("[TRACE] [TTSInterface] play_dialogue_audio CACHE MISS at: %d ms%s. voice=%s" % [tts_request_time, elapsed_str, voice_id])
	
	is_requesting = true
	var payload = {
		"text": clean_text,
		"voice": voice_id,
		"speed": speed_override,
		"style_scale": style_scale
	}
	# Only sent when the caller asked for a specific gap, so the server keeps
	# applying its own default everywhere else.
	if pause_seconds >= 0.0:
		payload["pause_seconds"] = pause_seconds
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	
	# Print statement to help debugging in console
	print("[TTSInterface] Requesting speech for: ", clean_text, " using voice: ", voice_id, " speed: ", speed_override)
	var err = http_request.request(TTS_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		print("[TTSInterface] Failed to initiate HTTP request. Error code: ", err)
		is_requesting = false

# Background pre-cache. Same call-shape change as play_dialogue_audio:
#   cache_dialogue_audio(text, faction)              # legacy, resolves to a provider voice
#   cache_dialogue_audio(text, voice_id, speed)      # per-NPC, speed is the override
# Empty voice_id means "use faction". Speed <0 means "default 1.0".
func cache_dialogue_audio(text: String, voice_id_or_faction: String = "neutral", speed: float = -1.0, style_scale: float = 1.0):
	text = text.strip_edges()
	var clean_text = clean_dialogue_text(text)
	if clean_text == "":
		return "empty"
	# Resolve voice_id from the second argument
	var voice_id: String
	if _is_known_faction(voice_id_or_faction):
		voice_id = get_voice_for_faction(voice_id_or_faction)
		speed = 1.0
	else:
		voice_id = voice_id_or_faction if voice_id_or_faction != "" else "af_aoede"
		if speed < 0.0:
			speed = 1.0

	# Tone guard (see play_dialogue_audio). The cached audio must match
	# what gets played — running the rewrite here keeps cache_key and
	# the on-disk file aligned with the verify rules. A line cached
	# pre-verify and played post-verify would sound different than the
	# on-screen text.
	clean_text = GlobalState.apply_tone_guard(clean_text, voice_id)
	clean_text = normalize_tts_pronunciation(clean_text)

	var cache_key: String = voice_id + "|" + clean_text
	if tts_audio_cache.has(cache_key):
		GenerationDiagnostics.record_lifecycle_timestamp(
			"tts_cache",
			"tts_ready",
			"TTSInterface",
			{
				"voice_id": voice_id,
				"text_hash": clean_text.hash(),
				"cache_state": "already_cached",
			}
		)
		return "already_cached"
		
	if not tts_connected or active_cache_requests >= MAX_BACKGROUND_CACHE_REQUESTS:
		_enqueue_cache_request(cache_key, clean_text, voice_id, speed, style_scale)
		if not tts_connected:
			GlobalState.trace("[TRACE] [TTSInterface] Queueing cache request (TTS not connected): %d voice=%s" % [clean_text.hash(), voice_id])
		else:
			GlobalState.trace("[TRACE] [TTSInterface] Queueing cache request (cache throttle): %d voice=%s" % [clean_text.hash(), voice_id])
		return "queued"

	_start_background_cache_request(cache_key, clean_text, voice_id, speed, style_scale)
	return "started"


func _enqueue_cache_request(
	cache_key: String,
	clean_text: String,
	voice_id: String,
	speed: float,
	style_scale: float
) -> void:
	for item in cache_queue:
		if str(item.get("key", "")) == cache_key:
			return
	cache_queue.append({
		"key": cache_key,
		"text": clean_text,
		"voice_id": voice_id,
		"speed": speed,
		"style_scale": style_scale,
	})


func _start_background_cache_request(
	cache_key: String,
	clean_text: String,
	voice_id: String,
	speed: float,
	style_scale: float
) -> void:
	# Create a dynamic HTTPRequest node for caching
	var temp_http = HTTPRequest.new()
	add_child(temp_http)
	temp_http.timeout = 15.0
	
	var payload = {
		"text": clean_text,
		"voice": voice_id,
		"speed": speed,
		"style_scale": style_scale
	}
	var json_str = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]

	active_cache_requests += 1
	GenerationDiagnostics.record_lifecycle_timestamp(
		"tts_cache",
		"tts_cache_started",
		"TTSInterface",
		{
			"voice_id": voice_id,
			"text_hash": clean_text.hash(),
			"active_cache_requests": active_cache_requests,
		}
	)
	GlobalState.trace("[TRACE] [TTSInterface] Background caching started for text hash: %d (len: %d), active: %d using voice: %s speed: %.1f" % [clean_text.hash(), clean_text.length(), active_cache_requests, voice_id, speed])
	
	temp_http.request_completed.connect(func(result, response_code, headers, body):
		temp_http.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var stream = load_wav_from_buffer(body)
			if stream:
				tts_audio_cache[cache_key] = stream
				GenerationDiagnostics.record_lifecycle_timestamp(
					"tts_cache",
					"tts_ready",
					"TTSInterface",
					{
						"voice_id": voice_id,
						"text_hash": clean_text.hash(),
						"response_code": response_code,
					}
				)
				GlobalState.trace("[TRACE] [TTSInterface] Background caching completed for text hash: %d voice=%s" % [clean_text.hash(), voice_id])
			else:
				print("[TTSInterface] Background cache parsing failed for text hash: ", clean_text.hash())
				_record_tts_cache_failure(
					"audio_parse_failed",
					voice_id,
					clean_text,
					response_code,
					result
				)
		else:
			print("[TTSInterface] Background cache request failed. Code: ", response_code)
			_record_tts_cache_failure(
				"http_or_timeout_failed",
				voice_id,
				clean_text,
				response_code,
				result
			)
			
		active_cache_requests -= 1
		GlobalState.trace("[TRACE] [TTSInterface] Active cache requests left: %d" % active_cache_requests)
		_drain_cache_queue()
	)
	
	var err = temp_http.request(TTS_URL, headers, HTTPClient.METHOD_POST, json_str)
	if err != OK:
		temp_http.queue_free()
		_record_tts_cache_failure(
			"request_start_failed_%d" % err,
			voice_id,
			clean_text,
			0,
			err
		)
		active_cache_requests -= 1
		_drain_cache_queue()


func _record_tts_cache_failure(
	reason: String,
	voice_id: String,
	clean_text: String,
	response_code: int,
	result_code: int
) -> void:
	GenerationDiagnostics.record_lifecycle_timestamp(
		"tts_cache",
		"tts_failed",
		"TTSInterface",
		{
			"failure_reason": reason,
			"voice_id": voice_id,
			"text_hash": clean_text.hash(),
			"response_code": response_code,
			"result": result_code,
		}
	)


func _drain_cache_queue() -> void:
	active_cache_requests = maxi(active_cache_requests, 0)
	while tts_connected \
			and active_cache_requests < MAX_BACKGROUND_CACHE_REQUESTS \
			and not cache_queue.is_empty():
		var item: Dictionary = cache_queue.pop_front()
		var cache_key := str(item.get("key", ""))
		if cache_key.is_empty() or tts_audio_cache.has(cache_key):
			continue
		_start_background_cache_request(
			cache_key,
			str(item.get("text", "")),
			str(item.get("voice_id", "af_aoede")),
			float(item.get("speed", 1.0)),
			float(item.get("style_scale", 1.0))
		)
	if active_cache_requests <= 0 and cache_queue.is_empty():
		active_cache_requests = 0
		cache_queue_completed.emit()

# Returns true if the given string matches one of the legacy faction
# names that callers pass as the 2nd arg of play_dialogue_audio /
# cache_dialogue_audio. Used by the voice_id override logic to
# disambiguate "this is a faction" from "this is a Kokoro voice id".
func _is_known_faction(s: String) -> bool:
	match s.to_lower():
		"zenith", "aurelia", "vanguard", "neutral", "":
			return true
		_:
			return false

func clean_dialogue_text(text: String) -> String:
	# Strip off the "--- Contract Details ---" block or other metadata to only speak narrative
	var details_idx = text.find("--- Contract Details ---")
	if details_idx != -1:
		text = text.substr(0, details_idx).strip_edges()
	
	# Strip off offline backup notes
	text = text.replace(" [Offline Backup]", "")
	
	# Strip voice direction stage cues in parentheses e.g. (spoken softly), (with tension)
	var regex_paren = RegEx.new()
	regex_paren.compile("\\([^)]*\\)")
	text = regex_paren.sub(text, "", true)
	
	# Strip bracketed cues e.g. [sighs], [pause], [static] — but only for broker dialogue
	# (radio chatter uses [static] intentionally so this only runs on dialogue paths)
	var regex_bracket = RegEx.new()
	regex_bracket.compile("\\[[^\\]]*\\]")
	text = regex_bracket.sub(text, "", true)
	
	# Strip asterisk emphasis e.g. *sighs*, *leans forward*
	var regex_asterisk = RegEx.new()
	regex_asterisk.compile("\\*[^*]*\\*")
	text = regex_asterisk.sub(text, "", true)
	
	# Collapse multiple spaces left behind
	var regex_spaces = RegEx.new()
	regex_spaces.compile(" {2,}")
	text = regex_spaces.sub(text, " ", true)
	
	return text.strip_edges()


func normalize_tts_pronunciation(text: String) -> String:
	var words := text.split(" ", false)
	var output: Array[String] = []
	for word in words:
		output.append(_normalize_tts_word(word))
	return " ".join(output)


func _normalize_tts_word(word: String) -> String:
	var prefix := ""
	var core := word
	var suffix := ""
	while not core.is_empty() and not _is_ascii_alnum(core.substr(0, 1)):
		prefix += core.substr(0, 1)
		core = core.substr(1)
	while not core.is_empty() and not _is_ascii_alnum(core.substr(core.length() - 1, 1)):
		suffix = core.substr(core.length() - 1, 1) + suffix
		core = core.substr(0, core.length() - 1)
	if core.length() < 3 or not _is_all_caps_word(core):
		return word
	if core in ["AI", "HP", "LLM", "NPC", "PG", "ROE", "SC", "TTS", "UI"]:
		return word
	return prefix + core.substr(0, 1) + core.substr(1).to_lower() + suffix


func _is_all_caps_word(text: String) -> bool:
	var has_letter := false
	for i in range(text.length()):
		var ch := text.substr(i, 1)
		if ch >= "A" and ch <= "Z":
			has_letter = true
			continue
		if ch >= "0" and ch <= "9":
			continue
		return false
	return has_letter


func _is_ascii_alnum(ch: String) -> bool:
	return (ch >= "A" and ch <= "Z") \
		or (ch >= "a" and ch <= "z") \
		or (ch >= "0" and ch <= "9")

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	is_requesting = false
	var now = Time.get_ticks_msec()
	var elapsed = (now - tts_request_time) / 1000.0
	var elapsed_str = ""
	if last_interaction_time > 0.0:
		elapsed_str = " (Total since '%s': %.3fs)" % [last_interaction_name, (now - last_interaction_time) / 1000.0]
	GlobalState.trace("[TRACE] [TTSInterface] HTTP response received. Time elapsed since request: %.3fs%s. Result: %d Response code: %d" % [elapsed, elapsed_str, result, response_code])
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("[TTSInterface] Kokoro TTS request failed. Response code: ", response_code)
		return
		
	var start_decode = Time.get_ticks_msec()
	var stream = load_wav_from_buffer(body)
	var decode_elapsed = Time.get_ticks_msec() - start_decode
	GlobalState.trace("[TRACE] [TTSInterface] WAV decoding completed in: %dms." % decode_elapsed)
	
	if stream:
		audio_player.stream = stream
		audio_player.play()
		AudioManager.duck_audio() # Duck background audio
		var play_now = Time.get_ticks_msec()
		var total_elapsed_str = ""
		if last_interaction_time > 0.0:
			total_elapsed_str = " (Total since '%s': %.3fs)" % [last_interaction_name, (play_now - last_interaction_time) / 1000.0]
		GlobalState.trace("[TRACE] [TTSInterface] Playing speech audio stream. Total time since play_dialogue_audio called: %.3fs%s" % [(play_now - tts_request_time) / 1000.0, total_elapsed_str])
	else:
		print("[TTSInterface] Failed to parse WAV buffer from TTS response.")

func load_wav_from_buffer(bytes: PackedByteArray) -> AudioStreamWAV:
	if bytes.size() < 44:
		print("[TTSInterface] Byte array too small to parse as WAV.")
		return null
		
	var riff_header = bytes.slice(0, 4).get_string_from_ascii()
	var wave_header = bytes.slice(8, 12).get_string_from_ascii()
	if riff_header != "RIFF" or wave_header != "WAVE":
		print("[TTSInterface] Invalid WAV header, expected RIFF and WAVE.")
		return null
		
	var stream = AudioStreamWAV.new()
	stream.mix_rate = 24000
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	
	var idx = 12
	var found_data = false
	var data_offset = 44
	var data_length = bytes.size() - 44
	
	while idx < bytes.size() - 8:
		var chunk_name = bytes.slice(idx, idx + 4).get_string_from_ascii()
		var chunk_size = bytes.decode_u32(idx + 4)
		if chunk_name == "fmt ":
			if idx + 20 <= bytes.size():
				var channels = bytes.decode_u16(idx + 10)
				var sample_rate = bytes.decode_u32(idx + 12)
				var bits_per_sample = bytes.decode_u16(idx + 20)
				stream.mix_rate = sample_rate
				stream.stereo = (channels == 2)
				if bits_per_sample == 8:
					stream.format = AudioStreamWAV.FORMAT_8_BITS
				elif bits_per_sample == 16:
					stream.format = AudioStreamWAV.FORMAT_16_BITS
		elif chunk_name == "data":
			data_offset = idx + 8
			data_length = chunk_size
			found_data = true
			break
		idx += 8 + chunk_size
		
	if found_data:
		stream.data = bytes.slice(data_offset, data_offset + data_length)
	else:
		stream.data = bytes.slice(44)
		
	return stream

func _discover_and_verify_tts():
	tts_connection_attempts += 1
	tts_connection_attempt.emit(tts_connection_attempts)
	GlobalState.trace("[TRACE] [TTSInterface] Verifying TTS server connection (attempt %d)..." % tts_connection_attempts)
	
	var check_http = HTTPRequest.new()
	add_child(check_http)
	check_http.timeout = 2.0
	check_http.request_completed.connect(func(result, response_code, headers, body):
		check_http.queue_free()
		var success = false
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				var data = json.get_data()
				if data is Dictionary and data.get("status") == "ok" and data.get("pipeline_ready") == true:
					success = true
					
		if success:
			GlobalState.trace("[TRACE] [TTSInterface] TTS server successfully verified and pipeline is ready.")
			tts_connected = true
			tts_connection_established.emit()
			
			# Process queued cache requests. queue items carry the
			# resolved voice_id + speed (set by cache_dialogue_audio),
			# not a faction — re-issue them via the legacy faction
			# path is wrong here. We re-call cache_dialogue_audio with
			# the resolved voice_id, but cache_dialogue_audio will
			# re-resolve via _is_known_faction, which is false for
			# voice ids, so we need to skip the legacy fast path.
			var queue_copy = cache_queue.duplicate()
			cache_queue.clear()
			for item in queue_copy:
				# Bypass the (faction-resolving) public method and call
				# the underlying work directly. The simplest way is to
				# call the public method with the voice_id — it will
				# be treated as a voice id (not a faction) and routed
				# correctly.
				cache_dialogue_audio(item.text, item.voice_id, item.speed, item.get("style_scale", 1.0))
		else:
			# If first attempt failed, start the server process
			if tts_connection_attempts == 1:
				print("[TTSInterface] Local TTS server not detected or not ready. Launching it...")
				_launch_tts_server_process()
				
			# Retry after 1.5 seconds
			get_tree().create_timer(1.5).timeout.connect(_discover_and_verify_tts)
	)
	
	var err = check_http.request("http://127.0.0.1:5000/health")
	if err != OK:
		check_http.queue_free()
		print("[TTSInterface] Failed to check health endpoint. Retrying in 1.5s...")
		if tts_connection_attempts == 1:
			_launch_tts_server_process()
		get_tree().create_timer(1.5).timeout.connect(_discover_and_verify_tts)

func _launch_tts_server_process():
	if DisplayServer.get_name() == "headless":
		print("[TTSInterface] Headless mode detected; skipping local TTS server auto-launch.")
		return
	var global_script_path = ProjectSettings.globalize_path("res://scripts/tts_server.py")
	print("[TTSInterface] Sourced TTS server script path: ", global_script_path)
	
	var launcher := _resolve_python_launcher()
	if str(launcher.get("executable", "")).is_empty():
		print(
			"[TTSInterface] Python executable not found; TTS server was not launched. "
			+ "Install Python, add it to PATH, set SPACEGAME_PYTHON, or set %s." %
			PYTHON_SETTING
		)
		return
	var args := PackedStringArray()
	for arg in launcher.get("args", []):
		args.append(str(arg))
	args.append(global_script_path)
	var pid = OS.create_process(str(launcher["executable"]), args)
	if pid > 0:
		print("[TTSInterface] Successfully launched local TTS server background process (PID: ", pid, ")")
	else:
		print("[TTSInterface] Failed to launch local TTS server with Python: ", launcher["executable"])


func _resolve_python_launcher() -> Dictionary:
	var configured := str(ProjectSettings.get_setting(PYTHON_SETTING, "")).strip_edges()
	if not configured.is_empty():
		var configured_path := _resolve_python_executable(configured)
		if not configured_path.is_empty():
			return {"executable": configured_path, "args": _launcher_args(configured_path)}
	var env_value := OS.get_environment(PYTHON_ENV_VAR).strip_edges()
	if not env_value.is_empty():
		var env_path := _resolve_python_executable(env_value)
		if not env_path.is_empty():
			return {"executable": env_path, "args": _launcher_args(env_path)}
	for candidate in ["python", "python3", "py"]:
		var resolved := _resolve_python_executable(candidate)
		if not resolved.is_empty():
			return {"executable": resolved, "args": _launcher_args(resolved)}
	return {}


func _launcher_args(executable_path: String) -> Array[String]:
	if executable_path.get_file().to_lower() == "py.exe" \
			or executable_path.get_file().to_lower() == "py":
		return ["-3"]
	return []


func _resolve_python_executable(candidate: String) -> String:
	if candidate.is_empty():
		return ""
	if candidate.contains("/") or candidate.contains("\\"):
		return candidate if FileAccess.file_exists(candidate) else ""
	var path_value := OS.get_environment("PATH")
	if path_value.is_empty():
		return ""
	var separator := ";" if OS.get_name() == "Windows" else ":"
	var suffixes: Array[String] = [""]
	if OS.get_name() == "Windows" and candidate.get_extension().is_empty():
		suffixes = [".exe", ".bat", ".cmd", ""]
	for dir in path_value.split(separator, false):
		var clean_dir := str(dir).strip_edges()
		if clean_dir.is_empty():
			continue
		for suffix in suffixes:
			var path := "%s/%s%s" % [clean_dir.trim_suffix("/").trim_suffix("\\"), candidate, suffix]
			if FileAccess.file_exists(path):
				return path
	return ""

func get_voice_for_faction(faction: String) -> String:
	match faction.to_lower():
		"zenith":
			return "am_adam"
		"aurelia":
			return "af_sarah"
		"vanguard":
			return "am_michael"
		"neutral", _:
			return "af_aoede"

func _on_audio_player_finished():
	AudioManager.unduck_audio()
