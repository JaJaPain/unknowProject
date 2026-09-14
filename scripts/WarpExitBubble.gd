extends Node3D

@onready var sphere: MeshInstance3D = $Sphere
@onready var particles: CPUParticles3D = $BlastParticles

var bubble_duration := 0.75

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		queue_free()
		return
		
	# Duplicate material to avoid overriding the global resource
	var mat = sphere.get_active_material(0).duplicate() as ShaderMaterial
	sphere.material_override = mat
	
	sphere.scale = Vector3.ONE * 0.1
	particles.emitting = true
	
	var tween = create_tween().set_parallel(true)
	
	# Expand bubble
	tween.tween_property(sphere, "scale", Vector3.ONE * 24.0, bubble_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Fade refraction and transparency
	tween.tween_method(
		func(val): mat.set_shader_parameter("alpha", val),
		1.0, 0.0, bubble_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	tween.tween_method(
		func(val): mat.set_shader_parameter("refraction_strength", val),
		0.07, 0.0, bubble_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	await tween.finished
	queue_free()
