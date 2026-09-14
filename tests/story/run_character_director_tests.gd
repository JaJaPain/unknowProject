extends SceneTree

const CharacterDirectorType := preload("res://scripts/story/CharacterDirector.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_deterministic_complete_cards()
	_test_recent_combinations_are_avoided_when_possible()

	if _failures.is_empty():
		print("[PASS] Character director tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_deterministic_complete_cards() -> void:
	var source := {
		"id": "npc.gen.fixture.mara",
		"job_role": "Dock controller",
	}
	var first: Dictionary = CharacterDirectorType.generate_card(
		source,
		"campaign.seed.alpha"
	)
	var second: Dictionary = CharacterDirectorType.generate_card(
		source,
		"campaign.seed.alpha"
	)
	_expect(bool(first.get("ok", false)), first.get("error", ""))
	_expect(bool(second.get("ok", false)), second.get("error", ""))
	var first_card: Dictionary = first.get("card", {})
	var second_card: Dictionary = second.get("card", {})
	_expect(
		first_card == second_card,
		"CharacterDirector did not produce deterministic cards for seed + NPC ID."
	)
	_expect(
		CharacterDirectorType.is_complete_card(first_card),
		"Generated character card is incomplete."
	)
	var voice_rules: Dictionary = first_card.get("voice_rules", {})
	_expect(
		(voice_rules.get("banned_tics", []) as Array).has("Shiny"),
		"Generated character card did not preserve protected banned tics."
	)


func _test_recent_combinations_are_avoided_when_possible() -> void:
	var source := {
		"id": "npc.gen.fixture.toma",
		"job_role": "Station broker",
	}
	var first: Dictionary = CharacterDirectorType.generate_card(
		source,
		"campaign.seed.beta"
	)
	_expect(bool(first.get("ok", false)), first.get("error", ""))
	var first_key := str(first.get("card", {}).get("trait_combination_key", ""))
	var avoided: Dictionary = CharacterDirectorType.generate_card(
		source,
		"campaign.seed.beta",
		[first_key]
	)
	_expect(bool(avoided.get("ok", false)), avoided.get("error", ""))
	var avoided_key := str(avoided.get("card", {}).get("trait_combination_key", ""))
	_expect(
		not avoided_key.is_empty() and avoided_key != first_key,
		"CharacterDirector reused a recent trait combination when alternatives existed."
	)
	_expect(
		CharacterDirectorType.is_complete_card(avoided.get("card", {})),
		"Recent-combination retry produced an incomplete card."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
