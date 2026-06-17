extends SceneTree

const DomainIdType := preload("res://scripts/domain/DomainId.gd")
const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)
const DomainDefinitionType := preload(
	"res://scripts/domain/DomainDefinition.gd"
)
const DomainJsonType := preload("res://scripts/domain/DomainJson.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_authored_ids()
	_test_generated_ids()
	_test_legacy_aliases()
	_test_validation_results()
	_test_definition_common_fields()
	_test_json_codec()

	if _failures.is_empty():
		print("[PASS] Domain foundation tests")
		quit(0)
		return

	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_authored_ids() -> void:
	_expect(
		DomainIdType.is_valid("system.start", "system"),
		"Readable authored system ID should be valid."
	)
	_expect(
		DomainIdType.is_valid("voice.kaelen.v1", "voice"),
		"Multi-segment voice ID should be valid."
	)
	for invalid_id in [
		"",
		"system",
		"System.start",
		"system..start",
		"system.start-system",
		" system.start",
	]:
		_expect(
			not DomainIdType.is_valid(invalid_id),
			"Invalid ID was accepted: '%s'." % invalid_id
		)
	_expect(
		not DomainIdType.is_valid("npc.kaelen", "faction"),
		"Namespace mismatch should fail."
	)


func _test_generated_ids() -> void:
	var generated := DomainIdType.build_generated(
		"npc",
		"campaign_01",
		"000042"
	)
	_expect(
		generated == &"npc.gen.campaign_01.000042",
		"Generated ID was not built deterministically."
	)
	_expect(
		DomainIdType.is_generated(generated),
		"Generated ID marker was not detected."
	)
	_expect(
		DomainIdType.build_generated("NPC", "bad", "key").is_empty(),
		"Invalid generated namespace should fail closed."
	)


func _test_legacy_aliases() -> void:
	_expect(
		DomainIdType.canonicalize("start_system") == &"system.start",
		"Legacy start system alias did not canonicalize."
	)
	_expect(
		DomainIdType.canonicalize("npc.kaelen") == &"npc.kaelen",
		"Canonical IDs should remain unchanged."
	)


func _test_validation_results() -> void:
	var child := ValidationResultType.new()
	child.add_error("missing", "Required value is missing.", "name")
	child.add_warning("legacy", "Legacy value was translated.", "id")
	var parent := ValidationResultType.new()
	parent.merge(child, "npc")
	_expect(not parent.is_valid(), "Merged errors should invalidate result.")
	_expect(
		parent.errors[0]["path"] == "npc.name",
		"Merged error path prefix was not preserved."
	)
	_expect(
		parent.warnings[0]["path"] == "npc.id",
		"Merged warning path prefix was not preserved."
	)


func _test_definition_common_fields() -> void:
	var definition := DomainDefinitionType.new()
	var valid := definition.load_common(
		{"id": "system.start", "schema_version": 1},
		"system",
		1
	)
	_expect(valid.is_valid(), "Valid common definition fields failed.")
	_expect(
		definition.to_common_dict() == {
			"id": "system.start",
			"schema_version": 1,
		},
		"Common definition fields did not round-trip."
	)

	var unsupported := DomainDefinitionType.new().load_common(
		{"id": "system.start", "schema_version": 2},
		"system",
		1
	)
	_expect(
		not unsupported.is_valid(),
		"Unsupported schema version should fail."
	)
	var fractional := DomainDefinitionType.new().load_common(
		{"id": "system.start", "schema_version": 1.5},
		"system",
		1
	)
	_expect(
		not fractional.is_valid(),
		"Fractional schema version should fail."
	)
	var padded_id := DomainDefinitionType.new().load_common(
		{"id": " system.start", "schema_version": 1},
		"system",
		1
	)
	_expect(
		not padded_id.is_valid(),
		"Definition IDs with whitespace should fail."
	)


func _test_json_codec() -> void:
	var source := {
		"id": "system.start",
		"schema_version": 1,
		"nested": {"value": 7},
	}
	var encoded := DomainJsonType.stringify(source)
	var decoded := DomainJsonType.parse_object(encoded, "round_trip")
	var validation := decoded["validation"] as ValidationResult
	_expect(validation.is_valid(), "Valid JSON object failed to parse.")
	_expect(
		str(decoded["data"].get("id", "")) == "system.start"
			and int(decoded["data"].get("schema_version", 0)) == 1
			and int(decoded["data"].get("nested", {}).get("value", 0)) == 7,
		"JSON object fields did not round-trip."
	)

	var malformed := DomainJsonType.parse_object("{ nope", "malformed")
	_expect(
		not (malformed["validation"] as ValidationResult).is_valid(),
		"Malformed JSON should fail."
	)
	var array_root := DomainJsonType.parse_object("[]", "array_root")
	_expect(
		not (array_root["validation"] as ValidationResult).is_valid(),
		"Array JSON root should fail."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
