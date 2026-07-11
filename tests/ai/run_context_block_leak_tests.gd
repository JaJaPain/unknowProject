extends SceneTree

const ContextBlockBuilderType := preload(
	"res://scripts/ai/ContextBlockBuilder.gd"
)

var _failures: Array[String] = []


func _initialize() -> void:
	_test_story_state_public_block_uses_allowlist()
	_test_named_small_model_blocks_do_not_leak_director_fields()

	if _failures.is_empty():
		print("[PASS] Context block leak tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_story_state_public_block_uses_allowlist() -> void:
	var state := _salted_story_state()
	var block: String = ContextBlockBuilderType.story_state_public_block(state)
	_expect(block.contains("Visible shortage pressure"), "Public tension missing.")
	_expect(block.contains("Kaelen looks worried"), "Public knowledge missing.")
	_expect(block.contains("guarded"), "Public Kaelen mood missing.")
	_expect(block.contains("Zenith [rising(+2)]"), "Faction pressure missing.")
	_expect(
		block.contains("Open story thread refs: hook:")
			and not block.contains("A convoy vanished near the relay."),
		"Public story block did not replace free-form hook text with stable refs."
	)
	_assert_no_secret_tokens(block, "story_state_public_block")


func _test_named_small_model_blocks_do_not_leak_director_fields() -> void:
	var state := _salted_story_state()
	var blocks := {
		"mission_offer": ContextBlockBuilderType.mission_offer_block(state),
		"mission_answer": ContextBlockBuilderType.mission_answer_block(state),
		"character_conversation": ContextBlockBuilderType.character_conversation_block(state),
		"ambient_chatter": ContextBlockBuilderType.ambient_chatter_block(state),
		"nova": ContextBlockBuilderType.nova_block(state),
		"kaelen": ContextBlockBuilderType.kaelen_block(state),
	}
	for block_name in blocks.keys():
		var block := str(blocks[block_name])
		_expect(
			block.contains("### ") and block.contains("Purpose: "),
			"%s did not include a capability-specific header and purpose." %
				block_name
		)
		_expect(
			block.contains("Story State:"),
			"%s did not include the shared public story-state projection." %
				block_name
		)
		_assert_no_secret_tokens(block, block_name)


func _salted_story_state() -> Dictionary:
	return {
		"chapter": 3,
		"active_tensions": ["Visible shortage pressure"],
		"player_knows": ["Kaelen looks worried"],
		"current_foreshadow": "Dock crews are counting sealed crates.",
		"kaelen_current_mood": "guarded",
		"pending_hooks": ["A convoy vanished near the relay."],
		"faction_pressure": {
			"zenith": {"pressure": 2, "posture": "repossessing mining rigs"},
			"aurelia": {"pressure": -1, "posture": "rationing coolant"},
		},
		"player_does_not_know_yet": ["SECRET_UNKNOWN_TRUTH_TOKEN"],
		"kaelen_hidden_angle": "SECRET_KAELEN_ANGLE_TOKEN",
		"nova_memory_flicker": "SECRET_NOVA_MEMORY_TOKEN",
		"kaelen_hidden_hints": ["SECRET_HINT_TOKEN"],
		"knowledge_states": {
			"fact.hidden.director": {
				"state": "unknown",
				"legacy_text": "SECRET_FACT_TEXT_TOKEN",
			},
		},
		"beat_states": {
			"beat.hidden": {"director_note": "SECRET_BEAT_TOKEN"},
		},
		"new_schema_field_not_yet_allowlisted": "NEW_SCHEMA_PRIVATE_TOKEN",
	}


func _assert_no_secret_tokens(block: String, block_name: String) -> void:
	for secret in [
		"SECRET_UNKNOWN_TRUTH_TOKEN",
		"SECRET_KAELEN_ANGLE_TOKEN",
		"SECRET_NOVA_MEMORY_TOKEN",
		"SECRET_HINT_TOKEN",
		"SECRET_FACT_TEXT_TOKEN",
		"SECRET_BEAT_TOKEN",
		"NEW_SCHEMA_PRIVATE_TOKEN",
	]:
		_expect(
			not block.contains(secret),
			"%s leaked director-only token: %s" % [block_name, secret]
		)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
