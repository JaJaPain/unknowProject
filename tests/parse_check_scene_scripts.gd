extends SceneTree
# Compile check for EVERY project script.
#
# This used to be a hand-maintained list, and the list is exactly what failed:
# PlayerShip.gd was never on it, so when a refactor left an orphaned call the
# player's own ship script stopped compiling and this check still reported
# "[PASS] ... parse_failures: 0". A green check on a game that cannot load its
# player ship is worse than no check at all.
#
# Runtime load(), not preload -- autoloads must be registered first or these
# fail spuriously (see run_story_state_bible_seed_tests harness note).

## Not our code: the godot_ai plugin updates itself and its scripts come and go.
const _SKIP_PREFIXES := ["res://addons/"]


func _initialize() -> void:
	var paths := _gather("res://scripts")
	paths.append_array(_gather("res://tests"))
	var failed: Array[String] = []
	for path in paths:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failed.append(path)
	print("[ParseCheck] %d scripts checked, %d failed." % [paths.size(), failed.size()])
	for path in failed:
		push_error("[FAIL] %s did not compile." % path)
	if not failed.is_empty():
		quit(1)
		return
	print("[PASS] Scene script parse check")
	quit(0)


func _gather(root: String) -> Array[String]:
	var out: Array[String] = []
	var dirs: Array[String] = [root]
	while not dirs.is_empty():
		var dir_path: String = dirs.pop_back()
		var skip := false
		for prefix in _SKIP_PREFIXES:
			if dir_path.begins_with(str(prefix)):
				skip = true
		if skip:
			continue
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			var full := "%s/%s" % [dir_path, name]
			if dir.current_is_dir():
				if not name.begins_with("."):
					dirs.append(full)
			elif name.ends_with(".gd"):
				out.append(full)
			name = dir.get_next()
		dir.list_dir_end()
	return out
