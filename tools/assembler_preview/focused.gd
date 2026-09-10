extends Node3D
const ANGLES := {"a": Vector3(0.6,0.4,0.7), "b": Vector3(1,0.1,0.05), "c": Vector3(0.05,0.1,1)}

func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(1000,1000))
	var cam: Camera3D = $Camera3D
	var gray := StandardMaterial3D.new(); gray.albedo_color = Color(0.65,0.66,0.7); gray.metallic=0.5; gray.roughness=0.45
	await get_tree().process_frame

	# 1) hull.Grill bare
	# 2) full Gunner #6 (seed=5 -> index 5)
	var targets := [
		{"tag":"tall_bare", "node": (load("res://assets/ship_parts/hulls/hull.tall.glb") as PackedScene).instantiate(), "gray": true},
	]
	for t in targets:
		for c in $ShipHolder.get_children(): c.queue_free()
		await get_tree().process_frame
		var node = t["node"]
		if t["gray"]: ShipAssembler._apply_material(node, gray)
		$ShipHolder.add_child(node)
		var box := _aabb(node); var size: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
		var center: Vector3 = box.position + box.size*0.5
		for a in ANGLES:
			cam.position = center + (ANGLES[a] as Vector3).normalized() * maxf(size*1.0, 4.0)
			cam.look_at(center, Vector3.UP)
			for _f in range(5): await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, t["tag"], a])
		print("DONE ", t["tag"])
	print("FOCUSED_DONE"); get_tree().quit()

func _aabb(n: Node3D) -> AABB:
	var m: Array = []; _c(n,m); var r := AABB(); var f := true
	for mi in m:
		var b: AABB = (n.global_transform.affine_inverse()*mi.global_transform)*mi.get_aabb()
		if f: r=b; f=false
		else: r=r.merge(b)
	return r
func _c(n: Node, o: Array) -> void:
	if n is MeshInstance3D: o.append(n)
	for c in n.get_children(): _c(c,o)
