extends Node3D
func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(1000,800))
	# Environment + light
	var env := Environment.new(); env.background_mode=Environment.BG_COLOR
	env.background_color=Color(0.03,0.04,0.07); env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color(0.55,0.6,0.72); env.ambient_light_energy=1.0; env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	var we:=WorldEnvironment.new(); we.environment=env; add_child(we)
	var key:=DirectionalLight3D.new(); key.rotation_degrees=Vector3(-35,-40,0); key.light_energy=1.6; add_child(key)
	var ps = load("res://scenes/player_ship.tscn").instantiate()
	add_child(ps)
	for i in range(20): await get_tree().process_frame
	for i in range(6): await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/player_view.png" % out)
	print("PLAYERTEST_DONE size=", ps.get("_player_model_size"), " orbit=", ps.get("_drone_orbit_radius"))
	get_tree().quit()
