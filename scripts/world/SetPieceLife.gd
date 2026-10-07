extends Node

## A little life for a placed set piece (SetPieceDressing): lit materials that
## pulse with a signal, breathe, flicker or blink; loose parts that drift; a
## centre glow that swells. Works on its parent model.

## Material name (substring) -> "signal" | "breathe" | "flicker" | "blink".
var lamps: Dictionary = {}
## Node name prefixes that drift slowly (the anomaly's loose shards).
var drifters: Array = []
## Node name prefix of a part that swells and fades (the anomaly's centre glow).
var swell := ""

var _t := 0.0
var _mats: Array = []      # [{mat, base, mode, phase}]
var _drift: Array = []     # [{node, axis, speed}]
var _swell_node: Node3D = null


func _ready() -> void:
	var model := get_parent() as Node3D
	if model == null:
		return
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := (mi.get_surface_override_material(i) if mi.get_surface_override_material(i) != null else mi.mesh.surface_get_material(i)) as StandardMaterial3D
			if m == null:
				continue
			for key in lamps:
				if m.resource_name.contains(str(key)):
					var own := m.duplicate() as StandardMaterial3D
					own.emission_enabled = true
					mi.set_surface_override_material(i, own)
					_mats.append({"mat": own, "base": maxf(own.emission_energy_multiplier, 0.6), "mode": str(lamps[key]), "phase": float(_mats.size()) * 0.9})
	var n := 0
	for node in model.find_children("*", "Node3D", true, false):
		for prefix in drifters:
			if str(node.name).begins_with(str(prefix)):
				_drift.append({"node": node, "axis": Vector3(0.3, 1.0, 0.25).rotated(Vector3.UP, float(n)).normalized(), "speed": 0.05 + 0.03 * float(n % 3)})
				n += 1
		if not swell.is_empty() and str(node.name).begins_with(swell) and _swell_node == null:
			_swell_node = node as Node3D


func _process(delta: float) -> void:
	_t += delta
	for entry in _mats:
		var mat := entry["mat"] as StandardMaterial3D
		var base := float(entry["base"])
		var phase := float(entry["phase"])
		match str(entry["mode"]):
			"signal":
				# A slow carrier with a sharp repeating pulse on top.
				var beat := pow(maxf(0.0, sin(_t * 2.4 + phase)), 12.0)
				mat.emission_energy_multiplier = base * (0.5 + 0.3 * sin(_t * 0.7) + 1.8 * beat)
			"breathe":
				mat.emission_energy_multiplier = base * (0.6 + 0.4 * sin(_t * 0.6 + phase))
			"flicker":
				var on := fmod(_t * 7.3 + phase * 3.1, 1.0) > 0.18 or fmod(_t * 0.37 + phase, 1.0) < 0.6
				mat.emission_energy_multiplier = base * (1.0 if on else 0.1)
			"blink":
				mat.emission_energy_multiplier = base * (1.8 if fmod(_t + phase, 2.5) < 0.3 else 0.1)
	for d in _drift:
		var node := d["node"] as Node3D
		if is_instance_valid(node):
			node.rotate_object_local(d["axis"], float(d["speed"]) * delta)
	if is_instance_valid(_swell_node):
		_swell_node.scale = Vector3.ONE * (1.0 + 0.25 * sin(_t * 0.6))
