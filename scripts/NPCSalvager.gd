extends CharacterBody3D

@export var speed: float = 12.0
@export var rotation_speed: float = 2.0
@export var max_health: float = 100.0
var health: float = 100.0
var faction: String = "player" # Friendly/Neutral to player

var state: String = "IDLE" # IDLE, APPROACHING, SALVAGING, RETURNING
var target_wreck: Node3D = null
var salvage_time: float = 0.0
const SALVAGE_DURATION: float = 60.0 # 1 minute

var model: Node3D
var laser_beam: MeshInstance3D
var station: Node3D = null

func _ready():
	health = max_health
	
	# Load ship model
	var ship_scene = load("res://assets/INDYMiner.glb")
	if ship_scene:
		model = ship_scene.instantiate()
		add_child(model)
		model.scale = Vector3(6.0, 6.0, 6.0)
		model.rotation.y = PI
		
	# Setup laser beam
	laser_beam = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.15
	cyl.bottom_radius = 0.15
	cyl.height = 1.0
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.0) # Bright orange
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.0)
	mat.emission_energy_multiplier = 4.0
	cyl.material = mat
	
	laser_beam.mesh = cyl
	add_child(laser_beam)
	laser_beam.visible = false
	
	# Find space station in the scene
	station = GlobalState.get_primary_station()

func _physics_process(delta: float):
	if GlobalState.paused: return
	
	# Scan for station if not found yet
	if not station:
		station = GlobalState.get_primary_station()
			
	match state:
		"IDLE":
			laser_beam.visible = false
			# Stay near station
			if station and is_instance_valid(station):
				var dist = global_position.distance_to(station.global_position)
				if dist > 80.0:
					steer_towards(station.global_position, delta)
					velocity = -global_transform.basis.z * (speed * 0.5)
					move_and_slide()
				else:
					velocity = Vector3.ZERO
					# Slow orbit around station
					rotation.y += 0.05 * delta
					
			# Scan for untargeted wreckages
			var wrecks = get_tree().get_nodes_in_group("wreckage")
			for wreck in wrecks:
				if is_instance_valid(wreck) and not wreck.get("being_salvaged"):
					target_wreck = wreck
					target_wreck.set("being_salvaged", true)
					state = "APPROACHING"
					
					# Trigger industrial banter — pass wreck name and kill attribution for contextual LLM lines
					var killed_by_player = target_wreck.get("last_attacker_faction") == "player"
					var banter = LLMInterface.get_chatter_line("industrial_banter", {
						"wreck_name": target_wreck.name,
						"killed_by_player": killed_by_player
					})
					GlobalState.emit_chatter(name, banter, Color(0.9, 0.7, 0.1))
					break
					
		"APPROACHING":
			laser_beam.visible = false
			if not is_instance_valid(target_wreck):
				target_wreck = null
				state = "RETURNING"
				return
				
			var dist = global_position.distance_to(target_wreck.global_position)
			steer_towards(target_wreck.global_position, delta)
			
			if dist > 40.0:
				velocity = -global_transform.basis.z * speed
				move_and_slide()
			else:
				velocity = Vector3.ZERO
				state = "SALVAGING"
				salvage_time = 0.0
				
		"SALVAGING":
			if not is_instance_valid(target_wreck):
				target_wreck = null
				state = "RETURNING"
				return
				
			steer_towards(target_wreck.global_position, delta)
			salvage_time += delta
			
			# Draw laser beam
			laser_beam.visible = true
			var ship_front = global_position + (-global_transform.basis.z * 2.0)
			var wreck_pos = target_wreck.global_position
			var mid_point = (ship_front + wreck_pos) / 2.0
			var laser_len = ship_front.distance_to(wreck_pos)
			
			laser_beam.global_position = mid_point
			laser_beam.look_at(wreck_pos, Vector3.UP)
			laser_beam.rotate_object_local(Vector3.RIGHT, PI / 2.0)
			
			# Pulse laser beam
			var pulse = 0.15 + sin(Time.get_ticks_msec() * 0.03) * 0.05
			laser_beam.scale = Vector3(pulse, laser_len / 2.0, pulse)
			
			# Shrink wreckage to simulate salvaging process
			var progress = clamp(salvage_time / SALVAGE_DURATION, 0.0, 1.0)
			if is_instance_valid(target_wreck):
				var s_factor = max(1.0 - progress, 0.01)
				target_wreck.scale = Vector3(s_factor, s_factor, s_factor)
			
			if salvage_time >= SALVAGE_DURATION:
				# Complete salvage
				laser_beam.visible = false
				if is_instance_valid(target_wreck):
					target_wreck.queue_free()
				target_wreck = null
				state = "RETURNING"
				
		"RETURNING":
			laser_beam.visible = false
			if station and is_instance_valid(station):
				var dist = global_position.distance_to(station.global_position)
				steer_towards(station.global_position, delta)
				if dist > 60.0:
					velocity = -global_transform.basis.z * speed
					move_and_slide()
				else:
					velocity = Vector3.ZERO
					state = "IDLE"
			else:
				state = "IDLE"

func steer_towards(target_pos: Vector3, delta: float):
	var to_target = target_pos - global_position
	if to_target.length() > 1.0:
		var target_dir = to_target.normalized()
		if abs(target_dir.dot(Vector3.UP)) < 0.99:
			var target_basis = Basis.looking_at(target_dir, Vector3.UP)
			var target_rot = target_basis.get_euler()
			
			var diff_y = fposmod(target_rot.y - rotation.y + PI, TAU) - PI
			var diff_x = fposmod(target_rot.x - rotation.x + PI, TAU) - PI
			
			rotation.y += diff_y * delta * rotation_speed
			rotation.x += diff_x * delta * rotation_speed

func take_damage(amount: float, attacker_faction: String = ""):
	if health <= 0.0: return
	health -= amount
	if health <= 0.0:
		die()

func die():
	AudioManager.play_explosion(global_position)
	var system_root = GlobalState.get_system_root()
	if system_root and system_root.has_method("_on_salvager_destroyed"):
		system_root.call("_on_salvager_destroyed")
	queue_free()
