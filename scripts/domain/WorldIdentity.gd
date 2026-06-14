class_name WorldIdentity
extends RefCounted

const IDENTITY_GROUP := "world_identity"
const STATEFUL_GROUP := "persistent_entity"


static func validate_node(
	node: Node,
	require_state_contract: bool = false
) -> ValidationResult:
	var result := ValidationResult.new()
	if node == null or not is_instance_valid(node):
		return result.add_error(
			"invalid_node",
			"World identity node is missing or invalid."
		)
	if not node.has_method("get_world_id"):
		result.add_error(
			"missing_world_id_method",
			"Node does not implement get_world_id()."
		)
	else:
		var world_id := str(node.call("get_world_id"))
		if world_id.is_empty():
			result.add_error(
				"empty_world_id",
				"World identity cannot be empty."
			)

	if not node.has_method("get_world_type_id"):
		result.add_error(
			"missing_world_type_method",
			"Node does not implement get_world_type_id()."
		)
	elif str(node.call("get_world_type_id")).is_empty():
		result.add_error(
			"empty_world_type",
			"World type identity cannot be empty."
		)

	if require_state_contract:
		for method_name in [
			"get_state_schema_version",
			"capture_state",
			"restore_state",
		]:
			if not node.has_method(method_name):
				result.add_error(
					"missing_state_method",
					"Stateful entity does not implement %s()." % method_name
				)
		if node.has_method("get_state_schema_version") \
				and int(node.call("get_state_schema_version")) < 1:
			result.add_error(
				"invalid_state_schema",
				"State schema version must be at least 1."
			)
	return result


static func validate_collection(
	nodes: Array,
	require_state_contract: bool = false
) -> ValidationResult:
	var result := ValidationResult.new()
	var seen_ids: Dictionary = {}
	for index in range(nodes.size()):
		var node: Node = nodes[index]
		var node_result := validate_node(node, require_state_contract)
		result.merge(node_result, "entities.%d" % index)
		if not node_result.is_valid() or not node.has_method("get_world_id"):
			continue
		var world_id := str(node.call("get_world_id"))
		if seen_ids.has(world_id):
			result.add_error(
				"duplicate_world_id",
				"Duplicate world ID '%s'." % world_id,
				"entities.%d" % index
			)
		else:
			seen_ids[world_id] = true
	return result


static func state_envelope(node: Node) -> Dictionary:
	var validation := validate_node(node, true)
	if not validation.is_valid():
		return {}
	var state: Dictionary = node.call("capture_state")
	state["entity_id"] = str(node.call("get_world_id"))
	state["entity_type"] = str(node.call("get_world_type_id"))
	state["schema_version"] = int(node.call("get_state_schema_version"))
	return state
