extends SceneTree
func _init():
	var root := Node3D.new()
	get_root().add_child(root)
	var ship := ShipAssembler.build_special(0)
	root.add_child(ship)
	await process_frame
	var meshes: Array = []
	_c(ship, meshes)
	var box := AABB(); var first := true
	for mi in meshes:
		var b: AABB = (ship.global_transform.affine_inverse()*mi.global_transform)*mi.get_aabb()
		if first: box=b; first=false
		else: box=box.merge(b)
	print("SPECIAL AABB pos=", box.position, " size=", box.size)
	# hull.tall bare
	var h := (load("res://assets/ship_parts/hulls/hull.tall.glb") as PackedScene).instantiate()
	root.add_child(h); await process_frame
	var hm: Array = []; _c(h, hm)
	var hb := AABB(); first=true
	for mi in hm:
		var b: AABB = (h.global_transform.affine_inverse()*mi.global_transform)*mi.get_aabb()
		if first: hb=b; first=false
		else: hb=hb.merge(b)
	print("HULL.TALL size=", hb.size)
	quit()
func _c(n: Node, o: Array) -> void:
	if n is MeshInstance3D: o.append(n)
	for c in n.get_children(): _c(c,o)
