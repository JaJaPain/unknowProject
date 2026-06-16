extends SceneTree

const MI := preload("res://scripts/domain/MissionInstance.gd")
const MC := preload("res://scripts/domain/MissionCollection.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_add_and_get_focused()
	_test_add_respects_lane_limit()
	_test_three_lanes_coexist()
	_test_remove_shifts_focus()
	_test_get_by_id()
	_test_get_by_lane()
	_test_is_lane_occupied()
	_test_focus_switches()
	_test_get_all_active()
	_test_clear()
	_test_to_array_and_from_array()
	_test_from_array_restores_focus()
	_test_legacy_single_dict_compat()
	_test_station_lane_detection()

	if _failures.is_empty():
		print("[PASS] Mission collection tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _make_mission(lane: MI.SourceLane, id_suffix: String) -> MI:
	var data := _sample_state(id_suffix)
	match lane:
		MI.SourceLane.BOARD:
			data["public_board"] = true
		MI.SourceLane.STATION:
			data["station_errand"] = true
	var inst = MI.create_active(data)
	return inst


func _sample_state(id_suffix: String = "abc") -> Dictionary:
	return {
		"runtime_id": "mission.runtime.test_%s" % id_suffix,
		"definition_id": "def_%s" % id_suffix,
		"title": "Test Mission %s" % id_suffix,
		"objective_type": "KILL_SHIPS",
		"faction": "zenith",
		"agent_name": "Test Agent",
		"dialogue": "Test dialogue",
		"choice_text_selected": "Go",
		"target_faction": "aurelia",
		"current_count": 0,
		"count_required": 3,
		"reward_credits": 100,
		"reward_credits_multiplier": 1.0,
		"combat_multiplier": 1.0,
		"system_id": "start_system",
		"is_timed": false,
		"is_urgent": false,
		"urgent_reward_multiplier": 1.0,
		"public_board": false,
		"public_board_template_id": "",
		"public_board_turn_in_line": "",
		"public_board_text_is_fallback": false,
		"station_errand": false,
	}


# --- Tests ---

func _test_add_and_get_focused() -> void:
	var col := MC.new()
	var m := _make_mission(MI.SourceLane.AGENT, "a1")
	_expect(col.add(m), "add should succeed")
	_expect(col.size() == 1, "size should be 1")
	var f = col.get_focused()
	_expect(f != null, "focused should not be null")
	_expect(f.runtime_id == m.runtime_id, "focused should be the added mission")


func _test_add_respects_lane_limit() -> void:
	var col := MC.new()
	var m1 := _make_mission(MI.SourceLane.AGENT, "a1")
	var m2 := _make_mission(MI.SourceLane.AGENT, "a2")
	_expect(col.add(m1), "first AGENT should succeed")
	_expect(not col.add(m2), "second AGENT should fail")
	_expect(col.size() == 1, "size should still be 1")


func _test_three_lanes_coexist() -> void:
	var col := MC.new()
	var agent := _make_mission(MI.SourceLane.AGENT, "ag")
	var board := _make_mission(MI.SourceLane.BOARD, "bd")
	var station := _make_mission(MI.SourceLane.STATION, "st")
	_expect(col.add(agent), "AGENT add should succeed")
	_expect(col.add(board), "BOARD add should succeed")
	_expect(col.add(station), "STATION add should succeed")
	_expect(col.size() == 3, "size should be 3")
	_expect(col.has_any_active(), "should have active missions")


func _test_remove_shifts_focus() -> void:
	var col := MC.new()
	var m1 := _make_mission(MI.SourceLane.AGENT, "a1")
	var m2 := _make_mission(MI.SourceLane.BOARD, "b1")
	col.add(m1)
	col.add(m2)
	col.focus(m1.runtime_id)
	col.remove(m1.runtime_id)
	var f = col.get_focused()
	_expect(f != null, "focus should shift after remove")
	_expect(f.runtime_id == m2.runtime_id, "focus should shift to remaining")


func _test_get_by_id() -> void:
	var col := MC.new()
	var m := _make_mission(MI.SourceLane.AGENT, "x1")
	col.add(m)
	_expect(col.get_by_id(m.runtime_id) != null, "get_by_id should find it")
	_expect(col.get_by_id("nonexistent") == null, "get_by_id should return null for unknown")


func _test_get_by_lane() -> void:
	var col := MC.new()
	var agent := _make_mission(MI.SourceLane.AGENT, "ag")
	var board := _make_mission(MI.SourceLane.BOARD, "bd")
	col.add(agent)
	col.add(board)
	var found = col.get_by_lane(MI.SourceLane.AGENT)
	_expect(found != null, "get_by_lane AGENT should work")
	_expect(found.runtime_id == agent.runtime_id, "wrong mission for AGENT lane")
	_expect(col.get_by_lane(MI.SourceLane.STATION) == null, "STATION should be empty")


func _test_is_lane_occupied() -> void:
	var col := MC.new()
	col.add(_make_mission(MI.SourceLane.BOARD, "b1"))
	_expect(col.is_lane_occupied(MI.SourceLane.BOARD), "BOARD should be occupied")
	_expect(not col.is_lane_occupied(MI.SourceLane.AGENT), "AGENT should be free")
	_expect(not col.is_lane_occupied(MI.SourceLane.STATION), "STATION should be free")


func _test_focus_switches() -> void:
	var col := MC.new()
	var m1 := _make_mission(MI.SourceLane.AGENT, "a1")
	var m2 := _make_mission(MI.SourceLane.BOARD, "b1")
	col.add(m1)
	col.add(m2)
	col.focus(m2.runtime_id)
	var f = col.get_focused()
	_expect(f.runtime_id == m2.runtime_id, "focus should switch to m2")
	_expect(not col.focus("nonexistent"), "focus on nonexistent should fail")


func _test_get_all_active() -> void:
	var col := MC.new()
	var m1 := _make_mission(MI.SourceLane.AGENT, "a1")
	var m2 := _make_mission(MI.SourceLane.BOARD, "b1")
	col.add(m1)
	col.add(m2)
	_expect(col.get_all_active().size() == 2, "should have 2 active")
	m1.transition_to(MI.State.ABANDONED)
	_expect(col.get_all_active().size() == 1, "should have 1 active after abandon")


func _test_clear() -> void:
	var col := MC.new()
	col.add(_make_mission(MI.SourceLane.AGENT, "a1"))
	col.clear()
	_expect(col.is_empty(), "should be empty after clear")
	_expect(col.get_focused() == null, "focused should be null after clear")


func _test_to_array_and_from_array() -> void:
	var col := MC.new()
	var m1 := _make_mission(MI.SourceLane.AGENT, "a1")
	var m2 := _make_mission(MI.SourceLane.BOARD, "b1")
	col.add(m1)
	col.add(m2)
	col.focus(m2.runtime_id)
	var arr := col.to_array()
	_expect(arr.size() == 2, "to_array should have 2 items")

	var restored := MC.from_array(arr)
	_expect(restored.size() == 2, "restored should have 2 items")
	var rf = restored.get_focused()
	_expect(rf != null, "restored focused should not be null")
	_expect(rf.runtime_id == m2.runtime_id, "restored focus should be m2")


func _test_from_array_restores_focus() -> void:
	var col := MC.new()
	var m1 := _make_mission(MI.SourceLane.AGENT, "a1")
	var m2 := _make_mission(MI.SourceLane.STATION, "s1")
	col.add(m1)
	col.add(m2)
	col.focus(m2.runtime_id)
	var arr := col.to_array()
	var restored := MC.from_array(arr)
	var rf = restored.get_focused()
	_expect(rf.runtime_id == m2.runtime_id, "focus should restore to m2")


func _test_legacy_single_dict_compat() -> void:
	var data := _sample_state("legacy")
	var arr := [data]
	var col := MC.from_array(arr)
	_expect(col.size() == 1, "legacy single item should restore")
	var f = col.get_focused()
	_expect(f != null, "focused should not be null")
	_expect(f.source_lane == MI.SourceLane.AGENT, "legacy should be AGENT lane")


func _test_station_lane_detection() -> void:
	var data := _sample_state("station")
	data["station_errand"] = true
	var inst = MI.create_active(data)
	_expect(inst.source_lane == MI.SourceLane.STATION, "station_errand should set STATION lane")

	var data2 := _sample_state("board")
	data2["public_board"] = true
	var inst2 = MI.create_active(data2)
	_expect(inst2.source_lane == MI.SourceLane.BOARD, "public_board should set BOARD lane")

	var data3 := _sample_state("agent")
	var inst3 = MI.create_active(data3)
	_expect(inst3.source_lane == MI.SourceLane.AGENT, "default should be AGENT lane")
