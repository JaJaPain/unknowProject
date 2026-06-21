extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var registry := GameContentRegistry.shared()
	_expect(
		registry.is_valid(),
		"Content registry failed: %s" % JSON.stringify(registry.validation.to_dict())
	)
	if registry.is_valid():
		_expect(registry.factions.size() >= 8, "Expected at least 8 factions, got %d." % registry.factions.size())
		_expect(registry.npcs.size() >= 12, "Expected at least 12 handcrafted NPCs, got %d." % registry.npcs.size())
		_expect(registry.voices.size() >= 13, "Expected at least 13 voice profiles, got %d." % registry.voices.size())
		_expect(registry.ships.size() >= 13, "Expected at least 13 ship designs, got %d." % registry.ships.size())
		_expect(registry.portraits.size() >= 100, "Expected at least 100 portraits, got %d." % registry.portraits.size())
		_expect(registry.faction("reavers").classification == "minor", "Minor faction alias failed.")
		_expect(registry.faction("faction.zenith").display_name == "Zenith", "Canonical faction lookup failed.")
		_expect(registry.npc_by_name("Jenna Kross").id == &"npc.jenna_kross", "NPC display-name lookup failed.")
		_expect(registry.npcs[&"npc.kaelen"].protected, "Kaelen must be protected.")
		_expect(
			registry.faction("zenith").agent_npc_id == &"npc.agent.zenith",
			"Faction agent reference failed."
		)
		_expect(registry.portrait_texture("portrait.minor_npc_02.jenna_kross") != null, "2x2 portrait did not resolve.")
		_expect(registry.portrait_texture("portrait.p001.01") != null, "Imported 5x5 portrait did not resolve.")
		_expect(not registry.ship_path("zenith", "Gunner").is_empty(), "Ship path lookup failed.")
		_expect(registry.provider_voice("voice.kaelen.v1").get("provider_voice", "") == "af_bella", "Voice provider mapping failed.")
		_expect(
			registry.voices[&"voice.kaelen.v1"].fallback_voice_profile_id
			== &"voice.neutral.v1",
			"Voice fallback reference failed."
		)

	if _failures.is_empty():
		print("[PASS] Game content registry tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
