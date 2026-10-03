extends SceneTree

## Core loop step 11b: N.O.V.A. and Kaelen nudge the captain deeper, lightly,
## with the lines and timings Abe approved. Every trigger fires when it should,
## respects its cooldown and the once-per-visit rule, and two nudges never land
## on the same moment.
##   Godot --headless --path . --script res://tests/story/run_undercurrent_nudge_tests.gd --log-file <path>

const Nudge := preload("res://scripts/story/UndercurrentNudge.gd")
const ReservedTopics := preload("res://scripts/story/ReservedTopics.gd")

var _failures: Array[String] = []


func _ctx(system_id: String, depth: int, flying := true, docked := false, next_class := 3, upgrades := "[1]") -> Dictionary:
	return {"system_id": system_id, "depth": depth, "flying": flying, "docked": docked, "next_class": next_class, "upgrades": upgrades}


## Runs `seconds` of one-second ticks; returns everything said.
func _run(s: Dictionary, ctx: Dictionary, seconds: int) -> Array:
	var said: Array = []
	for i in seconds:
		said.append_array(Nudge.step(s, ctx, 1.0))
	return said


func _who(said: Array) -> Array:
	return said.map(func(n): return str(n["who"]) + ":" + _pool_of(str(n["line"])))


func _pool_of(line: String) -> String:
	for pool in Nudge.POOLS:
		if line in Nudge.POOLS[pool]:
			return pool
	return "?"


func _initialize() -> void:
	# --- New deepest system: a line at most every 2 new depths -------------------
	var s := Nudge.fresh_state()
	_check(_run(s, _ctx("a", 1), 1).is_empty(), "the first system sets the baseline, no line")
	_check(_run(s, _ctx("b", 2), 70).is_empty(), "one deeper: nothing yet")
	var deeper := _run(s, _ctx("c", 3), 1)
	_check(_who(deeper) == ["nova:nova_new_deepest"], "two deeper: N.O.V.A. notices (%s)" % str(_who(deeper)))
	_check(_run(s, _ctx("d", 4), 70).is_empty(), "and not again until two more")

	# --- Lingering shallow: N.O.V.A. after 10 minutes, once per visit, 30 min cooldown
	s = Nudge.fresh_state()
	_run(s, _ctx("deep", 4), 1)
	var shallow := _run(s, _ctx("near", 2), 599)
	_check(not _who(shallow).has("nova:nova_linger"), "not before ten minutes")
	shallow = _run(s, _ctx("near", 2), 2)
	_check(_who(shallow) == ["nova:nova_linger"], "ten minutes shallow: N.O.V.A. gets restless (%s)" % str(_who(shallow)))
	_check(not _who(_run(s, _ctx("near", 2), 3000)).has("nova:nova_linger"), "once per visit")

	# --- Kaelen in the shallows: 2+ jumps shallower, 15 minutes, comms ------------
	s = Nudge.fresh_state()
	_run(s, _ctx("deep", 5), 1)
	var heard := _who(_run(s, _ctx("home", 2), 901))
	_check(heard.has("nova:nova_linger") and heard.has("kaelen:kaelen_shallow"), "both, three jumps back: %s" % str(heard))
	# Never on the same moment.
	var times: Array = []
	s = Nudge.fresh_state()
	_run(s, _ctx("deep", 5), 1)
	for t in 1000:
		for n in Nudge.step(s, _ctx("home", 2), 1.0):
			times.append(t)
	_check(times.size() == 2 and absi(int(times[1]) - int(times[0])) >= int(Nudge.SAME_MOMENT_GAP_S), "at least a minute apart (%s)" % str(times))
	s = Nudge.fresh_state()
	_run(s, _ctx("deep", 3), 1)
	_check(not _who(_run(s, _ctx("near", 2), 1000)).has("kaelen:kaelen_shallow"), "one jump back isn't 'the shallows' for her")

	# --- A gate class opens: from Class III on ------------------------------------
	s = Nudge.fresh_state()
	_run(s, _ctx("x", 3, true, false, 2), 70)
	_check(_run(s, _ctx("x", 3, true, false, 3), 1).is_empty(), "Class II opening is the guided rung: her own line covers it")
	_run(s, _ctx("x", 3, true, false, 3), 70)
	_check(_who(_run(s, _ctx("x", 3, true, false, 4), 1)) == ["nova:nova_class_open"], "Class III opens: a little relief")

	# --- After an upgrade: Kaelen on the next undock, 45 min cooldown -------------
	s = Nudge.fresh_state()
	_run(s, _ctx("x", 3, false, true, 3, "[1]"), 2)
	_run(s, _ctx("x", 3, false, true, 3, "[2]"), 2)
	_check(_who(_run(s, _ctx("x", 3, true, false, 3, "[2]"), 1)) == ["kaelen:kaelen_after_upgrade"], "fitted, then undocked: 'Good. Now go.'")
	_run(s, _ctx("x", 3, false, true, 3, "[3]"), 2)
	_check(_run(s, _ctx("x", 3, true, false, 3, "[3]"), 1).is_empty(), "not again within 45 minutes")

	# --- Her pitches: about 1 in 4, never two in a row ----------------------------
	s = Nudge.fresh_state()
	_check(not Nudge.pitch_tail(s, 0.1).is_empty(), "a low roll: a nudge on the pitch")
	_check(Nudge.pitch_tail(s, 0.1).is_empty(), "never two in a row")
	_check(Nudge.pitch_tail(s, 0.9).is_empty(), "most pitches stay clean")
	var tails := 0
	for i in 4000:
		if not Nudge.pitch_tail(s, randf()).is_empty():
			tails += 1
	_check(tails > 600 and tails < 1100, "roughly one in four or five offers (%d/4000)" % tails)

	# --- Every line once before any repeats; all clean of the canon --------------
	s = Nudge.fresh_state()
	var got := {}
	for i in Nudge.KAELEN_PITCH.size():
		got[Nudge.next_line(s, "kaelen_pitch")] = true
	_check(got.size() == Nudge.KAELEN_PITCH.size(), "a pool plays through before repeating")
	for pool in Nudge.POOLS:
		for line in Nudge.POOLS[pool]:
			_check(ReservedTopics.is_clean(str(line)), "%s: %s" % [pool, ReservedTopics.find_in(str(line))])
	_check(not "I'm not complaining. I'm noticing. There's a difference." in Nudge.NOVA_LINGER, "the cut line stays cut")
	# Wiring.
	_check(FileAccess.get_file_as_string("res://scripts/navigation/GateDiscoveryManager.gd").contains("OUTWARD_DISCOUNT"), "outward reveals are cheaper")
	_check(FileAccess.get_file_as_string("res://scripts/UIManager.gd").contains("pitch_tail("), "her pitches carry the nudge")
	if _failures.is_empty():
		print("[PASS] Undercurrent nudge")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
