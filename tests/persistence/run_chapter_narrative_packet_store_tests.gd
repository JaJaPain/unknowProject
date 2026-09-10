extends SceneTree

var PacketStoreType: GDScript = null

const TEST_ROOT := "user://chapter_packet_store_fixture"

var _failures: Array[String] = []


func _initialize() -> void:
	PacketStoreType = load(
		"res://scripts/persistence/ChapterNarrativePacketStore.gd"
	)
	if PacketStoreType == null:
		push_error("[FAIL] ChapterNarrativePacketStore.gd did not compile.")
		quit(1)
		return
	_cleanup()
	_test_bootstrap_append_reopen_and_reject_duplicate()
	_cleanup()

	if _failures.is_empty():
		print("[PASS] Chapter narrative packet store tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_bootstrap_append_reopen_and_reject_duplicate() -> void:
	var store: RefCounted = PacketStoreType.open(TEST_ROOT)
	_expect(
		store.is_valid(),
		"Packet store did not bootstrap cleanly: %s" %
			store.validation.summary()
	)
	_expect(store.all_packets().is_empty(), "New packet store should start empty.")
	var packet := _packet("chapter_packet.1", 1)
	var appended: Dictionary = store.append_packet(packet)
	_expect(bool(appended.get("ok", false)), appended.get("error", ""))
	_expect(
		store.packet_ids() == ["chapter_packet.1"],
		"Packet append did not expose the new packet ID."
	)
	var duplicate: Dictionary = store.append_packet(packet)
	_expect(
		not bool(duplicate.get("ok", true)),
		"Packet store accepted a duplicate packet ID."
	)
	var reopened: RefCounted = PacketStoreType.open(TEST_ROOT)
	_expect(
		reopened.is_valid()
			and reopened.packet_ids() == ["chapter_packet.1"]
			and str(
				reopened.latest_packet_for_chapter(1).get("premise", "")
			) == "Packet chapter_packet.1 pressure",
		"Packet store did not persist and reopen appended packets."
	)
	var persisted_packet: Dictionary = reopened.latest_packet_for_chapter(1)
	var dossier: Dictionary = persisted_packet.get("opposing_force", {})
	_expect(
		str(dossier.get("status", "")) == "unformed"
			and dossier.get("identity", {}) is Dictionary
			and (dossier.get("identity", {}) as Dictionary).get("known", []) is Array
			and (dossier.get("identity", {}) as Dictionary).get("unknown", []) is Array
			and int(dossier.get("escalation_tier", -1)) == 0,
		"Packet store did not persist the default unformed opposing-force dossier."
	)


func _packet(packet_id: String, chapter: int) -> Dictionary:
	return {
		"packet_id": packet_id,
		"chapter": chapter,
		"premise": "Packet %s pressure" % packet_id,
		"threads": [{"thread_id": "thread.fixture"}],
		"facts": [{"fact_id": "fact.fixture.visible", "privacy": "public"}],
		"beats": [
			{
				"beat_id": "beat.fixture",
				"supported_objective_types": ["DELIVERY_COURIER"],
				"eligible_entity_ids": ["station.start.main"],
				"stake": "The fixture needs a packet.",
			},
		],
	}


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
