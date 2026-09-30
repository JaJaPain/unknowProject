extends SceneTree

## Screenshots of the combat effects (windowed):
##   Godot --path . --script res://tools/combat_fx_snapshot.gd --log-file <path> -- --out=<dir>
## Frames: an explosion at 0.1 s / 0.35 s / 1.2 s, a hull hit, a crit and a
## shield hit, each against a dark sky with a stand-in hull for scale.

var _out := "user://combat_fx"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _stage() -> Node3D:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.012, 0.02)
	e.glow_enabled = true
	e.glow_intensity = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.6, 0.7, 0)
	sun.light_energy = 0.6
	world.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 6, 30)
	world.add_child(cam)
	cam.look_at(Vector3.ZERO)
	var hull := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(5, 1.6, 8)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.32, 0.35)
	mat.metallic = 0.6
	box.material = mat
	hull.mesh = box
	hull.position = Vector3(-10, 0, 0)
	world.add_child(hull)
	return world


func _run() -> void:
	var impact = load("res://scripts/visuals/ImpactEffect.gd")
	var world := _stage()
	await _frames(10)
	impact.spawn_explosion(world, Vector3(4, 0, 0), Color(1.0, 0.6, 0.2), 1.0)
	await _wait(0.1)
	await _shot("explosion_a")
	await _wait(0.25)
	await _shot("explosion_b")
	await _wait(0.85)
	await _shot("explosion_c")
	await _wait(2.5)
	impact.spawn_hit(world, Vector3(-10, 0, 4), Color(1.0, 0.6, 0.25), 1.2)
	await _wait(0.05)
	await _shot("hit_hull")
	await _wait(0.6)
	impact.spawn_hit(world, Vector3(-10, 0, 4), Color(1.0, 0.95, 0.75), 1.8)
	await _wait(0.05)
	await _shot("hit_crit")
	await _wait(0.6)
	impact.spawn_shield_ripple(world, Vector3(-10, 0, 0), 5.5, Vector3(-10, 0, 4.5))
	await _wait(0.08)
	await _shot("hit_shield")
	print("FXSHOT done")
	quit(0)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var path := _out.path_join("%s.png" % name)
	root.get_texture().get_image().save_png(path)
	print("FXSHOT saved ", path)
