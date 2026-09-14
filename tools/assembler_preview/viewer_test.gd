extends Control
## Harness for ModelViewer: load it fullscreen, show a ship, capture a few
## frames (auto-rotate gives angle variation), test zoom + model swap.
## Run: Godot --path . tools/assembler_preview/viewer_test.tscn -- <out_dir>

func _ready() -> void:
	var out_dir := "user://viewer_test"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(900, 900))
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var mv = load("res://scenes/ui/model_viewer.tscn").instantiate()
	add_child(mv)
	await get_tree().process_frame
	mv.show_ship("vanguard", "Gunner", 0)

	await _settle(8)
	_shot(out_dir, "1_initial")

	# Auto-rotate should change the angle.
	await _settle(40)
	_shot(out_dir, "2_rotated")

	# Zoom in.
	mv._zoom(-0.5)
	await _settle(20)
	_shot(out_dir, "3_zoomed")

	# Swap model (proves set_model reframes a new ship).
	mv.show_ship("vanguard", "MiningHauler", 2)
	await _settle(12)
	_shot(out_dir, "4_swapped")

	print("VIEWER_TEST_DONE")
	get_tree().quit()


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _shot(out_dir: String, tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, tag])
	print("SHOT ", tag)
