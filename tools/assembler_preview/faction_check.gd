extends Node3D
func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(820,820))
	var env := Environment.new(); env.background_mode=Environment.BG_COLOR
	env.background_color=Color(0.03,0.04,0.07); env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color(0.6,0.65,0.75); env.ambient_light_energy=1.4; env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	var we:=WorldEnvironment.new(); we.environment=env; add_child(we)
	var key:=DirectionalLight3D.new(); key.rotation_degrees=Vector3(-45,-35,0); key.light_energy=2.0; add_child(key)
	var cam:=Camera3D.new(); cam.fov=50; add_child(cam); cam.current=true
	var holder:=Node3D.new(); add_child(holder)
	var cols=2; var cell=400
	var sheet:=Image.create(cols*cell,cell,false,Image.FORMAT_RGBA8); sheet.fill(Color(0.02,0.025,0.04))
	var facs=["zenith","aurelia"]
	for i in range(facs.size()):
		for c in holder.get_children(): c.queue_free()
		await get_tree().process_frame
		var ship=ShipAssembler.build_catalog_ship(facs[i],"Gunner",1)
		if ship==null: print("NULL",facs[i]); continue
		holder.add_child(ship); await get_tree().process_frame
		var box=_ab(ship); var sz: float=maxf(box.size.x,maxf(box.size.y,box.size.z))
		var ctr: Vector3=box.position+box.size*0.5
		cam.position=ctr+Vector3(0.6,0.4,0.7).normalized()*sz*1.05; cam.look_at(ctr,Vector3.UP)
		for _f in range(5): await RenderingServer.frame_post_draw
		var img=get_viewport().get_texture().get_image(); img.resize(cell,cell)
		if img.get_format()!=Image.FORMAT_RGBA8: img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img,Rect2i(0,0,cell,cell),Vector2i(i*cell,0))
		print("OK",facs[i])
	sheet.save_png("%s/factions.png"%out); print("FAC_DONE"); get_tree().quit()
func _ab(n: Node3D)->AABB:
	var m: Array=[]; _c(n,m); var r:=AABB(); var f:=true
	for mi in m:
		var b: AABB=(n.global_transform.affine_inverse()*mi.global_transform)*mi.get_aabb()
		if f: r=b;f=false
		else: r=r.merge(b)
	return r
func _c(n: Node,o: Array)->void:
	if n is MeshInstance3D: o.append(n)
	for c in n.get_children(): _c(c,o)
