extends SceneTree

## Breathe in, breathe out: the window opens while docked or jumping, closes in
## flight, and the ledger counts model calls on the right side of the line.
##   Godot --headless --path . --script res://tests/story/run_generation_window_tests.gd --log-file <path> -- --baseline-offline

const WindowType := preload("res://scripts/ai/GenerationWindow.gd")
const Gateway := preload("res://scripts/ai/LocalModelGateway.gd")
const DirectorType := preload("res://scripts/story/premise/PremiseDirector.gd")

var _failures: Array[String] = []
var _events: Array = []


class FakeShip extends Node3D:
	var is_docked := false
	var destroyed := false


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GlobalState")
	var saved_player = gs.player
	var ship := FakeShip.new()
	root.add_child(ship)
	gs.player = ship
	var jumping := [false]
	var window = WindowType.new()
	window.jump_probe = func() -> bool: return jumping[0]
	window.set_process(false)  # driven by hand
	root.add_child(window)
	window.opened.connect(func(reason: String) -> void: _events.append("open:" + reason))
	window.closed.connect(func() -> void: _events.append("close"))
	Gateway.request_ledger = {"window": 0, "flight": 0, "flight_by_source": {}}

	window._process(0.1)
	_check(not window.is_open() and _events.is_empty() and not Gateway.window_open, "in flight the window is closed")
	Gateway.note_request("npc_chat")
	ship.is_docked = true
	window._process(0.1)
	_check(window.is_open() and window.reason() == "docked" and Gateway.window_open, "docking opens it")
	Gateway.note_request("premise_line_writer")
	window._process(0.1)
	_check(_events == ["open:docked"], "staying docked does not re-open it: %s" % str(_events))
	ship.is_docked = false
	window._process(0.1)
	_check(not window.is_open() and _events.back() == "close", "undocking closes it")
	jumping[0] = true
	window._process(0.1)
	_check(window.is_open() and window.reason() == "jump", "a gate jump opens it")
	jumping[0] = false
	window._process(0.1)
	_check(not window.is_open(), "arriving closes it")
	var ledger: Dictionary = Gateway.request_ledger
	_check(int(ledger["window"]) == 1 and int(ledger["flight"]) == 1 and ledger["flight_by_source"] == {"npc_chat": 1},
		"the ledger counts each call on its side: %s" % str(ledger))

	# The premise director waits for the window before model work.
	var d = DirectorType.new()
	_check(d._window_open(), "no probe (headless): always allowed")
	d.window_probe = window.is_open
	_check(not d._window_open(), "wired to the window: closed in flight")
	ship.is_docked = true
	window._process(0.1)
	_check(d._window_open(), "and open while docked")

	d.free()
	window.free()
	gs.player = saved_player
	ship.free()
	Gateway.window_open = false
	if _failures.is_empty():
		print("[PASS] Generation window tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
