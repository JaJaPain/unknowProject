extends Node

var bgm_player: AudioStreamPlayer
var jump_player: AudioStreamPlayer  # dedicated channel for the tunnel jet (so we can fade it)
var broken_gate_rain_player: AudioStreamPlayer
var broken_gate_thunder_player: AudioStreamPlayer
var mining_player: AudioStreamPlayer3D
var tractor_player: AudioStreamPlayer3D
var _mining_loop_active: bool = false
var _tractor_loop_active: bool = false
var jump_fade_tween: Tween
var _jump_fade_dur: float = 1.0
var _jump_fade_base_gain: float = 1.0
# Stutter gate applied during the jet fade — ~6 cuts/sec, "on" longer than "off".
const JUMP_FADE_STUTTER_RATE := 6.0
const JUMP_FADE_STUTTER_ON := 0.6
var sfx_players: Array[AudioStreamPlayer] = []
var max_sfx_channels: int = 8

var music_volume_percent: float = 0.5
var sfx_volume_percent: float = 1.0
var is_ducked: bool = false
var _dialogue_duck_music_db := 18.0
var _dialogue_duck_sfx_db := 12.0
var _broken_gate_ambience_active := false
var _music_suspended_for_broken_gate := false
var _broken_gate_saved_stream: AudioStream = null
var _broken_gate_saved_position := 0.0

# Audio Streams
var bgm_track1 = preload("res://sound/BackgroundMusic/Iron Lullaby1.mp3")
var bgm_track2 = preload("res://sound/BackgroundMusic/Iron Lullaby2.mp3")
var bgm_lounge = preload("res://sound/BackgroundMusic/LoungeMusic.wav")
# Loaded at runtime because these landing tracks may be imported after the
# scripts are first scanned (for example, when audio is copied into a project).
var bgm_landing1: AudioStream = null
var bgm_landing2: AudioStream = null
var sfx_laser1 = preload("res://sound/WeaponFire/Laser Weapon Firing1.mp3")
var sfx_laser2 = preload("res://sound/WeaponFire/Laser Weapon Firing2.mp3")
var sfx_mining = preload("res://sound/Mining/MiningSound.mp3")
var sfx_tractor_beam = preload("res://sound/Mining/TractorBeam.mp3")
var sfx_explosion1 = preload("res://sound/SpaceShipExplosion/Spaceship Explosion1.mp3")
var sfx_explosion2 = preload("res://sound/SpaceShipExplosion/Spaceship Explosion2.mp3")
var sfx_cargo_full = preload("res://assets/Cargo Full.mp3")
var sfx_repair: AudioStream = null
var sfx_sell_ore: AudioStream = null
var sfx_align: AudioStream = null
var sfx_jump_spool: AudioStreamWAV = null
var sfx_jump_transit: AudioStreamWAV = null
var sfx_jump_arrival: AudioStreamWAV = null
const BROKEN_GATE_RAIN_PATH := "res://sound/storm/juliush-heavy-rain-nature-sounds-8186.mp3"
const BROKEN_GATE_THUNDER_PATH := "res://sound/storm/ramolmusic-thunderstorm-and-rain-sound-effects-548253.mp3"

var tracks: Array = []
var current_track_idx: int = 0
var _lounge_music_active: bool = false
var _landing_music_active: bool = false
var _landing_track_idx: int = 0
var _pre_lounge_stream: AudioStream = null
var _pre_lounge_position: float = 0.0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Ensure Music and SFX buses exist in AudioServer
	var music_bus_idx = AudioServer.get_bus_index("Music")
	if music_bus_idx == -1:
		AudioServer.add_bus()
		music_bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(music_bus_idx, "Music")
		
	var sfx_bus_idx = AudioServer.get_bus_index("SFX")
	if sfx_bus_idx == -1:
		AudioServer.add_bus()
		sfx_bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(sfx_bus_idx, "SFX")
	
	# Setup BGM Player
	bgm_player = AudioStreamPlayer.new()
	bgm_player.bus = "Music"
	add_child(bgm_player)
	bgm_player.finished.connect(_on_bgm_finished)

	# Dedicated player for the jump-tunnel jet so we can fade it on arrival.
	jump_player = AudioStreamPlayer.new()
	jump_player.bus = "SFX"
	add_child(jump_player)
	broken_gate_rain_player = _create_broken_gate_ambience_player(-12.0)
	broken_gate_thunder_player = _create_broken_gate_ambience_player(-15.0)

	mining_player = AudioStreamPlayer3D.new()
	mining_player.bus = "SFX"
	mining_player.unit_size = 15.0
	mining_player.max_db = 2.0
	mining_player.max_distance = 350.0
	add_child(mining_player)
	mining_player.finished.connect(_on_mining_loop_finished)

	tractor_player = AudioStreamPlayer3D.new()
	tractor_player.bus = "SFX"
	tractor_player.unit_size = 15.0
	tractor_player.max_db = 2.0
	tractor_player.max_distance = 350.0
	add_child(tractor_player)
	tractor_player.finished.connect(_on_tractor_loop_finished)

	tracks = [bgm_track1, bgm_track2]
	
	# Setup SFX Players pool
	for i in range(max_sfx_channels):
		var p = AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		sfx_players.append(p)
		
	_load_preferences()

	# Start playing music
	play_next_bgm()

func play_next_bgm():
	if tracks.size() == 0: return
	_lounge_music_active = false
	_landing_music_active = false
	bgm_player.stream = tracks[current_track_idx]
	bgm_player.play()
	current_track_idx = (current_track_idx + 1) % tracks.size()


func _create_broken_gate_ambience_player(volume_db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = "SFX"
	player.volume_db = volume_db
	player.finished.connect(func() -> void:
		if _broken_gate_ambience_active and not player.playing:
			player.play()
	)
	add_child(player)
	return player


# The broken gate is deliberately musicless. Separate rain and thunder players
# keep the mix tunable without baking a combined audio asset.
func begin_broken_gate_ambience() -> void:
	if _broken_gate_ambience_active:
		return
	_broken_gate_ambience_active = true
	_dialogue_duck_music_db = 6.0
	_dialogue_duck_sfx_db = 4.0
	if bgm_player and not _music_suspended_for_broken_gate:
		_broken_gate_saved_stream = bgm_player.stream
		_broken_gate_saved_position = bgm_player.get_playback_position() if bgm_player.playing else 0.0
		_music_suspended_for_broken_gate = true
		bgm_player.stop()
	_start_broken_gate_track(broken_gate_rain_player, BROKEN_GATE_RAIN_PATH)
	_start_broken_gate_track(broken_gate_thunder_player, BROKEN_GATE_THUNDER_PATH)
	GlobalState.trace("[TRACE] [AudioManager] Broken-gate ambience started; music suspended.")


func _start_broken_gate_track(player: AudioStreamPlayer, path: String) -> void:
	if player == null:
		return
	if player.stream == null:
		player.stream = load(path) as AudioStream
	if player.stream == null:
		push_warning("[AudioManager] Missing broken-gate ambience: %s" % path)
		return
	if not player.playing:
		player.play()


func stop_broken_gate_ambience() -> void:
	_broken_gate_ambience_active = false
	_dialogue_duck_music_db = 18.0
	_dialogue_duck_sfx_db = 12.0
	if broken_gate_rain_player:
		broken_gate_rain_player.stop()
	if broken_gate_thunder_player:
		broken_gate_thunder_player.stop()
	_update_bus_volumes()


# Called after the ship's existing return-to-normal-space one-shot finishes.
func resume_music_after_broken_gate() -> void:
	if not _music_suspended_for_broken_gate:
		return
	_music_suspended_for_broken_gate = false
	if bgm_player and _broken_gate_saved_stream:
		bgm_player.stream = _broken_gate_saved_stream
		bgm_player.play(maxf(0.0, _broken_gate_saved_position))
	else:
		play_next_bgm()
	_broken_gate_saved_stream = null
	_broken_gate_saved_position = 0.0
	GlobalState.trace("[TRACE] [AudioManager] Broken-gate ambience ended; music resumed.")

func _on_bgm_finished():
	if _landing_music_active:
		play_next_landing_track()
		return
	if _lounge_music_active:
		bgm_player.play()
	else:
		play_next_bgm()

func enter_lounge_music() -> void:
	if bgm_player == null or bgm_lounge == null:
		return
	if _lounge_music_active:
		return
	_pre_lounge_stream = bgm_player.stream
	_pre_lounge_position = bgm_player.get_playback_position() if bgm_player.playing else 0.0
	_lounge_music_active = true
	_landing_music_active = false
	bgm_player.stream = bgm_lounge
	bgm_player.play()

func exit_lounge_music() -> void:
	if bgm_player == null or not _lounge_music_active:
		return
	_lounge_music_active = false
	if _pre_lounge_stream:
		bgm_player.stream = _pre_lounge_stream
		bgm_player.play(maxf(0.0, _pre_lounge_position))
	else:
		play_next_bgm()
	_pre_lounge_stream = null
	_pre_lounge_position = 0.0

func enter_landing_music() -> void:
	if bgm_player == null:
		return
	if bgm_landing1 == null:
		bgm_landing1 = load("res://sound/BackgroundMusic/FrontPage01.mp3")
	if bgm_landing2 == null:
		bgm_landing2 = load("res://sound/BackgroundMusic/FrontPage02.mp3")
	if bgm_landing1 == null and bgm_landing2 == null:
		push_warning("[AudioManager] Landing music could not be loaded.")
		return
	_lounge_music_active = false
	_landing_music_active = true
	_landing_track_idx = 0
	play_next_landing_track()

func exit_landing_music() -> void:
	if bgm_player == null or not _landing_music_active:
		return
	_landing_music_active = false
	play_next_bgm()

func play_next_landing_track() -> void:
	var landing_tracks := [bgm_landing1, bgm_landing2].filter(
		func(track: AudioStream) -> bool: return track != null
	)
	if landing_tracks.is_empty():
		return
	bgm_player.stream = landing_tracks[_landing_track_idx]
	bgm_player.play()
	_landing_track_idx = (_landing_track_idx + 1) % landing_tracks.size()

func play_sfx(stream: AudioStream, volume_db: float = 0.0):
	for p in sfx_players:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.play()
			return
	# If all busy, steal the first channel
	var p = sfx_players[0]
	p.stop()
	p.stream = stream
	p.volume_db = volume_db
	p.play()

func play_sfx_3d(stream: AudioStream, position: Vector3, volume_db: float = 0.0):
	var p = AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.bus = "SFX"
	
	# Configure 3D attenuation settings
	p.unit_size = 15.0 # Distance where the sound begins to fade
	p.max_db = 3.0
	p.max_distance = 350.0 # Beyond this, completely silent
	
	var main = get_tree().current_scene
	if main:
		main.add_child(p)
		p.global_position = position
		p.play()
		p.finished.connect(p.queue_free)

func play_laser(pos: Variant = null):
	var laser = sfx_laser1 if randf() > 0.5 else sfx_laser2
	if pos is Vector3:
		play_sfx_3d(laser, pos, -6.0)
	else:
		play_sfx(laser, -6.0)

func play_mining_laser(pos: Variant = null):
	if pos is Vector3:
		play_sfx_3d(sfx_mining, pos, -2.0)
	else:
		play_sfx(sfx_mining, -2.0)

func play_tractor_beam(pos: Variant = null):
	if pos is Vector3:
		play_sfx_3d(sfx_tractor_beam, pos, -4.0)
	else:
		play_sfx(sfx_tractor_beam, -4.0)

func start_mining_loop(pos: Vector3) -> void:
	_mining_loop_active = true
	_start_positioned_loop(mining_player, sfx_mining, pos, -2.0)

func stop_mining_loop() -> void:
	_mining_loop_active = false
	if mining_player:
		mining_player.stop()

func start_tractor_loop(pos: Vector3) -> void:
	_tractor_loop_active = true
	_start_positioned_loop(tractor_player, sfx_tractor_beam, pos, -4.0)

func stop_tractor_loop() -> void:
	_tractor_loop_active = false
	if tractor_player:
		tractor_player.stop()

func update_mining_audio_position(pos: Vector3) -> void:
	if mining_player and mining_player.playing:
		mining_player.global_position = pos
	if tractor_player and tractor_player.playing:
		tractor_player.global_position = pos

func stop_mining_audio() -> void:
	stop_mining_loop()
	stop_tractor_loop()

func _start_positioned_loop(
		player: AudioStreamPlayer3D,
		stream: AudioStream,
		pos: Vector3,
		volume_db: float
) -> void:
	if player == null or stream == null:
		return
	player.global_position = pos
	player.volume_db = volume_db
	if player.stream != stream:
		player.stream = stream
	if not player.playing:
		player.play()

func _on_mining_loop_finished() -> void:
	if _mining_loop_active and mining_player:
		mining_player.play()

func _on_tractor_loop_finished() -> void:
	if _tractor_loop_active and tractor_player:
		tractor_player.play()

func play_explosion(pos: Variant = null):
	var expl = sfx_explosion1 if randf() > 0.5 else sfx_explosion2
	if pos is Vector3:
		play_sfx_3d(expl, pos, -3.0)
	else:
		play_sfx(expl, -3.0)

func play_cargo_full():
	play_sfx(sfx_cargo_full, 0.0)

func set_music_volume(value: float):
	music_volume_percent = value
	_update_bus_volumes()
	_save_preferences()

func get_music_volume() -> float:
	return music_volume_percent

func set_music_pitch(scale: float) -> void:
	if bgm_player:
		bgm_player.pitch_scale = scale

func reset_music_pitch() -> void:
	if bgm_player:
		bgm_player.pitch_scale = 1.0

func set_sfx_volume(value: float):
	sfx_volume_percent = value
	_update_bus_volumes()
	_save_preferences()

func get_sfx_volume() -> float:
	return sfx_volume_percent

func _update_bus_volumes():
	var music_idx = AudioServer.get_bus_index("Music")
	if music_idx != -1:
		var target_db = linear_to_db(music_volume_percent)
		if is_ducked:
			target_db -= _dialogue_duck_music_db
		AudioServer.set_bus_volume_db(music_idx, target_db)
		AudioServer.set_bus_mute(music_idx, music_volume_percent <= 0.0001)
		
	var sfx_idx = AudioServer.get_bus_index("SFX")
	if sfx_idx != -1:
		var target_db = linear_to_db(sfx_volume_percent)
		if is_ducked:
			target_db -= _dialogue_duck_sfx_db
		AudioServer.set_bus_volume_db(sfx_idx, target_db)
		AudioServer.set_bus_mute(sfx_idx, sfx_volume_percent <= 0.0001)

func duck_audio():
	if not is_ducked:
		is_ducked = true
		_update_bus_volumes()
		GlobalState.trace("[TRACE] [AudioManager] Audio ducked (Music -%.0fdB, SFX -%.0fdB)" % [_dialogue_duck_music_db, _dialogue_duck_sfx_db])

func unduck_audio():
	if is_ducked:
		is_ducked = false
		_update_bus_volumes()
		GlobalState.trace("[TRACE] [AudioManager] Audio unducked")

func play_align():
	if sfx_align == null:
		sfx_align = load("res://sound/ShipSounds/ShipAlignSound.mp3")
	if sfx_align:
		play_sfx(sfx_align, -4.0)

func play_repair():
	if sfx_repair == null:
		sfx_repair = load("res://sound/spaceStationSoundFX/RepairShip.wav")
	if sfx_repair:
		play_sfx(sfx_repair, 0.0)

func play_sell_ore():
	if sfx_sell_ore == null:
		sfx_sell_ore = load("res://sound/spaceStationSoundFX/sellOre.mp3")
	if sfx_sell_ore:
		play_sfx(sfx_sell_ore, -2.0)

func play_jump_spool() -> void:
	if not sfx_jump_spool:
		sfx_jump_spool = _create_jump_tone(1.0, 70.0, 420.0, 0.18)
	play_sfx(sfx_jump_spool, -3.0)

func play_jump_transit() -> void:
	if not sfx_jump_transit:
		# Real synthesized jet-engine spool-up for the tunnel. Regenerate at a
		# different length via tools/generate_jet_spool.py. Falls back to the
		# old swept tone if the WAV isn't imported (e.g. headless tests).
		var loaded = load("res://sound/ShipSounds/jet_spool_up.wav")
		if loaded is AudioStreamWAV:
			sfx_jump_transit = loaded
		else:
			sfx_jump_transit = _create_jump_tone(1.4, 180.0, 70.0, 0.42)
	# Play on the dedicated jump channel so fade_out_jump_transit() can ride it
	# out as the ship emerges, instead of a hard cut when the clip ends.
	if jump_fade_tween and jump_fade_tween.is_valid():
		jump_fade_tween.kill()
	jump_player.stream = sfx_jump_transit
	jump_player.volume_db = -1.0
	jump_player.play()


# Fade the tunnel jet out over `duration` with a stutter gate (noise-gate
# chopping on/off) layered on top, so it tails off in pulses rather than a
# smooth ramp. Ends silent and stops the player.
func fade_out_jump_transit(duration: float = 1.5) -> void:
	if not jump_player or not jump_player.playing:
		return
	if jump_fade_tween and jump_fade_tween.is_valid():
		jump_fade_tween.kill()
	_jump_fade_dur = maxf(0.01, duration)
	_jump_fade_base_gain = db_to_linear(jump_player.volume_db)
	jump_fade_tween = create_tween()
	jump_fade_tween.tween_method(_jump_fade_step, 0.0, 1.0, duration)
	jump_fade_tween.tween_callback(jump_player.stop)


func _jump_fade_step(p: float) -> void:
	if not jump_player:
		return
	# Smooth amplitude fade to silence...
	var fade_gain: float = _jump_fade_base_gain * (1.0 - p)
	# ...chopped by the stutter gate (on-phase longer than off-phase).
	var phase: float = fmod(p * _jump_fade_dur * JUMP_FADE_STUTTER_RATE, 1.0)
	var gain: float = fade_gain if phase < JUMP_FADE_STUTTER_ON else 0.0
	jump_player.volume_db = linear_to_db(gain) if gain > 0.0001 else -60.0

func play_jump_arrival() -> void:
	if not sfx_jump_arrival:
		sfx_jump_arrival = _create_jump_tone(0.55, 360.0, 85.0, 0.28)
	play_sfx(sfx_jump_arrival, -2.0)

func _create_jump_tone(duration: float, start_hz: float, end_hz: float, noise_amount: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var sample_count := int(duration * sample_rate)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase := 0.0
	for i in range(sample_count):
		var progress: float = float(i) / float(maxi(1, sample_count - 1))
		var frequency: float = lerpf(start_hz, end_hz, progress)
		phase += TAU * frequency / sample_rate
		var envelope: float = sin(PI * progress)
		var noise: float = randf_range(-1.0, 1.0) * noise_amount
		var sample_value: float = clampf((sin(phase) * (1.0 - noise_amount) + noise) * envelope, -1.0, 1.0)
		data.encode_s16(i * 2, int(sample_value * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	return stream


const PREFS_PATH := "user://player_preferences.json"

func _load_preferences() -> void:
	if not FileAccess.file_exists(PREFS_PATH):
		set_music_volume(0.5)
		return
	var file := FileAccess.open(PREFS_PATH, FileAccess.READ)
	if file == null:
		set_music_volume(0.5)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		var prefs: Dictionary = parsed
		set_music_volume(clampf(float(prefs.get("music_volume", 0.5)), 0.0, 1.0))
		set_sfx_volume(clampf(float(prefs.get("sfx_volume", 1.0)), 0.0, 1.0))
	else:
		set_music_volume(0.5)


func _save_preferences() -> void:
	var prefs := {
		"music_volume": music_volume_percent,
		"sfx_volume": sfx_volume_percent,
	}
	var file := FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(prefs, "\t"))
	file.close()
