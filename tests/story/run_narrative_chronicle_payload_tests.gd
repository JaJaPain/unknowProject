extends SceneTree

var GameRootType: GDScript = null
var _failures: Array[String] = []


func _initialize() -> void:
	GameRootType = load("res://scripts/GameRoot.gd")
	if GameRootType == null:
		push_error("[FAIL] GameRoot.gd did not compile - suite cannot run.")
		quit(1)
		return
	_test_quest_chronicle_payload_preserves_narrative_metadata()

	if _failures.is_empty():
		print("[PASS] Narrative chronicle payload tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_quest_chronicle_payload_preserves_narrative_metadata() -> void:
	var payload: Dictionary = GameRootType._quest_chronicle_payload(
		{
			"runtime_id": "mission.runtime.payload_test",
			"definition_id": "mission.offer.payload_test",
			"title": "Payload Test",
			"objective_type": "KILL_SHIPS",
			"faction": "vanguard",
			"narrative_metadata": {
				"offer_id": "offer.payload",
				"story_hook_ref": "hook:payload123",
				"completion_fact_ids": ["fact.payload_done"],
			},
		},
		"completed"
	)
	var metadata: Dictionary = payload.get("narrative_metadata", {})
	_expect(
		metadata.get("story_hook_ref", "") == "hook:payload123",
		"Chronicle payload did not preserve story_hook_ref."
	)
	_expect(
		(metadata.get("completion_fact_ids", []) as Array).has("fact.payload_done"),
		"Chronicle payload did not preserve completion_fact_ids."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
