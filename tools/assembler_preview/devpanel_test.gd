extends Node
## Harness: mount DevPanel, open it, switch to the Ship Viewer tab, cycle a few
## dropdown entries, screenshot each. Run:
##   Godot --path . tools/assembler_preview/devpanel_test.tscn -- <out_dir>

func _ready() -> void:
	var out_dir := "user://devpanel_test"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1100, 800))

	var panel := DevPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.visible = true

	# Find the Ship Viewer tab and select it.
	var tabs := _find_tab_container(panel)
	if tabs:
		for i in range(tabs.get_tab_count()):
			if tabs.get_tab_title(i) == "Ship Viewer":
				tabs.current_tab = i
				break
	await _settle(10)
	_shot(out_dir, "0_default")

	# Cycle a few dropdown entries (different roles).
	var dd: OptionButton = panel._sv_dropdown
	var picks := [1, 6, 12, 18]
	var n := 1
	for p in picks:
		if p < dd.item_count:
			dd.select(p)
			dd.item_selected.emit(p)
			await _settle(12)
			_shot(out_dir, "%d_pick%d" % [n, p])
			n += 1

	print("DEVPANEL_TEST_DONE")
	get_tree().quit()


func _find_tab_container(node: Node) -> TabContainer:
	if node is TabContainer:
		return node
	for c in node.get_children():
		var r := _find_tab_container(c)
		if r:
			return r
	return null


func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _shot(out_dir: String, tag: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, tag])
	print("SHOT ", tag)
