extends RefCounted

## How big an obstacle LOOKS, for the autopilot (playtest 2026-10-02: it flew
## through outposts). Stations and outposts load scaled models (Kova's is 20x)
## that dwarf their collision boxes, so a route sized from the collision clipped
## straight through what the player sees.
##
## visual_radius: the farthest corner of every mesh's bounds, measured from the
## node's origin. Cached on the node (meta), since models don't change size.

const CACHE_META := "_nav_visual_radius"


static func visual_radius(node: Node3D) -> float:
	if node == null or not is_instance_valid(node):
		return 0.0
	if node.has_meta(CACHE_META):
		return float(node.get_meta(CACHE_META))
	var inverse := node.global_transform.affine_inverse()
	var best := 0.0
	var found := false
	for child in node.find_children("*", "VisualInstance3D", true, false):
		var visual := child as VisualInstance3D
		if visual == null or not visual.is_visible_in_tree() or visual is Light3D:
			continue
		if visual is GPUParticles3D or visual is CPUParticles3D:
			continue
		var box: AABB = visual.get_aabb()
		if box.size.length_squared() <= 0.0:
			continue
		var to_node := inverse * visual.global_transform
		for i in 8:
			best = maxf(best, (to_node * box.get_endpoint(i)).length())
		found = true
	# Measured once the model is in; until then, don't cache a zero.
	if found:
		node.set_meta(CACHE_META, best)
	return best


## The largest collision shape under `node`, by the same rules the autopilot
## always used, but over EVERY shape, not just the first one named
## "CollisionShape3D" (runtime-added shapes get names like @CollisionShape3D@12).
static func collision_radius(node: Node3D) -> float:
	var best := 0.0
	for child in node.find_children("*", "CollisionShape3D", true, false):
		var collision := child as CollisionShape3D
		if collision == null or collision.shape == null:
			continue
		var scale := collision.global_transform.basis.get_scale().abs()
		var offset := node.global_transform.affine_inverse() * collision.global_position
		var r := 0.0
		var shape := collision.shape
		if shape is SphereShape3D:
			r = (shape as SphereShape3D).radius * maxf(scale.x, maxf(scale.y, scale.z))
		elif shape is BoxShape3D:
			r = ((shape as BoxShape3D).size * 0.5 * scale).length()
		elif shape is CylinderShape3D:
			var cyl := shape as CylinderShape3D
			r = maxf(cyl.radius * maxf(scale.x, scale.z), cyl.height * 0.5 * scale.y)
		elif shape is CapsuleShape3D:
			var cap := shape as CapsuleShape3D
			r = maxf(cap.radius * maxf(scale.x, scale.z), cap.height * 0.5 * scale.y)
		else:
			# Mesh-shaped collisions: their own bounds.
			var mesh := shape.get_debug_mesh()
			if mesh != null:
				r = (mesh.get_aabb().size * 0.5 * scale).length()
		best = maxf(best, r + offset.length())
	return best
