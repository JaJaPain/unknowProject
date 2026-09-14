class_name GeneratedGateBuilder
extends RefCounted


static func build_outbound_gate_defs(
	system_id: String,
	system_name: String,
	config: SystemConfig
) -> Array[Dictionary]:
	var gate_defs: Array[Dictionary] = []
	var source_suffix := _id_suffix(system_id, "system.")
	for index in range(config.outbound_gate_count):
		var branch_key := outbound_branch_key(system_id, config.seed_value, index)
		var destination_system_id := "system.gen.route.%s" % branch_key
		var destination_suffix := _id_suffix(destination_system_id, "system.")
		var gate_id := "gate.%s.out_%d" % [source_suffix, index + 1]
		var destination_gate_id := "gate.%s.return" % destination_suffix
		gate_defs.append({
			"id": gate_id,
			"legacy_id": gate_id.replace(".", "_"),
			"display_name": "%s Outbound Gate %d" % [system_name, index + 1],
			"destination_system_id": destination_system_id,
			"destination_gate_id": destination_gate_id,
			"initial_state": "unknown",
			"discovery_action": "",
			"discovery_cost": {},
			"discovery_prerequisites": [],
		})
	return gate_defs


static func outbound_branch_key(
	system_id: String,
	seed_value: int,
	index: int
) -> String:
	return ("%s|%d|outbound|%d" % [
		system_id,
		seed_value,
		index + 1,
	]).sha256_text().substr(0, 16)


static func _id_suffix(id: String, prefix: String) -> String:
	if id.begins_with(prefix):
		return id.substr(prefix.length())
	return id
