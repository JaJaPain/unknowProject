extends SceneTree

# Small real-model audit for the reviewed Kaelen style references. Unlike the
# broad baseline capture, this stays intentionally tiny and prints both results
# for quick human inspection.
var _index := 0
var _llm: Node = null
var _fixtures: Array[Dictionary] = [
	{
		"title": "Quiet Haul",
		"faction": "neutral",
		"objective": {"type": "DELIVER_ORE", "amount_required": 20, "reward_credits": 100},
		"reward_credits": 100,
	},
	{
		"title": "Hot Collection",
		"faction": "vanguard",
		"objective": {"type": "KILL_SHIPS", "target_faction": "reavers", "count_required": 3, "reward_credits": 500},
		"reward_credits": 500,
		"known_tough": true,
	}
]


func _initialize() -> void:
	await process_frame
	_llm = get_root().get_node_or_null("LLMInterface")
	if _llm == null:
		push_error("[KaelenCuratedLive] LLMInterface autoload is unavailable.")
		quit(1)
		return
	var deadline := Time.get_ticks_msec() + 90000
	while not bool(_llm.get("small_model_verified")) \
			and Time.get_ticks_msec() < deadline:
		await process_frame
	if not bool(_llm.get("small_model_verified")):
		push_error("[KaelenCuratedLive] Small model did not become ready.")
		quit(1)
		return
	_run_next()


func _run_next() -> void:
	if _index >= _fixtures.size():
		print("[PASS] Kaelen curated-style live audit")
		quit(0)
		return
	var fixture: Dictionary = _fixtures[_index]
	_index += 1
	_llm.call(
		"request_kaelen_reaction",
		fixture,
		func(completion: String, abandonment: String) -> void:
			print("[KaelenCuratedLive] %s completion: %s" % [fixture.get("title", ""), completion])
			print("[KaelenCuratedLive] %s abandonment: %s" % [fixture.get("title", ""), abandonment])
			_run_next()
	)
