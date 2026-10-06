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
## The player's own beam is heard at a steady level wherever the camera is
## (playtest 2026-10-06 finding 1: as a 3D sound at the ship, the chase camera's
## distance took ~20 dB off it). Traffic beams stay 3D and fade with distance.
const HUM_PLAYER_DB := -8.0
const HUM_TRAFFIC_DB := -11.2
## A latch click when the beam takes hold and when it lets go (finding 2).
const CLICK_STREAM := preload("res://sound/ShipSounds/tractor_click.wav")
const CLICK_DB := -4.0
## AudioStreamPlayer for the player's beam, AudioStreamPlayer3D for traffic.
var hum: Node
var _is_player := false


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
	var gs := get_node_or_null("/root/GlobalState")
	_is_player = _ship != null and gs != null and _ship == gs.get("player")
	if _is_player:
		var flat := AudioStreamPlayer.new()
		flat.volume_db = HUM_PLAYER_DB
		hum = flat
		_click()
	else:
		var spatial := AudioStreamPlayer3D.new()
		spatial.unit_size = 15.0
		spatial.max_db = 2.0
		spatial.volume_db = HUM_TRAFFIC_DB
		spatial.max_distance = 250.0
		hum = spatial
	hum.name = "TractorHum"
	hum.set("stream", HUM_STREAM)
	hum.set("bus", "SFX")
	add_child(hum)
	hum.connect("finished", func() -> void:
		if is_inside_tree():
			hum.call("play"))
	hum.call("play")


## The latch: played on the scene root so the let-go click outlives the beam.
func _click() -> void:
	var tree := get_tree() if is_inside_tree() else null
	if tree == null or tree.current_scene == null:
		return
	var click := AudioStreamPlayer.new()
	click.stream = CLICK_STREAM
	click.bus = "SFX"
	click.volume_db = CLICK_DB
	tree.current_scene.add_child(click)
	click.finished.connect(click.queue_free)
	click.play()


func _exit_tree() -> void:
	if _is_player:
		_click()


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
	if hum is Node3D:
		(hum as Node3D).global_position = _ship.global_position
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
