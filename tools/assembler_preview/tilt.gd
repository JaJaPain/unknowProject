extends Node3D
const TILTS := [0, 25, 45, 70]
func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(900,900))
	var env := Environment.new(); env.background_mode=Environment.BG_COLOR
	env.background_color=Color(0.03,0.04,0.07); env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color(0.55,0.6,0.72); env.ambient_light_energy=1.0; env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	var we:=WorldEnvironment.new(); we.environment=env; add_child(we)
	var key:=DirectionalLight3D.new(); key.rotation_degrees=Vector3(-40,-35,0); key.light_energy=1.7; add_child(key)
	var cam:=Camera3D.new(); cam.fov=45; add_child(cam); cam.current=true
	var holder:=Node3D.new(); add_child(holder)
	for tilt in TILTS:
		for c in holder.get_children(): c.queue_free()
		await get_tree().process_frame
		var ship := ShipAssembler.build_special(0)
		ship.rotation_degrees = Vector3(tilt, 0, 0)   # pitch back
		holder.add_child(ship)
		await get_tree().process_frame
		var box := _ab(ship); var sz: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
		var ctr: Vector3 = box.position + box.size*0.5
		# player-like view: behind (+Z) and above, looking down slightly
		cam.position = ctr + Vector3(0, sz*0.35, sz*1.5)
		cam.look_at(ctr, Vector3.UP)
		for _f in range(5): await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/tilt_%d.png" % [out, tilt])
		print("SHOT tilt", tilt)
	print("TILT_DONE"); get_tree().quit()
func _ab(n: Node3D) -> AABB:
	var m: Array=[]; _c(n,m); var r:=AABB(); var f:=true
	for mi in m:
		var b: AABB=(n.global_transform.affine_inverse()*mi.global_transform)*mi.get_aabb()
		if f: r=b;f=false
		else: r=r.merge(b)
	return r
func _c(n: Node,o: Array)->void:
	if n is MeshInstance3D: o.append(n)
	for c in n.get_children(): _c(c,o)
