extends CanvasLayer

@onready var tunnel: ColorRect = $Tunnel
@onready var distortion_overlay: ColorRect = $DistortionOverlay
@onready var star_streaks: CPUParticles2D = $StarStreaks
@onready var flash: ColorRect = $Flash

var tunnel_mat: ShaderMaterial
var distortion_mat: ShaderMaterial

func _ready() -> void:
	tunnel_mat = tunnel.material as ShaderMaterial
	distortion_mat = distortion_overlay.material as ShaderMaterial
	tunnel.visible = false
	distortion_overlay.visible = false
	star_streaks.emitting = false
	flash.visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Center star streaks on viewport regardless of resolution
	var vp := get_viewport()
	if vp:
		star_streaks.position = vp.get_visible_rect().size * 0.5


# GameRoot calls this. GameRoot already tweens camera FOV during entry,
# so we only drive the overlay visuals here.
func play_entry(duration: float = 1.2) -> void:
	if DisplayServer.get_name() == "headless":
		return
	tunnel_mat.set_shader_parameter("intensity", 0.0)
	distortion_mat.set_shader_parameter("radial_blur_strength", 0.0)
	distortion_mat.set_shader_parameter("shockwave_progress", 0.0)
	distortion_mat.set_shader_parameter("shockwave_amplitude", 0.0)
	tunnel.visible = true
	distortion_overlay.visible = true
	flash.visible = true
	flash.modulate.a = 0.0
	star_streaks.emitting = true

	var tween := create_tween().set_parallel(true)
	# Phase 1: tunnel ramps up over the first half
	tween.tween_method(
		func(val): tunnel_mat.set_shader_parameter("intensity", val),
		0.0, 0.6, duration * 0.5
	).set_trans(Tween.TRANS_SINE)

	# Phase 2: snap-in — tunnel to full, radial blur spike, white-out flash
	tween.tween_method(
		func(val): tunnel_mat.set_shader_parameter("intensity", val),
		0.6, 1.0, duration * 0.5
	).set_delay(duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	tween.tween_method(
		func(val): distortion_mat.set_shader_parameter("radial_blur_strength", val),
		0.0, 0.12, duration * 0.5
	).set_delay(duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	tween.tween_property(flash, "modulate:a", 1.0, duration * 0.4
	).set_delay(duration * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	await tween.finished


# Called while the new system is loading, screen stays covered.
# frame_count matches the existing GameRoot call site.
func hold_covered(frame_count: int = 2) -> void:
	tunnel_mat.set_shader_parameter("intensity", 1.0)
	distortion_mat.set_shader_parameter("radial_blur_strength", 0.0)
	distortion_mat.set_shader_parameter("shockwave_progress", 0.0)
	distortion_mat.set_shader_parameter("shockwave_amplitude", 0.0)
	tunnel.visible = true
	distortion_overlay.visible = true
	flash.visible = true
	flash.modulate.a = 1.0
	star_streaks.emitting = false
	for _i in range(frame_count):
		await get_tree().process_frame


func play_exit(duration: float = 0.9) -> void:
	if DisplayServer.get_name() == "headless":
		tunnel.visible = false
		distortion_overlay.visible = false
		flash.visible = false
		return
	tunnel.visible = true
	distortion_overlay.visible = true
	flash.visible = true
	star_streaks.emitting = false

	var camera := _find_player_camera()
	var base_fov := camera.fov if camera else 70.0
	if camera:
		camera.fov = base_fov + 12.0

	var tween := create_tween().set_parallel(true)
	tween.tween_property(flash, "modulate:a", 0.0, duration * 0.4
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	tween.tween_method(
		func(val): tunnel_mat.set_shader_parameter("intensity", val),
		1.0, 0.0, duration
	).set_trans(Tween.TRANS_SINE)

	tween.tween_method(
		func(val): distortion_mat.set_shader_parameter("shockwave_progress", val),
		0.0, 1.2, duration * 0.9
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	tween.tween_method(
		func(val): distortion_mat.set_shader_parameter("shockwave_amplitude", val),
		0.08, 0.0, duration * 0.9
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if camera:
		tween.tween_property(camera, "fov", base_fov, duration * 0.6
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if camera:
		_trigger_camera_shake(camera, duration * 0.7)

	await tween.finished

	tunnel.visible = false
	distortion_overlay.visible = false
	flash.visible = false
	if camera:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func _find_player_camera() -> Camera3D:
	var player: Node = GlobalState.player if GlobalState.player else null
	if not player:
		return null
	return player.get_node_or_null("CameraPivot/Camera3D") as Camera3D


func _trigger_camera_shake(camera: Camera3D, duration: float) -> void:
	var shake_tween := create_tween()
	var elapsed := 0.0
	var frequency := 0.05
	while elapsed < duration:
		var strength := (1.0 - (elapsed / duration)) * 0.8
		shake_tween.tween_property(camera, "h_offset", randf_range(-strength, strength), frequency)
		shake_tween.tween_property(camera, "v_offset", randf_range(-strength, strength), frequency)
		elapsed += frequency
		await get_tree().create_timer(frequency).timeout
	if is_instance_valid(camera):
		camera.h_offset = 0.0
		camera.v_offset = 0.0
