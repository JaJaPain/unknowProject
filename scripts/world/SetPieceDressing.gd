extends RefCounted

## ChatGPT's reusable set pieces placed in ordinary play (set piece wishlist
## #7 and #8): the lone derelict for dead ships worth a look (a distress-beacon
## find, an investigation into a ship's recorder or archive) and the signal
## anomaly where something broadcasts that shouldn't (a transmitter lure).
## Each comes with a little life: pulsing seams and a breathing centre glow,
## flickering emergency lights and a blinking beacon, loose shards drifting.
## Returns null when the model is missing, so callers keep their old marker.

const DERELICT_PATH := "res://assets/landmarks/lone_derelict.glb"
const ANOMALY_PATH := "res://assets/landmarks/signal_anomaly.glb"
const LifeScript := preload("res://scripts/world/SetPieceLife.gd")


static func derelict(model_scale: float = 1.0, hull_tint: Color = Color(0.62, 0.64, 0.66)) -> Node3D:
	var model := _load(DERELICT_PATH)
	if model == null:
		return null
	model.name = "Derelict"
	model.scale = Vector3.ONE * model_scale
	_tint(model, "Neutral hull", hull_tint)
	var life: Node = LifeScript.new()
	life.lamps = {"Emergency emission": "flicker", "Beacon emission": "blink"}
	model.add_child(life)
	return model


static func anomaly(model_scale: float = 1.0) -> Node3D:
	var model := _load(ANOMALY_PATH)
	if model == null:
		return null
	model.name = "SignalAnomaly"
	model.scale = Vector3.ONE * model_scale
	var life: Node = LifeScript.new()
	life.lamps = {"Cold seam emission": "signal", "Central faint glow": "breathe"}
	life.drifters = ["LooseShard"]
	life.swell = "CentreGlow"
	model.add_child(life)
	# Brighter than as exported, so it reads from a distance (wishlist #8 note).
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if m != null and m.resource_name.contains("Cold seam emission"):
				var own := m.duplicate() as StandardMaterial3D
				own.emission_energy_multiplier = maxf(own.emission_energy_multiplier, 1.0) * 8.0
				mi.set_surface_override_material(i, own)
	# Its own cold light, so the dark shards read against space.
	var glow := OmniLight3D.new()
	glow.name = "AnomalyGlow"
	glow.light_color = Color(0.55, 0.9, 1.0)
	glow.light_energy = 1.6
	glow.omni_range = ANOMALY_REACH * 3.0
	glow.omni_attenuation = 0.3
	glow.position = Vector3(0, ANOMALY_REACH * 0.4, 0)
	model.add_child(glow)
	return model


## How far each model reaches from its origin at scale 1 (from the READMEs:
## the derelict is ~300 m long, the anomaly ~133 x 123 m and 150 m tall).
const DERELICT_REACH := 160.0
const ANOMALY_REACH := 95.0


static func reach(model: Node3D) -> float:
	var base := DERELICT_REACH if str(model.name) == "Derelict" else ANOMALY_REACH
	return base * model.scale.x


static func _load(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	return scene.instantiate() as Node3D if scene != null else null


static func _tint(model: Node3D, material_name: String, color: Color) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if m != null and m.resource_name.contains(material_name):
				var own := m.duplicate() as StandardMaterial3D
				own.albedo_color = color
				mi.set_surface_override_material(i, own)
