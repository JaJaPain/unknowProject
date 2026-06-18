extends RefCounted

const MIN_SYSTEM_TIME_MINUTES := 30
const RUMOR_NARRATIVES := [
	"Docking crew mentioned a faint hypergate signature beyond the outer belt.",
	"Station intel picked up an old nav beacon — could be a dormant gate.",
	"Scrappers found relay fragments. Might be a gate out there.",
	"Comms chatter suggests a derelict gate drifting in deep space nearby.",
	"An old pilot's log references a gate nobody's charted in years.",
	"Sensor sweep caught anomalous readings — consistent with gate residue.",
]


func event_type_id() -> String:
	return "gate_rumor"


func is_eligible(context) -> bool:
	if context.campaign_time < MIN_SYSTEM_TIME_MINUTES:
		return false
	var unknown_gates := _find_unknown_gates()
	return not unknown_gates.is_empty()


func priority(_context) -> float:
	return 0.8


func execute(_context) -> Dictionary:
	var unknown_gates := _find_unknown_gates()
	if unknown_gates.is_empty():
		return {"event": "gate_rumor", "applied": false}
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var gate_id: String = unknown_gates[rng.randi() % unknown_gates.size()]
	var narrative: String = RUMOR_NARRATIVES[rng.randi() % RUMOR_NARRATIVES.size()]
	var result := GateDiscovery.apply_rumor(gate_id, narrative)
	if result.get("ok", false):
		GlobalState.emit_chatter(
			"SYSTEM",
			narrative,
			Color(0.7, 0.85, 0.5)
		)
	return {
		"event": "gate_rumor",
		"applied": result.get("ok", false),
		"gate_id": gate_id,
		"narrative": narrative,
	}


func _find_unknown_gates() -> Array[String]:
	var output: Array[String] = []
	var registry = _get_system_registry()
	if registry == null:
		return output
	var current_system_id := _get_current_system_id()
	var current_system: SystemDefinition = registry.get_system(current_system_id)
	if current_system == null:
		return output
	for gate_def in current_system.gates:
		var gate_id: String = str(gate_def.id)
		if GateDiscovery.get_gate_state(gate_id) == "unknown":
			output.append(gate_id)
	return output


func _get_system_registry():
	var game_root = Engine.get_main_loop().root.get_child(0) if Engine.get_main_loop() else null
	if game_root and "system_registry" in game_root:
		return game_root.system_registry
	return null


func _get_current_system_id() -> String:
	var game_root = Engine.get_main_loop().root.get_child(0) if Engine.get_main_loop() else null
	if game_root and "system_registry" in game_root:
		return str(game_root.system_registry.resolve_system_id(GlobalState.current_system_id))
	return GlobalState.current_system_id
