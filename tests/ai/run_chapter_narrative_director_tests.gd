extends SceneTree

const ChapterDirectorType := preload("res://scripts/ai/ChapterNarrativeDirector.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_prompt_uses_labeled_director_inputs_only()
	_test_prompt_declares_chapter_packet_contract()
	_test_parser_repairs_aliases_and_accepts_valid_packet()
	_test_parser_supplies_unformed_opposing_force_dossier()
	_test_parser_rejects_ineligible_attachment_beats()
	_test_parser_rejects_unavailable_objectives_and_entities()
	_test_validation_correction_notes_are_retry_ready()
	_test_fallback_packet_is_valid_and_grounded()

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
		prompt.contains("opposing_force")
			and prompt.contains("current_footprint")
			and prompt.contains("escalation_tier"),
		"Chapter plan prompt did not declare the opposing-force dossier contract."
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


func _test_parser_repairs_aliases_and_accepts_valid_packet() -> void:
	var raw_packet := {
		"id": "chapter_packet.2",
		"chapter": 2,
		"premise": "A convoy loss is pressuring the docks.",
		"narrative_threads": [{"thread_id": "thread.convoy_loss"}],
		"story_facts": [{"fact_id": "fact.convoy_loss.visible", "privacy": "public"}],
		"story_beats": [
			{
				"beat_id": "beat.trace_convoy",
				"thread_id": "thread.convoy_loss",
				"cause_id": "cause.convoy_pressure",
				"supported_objective_types": ["DELIVERY_COURIER"],
				"eligible_entity_ids": ["station.start.main"],
				"stake": "Dock deliveries will stall.",
			},
		],
	}
	var envelope := {"response": JSON.stringify(raw_packet)}
	var result: Dictionary = ChapterDirectorType.parse_chapter_plan_response(
		JSON.stringify(envelope),
		["DELIVERY_COURIER"],
		["station.start.main"],
		"qwen3:8b"
	)
	var packet: Dictionary = result.get("packet", {})
	_expect(
		bool(result.get("ok", false))
			and str(packet.get("packet_id", "")) == "chapter_packet.2"
			and (packet.get("threads", []) as Array).size() == 1
			and (packet.get("facts", []) as Array).size() == 1
			and (packet.get("beats", []) as Array).size() == 1,
		"Chapter plan parser did not repair aliases into canonical packet shape."
	)


func _test_parser_supplies_unformed_opposing_force_dossier() -> void:
	var raw_packet := {
		"packet_id": "chapter_packet.3",
		"chapter": 3,
		"premise": "The route pressure has not identified its source.",
		"threads": [],
		"facts": [],
		"beats": [
			{
				"beat_id": "beat.route_pressure",
				"supported_objective_types": ["DELIVERY_COURIER"],
				"eligible_entity_ids": ["station.start.main"],
				"stake": "The local route remains unstable.",
			},
		],
	}
	var result: Dictionary = ChapterDirectorType.parse_chapter_plan_response(
		JSON.stringify({"response": JSON.stringify(raw_packet)}),
		["DELIVERY_COURIER"],
		["station.start.main"],
		"qwen3:8b"
	)
	var dossier: Dictionary = (result.get("packet", {}) as Dictionary).get(
		"opposing_force",
		{}
	)
	var identity: Dictionary = dossier.get("identity", {})
	_expect(
		bool(result.get("ok", false))
			and str(dossier.get("status", "")) == "unformed"
			and (identity.get("known", []) as Array).is_empty()
			and (identity.get("unknown", []) as Array).is_empty()
			and str(dossier.get("chapter_move", "")).is_empty()
			and int(dossier.get("escalation_tier", -1)) == 0,
		"Chapter plan parser did not add the safe unformed opposing-force dossier."
	)


func _test_parser_rejects_ineligible_attachment_beats() -> void:
	var raw_packet := {
		"packet_id": "chapter_packet.attachment",
		"chapter": 1,
		"premise": "A test pressure.",
		"threads": [],
		"facts": [],
		"attachment_beats": [
			{"character_id": "kaelen", "beat_id": "earned_change"},
		],
		"beats": [
			{
				"beat_id": "beat.attachment",
				"supported_objective_types": ["DELIVERY_COURIER"],
				"eligible_entity_ids": ["station.start.main"],
				"stake": "The test needs a beat.",
			},
		],
	}
	var result: Dictionary = ChapterDirectorType.parse_chapter_plan_response(
		JSON.stringify({"response": JSON.stringify(raw_packet)}),
		["DELIVERY_COURIER"],
		["station.start.main"],
		"qwen3:8b",
		[{"character_id": "kaelen", "beat_id": "first_impression"}]
	)
	_expect(
		not bool(result.get("ok", true))
			and _has_error_code(result.get("validation") as ValidationResult, "ineligible_attachment_beat"),
		"Chapter plan parser accepted an attachment beat that had not been earned."
	)


func _test_parser_rejects_unavailable_objectives_and_entities() -> void:
	var raw_packet := {
		"packet_id": "chapter_packet.2",
		"chapter": 2,
		"premise": "A bad fixture.",
		"threads": [],
		"facts": [],
		"beats": [
			{
				"beat_id": "beat.bad",
				"supported_objective_types": ["MADE_UP_OBJECTIVE"],
				"eligible_entity_ids": ["station.missing"],
				"stake": "The fixture should fail.",
			},
		],
	}
	var result: Dictionary = ChapterDirectorType.parse_chapter_plan_response(
		JSON.stringify({"response": JSON.stringify(raw_packet)}),
		["KILL_SHIPS"],
		["station.start.main"],
		"qwen3:8b"
	)
	var validation := result.get("validation") as ValidationResult
	_expect(
		not bool(result.get("ok", true))
			and str(result.get("reason", "")) == "chapter_plan_validation_failed"
			and _has_error_code(validation, "unsupported_chapter_beat_objective")
			and _has_error_code(validation, "unknown_chapter_beat_entity"),
		"Chapter plan parser did not loudly reject unavailable objectives/entities."
	)


func _test_validation_correction_notes_are_retry_ready() -> void:
	var validation := ValidationResult.new()
	validation.add_error(
		"missing_chapter_beat_stake",
		"Chapter beat requires a stake.",
		"beats.0.stake"
	)
	var notes: Array[String] = ChapterDirectorType.validation_correction_notes(
		validation
	)
	_expect(
		notes.size() == 1
			and notes[0].contains("missing_chapter_beat_stake")
			and notes[0].contains("beats.0.stake"),
		"Chapter plan validation notes were not suitable for correction retry."
	)


func _test_fallback_packet_is_valid_and_grounded() -> void:
	var packet: Dictionary = ChapterDirectorType.fallback_chapter_packet(
		1,
		["PURCHASE_DELIVERY", "KILL_SHIPS"],
		["npc.kaelen", "station.start.main"],
		"chapter_plan_validation_failed"
	)
	var result: Dictionary = ChapterDirectorType.parse_chapter_plan_response(
		JSON.stringify({"response": JSON.stringify(packet)}),
		["PURCHASE_DELIVERY", "KILL_SHIPS"],
		["npc.kaelen", "station.start.main"],
		"fallback"
	)
	var parsed: Dictionary = result.get("packet", {}) \
		if result.get("packet", {}) is Dictionary else {}
	_expect(
		bool(result.get("ok", false))
			and str(parsed.get("packet_id", "")) == "chapter_packet.1.fallback"
			and str(parsed.get("source", "")) == "procedural_fallback"
			and int(parsed.get("chapter", 0)) == 1,
		"Fallback chapter packet was not valid, grounded, and clearly labeled."
	)


func _has_error_code(validation: ValidationResult, code: String) -> bool:
	if validation == null:
		return false
	for error in validation.errors:
		if str(error.get("code", "")) == code:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
