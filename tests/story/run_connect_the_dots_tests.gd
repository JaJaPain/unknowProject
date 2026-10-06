extends SceneTree

# The climax's connect-the-dots (campaign spine plan 12): real clues only,
# pinned first, a spread of systems, in the order found, at most five; the
# full version calls Kaelen, the short one is cooler; nothing left unfilled.

const Dots := preload("res://scripts/story/premise/ConnectTheDots.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_pick()
	_test_full_and_short()
	_test_nothing_to_show()
	if _failures.is_empty():
		print("[PASS] ConnectTheDots (all cases)")
		quit(0)
		return
	for f in _failures:
		push_error(f)
	print("[FAIL] ConnectTheDots: %d case(s)" % _failures.size())
	quit(1)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_failures.append(msg)


func _thread(id: String, system: String, minute: int, trace: bool, linked: bool, pinned := false) -> Dictionary:
	var t := {"id": id, "text": "Detail %s" % id, "system": system, "story": "Story %s" % id, "seen_minute": minute,
		"pinned": pinned, "trace": trace}
	if linked:
		t["explanation"] = "part of it"
	else:
		t["dead_end"] = true
	return t


func _threads() -> Array:
	return [
		_thread("a", "Myrion", 10, true, true),
		_thread("b", "Myrion", 20, true, true),
		_thread("c", "Kova", 30, true, true),
		_thread("d", "Zaren", 40, false, false),
		_thread("e", "Ashis", 50, true, true, true),
		_thread("f", "Vell", 60, true, true),
		_thread("g", "Orr", 70, true, true),
		_thread("h", "Tal", 80, true, true),
	]


func _test_pick() -> void:
	var picked := Dots.pick_clues(_threads())
	var ids: Array = picked.map(func(t): return t["id"])
	_check(picked.size() == Dots.MAX_CARDS, "five cards at most: %s" % str(ids))
	_check(not ids.has("d"), "a dead end is never shown")
	_check(ids.has("e"), "the pinned clue is shown")
	_check(not (ids.has("a") and ids.has("b")), "a spread of systems before a second from the same one: %s" % str(ids))
	var minutes: Array = picked.map(func(t): return t["seen_minute"])
	var sorted_minutes := minutes.duplicate()
	sorted_minutes.sort()
	_check(minutes == sorted_minutes, "shown in the order found")


func _test_full_and_short() -> void:
	var full := Dots.build(_threads(), "Oren Vask", "forged_records", "The beacon logs every ship.", "The Lighthouse", true)
	var whos: Array = full.map(func(s): return s["who"])
	_check(whos.has("kaelen") and whos.has("nova_comms"), "the full version calls Kaelen")
	_check(whos.count("card") == Dots.MAX_CARDS, "one step per card")
	for s in full:
		var text := str(s["text"])
		_check(not text.contains("{"), "nothing left unfilled: %s" % text)
	_check(full.any(func(s): return str(s["text"]).contains("The beacon logs every ship.")), "Kaelen puts it together with the bridge")
	var link_said: Array = full.filter(func(s): return str(s["text"]) == "Forged paperwork. Oren Vask's hand.")
	_check(link_said.size() == 1, "the method's line lands once, on the last card (said %d times)" % link_said.size())
	var short := Dots.build(_threads(), "Oren Vask", "forged_records", "The beacon logs every ship.", "The Lighthouse", false)
	_check(short.size() < full.size(), "later seasons get the shorter version")


func _test_nothing_to_show() -> void:
	_check(Dots.build([], "Oren Vask", "bribery", "", "", true).is_empty(), "no clues, no scene")
	_check(Dots.build(_threads(), "", "bribery", "", "", true).is_empty(), "no culprit, no scene")
