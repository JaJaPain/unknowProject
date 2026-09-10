extends RefCounted

static var _shared = null

var _activated_ids: Array = []
var _last_spawned_flavors: Array = []  # flavor_type strings from last generate call

const MIN_ANOMALIES := 0
const MAX_ANOMALIES := 2

static func shared() -> Object:
	if _shared == null:
		_shared = new()
	return _shared

static func reset() -> void:
	_shared = null


# Spawn 0-2 deterministic anomaly nodes at stable positions in the system.
func generate_for_system(system_id: String, scene_parent: Node3D) -> void:
	_last_spawned_flavors.clear()
	var rng := _rng_for_system(system_id)
	var count: int = rng.randi_range(MIN_ANOMALIES, MAX_ANOMALIES)

	# story_forced_anomaly: StoryManager can plant a guaranteed anomaly of a
	# specific flavor. Only fires when system_id matches (or is left blank).
	var forced: Dictionary = GlobalState.story_forced_anomaly
	var forced_system: String = str(forced.get("system_id", ""))
	var forced_flavor: String = str(forced.get("flavor_type", ""))
	var has_forced: bool = (not forced.is_empty()
		and not forced_flavor.is_empty()
		and (forced_system == "" or forced_system == system_id))

	print("[AnomalyRegistry] Spawning %d anomalies for system '%s'" % [count, system_id])
	var presets: Array = _fallback_table()
	_shuffle_with_rng(presets, rng)
	for i in range(count):
		var data: Dictionary = presets[i % presets.size()].duplicate(true)
		data["anomaly_id"] = _anomaly_id(system_id, i)
		if data["anomaly_id"] in _activated_ids:
			continue
		var node: StaticBody3D = StaticBody3D.new()
		node.set_script(load("res://scripts/SpaceAnomaly.gd"))
		node.name = "Anomaly_%d" % i
		node.set("persistent_id", str(data["anomaly_id"]))
		node.set("anomaly_data", data)
		node.position = _random_position(rng)
		scene_parent.add_child(node)
		_request_llm_event_for_node(system_id, node, data)
		_last_spawned_flavors.append(str(data.get("flavor_type", "")))

	if has_forced:
		var forced_preset: Dictionary = {}
		for p in presets:
			if str(p.get("flavor_type", "")) == forced_flavor:
				forced_preset = p.duplicate(true)
				break
		if forced_preset.is_empty() and not presets.is_empty():
			forced_preset = presets[0].duplicate(true)
		if not forced_preset.is_empty():
			forced_preset["anomaly_id"] = "%s_forced" % system_id
			forced_preset["flavor_type"] = forced_flavor
			if forced_preset["anomaly_id"] not in _activated_ids:
				var fnode: StaticBody3D = StaticBody3D.new()
				fnode.set_script(load("res://scripts/SpaceAnomaly.gd"))
				fnode.name = "Anomaly_Forced"
				fnode.set("persistent_id", str(forced_preset["anomaly_id"]))
				fnode.set("anomaly_data", forced_preset)
				fnode.position = _random_position(rng)
				scene_parent.add_child(fnode)
				_request_llm_event_for_node(system_id, fnode, forced_preset)
				_last_spawned_flavors.append(forced_flavor)
				print("[AnomalyRegistry] Planted story anomaly '%s' for system '%s'" % [forced_flavor, system_id])
		GlobalState.story_forced_anomaly = {}


func mark_activated(anomaly_id: String) -> void:
	if anomaly_id not in _activated_ids:
		_activated_ids.append(anomaly_id)


func clear() -> void:
	_activated_ids.clear()


# Returns a rumor hint line if anomalies were spawned this system, "" otherwise.
# Call this ~10s after generate_for_system so it fires naturally in-world.
func get_arrival_rumor() -> Dictionary:
	if _last_spawned_flavors.is_empty():
		return {}
	# Only fire ~60% of the time even when anomalies exist
	if randf() > 0.60:
		return {}
	var flavor: String = _last_spawned_flavors[0]
	var senders := ["Independent Hauler", "Passing Vessel", "Comms Relay", "Local Traffic"]
	var sender: String = senders[randi() % senders.size()]
	var line: String
	match flavor:
		"military":
			var opts := [
				"Something with mil-spec encryption drifting out past the belt. Couldn't get close.",
				"Picked up a sealed container with no registry. Military stenciling. Left it alone.",
				"Classified signature out there. Not transmitting. Could be old, could be trouble.",
			]
			line = opts[randi() % opts.size()]
		"pirate":
			var opts := [
				"Watch yourself out past the main lane. Something's sitting there quiet. Too quiet.",
				"Debris pattern looks deliberate. Like someone wanted ships to stop and check.",
				"Picked up a contact then lost it. Looked like a setup to me.",
			]
			line = opts[randi() % opts.size()]
		"scientific":
			var opts := [
				"Anomalous reading on long-range. Could be worth a scan if you've got the gear.",
				"Something's broadcasting on a weird band out there. Not standard comms.",
				"My sensors flagged something unusual about 800 clicks out. Couldn't identify it.",
			]
			line = opts[randi() % opts.size()]
		"civilian":
			var opts := [
				"Passive signature out near the rock field. Might be salvage, might be junk.",
				"Something drifting out past the main lane. Looks like abandoned freight.",
				"Picked up a beacon but it's old. Could still be worth checking.",
			]
			line = opts[randi() % opts.size()]
		_:
			var opts := [
				"Sensor ghost or something real out there — can't tell. Maybe nothing.",
				"Odd reading on the long-range. Didn't stop to check.",
				"Something out there that shouldn't be. Could be interesting.",
			]
			line = opts[randi() % opts.size()]
	return {"sender": sender, "line": line}


# ── private ───────────────────────────────────────────────────────────────────

func _rng_for_system(system_id: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var seed_source := "%s|%d|anomalies" % [system_id, GlobalState.campaign_seed]
	rng.seed = abs(hash(seed_source))
	return rng


func _anomaly_id(system_id: String, index: int) -> String:
	return "anomaly.%s.%d" % [system_id.replace(":", "_"), index]


func _random_position(rng: RandomNumberGenerator) -> Vector3:
	var angle: float = rng.randf() * TAU
	var dist: float = rng.randf_range(500.0, 1200.0)
	return Vector3(cos(angle) * dist, rng.randf_range(-20.0, 20.0), sin(angle) * dist)


func _shuffle_with_rng(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp


func _request_llm_event_for_node(
	system_id: String,
	node: StaticBody3D,
	fallback_data: Dictionary
) -> void:
	if not is_instance_valid(LLMInterface) \
			or not LLMInterface.has_method("fetch_anomaly_event"):
		return
	var anomaly_id := str(fallback_data.get("anomaly_id", ""))
	LLMInterface.fetch_anomaly_event(system_id, fallback_data, func(generated: Dictionary) -> void:
		if generated.is_empty() or not is_instance_valid(node):
			return
		if str(node.get("persistent_id")) != anomaly_id:
			return
		generated["anomaly_id"] = anomaly_id
		node.set("anomaly_data", generated)
		print("[AnomalyRegistry] LLM anomaly event ready for '%s'" % anomaly_id)
	)


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
				{
					"type": "grant_data_core",
					"name": "Encrypted Black Box Core",
					"description": "A locked flight recorder recovered from a drifting black box.",
					"payout_credits": 135,
				},
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
