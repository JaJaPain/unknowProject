extends SceneTree

class IdentityNode:
	extends Node

	var world_id: String
	var world_type: String = "entity_type.test"

	func _init(id_value: String) -> void:
		world_id = id_value

	func get_world_id() -> String:
		return world_id

	func get_world_type_id() -> String:
		return world_type


class StatefulIdentityNode:
	extends IdentityNode

	func get_state_schema_version() -> int:
		return 1

	func capture_state() -> Dictionary:
		return {"value": 7}

	func restore_state(_state: Dictionary) -> void:
		pass


var _failures: Array[String] = []


func _initialize() -> void:
	_test_valid_identity()
	_test_missing_identity()
	_test_state_contract()
	_test_duplicate_detection()
	_test_state_envelope()

	if _failures.is_empty():
		print("[PASS] World identity tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_valid_identity() -> void:
	var node := IdentityNode.new("station.start.main")
	_expect(
		WorldIdentity.validate_node(node).is_valid(),
		"Valid immutable world identity failed."
	)
	node.free()


func _test_missing_identity() -> void:
	var node := IdentityNode.new("")
	_expect(
		not WorldIdentity.validate_node(node).is_valid(),
		"Empty world identity should fail."
	)
	node.free()


func _test_state_contract() -> void:
	var immutable := IdentityNode.new("station.start.main")
	_expect(
		not WorldIdentity.validate_node(immutable, true).is_valid(),
		"Identity without state methods should fail the stateful contract."
	)
	immutable.free()

	var stateful := StatefulIdentityNode.new("entity.test.asteroid")
	_expect(
		WorldIdentity.validate_node(stateful, true).is_valid(),
		"Complete stateful identity contract failed."
	)
	stateful.free()


func _test_duplicate_detection() -> void:
	var first := StatefulIdentityNode.new("entity.test.duplicate")
	var second := StatefulIdentityNode.new("entity.test.duplicate")
	var result := WorldIdentity.validate_collection([first, second], true)
	_expect(not result.is_valid(), "Duplicate world IDs should fail.")
	_expect(
		result.errors.any(func(issue): return issue["code"] == "duplicate_world_id"),
		"Duplicate world ID error was not reported."
	)
	first.free()
	second.free()


func _test_state_envelope() -> void:
	var node := StatefulIdentityNode.new("entity.test.envelope")
	var envelope := WorldIdentity.state_envelope(node)
	_expect(
		envelope.get("entity_id", "") == "entity.test.envelope"
			and envelope.get("entity_type", "") == "entity_type.test"
			and int(envelope.get("schema_version", 0)) == 1
			and int(envelope.get("value", 0)) == 7,
		"State envelope omitted identity or schema metadata."
	)
	node.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
