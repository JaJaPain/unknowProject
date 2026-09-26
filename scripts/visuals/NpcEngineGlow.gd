class_name NpcEngineGlow
extends RefCounted

## NPC engine glow: one stretched, unshaded blob per engine point, drawn with a
## single MultiMesh. Each blob is sized to its nozzle (the "thruster_radius"
## meta ShipAssembler puts on thruster markers; points without it keep the old
## fixed size) and trails out behind (+Z).

const BASE_RADIUS := 0.42
## How far the glow stretches rearward, as a multiple of its width.
const TRAIL := 1.9
## A sized nozzle's glow fills this much of its exit.
const NOZZLE_FILL := 0.9


## True for nodes that mark where an engine exhausts. Hidden socket meshes
## inside engine parts are skipped: ShipAssembler already made markers for them.
static func is_engine_point(node: Node) -> bool:
	if not node is Node3D:
		return false
	if node is MeshInstance3D and not (node as MeshInstance3D).visible:
		return false
	var lower_name := str(node.name).to_lower()
	return lower_name.begins_with("engine_") or "thruster" in lower_name or "exhaust" in lower_name


## Builds the glow under `visual`. Returns the node and each blob's base
## transform (for animate()).
static func build(visual: Node3D, points: Array[Node3D], color: Color) -> Dictionary:
	var glow := MultiMeshInstance3D.new()
	glow.name = "EngineGlow"
	var mesh := SphereMesh.new()
	mesh.radius = BASE_RADIUS
	mesh.height = BASE_RADIUS * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(color.r, color.g, color.b, 0.82)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 4.0
	mesh.material = material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = points.size()
	var bases: Array[Transform3D] = []
	var inverse := visual.global_transform.affine_inverse()
	for index in points.size():
		var point := points[index]
		var relative := inverse * point.global_transform
		# Nozzle size in the visual's space: the marker's own radius, scaled
		# by however the engine part was scaled onto the hull.
		# Points without a radius keep the old fixed size.
		var width := 1.0
		if point.has_meta("thruster_radius"):
			width = relative.basis.get_scale().x * float(point.get_meta("thruster_radius")) * NOZZLE_FILL / BASE_RADIUS
		var basis := Basis.IDENTITY.scaled(Vector3(width, width, width * TRAIL))
		var origin := relative.origin + Vector3(0.0, 0.0, BASE_RADIUS * width * (TRAIL - 1.0))
		var base := Transform3D(basis, origin)
		multimesh.set_instance_transform(index, base)
		bases.append(base)
	glow.multimesh = multimesh
	visual.add_child(glow)
	return {"node": glow, "material": material, "bases": bases}


## Pulses and scales the glow with speed (0..1).
static func animate(glow: MultiMeshInstance3D, material: StandardMaterial3D, bases: Array[Transform3D], speed_ratio: float) -> void:
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.012) * 0.15
	material.albedo_color.a = lerpf(0.3, 0.9, speed_ratio) * pulse
	material.emission_energy_multiplier = lerpf(2.0, 6.0, speed_ratio) * pulse
	var mm := glow.multimesh
	if mm == null:
		return
	var s := lerpf(0.6, 1.4, speed_ratio) * pulse
	for i in mini(bases.size(), mm.instance_count):
		var base := bases[i]
		mm.set_instance_transform(i, Transform3D(base.basis.scaled(Vector3(s, s, s)), base.origin))
