extends SceneTree

# Tests for LLMDialogueContentRegistry: the JSON loads, required keys exist,
# quest examples/dummy-constraints resolve for every agent x mission type, and
# nickname ownership rules (Shiny = Kaelen only, Indy = rare) are intact.

var _failures: Array[String] = []


func _initialize() -> void:
	LLMDialogueContentRegistry.reset_shared()
	var registry := LLMDialogueContentRegistry.shared()

	_expect(
		registry.is_valid(),
		"Dialogue content registry failed to load: %s" % JSON.stringify(registry.validation.to_dict())
	)

	if registry.is_valid():
		_test_quest_content(registry)
		_test_global_rules(registry)
		_test_speakers(registry)
		_test_fallbacks(registry)
		_test_in_memory_mutation(registry)
		_test_override_lifecycle(registry)

	if _failures.is_empty():
		print("[PASS] LLM dialogue content registry tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_quest_content(registry: LLMDialogueContentRegistry) -> void:
	var agents := ["zenith", "aurelia", "vanguard", "neutral"]
	var types := ["KILL_SHIPS", "DELIVER_ORE", "PICKUP_SPECIAL"]
	for objective_type in types:
		var constraints := registry.quest_dummy_constraints(objective_type)
		_expect(
			not constraints.strip_edges().is_empty(),
			"Missing dummy_constraints for %s." % objective_type
		)
		for agent in agents:
			var bundle := registry.quest_examples(agent, objective_type)
			var dialogues: Array = bundle.get("dialogues", [])
			_expect(
				dialogues.size() >= 3,
				"Expected >=3 example dialogues for %s/%s, got %d." % [agent, objective_type, dialogues.size()]
			)
			_expect(
				not str(bundle.get("response_1", "")).is_empty()
				and not str(bundle.get("response_2", "")).is_empty()
				and not str(bundle.get("response_3", "")).is_empty(),
				"Missing choice responses for %s/%s." % [agent, objective_type]
			)
			# No non-Kaelen example bucket may say "Shiny" — that word is Kaelen's.
			for line in dialogues:
				_expect(
					not str(line).contains("Shiny"),
					"'Shiny' leaked into non-Kaelen example (%s/%s): %s" % [agent, objective_type, line]
				)

	# KILL_SHIPS must still steer the enemy dummy name and count.
	var kill := registry.quest_dummy_constraints("KILL_SHIPS")
	_expect(kill.contains("Slithern"), "KILL_SHIPS dummy_constraints lost the Slithern enemy name.")
	_expect(kill.contains("3 ships"), "KILL_SHIPS dummy_constraints lost the 3-ships count.")


func _test_global_rules(registry: LLMDialogueContentRegistry) -> void:
	var rules := registry.global_non_kaelen_rules()
	_expect(
		rules.get("kaelen_only_words", []).has("Shiny"),
		"Shiny must be listed as a Kaelen-only word."
	)
	_expect(
		rules.get("banned_non_kaelen_phrases", []).has("Shiny"),
		"Shiny must be banned for non-Kaelen speakers."
	)
	_expect(
		rules.get("allowed_rare_non_kaelen_addresses", []).has("Indy"),
		"Indy should be an allowed-but-rare non-Kaelen address."
	)


func _test_speakers(registry: LLMDialogueContentRegistry) -> void:
	# Kaelen owns Shiny + the Bella voice; other speakers must not.
	_expect(
		registry.speaker_address_rule("kaelen").contains("Shiny"),
		"Kaelen's address rule should mention Shiny."
	)
	for other in ["faction_agent", "mechanic", "lounge_local", "enemy_pilot"]:
		_expect(
			not registry.speaker_address_rule(other).contains("Shiny")
			or registry.speaker_address_rule(other).contains("Never"),
			"Non-Kaelen speaker '%s' must not be told to use Shiny." % other
		)


func _test_fallbacks(registry: LLMDialogueContentRegistry) -> void:
	# Unknown sections resolve to empty so callers use their built-in fallback.
	_expect(
		registry.quest_examples("neutral", "NONEXISTENT_TYPE").is_empty(),
		"Unknown mission type should return an empty bundle."
	)
	_expect(
		registry.quest_dummy_constraints("NONEXISTENT_TYPE").is_empty(),
		"Unknown mission type should return empty dummy constraints."
	)
	_expect(
		registry.quest_examples("unknown_agent", "KILL_SHIPS").is_empty(),
		"Unknown agent key should return an empty bundle."
	)


func _test_in_memory_mutation(registry: LLMDialogueContentRegistry) -> void:
	# set_quest_content mutates the live instance (used by the DevPanel "Apply"
	# button); reload() restores from disk. This test never writes to disk.
	registry.set_quest_content(
		"zenith",
		"KILL_SHIPS",
		["EDIT_MARKER dialogue, George. 3 Slithern ships."],
		"r1", "r2", "r3",
		"EDIT_MARKER constraints "
	)
	var edited := registry.quest_examples("zenith", "KILL_SHIPS")
	_expect(
		str(edited.get("dialogues", [""])[0]).contains("EDIT_MARKER"),
		"set_quest_content did not update the live bundle."
	)
	_expect(
		registry.quest_dummy_constraints("KILL_SHIPS").contains("EDIT_MARKER"),
		"set_quest_content did not update dummy_constraints."
	)
	registry.reload()
	_expect(
		not str(registry.quest_examples("zenith", "KILL_SHIPS").get("dialogues", [""])[0]).contains("EDIT_MARKER"),
		"reload() did not discard in-memory edits."
	)


func _test_override_lifecycle(registry: LLMDialogueContentRegistry) -> void:
	# Full delta path: edit -> save (writes override file) -> reload (delta merges
	# over base) -> toggle off (base) -> toggle on (delta) -> discard (file gone,
	# base restored). Writes/deletes the real override file, so it cleans up.
	registry.discard_override()  # start clean
	registry.set_quest_content(
		"aurelia", "DELIVER_ORE",
		["OVR_MARKER line, George. 25 m³ of ore."],
		"a", "b", "c", "OVR_MARKER constraints "
	)
	var save_result := registry.save()
	_expect(save_result.is_valid(), "Override save failed: %s" % save_result.summary())
	_expect(registry.has_override(), "has_override() should be true after save.")

	registry.reload()
	_expect(
		str(registry.quest_examples("aurelia", "DELIVER_ORE").get("dialogues", [""])[0]).contains("OVR_MARKER"),
		"Override delta did not survive reload / merge over base."
	)
	# A bucket NOT in the override must still come from the base untouched.
	_expect(
		not str(registry.quest_examples("zenith", "DELIVER_ORE").get("dialogues", [""])[0]).contains("OVR_MARKER"),
		"Override delta leaked into an unedited bucket."
	)

	registry.set_override_enabled(false)
	_expect(
		not str(registry.quest_examples("aurelia", "DELIVER_ORE").get("dialogues", [""])[0]).contains("OVR_MARKER"),
		"Override OFF should show the base bucket."
	)
	registry.set_override_enabled(true)
	_expect(
		str(registry.quest_examples("aurelia", "DELIVER_ORE").get("dialogues", [""])[0]).contains("OVR_MARKER"),
		"Override ON should show the edited bucket."
	)

	registry.discard_override()
	_expect(not registry.has_override(), "discard_override() should clear the delta.")
	_expect(
		not FileAccess.file_exists(LLMDialogueContentRegistry.OVERRIDE_PATH),
		"discard_override() should delete the override file."
	)
	_expect(
		not str(registry.quest_examples("aurelia", "DELIVER_ORE").get("dialogues", [""])[0]).contains("OVR_MARKER"),
		"discard_override() should restore the base bucket."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
