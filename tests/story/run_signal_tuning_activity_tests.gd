extends SceneTree

## Signal tuning in the game: the panel locks when the dials follow the
## source, an overheard thread lands on the Loose ends board, ambient chatter
## pays and is not offered again, a failure hears nothing, and storms and
## nebulae make it harder.
##   Godot --headless --path . --script res://tests/story/run_signal_tuning_activity_tests.gd --log-file <path> -- --baseline-offline

const ActivityType := preload("res://scripts/story/activities/SignalTuningActivity.gd")
const PanelType := preload("res://scripts/ui/SignalTuningPanel.gd")
const DirectorType := preload("res://scripts/story/premise/PremiseDirector.gd")
const Quirks := preload("res://scripts/story/quirks/SystemQuirkEffects.gd")

var _failures: Array[String] = []
var _panel_result: Array = []


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GlobalState")

	# The panel: dials held on the source lock it, once.
	var panel = PanelType.new()
	root.add_child(panel)
	panel.finished.connect(func(o: String, c: float) -> void: _panel_result.append([o, c]))
	panel.begin(21, 1.0)
	for i in range(80):
		panel._freq.value = float(panel.state["target_freq"])
		panel._phase.value = float(panel.state["target_phase"])
		panel._process(0.1)
		if not _panel_result.is_empty():
			break
	_check(_panel_result.size() == 1 and _panel_result[0][0] == "clean" and float(_panel_result[0][1]) == 1.0, "following the source locks clean: %s" % str(_panel_result))

	# The director hears it.
	var director = DirectorType.new()
	root.add_child(director)
	director.state["arcs"] = {"arc.1": {"system_id": "sys.a", "cast": {"broker": {"kind": "person", "entity_id": "npc.broker", "display_name": "Vessa Orl"}}}}
	director.state["main_story"] = {"stage": "gathering", "threads": [
		{"id": "th.0001", "arc_id": "arc.1", "surface": "dialogue", "detail": "{role:broker} paid twice.", "seen": false, "pinned": false, "trace": true}]}
	var activity = ActivityType.new()
	activity.director = director
	root.add_child(activity)
	activity.set_process(false)
	var item: Dictionary = director.faint_transmission({"system_id": "sys.a"}, 1)
	_check(item.get("kind", "") == "thread", "the director offers the thread here")
	activity.offer(item)
	_check(activity.has_offer(), "offered")
	activity._on_finished("failed", 0.0)
	_check(director.main_story_threads().is_empty(), "a failed attempt hears nothing")
	activity.offer(item)
	activity._on_finished("partial", 0.6)
	var threads: Array = director.main_story_threads()
	_check(threads.size() == 1 and str(threads[0]["text"]).contains("Vessa Orl"), "an overheard thread is on the Loose ends board: %s" % str(threads))
	_check(not activity.has_offer(), "one transmission, one attempt")

	var ambient: Dictionary = director.faint_transmission({"system_id": "sys.z"}, 2)
	var credits_before: int = gs.player_credits
	activity.offer(ambient)
	activity._on_finished("clean", 1.0)
	_check(gs.player_credits == credits_before + 60, "a clean ambient intercept sells for 60")
	_check((director.state.get("heard_intercepts", []) as Array).has(ambient["id"]), "ambient chatter is marked heard")
	_check(director.faint_transmission({"system_id": "sys.z"}, 2)["id"] != ambient["id"], "and not offered again")
	var saved: Dictionary = director.to_dict()
	var reloaded = DirectorType.new()
	reloaded.load_from_dict(saved)
	_check((reloaded.state.get("heard_intercepts", []) as Array).has(ambient["id"]), "heard intercepts survive a save")

	# Harder in a nebula; much harder under an active ion storm.
	var nebula := Quirks.environment_at(Quirks.effects_for(["nebula"]), 0.0)
	_check(float(nebula["signal_interference"]) == 1.5, "a nebula muddies the signal")
	var storm_fx := Quirks.effects_for(["ion_storm"])
	var hazard: Dictionary = storm_fx["hazards"][0]
	var in_storm := Quirks.environment_at(storm_fx, float(hazard["period_s"]) - 1.0)
	_check(float(in_storm["signal_interference"]) == 3.0, "an ion storm overhead wrecks it: %s" % str(in_storm))
	_check(float(Quirks.environment_at(storm_fx, 1.0)["signal_interference"]) == 1.0, "calm between storms")

	activity.free()
	director.free()
	reloaded.free()
	if _failures.is_empty():
		print("[PASS] Signal tuning activity")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
