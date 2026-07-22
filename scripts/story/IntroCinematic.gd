extends Node

# The cold open (docs/plan_intro_cinematic.md): the ship is thrown through a
# failing gate into the start system — no control, no UI — N.O.V.A. introduces
# herself mid-crisis, the ship arrives damaged, an untraceable data stream
# wires exactly enough credits to repair, then the UI returns and the existing
# Kaelen intro runs. One-shot node; UIManager spawns it on NEW campaigns only.
#
# Every beat checks _finished so the SPACE skip / 30s watchdog can cut in at
# any await point. _finish() is idempotent and ALWAYS restores control — the
# game must never be left controllerless.

# ── Feel-tuning knobs ─────────────────────────────────────────────────────────
const TUMBLE_DURATION := 20.0    # the long, violent haul THROUGH the failing gate
const FLING_FLASH := 0.15
const REVEAL_DURATION := 1.2
const ARRIVAL_LINE2_AT := 1.0    # seconds after reveal
const ARRIVAL_LINE3_AT := 5.0
const DATA_STREAM_AT := 8.0
const DATA_LINE4_AT := 10.0
const HANDOFF_AT := 18.0         # after reveal; lets Nova's last spoken line finish
const HANDOFF_TO_KAELEN_S := 11.0 # beat to breathe after the UI returns, before Kaelen
const NOVA_CALLING_BEFORE_KAELEN_S := 3.5
const TTS_READY_WAIT_S := 45.0
const DAMAGE_HEALTH_PCT := 0.4   # ship arrives at 40% hull
const REPAIR_COST_PER_HP := 2.0  # MUST match UIManager._repair_ship cost_per_hp
const SPIN_TURNS := 9.0          # full-axis tumble rotations (scaled to TUMBLE_DURATION)
const WATCHDOG_S := 60.0  # fallback only; must exceed full runtime (~40s)

const GLITCH_SHADER := preload("res://shaders/intro_glitch.gdshader")
const JUMP_TUNNEL_SCENE := preload("res://scenes/jump_tunnel.tscn")
const NOVA_PORTRAIT_TEXTURE := preload("res://assets/Portraits/ShipAI.png")
const SFX_GATE_1 := "res://sound/Opening/GateSound1.wav"
const SFX_GATE_2 := "res://sound/Opening/GateSound2.wav"
const SFX_MALFUNCTION := "res://sound/Opening/Damaged_spaceship_systems_malf_take2.wav"
const SFX_FLASH := "res://sound/Opening/A_powerful_sci-fi_energy_disch_take2.wav"
const SFX_WARP_DROP := "res://sound/Opening/Spaceship_thrown_out_of_warp_i_take1.wav"
const NOVA_VOICE_PROFILE_ID := "voice.nova.v1"
const NOVA_LINE_1 := "Hold on, Captain! I'm doing everything I can to stabilize the ship - I've got ONE last thing I can try!"
const NOVA_LINE_1A := "I almost got it."
const NOVA_LINE_1B := "ALMOST!"
const NOVA_LINE_2 := "We're... somewhere. That wasn't a gate transit, Captain - we were thrown. Hull's a mess, but we're alive."
const NOVA_LINE_3 := "Here's the part I don't like: my memory starts fourteen seconds ago. I know you're my captain. I know I trust you. I just can't tell you WHY I know either of those things."
const NOVA_LINE_4 := "Someone just wired us what I am guessing is the local currency. No routing data. No sender. I ran the trace twice - it goes nowhere. I'd say 'lucky us', but luck doesn't usually know our account number."
const NOVA_LINE_5 := "Uh, Captain, someone is calling you?"
const NOVA_LINES := [
	NOVA_LINE_1,
	NOVA_LINE_1A,
	NOVA_LINE_1B,
	NOVA_LINE_2,
	NOVA_LINE_3,
	NOVA_LINE_4,
	NOVA_LINE_5,
]

var _ui: Control = null            # UIManager root (hidden during the sequence)
var _layer: CanvasLayer = null
var _glitch_rect: ColorRect = null
var _glitch_mat: ShaderMaterial = null
var _black: ColorRect = null
var _nova_panel: PanelContainer = null
var _nova_portrait: TextureRect = null
var _subtitle: Label = null
var _stream_label: Label = null
var _skip_hint: Label = null
var _tunnel: Node3D = null
var _tunnel_mat: ShaderMaterial = null
var _player_camera: Camera3D = null
var _camera_base_fov := 70.0
var _camera_base_h_offset := 0.0
var _camera_base_v_offset := 0.0
var _ship_light: OmniLight3D = null
var _ship_light_energy := 4.0
var _elapsed := 0.0
var _camera_settling := false
var _gate_player_1: AudioStreamPlayer = null
var _gate_player_2: AudioStreamPlayer = null
var _malfunction_player: AudioStreamPlayer = null
var _audio_players: Array[Node] = []
var _gate_pan_1: AudioEffectPanner = null
var _gate_pan_2: AudioEffectPanner = null
var _data_sfx_played := false
var _finished := false
var _consequences_applied := false


static func cache_nova_voice_lines() -> void:
	if not is_instance_valid(SpeechService):
		return
	for line in NOVA_LINES:
		SpeechService.cache(str(line), NOVA_VOICE_PROFILE_ID)
	print("[IntroCinematic] Queued Nova intro voice cache lines: ", NOVA_LINES.size())


# Entry point. ui_manager is hidden/restored by us; on finish (or skip, or
# watchdog) we call show_kaelen_intro() on it after a 1s beat.
func start(ui_manager: Control) -> void:
	_ui = ui_manager
	# The opening is a self-contained sequence. Ambient NPC simulation must not
	# fire weapons or start combat under its dialogue and effects.
	GlobalState.intro_cinematic_active = true
	var p = GlobalState.player
	if p == null or not is_instance_valid(p):
		# No player yet — abort gracefully straight to the normal flow.
		_finish()
		return
	_ui.visible = false
	p.set_physics_process(false)
	if p.has_method("hard_stop"):
		p.hard_stop()
	_setup_broken_tunnel(p)
	_build_visuals()
	if is_instance_valid(AudioManager):
		AudioManager.begin_broken_gate_ambience()
	_start_intro_audio()
	# Watchdog: whatever happens, control comes back.
	get_tree().create_timer(WATCHDOG_S, true, false, true).timeout.connect(_finish)
	_run_after_initial_black_frame()


# The black layer must render over the already-spawned world before it fades.
# That frame also lets the tunnel and glitch material initialize behind it, so
# the first thing the player sees is the broken-gate effect—not the ship parked
# in the destination system.
func _run_after_initial_black_frame() -> void:
	await get_tree().process_frame
	if _finished:
		return
	_run()


func _build_visuals() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 90
	add_child(_layer)

	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 1)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_black)

	_glitch_rect = ColorRect.new()
	_glitch_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glitch_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glitch_mat = ShaderMaterial.new()
	_glitch_mat.shader = GLITCH_SHADER
	_glitch_mat.set_shader_parameter("intensity", 1.0)
	_glitch_mat.set_shader_parameter("white_out", 0.0)
	_glitch_rect.material = _glitch_mat
	_layer.add_child(_glitch_rect)

	_nova_panel = PanelContainer.new()
	_nova_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_nova_panel.offset_left = 42.0
	_nova_panel.offset_top = -382.0
	_nova_panel.offset_right = 354.0
	_nova_panel.offset_bottom = -70.0
	_nova_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nova_panel.modulate.a = 0.0
	var portrait_style := StyleBoxFlat.new()
	portrait_style.bg_color = Color(0.02, 0.06, 0.10, 0.82)
	portrait_style.border_color = Color(0.26, 0.72, 1.0, 0.95)
	portrait_style.border_width_left = 2
	portrait_style.border_width_top = 2
	portrait_style.border_width_right = 2
	portrait_style.border_width_bottom = 2
	portrait_style.corner_radius_top_left = 5
	portrait_style.corner_radius_top_right = 5
	portrait_style.corner_radius_bottom_right = 5
	portrait_style.corner_radius_bottom_left = 5
	_nova_panel.add_theme_stylebox_override("panel", portrait_style)
	_layer.add_child(_nova_panel)

	_nova_portrait = TextureRect.new()
	_nova_portrait.custom_minimum_size = Vector2(292, 292)
	_nova_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_nova_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_nova_panel.add_child(_nova_portrait)

	_subtitle = Label.new()
	_subtitle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_subtitle.offset_bottom = -90.0
	_subtitle.offset_left = 390.0
	_subtitle.offset_right = -120.0
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_theme_font_size_override("font_size", 22)
	_subtitle.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	_subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_subtitle.add_theme_constant_override("shadow_offset_y", 2)
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_subtitle)

	_stream_label = Label.new()
	_stream_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stream_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stream_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stream_label.add_theme_font_size_override("font_size", 18)
	_stream_label.add_theme_color_override("font_color", Color(0.2, 0.95, 0.85))
	_stream_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stream_label.visible = false
	_layer.add_child(_stream_label)

	_skip_hint = Label.new()
	_skip_hint.text = "[SPACE]  skip"
	_skip_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_hint.offset_left = -160.0
	_skip_hint.offset_top = -44.0
	_skip_hint.offset_right = -24.0
	_skip_hint.offset_bottom = -20.0
	_skip_hint.add_theme_font_size_override("font_size", 13)
	_skip_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.0))
	_skip_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_skip_hint)
	# Fade the hint in after a couple of seconds — present, not pushy.
	var hint_tween := create_tween().set_ignore_time_scale(true)
	hint_tween.tween_interval(2.0)
	hint_tween.tween_property(_skip_hint, "theme_override_colors/font_color", Color(0.6, 0.6, 0.6, 0.8), 0.6)


# N.O.V.A. speaks: our subtitle (UI is hidden, chatter feed invisible) plus her
# real voice/portrait routing through Nova.speak (TTS still runs while the UI
# root is hidden — audio handlers don't care about visibility).
func _nova_line(text: String, expression: String) -> void:
	if _finished:
		return
	_show_nova_line_visual(text, expression)
	if is_instance_valid(Nova) and Nova.has_method("speak"):
		Nova.speak(text, Nova.Severity.THREAT, expression)


func _show_nova_line_visual(text: String, expression: String) -> void:
	_show_nova_portrait(expression)
	if _subtitle != null and is_instance_valid(_subtitle):
		_subtitle.text = "N.O.V.A.:  " + text


func _nova_line_after_voice_ready(text: String, expression: String) -> void:
	_show_nova_line_visual(text, expression)
	if not _speech_ready_for_intro():
		await _wait_for_speech_ready(TTS_READY_WAIT_S)
	if _finished:
		return
	if _speech_ready_for_intro():
		if is_instance_valid(SpeechService):
			SpeechService.play(text, NOVA_VOICE_PROFILE_ID)
			# Do not let a longer N.O.V.A. line get cut off by the next timed
			# beat. The cinematic waits for playback; its timeout is only a
			# fail-safe for a broken audio backend, not a schedule to catch up to.
			await _wait_for_nova_playback(clampf(float(text.length()) / 8.0 + 3.0, 18.0, 36.0))
	else:
		print("[IntroCinematic] Nova TTS skipped after waiting; voice service still busy/offline.")


func _speech_ready_for_intro() -> bool:
	if not is_instance_valid(TTSInterface):
		return false
	if not bool(TTSInterface.get("tts_connected")):
		return false
	if bool(TTSInterface.get("is_requesting")):
		return false
	# The cold-open lines are explicitly pre-cached before this cinematic starts.
	# Optional background cache requests must not hold those ready clips hostage:
	# they can run for a long time on a busy machine, and waiting for them here
	# used to make N.O.V.A. start late or skip a timed beat altogether.
	return true


func _wait_for_speech_ready(max_seconds: float) -> void:
	var elapsed := 0.0
	var announced := false
	while not _finished and not _speech_ready_for_intro() and elapsed < max_seconds:
		if not announced:
			announced = true
			print("[IntroCinematic] Waiting for Nova TTS to be ready...")
		await _beat(0.25)
		elapsed += 0.25
	if _speech_ready_for_intro():
		print("[IntroCinematic] Nova TTS ready after %.1fs." % elapsed)


func _wait_for_nova_playback(max_seconds: float) -> void:
	if not is_instance_valid(TTSInterface):
		return
	var elapsed := 0.0
	var saw_voice_activity := false
	while not _finished and elapsed < max_seconds:
		var requesting := bool(TTSInterface.get("is_requesting"))
		var playing := false
		var player = TTSInterface.get("audio_player")
		if player != null and is_instance_valid(player):
			playing = bool(player.get("playing"))
		if requesting or playing:
			saw_voice_activity = true
		elif saw_voice_activity:
			return
		await _beat(0.1)
		elapsed += 0.1


func _show_nova_portrait(expression: String) -> void:
	if _nova_portrait == null or not is_instance_valid(_nova_portrait):
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = NOVA_PORTRAIT_TEXTURE
	var frame := 0
	if is_instance_valid(Nova) and Nova.has_method("frame_index_for"):
		frame = Nova.frame_index_for(expression)
	atlas.region = Nova.region_for_frame(
		frame,
		float(NOVA_PORTRAIT_TEXTURE.get_width()),
		float(NOVA_PORTRAIT_TEXTURE.get_height())
	)
	_nova_portrait.texture = atlas
	if _nova_panel != null and is_instance_valid(_nova_panel):
		var tween := create_tween().set_ignore_time_scale(true)
		tween.tween_property(_nova_panel, "modulate:a", 1.0, 0.25)


func _setup_broken_tunnel(player: CharacterBody3D) -> void:
	if DisplayServer.get_name() == "headless" or player == null or not is_instance_valid(player):
		return
	_player_camera = player.get_node_or_null("CameraPivot/Camera3D") as Camera3D
	if _player_camera != null:
		_camera_base_fov = _player_camera.fov
		_camera_base_h_offset = _player_camera.h_offset
		_camera_base_v_offset = _player_camera.v_offset
	_ship_light = player.get_node_or_null("ShipLight") as OmniLight3D
	if _ship_light != null:
		_ship_light_energy = _ship_light.light_energy
	_tunnel = JUMP_TUNNEL_SCENE.instantiate() as Node3D
	player.get_parent().add_child(_tunnel)
	_tunnel.global_position = player.global_position
	if _tunnel.has_method("setup_real_ship"):
		_tunnel.call("setup_real_ship", player)
	var cylinder := _tunnel.get_node_or_null("TunnelCylinder") as MeshInstance3D
	if cylinder != null:
		cylinder.visible = true
		var mat := cylinder.get_active_material(0) as ShaderMaterial
		if mat != null:
			_tunnel_mat = mat.duplicate() as ShaderMaterial
			_tunnel_mat.set_shader_parameter("speed", 9.0)
			_tunnel_mat.set_shader_parameter("ring_speed", 15.0)
			_tunnel_mat.set_shader_parameter("ring_frequency", 18.0)
			_tunnel_mat.set_shader_parameter("base_color", Color(0.01, 0.02, 0.08, 1.0))
			_tunnel_mat.set_shader_parameter("neon_color", Color(0.02, 0.75, 1.0, 1.0))
			_tunnel_mat.set_shader_parameter("accent_color", Color(1.0, 0.08, 0.18, 1.0))
			cylinder.material_override = _tunnel_mat
	var particles := _tunnel.get_node_or_null("WarpParticles") as CPUParticles3D
	if particles != null:
		particles.amount = 300
		particles.initial_velocity_min = 360.0
		particles.initial_velocity_max = 620.0
		particles.emitting = true


func _cleanup_tunnel() -> void:
	if _tunnel != null and is_instance_valid(_tunnel):
		if _tunnel.has_method("cleanup"):
			_tunnel.call("cleanup")
		_tunnel.queue_free()
	_tunnel = null
	_tunnel_mat = null


func _start_intro_audio() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_gate_player_1 = _create_loop_player(SFX_GATE_1, 10.0)


func _ensure_intro_pan_bus(bus_name: String, start_pan: float) -> AudioEffectPanner:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx == -1:
		AudioServer.add_bus()
		bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus_idx, bus_name)
		AudioServer.set_bus_send(bus_idx, "SFX")
	var effect: AudioEffectPanner = null
	for i in range(AudioServer.get_bus_effect_count(bus_idx)):
		var existing := AudioServer.get_bus_effect(bus_idx, i)
		if existing is AudioEffectPanner:
			effect = existing as AudioEffectPanner
			break
	if effect == null:
		effect = AudioEffectPanner.new()
		AudioServer.add_bus_effect(bus_idx, effect)
	effect.pan = start_pan
	return effect


func _create_panned_loop(path: String, volume_db: float, bus_name: String) -> AudioStreamPlayer:
	var stream := _load_loop_stream(path)
	if stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.bus = bus_name
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	_audio_players.append(player)
	player.play()
	print("[IntroCinematic] Playing panned loop: ", path, " bus=", bus_name, " volume_db=", volume_db)
	return player


func _create_loop_player(path: String, volume_db: float) -> AudioStreamPlayer:
	var stream := _load_loop_stream(path)
	if stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.bus = "SFX"
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	_audio_players.append(player)
	player.play()
	print("[IntroCinematic] Playing loop: ", path, " volume_db=", volume_db)
	return player


func _load_loop_stream(path: String) -> AudioStream:
	var stream := load(path) as AudioStream
	if stream == null:
		return null
	if stream is AudioStreamWAV:
		var wav := (stream as AudioStreamWAV).duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		return wav
	return stream


func _play_intro_one_shot(path: String, volume_db: float = 0.0) -> AudioStreamPlayer:
	var stream := load(path) as AudioStream
	if stream == null:
		print("[IntroCinematic] Missing intro sound: ", path)
		return null
	var player := AudioStreamPlayer.new()
	player.bus = "SFX"
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	print("[IntroCinematic] Playing one-shot: ", path, " volume_db=", volume_db)
	return player


func _stop_intro_audio() -> void:
	for player in _audio_players:
		if player == null or not is_instance_valid(player):
			continue
		if player.has_method("stop"):
			player.call("stop")
		player.queue_free()
	_audio_players.clear()
	_gate_player_1 = null
	_gate_player_2 = null
	_malfunction_player = null
	if _gate_pan_1 != null:
		_gate_pan_1.pan = 0.0
	if _gate_pan_2 != null:
		_gate_pan_2.pan = 0.0
	_gate_pan_1 = null
	_gate_pan_2 = null


func _process(delta: float) -> void:
	if _finished:
		return
	var real_delta := delta / maxf(Engine.time_scale, 0.01)
	_elapsed += real_delta
	if not _camera_settling and _player_camera != null and is_instance_valid(_player_camera):
		var decay := clampf(1.0 - (_elapsed / maxf(TUMBLE_DURATION + REVEAL_DURATION, 0.1)), 0.0, 1.0)
		var shock := 0.35 + sin(_elapsed * 8.0) * 0.18 + randf() * 0.18
		var strength := decay * shock
		_player_camera.h_offset = _camera_base_h_offset + randf_range(-strength, strength)
		_player_camera.v_offset = _camera_base_v_offset + randf_range(-strength, strength)
		_player_camera.fov = _camera_base_fov + sin(_elapsed * 2.6) * 2.0 * decay + 5.0 * decay
	if _ship_light != null and is_instance_valid(_ship_light):
		var pulse := 0.35 + randf() * 1.4 + maxf(0.0, sin(_elapsed * 18.0)) * 1.8
		_ship_light.light_energy = _ship_light_energy * pulse
	if _tunnel_mat != null:
		_tunnel_mat.set_shader_parameter("speed", 8.0 + randf() * 7.0)
		_tunnel_mat.set_shader_parameter("ring_speed", 10.0 + randf() * 14.0)


func _unhandled_input(event: InputEvent) -> void:
	if _finished:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_SPACE:
		_finish()


# The story consequences must land whether the player watched or skipped:
# battered hull + the untraceable data stream that covers EXACTLY the repair
# bill (cost mirrors UIManager._repair_ship: missing_hp * cost_per_hp).
func _apply_consequences() -> void:
	if _consequences_applied:
		return
	_consequences_applied = true
	var p = GlobalState.player
	if p == null or not is_instance_valid(p):
		return
	var max_hp := float(p.get("max_health")) if p.get("max_health") != null else 100.0
	p.set("health", max_hp * DAMAGE_HEALTH_PCT)
	if p.has_method("_update_drone_colors"):
		p.call("_update_drone_colors")
	var missing := max_hp - (max_hp * DAMAGE_HEALTH_PCT)
	var credits := int(ceil(missing * REPAIR_COST_PER_HP))
	GlobalState.add_credits(credits)
	GenerationDiagnostics.record_event(
		"intro_cinematic", "consequences_applied", "intro_cinematic",
		{"health_pct": DAMAGE_HEALTH_PCT, "credits": credits}
	)


# Idempotent teardown: consequences, control, UI, Kaelen handoff — in that
# order, safe from any phase, any await, the skip key, or the watchdog.
func _finish() -> void:
	if _finished:
		return
	_finished = true
	_apply_consequences()
	var p = GlobalState.player
	if p != null and is_instance_valid(p):
		p.set_physics_process(true)
		# Leave the ship level — the tumble may have ended mid-spin.
		var rot: Vector3 = p.rotation
		p.rotation = Vector3(0.0, rot.y, 0.0)
	_cleanup_tunnel()
	if _player_camera != null and is_instance_valid(_player_camera):
		_player_camera.fov = _camera_base_fov
		_player_camera.h_offset = _camera_base_h_offset
		_player_camera.v_offset = _camera_base_v_offset
	if _ship_light != null and is_instance_valid(_ship_light):
		_ship_light.light_energy = _ship_light_energy
	_stop_intro_audio()
	if is_instance_valid(AudioManager):
		AudioManager.stop_broken_gate_ambience()
		# Skip/watchdog paths have no return-drop one-shot to wait for.
		AudioManager.resume_music_after_broken_gate()
	GlobalState.intro_cinematic_active = false
	if _layer != null and is_instance_valid(_layer):
		_layer.hide()
	if _ui != null and is_instance_valid(_ui):
		_ui.visible = true
		var ui := _ui
		get_tree().create_timer(
			HANDOFF_TO_KAELEN_S - NOVA_CALLING_BEFORE_KAELEN_S,
			true,
			false,
			true
		).timeout.connect(_play_nova_handoff_line)
		get_tree().create_timer(HANDOFF_TO_KAELEN_S, true, false, true).timeout.connect(func() -> void:
			if is_instance_valid(ui) and ui.has_method("show_kaelen_intro"):
				ui.show_kaelen_intro()
			queue_free()
		)
	else:
		queue_free()


func _play_nova_handoff_line() -> void:
	if is_instance_valid(Nova) and Nova.has_method("speak"):
		Nova.speak(NOVA_LINE_5, Nova.Severity.THREAT, "alert")


# ── The beat timeline ─────────────────────────────────────────────────────────

# Wall-clock wait: the 4th arg (ignore_time_scale=true) makes each phase last
# REAL seconds no matter what Engine.time_scale is doing. Without it, if the
# engine is running at anything but 1.0x (combat drives it to 0.02x and back —
# CombatManager) every beat fires near-instantly and the whole intro collapses
# into a couple of seconds instead of spacing out. process_always=true so a
# paused tree can't stall it either.
func _beat(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _settle_to_gameplay_camera(duration: float = 2.0) -> void:
	_camera_settling = true
	if _player_camera != null and is_instance_valid(_player_camera):
		var camera_tween := create_tween().set_ignore_time_scale(true)
		camera_tween.set_parallel(true)
		camera_tween.tween_property(_player_camera, "fov", _camera_base_fov, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		camera_tween.tween_property(_player_camera, "h_offset", _camera_base_h_offset, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		camera_tween.tween_property(_player_camera, "v_offset", _camera_base_v_offset, duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var p = GlobalState.player
	if p != null and is_instance_valid(p):
		var rot: Vector3 = p.rotation
		var ship_tween := create_tween().set_ignore_time_scale(true)
		ship_tween.tween_property(p, "rotation", Vector3(0.0, rot.y, 0.0), duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _run() -> void:
	var p = GlobalState.player
	# TUMBLE — thrown through a dying gate: violent spin, screaming glitch.
	if p != null and is_instance_valid(p):
		var spin := create_tween().set_ignore_time_scale(true)
		var target: Vector3 = p.rotation + Vector3(
			TAU * SPIN_TURNS, TAU * (SPIN_TURNS * 0.7), TAU * (SPIN_TURNS * 1.3)
		)
		spin.tween_property(p, "rotation", target, TUMBLE_DURATION + REVEAL_DURATION) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# All intro tweens ignore time scale to stay in sync with the wall-clock
	# beats above — otherwise a non-1.0x engine desyncs visuals from dialogue.
	var flicker := create_tween().set_ignore_time_scale(true)
	flicker.set_loops(0)  # pulse for the whole tumble; killed at the fling
	flicker.tween_property(_glitch_mat, "shader_parameter/intensity", 0.7, 0.35)
	flicker.tween_property(_glitch_mat, "shader_parameter/intensity", 1.0, 0.4)
	var black_fade := create_tween().set_ignore_time_scale(true)
	black_fade.tween_property(_black, "color:a", 0.0, 1.4)
	await _beat(1.0)
	if _finished:
		return
	await _nova_line_after_voice_ready(NOVA_LINE_1, "alert")
	# The failing jump needs audible momentum: a short pause after the plan,
	# then a tentative status update, then the last-second shout before the drop.
	await _beat(4.0)
	if _finished:
		return
	await _nova_line_after_voice_ready(NOVA_LINE_1A, "worried")
	await _beat(2.5)
	if _finished:
		return
	await _nova_line_after_voice_ready(NOVA_LINE_1B, "alert")
	await _beat(1.25)
	if _finished:
		return

	# FLING — her last-ditch trick fires: white-out, then thrown INTO the
	# system. No gate on the other side. The black shell peels away to space.
	flicker.kill()
	if _tunnel != null and is_instance_valid(_tunnel) and _tunnel.has_method("begin_exit_burst"):
		_tunnel.call("begin_exit_burst", 0.8)
	_play_intro_one_shot(SFX_FLASH, 4.0)
	_glitch_mat.set_shader_parameter("white_out", 1.0)
	await _beat(FLING_FLASH)
	if _finished:
		return
	_cleanup_tunnel()
	_stop_intro_audio()
	_apply_consequences()
	var warp_drop_player := _play_intro_one_shot(SFX_WARP_DROP, 4.0)
	if is_instance_valid(AudioManager):
		AudioManager.stop_broken_gate_ambience()
		if warp_drop_player != null:
			warp_drop_player.finished.connect(AudioManager.resume_music_after_broken_gate, CONNECT_ONE_SHOT)
		else:
			AudioManager.resume_music_after_broken_gate()
	var reveal := create_tween().set_ignore_time_scale(true)
	reveal.set_parallel(true)
	reveal.tween_property(_black, "color:a", 0.0, REVEAL_DURATION)
	reveal.tween_property(_glitch_mat, "shader_parameter/white_out", 0.0, REVEAL_DURATION * 0.6)
	reveal.tween_property(_glitch_mat, "shader_parameter/intensity", 0.15, REVEAL_DURATION)
	await _beat(REVEAL_DURATION)
	if _finished:
		return

	# ARRIVAL — battered and drifting. Damage already landed behind the white-out.
	_settle_to_gameplay_camera(2.4)
	var residual := create_tween().set_ignore_time_scale(true)
	residual.set_loops(0)
	residual.tween_property(_glitch_mat, "shader_parameter/intensity", 0.02, 0.9)
	residual.tween_property(_glitch_mat, "shader_parameter/intensity", 0.14, 0.12)
	await _beat(ARRIVAL_LINE2_AT)
	if _finished:
		return
	await _nova_line_after_voice_ready(NOVA_LINE_2, "worried")
	await _beat(ARRIVAL_LINE3_AT - ARRIVAL_LINE2_AT)
	if _finished:
		return
	await _nova_line_after_voice_ready(NOVA_LINE_3, "wondering")
	await _beat(DATA_STREAM_AT - ARRIVAL_LINE3_AT)
	if _finished:
		return

	# DATA STREAM — exactly enough to fix the hull, from nowhere.
	var credits_shown := 0
	if p != null and is_instance_valid(p):
		var max_hp := float(p.get("max_health")) if p.get("max_health") != null else 100.0
		credits_shown = int(ceil((max_hp - float(p.get("health"))) * REPAIR_COST_PER_HP))
	_stream_label.text = "INCOMING DATA STREAM  //  ORIGIN: [UNRESOLVED]  //  CREDITS RECEIVED: %d" % credits_shown
	_stream_label.visible = true
	_stream_label.modulate.a = 0.0
	if not _data_sfx_played:
		_data_sfx_played = true
		if is_instance_valid(AudioManager) and AudioManager.has_method("play_sell_ore"):
			AudioManager.play_sell_ore()
	var stream_tween := create_tween().set_ignore_time_scale(true)
	stream_tween.tween_property(_stream_label, "modulate:a", 1.0, 0.4)
	await _beat(DATA_LINE4_AT - DATA_STREAM_AT)
	if _finished:
		return
	await _nova_line_after_voice_ready(NOVA_LINE_4, "thoughtful")
	await _beat(HANDOFF_AT - DATA_LINE4_AT)
	if _finished:
		return
	residual.kill()
	_finish()
