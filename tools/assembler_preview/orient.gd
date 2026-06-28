extends Node3D
const VIEWS := {"rear": Vector3(0.2,0.25,-1), "q34": Vector3(0.7,0.4,-0.7), "side": Vector3(1,0.15,0.05)}
func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(900,900))
	var cam: Camera3D = $Camera3D
	var gray := StandardMaterial3D.new(); gray.albedo_color=Color(0.5,0.52,0.56); gray.metallic=0.85; gray.roughness=0.4
	await get_tree().process_frame
	for rotx in [-90, 90]:
		for c in $ShipHolder.get_children(): c.queue_free()
		await get_tree().process_frame
		var h := (load("res://assets/ship_parts/hulls/hull.tall.glb") as PackedScene).instantiate()
		h.rotation_degrees = Vector3(rotx, 0, 0)
		ShipAssembler._apply_material(h, gray)
		$ShipHolder.add_child(h)
		await get_tree().process_frame
		var box := _aabb(h); var size: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
		var center: Vector3 = box.position + box.size*0.5
		for v in VIEWS:
			cam.position = center + (VIEWS[v] as Vector3).normalized()*maxf(size*1.0,4.0)
			cam.look_at(center, Vector3.UP)
			for _f in range(4): await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/rot%d_%s.png" % [out, rotx, v])
		print("DONE rot", rotx)
	print("ORIENT_DONE"); get_tree().quit()
func _aabb(n: Node3D) -> AABB:
	var m: Array=[]; _c(n,m); var r:=AABB(); var f:=true
	for mi in m:
		var b: AABB=(n.global_transform.affine_inverse()*mi.global_transform)*mi.get_aabb()
		if f: r=b;f=false
		else: r=r.merge(b)
	return r
func _c(n: Node,o: Array)->void:
	if n is MeshInstance3D: o.append(n)
	for c in n.get_children(): _c(c,o)
