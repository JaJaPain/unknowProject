class_name SystemDefinition
extends DomainDefinition

const SUPPORTED_SCHEMA_VERSION := 1

var legacy_id: String = ""
var display_name: String = ""
var scene_path: String = ""
var origin: String = ""
var tags: Array[String] = []
var station_ids: Array[StringName] = []
var faction_ids: Array[StringName] = []
var gates: Array[GateDefinition] = []


func load_from_dict(data: Dictionary) -> ValidationResult:
	var result := load_common(data, "system", SUPPORTED_SCHEMA_VERSION)
	legacy_id = str(data.get("legacy_id", ""))
	display_name = str(data.get("display_name", "")).strip_edges()
	scene_path = str(data.get("scene_path", "")).strip_edges()
	origin = str(data.get("origin", "")).strip_edges()

	if legacy_id.is_empty():
		result.add_error(
			"missing_legacy_id",
			"System requires a runtime legacy_id during Phase 1.",
			"legacy_id"
		)
	if display_name.is_empty():
		result.add_error(
			"missing_display_name",
			"System requires a display name.",
			"display_name"
		)
	if scene_path.is_empty():
		result.add_error(
			"missing_scene_path",
			"System requires a scene path.",
			"scene_path"
		)
	elif scene_path != "generated" and not ResourceLoader.exists(scene_path, "PackedScene"):
		result.add_error(
			"scene_not_found",
			"System scene does not exist or is not a PackedScene.",
			"scene_path"
		)
	if origin not in ["authored", "generated"]:
		result.add_error(
			"invalid_origin",
			"System origin must be 'authored' or 'generated'.",
			"origin"
		)

	_load_string_array(data, "tags", tags, result)
	_load_id_array(data, "station_ids", "station", station_ids, result)
	_load_id_array(data, "faction_ids", "faction", faction_ids, result)
	_load_gates(data, result)
	return result


func get_gate(gate_id: Variant) -> GateDefinition:
	var canonical := DomainId.canonicalize(gate_id)
	for gate in gates:
		if gate.id == canonical or gate.legacy_id == str(gate_id):
			return gate
	return null


func to_dict() -> Dictionary:
	var gate_data: Array[Dictionary] = []
	for gate in gates:
		gate_data.append(gate.to_dict())
	var data := to_common_dict()
	data.merge({
		"legacy_id": legacy_id,
		"display_name": display_name,
		"scene_path": scene_path,
		"origin": origin,
		"tags": tags.duplicate(),
		"station_ids": _string_names_to_strings(station_ids),
		"faction_ids": _string_names_to_strings(faction_ids),
		"gates": gate_data,
	})
	return data


func _load_gates(data: Dictionary, result: ValidationResult) -> void:
	var raw_gates: Variant = data.get("gates", [])
	if not raw_gates is Array:
		result.add_error("invalid_type", "gates must be an array.", "gates")
		return
	var seen_ids: Dictionary = {}
	var seen_legacy_ids: Dictionary = {}
	for index in range(raw_gates.size()):
		var raw_gate: Variant = raw_gates[index]
		if not raw_gate is Dictionary:
			result.add_error(
				"invalid_type",
				"Gate entry must be an object.",
				"gates.%d" % index
			)
			continue
		var gate := GateDefinition.new()
		var gate_result := gate.load_from_dict(raw_gate, id)
		result.merge(gate_result, "gates.%d" % index)
		if not gate_result.is_valid():
			continue
		if seen_ids.has(gate.id):
			result.add_error(
				"duplicate_gate_id",
				"Duplicate gate ID '%s'." % gate.id,
				"gates.%d.id" % index
			)
			continue
		if seen_legacy_ids.has(gate.legacy_id):
			result.add_error(
				"duplicate_legacy_gate_id",
				"Duplicate legacy gate ID '%s'." % gate.legacy_id,
				"gates.%d.legacy_id" % index
			)
			continue
		seen_ids[gate.id] = true
		seen_legacy_ids[gate.legacy_id] = true
		gates.append(gate)


static func _load_string_array(
	data: Dictionary,
	key: String,
	output: Array[String],
	result: ValidationResult
) -> void:
	var raw: Variant = data.get(key, [])
	if not raw is Array:
		result.add_error("invalid_type", "%s must be an array." % key, key)
		return
	for index in range(raw.size()):
		var value := str(raw[index]).strip_edges()
		if value.is_empty():
			result.add_error(
				"empty_value",
				"%s entry cannot be empty." % key,
				"%s.%d" % [key, index]
			)
		else:
			output.append(value)


static func _load_id_array(
	data: Dictionary,
	key: String,
	expected_namespace: String,
	output: Array[StringName],
	result: ValidationResult
) -> void:
	var raw: Variant = data.get(key, [])
	if not raw is Array:
		result.add_error("invalid_type", "%s must be an array." % key, key)
		return
	var seen: Dictionary = {}
	for index in range(raw.size()):
		var value := DomainId.canonicalize(raw[index])
		var error := DomainId.validation_error(value, expected_namespace)
		if not error.is_empty():
			result.add_error(
				"invalid_reference",
				error,
				"%s.%d" % [key, index]
			)
		elif seen.has(value):
			result.add_error(
				"duplicate_reference",
				"Duplicate reference '%s'." % value,
				"%s.%d" % [key, index]
			)
		else:
			seen[value] = true
			output.append(value)


static func _string_names_to_strings(values: Array[StringName]) -> Array[String]:
	var output: Array[String] = []
	for value in values:
		output.append(str(value))
	return output
