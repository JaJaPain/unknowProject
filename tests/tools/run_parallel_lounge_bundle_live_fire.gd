extends SceneTree

# Explicit concurrency probe. Normal game interaction remains bundle-cached and
# click-safe; this tool only establishes how Ollama behaves with two writers.

const ARTIFACT_PATH := "res://logs/parallel_lounge_bundle_live_fire.json"

var _llm: Node = null
var _convo: GDScript = null
var _started_msec := 0
var _results: Array[Dictionary] = []


func _initialize() -> void:
	_started_msec = Time.get_ticks_msec()
	await process_frame
	_llm = get_root().get_node_or_null("LLMInterface")
	if _llm == null:
		_finish()
		return
	_convo = load("res://scripts/story/LoungeConversation.gd")
	if _convo == null:
		_finish()
		return
	while not bool(_llm.get("small_model_verified")):
		await process_frame
	for index in 2:
		var fixture := _fixture(index)
		var npc: Dictionary = fixture.get("npc", {})
		var intents: Array = fixture.get("intents", [])
		var prompt: String = _convo.build_bundle_prompt(npc, str(fixture.get("flavor", "")), intents)
		_llm.call("request_lounge_exchange_bundle", prompt, func(result: Dictionary) -> void:
			var parsed := {"ok": false, "reason": str(result.get("reason", "transport_failed"))}
			if bool(result.get("ok", false)):
				parsed = _convo.parse_bundle(str(result.get("inner_text", "")), str(npc.get("name", "")), intents.size())
				parsed = _convo.validate_bundle_answers(parsed, intents)
			_results.append({"fixture": fixture.get("label", ""), "result": result, "parsed": parsed})
			if _results.size() == 2:
				_finish()
		)


func _fixture(index: int) -> Dictionary:
	var topics := [["convoy", "Why are the convoy delays getting worse?", "Traffic control is marking the convoy delays as unscheduled."], ["shortage", "What is the fabrication shortage doing to this station?", "The fabrication shops are rationing parts."]]
	var topic: Array = topics[index]
	return {
		"label": str(topic[0]),
		"npc": {"name": "Parallel Contact %d" % (index + 1), "role": "dockside regular", "station": "Morrow Station", "mood": "wary", "faction": "independent", "extra": "Stranger contact."},
		"flavor": "Campaign tone: dry and practical. Known local fact: %s" % str(topic[2]),
		"intents": [{"id": "ask_%s" % str(topic[0]), "text": str(topic[1]), "anchors": [str(topic[0])]}, {"id": "ask_personal", "text": "Does that change how you work?", "anchors": []}],
	}


func _finish() -> void:
	var passed := 0
	for row in _results:
		if bool((row.get("parsed", {}) as Dictionary).get("ok", false)):
			passed += 1
	var artifact := {"count": _results.size(), "passed": passed, "elapsed_seconds": float(Time.get_ticks_msec() - _started_msec) / 1000.0, "rows": _results}
	var file := FileAccess.open(ARTIFACT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(artifact, "\t"))
		file.close()
	print("[ParallelLoungeLiveFire] %d/2 writers parsed." % passed)
	quit(0 if passed == 2 else 1)
