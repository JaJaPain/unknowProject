extends Node3D
const GUNS := ["Big_Gun","Med_Gun","Turret_Set","Small_Gun.001","hardpoint.gun.barb","hardpoint.gun.bracket","hardpoint.gun.fork","hardpoitn.gun.dual"]
func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(820,820))
	var env := Environment.new(); env.background_mode=Environment.BG_COLOR
	env.background_color=Color(0.03,0.04,0.07); env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color(0.6,0.65,0.75); env.ambient_light_energy=1.2; env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	var we:=WorldEnvironment.new(); we.environment=env; add_child(we)
	var key:=DirectionalLight3D.new(); key.rotation_degrees=Vector3(-45,-35,0); key.light_energy=1.8; add_child(key)
	var cam:=Camera3D.new(); cam.fov=45; add_child(cam); cam.current=true
	var holder:=Node3D.new(); add_child(holder)
	var gray:=StandardMaterial3D.new(); gray.albedo_color=Color(0.6,0.62,0.66); gray.metallic=0.6; gray.roughness=0.4
	var cols=4; var cell=205
	var sheet:=Image.create(cols*cell,2*cell,false,Image.FORMAT_RGBA8); sheet.fill(Color(0.02,0.025,0.04))
	for i in range(GUNS.size()):
		for c in holder.get_children(): c.queue_free()
		await get_tree().process_frame
		var path="res://assets/ship_parts/weapons/%s.glb" % GUNS[i]
		if not ResourceLoader.exists(path): print("MISSING",GUNS[i]); continue
		var n=(load(path) as PackedScene).instantiate()
		ShipAssembler._apply_material(n,gray); holder.add_child(n)
		await get_tree().process_frame
		var box=_ab(n); var sz: float=maxf(box.size.x,maxf(box.size.y,box.size.z))
		var ctr: Vector3=box.position+box.size*0.5
		cam.position=ctr+Vector3(0.6,0.5,0.8).normalized()*maxf(sz*1.1,2.0); cam.look_at(ctr,Vector3.UP)
		for _f in range(4): await RenderingServer.frame_post_draw
		var img=get_viewport().get_texture().get_image(); img.resize(cell,cell)
		if img.get_format()!=Image.FORMAT_RGBA8: img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img,Rect2i(0,0,cell,cell),Vector2i((i%cols)*cell,(i/cols)*cell))
		print("[%d] %s" % [i, GUNS[i]])
	sheet.save_png("%s/guns.png" % out); print("GUNS_DONE"); get_tree().quit()
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
