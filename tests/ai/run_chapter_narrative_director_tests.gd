extends SceneTree

const ChapterDirectorType := preload("res://scripts/ai/ChapterNarrativeDirector.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_prompt_uses_labeled_director_inputs_only()
	_test_prompt_declares_chapter_packet_contract()

	if _failures.is_empty():
		print("[PASS] Chapter narrative director tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_prompt_uses_labeled_director_inputs_only() -> void:
	var prompt: String = ChapterDirectorType.build_chapter_plan_prompt(
		"Director-only campaign pressure. SECRET_DIRECTOR_ALLOWED",
		[
			{"entity_id": "station.start.main", "kind": "station"},
			{"entity_id": "faction.zenith", "kind": "faction"},
		],
		[
			{
				"objective_type": "DELIVERY_COURIER",
				"mechanic": "move special cargo between valid stations",
			},
		],
		[
			{"choice_id": "choice.helped_zenith", "description": "Helped Zenith keep a route open."},
		],
		{
			"chapter": 2,
			"pending_thread_refs": ["thread:convoy_loss"],
			"knowledge_gaps": ["fact.convoy_loss.visible"],
		}
	)
	for label in [
		"@@director_context",
		"@@validated_entities",
		"@@available_mission_capabilities",
		"@@recent_player_choices",
		"@@unresolved_story_state",
		"@@output_contract",
	]:
		_expect(prompt.contains(label), "Chapter plan prompt missing %s." % label)
	_expect(
		prompt.contains("station.start.main")
			and prompt.contains("DELIVERY_COURIER")
			and prompt.contains("choice.helped_zenith")
			and prompt.contains("thread:convoy_loss"),
		"Chapter plan prompt dropped one of its explicit inputs."
	)
	_expect(
		not prompt.contains("SECRET_UNPASSED_CAMPAIGN_BIBLE_FIELD"),
		"Chapter plan prompt included data that was not passed to the builder."
	)


func _test_prompt_declares_chapter_packet_contract() -> void:
	var prompt: String = ChapterDirectorType.build_chapter_plan_prompt(
		"Director context",
		[],
		[],
		[],
		{"chapter": 1},
		["Beat is missing a decline consequence."]
	)
	_expect(
		prompt.contains("@@correction_notes")
			and prompt.contains("Beat is missing a decline consequence."),
		"Chapter plan prompt did not include correction notes."
	)
	_expect(
		prompt.contains("packet_id")
			and prompt.contains("threads")
			and prompt.contains("facts")
			and prompt.contains("beats")
			and prompt.contains("start_when_consumed_ratio_at_least"),
		"Chapter plan prompt did not declare the packet output contract."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
