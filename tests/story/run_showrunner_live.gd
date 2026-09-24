extends SceneTree

## LIVE check against a running Ollama (not part of the regular suite): sends a
## real campaign's evidence to the Showrunner model and reports what came back.
##   Godot --headless --path . --script res://tests/story/run_showrunner_live.gd --log-file <path>

const Show := preload("res://scripts/story/premise/Showrunner.gd")
const Hand := preload("res://scripts/story/premise/HiddenHand.gd")
const Fixture := preload("res://tests/story/run_showrunner_tests.gd")

var _fixture: Dictionary
var _started := 0


func _initialize() -> void:
	_fixture = Fixture.build_fixture()
	var req := Show.build_request(_fixture["state"], _fixture["library"], _fixture["names"])
	print("[Live] prompt: %d chars, model %s" % [str(req["prompt"]).length(), req["model"]])
	var http := HTTPRequest.new()
	http.timeout = 240.0
	root.add_child(http)
	http.request_completed.connect(_on_done)
	# The node is only inside the tree (and able to send) after a frame.
	await process_frame
	_started = Time.get_ticks_msec()
	var err := http.request("http://127.0.0.1:11434/api/generate", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(req))
	if err != OK:
		print("[Live] request failed to start: %d" % err)
		quit(1)


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var seconds := (Time.get_ticks_msec() - _started) / 1000.0
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("[Live] HTTP failure result=%d code=%d after %.1fs" % [result, code, seconds])
		quit(1)
		return
	var raw_body := body.get_string_from_utf8()
	var meta = JSON.parse_string(raw_body)
	if meta is Dictionary:
		print("[Live] load %.1fs, prompt eval %d tok in %.1fs, output %d tok in %.1fs (%.1f tok/s)" % [
			float(meta.get("load_duration", 0)) / 1e9, int(meta.get("prompt_eval_count", 0)), float(meta.get("prompt_eval_duration", 0)) / 1e9,
			int(meta.get("eval_count", 0)), float(meta.get("eval_duration", 0)) / 1e9,
			float(meta.get("eval_count", 0)) / maxf(0.001, float(meta.get("eval_duration", 1)) / 1e9)])
	var text := Show.response_text(raw_body)
	var parsed := Show.parse_response(text, _fixture["state"])
	print("[Live] %.1fs, parse ok=%s reason=%s" % [seconds, str(parsed["ok"]), parsed["reason"]])
	if bool(parsed["ok"]):
		var choice: Dictionary = parsed["choice"]
		print("[Live] chose: %s (expected npc.recurring to be the obvious pick)" % choice["entity_id"])
		print("[Live] truth: %s" % choice["truth"])
		for tid in choice["links"].keys():
			print("[Live]   %s -> %s" % [tid, choice["links"][tid]])
		for b in choice["next_beats"]:
			print("[Live]   beat: %s" % b)
		var locked := Hand.lock(_fixture["state"], choice, 99)
		print("[Live] lock ok=%s" % str(locked["ok"]))
		print("[PASS] Showrunner live")
		quit(0)
	else:
		print("[Live] raw: %s" % text.substr(0, 800))
		quit(1)
