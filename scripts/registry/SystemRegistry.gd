class_name SystemRegistry
extends RefCounted

const DEFAULT_PATH := "res://data/systems/system_registry.json"
const SUPPORTED_SCHEMA_VERSION := 1

var systems: Dictionary = {}
var gates: Dictionary = {}
var system_aliases: Dictionary = {}
var gate_aliases: Dictionary = {}
var validation := ValidationResult.new()


static func load_default() -> SystemRegistry:
	return load_from_path(DEFAULT_PATH)


static func load_from_path(path: String) -> SystemRegistry:
	var registry := SystemRegistry.new()
	var parsed := DomainJson.read_object(path)
	registry.validation.merge(parsed["validation"])
	if registry.validation.is_valid():
		registry._load_from_dict(parsed["data"])
	return registry


static func load_from_dict(data: Dictionary) -> SystemRegistry:
	var registry := SystemRegistry.new()
	registry._load_from_dict(data)
	return registry


func is_valid() -> bool:
	return validation.is_valid()


func has_system(system_id: Variant) -> bool:
	return get_system(system_id) != null


func get_system(system_id: Variant) -> SystemDefinition:
	var canonical := resolve_system_id(system_id)
	return systems.get(canonical) as SystemDefinition


func get_gate(gate_id: Variant) -> GateDefinition:
	var canonical := resolve_gate_id(gate_id)
	return gates.get(canonical) as GateDefinition


func resolve_system_id(system_id: Variant) -> StringName:
	var raw := str(system_id)
	if system_aliases.has(raw):
		return system_aliases[raw]
	return DomainId.canonicalize(raw)


func resolve_gate_id(gate_id: Variant) -> StringName:
	var raw := str(gate_id)
	if gate_aliases.has(raw):
		return gate_aliases[raw]
	return DomainId.canonicalize(raw)


func runtime_system_id(system_id: Variant) -> String:
	var definition := get_system(system_id)
	return definition.legacy_id if definition else ""


func runtime_gate_id(gate_id: Variant) -> String:
	var definition := get_gate(gate_id)
	return definition.legacy_id if definition else ""


func load_scene(system_id: Variant) -> PackedScene:
	var definition := get_system(system_id)
	if definition == null:
		return null
	return load(definition.scene_path) as PackedScene


func _load_from_dict(data: Dictionary) -> void:
	var raw_version: Variant = data.get("schema_version", null)
	if raw_version == null \
			or (not raw_version is int and not raw_version is float) \
			or (raw_version is float and not is_equal_approx(
				float(raw_version),
				floorf(float(raw_version))
			)):
		validation.add_error(
			"invalid_registry_schema",
			"Registry schema_version must be a whole number.",
			"schema_version"
		)
	elif int(raw_version) != SUPPORTED_SCHEMA_VERSION:
		validation.add_error(
			"unsupported_registry_schema",
			"Registry schema version %d is unsupported; expected %d." % [
				int(raw_version),
				SUPPORTED_SCHEMA_VERSION,
			],
			"schema_version"
		)

	var raw_systems: Variant = data.get("systems", null)
	if not raw_systems is Array:
		validation.add_error(
			"invalid_systems",
			"Registry systems must be an array.",
			"systems"
		)
		return

	for index in range(raw_systems.size()):
		var raw_system: Variant = raw_systems[index]
		if not raw_system is Dictionary:
			validation.add_error(
				"invalid_system",
				"System entry must be an object.",
				"systems.%d" % index
			)
			continue
		var definition := SystemDefinition.new()
		var result := definition.load_from_dict(raw_system)
		validation.merge(result, "systems.%d" % index)
		if not result.is_valid():
			continue
		_register_system(definition, index)

	_validate_gate_destinations()
	_validate_gate_pairs()


func _register_system(definition: SystemDefinition, index: int) -> void:
	if systems.has(definition.id):
		validation.add_error(
			"duplicate_system_id",
			"Duplicate system ID '%s'." % definition.id,
			"systems.%d.id" % index
		)
		return
	if system_aliases.has(definition.legacy_id):
		validation.add_error(
			"duplicate_legacy_system_id",
			"Duplicate legacy system ID '%s'." % definition.legacy_id,
			"systems.%d.legacy_id" % index
		)
		return
	systems[definition.id] = definition
	system_aliases[definition.legacy_id] = definition.id
	system_aliases[str(definition.id)] = definition.id

	for gate in definition.gates:
		if gates.has(gate.id):
			validation.add_error(
				"duplicate_gate_id",
				"Duplicate gate ID '%s' across systems." % gate.id,
				"systems.%d.gates" % index
			)
			continue
		if gate_aliases.has(gate.legacy_id):
			validation.add_error(
				"duplicate_legacy_gate_id",
				"Duplicate legacy gate ID '%s' across systems." % gate.legacy_id,
				"systems.%d.gates" % index
			)
			continue
		gates[gate.id] = gate
		gate_aliases[gate.legacy_id] = gate.id
		gate_aliases[str(gate.id)] = gate.id


func _validate_gate_destinations() -> void:
	for gate: GateDefinition in gates.values():
		if not systems.has(gate.destination_system_id):
			validation.add_error(
				"unknown_destination_system",
				"Gate '%s' references unknown system '%s'." % [
					gate.id,
					gate.destination_system_id,
				],
				str(gate.id)
			)
		if not gates.has(gate.destination_gate_id):
			validation.add_error(
				"unknown_destination_gate",
				"Gate '%s' references unknown gate '%s'." % [
					gate.id,
					gate.destination_gate_id,
				],
				str(gate.id)
			)


func _validate_gate_pairs() -> void:
	for gate: GateDefinition in gates.values():
		var destination := gates.get(
			gate.destination_gate_id
		) as GateDefinition
		if destination == null:
			continue
		if destination.system_id != gate.destination_system_id:
			validation.add_error(
				"destination_gate_wrong_system",
				"Gate '%s' points to gate '%s' in the wrong system." % [
					gate.id,
					destination.id,
				],
				str(gate.id)
			)
		if destination.destination_system_id != gate.system_id \
				or destination.destination_gate_id != gate.id:
			validation.add_error(
				"unpaired_gate",
				"Gate '%s' and '%s' are not a reciprocal pair." % [
					gate.id,
					destination.id,
				],
				str(gate.id)
			)
