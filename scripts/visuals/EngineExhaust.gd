class_name EngineExhaust
extends RefCounted


static func create_exhaust(
	parent: Node3D,
	anchor_points: Array[Node3D],
	color: Color,
	scale_factor: float = 1.0
) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if anchor_points.is_empty():
		return result

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, 0.5)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.5
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED

	var mesh := SphereMesh.new()
	mesh.radius = 0.18 * scale_factor
	mesh.height = 0.7 * scale_factor
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = mat

	for anchor in anchor_points:
		if not is_instance_valid(anchor):
			continue

		var flame := MeshInstance3D.new()
		flame.name = "EngineExhaust"
		flame.mesh = mesh
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.visible = false

		var relative_xform := parent.global_transform.affine_inverse() * anchor.global_transform
		flame.position = relative_xform.origin + Vector3(0, 0, 0.3 * scale_factor)
		flame.rotation = relative_xform.basis.get_euler()
		parent.add_child(flame)
		result.append(flame)

	return result


static func update_intensity(
	flames: Array[MeshInstance3D],
	speed_ratio: float,
	is_boosting: bool
) -> void:
	speed_ratio = clampf(speed_ratio, 0.0, 1.0)
	for flame in flames:
		if not is_instance_valid(flame):
			continue
		if speed_ratio < 0.01:
			flame.visible = false
			continue
		flame.visible = true
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.015) * 0.15
		if is_boosting:
			flame.scale = Vector3(1.2, 1.2, 2.5) * pulse
		else:
			var s := lerpf(0.4, 1.0, speed_ratio)
			var stretch := lerpf(0.6, 1.4, speed_ratio)
			flame.scale = Vector3(s, s, stretch) * pulse
