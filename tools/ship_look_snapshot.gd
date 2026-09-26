extends SceneTree

## Renders ships side by side and saves a screenshot, for checking by eye:
## row 1 in Faction DNA looks, row 2 every base faction's kitbash style. Needs a window (not headless):
##   Godot --path . --script res://tools/ship_look_snapshot.gd --log-file <path> -- --out=<dir>

const Assembler := preload("res://scripts/generation/ShipAssembler.gd")
const DNA := preload("res://scripts/story/premise/FactionDNA.gd")

var _out := "user://ship_look_snapshots"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	# A sky gives the metal something to reflect; the background stays dark.
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
	env.environment.ambient_light_energy = 1.2
	env.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 2.2
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -140, 0)
	fill.light_energy = 0.9
	world.add_child(fill)

	# Row 1: one role in several factions' looks; the first is the plain base.
	# Row 2: the same look in each wear.
	var looks: Array = [{}]
	for id in ["faction.gen.tarn_guild", "faction.gen.kova_union", "faction.gen.rusk_combine", "faction.gen.orl_house"]:
		looks.append(DNA.ship_look(DNA.for_faction(id)))
	var spacing := 22.0
	for i in looks.size():
		var look: Dictionary = looks[i]
		var ship: Node3D = Assembler.build_catalog_ship("zenith", "Gunner", 7) if look.is_empty() \
			else Assembler.build_catalog_ship_with_look("zenith", "Gunner", 7, look)
		_place(world, ship, Vector3((i - 2) * spacing, 6.0, 0.0))
		print("SHIPLOOK row1 %d %s" % [i, str(look)])
	# Row 2: every base faction in the kitbash (what minor factions now fly).
	var factions := ["vanguard", "zenith", "aurelia", "reavers", "obsidian", "dustborn", "wraiths", "ironclad"]
	for i in factions.size():
		var ship2 := Assembler.build_catalog_ship(factions[i], "Interceptor", 3 + i)
		_place(world, ship2, Vector3((i - 3.5) * spacing * 0.7, -10.0, 0.0))

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 45.0
	cam.position = Vector3(0, 4, 95)
	cam.look_at(Vector3(0, -2, 0))
	cam.current = true
	root.size = Vector2i(1600, 900)
	for i in 15:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join("ship_looks.png"))
	print("SHIPLOOK saved")
	quit(0)


func _place(world: Node3D, ship: Node3D, at: Vector3) -> void:
	if ship == null:
		return
	world.add_child(ship)
	ship.position = at
	ship.rotation_degrees = Vector3(12, 35, 0)
	# Fit to a common size.
	var box := AABB()
	var first := true
	for mi in ship.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		b = (mi as MeshInstance3D).transform * b
		box = b if first else box.merge(b)
		first = false
	var size := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if size > 0.0:
		ship.scale = Vector3.ONE * (13.0 / size)
