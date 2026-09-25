class_name GenerationWindow
extends Node

## "Breathe in, breathe out" (plan Section 2, Phase 1).
##
## The window is OPEN while the game boots or builds a campaign, while the
## pilot is docked, or while a gate jump is under way:
## cheap scenes where the local model may load and write ahead. It is CLOSED
## in flight, where the renderer owns the GPU and content should already be
## written.
##
## This node only knows the state and keeps the ledger; callers ask
## `is_open()` before starting model work, and every model request reports
## itself through LocalModelGateway.note_request(), so a session shows how many
## calls still happen in flight (the Phase 1 exit criterion is zero).
##
## `unload_on_close` frees the small model from VRAM when the pilot leaves a
## window. Off until the ledger shows flight no longer needs the model (live
## conversations would otherwise pay a cold reload each time).

signal opened(reason: String)
signal closed()

const GatewayType := preload("res://scripts/ai/LocalModelGateway.gd")

var unload_on_close := false
## Tells the window whether a jump is under way (GameRoot owns that state).
var jump_probe: Callable = Callable()
## True while the game is starting up or building a new campaign (before
## gameplay begins): the plan allows model work then, the renderer is idle.
var boot_probe: Callable = Callable()
var _open := false
var _reason := ""


func is_open() -> bool:
	return _open


func reason() -> String:
	return _reason


func _process(_delta: float) -> void:
	var now := _current_reason()
	if now.is_empty() == not _open:
		return  # unchanged
	if now.is_empty():
		_open = false
		_reason = ""
		GatewayType.window_open = false
		closed.emit()
		if unload_on_close:
			_unload_small_model()
	else:
		_open = true
		_reason = now
		GatewayType.window_open = true
		opened.emit(now)


## "boot", "docked", "jump" or "" (in flight).
func _current_reason() -> String:
	if boot_probe.is_valid() and bool(boot_probe.call()):
		return "boot"
	if jump_probe.is_valid() and bool(jump_probe.call()):
		return "jump"
	var gs := get_node_or_null("/root/GlobalState")
	var ship = gs.player if gs != null else null
	if ship != null and is_instance_valid(ship) and bool(ship.get("is_docked")):
		return "docked"
	return ""


## Ollama unloads a model when asked to generate nothing with keep_alive 0.
func _unload_small_model() -> void:
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	http.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray) -> void: http.queue_free())
	var body := JSON.stringify({"model": GatewayType.DEFAULT_SMALL_MODEL, "keep_alive": 0})
	if http.request(GatewayType.OLLAMA_GENERATE_URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body) != OK:
		http.queue_free()
