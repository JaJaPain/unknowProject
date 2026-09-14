extends Node

var _material: StandardMaterial3D
var _speed: float = 0.0


func _ready() -> void:
	var planet := get_parent()
	if planet == null:
		return
	_speed = planet.get_meta("rotation_speed", 0.0)
	var mesh_inst := planet.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_inst and mesh_inst.mesh:
		_material = mesh_inst.mesh.material as StandardMaterial3D


func _process(delta: float) -> void:
	if _speed == 0.0 or _material == null:
		return
	_material.uv1_offset.x += _speed * delta


static func apply(planet: Node3D, is_gas: bool, rng: RandomNumberGenerator) -> void:
	var speed: float
	if is_gas:
		speed = rng.randf_range(0.006, 0.011)
	else:
		speed = rng.randf_range(0.001125, 0.003375)

	# ~15% chance of retrograde rotation
	if rng.randf() < 0.15:
		speed = -speed

	planet.set_meta("rotation_speed", speed)

	var rotator := Node.new()
	rotator.name = "PlanetRotation"
	rotator.set_script(load("res://scripts/visuals/PlanetRotation.gd"))
	planet.add_child(rotator)
