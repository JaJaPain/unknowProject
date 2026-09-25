extends SceneTree

## Renders the drone maze view (asteroid and wreck) from a few spots and saves
## screenshots, for checking the look without playing. Needs a window (not
## headless):
##   Godot --path . --script res://tools/maze_snapshot.gd --log-file <path> -- --out=<dir>

const ViewType := preload("res://scripts/ui/DroneMazeView.gd")
const Maze := preload("res://scripts/story/activities/DroneMazeModel.gd")

var _out := "user://maze_snapshots"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	await _shoot("asteroid", 1234, false)
	await _shoot("wreck", 5, true)
	paused = false
	print("[MazeSnapshot] saved to %s" % _out)
	quit(0)


func _shoot(kind: String, seed_value: int, recorder: bool) -> void:
	var view = ViewType.new()
	root.add_child(view)
	view.begin(seed_value, kind, recorder)
	view.set_process(false)
	view.finish_loading()
	view._update_hud()
	await _frames(20)
	await _save("%s_1_start" % kind)
	# Halfway down a crack, looking along it.
	var route: Array = Maze.route_to(view.state, Maze.target_at(view.state["targets"][0]))
	if route.size() >= 3:
		var p1: Vector2 = route[1]
		var p2: Vector2 = route[2]
		var mid := p1.lerp(p2, 0.3)
		view.state["pos"] = [mid.x, mid.y]
		view.state["heading"] = (p2 - p1).angle()
		view._sync_camera()
		await _frames(5)
		await _save("%s_1b_along" % kind)
	# Look straight at the first target from a tile away.
	var t: Dictionary = view.state["targets"][0]
	var at := Vector2(float(t["tile"][0]) + 0.5, float(t["tile"][1]) + 0.5)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var from: Vector2 = at + d * 1.0
		if Maze.is_open(view.state["grid"], int(floor(from.x)), int(floor(from.y))):
			view.state["pos"] = [from.x, from.y]
			view.state["heading"] = (at - from).angle()
			break
	view._sync_camera()
	view._update_hud()
	await _frames(10)
	await _save("%s_2_target" % kind)
	# A knock: the red flash and shake.
	view._flash.color.a = 0.35
	view._shake = 0.25
	view._sync_camera()
	await _frames(2)
	await _save("%s_3_knock" % kind)
	view.queue_free()
	paused = false
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))
