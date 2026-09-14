class_name DockingTractorBeam
extends MeshInstance3D

## Lightweight visual tether for the automated docking procedure. It follows
## the station and ship every frame, so the tractor read remains truthful even
## while the station rotates or the ship is being pulled into alignment.

var _station: Node3D
var _ship: Node3D
var _cylinder: CylinderMesh
const SHIP_SURFACE_CLEARANCE := 5.0


func configure(station: Node3D, ship: Node3D) -> void:
	_station = station
	_ship = ship
	_cylinder = CylinderMesh.new()
	_cylinder.top_radius = 0.42
	_cylinder.bottom_radius = 0.42
	_cylinder.height = 1.0
	_cylinder.radial_segments = 10
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.82, 1.0, 0.5)
	material.emission_enabled = true
	material.emission = Color(0.04, 0.72, 1.0)
	material.emission_energy_multiplier = 2.2
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cylinder.material = material
	mesh = _cylinder
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_update_beam()


func _process(_delta: float) -> void:
	_update_beam()


func _update_beam() -> void:
	if not is_instance_valid(_station) or not is_instance_valid(_ship):
		queue_free()
		return
	var station_origin := _station.global_position
	var offset := _ship.global_position - station_origin
	var length := offset.length()
	if length <= SHIP_SURFACE_CLEARANCE:
		visible = false
		return
	# End at the near side of the ship's hull, never through the ship or the
	# player camera. This makes the tether visibly terminate at its target.
	var direction := offset / length
	var end_point := _ship.global_position - direction * SHIP_SURFACE_CLEARANCE
	var beam_length := station_origin.distance_to(end_point)
	visible = true
	global_position = station_origin.lerp(end_point, 0.5)
	global_basis = Basis.looking_at(direction, Vector3.UP) \
		* Basis(Vector3.RIGHT, PI * 0.5)
	# Set mesh height directly rather than scaling the node. Stations can be
	# scaled for their models, and inherited node scale made the old beam run far
	# beyond the ship.
	_cylinder.height = beam_length
