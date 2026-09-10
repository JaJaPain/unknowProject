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


func get_all_systems() -> Array:
	return systems.values()


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
	if definition.scene_path == "generated":
		return null
	return load(definition.scene_path) as PackedScene


func instantiate_system(system_id: Variant) -> Node3D:
	var definition := get_system(system_id)
	if definition == null:
		return null
	if definition.scene_path == "generated":
		return _build_generated_root(definition)
	var packed := load(definition.scene_path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D


func register_generated_system(
	sys_data: Dictionary,
	gate_defs: Array[Dictionary]
) -> ValidationResult:
	var result := ValidationResult.new()
	var definition := SystemDefinition.new()
	definition.id = DomainId.canonicalize(sys_data.get("id", ""))
	definition.schema_version = SystemDefinition.SUPPORTED_SCHEMA_VERSION
	definition.legacy_id = str(sys_data.get("legacy_id", ""))
	definition.display_name = str(sys_data.get("display_name", ""))
	definition.scene_path = "generated"
	definition.origin = "generated"
	definition.tags = ["procedural"]
	for sid in sys_data.get("station_ids", []):
		definition.station_ids.append(DomainId.canonicalize(sid))
	for fid in sys_data.get("faction_ids", []):
		definition.faction_ids.append(DomainId.canonicalize(fid))

	for gate_data: Dictionary in gate_defs:
		var gate := GateDefinition.new()
		gate.id = DomainId.canonicalize(gate_data.get("id", ""))
		gate.schema_version = GateDefinition.SUPPORTED_SCHEMA_VERSION
		gate.legacy_id = str(gate_data.get("legacy_id", ""))
		gate.system_id = definition.id
		gate.display_name = str(gate_data.get("display_name", ""))
		gate.destination_system_id = DomainId.canonicalize(
			gate_data.get("destination_system_id", "")
		)
		gate.destination_gate_id = DomainId.canonicalize(
			gate_data.get("destination_gate_id", "")
		)
		gate.initial_state = str(gate_data.get("initial_state", "unknown"))
		gate.discovery_action = str(gate_data.get("discovery_action", "scan"))
		gate.discovery_cost = gate_data.get("discovery_cost", {})
		gate.discovery_prerequisites = gate_data.get("discovery_prerequisites", [])
		definition.gates.append(gate)
		if not gates.has(gate.id):
			gates[gate.id] = gate
			gate_aliases[gate.legacy_id] = gate.id
			gate_aliases[str(gate.id)] = gate.id

	if systems.has(definition.id):
		result.add_error("duplicate_system_id", "System '%s' already registered." % definition.id, "id")
		return result

	systems[definition.id] = definition
	system_aliases[definition.legacy_id] = definition.id
	system_aliases[str(definition.id)] = definition.id
	return result


func export_generated_systems() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for definition: SystemDefinition in systems.values():
		if definition.origin == "generated":
			var record := definition.to_dict()
			var config := _config_for_definition(definition)
			if config != null:
				record["config"] = config.to_dict()
			output.append(record)
	return output


func import_generated_systems(records: Variant) -> ValidationResult:
	var result := ValidationResult.new()
	if records == null:
		return result
	if not records is Array:
		result.add_error(
			"invalid_generated_systems",
			"Generated systems must be an array.",
			"generated_systems"
		)
		return result
	for index in range((records as Array).size()):
		var record: Variant = (records as Array)[index]
		if not record is Dictionary:
			result.add_error(
				"invalid_generated_system",
				"Generated system entry must be an object.",
				"generated_systems.%d" % index
			)
			continue
		var system_id := DomainId.canonicalize(record.get("id", ""))
		if systems.has(system_id):
			_import_generated_config(record)
			continue
		var gate_defs: Variant = record.get("gates", [])
		if not gate_defs is Array:
			result.add_error(
				"invalid_generated_gates",
				"Generated system gates must be an array.",
				"generated_systems.%d.gates" % index
			)
			continue
		var typed_gate_defs: Array[Dictionary] = []
		var gates_valid := true
		for gate_def in gate_defs:
			if gate_def is Dictionary:
				typed_gate_defs.append(gate_def)
			else:
				gates_valid = false
				result.add_error(
					"invalid_generated_gate",
					"Generated gate entry must be an object.",
					"generated_systems.%d.gates" % index
				)
		if not gates_valid:
			continue
		var registered := register_generated_system(record, typed_gate_defs)
		result.merge(registered, "generated_systems.%d" % index)
		if registered.is_valid():
			_import_generated_config(record)
	return result


var _generated_configs: Dictionary = {}


func set_generated_config(system_id: String, config: SystemConfig) -> void:
	_generated_configs[system_id] = config


func get_generated_config(system_id: String) -> SystemConfig:
	return _generated_configs.get(system_id) as SystemConfig


func _config_for_definition(definition: SystemDefinition) -> SystemConfig:
	var config: SystemConfig = _generated_configs.get(str(definition.id))
	if config == null:
		config = _generated_configs.get(definition.legacy_id)
	return config


func _import_generated_config(record: Dictionary) -> void:
	var raw_config: Variant = record.get("config", {})
	if not raw_config is Dictionary:
		return
	var config := SystemConfig.from_dict(raw_config)
	if config.system_id.is_empty():
		config.system_id = str(record.get("id", ""))
	if config.legacy_id.is_empty():
		config.legacy_id = str(record.get("legacy_id", ""))
	if config.system_name.is_empty():
		config.system_name = str(record.get("display_name", ""))
	set_generated_config(config.system_id, config)
	if not config.legacy_id.is_empty():
		set_generated_config(config.legacy_id, config)


func _build_generated_root(definition: SystemDefinition) -> Node3D:
	var config := _config_for_definition(definition)
	if config == null:
		push_error("[SystemRegistry] No config for generated system '%s'." % definition.id)
		return null
	var result := SystemFactory.generate(config)
	if not bool(result.get("ok", false)):
		return null
	var root: Node3D = result["root"]
	for gate in definition.gates:
		var rng := RandomNumberGenerator.new()
		rng.seed = config.seed_value + gate.id.hash()
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(500.0, 1200.0)
		var gate_pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var dest_sys := get_system(gate.destination_system_id)
		SystemFactory.add_gate_to_system(
			root,
			gate.legacy_id,
			str(gate.id),
			gate.display_name,
			runtime_system_id(gate.destination_system_id),
			runtime_gate_id(gate.destination_gate_id),
			dest_sys.display_name if dest_sys else "UNKNOWN",
			gate_pos,
			angle + PI
		)
	return root


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
			if not DomainId.is_generated(gate.destination_system_id):
				validation.add_error(
					"unknown_destination_system",
					"Gate '%s' references unknown system '%s'." % [
						gate.id,
						gate.destination_system_id,
					],
					str(gate.id)
				)
		if not gates.has(gate.destination_gate_id):
			if not DomainId.is_generated(gate.destination_gate_id):
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
