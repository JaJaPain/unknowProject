extends SceneTree

# Loaded at runtime, NOT via const preload: a preload here fires before the
# autoload singletons register, so StoryManager (which references GlobalState,
# LLMInterface, Nova, ...) caches a FAILED compile and every test aborts on a
# Nil manager while the suite still prints PASS with zero assertions. Loading
# lazily inside _initialize() compiles it after autoloads exist.
var StoryManagerType: GDScript = null

var _failures: Array[String] = []


func _initialize() -> void:
	StoryManagerType = load("res://scripts/story/StoryManager.gd")
	if StoryManagerType == null or not StoryManagerType.can_instantiate():
		push_error("[FAIL] StoryManager.gd did not compile — suite cannot run.")
		quit(1)
		return
	_test_seed_maps_bible_fields_into_story_state()
	_test_seed_is_idempotent()
	_test_seed_maps_factions_into_pressure()
	_test_kaelen_hint_delivery()
	_test_nova_fields_seed_and_privacy()

	if _failures.is_empty():
		print("[PASS] Story state bible seed tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _fake_bible() -> Dictionary:
	return {
		"campaign_title": "Test Campaign",
		"main_mystery": "Who is sabotaging the fixture.",
		"opening_situation": "The fixture opens on a quiet dock.",
		"kaelen_angle": "Kaelen secretly wrote the fixture herself.",
		"act_1_outline": [
			"Beat zero — consumed at seed time as the chapter-1 tension.",
			"Beat one — should land in player_does_not_know_yet.",
			"Beat two — should also land in player_does_not_know_yet.",
		],
		"story_arcs": [
			{"name": "Arc One", "summary": "The fixture's opening tension."},
		],
		"rumor_trails": [
			{
				"name": "Trail One",
				"trail_id": "rumor_trail.trail_one",
				"clue_templates": ["Clue A about the fixture.", "Clue B about the fixture."],
			},
		],
		"factions": {
			"zenith": "Zenith is auditing every dock ledger twice.",
			"aurelia": "Aurelia is quietly buying out debt.",
			"vanguard": "Vanguard is massing patrols near the gate.",
		},
		"kaelen_hint_plan": [
			"She pays dock fees for a hauler she never mentions.",
			"She flinches at the name of a dead station.",
		],
		"kaelen_hint_style": "over-precise details",
		"nova_quirk": "I recount the fixture's bolts every jump. The count changes.",
		"nova_memory_flicker": "A wiped diagnostic log hums whenever the fixture is named.",
	}


func _fresh_manager() -> Node:
	var manager: Node = StoryManagerType.new()
	root.add_child(manager)
	return manager


func _test_seed_maps_bible_fields_into_story_state() -> void:
	var manager := _fresh_manager()
	manager.seed_story_state_from_bible(_fake_bible())

	var state: Dictionary = manager.story_state
	_expect(
		(state.get("active_tensions", []) as Array).has("The fixture's opening tension."),
		"active_tensions did not receive the first story_arc summary."
	)
	var hidden: Array = state.get("player_does_not_know_yet", [])
	_expect(
		hidden.has("Beat one — should land in player_does_not_know_yet.")
			and hidden.has("Beat two — should also land in player_does_not_know_yet.")
			and hidden.has("Who is sabotaging the fixture."),
		"player_does_not_know_yet did not receive the unconsumed act_1_outline beats and main_mystery."
	)
	_expect(
		not hidden.has("Beat zero — consumed at seed time as the chapter-1 tension."),
		"player_does_not_know_yet incorrectly included the chapter-1 tension beat."
	)
	var hooks: Array = state.get("pending_hooks", [])
	_expect(
		hooks.has("Clue A about the fixture.") and hooks.has("Clue B about the fixture."),
		"pending_hooks did not receive both rumor_trail clue_templates."
	)
	_expect(
		str(state.get("kaelen_hidden_angle", "")) == "Kaelen secretly wrote the fixture herself.",
		"kaelen_hidden_angle was not seeded from bible_data.kaelen_angle."
	)
	_expect(
		bool(state.get("bible_seeded", false)),
		"bible_seeded was not set to true after seeding."
	)
	var context_block: String = manager.get_story_context_block()
	_expect(
		not context_block.contains("Kaelen secretly wrote the fixture herself."),
		"get_story_context_block() leaked kaelen_hidden_angle — this must never reach prompts."
	)
	_expect(
		not context_block.contains("Who is sabotaging the fixture."),
		"get_story_context_block() leaked a player_does_not_know_yet entry — this must never reach prompts."
	)
	manager.queue_free()


func _test_seed_is_idempotent() -> void:
	var manager := _fresh_manager()
	manager.seed_story_state_from_bible(_fake_bible())
	var tensions_after_first: Array = (manager.story_state.get("active_tensions", []) as Array).duplicate()
	manager.seed_story_state_from_bible(_fake_bible())
	var tensions_after_second: Array = manager.story_state.get("active_tensions", [])
	_expect(
		tensions_after_second.size() == tensions_after_first.size(),
		"Calling seed_story_state_from_bible twice duplicated active_tensions instead of being a no-op."
	)
	manager.queue_free()


func _test_seed_maps_factions_into_pressure() -> void:
	var manager := _fresh_manager()
	manager.seed_story_state_from_bible(_fake_bible())
	var pressure: Dictionary = manager.story_state.get("faction_pressure", {})
	_expect(
		pressure.has("zenith") and pressure.has("aurelia") and pressure.has("vanguard"),
		"faction_pressure was not seeded for all three anchors."
	)
	_expect(
		str(pressure.get("vanguard", {}).get("posture", "")).contains("massing patrols")
			and int(pressure.get("vanguard", {}).get("pressure", 99)) == 0,
		"vanguard pressure did not seed posture from the faction problem at neutral scalar."
	)
	# Faction pressure rides in the player-safe story-state block.
	var block: String = manager.get_story_context_block()
	_expect(
		block.contains("Faction pressure:") and block.contains("massing patrols"),
		"get_story_context_block() did not surface faction pressure. Got: %s" % block
	)
	# Write path clamps and updates the scalar.
	manager.adjust_faction_pressure("vanguard", 5)
	_expect(
		int(manager.story_state.get("faction_pressure", {}).get("vanguard", {}).get("pressure", 0)) == 3,
		"adjust_faction_pressure did not clamp the scalar to +3."
	)
	manager.adjust_faction_pressure("vanguard", -10)
	_expect(
		int(manager.story_state.get("faction_pressure", {}).get("vanguard", {}).get("pressure", 0)) == -3,
		"adjust_faction_pressure did not clamp the scalar to -3."
	)
	manager.queue_free()


func _test_kaelen_hint_delivery() -> void:
	var manager := _fresh_manager()
	manager.seed_story_state_from_bible(_fake_bible())

	var hidden: Array = manager.story_state.get("kaelen_hidden_hints", [])
	_expect(hidden.size() == 2, "Kaelen hint plan did not seed the undelivered hints.")
	_expect(
		str(manager.story_state.get("kaelen_hint_style", "")) == "over-precise details",
		"kaelen_hint_style was not seeded from the bible."
	)
	# Undelivered hints are director-only — never in the prompt context block.
	var block: String = manager.get_story_context_block()
	_expect(
		not block.contains("hauler she never mentions"),
		"get_story_context_block() leaked an undelivered Kaelen hint."
	)

	# Delivery pops hints in order and moves them to the player-safe delivered list.
	var first: String = manager.deliver_next_kaelen_hint()
	_expect(
		first.contains("hauler she never mentions"),
		"deliver_next_kaelen_hint did not return the first hint. Got: %s" % first
	)
	_expect(
		(manager.story_state.get("kaelen_hidden_hints", []) as Array).size() == 1
			and (manager.story_state.get("kaelen_hints_delivered", []) as Array).size() == 1,
		"Delivering a hint did not move it from hidden to delivered."
	)
	manager.deliver_next_kaelen_hint()
	_expect(
		manager.deliver_next_kaelen_hint() == "",
		"Delivering past the last hint should return an empty string."
	)
	manager.queue_free()


func _test_nova_fields_seed_and_privacy() -> void:
	var manager := _fresh_manager()
	manager.seed_story_state_from_bible(_fake_bible())

	_expect(
		str(manager.story_state.get("nova_quirk", "")).contains("bolts"),
		"nova_quirk was not seeded from the bible."
	)
	_expect(
		str(manager.story_state.get("nova_memory_flicker", "")).contains("diagnostic log"),
		"nova_memory_flicker was not seeded from the bible."
	)
	# The flicker is director-only: never in the prompt-facing context block.
	var block: String = manager.get_story_context_block()
	_expect(
		not block.contains("diagnostic log"),
		"get_story_context_block() leaked nova_memory_flicker — this must never reach prompts."
	)
	# Ambient flavor block is player-safe: carries the current tension, never the
	# flicker, never undelivered Kaelen hints.
	var flavor: String = manager.get_ambient_flavor_block()
	_expect(
		flavor.contains("The fixture's opening tension."),
		"get_ambient_flavor_block() did not carry the active tension. Got: %s" % flavor
	)
	_expect(
		not flavor.contains("diagnostic log") and not flavor.contains("hauler she never mentions"),
		"get_ambient_flavor_block() leaked a director-only field."
	)
	# clear_story_state wipes both fields (new campaigns inherit nothing).
	manager.clear_story_state()
	_expect(
		str(manager.story_state.get("nova_quirk", "")).is_empty()
			and str(manager.story_state.get("nova_memory_flicker", "")).is_empty(),
		"clear_story_state did not wipe the nova fields."
	)
	manager.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
