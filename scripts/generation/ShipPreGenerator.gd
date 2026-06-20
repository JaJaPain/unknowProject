class_name ShipPreGenerator
extends Node

signal ship_generated(model_seed: String)

var _thread: Thread = null
var _pending_jobs: Array[Dictionary] = []
var _completed_seeds: Array[String] = []
var _mutex := Mutex.new()
var _running := false
var _system_registry: SystemRegistry = null


func initialize(registry: SystemRegistry) -> void:
	_system_registry = registry


func on_system_entered(system_id: String, _arrival_gate_id: String) -> void:
	var definition := _system_registry.get_system(system_id)
	if definition == null:
		return
	_queue_for_system(definition)

	var seen: Dictionary = {}
	var neighbor_defs: Array = []
	for gate: GateDefinition in definition.gates:
		var dest_def := _system_registry.get_system(gate.destination_system_id)
		if dest_def == null or dest_def.scene_path != "generated":
			continue
		var key: String = str(dest_def.id)
		if seen.has(key):
			continue
		seen[key] = true
		neighbor_defs.append(dest_def)

	for dest_def: SystemDefinition in neighbor_defs:
		_queue_for_system(dest_def)


func _queue_for_system(sys_def: SystemDefinition) -> void:
	if sys_def.scene_path != "generated":
		return
	var config: SystemConfig = _system_registry.get_generated_config(str(sys_def.id))
	if config == null:
		config = _system_registry.get_generated_config(sys_def.legacy_id)
	if config == null:
		return

	var jobs: Array[Dictionary] = []
	for i in range(config.npc_patrol_count):
		var seed_str: String = "ship_%d_%d" % [config.seed_value, i + 1]
		if ShipGenerator.has_cached(seed_str):
			continue
		var faction_name := _pick_faction_for_index(config, i)
		jobs.append({
			"seed": seed_str,
			"faction": faction_name,
			"ship_style": config.ship_style_for_faction(faction_name),
		})

	if jobs.is_empty():
		return

	_mutex.lock()
	_pending_jobs.append_array(jobs)
	_mutex.unlock()
	_start_thread_if_needed()


func _pick_faction_for_index(config: SystemConfig, index: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = config.seed_value + 9999 + index
	var roll := rng.randf()
	var cumulative := 0.0
	for faction_name: String in config.faction_weights:
		cumulative += float(config.faction_weights[faction_name])
		if roll <= cumulative:
			return faction_name
	return config.faction_weights.keys()[0] as String


func _start_thread_if_needed() -> void:
	if _running:
		return
	_running = true
	_thread = Thread.new()
	_thread.start(_worker)


func _worker() -> void:
	while true:
		_mutex.lock()
		if _pending_jobs.is_empty():
			_mutex.unlock()
			break
		var job: Dictionary = _pending_jobs.pop_front()
		_mutex.unlock()

		var seed_str: String = job["seed"]
		var faction: String = job["faction"]
		var ship_style: Dictionary = job.get("ship_style", {})
		var result := ShipGenerator.generate(seed_str, "", faction, ship_style)
		if not result.is_empty():
			_mutex.lock()
			_completed_seeds.append(seed_str)
			_mutex.unlock()

	call_deferred("_on_thread_done")


func _on_thread_done() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	_running = false

	_mutex.lock()
	var seeds := _completed_seeds.duplicate()
	_completed_seeds.clear()
	var has_more := not _pending_jobs.is_empty()
	_mutex.unlock()

	for seed_str in seeds:
		ship_generated.emit(seed_str)

	if has_more:
		_start_thread_if_needed()


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_mutex.lock()
		_pending_jobs.clear()
		_mutex.unlock()
		_thread.wait_to_finish()
