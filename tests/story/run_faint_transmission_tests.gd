extends SceneTree

## What signal tuning overhears: an unheard story thread here first, else
## ambient chatter that does not repeat until the pool runs out.
##   Godot --headless --path . --script res://tests/story/run_faint_transmission_tests.gd --log-file <path>

const Faint := preload("res://scripts/story/activities/FaintTransmissions.gd")

var _failures: Array[String] = []


func _state() -> Dictionary:
	return {
		"arcs": {
			"arc.1": {"system_id": "sys.a", "cast": {
				"broker": {"kind": "person", "entity_id": "npc.broker", "display_name": "Vessa Orl"},
				"guild": {"kind": "faction", "entity_id": "faction.guild", "display_name": "Ore Guild"}}},
			"arc.2": {"system_id": "sys.b", "cast": {}},
		},
		"main_story": {"threads": [
			{"id": "th.0001", "arc_id": "arc.1", "surface": "scan", "detail": "Scanned only.", "seen": false},
			{"id": "th.0002", "arc_id": "arc.1", "surface": "dialogue", "detail": "{role:broker} paid the {role:guild} twice.", "seen": false},
			{"id": "th.0003", "arc_id": "arc.2", "surface": "radio", "detail": "Elsewhere.", "seen": false},
			{"id": "th.0004", "arc_id": "arc.1", "surface": "radio", "detail": "Already heard.", "seen": true},
		]},
	}


func _initialize() -> void:
	var state := _state()
	var found := Faint.pick(state, "sys.a", "Tarn", [], 3)
	_check(found["kind"] == "thread" and found["thread_id"] == "th.0002", "an unheard, hearable thread here comes first: %s" % str(found))
	_check(str(found["text"]).contains("Vessa Orl paid the Ore Guild twice"), "the thread is filled with its cast: %s" % found["text"])
	_check(found["speaker_id"] == "npc.broker", "one of the arc's people speaks it")
	_check(Faint.thread_candidates(state, "sys.a").size() == 1, "scan-only and already-heard threads are skipped")

	var elsewhere := Faint.pick(state, "sys.c", "Nowhere", [], 3)
	_check(elsewhere["kind"] == "ambient", "no thread here: ambient chatter")
	var heard: Array = []
	for i in Faint.AMBIENT.size():
		var a := Faint.pick({}, "sys.c", "Nowhere", heard, i * 7)
		_check(not heard.has(a["id"]), "ambient does not repeat before the pool runs out: %s" % a["id"])
		heard.append(a["id"])
	_check(Faint.pick({}, "sys.c", "Nowhere", heard, 1)["kind"] == "ambient", "a used-up pool starts over")
	for line: String in Faint.AMBIENT:
		_check(not line.contains("!"), "ambient lines are not shouted: %s" % line)

	if _failures.is_empty():
		print("[PASS] Faint transmissions")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
