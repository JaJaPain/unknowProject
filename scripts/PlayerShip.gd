extends CharacterBody3D

@export var max_speed: float = 25.0
@export var max_health: float = 100.0
var health: float = 100.0
var faction: String = "player"
var destroyed: bool = false
var is_docked: bool = false
@export var rotation_speed: float = 3.5

var current_shield: float = 0.0
var shield_regen_timer: float = 0.0
var current_speed: float = 0.0

# Drawback tracking variables
var engine_stall_timer: float = 0.0
var mining_cycles: int = 0
var mining_continuous_timer: float = 0.0

# Navigation variables
var target_position: Variant = null # null or Vector3
var is_aligning: bool = false:
	set(val):
		if val != is_aligning:
			is_aligning = val
			if is_aligning:
				AudioManager.play_align()

var nav_mode: String = "MANUAL":
	set(val):
		if val != nav_mode:
			nav_mode = val
			if val != "DOCK":
				dock_stuck_timer = 0.0
				last_dock_distance = INF
				last_dock_target = null
			if val != "JUMP_APPROACH":
				staged_jump_gate_id = 0
			if val in ["APPROACH", "APPROACH_1K", "JUMP_APPROACH", "ORBIT", "MINE", "ATTACK", "DOCK"]:
				is_aligning = false
				is_aligning = true

var fire_cooldown: float = 0.0

# Camera controls
var camera_aligned: bool = true
var last_nav_mode: String = "MANUAL"
var dock_stuck_timer: float = 0.0
var last_dock_distance: float = INF
var last_dock_target: Node3D = null
var staged_jump_gate_id: int = 0
var avoidance_obstacle_id: int = 0
var avoidance_side: Vector3 = Vector3.ZERO
var rmb_down_time: float = 0.0
var last_target: Node3D = null
var drones: Array[Node3D] = []
var drone_rotations: Array[Vector3] = []

@onready var visual: Node3D = $Visual
@onready var mining_laser: MeshInstance3D = $MiningLaser
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D

func _ready():
	GlobalState.player = self
	mining_laser.visible = false
	current_shield = GlobalState.shield_capacity
	
	# Decouple camera pivot transform from player's parent transform
	camera_pivot.top_level = true
	camera_pivot.global_position = global_position
	camera_pivot.rotation_degrees = Vector3(-15, 0, 0) # Pitch down, looking at player
	
	# Connect to target change signal
	GlobalState.target_changed.connect(_on_target_changed)
	
	# Create two orbiting drones
	_create_drones()

func sync_camera_to_ship() -> void:
	camera_pivot.global_position = global_position

func _on_target_changed(new_target: Node3D):
	staged_jump_gate_id = 0
	if new_target == null:
		mining_laser.visible = false
		if nav_mode in ["APPROACH", "APPROACH_1K", "JUMP_APPROACH", "ORBIT", "MINE", "ATTACK", "DOCK"]:
			nav_mode = "MANUAL"
			target_position = null

func _unhandled_input(event: InputEvent):
	# While docked the dock UI owns the screen — block any world-bound
	# input (LMB fly-to, RMB targeting, camera orbit, autopilot keys).
	# Control children of the dock menu still get their own _gui_input
	# before this runs, so dock buttons keep working.
	if is_docked:
		return
	# Autopilot override keys
	if event.is_action_pressed("override_approach"):
		var t = GlobalState.active_target
		if t and is_instance_valid(t):
			nav_mode = "JUMP_APPROACH" if t.is_in_group("jumpgate") else "APPROACH"
			var ui = GlobalState.get_ui_manager()
			if ui and ui.has_method("show_target_marker"):
				ui.show_target_marker(t.global_position)
	elif event.is_action_pressed("override_orbit"):
		var t = GlobalState.active_target
		if t and is_instance_valid(t):
			nav_mode = "ORBIT"
			var ui = GlobalState.get_ui_manager()
			if ui and ui.has_method("show_target_marker"):
				ui.show_target_marker(t.global_position)
	elif event.is_action_pressed("override_action"):
		var t = GlobalState.active_target
		if t and is_instance_valid(t):
			if t.is_in_group("asteroid"):
				nav_mode = "MINE"
			elif t.is_in_group("station"):
				nav_mode = "DOCK"
			elif t.is_in_group("jumpgate"):
				var ui = GlobalState.get_ui_manager()
				if ui and ui.has_method("activate_selected_jumpgate"):
					ui.activate_selected_jumpgate()
				return
			else:
				nav_mode = "ATTACK"
			var ui = GlobalState.get_ui_manager()
			if ui and ui.has_method("show_target_marker"):
				ui.show_target_marker(t.global_position)

	# Handle Mouse Zoom
	if event.is_action_pressed("zoom_in"):
		camera.position.z = max(camera.position.z - 1.5, 6.0)
	elif event.is_action_pressed("zoom_out"):
		camera.position.z = min(camera.position.z + 1.5, 50.0)
		
	# RMB Click vs Drag detection
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			rmb_down_time = Time.get_unix_time_from_system()
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			var hold_duration = Time.get_unix_time_from_system() - rmb_down_time
			if hold_duration < 0.25:
				# Short RMB click: Try targeting / open context menu
				var hit = get_mouse_raycast_hit()
				if hit.has("collider"):
					var entity: Node = hit.collider
					var system_root := GlobalState.get_system_root()
					while entity and system_root and entity.get_parent() != system_root:
						entity = entity.get_parent()
					if entity and entity != self:
						GlobalState.active_target = entity
						var ui = GlobalState.get_ui_manager()
						if ui and ui.has_method("show_context_menu"):
							ui.show_context_menu(entity)
							
	# Drag Camera Orbit
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotation.y -= event.relative.x * 0.003
		camera_pivot.rotation.x -= event.relative.y * 0.003
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -deg_to_rad(80), deg_to_rad(80))
		camera_aligned = true # Release camera alignment control
		
	# Left Click & Double-click
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if event.double_click:
			# Free space movement steering
			var hit = get_mouse_raycast_hit()
			if hit.has("position"):
				double_click_move(hit.position)
			else:
				# Clicked into deep space, project a point in forward depth
				var mouse_pos = get_viewport().get_mouse_position()
				var ray_normal = camera.project_ray_normal(mouse_pos)
				double_click_move(camera.global_position + ray_normal * 150.0)
		else:
			# Single click selection
			var hit = get_mouse_raycast_hit()
			if hit.has("collider"):
				var entity = hit.collider
				while entity and entity.get_parent() != get_parent():
					entity = entity.get_parent()
				if entity and entity != self:
					GlobalState.active_target = entity

func get_mouse_raycast_hit() -> Dictionary:
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_normal = camera.project_ray_normal(mouse_pos)
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_normal * 1000.0)
	query.collide_with_areas = true
	var result = space_state.intersect_ray(query)
	return result

func _physics_process(delta: float):
	if GlobalState.paused:
		mining_laser.visible = false
		return
		
	# Shield Regeneration
	if shield_regen_timer > 0.0:
		shield_regen_timer -= delta
	elif current_shield < GlobalState.shield_capacity and GlobalState.shield_regen_rate > 0.0:
		current_shield = min(current_shield + GlobalState.shield_regen_rate * delta, GlobalState.shield_capacity)
		
	if engine_stall_timer > 0.0:
		engine_stall_timer -= delta
		
	if mining_laser.visible:
		mining_continuous_timer += delta
		if GlobalState.has_max_deep_mining and mining_continuous_timer > 10.0:
			mining_continuous_timer = 0.0
			take_damage(5.0, "self")
	else:
		mining_continuous_timer = max(0.0, mining_continuous_timer - delta)
		
	# Animate orbiting drones
	for i in range(drones.size()):
		var pivot = drones[i]
		if is_instance_valid(pivot):
			var rot_speed = drone_rotations[i]
			pivot.rotate_x(rot_speed.x * delta)
			pivot.rotate_y(rot_speed.y * delta)
			pivot.rotate_z(rot_speed.z * delta)
			
	# Update drone colors based on health
	_update_drone_colors()
			
	# Follow player position
	camera_pivot.global_position = global_position
	
	# Autopilot Camera Auto-facing
	var current_target = GlobalState.active_target
	if current_target != last_target:
		if nav_mode != "MANUAL" and current_target != null:
			camera_aligned = false
		last_target = current_target
		
	if nav_mode != last_nav_mode:
		if nav_mode != "MANUAL":
			camera_aligned = false
		last_nav_mode = nav_mode
		
	if nav_mode != "MANUAL" and not camera_aligned:
		# Target camera rotation should follow ship heading (looking from behind)
		var target_rot_y = rotation.y
		var target_rot_x = rotation.x - deg_to_rad(15) # Tilt down slightly
		
		var diff_y = fposmod(target_rot_y - camera_pivot.rotation.y + PI, TAU) - PI
		var diff_x = fposmod(target_rot_x - camera_pivot.rotation.x + PI, TAU) - PI
		
		camera_pivot.rotation.y += diff_y * delta * 4.0
		camera_pivot.rotation.x += diff_x * delta * 4.0
		
		# Check if the ship itself has successfully aligned with the target
		var look_target_pos = Vector3.ZERO
		var has_look_target = false
		
		if target_position != null:
			look_target_pos = target_position
			has_look_target = true
		elif current_target and is_instance_valid(current_target):
			look_target_pos = current_target.global_position
			has_look_target = true
			
		if has_look_target:
			var to_target = look_target_pos - global_position
			if to_target.length() > 1.0:
				var target_dir = to_target.normalized()
				var ship_forward = -global_transform.basis.z
				var angle_to_target = ship_forward.angle_to(target_dir)
				
				# If the ship is facing the target (within ~5 degrees) and the camera is behind the ship
				if angle_to_target < 0.08:
					var cam_diff_y = fposmod(rotation.y - camera_pivot.rotation.y + PI, TAU) - PI
					var cam_diff_x = fposmod(rotation.x - deg_to_rad(15) - camera_pivot.rotation.x + PI, TAU) - PI
					if abs(cam_diff_y) < 0.08 and abs(cam_diff_x) < 0.08:
						camera_aligned = true
			else:
				camera_aligned = true
		else:
			camera_aligned = true
			
	# Check if cargo filled up (only matters when carrying ore; special
	# cargo items don't go through cargo_max the same way)
	if GlobalState.cargo_type == GlobalState.CargoType.ORE and GlobalState.cargo >= GlobalState.cargo_max:
		mining_laser.visible = false
		if nav_mode == "MINE":
			nav_mode = "MANUAL"
			target_position = null
	# When a special item is loaded, hide the mining laser entirely —
	# the player can't mine until they deliver or jettison the special.
	elif GlobalState.cargo_type == GlobalState.CargoType.SPECIAL:
		mining_laser.visible = false
			
	if fire_cooldown > 0.0:
		fire_cooldown -= delta
		
	# Autopilot updates
	var active_target = GlobalState.active_target
	if active_target and is_instance_valid(active_target) and not active_target.get("destroyed"):
		var dist = global_position.distance_to(active_target.global_position)
		
		# Autopilot modes
		match nav_mode:
			"APPROACH":
				target_position = active_target.global_position
					
			"APPROACH_1K":
				target_position = active_target.global_position
				if dist < 1000.0:
					target_position = null
					nav_mode = "MANUAL"

			"JUMP_APPROACH":
				var gate_instance_id := active_target.get_instance_id()
				var approach_position: Vector3 = active_target.global_position
				if active_target.has_method("get_approach_position"):
					approach_position = active_target.call("get_approach_position") as Vector3

				if staged_jump_gate_id != gate_instance_id:
					if _is_inside_gate_entry_corridor(active_target, approach_position):
						staged_jump_gate_id = gate_instance_id
					elif global_position.distance_to(approach_position) <= 18.0:
						staged_jump_gate_id = gate_instance_id

				target_position = active_target.global_position \
					if staged_jump_gate_id == gate_instance_id \
					else approach_position
					
			"MINE":
				# Refuse to mine when a special item is loaded OR when
				# the ore hold is full. EMPTY hold is fine — that's the
				# default state on a fresh game and the player should be
				# able to mine from empty. (Previous condition used
				# `cargo_type != ORE` which incorrectly bailed on EMPTY.)
				if not GlobalState.can_accept_ore() or GlobalState.cargo >= GlobalState.cargo_max:
					nav_mode = "MANUAL"
					target_position = null
					mining_laser.visible = false
				else:
					target_position = active_target.global_position
					if dist < 75.0:
						steer_towards(active_target.global_position, delta)
						perform_action(active_target, delta)
					else:
						mining_laser.visible = false
					
			"ATTACK":
				target_position = active_target.global_position
				if dist < 75.0:
					steer_towards(active_target.global_position, delta)
					perform_action(active_target, delta)
					
			"DOCK":
				var docking_position := _get_docking_position(active_target)
				var distance_to_dock := global_position.distance_to(docking_position)
				target_position = docking_position

				if last_dock_target != active_target:
					last_dock_target = active_target
					last_dock_distance = distance_to_dock
					dock_stuck_timer = 0.0
				elif distance_to_dock < last_dock_distance - 0.1:
					dock_stuck_timer = 0.0
				elif distance_to_dock <= 35.0:
					dock_stuck_timer += delta
				else:
					dock_stuck_timer = 0.0
				last_dock_distance = distance_to_dock

				if distance_to_dock <= 6.0 or dock_stuck_timer >= 1.5:
					global_position = docking_position
					velocity = Vector3.ZERO
					current_speed = 0.0
					target_position = null
					nav_mode = "MANUAL"
					dock_stuck_timer = 0.0
					last_dock_distance = INF
					last_dock_target = null
					if active_target.has_method("dock_player"):
						active_target.dock_player()
						
			"ORBIT":
				var to_target = global_position - active_target.global_position
				var orbit_radius = 25.0
				var tangent = Vector3(-to_target.z, 0, to_target.x).normalized()
				var radial = to_target.normalized()
				
				var des_dir: Vector3
				if dist > orbit_radius:
					des_dir = (tangent * 0.7 - radial * 0.3).normalized()
				else:
					des_dir = (tangent * 0.7 + radial * 0.3).normalized()
				
				target_position = global_position + des_dir * 10.0
	else:
		mining_laser.visible = false
		if nav_mode in ["APPROACH", "APPROACH_1K", "JUMP_APPROACH", "ORBIT", "MINE", "ATTACK", "DOCK"]:
			nav_mode = "MANUAL"
			target_position = null

	# Move and steer
	if target_position != null:
		var dest = target_position as Vector3
		var avoidance := _get_autopilot_avoidance(dest, active_target)
		var final_steer_target: Vector3 = avoidance.get("steer_target", dest)
		steer_towards(final_steer_target, delta)
		
		var speed_limit: float = max_speed * GlobalState.engine_speed_mult
		var target_speed: float = speed_limit
		
		# Proportional speed controller to maintain safe distance from targets
		if active_target and is_instance_valid(active_target):
			var dist = global_position.distance_to(active_target.global_position)
			
			if nav_mode == "APPROACH":
				var target_stop_dist = 60.0
				if active_target.name == "GasGiant":
					target_stop_dist = 750.0
				elif active_target.name == "RockyPlanet":
					target_stop_dist = 350.0
				elif active_target.is_in_group("station"):
					target_stop_dist = 110.0
				elif active_target.is_in_group("asteroid") or active_target.is_in_group("ship"):
					target_stop_dist = 60.0
				target_speed = clamp((dist - target_stop_dist) * 4.0, -speed_limit, speed_limit)
			elif nav_mode == "JUMP_APPROACH":
				if staged_jump_gate_id == active_target.get_instance_id():
					var direction_to_gate: Vector3 = (
						active_target.global_position - global_position
					).normalized()
					var facing_gate: bool = (-global_transform.basis.z).angle_to(direction_to_gate) < 0.08
					target_speed = clamp((dist - 85.0) * 4.0, -speed_limit, speed_limit) \
						if facing_gate else 0.0
				else:
					var remaining_to_stage := global_position.distance_to(target_position as Vector3)
					target_speed = clampf(
						(remaining_to_stage - 8.0) * 2.5,
						0.0,
						speed_limit * 0.75
					)
			elif nav_mode == "MINE" and active_target.is_in_group("asteroid"):
				# Keep 35m from mined asteroids to prevent crashing
				target_speed = clamp((dist - 35.0) * 3.0, -speed_limit, speed_limit)
			elif nav_mode == "ATTACK" and active_target.is_in_group("ship"):
				# Keep 45m from attacked hostile NPC ships
				target_speed = clamp((dist - 45.0) * 3.0, -speed_limit, speed_limit)
			elif nav_mode == "DOCK":
				var remaining_dock_distance := global_position.distance_to(target_position as Vector3)
				target_speed = clamp(remaining_dock_distance * 2.0, 0.0, speed_limit)

		# Give the ship time to turn around nearby obstacles instead of charging
		# toward a detour point at full cruise speed.
		if bool(avoidance.get("is_avoiding", false)):
			var obstacle_distance := float(avoidance.get("obstacle_distance", 9999.0))
			var avoidance_speed_limit: float = speed_limit * clampf(
				obstacle_distance / 180.0,
				0.3,
				0.75
			)
			target_speed = min(target_speed, avoidance_speed_limit)
			
		# Calculate acceleration taking cargo mass into account
		var accel = 15.0 * GlobalState.acceleration_mult
		if not GlobalState.ignore_cargo_mass and GlobalState.cargo_max > 0:
			var cargo_ratio = GlobalState.cargo / GlobalState.cargo_max
			# Full cargo reduces acceleration by up to 60%
			accel *= (1.0 - (cargo_ratio * 0.6))
			
		if engine_stall_timer > 0.0:
			target_speed = 0.0
			accel = 15.0 # Decelerate quickly on stall
			
		current_speed = move_toward(current_speed, target_speed, accel * delta)
			
		var forward_dir = -global_transform.basis.z
		velocity = forward_dir * current_speed
		move_and_slide()
		
		if global_position.distance_to(dest) < 2.0:
			if nav_mode == "MANUAL":
				target_position = null
	else:
		# Decelerate to stop
		var accel = 15.0 * GlobalState.acceleration_mult
		current_speed = move_toward(current_speed, 0.0, accel * delta)
		if current_speed > 0.0:
			var forward_dir = -global_transform.basis.z
			velocity = forward_dir * current_speed
			move_and_slide()
		else:
			velocity = Vector3.ZERO
		
	# Check alignment completion
	if is_aligning:
		var look_target_pos = Vector3.ZERO
		var has_look_target = false
		
		if target_position != null:
			look_target_pos = target_position
			has_look_target = true
		elif active_target and is_instance_valid(active_target):
			look_target_pos = active_target.global_position
			has_look_target = true
			
		if has_look_target:
			var to_target = look_target_pos - global_position
			if to_target.length() > 1.0:
				var target_dir = to_target.normalized()
				var ship_forward = -global_transform.basis.z
				var angle_to_target = ship_forward.angle_to(target_dir)
				if angle_to_target < 0.08:
					is_aligning = false
			else:
				is_aligning = false
		else:
			is_aligning = false

func _get_autopilot_avoidance(destination: Vector3, navigation_target: Node3D) -> Dictionary:
	var route := destination - global_position
	var route_length := route.length()
	if route_length < 1.0:
		_clear_avoidance_state()
		return {"steer_target": destination, "is_avoiding": false}

	var route_direction := route / route_length
	var best_obstacle: Node3D = null
	var best_clearance := 0.0
	var best_distance_to_route := INF
	var best_distance_along_route := INF

	for obstacle in _get_autopilot_obstacles():
		if obstacle == navigation_target or obstacle == self:
			continue
		if obstacle.get("destroyed"):
			continue

		var to_obstacle := obstacle.global_position - global_position
		var distance_along_route := clampf(to_obstacle.dot(route_direction), 0.0, route_length)
		# Ignore objects behind the ship and objects beyond the destination.
		if to_obstacle.dot(route_direction) <= 0.0 or distance_along_route >= route_length:
			continue

		var closest_route_point := global_position + route_direction * distance_along_route
		var distance_to_route := obstacle.global_position.distance_to(closest_route_point)
		var required_clearance := _get_obstacle_radius(obstacle) + _get_obstacle_safety_margin(obstacle)
		if distance_to_route >= required_clearance:
			continue

		# Favor the first obstacle on the route. The normalized penetration is a
		# tiebreaker when large safety envelopes overlap.
		var penetration: float = (required_clearance - distance_to_route) / maxf(required_clearance, 1.0)
		var score: float = distance_along_route - penetration * 20.0
		var best_score: float = best_distance_along_route - (
			(best_clearance - best_distance_to_route) / maxf(best_clearance, 1.0)
		) * 20.0
		if best_obstacle == null or score < best_score:
			best_obstacle = obstacle
			best_clearance = required_clearance
			best_distance_to_route = distance_to_route
			best_distance_along_route = distance_along_route

	if best_obstacle == null:
		_clear_avoidance_state()
		return {"steer_target": destination, "is_avoiding": false}

	var obstacle_id: int = best_obstacle.get_instance_id()
	if avoidance_obstacle_id != obstacle_id or avoidance_side.length_squared() < 0.5:
		avoidance_obstacle_id = obstacle_id
		avoidance_side = _choose_avoidance_side(
			best_obstacle.global_position,
			route_direction
		)

	# Aim slightly beyond the obstacle as well as to its side. That creates a
	# smooth bypass rather than steering directly toward the edge of the safety
	# envelope and then immediately turning back into it.
	var forward_offset: float = minf(best_clearance * 0.65, 220.0)
	var steer_target: Vector3 = best_obstacle.global_position \
		+ avoidance_side * (best_clearance + 12.0) \
		+ route_direction * forward_offset

	return {
		"steer_target": steer_target,
		"is_avoiding": true,
		"obstacle_distance": best_distance_along_route,
		"obstacle": best_obstacle,
	}

func _is_inside_gate_entry_corridor(gate: Node3D, approach_position: Vector3) -> bool:
	var entry_axis := approach_position - gate.global_position
	var entry_length := entry_axis.length()
	if entry_length < 1.0:
		return true

	entry_axis /= entry_length
	var gate_to_player := global_position - gate.global_position
	var axial_distance := gate_to_player.dot(entry_axis)
	if axial_distance < 0.0 or axial_distance > entry_length:
		return false

	var closest_axis_point := gate.global_position + entry_axis * axial_distance
	var radial_distance := global_position.distance_to(closest_axis_point)
	return radial_distance <= 32.0

func _get_autopilot_obstacles() -> Array[Node3D]:
	var obstacles: Array[Node3D] = []
	var seen: Dictionary = {}
	for group_name in ["celestial", "asteroid", "station", "jumpgate", "ship"]:
		for candidate in get_tree().get_nodes_in_group(group_name):
			if not candidate is Node3D or candidate == self:
				continue
			var node := candidate as Node3D
			var instance_id := node.get_instance_id()
			if seen.has(instance_id):
				continue
			seen[instance_id] = true
			obstacles.append(node)
	return obstacles

func _choose_avoidance_side(obstacle_position: Vector3, route_direction: Vector3) -> Vector3:
	var closest_route_point := global_position + route_direction * clampf(
		(obstacle_position - global_position).dot(route_direction),
		0.0,
		global_position.distance_to(obstacle_position)
	)
	var away_from_obstacle := closest_route_point - obstacle_position
	away_from_obstacle -= route_direction * away_from_obstacle.dot(route_direction)
	if away_from_obstacle.length_squared() > 0.01:
		return away_from_obstacle.normalized()

	var horizontal_side := route_direction.cross(Vector3.UP)
	if horizontal_side.length_squared() < 0.01:
		horizontal_side = route_direction.cross(Vector3.RIGHT)
	return horizontal_side.normalized()

func _get_obstacle_safety_margin(obstacle: Node3D) -> float:
	if obstacle.is_in_group("celestial"):
		var radius := _get_obstacle_radius(obstacle)
		return max(100.0, radius * 0.25)
	if obstacle.is_in_group("station"):
		return 55.0
	if obstacle.is_in_group("jumpgate"):
		return 45.0
	if obstacle.is_in_group("asteroid"):
		return 20.0
	if obstacle.is_in_group("ship"):
		return 18.0
	return 25.0

func _get_obstacle_radius(obstacle: Node3D) -> float:
	var collision := obstacle.find_child("CollisionShape3D", true, false) as CollisionShape3D
	if not collision or not collision.shape:
		return 12.0

	var world_scale := collision.global_transform.basis.get_scale().abs()
	if collision.shape is SphereShape3D:
		var sphere := collision.shape as SphereShape3D
		return sphere.radius * max(world_scale.x, world_scale.y, world_scale.z)
	if collision.shape is BoxShape3D:
		var box := collision.shape as BoxShape3D
		return (box.size * 0.5 * world_scale).length()
	if collision.shape is CylinderShape3D:
		var cylinder := collision.shape as CylinderShape3D
		return max(
			cylinder.radius * max(world_scale.x, world_scale.z),
			cylinder.height * 0.5 * world_scale.y
		)
	if collision.shape is CapsuleShape3D:
		var capsule := collision.shape as CapsuleShape3D
		return max(
			capsule.radius * max(world_scale.x, world_scale.z),
			capsule.height * 0.5 * world_scale.y
		)
	return 12.0

func _clear_avoidance_state() -> void:
	avoidance_obstacle_id = 0
	avoidance_side = Vector3.ZERO

func steer_towards(target_pos: Vector3, delta: float):
	var to_target = target_pos - global_position
	if to_target.length() > 1.0:
		var target_dir = to_target.normalized()
		if abs(target_dir.dot(Vector3.UP)) < 0.99:
			var target_basis = Basis.looking_at(target_dir, Vector3.UP)
			var target_rot = target_basis.get_euler()
			
			var diff_y = fposmod(target_rot.y - rotation.y + PI, TAU) - PI
			var diff_x = fposmod(target_rot.x - rotation.x + PI, TAU) - PI
			
			var current_rot_speed = rotation_speed
			if GlobalState.has_max_rapid_weapon and fire_cooldown > 0.0:
				current_rot_speed *= 0.85
			
			rotation.y += diff_y * delta * current_rot_speed
			rotation.x += diff_x * delta * current_rot_speed

func _get_docking_position(dockable: Node3D) -> Vector3:
	if dockable.has_method("get_docking_position"):
		return dockable.get_docking_position(global_position)

	var away_from_dockable := global_position - dockable.global_position
	if away_from_dockable.length_squared() < 0.001:
		away_from_dockable = dockable.global_transform.basis.z
	return dockable.global_position + away_from_dockable.normalized() * _estimate_docking_distance(dockable)

func _estimate_docking_distance(dockable: Node3D) -> float:
	const MINIMUM_DOCKING_DISTANCE := 100.0
	var collision := dockable.find_child("CollisionShape3D", true, false) as CollisionShape3D
	if not collision or not collision.shape:
		return MINIMUM_DOCKING_DISTANCE

	var world_scale := collision.global_transform.basis.get_scale().abs()
	var horizontal_radius := 0.0
	if collision.shape is BoxShape3D:
		var box := collision.shape as BoxShape3D
		var half_extents := box.size * 0.5 * world_scale
		horizontal_radius = Vector2(half_extents.x, half_extents.z).length()
	elif collision.shape is SphereShape3D:
		var sphere := collision.shape as SphereShape3D
		horizontal_radius = sphere.radius * max(world_scale.x, world_scale.z)
	elif collision.shape is CylinderShape3D:
		var cylinder := collision.shape as CylinderShape3D
		horizontal_radius = cylinder.radius * max(world_scale.x, world_scale.z)
	elif collision.shape is CapsuleShape3D:
		var capsule := collision.shape as CapsuleShape3D
		horizontal_radius = capsule.radius * max(world_scale.x, world_scale.z)

	return max(MINIMUM_DOCKING_DISTANCE, horizontal_radius + 16.0)

func perform_action(target_node: Node3D, delta: float):
	if target_node.is_in_group("asteroid"):
		# Refuse to mine when a special item is loaded OR when the
		# ore hold is full. EMPTY hold is allowed (default state on a
		# fresh game). (Previous condition used `cargo_type != ORE`
		# which incorrectly refused to fire the laser when the hold
		# was empty.)
		if not GlobalState.can_accept_ore() or GlobalState.cargo >= GlobalState.cargo_max:
			mining_laser.visible = false
			return

		mining_laser.visible = true
		
		# Position laser beam cylinder
		var ship_front = global_position + (-global_transform.basis.z * 2.0)
		var asteroid_pos = target_node.global_position
		var mid_point = (ship_front + asteroid_pos) / 2.0
		var laser_len = ship_front.distance_to(asteroid_pos)
		
		mining_laser.global_position = mid_point
		mining_laser.look_at(asteroid_pos, Vector3.UP)
		mining_laser.rotate_object_local(Vector3.RIGHT, PI / 2.0)
		
		# Laser Pulse FX
		var pulse = 0.12 + sin(Time.get_ticks_msec() * 0.025) * 0.04
		mining_laser.scale = Vector3(pulse, laser_len / 2.0, pulse)
		
		if fire_cooldown <= 0.0:
			fire_cooldown = GlobalState.mining_cooldown
			if GlobalState.has_max_bulwark_shield:
				fire_cooldown *= 1.05
				
			AudioManager.play_laser(global_position)
			if target_node.has_method("mine"):
				target_node.mine()
				
			if GlobalState.has_max_rapid_mining:
				mining_cycles += 1
				if mining_cycles >= 10:
					GlobalState.remove_ore(1.0)
					mining_cycles = 0
	
	elif target_node.has_method("take_damage") and target_node.get("faction") != "player":
		mining_laser.visible = false
		if fire_cooldown <= 0.0:
			fire_cooldown = GlobalState.weapon_cooldown
			AudioManager.play_laser(global_position)
			spawn_projectile(target_node)
	else:
		mining_laser.visible = false

func spawn_projectile(target_node: Node3D):
	if GlobalState.has_max_heavy_weapon:
		engine_stall_timer = max(engine_stall_timer, 0.1)
		
	var proj_scene = load("res://scenes/projectile.tscn")
	if proj_scene:
		var p = proj_scene.instantiate()
		p.direction = -global_transform.basis.z
		p.damage = GlobalState.weapon_damage
		p.faction = "player"
		p.color = Color.CYAN
		get_parent().add_child(p)
		p.global_position = global_position + (-global_transform.basis.z * 2.2)

func double_click_move(click_pos: Vector3):
	is_aligning = false
	target_position = click_pos
	nav_mode = "MANUAL"
	is_aligning = true
	var ui = GlobalState.get_ui_manager()
	if ui and ui.has_method("show_target_marker"):
		ui.show_target_marker(click_pos)

func die():
	destroyed = true
	AudioManager.play_explosion(global_position)
	var ui = GlobalState.get_ui_manager()
	if ui and ui.has_method("show_death_screen"):
		ui.show_death_screen()
	queue_free()

func _create_drones():
	randomize()
	
	var orbit_radius = 6.8
	var sphere_radius = 0.12 # Basketball size relative to ship scale
	
	# Create common glowing green material for both drones
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 0.4)
	mat.metallic = 0.9
	mat.roughness = 0.15
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.9, 0.4)
	mat.emission_energy_multiplier = 3.0
	
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = sphere_radius
	sphere_mesh.height = sphere_radius * 2.0
	sphere_mesh.material = mat
	
	# Create Drone 1
	var pivot1 = Node3D.new()
	pivot1.name = "DronePivot1"
	add_child(pivot1)
	
	var mesh1 = MeshInstance3D.new()
	mesh1.name = "DroneMesh1"
	mesh1.mesh = sphere_mesh
	mesh1.position = Vector3(orbit_radius, 0.0, 0.0)
	pivot1.add_child(mesh1)
	
	var light1 = OmniLight3D.new()
	light1.name = "DroneLight1"
	light1.light_color = Color(0.2, 0.9, 0.4)
	light1.light_energy = 3.5
	light1.omni_range = 8.0
	mesh1.add_child(light1)
	
	drones.append(pivot1)
	drone_rotations.append(Vector3(randf_range(0.4, 0.9), randf_range(0.9, 1.6), randf_range(0.1, 0.6)))
	
	# Create Drone 2
	var pivot2 = Node3D.new()
	pivot2.name = "DronePivot2"
	add_child(pivot2)
	pivot2.rotation_degrees = Vector3(50, 0, 50) # Tilted initial plane
	
	var mesh2 = MeshInstance3D.new()
	mesh2.name = "DroneMesh2"
	mesh2.mesh = sphere_mesh
	mesh2.position = Vector3(-orbit_radius, 0.0, 0.0)
	pivot2.add_child(mesh2)
	
	var light2 = OmniLight3D.new()
	light2.name = "DroneLight2"
	light2.light_color = Color(0.2, 0.9, 0.4)
	light2.light_energy = 3.5
	light2.omni_range = 8.0
	mesh2.add_child(light2)
	
	drones.append(pivot2)
	drone_rotations.append(Vector3(randf_range(-0.9, -0.4), randf_range(0.9, 1.6), randf_range(-0.6, -0.1)))

func take_damage(amount: float, attacker_faction: String = ""):
	if is_docked: return
	if health <= 0.0: return
	
	shield_regen_timer = GlobalState.shield_regen_delay
	if GlobalState.has_max_speed_engine:
		shield_regen_timer += 2.0
	
	if current_shield > 0.0:
		if amount <= current_shield:
			current_shield -= amount
			amount = 0.0
		else:
			amount -= current_shield
			current_shield = 0.0
			if GlobalState.has_max_deflector_shield:
				engine_stall_timer = max(engine_stall_timer, 1.0)
			
	if amount > 0.0:
		health -= amount
		
	if health <= 0.0:
		die()

func _update_drone_colors():
	var health_pct = health / max_health
	var target_color = Color(0.2, 0.9, 0.4) # Green
	if health_pct <= 0.3:
		target_color = Color(1.0, 0.2, 0.2) # Red
	elif health_pct <= 0.6:
		target_color = Color(0.9, 0.8, 0.2) # Yellow
		
	# Update both drones
	for pivot in drones:
		if is_instance_valid(pivot) and pivot.get_child_count() > 0:
			var mesh_inst = pivot.get_child(0) as MeshInstance3D
			if is_instance_valid(mesh_inst):
				var mat = mesh_inst.mesh.material as StandardMaterial3D
				if mat:
					mat.albedo_color = target_color
					mat.emission = target_color
				
				if mesh_inst.get_child_count() > 0:
					var light = mesh_inst.get_child(0) as OmniLight3D
					if is_instance_valid(light):
						light.light_color = target_color
