extends Node3D
const VIEWS := {"userang": Vector3(-0.55,0.35,-0.75)}
func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(900,900))
	var env := Environment.new(); env.background_mode=Environment.BG_COLOR
	env.background_color=Color(0.03,0.04,0.07); env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color(0.6,0.65,0.75); env.ambient_light_energy=2.0; env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	var we:=WorldEnvironment.new(); we.environment=env; add_child(we)
	var key:=DirectionalLight3D.new(); key.rotation_degrees=Vector3(-50,-30,0); key.light_energy=2.5; add_child(key)
	var cam:=Camera3D.new(); cam.fov=45; add_child(cam); cam.current=true
	var ship := ShipAssembler.build_special(0); add_child(ship)
	# report weapon mount positions
	for c in ship.get_children():
		if str(c.name).begins_with("mount_weapons") or str(c.name).begins_with("weapon_"):
			print("WPN ", c.name, " pos=", c.position)
	await get_tree().process_frame
	var box := _ab(ship); var sz: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	var ctr: Vector3 = box.position + box.size*0.5
	for v in VIEWS:
		var up := Vector3.UP if v!="top" else Vector3(0,0,-1)
		cam.position = ctr + (VIEWS[v] as Vector3).normalized()*sz*1.1
		cam.look_at(ctr, up)
		for _f in range(5): await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/hp_%s.png" % [out, v])
	print("HP_DONE"); get_tree().quit()
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
