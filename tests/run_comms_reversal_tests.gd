extends SceneTree

const CommsReversalType := preload(
	"res://scripts/domain/capabilities/CommsReversalCapability.gd"
)
const MissionAdapterType := preload("res://scripts/domain/MissionAdapter.gd")
const MissionInstanceType := preload("res://scripts/domain/MissionInstance.gd")
const MissionCollectionType := preload("res://scripts/domain/MissionCollection.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_handle_event_counts_kills()
	_test_handle_event_triggers_comms_at_threshold()
	_test_handle_event_blocks_during_unresolved_comms()
	_test_handle_event_resumes_after_finish_kill()
	_test_handle_event_ignores_wrong_faction()
	_test_handle_event_ignores_non_ship_destroyed()
	_test_is_completed_finish_kill_path()
	_test_is_completed_branch_chosen_path()
	_test_is_completed_not_done_before_branch()
	_test_format_tracker_kills()
	_test_format_tracker_incoming()
	_test_format_tracker_branches()
	_test_on_cleanup_returns_ceasefire_hint()
	_test_normalize_legacy_state()
	_test_save_load_mid_branch_roundtrip()
	_test_fallback_template_exists()

	if _failures.is_empty():
		print("OK: All comms reversal tests passed.")
	else:
		for f in _failures:
			push_error(f)
		print("FAIL: %d comms reversal test(s) failed." % _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _make_data(overrides: Dictionary = {}) -> Dictionary:
	var base := {
		"objective_type": "TARGET_WITH_COMMS_REVERSAL",
		"target_faction": "reavers",
		"count_required": 3,
		"current_count": 0,
		"comms_triggered": false,
		"branch_chosen": false,
		"branch_id": "",
		"bribe_amount": 500,
		"comms_reversal_line": "Test comms line.",
	}
	base.merge(overrides, true)
	return base


func _test_handle_event_counts_kills() -> void:
	var cap := CommsReversalType.new()
	var data := _make_data()
	var event_data := {"faction": "reavers"}
	var result := cap.handle_event(data, "ship_destroyed", event_data)
	_expect(int(data["current_count"]) == 1, "Kill count should be 1")
	_expect(bool(result.get("progress_changed", false)), "Should signal progress")


func _test_handle_event_triggers_comms_at_threshold() -> void:
	var cap := CommsReversalType.new()
	var data := _make_data({"current_count": 1})
	var event_data := {"faction": "reavers"}
	var result := cap.handle_event(data, "ship_destroyed", event_data)
	_expect(int(data["current_count"]) == 2, "Kill count should be 2 (threshold)")
	_expect(bool(data.get("comms_triggered", false)), "comms_triggered should be true")
	_expect(bool(result.get("trigger_comms", false)), "Should trigger comms")
	_expect(str(result.get("comms_faction", "")) == "reavers", "Should report comms faction")


func _test_handle_event_blocks_during_unresolved_comms() -> void:
	var cap := CommsReversalType.new()
	var data := _make_data({"current_count": 2, "comms_triggered": true})
	var event_data := {"faction": "reavers"}
	var result := cap.handle_event(data, "ship_destroyed", event_data)
	_expect(result.is_empty(), "Should block kills during unresolved comms")
	_expect(int(data["current_count"]) == 2, "Kill count should not change")


func _test_handle_event_resumes_after_finish_kill() -> void:
	var cap := CommsReversalType.new()
	var data := _make_data({
		"current_count": 2,
		"comms_triggered": true,
		"branch_chosen": true,
		"branch_id": "finish_kill",
	})
	var event_data := {"faction": "reavers"}
	var result := cap.handle_event(data, "ship_destroyed", event_data)
	_expect(int(data["current_count"]) == 3, "Kill count should be 3 after finish_kill")
	_expect(bool(result.get("progress_changed", false)), "Should signal progress")


func _test_handle_event_ignores_wrong_faction() -> void:
	var cap := CommsReversalType.new()
	var data := _make_data()
	var result := cap.handle_event(data, "ship_destroyed", {"faction": "zenith"})
	_expect(result.is_empty(), "Should ignore wrong faction")
	_expect(int(data["current_count"]) == 0, "Kill count should not change")


func _test_handle_event_ignores_non_ship_destroyed() -> void:
	var cap := CommsReversalType.new()
	var data := _make_data()
	var result := cap.handle_event(data, "ore_delivered", {"faction": "reavers"})
	_expect(result.is_empty(), "Should ignore non-ship_destroyed events")


func _test_is_completed_finish_kill_path() -> void:
	var cap := CommsReversalType.new()
	var data := _make_data({
		"current_count": 3,
		"count_required": 3,
		"comms_triggered": true,
		"branch_chosen": true,
		"branch_id": "finish_kill",
	})
	_expect(cap.is_completed(data), "Should be completed when kills meet count after finish_kill")


func _test_is_completed_branch_chosen_path() -> void:
	var cap := CommsReversalType.new()
	for branch_id in ["accept_bribe", "walk_away"]:
		var data := _make_data({
			"comms_triggered": true,
			"branch_chosen": true,
			"branch_id": branch_id,
		})
		_expect(cap.is_completed(data), "Should be completed for branch: %s" % branch_id)


func _test_is_completed_not_done_before_branch() -> void:
	var cap := CommsReversalType.new()
	var data := _make_data({"current_count": 2, "comms_triggered": true})
	_expect(not cap.is_completed(data), "Should not be completed before branch is chosen")


func _test_format_tracker_kills() -> void:
	var cap := CommsReversalType.new()
	var data := _make_data({"current_count": 1})
	var text := cap.format_tracker_text(data)
	_expect(text.contains("1"), "Should show current count")
	_expect(text.contains("3"), "Should show required count")


func _test_format_tracker_incoming() -> void:
	var cap := CommsReversalType.new()
	var data := _make_data({"comms_triggered": true})
	var text := cap.format_tracker_text(data)
	_expect(text.contains("INCOMING"), "Should show incoming transmission")


func _test_format_tracker_branches() -> void:
	var cap := CommsReversalType.new()
	var branches := {
		"finish_kill": "eliminated",
		"accept_bribe": "accepted",
		"walk_away": "Walked away",
	}
	for branch_id in branches:
		var data := _make_data({
			"branch_chosen": true,
			"branch_id": branch_id,
		})
		var text := cap.format_tracker_text(data)
		_expect(
			text.to_lower().contains(str(branches[branch_id]).to_lower()),
			"Branch %s tracker should contain '%s', got: %s" % [branch_id, branches[branch_id], text]
		)


func _test_on_cleanup_returns_ceasefire_hint() -> void:
	var cap := CommsReversalType.new()
	var data := _make_data()
	var hints := cap.on_cleanup(data)
	_expect(
		str(hints.get("clear_ceasefire_faction", "")) == "reavers",
		"Cleanup should return ceasefire faction"
	)


func _test_normalize_legacy_state() -> void:
	var raw := {
		"objective_type": "TARGET_WITH_COMMS_REVERSAL",
		"target_faction": "reavers",
		"count_required": "3",
		"current_count": "1",
		"comms_triggered": 1,
		"branch_chosen": 0,
		"branch_id": "",
		"bribe_amount": "500",
		"comms_reversal_line": "test",
		"title": "Kill Them",
		"faction": "neutral",
		"accepted": true,
	}
	var normalized := MissionAdapterType.normalize_legacy_state(raw)
	_expect(int(normalized["current_count"]) == 1, "current_count should normalize to int")
	_expect(int(normalized["count_required"]) == 3, "count_required should normalize to int")
	_expect(bool(normalized["comms_triggered"]) == true, "comms_triggered should normalize to bool")
	_expect(bool(normalized["branch_chosen"]) == false, "branch_chosen should normalize to bool")
	_expect(int(normalized["bribe_amount"]) == 500, "bribe_amount should normalize to int")


func _test_save_load_mid_branch_roundtrip() -> void:
	var data := _make_data({
		"current_count": 2,
		"comms_triggered": true,
		"title": "Kill Contract",
		"faction": "neutral",
		"accepted": true,
		"public_board": true,
		"public_board_template_id": "TARGET_WITH_COMMS_REVERSAL",
		"runtime_id": "test-comms-1",
	})
	var instance = MissionInstanceType.create_active(data)
	var serialized := instance.to_dict()
	var restored = MissionInstanceType.from_dict(serialized)
	_expect(int(restored.data["current_count"]) == 2, "Roundtrip should preserve current_count")
	_expect(bool(restored.data["comms_triggered"]) == true, "Roundtrip should preserve comms_triggered")
	_expect(bool(restored.data["branch_chosen"]) == false, "Roundtrip should preserve branch_chosen")
	_expect(str(restored.data["branch_id"]) == "", "Roundtrip should preserve branch_id")
	_expect(int(restored.data["bribe_amount"]) == 500, "Roundtrip should preserve bribe_amount")
	_expect(
		restored.source_lane == MissionInstanceType.SourceLane.BOARD,
		"Roundtrip should detect BOARD lane"
	)

	var coll := MissionCollectionType.new()
	coll.add(instance)
	var arr := coll.to_array()
	_expect(arr.size() == 1, "Collection should have 1 mission")
	var coll2 := MissionCollectionType.from_array(arr)
	var restored2 = coll2.get_by_id("test-comms-1")
	_expect(restored2 != null, "Collection roundtrip should find mission by ID")
	_expect(
		bool(restored2.data["comms_triggered"]) == true,
		"Collection roundtrip should preserve comms_triggered"
	)


func _test_fallback_template_exists() -> void:
	var MissionTemplateRegistryType := preload(
		"res://scripts/domain/MissionTemplateRegistry.gd"
	)
	var t = MissionTemplateRegistryType.get_template("TARGET_WITH_COMMS_REVERSAL")
	_expect(t != null, "Registry should have TARGET_WITH_COMMS_REVERSAL template")
	_expect(t.objective_type == "TARGET_WITH_COMMS_REVERSAL", "Template objective type should match")
	_expect(t.fallback_variants.size() > 0, "Template should have at least one fallback variant")
	var fb: Dictionary = t.fallback_variants[0]
	_expect(fb.has("title"), "Fallback should have title")
	_expect(fb.has("poster"), "Fallback should have poster")
	_expect(fb.has("body"), "Fallback should have body")
