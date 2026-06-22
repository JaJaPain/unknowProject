extends RefCounted

static var _shared = null

var _activated_ids: Array = []

static func shared() -> Object:
	if _shared == null:
		_shared = new()
	return _shared

static func reset() -> void:
	_shared = null


# Spawn 1–3 anomaly nodes at random positions in the system.
func generate_for_system(system_id: String, scene_parent: Node3D) -> void:
	var count: int = randi_range(0, 2)
	print("[AnomalyRegistry] Spawning %d anomalies for system '%s'" % [count, system_id])
	var presets: Array = _fallback_table()
	presets.shuffle()
	for i in range(count):
		var data: Dictionary = presets[i % presets.size()].duplicate(true)
		data["anomaly_id"] = "%s_%d" % [system_id, i]
		if data["anomaly_id"] in _activated_ids:
			continue
		var node: StaticBody3D = StaticBody3D.new()
		node.set_script(load("res://scripts/SpaceAnomaly.gd"))
		node.name = "Anomaly_%d" % i
		node.anomaly_data = data
		scene_parent.add_child(node)
		node.global_position = _random_position()


func mark_activated(anomaly_id: String) -> void:
	if anomaly_id not in _activated_ids:
		_activated_ids.append(anomaly_id)


func clear() -> void:
	_activated_ids.clear()


# ── private ───────────────────────────────────────────────────────────────────

func _random_position() -> Vector3:
	var angle: float = randf() * TAU
	var dist: float = randf_range(500.0, 1200.0)
	return Vector3(cos(angle) * dist, randf_range(-20.0, 20.0), sin(angle) * dist)


func _fallback_table() -> Array:
	return [
		{
			"name": "Abandoned Cargo Cache",
			"flavor_type": "civilian",
			"approach_lines": ["Passive signature. Looks like jettisoned freight."],
			"actions": [
				{ "type": "emit_chat", "sender": "Cargo Manifest", "lines": ["Contents: mixed metals, partial ore batch."], "delay": 0.5 },
				{ "type": "grant_ore", "amount": 18 },
				{ "type": "grant_item", "item_id": "repair_kit" },
			]
		},
		{
			"name": "Distress Beacon — No Survivors",
			"flavor_type": "civilian",
			"approach_lines": ["Emergency beacon active. Signal is old."],
			"actions": [
				{ "type": "emit_chat", "sender": "Beacon WX-7", "lines": ["...day 31... fuel depleted... requesting any vessel...", "...no response... logging final position..."], "delay": 1.0 },
				{ "type": "grant_credits", "amount": 65 },
				{ "type": "grant_item", "item_id": "data_chip" },
			]
		},
		{
			"name": "Reaver Ambush Point",
			"flavor_type": "pirate",
			"approach_lines": ["Debris field. Pattern suggests deliberate placement."],
			"actions": [
				{ "type": "emit_chat", "sender": "SYSTEM", "lines": ["Threat pattern detected. This was a trap."], "delay": 0.0 },
				{ "type": "spawn_hostiles", "faction": "reavers", "count": 2, "delay": 2.0, "spawn_chat": "They were waiting." },
			]
		},
		{
			"name": "Cracked Reactor Core",
			"flavor_type": "military",
			"approach_lines": ["Radiation signature. Salvageable but unstable."],
			"actions": [
				{ "type": "emit_chat", "sender": "SYSTEM", "lines": ["Proximity warning: reactor venting."], "delay": 0.0 },
				{ "type": "damage_player", "amount": 12 },
				{ "type": "grant_credits", "amount": 90 },
				{ "type": "grant_item", "item_id": "antimatter_pod" },
			]
		},
		{
			"name": "Drifting Weapon Cache",
			"flavor_type": "military",
			"approach_lines": ["Sealed container. Military stenciling, no registry."],
			"actions": [
				{ "type": "emit_chat", "sender": "SYSTEM", "lines": ["Container cracked. Munitions inside — mixed types."], "delay": 0.5 },
				{ "type": "grant_item", "item_id": "kinetic_ammo" },
				{ "type": "grant_item", "item_id": "thermal_ammo" },
				{ "type": "grant_item", "item_id": "emp_charge" },
			]
		},
		{
			"name": "Encrypted Black Box",
			"flavor_type": "scientific",
			"approach_lines": ["Encrypted signal. Flight recorder class."],
			"actions": [
				{ "type": "emit_chat", "sender": "Black Box", "lines": ["RECORD 04: ...coordinates confirmed... do not transmit...", "RECORD 05: ...if recovered, find CHORUS-9..."], "delay": 1.5 },
				{ "type": "grant_item", "item_id": "encrypted_core" },
				{ "type": "grant_item", "item_id": "data_chip" },
			]
		},
		{
			"name": "Faction Skirmish Debris",
			"flavor_type": "military",
			"approach_lines": ["Recent battle site. Both sides took losses."],
			"actions": [
				{ "type": "emit_chat", "sender": "SYSTEM", "lines": ["Wreckage from multiple factions. Still hot."], "delay": 0.0 },
				{ "type": "grant_ore", "amount": 25 },
				{ "type": "grant_item", "item_id": "damaged_transponder" },
			]
		},
		{
			"name": "Navigation Buoy — Derelict",
			"flavor_type": "civilian",
			"approach_lines": ["NavBuoy offline. Last ping cycle: unknown."],
			"actions": [
				{ "type": "emit_chat", "sender": "NavBuoy 44-C", "lines": ["System restart... route tables corrupted... partial data intact."], "delay": 1.0 },
				{ "type": "grant_item", "item_id": "scanner_probe" },
				{ "type": "grant_credits", "amount": 30 },
			]
		},
		{
			"name": "Emergency Med Cache",
			"flavor_type": "civilian",
			"approach_lines": ["Humanitarian marker. Cache deployed and forgotten."],
			"actions": [
				{ "type": "emit_chat", "sender": "Cache AI", "lines": ["Emergency supplies available. Take what you need."], "delay": 0.5 },
				{ "type": "grant_item", "item_id": "repair_kit" },
				{ "type": "grant_item", "item_id": "shield_cell" },
			]
		},
		{
			"name": "Hostile Scout Probe",
			"flavor_type": "pirate",
			"approach_lines": ["Small signature. Self-propelled. Watching you."],
			"actions": [
				{ "type": "emit_chat", "sender": "SYSTEM", "lines": ["Probe destroyed. But it already transmitted your position."], "delay": 0.5 },
				{ "type": "spawn_hostiles", "faction": "dustborn", "count": 1, "delay": 4.0, "spawn_chat": "They got the signal." },
				{ "type": "grant_item", "item_id": "damaged_transponder" },
			]
		},
	]
