extends SceneTree

const KaelenKindsType := preload("res://scripts/story/KaelenInteractionKinds.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_phase_7_interaction_kinds_are_registered()
	_test_turn_in_and_reveal_groups_are_explicit()
	_test_existing_handoff_paths_use_interaction_constants()

	if _failures.is_empty():
		print("[PASS] Kaelen interaction bundle tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_phase_7_interaction_kinds_are_registered() -> void:
	var expected: Array[String] = [
		"agent_handoff",
		"offer_comment",
		"acceptance_afterthought",
		"objective_complete_pending_turn_in",
		"turn_in_clean",
		"turn_in_rough",
		"turn_in_late",
		"partial_delivery",
		"abandon",
		"decline",
		"chapter_comment",
		"first_system_arrival",
	]
	var actual := KaelenKindsType.all()
	_expect(
		actual == expected,
		"Kaelen interaction kind registry does not match the Phase 7 contract."
	)
	for kind in expected:
		_expect(
			KaelenKindsType.is_valid(kind),
			"Registered Kaelen interaction kind was not valid: %s" % kind
		)
	_expect(
		not KaelenKindsType.is_valid("director_secret_reveal"),
		"Unknown Kaelen interaction kind was accepted."
	)


func _test_turn_in_and_reveal_groups_are_explicit() -> void:
	for kind in [
		"objective_complete_pending_turn_in",
		"turn_in_clean",
		"turn_in_rough",
		"turn_in_late",
		"partial_delivery",
		"abandon",
		"decline",
	]:
		_expect(
			KaelenKindsType.is_turn_in(kind),
			"Kaelen turn-in/mission-outcome kind missing from turn-in group: %s" %
				kind
		)
	for kind in [
		"agent_handoff",
		"offer_comment",
		"acceptance_afterthought",
		"chapter_comment",
		"first_system_arrival",
	]:
		_expect(
			not KaelenKindsType.is_turn_in(kind),
			"Non-turn-in Kaelen kind was treated as a turn-in: %s" % kind
		)
	for kind in [
		"objective_complete_pending_turn_in",
		"turn_in_clean",
		"turn_in_rough",
		"turn_in_late",
		"partial_delivery",
	]:
		_expect(
			KaelenKindsType.allows_safe_after_completion_reveal(kind),
			"Completion-safe aftermath reveal missing for kind: %s" % kind
		)
	for kind in ["agent_handoff", "offer_comment", "acceptance_afterthought"]:
		_expect(
			not KaelenKindsType.allows_safe_after_completion_reveal(kind),
			"Pre-completion Kaelen kind allowed aftermath reveal too early: %s" %
				kind
		)


func _test_existing_handoff_paths_use_interaction_constants() -> void:
	var game_root_file := FileAccess.open("res://scripts/GameRoot.gd", FileAccess.READ)
	var ui_file := FileAccess.open("res://scripts/UIManager.gd", FileAccess.READ)
	_expect(
		game_root_file != null and ui_file != null,
		"Could not inspect existing Kaelen handoff constant wiring."
	)
	if game_root_file == null or ui_file == null:
		return
	var game_root_source := game_root_file.get_as_text()
	var ui_source := ui_file.get_as_text()
	_expect(
		game_root_source.contains("KaelenInteractionKindsType.AGENT_HANDOFF")
			and ui_source.contains("KaelenInteractionKindsType.AGENT_HANDOFF")
			and ui_source.contains("consume_cached_narrative_line_bank"),
		"Existing Kaelen handoff bank paths do not use the interaction-kind registry."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
