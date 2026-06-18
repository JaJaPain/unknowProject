extends SceneTree

const GeneratedGateBuilderType := preload(
	"res://scripts/navigation/GeneratedGateBuilder.gd"
)

var _failures: Array[String] = []


func _initialize() -> void:
	_test_config_from_seed()
	_test_config_deterministic()
	_test_config_faction_weights()
	_test_config_difficulty_multiplier()
	_test_config_npc_count()
	_test_campaign_system_names()
	_test_registry_generated_system()
	_test_generated_outbound_gate_defs()

	if _failures.is_empty():
		print("[PASS] System factory tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_config_from_seed() -> void:
	var config := SystemConfig.from_seed("Test Nebula", "system.gen.test", 12345)
	_expect(config.system_name == "Test Nebula", "Config name mismatch.")
	_expect(config.system_id == "system.gen.test", "Config id mismatch.")
	_expect(config.legacy_id == "system_gen_test", "Config legacy_id mismatch: '%s'" % config.legacy_id)
	_expect(config.seed_value == 12345, "Config seed mismatch.")
	_expect(config.star_type in ["yellow", "blue", "orange", "red", "white"], "Unknown star type: %s" % config.star_type)
	_expect(config.planet_count_min >= 1, "Planet min too low.")
	_expect(config.planet_count_max >= config.planet_count_min, "Planet max < min.")
	_expect(config.station_count >= 1, "Station count too low.")


func _test_config_deterministic() -> void:
	var config1 := SystemConfig.from_seed("Beta", "system.gen.beta", 42)
	var config2 := SystemConfig.from_seed("Beta", "system.gen.beta", 42)
	_expect(config1.star_type == config2.star_type, "Same seed produced different star types.")
	_expect(config1.planet_count_max == config2.planet_count_max, "Same seed produced different planet counts.")
	_expect(config1.station_count == config2.station_count, "Same seed produced different station counts.")
	_expect(config1.star_color == config2.star_color, "Same seed produced different star colors.")
	_expect(config1.ambient_energy == config2.ambient_energy, "Same seed produced different ambient energy.")


func _test_config_faction_weights() -> void:
	var valid_factions := [
		"zenith",
		"aurelia",
		"vanguard",
		"reavers",
		"obsidian",
		"dustborn",
		"wraiths",
		"ironclad",
	]
	var found_local := false
	for seed_val in [100, 200, 300, 400, 500]:
		var config := SystemConfig.from_seed("FW_%d" % seed_val, "system.gen.fw%d" % seed_val, seed_val)
		_expect(not config.faction_weights.is_empty(), "Seed %d: faction_weights is empty." % seed_val)
		var weight_sum := 0.0
		for faction_name: String in config.faction_weights:
			_expect(faction_name in valid_factions, "Seed %d: invalid faction '%s'." % [seed_val, faction_name])
			if faction_name not in ["zenith", "aurelia", "vanguard"]:
				found_local = true
			weight_sum += float(config.faction_weights[faction_name])
		_expect(absf(weight_sum - 1.0) < 0.01, "Seed %d: faction weights sum to %.3f, not 1.0." % [seed_val, weight_sum])
	_expect(found_local, "Generated faction weights did not include local factions.")


func _test_config_difficulty_multiplier() -> void:
	var found_tiers: Dictionary = {}
	for seed_val in range(1, 200):
		var config := SystemConfig.from_seed("DM", "system.gen.dm%d" % seed_val, seed_val)
		found_tiers[config.difficulty_tier] = config.difficulty_multiplier
	_expect(found_tiers.has(1), "Never generated tier 1.")
	_expect(found_tiers.has(2), "Never generated tier 2.")
	_expect(found_tiers.has(3), "Never generated tier 3.")
	if found_tiers.has(1):
		_expect(absf(float(found_tiers[1]) - 1.0) < 0.01, "Tier 1 multiplier wrong: %.2f" % float(found_tiers[1]))
	if found_tiers.has(2):
		_expect(absf(float(found_tiers[2]) - 1.15) < 0.01, "Tier 2 multiplier wrong: %.2f" % float(found_tiers[2]))
	if found_tiers.has(3):
		_expect(absf(float(found_tiers[3]) - 1.30) < 0.01, "Tier 3 multiplier wrong: %.2f" % float(found_tiers[3]))


func _test_config_npc_count() -> void:
	for seed_val in [10, 20, 30]:
		var config := SystemConfig.from_seed("NPC", "system.gen.npc%d" % seed_val, seed_val)
		_expect(config.npc_patrol_count >= 6, "Seed %d: npc_patrol_count too low: %d" % [seed_val, config.npc_patrol_count])
		_expect(config.npc_patrol_count <= 8, "Seed %d: npc_patrol_count too high: %d" % [seed_val, config.npc_patrol_count])
		_expect(config.npc_patrol_count == 5 + config.difficulty_tier, "Seed %d: npc_patrol_count doesn't match formula." % seed_val)


func _test_campaign_system_names() -> void:
	var names := CampaignSystemNames.new()
	names.set_names(["Apex", "Bravo", "Crest"] as Array[String])
	_expect(names.remaining() == 3, "remaining() wrong after set_names.")
	_expect(names.peek_next() == "Apex", "peek_next() didn't return first name.")
	var first := names.next_name()
	_expect(first == "Apex", "next_name() didn't return first name.")
	_expect(names.remaining() == 2, "remaining() wrong after next_name().")
	var second := names.next_name()
	_expect(second == "Bravo", "next_name() didn't return second name.")
	var third := names.next_name()
	_expect(third == "Crest", "next_name() didn't return third name.")
	var overflow := names.next_name()
	_expect(overflow == "Uncharted System 4", "Overflow name didn't use fallback pattern: '%s'" % overflow)
	var second_overflow := names.next_name()
	_expect(second_overflow == "Uncharted System 5", "Overflow name did not advance: '%s'" % second_overflow)


func _test_registry_generated_system() -> void:
	var registry := SystemRegistry.load_default()
	if not registry.is_valid():
		_expect(false, "Default registry invalid, cannot test generated registration.")
		return
	var config := SystemConfig.from_seed("Gamma Station", "system.gen.gamma", 7777)
	registry.set_generated_config("system.gen.gamma", config)
	registry.set_generated_config(config.legacy_id, config)

	var result := registry.register_generated_system(
		{
			"id": "system.gen.gamma",
			"legacy_id": config.legacy_id,
			"display_name": "Gamma Station",
			"station_ids": [],
			"faction_ids": [],
		},
		[{
			"id": "gate.gen.gamma.to_start",
			"legacy_id": "gen_gamma_to_start",
			"display_name": "Gamma Return Gate",
			"destination_system_id": "system.start",
			"destination_gate_id": "gate.start.to_test",
			"initial_state": "known",
			"discovery_action": "",
			"discovery_cost": {},
			"discovery_prerequisites": [],
		}]
	)
	_expect(result.is_valid(), "register_generated_system failed: %s" % result.summary())
	_expect(registry.has_system("system.gen.gamma"), "Generated system not found after registration.")
	var sys_def := registry.get_system("system.gen.gamma")
	_expect(sys_def != null, "get_system returned null for generated system.")
	if sys_def:
		_expect(sys_def.display_name == "Gamma Station", "Generated system display_name wrong.")
		_expect(sys_def.scene_path == "generated", "Generated system scene_path wrong.")
		_expect(sys_def.gates.size() == 1, "Generated system gate count wrong.")

	var exported := registry.export_generated_systems()
	_expect(exported.size() == 1, "Generated system export count wrong.")
	var imported_registry := SystemRegistry.load_default()
	var import_result := imported_registry.import_generated_systems(exported)
	_expect(import_result.is_valid(), "Generated system import failed: %s" % import_result.summary())
	_expect(imported_registry.has_system("system.gen.gamma"), "Imported generated system not found.")
	var imported_gate := imported_registry.get_gate("gate.gen.gamma.to_start")
	_expect(imported_gate != null, "Imported generated gate not found.")

	var duplicate_result := registry.register_generated_system(
		{
			"id": "system.gen.gamma",
			"legacy_id": config.legacy_id,
			"display_name": "Gamma Duplicate",
			"station_ids": [],
			"faction_ids": [],
		},
		[]
	)
	_expect(not duplicate_result.is_valid(), "Duplicate registration should fail.")


func _test_generated_outbound_gate_defs() -> void:
	var config := SystemConfig.from_seed("Delta", "system.gen.delta", 9901)
	config.outbound_gate_count = 2
	var gates: Array[Dictionary] = GeneratedGateBuilderType.build_outbound_gate_defs(
		"system.gen.delta",
		"Delta",
		config
	)
	_expect(gates.size() == 2, "Outbound gate count did not match config.")
	if gates.size() != 2:
		return
	_expect(gates[0].get("id", "") == "gate.gen.delta.out_1", "First outbound gate id was not deterministic.")
	_expect(gates[1].get("id", "") == "gate.gen.delta.out_2", "Second outbound gate id was not deterministic.")
	_expect(gates[0].get("initial_state", "") == "unknown", "Outbound gate did not start unknown.")
	_expect(str(gates[0].get("destination_system_id", "")).begins_with("system.gen."), "Outbound gate destination was not a generated system id.")
	_expect(str(gates[0].get("destination_gate_id", "")).begins_with("gate.gen."), "Outbound gate return id was not generated.")
	_expect(gates[0].get("destination_system_id", "") != gates[1].get("destination_system_id", ""), "Outbound gates should point to different future systems.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
