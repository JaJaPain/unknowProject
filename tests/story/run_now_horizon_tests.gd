extends SceneTree

## Core loop step 13 (plan 4.4): with no job for a while, N.O.V.A. points at
## one thing worth doing. Timing, priority, no repeats, and the lines stay
## clear of the canon.
##   Godot --headless --path . --script res://tests/story/run_now_horizon_tests.gd --log-file <path>

const Now := preload("res://scripts/story/NowHorizon.gd")
const ReservedTopics := preload("res://scripts/story/ReservedTopics.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var s := Now.fresh_state()
	var idle := {"flying": true, "has_job": false, "quiet": true}
	_check(Now.step(s, idle, 100.0).is_empty(), "not straight away")
	_check(not Now.step(s, idle, 60.0).is_empty(), "after a couple of minutes without a job: a line")
	_check(Now.step(s, idle, 300.0).is_empty(), "then a long cooldown")

	s = Now.fresh_state()
	_check(Now.step(s, {"flying": true, "has_job": true}, 400.0).is_empty(), "never with a job")
	_check(Now.step(s, {"flying": false}, 400.0).is_empty(), "never docked or in combat")
	Now.step(s, idle, 100.0)
	Now.step(s, {"flying": false}, 1.0)
	_check(Now.step(s, idle, 100.0).is_empty(), "docking starts the count again")
	_check(Now.step(s, {"flying": true, "has_job": false, "quiet": false}, 100.0).is_empty(), "never on top of an undercurrent nudge")
	_check(not Now.step(s, idle, 1.0).is_empty(), "and says it once the moment's clear")

	# Priority, and never the same reason twice running.
	var all := {"goal_ready": true, "bearing_here": true, "pinned_loose_end": true}
	_check(Now.reason_for(all, "") == "goal_ready", "a paid-for upgrade comes first")
	_check(Now.reason_for(all, "goal_ready") == "bearing", "then a bearing waiting here")
	_check(Now.reason_for({"pinned_loose_end": true}, "") == "loose_end", "a pinned loose end")
	_check(Now.reason_for({}, "") == "board" and Now.reason_for({}, "board") == "board", "otherwise the board (always)")
	s = Now.fresh_state()
	var ctx := {"flying": true, "has_job": false, "quiet": true, "goal_ready": true}
	var first := Now.step(s, ctx, 200.0)
	var second := Now.step(s, ctx, 700.0)
	_check(first in Now.POOLS["goal_ready"] and second in Now.POOLS["board"], "the same reason isn't nagged twice running")

	# Every line once before repeats; all clean.
	var seen := {}
	var rot := Now.fresh_state()
	for i in Now.POOLS["board"].size():
		seen[Now.next_line(rot, "board")] = true
	_check(seen.size() == Now.POOLS["board"].size(), "every board line before a repeat")
	for pool in Now.POOLS:
		for line in Now.POOLS[pool]:
			_check(ReservedTopics.is_clean(str(line)), "clean: %s" % line)
			_check(not str(line).to_lower().contains("deeper") and not str(line).to_lower().contains("further out"), "not an undercurrent nudge: %s" % line)
	_check(FileAccess.get_file_as_string("res://scripts/GameRoot.gd").contains("NowHorizon.gd"), "the game runs it")
	if _failures.is_empty():
		print("[PASS] Now horizon")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
