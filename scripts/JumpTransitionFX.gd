extends CanvasLayer

@onready var tunnel: ColorRect = $Tunnel
@onready var distortion_overlay: ColorRect = $DistortionOverlay
@onready var star_streaks: CPUParticles2D = $StarStreaks
@onready var flash: ColorRect = $Flash

var tunnel_mat: ShaderMaterial
var distortion_mat: ShaderMaterial

# Baseline tunnel speed during spool phase; script ramps up during snap-in
const TUNNEL_SPEED_BASE := 2.5
const TUNNEL_SPEED_WARP := 14.0

var _arrival_banner: Control = null
var _arrival_name_label: Label = null

func _ready() -> void:
	tunnel_mat = tunnel.material as ShaderMaterial
	distortion_mat = distortion_overlay.material as ShaderMaterial
	tunnel.visible = false
	distortion_overlay.visible = false
	star_streaks.emitting = false
	flash.visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var vp := get_viewport()
	if vp:
		star_streaks.position = vp.get_visible_rect().size * 0.5
	_build_arrival_banner()


func _build_arrival_banner() -> void:
	_arrival_banner = Control.new()
	_arrival_banner.name = "ArrivalBanner"
	_arrival_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arrival_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrival_banner.modulate.a = 0.0
	add_child(_arrival_banner)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arrival_banner.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	var entering_label := Label.new()
	entering_label.text = "ENTERING"
	entering_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	entering_label.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0, 1.0))
	entering_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(entering_label)

	_arrival_name_label = Label.new()
	_arrival_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arrival_name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_arrival_name_label.add_theme_font_size_override("font_size", 38)
	vbox.add_child(_arrival_name_label)


# GameRoot drives camera FOV and player position during entry.
# We handle all overlay visuals only.
func play_entry(duration: float = 1.2) -> void:
	if DisplayServer.get_name() == "headless":
		return

	tunnel_mat.set_shader_parameter("intensity", 0.0)
	tunnel_mat.set_shader_parameter("driven_speed", TUNNEL_SPEED_BASE)
	tunnel_mat.set_shader_parameter("streak_brightness", 0.6)
	distortion_mat.set_shader_parameter("radial_blur_strength", 0.0)
	distortion_mat.set_shader_parameter("chromatic_strength", 0.0)
	distortion_mat.set_shader_parameter("shockwave_progress", 0.0)
	distortion_mat.set_shader_parameter("shockwave_amplitude", 0.0)

	tunnel.visible = false
	distortion_overlay.visible = true
	flash.visible = true
	flash.modulate.a = 0.0
	star_streaks.emitting = false

	# Phase 1 (first 55%): tunnel spool — intensity and streaks ramp gently
	var spool_dur := duration * 0.55
	var snap_dur := duration * 0.45

	var spool := create_tween().set_parallel(true)
	spool.tween_method(
		func(v): tunnel_mat.set_shader_parameter("intensity", v),
		0.0, 0.55, spool_dur
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	spool.tween_method(
		func(v): tunnel_mat.set_shader_parameter("streak_brightness", v),
		0.6, 1.2, spool_dur
	).set_trans(Tween.TRANS_SINE)

	await spool.finished

	# Phase 2: warp snap-in — speed rockets, intensity slams to 1, blur and flash spike
	var snap := create_tween().set_parallel(true)

	snap.tween_method(
		func(v): tunnel_mat.set_shader_parameter("intensity", v),
		0.55, 1.0, snap_dur
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

	snap.tween_method(
		func(v): tunnel_mat.set_shader_parameter("driven_speed", v),
		TUNNEL_SPEED_BASE, TUNNEL_SPEED_WARP, snap_dur
	).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

	snap.tween_method(
		func(v): distortion_mat.set_shader_parameter("radial_blur_strength", v),
		0.0, 0.13, snap_dur * 0.7
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	snap.tween_method(
		func(v): distortion_mat.set_shader_parameter("chromatic_strength", v),
		0.0, 0.012, snap_dur * 0.7
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	snap.tween_property(flash, "modulate:a", 1.0, snap_dur * 0.6
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	await snap.finished


# Hold screen white while system loads. frame_count matches GameRoot call site.
func hold_covered(frame_count: int = 2) -> void:
	tunnel_mat.set_shader_parameter("intensity", 1.0)
	tunnel_mat.set_shader_parameter("driven_speed", TUNNEL_SPEED_BASE)
	tunnel_mat.set_shader_parameter("streak_brightness", 1.0)
	distortion_mat.set_shader_parameter("radial_blur_strength", 0.0)
	distortion_mat.set_shader_parameter("chromatic_strength", 0.0)
	distortion_mat.set_shader_parameter("shockwave_progress", 0.0)
	distortion_mat.set_shader_parameter("shockwave_amplitude", 0.0)
	tunnel.visible = false
	distortion_overlay.visible = true
	flash.visible = true
	flash.modulate.a = 1.0
	star_streaks.emitting = false
	for _i in range(frame_count):
		await get_tree().process_frame


# Exit: deceleration feel. No FOV snap — GameRoot already reset it.
# Blur briefly spikes then fades (momentum), shockwave ripples outward, tunnel dissolves.
func play_exit(duration: float = 2.0) -> void:
	if DisplayServer.get_name() == "headless":
		tunnel.visible = false
		distortion_overlay.visible = false
		flash.visible = false
		return

	tunnel_mat.set_shader_parameter("driven_speed", TUNNEL_SPEED_WARP)
	tunnel.visible = false
	distortion_overlay.visible = true
	flash.visible = true
	star_streaks.emitting = false

	var camera := _find_player_camera()

	var tween := create_tween().set_parallel(true)

	# Flash fades out fast — reveals the new system quickly
	tween.tween_property(flash, "modulate:a", 0.0, duration * 0.25
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Tunnel dissolves over most of the exit — slower = more visible corridor
	tween.tween_method(
		func(v): tunnel_mat.set_shader_parameter("intensity", v),
		1.0, 0.0, duration * 0.85
	).set_delay(duration * 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Tunnel speed winds down (deceleration)
	tween.tween_method(
		func(v): tunnel_mat.set_shader_parameter("driven_speed", v),
		TUNNEL_SPEED_WARP, TUNNEL_SPEED_BASE, duration * 0.7
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Decel blur: brief spike then fade — feels like braking
	tween.tween_method(
		func(v): distortion_mat.set_shader_parameter("radial_blur_strength", v),
		0.0, 0.07, duration * 0.15
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(
		func(v): distortion_mat.set_shader_parameter("radial_blur_strength", v),
		0.07, 0.0, duration * 0.5
	).set_delay(duration * 0.15).set_trans(Tween.TRANS_SINE)

	tween.tween_method(
		func(v): distortion_mat.set_shader_parameter("chromatic_strength", v),
		0.008, 0.0, duration * 0.5
	).set_trans(Tween.TRANS_SINE)

	# Shockwave ring expands outward and fades
	tween.tween_method(
		func(v): distortion_mat.set_shader_parameter("shockwave_progress", v),
		0.0, 1.3, duration * 0.75
	).set_delay(duration * 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(
		func(v): distortion_mat.set_shader_parameter("shockwave_amplitude", v),
		0.07, 0.0, duration * 0.7
	).set_delay(duration * 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Camera shake starts once the flash is down — feels like physical arrival impact
	if camera:
		_trigger_camera_shake(camera, duration * 0.5, duration * 0.3)

	await tween.finished

	tunnel.visible = false
	distortion_overlay.visible = false
	flash.visible = false
	if camera and is_instance_valid(camera):
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func play_arrival_banner(system_name: String) -> void:
	if DisplayServer.get_name() == "headless" or not _arrival_banner or not _arrival_name_label:
		return
	_arrival_name_label.text = system_name.to_upper()
	var tween := create_tween()
	tween.tween_property(_arrival_banner, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE)
	tween.tween_interval(2.0)
	tween.tween_property(_arrival_banner, "modulate:a", 0.0, 0.65).set_trans(Tween.TRANS_SINE)


func _find_player_camera() -> Camera3D:
	if not GlobalState.player:
		return null
	return GlobalState.player.get_node_or_null("CameraPivot/Camera3D") as Camera3D


# start_delay: seconds before shake starts (wait for flash to clear)
func _trigger_camera_shake(camera: Camera3D, duration: float, start_delay: float = 0.0) -> void:
	if start_delay > 0.0:
		await get_tree().create_timer(start_delay).timeout
	if not is_instance_valid(camera):
		return
	var elapsed := 0.0
	var frequency := 0.04
	while elapsed < duration:
		if not is_instance_valid(camera):
			return
		var t := elapsed / duration
		# Strength peaks early then decays — thud landing, not sustained vibration
		var strength := (1.0 - t) * (1.0 - t) * 0.6
		camera.h_offset = randf_range(-strength, strength)
		camera.v_offset = randf_range(-strength, strength)
		elapsed += frequency
		await get_tree().create_timer(frequency).timeout
	if is_instance_valid(camera):
		camera.h_offset = 0.0
		camera.v_offset = 0.0
