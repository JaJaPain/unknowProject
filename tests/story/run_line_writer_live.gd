extends SceneTree

## LIVE (manual; needs Ollama): writes briefing lines for real card missions and
## prints each line, its check result and timing.
##   Godot --headless --path . --script res://tests/story/run_line_writer_live.gd --log-file <path>

const Writer := preload("res://scripts/story/premise/LineWriter.gd")
const LibraryType := preload("res://scripts/story/premise/PremiseCardLibrary.gd")
const Casting := preload("res://scripts/story/premise/PremiseCasting.gd")

const SAMPLE := 8
var _jobs: Array = []
var _index := 0
var _started := 0
var _passed := 0
var _http: HTTPRequest


func _initialize() -> void:
	var lib = LibraryType.new()
	lib.load_from_dir()
	var world := {"system_display": "Vessa", "main_station": {"id": "system.v", "display": "Vessa Main"},
		"outposts": [{"id": "outpost.a", "display": "Iron Reach"}, {"id": "outpost.b", "display": "Kova Station"}],
		"factions": [{"id": "faction.generated.g", "display_name": "the Tessin Guild", "spawn_key": "g"}],
		"hostile_factions": ["reavers"], "known_npcs": []}
	var ids := lib.ids()
	for i in SAMPLE:
		var card: Dictionary = lib.get_card(ids[(i * 13) % ids.size()])
		var cast := Casting.cast_card(card, world, i, "arc.%04d" % i)
		var mission: Dictionary = card["beats"][0]["missions"][0]
		var speaker: Dictionary = cast.get(str(mission["requester"]), {})
		var target: Dictionary = cast.get(str(mission.get("target", "")), {})
		_jobs.append({"card": card["id"], "private": Casting.fill_text(str(mission.get("private_fact", "")), cast, world), "brief": {
			"speaker": str(speaker.get("display_name", "A contact")),
			"archetype": str(speaker.get("archetype", "contact")),
			"faction": "",
			"voice_direction": str((card.get("voice_direction", {}) as Dictionary).get(str(mission["requester"]), "")),
			"situation": Casting.fill_text(str(card.get("public_situation", "")), cast, world),
			"note": Casting.fill_text(str(mission.get("reason", "")), cast, world),
			"task": "%s, at %s" % [str(mission["verb"]).replace("_", " "), str(target.get("display_name", "the station"))]}})
	# Returning faces: the line should bring up the history in the speaker's own words.
	_jobs[0]["brief"]["history"] = "They have dealt with the pilot once before; last time in Kova Station, it went badly for them, they still blame the pilot for it, and they are not hiding it."
	_jobs[1]["brief"]["history"] = "They have dealt with the pilot twice before; last time, the pilot came through for them and they haven't forgotten."
	_http = HTTPRequest.new()
	_http.timeout = 180.0
	root.add_child(_http)
	_http.request_completed.connect(_on_done)
	await process_frame
	_send()


func _send() -> void:
	if _index >= _jobs.size():
		print("[Live] %d of %d lines passed the checks" % [_passed, _jobs.size()])
		print("[PASS] Line writer live")
		quit(0)
		return
	_started = Time.get_ticks_msec()
	_http.request("http://127.0.0.1:11434/api/generate", ["Content-Type: application/json"], HTTPClient.METHOD_POST,
		JSON.stringify(Writer.build_briefing_request(_jobs[_index]["brief"], OS.get_environment("LINE_MODEL"))))


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var job: Dictionary = _jobs[_index]
	var seconds := (Time.get_ticks_msec() - _started) / 1000.0
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("[Live] %s: HTTP failure %d/%d" % [job["card"], result, code])
	else:
		var checked := Writer.check_line(Writer.response_text(body.get_string_from_utf8()), job["brief"], job["private"])
		if bool(checked["ok"]):
			_passed += 1
		print("[Live] %s (%.1fs) %s: %s" % [job["card"], seconds, "OK" if checked["ok"] else "REJECT " + checked["reason"],
			checked["line"] if checked["ok"] else Writer.response_text(body.get_string_from_utf8()).substr(0, 200)])
		print("[Live]    note: %s" % job["brief"]["note"])
		if not str(job["brief"].get("history", "")).is_empty():
			print("[Live]    history: %s" % job["brief"]["history"])
	_index += 1
	_send()
