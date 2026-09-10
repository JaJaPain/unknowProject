extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var registry := SystemRegistry.load_default()
	_expect(
		registry.is_valid(),
		"Default registry failed validation: %s" %
		JSON.stringify(registry.validation.to_dict())
	)
	if registry.is_valid():
		_test_resolution(registry)
		_test_scene_gate_metadata(registry)
		_test_main_scene_has_no_embedded_system()
	_test_invalid_pair()
	_test_unknown_destination()
	_test_missing_scene()
	_test_duplicate_legacy_alias()

	if _failures.is_empty():
		print("[PASS] System registry tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_resolution(registry: SystemRegistry) -> void:
	_expect(
		registry.resolve_system_id("start_system") == &"system.start",
		"Legacy start-system ID did not resolve."
	)
	_expect(
		registry.resolve_gate_id("start_to_test") == &"gate.start.to_test",
		"Legacy outbound gate ID did not resolve."
	)
	_expect(
		registry.load_scene("system.start") != null,
		"Canonical start-system scene did not load."
	)


func _test_scene_gate_metadata(registry: SystemRegistry) -> void:
	for system: SystemDefinition in registry.systems.values():
		var packed := registry.load_scene(system.id)
		if packed == null:
			_failures.append("Scene missing for '%s'." % system.id)
			continue
		var root := packed.instantiate()
		var scene_gates: Dictionary = {}
		_collect_scene_gates(root, scene_gates)
		for gate in system.gates:
			_expect(
				scene_gates.has(gate.legacy_id),
				"Scene for '%s' is missing gate '%s'." % [
					system.id,
					gate.legacy_id,
				]
			)
			if not scene_gates.has(gate.legacy_id):
				continue
			var scene_gate: Node = scene_gates[gate.legacy_id]
			_expect(
				registry.resolve_system_id(
					scene_gate.get("destination_system_id")
				) == gate.destination_system_id,
				"Scene destination system differs for '%s'." % gate.id
			)
			_expect(
				registry.resolve_gate_id(
					scene_gate.get("destination_gate_id")
				) == gate.destination_gate_id,
				"Scene destination gate differs for '%s'." % gate.id
			)
		_expect(
			scene_gates.size() == system.gates.size(),
			"Scene and registry gate counts differ for '%s'." % system.id
		)
		root.free()


func _test_main_scene_has_no_embedded_system() -> void:
	var main_scene := FileAccess.get_file_as_string("res://scenes/main.tscn")
	_expect(
		not main_scene.contains("res://scenes/systems/"),
		"Main scene embeds a system instead of using SystemRegistry."
	)


func _test_invalid_pair() -> void:
	var data := _minimal_registry_data()
	data["systems"][1]["gates"][0]["destination_gate_id"] = (
		"gate.test.to_start"
	)
	var registry := SystemRegistry.load_from_dict(data)
	_expect(
		not registry.is_valid(),
		"Non-reciprocal gate pair should fail validation."
	)


func _test_unknown_destination() -> void:
	var data := _minimal_registry_data()
	data["systems"][0]["gates"][0]["destination_system_id"] = (
		"system.missing"
	)
	var registry := SystemRegistry.load_from_dict(data)
	_expect(
		not registry.is_valid(),
		"Unknown destination system should fail validation."
	)


func _test_missing_scene() -> void:
	var data := _minimal_registry_data()
	data["systems"][0]["scene_path"] = "res://scenes/systems/missing.tscn"
	var registry := SystemRegistry.load_from_dict(data)
	_expect(
		not registry.is_valid(),
		"Missing system scene should fail validation."
	)


func _test_duplicate_legacy_alias() -> void:
	var data := _minimal_registry_data()
	data["systems"][1]["legacy_id"] = "start_system"
	var registry := SystemRegistry.load_from_dict(data)
	_expect(
		not registry.is_valid(),
		"Duplicate legacy system alias should fail validation."
	)


func _minimal_registry_data() -> Dictionary:
	return {
		"schema_version": 1,
		"systems": [
			{
				"id": "system.start",
				"schema_version": 1,
				"legacy_id": "start_system",
				"display_name": "Start",
				"scene_path": "res://scenes/systems/system_start.tscn",
				"origin": "authored",
				"tags": [],
				"station_ids": [],
				"faction_ids": [],
				"gates": [{
					"id": "gate.start.to_test",
					"schema_version": 1,
					"legacy_id": "start_to_test",
					"display_name": "Outbound",
					"destination_system_id": "system.test",
					"destination_gate_id": "gate.test.to_start",
				}],
			},
			{
				"id": "system.test",
				"schema_version": 1,
				"legacy_id": "test_system",
				"display_name": "Test",
				"scene_path": "res://scenes/systems/system_test.tscn",
				"origin": "authored",
				"tags": [],
				"station_ids": [],
				"faction_ids": [],
				"gates": [{
					"id": "gate.test.to_start",
					"schema_version": 1,
					"legacy_id": "test_to_start",
					"display_name": "Return",
					"destination_system_id": "system.start",
					"destination_gate_id": "gate.start.to_test",
				}],
			},
		],
	}


func _collect_scene_gates(node: Node, output: Dictionary) -> void:
	if node.is_in_group("jumpgate"):
		output[str(node.get("gate_id"))] = node
	for child in node.get_children():
		_collect_scene_gates(child, output)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
