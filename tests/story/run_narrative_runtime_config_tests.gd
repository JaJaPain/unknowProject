extends SceneTree

const NarrativeRuntimeConfigType := preload("res://scripts/story/NarrativeRuntimeConfig.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_defaults_are_disabled()
	_test_flags_are_independent()
	_test_unknown_flags_are_rejected()

	if _failures.is_empty():
		print("[PASS] Narrative runtime config tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_defaults_are_disabled() -> void:
	var config = NarrativeRuntimeConfigType.new()
	config.reset()
	var flags := config.snapshot()
	_expect(flags.size() == NarrativeRuntimeConfigType.FLAG_NAMES.size(), "Expected every rollout flag.")
	for flag_name in NarrativeRuntimeConfigType.FLAG_NAMES:
		_expect(not config.is_enabled(flag_name), "%s should default to disabled." % flag_name)


func _test_flags_are_independent() -> void:
	var config = NarrativeRuntimeConfigType.new()
	config.reset()
	_expect(config.set_enabled("mission_director_v2", true), "Known flag was not accepted.")
	_expect(config.is_enabled("mission_director_v2"), "Enabled flag did not remain enabled.")
	_expect(not config.is_enabled("narrative_metadata_v2"), "Enabling one flag changed another.")
	_expect(not config.is_enabled("conversation_bundle_v2"), "Enabling one flag changed another.")
	config.reset()
	_expect(not config.is_enabled("mission_director_v2"), "Reset did not restore disabled defaults.")


func _test_unknown_flags_are_rejected() -> void:
	var config = NarrativeRuntimeConfigType.new()
	config.reset()
	_expect(not config.set_enabled("not_a_narrative_flag", true), "Unknown flag was accepted.")
	_expect(not config.is_enabled("not_a_narrative_flag"), "Unknown flag became enabled.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
