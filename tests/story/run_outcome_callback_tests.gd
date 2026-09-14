extends SceneTree

const Projector := preload("res://scripts/story/OutcomeReactionProjector.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var mission := {"runtime_id": "mission.outcome", "system_id": "system.a", "objective_type": "INVESTIGATE_SIGNAL",
		"completed_time_minutes": 10, "investigation": {"phase": "ready", "outcome_tag": "preserved"}}
	var ledger := Projector.remember_completed([], mission, 10)
	_expect(Projector.eligible_reaction(ledger, "nova", "system.a", 10, 1).get("phase") == "immediate", "Immediate reaction must be eligible after committed outcome")
	_expect(Projector.eligible_reaction(ledger, "nova", "system.b", 10, 1).is_empty(), "Wrong system must be excluded")
	_expect(Projector.eligible_reaction(ledger, "nova", "system.a", 15, 1).is_empty(), "Outcome must expire after four activity steps")
	for entry in ledger:
		if entry["speaker_id"] == "nova":
			entry["immediate_delivered"] = true
			entry["delivered_visit"] = 1
			entry["delivered_step"] = 10
	_expect(Projector.eligible_reaction(ledger, "nova", "system.a", 10, 2).is_empty(), "Later callback needs another activity step")
	_expect(Projector.eligible_reaction(ledger, "nova", "system.a", 11, 1).is_empty(), "One reference per visit")
	_expect(Projector.eligible_reaction(ledger, "nova", "system.a", 11, 2).get("phase") == "callback", "Next visit/activity permits callback")
	for entry in ledger:
		if entry["speaker_id"] == "nova":
			entry["callback_delivered"] = true
	var restored := Projector.normalize_memories(JSON.parse_string(JSON.stringify(ledger)))
	_expect(Projector.eligible_reaction(restored, "nova", "system.a", 12, 3).is_empty(), "Retired callback must stay retired after reload")

	var probe := GDScript.new()
	probe.source_code = 'extends "res://scripts/story/QuietMomentDirector.gd"\nvar requests: Array = []\nvar prompts: Array = []\nfunc _ready() -> void:\n\tpass\nfunc _outcome_model_available() -> bool:\n\treturn true\nfunc _send_outcome_request(prompt: String, callback: Callable) -> void:\n\tprompts.append(prompt)\n\trequests.append(callback)\nfunc _screen(_id: String, _built: Dictionary, _line: String) -> Array:\n\treturn []\n'
	if probe.reload() != OK:
		quit(1)
		return
	var director: Node = probe.new()
	root.add_child(director)
	var state := {"valid": true, "present": true, "deliveries": 0, "finished": []}
	var valid := func() -> bool: return state["valid"]
	var deliver := func(_line: String) -> bool:
		if state["present"]:
			state["deliveries"] += 1
		return state["present"]
	var finished := func(presented: bool) -> void: state["finished"].append(presented)
	var memory := {"speaker_id": "nova", "outcome_tag": "preserved", "phase": "callback", "secret": "PRIVATE_SENTINEL"}
	_expect(director.try_outcome(memory, "observant", valid, deliver, finished), "Outcome must enter shared quiet-moment request slot")
	_expect(not director.try_outcome(memory, "observant", valid, deliver, finished), "Only one in-flight quiet request")
	_expect(not str(director.prompts[0]).contains("PRIVATE_SENTINEL"), "Prompt must project only classified public facts")
	state["valid"] = false
	director.requests.pop_front().call({"ok": true, "inner_text": '{"line":"The site is intact, Captain."}'})
	_expect(state["deliveries"] == 0 and state["finished"] == [false], "Late response must not present stale outcome")
	state["valid"] = true
	state["finished"] = []
	director.try_outcome(memory, "observant", valid, deliver, finished)
	director.requests.pop_front().call({"ok": false})
	_expect(director.requests.size() == 1, "First rejection permits exactly one retry")
	director.requests.pop_front().call({"ok": false})
	_expect(director.requests.is_empty() and state["finished"] == [false], "Second rejection ends without generated or canned presentation")
	state["finished"] = []
	state["present"] = false
	director.try_outcome(memory, "observant", valid, deliver, finished)
	director.requests.pop_front().call({"ok": true, "inner_text": '{"line":"The site is intact, Captain."}'})
	_expect(state["deliveries"] == 0 and state["finished"] == [false], "Speech-budget suppression must not count as delivery")
	state["finished"] = []
	state["present"] = true
	director.try_outcome(memory, "observant", valid, deliver, finished)
	director.requests.pop_front().call({"ok": true, "inner_text": '{"line":"The site is intact, Captain."}'})
	_expect(state["deliveries"] == 1 and state["finished"] == [true], "Actual presentation must report consumption")
	_expect(not director.try_outcome(memory, "observant", valid, deliver, finished), "Successful delivery must spend quiet-moment cooldown")
	director.reset_for_new_campaign()
	director.try_outcome(memory, "observant", valid, deliver, finished)
	var pending: Callable = director.requests.pop_front()
	director.reset_for_new_campaign()
	pending.call({"ok": true, "inner_text": '{"line":"The site is intact, Captain."}'})
	_expect(state["deliveries"] == 1, "Old campaign response must not present after reset")
	director.free()
	_test_game_root_delivery(mission)
	for failure in failures:
		push_error("[FAIL] " + failure)
	if failures.is_empty():
		print("[PASS] Outcome callbacks: eligibility, expiry, visit limits, reload, stale responses, retries, suppressed delivery and cooldown")
	quit(0 if failures.is_empty() else 1)


func _test_game_root_delivery(mission: Dictionary) -> void:
	var story := root.get_node("StoryManager")
	var gs := root.get_node("GlobalState")
	var nova := root.get_node("Nova")
	var old_story: Dictionary = story.story_state.duplicate(true)
	var old_store = story._story_state_store
	story._story_state_store = null
	story.story_state["local_outcome_memories"] = Projector.remember_completed([], mission, 10)
	story.story_state["local_outcome_step"] = 10
	story.story_state["local_outcome_visit"] = 1
	gs.current_system_id = "system.a"
	var game_script := GDScript.new()
	game_script.source_code = 'extends "res://scripts/GameRoot.gd"\nfunc _enter_tree() -> void:\n\tpass\nfunc _ready() -> void:\n\tpass\nfunc _player_is_docked() -> bool:\n\treturn false\nfunc _outcome_reaction_window(_speaker: String) -> bool:\n\treturn true\n'
	var director_script := GDScript.new()
	director_script.source_code = 'extends Node\nvar valid: Callable\nvar deliver: Callable\nvar finished: Callable\nfunc try_outcome(_memory: Dictionary, _state: String, v: Callable, d: Callable, f: Callable) -> bool:\n\tvalid = v\n\tdeliver = d\n\tfinished = f\n\treturn true\n'
	if game_script.reload() != OK or director_script.reload() != OK:
		_expect(false, "GameRoot consumer fixture must compile")
		story.story_state = old_story
		story._story_state_store = old_store
		return
	var game: Node = game_script.new()
	var probe: Node = director_script.new()
	game.quiet_moment_director = probe
	game.call("_try_pending_outcome_reaction")
	_expect(story.outcome_reaction_candidate("nova", "system.a").is_empty(), "GameRoot must persist the attempt before another timer tick or reload")
	_expect(probe.valid.call(), "Persisting an attempt must not invalidate its response")
	nova._last_spoken_line = ""
	nova._recent_speech_ms.clear()
	var presented: bool = probe.deliver.call("The site is intact, Captain.")
	probe.finished.call(presented)
	_expect(presented, "GameRoot must route accepted text through real Nova.speak")
	var memories := Projector.normalize_memories(story.story_state["local_outcome_memories"])
	_expect(memories.any(func(entry: Dictionary) -> bool: return entry["speaker_id"] == "nova" and entry["immediate_delivered"]), "Actual Nova presentation must retire immediate reaction")
	story.advance_outcome_activity(true)
	game.call("_try_pending_outcome_reaction")
	var repeated: bool = probe.deliver.call("The site is intact, Captain.")
	probe.finished.call(repeated)
	_expect(not repeated, "Real Nova repeat guard must report no presentation")
	memories = Projector.normalize_memories(story.story_state["local_outcome_memories"])
	_expect(not memories.any(func(entry: Dictionary) -> bool: return entry["speaker_id"] == "nova" and entry["callback_delivered"]), "Suppressed real Nova line must not retire callback")
	story.advance_outcome_activity(true)
	game.call("_try_pending_outcome_reaction")
	gs.current_system_id = "system.b"
	_expect(not probe.valid.call(), "GameRoot must invalidate work on system change")
	_expect(not probe.deliver.call("A stale line."), "GameRoot must refuse late text after system change")
	probe.finished.call(false)
	game.free()
	probe.free()
	story.story_state = old_story
	story._story_state_store = old_store

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
