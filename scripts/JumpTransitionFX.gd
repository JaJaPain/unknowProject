extends CanvasLayer

@onready var tunnel: ColorRect = $Tunnel
@onready var flash: ColorRect = $Flash

var tunnel_material: ShaderMaterial

func _ready() -> void:
	tunnel_material = tunnel.material as ShaderMaterial
	tunnel.visible = false
	flash.visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func play_entry(duration: float = 1.2) -> void:
	tunnel.visible = true
	flash.visible = true
	tunnel_material.set_shader_parameter("intensity", 0.0)
	flash.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_method(_set_tunnel_intensity, 0.0, 1.0, duration)
	tween.tween_property(flash, "modulate:a", 1.0, duration * 0.35).set_delay(duration * 0.65)
	await tween.finished

func play_exit(duration: float = 0.9) -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(flash, "modulate:a", 0.0, duration * 0.35)
	tween.tween_method(_set_tunnel_intensity, 1.0, 0.0, duration)
	await tween.finished
	tunnel.visible = false
	flash.visible = false

func hold_covered(frame_count: int = 2) -> void:
	tunnel.visible = true
	flash.visible = true
	tunnel_material.set_shader_parameter("intensity", 1.0)
	flash.modulate.a = 1.0
	for frame in range(frame_count):
		await get_tree().process_frame

func _set_tunnel_intensity(value: float) -> void:
	tunnel_material.set_shader_parameter("intensity", value)
