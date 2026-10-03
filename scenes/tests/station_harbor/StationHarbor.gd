extends Node3D

## Standalone F6 sandbox. No GameRoot, campaign loading, story setup, or saves.
const StationType := preload("res://scenes/tests/station_harbor/HarborStation.gd")
const BeamType := preload("res://scripts/effects/DockingTractorBeam.gd")
const StationLights := preload("res://scripts/visuals/StationLights.gd")
const MODEL_ROOT := "res://assets/NewForReview/Stations/"
@onready var player = $PlayerShip
@onready var hud = $CanvasLayer/UIManager
@onready var overview: Camera3D = $OverviewCamera
@onready var dock_camera: Camera3D = $DockCamera
var stations: Array = []
var selected := 0
var busy := false
var docked_station: Node3D
var traffic_dock_count := 0
var traffic: Array[Node3D] = []
var generated_planet_count := 0
var generated_asteroid_count := 0
var _service_modes: Dictionary = {}
var _previous_system: Node3D
var _previous_system_id := ""
var _previous_paused := false

func _enter_tree() -> void:
	# Autoloads still exist, but this test never starts the campaign runtime.
	# Stop ambient/story polling for this run; restore modes when leaving.
	for service_name in ["StoryManager", "StoryQuestManager", "Nova", "AmbientChat", "LLMInterface", "TTSInterface", "SpeechService", "PlayerInteractionQueue"]:
		var service := get_node_or_null("/root/" + service_name)
		if service != null:
			_service_modes[service] = service.process_mode
			service.process_mode = Node.PROCESS_MODE_DISABLED
	_previous_system = GlobalState.active_system_root
	_previous_system_id = GlobalState.current_system_id
	_previous_paused = GlobalState.paused

func _ready() -> void:
	var config := SystemConfig.new()
	config.system_name = "Station Harbor Test"
	config.system_id = "system.test.station_harbor"
	config.legacy_id = "station_harbor_test"
	config.seed_value = 20261003
	config.starfield_seed = 61003.0
	config.nebula_seed = 61003
	config.nebula_colors = [Color(0.12, 0.22, 0.45), Color(0.3, 0.12, 0.25)]
	config.station_count = 0
	config.npc_patrol_count = 0
	config.npc_minor_chance = 0.0
	config.npc_minor_max = 0
	config.ambient_energy = 0.7
	var generated := SystemFactory.generate(config)
	if not bool(generated.get("ok", false)):
		push_error("Station harbor: system generation failed")
		get_tree().quit(1)
		return
	var system: Node3D = generated.root
	# Replace only this generated instance's campaign NPC manager with test traffic.
	var manager := system.get_node_or_null("NPCManager")
	if manager != null:
		system.remove_child(manager)
		manager.free()
	$SystemContainer.add_child(system)
	# Soft fill makes the metal paint readable against the generated space sky.
	for heading in [Vector3(-35, -35, 0), Vector3(25, 145, 0)]:
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = heading
		fill.light_color = Color(0.72, 0.83, 1.0)
		fill.light_energy = 0.65
		system.add_child(fill)
	GlobalState.active_system_root = system
	GlobalState.current_system_id = config.legacy_id
	GlobalState.paused = false
	generated_planet_count = int(generated.planet_count)
	generated_asteroid_count = int(generated.asteroid_count)
	# Above the generator's planet/belt plane: full-size stations have clear space.
	_add_station(system, "Cinder Anchorage", "01_CinderAnchorage/CinderAnchorage_LOD1.glb", Vector3(-1600, 3600, 0), 0.99)
	_add_station(system, "Meridian Exchange", "02_MeridianExchange/MeridianExchange_LOD1.glb", Vector3(1600, 3600, 0), 1.045)
	if stations.any(func(station) -> bool: return station.berths.size() != 24):
		push_error("Station harbor requires all 24 authored berths on each station")
		get_tree().quit(1)
		return
	stage_player(0)
	for station_index in 2:
		for ship_index in 2:
			_spawn_friendly(stations[station_index], ship_index, station_index)
	if "--station-harbor-smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_smoke_test")
	elif "--station-harbor-snapshot" in OS.get_cmdline_user_args():
		call_deferred("_snapshot")
	print("[StationHarbor] Ready: generated system, two stations, 48 berths, four friendly ships. No campaign loaded.")

func _add_station(system: Node3D, label: String, path: String, location: Vector3, spin: float) -> void:
	var station := StationType.new()
	station.name = label.replace(" ", "")
	station.display_name = label
	station.world_id = "station.test." + station.name.to_snake_case()
	station.model_path = MODEL_ROOT + path
	station.rpm = spin
	station.position = location
	if stations.is_empty():
		station.add_to_group("primary_station")
	system.add_child(station)
	stations.append(station)

func stage_player(index: int) -> void:
	if busy or player.is_docked or index < 0 or index >= stations.size():
		return
	selected = index
	var station = stations[index]
	player.hard_stop()
	player.end_docking_camera()
	player.global_position = station.approach_position(station.player_berth)
	player.global_basis = station.berth_basis(station.player_berth)
	player.camera_pivot.global_position = player.global_position
	player.camera_pivot.rotation = player.rotation + Vector3(-0.25, 0, 0)
	GlobalState.active_target = station
	_frame_station()
	overview.make_current()
	player.set_process_unhandled_input(false)
	hud.status.text = "%s · approach lane ready" % station.display_name

func _frame_station() -> void:
	var station: Node3D = stations[selected]
	overview.global_position = station.global_position + Vector3(1900, 1550, 2600)
	overview.look_at(station.global_position + Vector3.UP * 220.0)

func toggle_view() -> void:
	if overview.current:
		if player.is_docked:
			dock_camera.make_current()
		else:
			player.camera.make_current()
		player.set_process_unhandled_input(true)
	else:
		_frame_station()
		overview.make_current()
		player.set_process_unhandled_input(false)

func request_dock() -> void:
	if busy or player.is_docked:
		return
	GlobalState.active_target = stations[selected]
	player.begin_target_navigation("DOCK")
	player.camera.make_current()
	player.set_process_unhandled_input(true)
	hud.status.text = "Approaching berth · awaiting tractor capture"

func begin_player_docking(station: Node3D, ship: Node3D) -> void:
	if busy or ship != player or player.is_docked:
		return
	busy = true
	docked_station = station
	var berth: Node3D = station.player_berth
	station.reservations[berth.name] = player
	player.hard_stop()
	player.is_docked = true
	player.set_physics_process(false)
	_update_dock_camera()
	dock_camera.make_current()
	var beam := _beam(berth, player)
	hud.status.text = "TRACTOR LOCK · pulling into %s" % berth.name
	var pull := create_tween()
	pull.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pull.tween_property(player, "global_position", station.berth_position(berth), 4.0)
	pull.parallel().tween_property(player, "quaternion", station.berth_basis(berth).get_rotation_quaternion(), 4.0)
	await pull.finished
	hud.status.text = "Alignment confirmed · securing clamps"
	await get_tree().create_timer(1.5).timeout
	beam.queue_free()
	station.completed_docks += 1
	busy = false
	hud.status.text = "DOCKED · %s · clamps secure" % station.display_name

func undock_player() -> void:
	if busy or not player.is_docked or not is_instance_valid(docked_station):
		return
	busy = true
	var station = docked_station
	var berth: Node3D = station.player_berth
	var beam := _beam(berth, player)
	hud.status.text = "Clamps released · tractor guiding ship clear"
	var push := create_tween()
	push.tween_property(player, "global_position", station.approach_position(berth), 3.0).set_trans(Tween.TRANS_SINE)
	await push.finished
	beam.queue_free()
	station.reservations.erase(berth.name)
	player.is_docked = false
	player.end_docking_camera()
	player.camera.make_current()
	player.set_physics_process(true)
	player.hard_stop()
	docked_station = null
	busy = false
	hud.status.text = "Departure lane clear · flight controls restored"

func _process(_delta: float) -> void:
	if player.is_docked and is_instance_valid(docked_station):
		_update_dock_camera()

func _update_dock_camera() -> void:
	# Look from the open side of the berth; the standard radial dock camera
	# would sit behind a radial pier on these side-facing docking ports.
	var berth: Node3D = docked_station.player_berth
	var outward := berth.global_basis.x.normalized()
	var radial := berth.global_position - docked_station.global_position
	radial.y = 0.0
	dock_camera.global_position = player.global_position + outward * 115.0 + radial.normalized() * 65.0 + Vector3.UP * 65.0
	dock_camera.look_at(player.global_position.lerp(berth.global_position, 0.25))

func _beam(anchor: Node3D, ship: Node3D) -> Node3D:
	var beam := BeamType.new()
	add_child(beam)
	beam.configure(anchor, ship)
	return beam

func _spawn_friendly(station: Node3D, index: int, station_index: int) -> void:
	var ship = load("res://scenes/npc_ship.tscn").instantiate()
	ship.ship_role = "Logistics"
	ship.faction = ["aurelia", "vanguard"][station_index]
	ship.persistent_id = "harbor.freighter.%d.%d" % [station_index, index]
	ship.set_meta("civilian_traffic", true)
	ship.set_meta("npc_attack_protected", true)
	GlobalState.active_system_root.add_child(ship)
	ship.display_name = "%s Courier %d" % [station.display_name, index + 1]
	ship.ceasefire = true
	ship.set_meta("harbor_docked", false)
	ship.behavior = "patrol"
	ship.set_physics_process(false) # This scene owns traffic; no combat AI.
	# Top tier, opposite piers; player has a different reserved berth.
	var berth: Node3D = station.berths[station.berths.size() - 8 + index * 2]
	ship.global_position = station.approach_position(berth) + Vector3.UP * (60.0 + index * 50.0)
	ship.global_basis = station.berth_basis(berth)
	traffic.append(ship)
	_traffic_cycle(ship, station, berth, index * 5.0 + station_index * 2.0)

func _traffic_cycle(ship: Node3D, station: Node3D, berth: Node3D, delay: float) -> void:
	await get_tree().create_timer(delay + 0.1).timeout
	while is_instance_valid(ship) and is_inside_tree():
		station.reservations[berth.name] = ship
		var beam := _beam(berth, ship)
		var arrival := ship.create_tween()
		arrival.tween_property(ship, "global_position", station.berth_position(berth), 5.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await arrival.finished
		beam.queue_free()
		traffic_dock_count += 1
		ship.set_meta("harbor_docked", true)
		# Ships stay visible alongside the pier while docked.
		await get_tree().create_timer(12.0 + delay).timeout
		beam = _beam(berth, ship)
		ship.set_meta("harbor_docked", false)
		var departure := ship.create_tween()
		departure.tween_property(ship, "global_position", station.approach_position(berth), 4.0).set_trans(Tween.TRANS_SINE)
		await departure.finished
		beam.queue_free()
		station.reservations.erase(berth.name)
		var loop := ship.create_tween()
		var lane: Vector3 = station.approach_position(berth)
		loop.tween_property(ship, "global_position", lane + Vector3.UP * 180.0, 5.0)
		loop.tween_interval(4.0)
		loop.tween_property(ship, "global_position", lane, 5.0)
		await loop.finished

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_1: stage_player(0)
		KEY_2: stage_player(1)
		KEY_D: request_dock()
		KEY_U: undock_player()
		KEY_V: toggle_view()
		KEY_ESCAPE: get_tree().quit()
		_: return
	get_viewport().set_input_as_handled()

func _smoke_test() -> void:
	await get_tree().physics_frame
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		push_error("[StationHarbor] FAIL: test timed out")
		get_tree().quit(1))
	var initial_main_scene := str(ProjectSettings.get_setting("application/run/main_scene"))
	assert(initial_main_scene == "res://scenes/main.tscn")
	assert(generated_planet_count >= 2 and generated_asteroid_count > 0)
	assert(traffic.size() == 4)
	for station in stations:
		assert(station.berths.size() == 24 and station.rotor != null)
		assert(station.has_node("StationLights"))
		assert(station.get_node("StationLights")._beacons.size() == 7)
		var clearance := PhysicsShapeQueryParameters3D.new()
		var hull := SphereShape3D.new()
		hull.radius = 8.0
		clearance.shape = hull
		clearance.collision_mask = 4
		var visitors: Array[RID] = []
		for ship in traffic:
			visitors.append((ship as CollisionObject3D).get_rid())
		clearance.exclude = visitors
		for berth in station.berths:
			clearance.transform = Transform3D(Basis.IDENTITY, station.berth_position(berth))
			assert(get_world_3d().direct_space_state.intersect_shape(clearance).is_empty(), "Berth blocked: " + str(berth.name))
		var lane := PhysicsRayQueryParameters3D.create(station.approach_position(station.player_berth), station.berth_position(station.player_berth), 4)
		lane.exclude = visitors
		assert(get_world_3d().direct_space_state.intersect_ray(lane).is_empty(), "Player approach crosses station hull")
		var original_rotation: Vector3 = station.rotation
		var initial_rotor: Basis = station.rotor.basis
		var fixed_marker: Transform3D = station.player_berth.global_transform
		stage_player(stations.find(station))
		request_dock()
		var timeout := 0.0
		while station.completed_docks == 0 and timeout < 30.0:
			await get_tree().create_timer(0.1).timeout
			timeout += 0.1
		if station.completed_docks == 0:
			push_error("[StationHarbor] FAIL: player could not dock at " + station.display_name)
			get_tree().quit(1)
			return
		assert(player.is_docked and not busy)
		assert(player.global_position.distance_to(station.berth_position(station.player_berth)) < 0.1)
		assert(station.rotation.is_equal_approx(original_rotation))
		assert(not station.rotor.basis.is_equal_approx(initial_rotor))
		assert(station.player_berth.global_transform.is_equal_approx(fixed_marker))
		undock_player()
		while busy:
			await get_tree().create_timer(0.1).timeout
		assert(not player.is_docked and player.is_physics_processing())
		assert(not station.reservations.has(station.player_berth.name))
	assert(traffic_dock_count >= 4)
	print("[StationHarbor] PASS: both player tractor docks/undocks, 48 fixed berths, rotating habitats, 14 beacon drones, four friendly arrivals, generated planets/belts; main scene unchanged.")
	get_tree().quit()

func _snapshot() -> void:
	await get_tree().create_timer(7.0).timeout
	for index in 2:
		stage_player(index)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.tmp_godot_user/station_harbor_%d.png" % index)
	request_dock()
	while not busy:
		await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.tmp_godot_user/station_harbor_tractor.png")
	while busy:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.tmp_godot_user/station_harbor_docked.png")
	get_tree().quit()

func _exit_tree() -> void:
	for service in _service_modes:
		if is_instance_valid(service):
			service.process_mode = _service_modes[service]
	GlobalState.active_system_root = _previous_system if is_instance_valid(_previous_system) else null
	GlobalState.current_system_id = _previous_system_id
	GlobalState.active_target = null
	GlobalState.paused = _previous_paused
