extends SceneTree

## Asteroids of each ore type side by side (plus a tech-grade seam for
## comparison), for checking the ore tints by eye: one shot close, one from
## further out. Needs a window (not headless):
##   Godot --path . --script res://tools/asteroid_ore_snapshot.gd --log-file <path> -- --out=<dir>

const ORDER := ["silicate", "water_ice", "ferrite", "cuprite", "thorium", "tech_seam"]

var _out := "user://asteroid_ore_snapshots"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		if arg.begins_with("--alpha="):
			load("res://scripts/Asteroid.gd").ore_tint_alpha = float(arg.substr(8))
	DirAccess.make_dir_recursive_absolute(_out)
	var world := Node3D.new()
	root.add_child(world)
	await process_frame
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.02, 0.025, 0.04)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.35, 0.37, 0.42)
	env.environment.ambient_light_energy = 0.6
	env.environment.glow_enabled = true
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.6
	world.add_child(sun)

	var gs: Node = root.get_node("GlobalState")
	var saved_mix: Dictionary = gs.system_ore_mix
	var scene: PackedScene = load("res://scenes/asteroid.tscn")
	var spacing := 7.0
	for i in ORDER.size():
		var kind: String = ORDER[i]
		gs.system_ore_mix = {"silicate": 1.0} if kind == "tech_seam" else {kind: 1.0}
		var rock: Node3D = scene.instantiate()
		rock.set("persistent_id", "snapshot.asteroid.%d" % (i + 3))
		if kind == "tech_seam":
			rock.set("force_tech_seam", true)
		world.add_child(rock)
		rock.position = Vector3((i - (ORDER.size() - 1) / 2.0) * spacing, 0.0, 0.0)
		rock.set_physics_process(false)
		print("ORESHOT %s -> %s" % [kind, str(rock.get("ore_type"))])
	gs.system_ore_mix = saved_mix

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 45.0
	cam.current = true
	root.size = Vector2i(1600, 700)
	for shot in [["near", 42.0], ["far", 160.0]]:
		cam.position = Vector3(0, float(shot[1]) * 0.12, float(shot[1]))
		cam.look_at(Vector3.ZERO)
		for f in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out.path_join("asteroid_ores_%s.png" % shot[0]))
		print("ORESHOT saved %s" % shot[0])
	quit(0)
