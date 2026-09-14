extends SceneTree

const HandoffStoreType := preload("res://scripts/persistence/KaelenHandoffStore.gd")

const TEST_ROOT := "res://.tmp_godot_user/kaelen_handoff_store_fixture"

var _failures: Array[String] = []


func _initialize() -> void:
	_cleanup()
	_test_scoped_pools_do_not_cross_story_system_or_relationship()
	_cleanup()

	if _failures.is_empty():
		print("[PASS] Kaelen handoff store tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_scoped_pools_do_not_cross_story_system_or_relationship() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_ROOT))
	var store: RefCounted = HandoffStoreType.open(TEST_ROOT)
	_expect(store.is_valid(), "Kaelen handoff store fixture did not open.")
	if not store.is_valid():
		return
	store.refill("Director Voss", ["legacy line"])
	store.refill_scoped(
		"Director Voss",
		1,
		"system.start",
		"neutral",
		["old story line"]
	)
	store.refill_scoped(
		"Director Voss",
		2,
		"system.start",
		"hostile",
		["wrong relationship line"]
	)
	store.refill_scoped(
		"Director Voss",
		2,
		"system.cinder",
		"neutral",
		["wrong system line"]
	)
	store.refill_scoped(
		"Director Voss",
		2,
		"system.start",
		"neutral",
		["current scoped line", "current scoped line 2"]
	)
	_expect(
		store.draw_scoped("Director Voss", 2, "system.start", "neutral")
			== "current scoped line",
		"Scoped draw did not use the current story/system/relationship pool."
	)
	_expect(
		store.draw_scoped("Director Voss", 1, "system.start", "neutral")
			== "old story line",
		"Story-revision scoped line was lost or overwritten."
	)
	_expect(
		store.draw_scoped("Director Voss", 2, "system.cinder", "neutral")
			== "wrong system line",
		"System-scoped line was lost or overwritten."
	)
	_expect(
		store.draw_scoped("Director Voss", 2, "system.start", "hostile")
			== "wrong relationship line",
		"Relationship-scoped line was lost or overwritten."
	)
	_expect(
		store.draw("Director Voss") == "legacy line",
		"Legacy unscoped handoff pool did not remain backward-compatible."
	)
	var reopened: RefCounted = HandoffStoreType.open(TEST_ROOT)
	_expect(
		reopened.is_valid()
			and reopened.pool_size_scoped(
				"Director Voss",
				2,
				"system.start",
				"neutral"
			) == 1,
		"Scoped handoff pool state did not persist after draw."
	)


func _cleanup() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_ROOT)
	if DirAccess.dir_exists_absolute(absolute):
		_remove_directory(absolute)


func _remove_directory(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child := "%s/%s" % [path, entry]
			if directory.current_is_dir():
				_remove_directory(child)
			else:
				DirAccess.remove_absolute(child)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
