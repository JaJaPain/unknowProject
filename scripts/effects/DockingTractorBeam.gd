class_name DockingTractorBeam
extends MeshInstance3D

## Lightweight visual tether for the automated docking procedure. It follows
## the station and ship every frame, so the tractor read remains truthful even
## while the station rotates or the ship is being pulled into alignment.

var _station: Node3D
var _ship: Node3D
var _cylinder: CylinderMesh
const SHIP_SURFACE_CLEARANCE := 5.0
const BEAM_WIDTH_PER_LENGTH := 0.004
## The same hum as the mining tractor (Abe, playtest 2026-10-04 c finding 6),
## looping at the ship's end for as long as the beam holds it. The player's
## own beam at the mining tractor's level; traffic quieter and only up close.
const HUM_STREAM := preload("res://sound/Mining/TractorBeam.mp3")
const HUM_PLAYER_DB := -4.0
const HUM_TRAFFIC_DB := -12.0
var hum: AudioStreamPlayer3D


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
	_start_hum()
	_update_beam()


func _start_hum() -> void:
	hum = AudioStreamPlayer3D.new()
	hum.name = "TractorHum"
	hum.stream = HUM_STREAM
	hum.bus = "SFX"
	hum.unit_size = 15.0
	hum.max_db = 2.0
	var gs := get_node_or_null("/root/GlobalState")
	var is_player: bool = _ship != null and gs != null and _ship == gs.get("player")
	hum.volume_db = HUM_PLAYER_DB if is_player else HUM_TRAFFIC_DB
	hum.max_distance = 350.0 if is_player else 250.0
	add_child(hum)
	hum.finished.connect(func() -> void:
		if is_inside_tree():
			hum.play())
	hum.play()


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
	if hum != null:
		hum.global_position = _ship.global_position
	var beam_length := station_origin.distance_to(end_point)
	visible = true
	global_position = station_origin.lerp(end_point, 0.5)
	# A straight-up beam (Crown Haven's pads) needs another up, or looking_at
	# fails on the colinear vectors (ChatGPT's harbor test).
	var up := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.99 else Vector3.UP
	global_basis = Basis.looking_at(direction, up) \
		* Basis(Vector3.RIGHT, PI * 0.5)
	# Set mesh height directly rather than scaling the node. Stations can be
	# scaled for their models, and inherited node scale made the old beam run far
	# beyond the ship.
	_cylinder.height = beam_length
	# A long beam (a big station's lane) is thicker, or it vanishes at range.
	var radius := maxf(0.42, beam_length * BEAM_WIDTH_PER_LENGTH)
	_cylinder.top_radius = radius
	_cylinder.bottom_radius = radius
