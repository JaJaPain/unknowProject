extends SceneTree

const StoryStateStoreType := preload(
	"res://scripts/persistence/StoryStateStore.gd"
)

const TEST_ROOT := "user://story_state_migration_fixture"

var _failures: Array[String] = []


func _initialize() -> void:
	_cleanup()
	_test_version_1_state_migrates_to_current_shape()
	_test_new_story_state_fields_validate_type_and_range()
	_cleanup()

	if _failures.is_empty():
		print("[PASS] Story state migration tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_version_1_state_migrates_to_current_shape() -> void:
	_write_legacy_story_state()
	var store = StoryStateStoreType.open(TEST_ROOT)
	_expect(
		store.is_valid(),
		"Legacy story state did not migrate cleanly: %s" %
			store.validation.summary()
	)
	if not store.is_valid():
		return
	_expect(
		int(store.data.get("schema_version", 0)) == StoryStateStoreType.DOCUMENT_VERSION,
		"Story state migration did not bump the schema version."
	)
	_expect(
		(store.data.get("player_knows", []) as Array).has("Kaelen has a buyer."),
		"Story state migration lost existing player_knows entries."
	)
	var fact_id := StoryStateStoreType.legacy_player_knows_fact_id(
		"Kaelen has a buyer."
	)
	var knowledge_states: Dictionary = store.data.get("knowledge_states", {})
	var fact_record: Dictionary = knowledge_states.get(fact_id, {})
	_expect(
		fact_record.get("state", "") == "known"
			and fact_record.get("source", "") == "legacy_player_knows"
			and fact_record.get("legacy_text", "") == "Kaelen has a buyer.",
		"Story state migration did not create the expected legacy fact record."
	)
	_expect(
		store.prompt_context().contains("Kaelen has a buyer."),
		"Story state prompt projection no longer exposes readable legacy knowledge."
	)
	_expect(
		int(store.data.get("story_revision", -1)) == 0
			and int(store.data.get("knowledge_revision", -1)) == 0
			and int(store.data.get("mission_history_revision", -1)) == 0,
		"Story state migration did not backfill revision counters."
	)
	_expect(
		store.data.get("knowledge_states", null) is Dictionary
			and store.data.get("beat_states", null) is Dictionary,
		"Story state migration did not backfill knowledge/beat state dictionaries."
	)

	var persisted := FileAccess.open(TEST_ROOT + "/story_state.json", FileAccess.READ)
	_expect(persisted != null, "Migrated story_state.json was not persisted.")
	if persisted:
		var parsed: Variant = JSON.parse_string(persisted.get_as_text())
		persisted.close()
		_expect(
			parsed is Dictionary
				and int((parsed as Dictionary).get("schema_version", 0))
					== StoryStateStoreType.DOCUMENT_VERSION,
			"Migrated story_state.json on disk did not have the current version."
		)


func _test_new_story_state_fields_validate_type_and_range() -> void:
	var invalid_revision := StoryStateStoreType._default_state()
	invalid_revision["story_revision"] = "one"
	_expect(
		not StoryStateStoreType._validate_data(invalid_revision).is_valid(),
		"Story state validation accepted a non-numeric story_revision."
	)
	var negative_revision := StoryStateStoreType._default_state()
	negative_revision["knowledge_revision"] = -1
	_expect(
		not StoryStateStoreType._validate_data(negative_revision).is_valid(),
		"Story state validation accepted a negative knowledge_revision."
	)
	var invalid_dictionary := StoryStateStoreType._default_state()
	invalid_dictionary["knowledge_states"] = []
	_expect(
		not StoryStateStoreType._validate_data(invalid_dictionary).is_valid(),
		"Story state validation accepted a non-dictionary knowledge_states field."
	)


func _write_legacy_story_state() -> void:
	var user_dir := DirAccess.open("user://")
	if user_dir == null:
		_expect(false, "Could not open user:// for story-state migration fixture.")
		return
	var mkdir_error := user_dir.make_dir_recursive("story_state_migration_fixture")
	if mkdir_error != OK:
		_expect(false, "Could not create story-state migration fixture directory.")
		return
	var legacy := {
		"schema_version": 1,
		"document_type": "story_state",
		"chapter": 2,
		"active_tensions": ["Missing freight"],
		"player_knows": ["Kaelen has a buyer."],
		"player_does_not_know_yet": ["The buyer is lying."],
		"pending_hooks": ["A quiet job went loud."],
	}
	var file := FileAccess.open(TEST_ROOT + "/story_state.json", FileAccess.WRITE)
	if file == null:
		_expect(false, "Could not write legacy story_state.json fixture.")
		return
	file.store_string(JSON.stringify(legacy, "\t"))
	file.close()


func _cleanup() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(TEST_ROOT)):
		_remove_tree(TEST_ROOT)


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var child := "%s/%s" % [path, name]
		if dir.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
