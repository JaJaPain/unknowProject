extends SceneTree

## Kitbash ships from behind with their engine glow lit (full throttle), for
## checking thruster placement by eye. Row 1: each engine part on its own.
## Row 2: catalog ships of several factions. Needs a window (not headless):
##   Godot --path . --script res://tools/engine_glow_snapshot.gd --log-file <path> -- --out=<dir>

const Assembler := preload("res://scripts/generation/ShipAssembler.gd")
const Glow := preload("res://scripts/visuals/NpcEngineGlow.gd")

const ENGINES := ["Cube_Engine", "Bracket_Engine", "Trap-Engine", "eng.body.split", "5-Engine", "Block_Engine_single"]

var _out := "user://engine_glow_snapshots"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var world := Node3D.new()
	root.add_child(world)
	# Global transforms need the world inside the tree.
	await process_frame
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.3, 0.4)
	sky_mat.sky_horizon_color = Color(0.5, 0.52, 0.56)
	sky_mat.ground_bottom_color = Color(0.1, 0.1, 0.12)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.environment.sky = sky
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.03, 0.035, 0.05)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment.ambient_light_energy = 1.4
	env.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.environment.glow_enabled = true
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 25, 0)
	sun.light_energy = 2.2
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -160, 0)
	fill.light_energy = 1.2
	world.add_child(fill)

	var spacing := 16.0
	var colors := [Color(1.0, 0.25, 0.08), Color(0.2, 0.65, 1.0), Color(0.35, 0.85, 1.0)]
	for i in ENGINES.size():
		var holder := Node3D.new()
		var part := Assembler._load_part("engines", ENGINES[i])
		if part == null:
			continue
		holder.add_child(part)
		Assembler._add_thruster_socket_markers(holder, part, 0)
		_place(world, holder, Vector3((i - 2.5) * spacing * 0.8, 8.0, 0.0), 9.0)
		_light(holder, colors[0])
		print("GLOWSHOT engine %s" % ENGINES[i])
	var ships := [["vanguard", "Interceptor"], ["vanguard", "Gunner"], ["zenith", "MiningHauler"], ["reavers", "Gunner"], ["ironclad", "Interceptor"]]
	for i in ships.size():
		var ship := Assembler.build_catalog_ship(ships[i][0], ships[i][1], 5 + i)
		if ship == null:
			continue
		_place(world, ship, Vector3((i - 2.0) * spacing, -9.0, 0.0), 14.0)
		_light(ship, colors[i % colors.size()])
		var parts := []
		for child in ship.get_children():
			if str(child.name).begins_with("mount_engines"):
				parts.append(child.scene_file_path.get_file())
		print("GLOWSHOT ship %s %s engines %s" % [ships[i][0], ships[i][1], str(parts)])

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 45.0
	# From behind (+Z is the rear) and a little above.
	cam.position = Vector3(0, 8, 62)
	cam.look_at(Vector3(0, -1, 0))
	cam.current = true
	root.size = Vector2i(1600, 900)
	for i in 15:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join("engine_glow.png"))
	print("GLOWSHOT saved")
	quit(0)


func _light(ship: Node3D, color: Color) -> void:
	var points: Array[Node3D] = []
	_collect(ship, points)
	if points.is_empty():
		print("GLOWSHOT no engine points on %s" % ship.name)
		return
	var sized := 0
	for p in points:
		if p.has_meta("thruster_radius"):
			sized += 1
	print("GLOWSHOT   %d points, %d sized" % [points.size(), sized])
	var built := Glow.build(ship, points, color)
	var bases: Array[Transform3D] = built["bases"]
	Glow.animate(built["node"], built["material"], bases, 1.0)


func _collect(node: Node, out: Array[Node3D]) -> void:
	if Glow.is_engine_point(node):
		out.append(node as Node3D)
	for child in node.get_children():
		_collect(child, out)


func _place(world: Node3D, ship: Node3D, at: Vector3, fit: float) -> void:
	world.add_child(ship)
	ship.position = at
	# Rear three-quarter: turned so the exhausts face the camera.
	ship.rotation_degrees = Vector3(-10, 30, 0)
	var box := AABB()
	var first := true
	for mi in ship.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).visible:
			continue
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		b = ship.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform * b
		box = b if first else box.merge(b)
		first = false
	var size := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if size > 0.0:
		ship.scale = Vector3.ONE * (fit / size)
