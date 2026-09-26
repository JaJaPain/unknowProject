extends SceneTree

## The inventory screen with a sample loadout, for checking it by eye.
## Needs a window (not headless):
##   Godot --path . --script res://tools/inventory_snapshot.gd --log-file <path> -- --out=<dir> [--tab=all]

var _out := "user://inventory_snapshots"
var _tab := "all"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		if arg.begins_with("--tab="):
			_tab = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	await process_frame
	var gs: Node = root.get_node("GlobalState")
	gs.inventory.clear()
	for pair in [["repair_kit", 3], ["shield_cell", 2], ["survey_drone", 1], ["salvage_drone", 1], ["kinetic_ammo", 24],
			["thermal_lattice", 2], ["cryo_ferrite", 1], ["fuel_booster", 6], ["data_chip", 1], ["pet_rock", 1]]:
		gs.inventory.add(str(pair[0]), int(pair[1]), -1, "system.test")
	gs.player_credits = 12840
	gs.player_storage_ore = 340.0
	gs.clear_cargo()
	gs.add_ore(22.0)
	gs.add_ore(14.0, "water_ice")
	gs.add_ore(9.0, "cuprite")
	gs.fuel = 64.0

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var screen: Panel = load("res://scripts/ui/InventoryScreen.gd").new()
	screen.anchor_left = 0.12
	screen.anchor_right = 0.88
	screen.anchor_top = 0.08
	screen.anchor_bottom = 0.92
	root.add_child(screen)
	root.size = Vector2i(1600, 900)
	await process_frame
	screen.set_tab(_tab)
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join("inventory_%s.png" % _tab))
	print("INVSHOT saved %s" % _tab)
	quit(0)
