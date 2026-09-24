extends SceneTree

## The pin board ("Loose ends"): threads, pins, and what the reveal shows.
##   Godot --headless --path . --script res://tests/story/run_pin_board_tests.gd --log-file <path> -- --baseline-offline

const Fixture := preload("res://tests/story/run_showrunner_tests.gd")
const DirectorType := preload("res://scripts/story/premise/PremiseDirector.gd")
const Hand := preload("res://scripts/story/premise/HiddenHand.gd")
const PanelType := preload("res://scripts/ui/PinBoardPanel.gd")

var _failures: Array[String] = []
var _pins: Array = []


func _initialize() -> void:
	await process_frame
	var fixture: Dictionary = Fixture.build_fixture()
	var d = DirectorType.new()
	d.use_showrunner = false
	d.state = fixture["state"]
	d._system_names = fixture["names"]
	var panel = PanelType.new()
	root.add_child(panel)
	panel.pin_toggled.connect(func(id: String, pinned: bool) -> void: _pins.append([id, pinned]))

	# Before the lock: notes, places, pins; nothing says which notes matter.
	var threads: Array = d.main_story_threads()
	_check(threads.size() >= 6, "the fixture has noticed threads (%d)" % threads.size())
	_check(threads.all(func(t): return not t.has("explanation") and not t.has("dead_end")), "no hints before the reveal")
	_check(not d.main_story_summary().has("hand"), "no name before the reveal")
	panel.show_threads(threads, d.main_story_summary())
	var text: String = panel.board_text()
	_check(text.contains(str(threads[0]["text"])), "notes are on the board")
	_check(text.contains("Noticed in"), "each note says where it was noticed")
	_check(text.contains("(0 pinned)"), "the header counts pins")
	var first_id := str(threads[0]["id"])
	panel._on_pin(first_id, true)
	_check(_pins == [[first_id, true]], "pinning reports to the game")
	_check(panel.board_text().contains("(1 pinned)"), "the header follows the pin")
	d.pin_thread(first_id, true)
	_check(d.main_story_threads().filter(func(t): return bool(t["pinned"])).size() == 1, "the pin lands in the story state")

	# Locked but not yet revealed: still no hints.
	d.state = Hand.lock_by_code(d.state, 100)["state"]
	_check(d.main_story_threads().all(func(t): return not t.has("explanation")), "a locked story still hides its links")

	# Revealed: each note shows how it connected, or that it was a dead end.
	d.state["main_story"]["stage"] = "revealed"
	var after: Array = d.main_story_threads()
	var summary: Dictionary = d.main_story_summary()
	_check(not str(summary.get("hand", "")).is_empty(), "the hand is named after the reveal")
	_check(after.any(func(t): return t.has("explanation")), "linked notes explain themselves")
	_check(after.all(func(t): return t.has("explanation") or bool(t.get("dead_end", false))), "every note is either connected or a dead end")
	panel.show_threads(after, summary)
	var revealed_text: String = panel.board_text()
	_check(revealed_text.contains("It was %s" % summary["hand"]), "the board names the hand: %s" % revealed_text.left(80))
	_check(revealed_text.contains("Connected:"), "the board shows the connections")
	_check(panel.find_children("*", "Button", true, false).filter(func(b): return (b as Button).text in ["Pin", "Unpin"]).is_empty(), "no pinning after the reveal")

	panel.free()
	d.free()
	if _failures.is_empty():
		print("[PASS] Pin board tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
