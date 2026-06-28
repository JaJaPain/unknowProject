class_name ThrusterBank
extends Node

const THRUSTER_PLUME_SHADER := preload("res://assets/shaders/thruster_plume.gdshader")
const MIN_VISIBLE_THROTTLE := 0.03

var _anchors: Array[Node3D] = []
var _effects: Array[Dictionary] = []
var _engine_color: Color = Color(0.35, 0.75, 1.0)
var _scale_factor: float = 1.0
var _shared_light: OmniLight3D = null
var _visual_boost: float = 0.0
var _last_update_msec: int = 0


func setup(anchor_points: Array[Node3D], color: Color, scale_factor: float = 1.0) -> void:
	clear()
	_engine_color = color
	_scale_factor = maxf(scale_factor, 0.05)
	for anchor in anchor_points:
		if is_instance_valid(anchor):
			_anchors.append(anchor)
			_effects.append(_create_effect(anchor))
	_create_shared_light()
	update_intensity(0.0, false)


func clear() -> void:
	for effect in _effects:
		for key in effect.keys():
			var node: Variant = effect[key]
			if node is Node and is_instance_valid(node):
				node.queue_free()
	_effects.clear()
	_anchors.clear()
	if is_instance_valid(_shared_light):
		_shared_light.queue_free()
	_shared_light = null
	_visual_boost = 0.0
	_last_update_msec = 0


func update_intensity(throttle: float, boosting: bool) -> void:
	throttle = clampf(throttle, 0.0, 1.0)
	var now_msec := Time.get_ticks_msec()
	var delta := 0.016
	if _last_update_msec > 0:
		delta = clampf(float(now_msec - _last_update_msec) * 0.001, 0.0, 0.1)
	_last_update_msec = now_msec

	var boost_target := 1.0 if boosting else 0.0
	var boost_speed := 9.0 if boosting else 2.6
	_visual_boost = lerpf(_visual_boost, boost_target, minf(delta * boost_speed, 1.0))
	if not boosting and _visual_boost < 0.01:
		_visual_boost = 0.0

	var visible := throttle >= MIN_VISIBLE_THROTTLE or boosting or _visual_boost > 0.01
	var boost_t := _visual_boost
	var pulse := 1.0 + sin(Time.get_ticks_msec() * (0.018 + boost_t * 0.014)) * (0.08 + boost_t * 0.10)
	var core_energy := lerpf(2.8, 8.5, throttle) * lerpf(1.0, 1.8, boost_t) * pulse
	var alpha := lerpf(0.25, 0.88, throttle) * lerpf(1.0, 1.25, boost_t)
	var inner_len := lerpf(0.55, 1.35, throttle) * lerpf(1.0, 2.25, boost_t) * _scale_factor
	var outer_len := lerpf(1.0, 2.35, throttle) * lerpf(1.0, 2.75, boost_t) * _scale_factor
	var core_scale := lerpf(0.55, 1.0, throttle) * lerpf(1.0, 1.22, boost_t) * pulse

	for effect in _effects:
		_set_node_visible(effect, visible)
		if not visible:
			continue
		var core := effect.get("core") as MeshInstance3D
		var inner := effect.get("inner") as MeshInstance3D
		var outer := effect.get("outer") as MeshInstance3D
		var warm_tip := effect.get("warm_tip") as MeshInstance3D
		var halo := effect.get("halo") as MeshInstance3D

		if core:
			core.scale = Vector3.ONE * core_scale
			var mat := core.material_override as StandardMaterial3D
			if mat:
				mat.emission_energy_multiplier = core_energy
				mat.albedo_color = Color(0.85, 0.96, 1.0, minf(1.0, alpha + 0.16))
		if inner:
			inner.position.z = inner_len * 0.48
			inner.scale = Vector3(1.0, inner_len, 1.0)
			var mat := inner.material_override as ShaderMaterial
			if mat:
				mat.set_shader_parameter("alpha", minf(0.88, alpha * 0.92))
				mat.set_shader_parameter("tip_strength", lerpf(0.10, 0.28, boost_t))
		if outer:
			outer.position.z = outer_len * 0.50
			outer.scale = Vector3(1.0, outer_len, 1.0)
			var mat := outer.material_override as ShaderMaterial
			if mat:
				mat.set_shader_parameter("alpha", minf(0.42, alpha * 0.48))
				mat.set_shader_parameter("tip_strength", lerpf(0.20, 0.55, boost_t))
		if warm_tip:
			warm_tip.position.z = outer_len * lerpf(0.76, 0.88, boost_t)
			var tip_width := lerpf(0.38, 0.62, throttle) * lerpf(1.0, 1.12, boost_t)
			var tip_len := lerpf(0.75, 1.35, throttle) * lerpf(1.0, 1.55, boost_t)
			warm_tip.scale = Vector3(tip_width, tip_len, tip_width)
			var mat := warm_tip.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color.a = lerpf(0.04, 0.18, throttle) * lerpf(1.0, 1.35, boost_t)
				mat.emission_energy_multiplier = lerpf(1.4, 4.2, throttle) * lerpf(1.0, 1.25, boost_t) * pulse
		if halo:
			var s := lerpf(1.0, 1.7, throttle) * lerpf(1.0, 1.35, boost_t) * pulse * _scale_factor
			halo.scale = Vector3(s, s, s)
			var mat := halo.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color.a = minf(0.72, alpha * 0.66)
				mat.emission_energy_multiplier = lerpf(2.0, 6.0, throttle) * lerpf(1.0, 1.8, boost_t)

	if _shared_light:
		_shared_light.visible = visible
		_shared_light.light_energy = lerpf(0.0, 5.5, throttle) * lerpf(1.0, 2.2, boost_t) if visible else 0.0
		_shared_light.light_color = _engine_color.lerp(Color.WHITE, 0.25 + boost_t * 0.25)


func _create_effect(anchor: Node3D) -> Dictionary:
	var root := Node3D.new()
	root.name = "ThrusterVFX"
	anchor.add_child(root)

	var socket_scale := _socket_scale_for(anchor)
	var core := _create_core(socket_scale)
	root.add_child(core)

	var inner := _create_plume("InnerPlume", socket_scale, 0.34, 0.18, true)
	root.add_child(inner)

	var outer := _create_plume("OuterPlume", socket_scale, 0.58, 0.16, false)
	root.add_child(outer)

	var warm_tip := _create_warm_tip(socket_scale)
	root.add_child(warm_tip)

	var halo := _create_halo(socket_scale)
	root.add_child(halo)

	return {
		"root": root,
		"core": core,
		"inner": inner,
		"outer": outer,
		"warm_tip": warm_tip,
		"halo": halo,
	}


func _create_core(socket_scale: float) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.16 * socket_scale * _scale_factor
	mesh.height = 0.22 * socket_scale * _scale_factor
	mesh.radial_segments = 16
	mesh.rings = 8
	var node := MeshInstance3D.new()
	node.name = "ThrusterCore"
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position.z = 0.08 * socket_scale * _scale_factor
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.85, 0.96, 1.0, 0.95)
	mat.emission_enabled = true
	mat.emission = _engine_color.lerp(Color.WHITE, 0.65)
	mat.emission_energy_multiplier = 5.0
	node.material_override = mat
	return node


func _create_plume(
	node_name: String,
	socket_scale: float,
	radius: float,
	tip_radius: float,
	hot: bool
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius * socket_scale * _scale_factor
	mesh.top_radius = tip_radius * socket_scale * _scale_factor
	mesh.height = 1.0
	mesh.radial_segments = 24
	mesh.rings = 8
	mesh.cap_top = false
	mesh.cap_bottom = false
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.rotation_degrees.x = 90.0
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.material_override = _create_plume_material(hot)
	return node


func _create_plume_material(hot: bool) -> ShaderMaterial:
	var color := _engine_color.lerp(Color.WHITE, 0.48 if hot else 0.15)
	var mat := ShaderMaterial.new()
	mat.shader = THRUSTER_PLUME_SHADER
	mat.set_shader_parameter("plume_color", Color(color, 1.0))
	mat.set_shader_parameter("tip_color", Color(1.0, 0.82, 0.48, 1.0))
	mat.set_shader_parameter("alpha", 0.78 if hot else 0.34)
	mat.set_shader_parameter("edge_power", 1.8 if hot else 1.2)
	mat.set_shader_parameter("tip_strength", 0.12 if hot else 0.24)
	return mat


func _create_warm_tip(socket_scale: float) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.13 * socket_scale * _scale_factor
	mesh.height = 0.95 * socket_scale * _scale_factor
	mesh.radial_segments = 16
	mesh.rings = 8
	var node := MeshInstance3D.new()
	node.name = "WarmThrusterTip"
	node.mesh = mesh
	node.rotation_degrees.x = 90.0
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.albedo_color = Color(1.0, 0.88, 0.62, 0.10)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.86, 0.58)
	mat.emission_energy_multiplier = 2.4
	node.material_override = mat
	return node


func _create_halo(socket_scale: float) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.2, 1.2) * socket_scale * _scale_factor
	var node := MeshInstance3D.new()
	node.name = "ThrusterHalo"
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position.z = 0.03 * socket_scale * _scale_factor
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(_engine_color, 0.42)
	mat.emission_enabled = true
	mat.emission = _engine_color
	mat.emission_energy_multiplier = 3.2
	node.material_override = mat
	return node


func _create_shared_light() -> void:
	if _anchors.is_empty():
		return
	var parent := _anchors[0].get_parent() as Node3D
	if parent == null:
		return
	_shared_light = OmniLight3D.new()
	_shared_light.name = "ThrusterBankLight"
	_shared_light.light_color = _engine_color
	_shared_light.light_energy = 0.0
	_shared_light.omni_range = 10.0 * _scale_factor
	parent.add_child(_shared_light)
	var average := Vector3.ZERO
	for anchor in _anchors:
		average += parent.to_local(anchor.global_position)
	average /= float(_anchors.size())
	_shared_light.position = average + Vector3(0.0, 0.0, 0.5 * _scale_factor)


func _socket_scale_for(anchor: Node3D) -> float:
	if anchor.has_meta("thruster_radius"):
		return maxf(float(anchor.get_meta("thruster_radius")), 0.08)
	return 1.0


func _set_node_visible(effect: Dictionary, visible: bool) -> void:
	var root := effect.get("root") as Node3D
	if root:
		root.visible = visible
