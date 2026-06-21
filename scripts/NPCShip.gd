extends CharacterBody3D

@export var faction: String = "zenith" # zenith, aurelia, vanguard
@export var max_health: float = 50.0
@export var speed: float = 10.0
@export var rotation_speed: float = 2.2
@export var is_reinforcement: bool = false
@export var difficulty_multiplier: float = 1.0
@export var persistent_id: String = ""
@export var custom_model_path: String = ""
var custom_model_scene: Node3D = null
@export_enum("Gunner", "Interceptor", "Logistics", "MiningHauler") var ship_role: String = ""

var health: float = 50.0
var patrol_center: Vector3
var target: Node3D = null
var fire_cooldown: float = 0.0
var destroyed: bool = false
var last_attacker_faction: String = ""
var taunted_player: bool = false
var ceasefire: bool = false

var hardpoints: Array[Node3D] = []
var engine_points: Array[Node3D] = []
var current_hp_index: int = 0
var hull_instance: Node3D = null
var engine_glow: MultiMeshInstance3D = null
var engine_glow_material: StandardMaterial3D = null
var engine_glow_base_transforms: Array[Transform3D] = []
var role_patrol_refresh_timer: float = 0.0

const RuntimeTraceType := preload(
	"res://scripts/diagnostics/RuntimeTrace.gd"
)

# Archetype attributes
var archetype: String = "Balanced"
var fire_cooldown_min: float = 1.3
var fire_cooldown_max: float = 1.5
var damage_min: float = 5.5
var damage_max: float = 6.5

@onready var visual: Node3D = $Visual

# Preloads
var mesh_zenith = preload("res://assets/faction2.glb")
var mesh_aurelia = preload("res://assets/F1HP.glb")
var mesh_vanguard = preload("res://assets/faction2.glb")
var mesh_faction1 = preload("res://assets/faction1.glb")

const MAJOR_FACTION_MODELS := {
	"zenith": {
		"Gunner": "res://Ships/Zenith/Zenith_Gunner.glb",
		"Interceptor": "res://Ships/Zenith/Zenith_Interceptor.glb",
		"Logistics": "res://Ships/Zenith/Zenith_Logistics.glb",
		"MiningHauler": "res://Ships/Zenith/Zenith_MiningHauler.glb",
	},
	"aurelia": {
		"Gunner": "res://Ships/Aurlelia/Aurelia_Gunner.glb",
		"Interceptor": "res://Ships/Aurlelia/Aurelia_interceptor.glb",
		"Logistics": "res://Ships/Aurlelia/Aurelia_Logistics.glb",
		"MiningHauler": "res://Ships/Aurlelia/Aurelia_MiningHauler.glb",
	},
	"vanguard": {
		"Gunner": "res://Ships/Vanguard/Vanguard_Gunner.glb",
		"Interceptor": "res://Ships/Vanguard/Vanguard_interceptor.glb",
		"Logistics": "res://Ships/Vanguard/Vanguard_Logistics.glb",
		"MiningHauler": "res://Ships/Vanguard/Vanguard_HaulerMiner.glb",
	},
}

const MAJOR_HULL_TARGET_SIZES := {
	"Gunner": 24.0,
	"Interceptor": 22.0,
	"Logistics": 28.0,
	"MiningHauler": 30.0,
}

func _generate_archetype():
	if ship_role == "":
		var roles := ["Gunner", "Interceptor", "Logistics", "MiningHauler"]
		ship_role = roles.pick_random()
	_configure_role(ship_role)

func _configure_role(role: String) -> void:
	var visual_scale_mult: float = 1.0

	match role:
		"Logistics":
			archetype = "Logistics"
			max_health = randf_range(45.0, 55.0)
			speed = randf_range(9.0, 11.0)
			rotation_speed = 2.2
			fire_cooldown_min = 1.3
			fire_cooldown_max = 1.5
			damage_min = 5.5
			damage_max = 6.5
			visual_scale_mult = 1.0
		"MiningHauler":
			archetype = "Mining Hauler"
			max_health = randf_range(85.0, 95.0)
			speed = randf_range(6.5, 7.5)
			rotation_speed = 1.6
			fire_cooldown_min = 1.6
			fire_cooldown_max = 2.0
			damage_min = 3.5
			damage_max = 4.5
			visual_scale_mult = 1.3
		"Gunner":
			archetype = "Gunner"
			max_health = randf_range(20.0, 25.0)
			speed = randf_range(9.5, 10.5)
			rotation_speed = 2.4
			fire_cooldown_min = 1.0
			fire_cooldown_max = 1.2
			damage_min = 11.0
			damage_max = 13.0
			visual_scale_mult = 0.9
		_:
			ship_role = "Interceptor"
			archetype = "Interceptor"
			max_health = randf_range(30.0, 40.0)
			speed = randf_range(15.0, 17.0)
			rotation_speed = 3.0
			fire_cooldown_min = 0.7
			fire_cooldown_max = 0.9
			damage_min = 3.0
			damage_max = 4.0
			visual_scale_mult = 0.8
		
	# Apply Elite Reinforcement Multiplier if applicable
	if is_reinforcement:
		max_health = max_health * 2.0
		damage_min = damage_min * 1.5
		damage_max = damage_max * 1.5
		visual_scale_mult = visual_scale_mult * 1.5
		archetype = "Elite " + archetype

	if difficulty_multiplier > 1.0:
		max_health *= difficulty_multiplier
		damage_min *= difficulty_multiplier
		damage_max *= difficulty_multiplier

	# Apply Quest Combat Multiplier if target of active combat quest
	for _m in QuestManager.get_mission_collection().get_all_active():
		if _m.data.get("objective_type", "") == "KILL_SHIPS" and _m.data.get("target_faction", "") == faction:
			var q_mult = float(_m.data.get("combat_multiplier", 1.0))
			if q_mult > 1.0:
				max_health *= q_mult
				damage_min *= q_mult
				damage_max *= q_mult
				visual_scale_mult *= (1.0 + (q_mult - 1.0) * 0.4)
				archetype = "Target " + archetype
			break
			
	health = max_health
	
	# Apply visual/collision scaling
	scale = Vector3(visual_scale_mult, visual_scale_mult, visual_scale_mult)
	
	# Override name to display archetype in UI
	name = faction.to_upper() + " " + archetype + " " + str(randi() % 1000)

func _ready():
	_generate_archetype()
	patrol_center = global_position
	if persistent_id != "":
		add_to_group(WorldIdentity.IDENTITY_GROUP)
	
	# Add to entities list
	GlobalState.active_system_entities.append(self)
	GlobalState.entities_changed.emit()
	
	# Load hull based on faction
	_setup_hull()
	call_deferred("_refresh_role_patrol_center")

func _setup_hull():
	var hull_scene: PackedScene = null

	if custom_model_scene != null:
		hull_instance = custom_model_scene
		visual.add_child(hull_instance)
		hull_instance.rotation.y = PI
		_fit_major_hull(hull_instance)
		hull_instance.scale *= 1.5
		_setup_model_points(hull_instance)
		return

	if custom_model_path != "" and ResourceLoader.exists(custom_model_path):
		hull_scene = load(custom_model_path) as PackedScene
		if hull_scene:
			hull_instance = hull_scene.instantiate()
			visual.add_child(hull_instance)
			hull_instance.rotation.y = PI
			_fit_major_hull(hull_instance)
			hull_instance.scale *= 1.5
			_setup_model_points(hull_instance)
			return

	# Check if this is a minor faction (data-driven lookup)
	if GlobalState.is_minor_faction(faction):
		var fdata = GlobalState.minor_faction_data(faction)
		var minor_model_path := GameContentRegistry.shared().ship_path(faction, ship_role)
		if minor_model_path != "" and ResourceLoader.exists(minor_model_path):
			hull_scene = load(minor_model_path) as PackedScene
			if hull_scene:
				hull_instance = hull_scene.instantiate()
				visual.add_child(hull_instance)
				hull_instance.rotation.y = PI
				_fit_major_hull(hull_instance)
				_apply_tint(hull_instance, fdata["tint"])
				_setup_model_points(hull_instance)
				return
		match fdata["model"]:
			"faction1": hull_scene = mesh_faction1
			"faction2": hull_scene = mesh_zenith  # faction2.glb
			"aurelia":  hull_scene = mesh_aurelia
			_: hull_scene = mesh_faction1
		if hull_scene:
			hull_instance = hull_scene.instantiate()
			visual.add_child(hull_instance)
			hull_instance.scale = Vector3(6.0, 6.0, 6.0)
			hull_instance.rotation.y = PI
			_apply_tint(hull_instance, fdata["tint"])
			# Setup hardpoints if using the Aurelia model
			if fdata["model"] == "aurelia":
				_setup_amarr_hardpoints(hull_instance)
		return
	
	# Major factions use role-specific local models. Dynamic loading keeps the
	# project runnable when the ignored art folders are absent on another machine.
	var model_path := GameContentRegistry.shared().ship_path(faction, ship_role)
	if model_path.is_empty():
		model_path = str(MAJOR_FACTION_MODELS.get(faction, {}).get(ship_role, ""))
	if model_path != "" and ResourceLoader.exists(model_path):
		hull_scene = load(model_path) as PackedScene
	else:
		hull_scene = _get_legacy_major_hull()
		push_warning("[NPCShip] Missing %s %s model at '%s'; using legacy hull." % [
			faction, ship_role, model_path
		])

	if hull_scene:
		hull_instance = hull_scene.instantiate()
		visual.add_child(hull_instance)
		hull_instance.rotation.y = PI
		if model_path != "" and ResourceLoader.exists(model_path):
			_fit_major_hull(hull_instance)
			_setup_model_points(hull_instance)
		else:
			hull_instance.scale = Vector3(6.0, 6.0, 6.0)
	else:
		# No matching model found — usually because the LLM hallucinated a
		# faction name that isn't in MINOR_FACTIONS or the major list. Fall
		# back to a random existing model so the ship is at least visible
		# and the player can still engage it. Surface the miss in the console
		# so it's easy to spot in logs.
		var fallbacks: Array = [mesh_faction1, mesh_zenith, mesh_aurelia]
		hull_scene = fallbacks[randi() % fallbacks.size()]
		push_warning("[NPCShip] Unknown faction '%s' — falling back to random model for visibility." % faction)
		hull_instance = hull_scene.instantiate()
		visual.add_child(hull_instance)
		hull_instance.scale = Vector3(6.0, 6.0, 6.0)
		hull_instance.rotation.y = PI

func apply_generated_model(model: Node3D) -> void:
	if destroyed or model == null:
		return
	if hull_instance and is_instance_valid(hull_instance):
		hull_instance.queue_free()
	if engine_glow and is_instance_valid(engine_glow):
		engine_glow.queue_free()
		engine_glow = null
	engine_glow_material = null
	engine_glow_base_transforms.clear()
	hardpoints.clear()
	engine_points.clear()
	hull_instance = model
	visual.add_child(hull_instance)
	hull_instance.rotation.y = PI
	_fit_major_hull(hull_instance)
	hull_instance.scale *= 1.5
	_setup_model_points(hull_instance)


func _get_legacy_major_hull() -> PackedScene:
	match faction:
		"zenith":
			return mesh_zenith
		"aurelia":
			return mesh_aurelia
		"vanguard":
			return mesh_vanguard
	return mesh_faction1

func _fit_major_hull(model_root: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	_find_hull_meshes(model_root, meshes)
	if meshes.is_empty():
		model_root.scale = Vector3.ONE
		return

	var combined := AABB()
	var first := true
	for mesh in meshes:
		var relative := model_root.global_transform.affine_inverse() * mesh.global_transform
		var mesh_aabb := relative * mesh.get_aabb()
		if first:
			combined = mesh_aabb
			first = false
		else:
			combined = combined.merge(mesh_aabb)

	var largest_dimension: float = maxf(combined.size.x, maxf(combined.size.y, combined.size.z))
	if largest_dimension <= 0.001:
		return
	var target_size := _get_major_hull_target_size()
	var fit_scale: float = target_size / largest_dimension
	model_root.scale = Vector3.ONE * fit_scale
	var rotated_center: Vector3 = model_root.transform.basis * combined.get_center()
	model_root.position = -rotated_center * fit_scale
	_fit_major_hull_collision(target_size)

func _get_major_hull_target_size() -> float:
	return float(MAJOR_HULL_TARGET_SIZES.get(ship_role, 24.0))

func _fit_major_hull_collision(target_size: float) -> void:
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or not collision_shape.shape is BoxShape3D:
		return
	var box := collision_shape.shape.duplicate() as BoxShape3D
	box.size = Vector3(target_size * 0.52, target_size * 0.38, target_size * 0.92)
	collision_shape.shape = box

func _find_hull_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		_find_hull_meshes(child, meshes)

func _setup_model_points(node: Node) -> void:
	var lower_name := str(node.name).to_lower()
	if node is Node3D:
		if lower_name.begins_with("weapon_") or "hardpoint" in lower_name or "muzzle" in lower_name:
			hardpoints.append(node as Node3D)
		elif lower_name.begins_with("engine_") or "thruster" in lower_name or "exhaust" in lower_name:
			engine_points.append(node as Node3D)
	for child in node.get_children():
		_setup_model_points(child)
	if node == hull_instance:
		_ensure_model_points()
		_create_engine_glow()

func _ensure_model_points() -> void:
	var hull_size := _get_major_hull_target_size()
	if hardpoints.is_empty():
		hardpoints.append(_create_fallback_marker("FallbackWeaponLeft", Vector3(-hull_size * 0.18, 0.0, -hull_size * 0.42)))
		hardpoints.append(_create_fallback_marker("FallbackWeaponRight", Vector3(hull_size * 0.18, 0.0, -hull_size * 0.42)))
	if engine_points.is_empty():
		engine_points.append(_create_fallback_marker("FallbackEngine", Vector3(0.0, 0.0, hull_size * 0.48)))

func _create_fallback_marker(marker_name: String, marker_position: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.position = marker_position
	visual.add_child(marker)
	return marker

func _create_engine_glow() -> void:
	if engine_points.is_empty():
		return

	engine_glow = MultiMeshInstance3D.new()
	engine_glow.name = "EngineGlow"
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 0.42
	glow_mesh.height = 0.84
	glow_mesh.radial_segments = 8
	glow_mesh.rings = 4
	var glow_material := StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.albedo_color = Color(0.15, 0.75, 1.0, 0.82)
	glow_material.emission_enabled = true
	glow_material.emission = _get_engine_color()
	glow_material.emission_energy_multiplier = 4.0
	glow_mesh.material = glow_material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = glow_mesh
	multimesh.instance_count = engine_points.size()
	for index in range(engine_points.size()):
		var engine_point := engine_points[index]
		var relative_transform := visual.global_transform.affine_inverse() * engine_point.global_transform
		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, relative_transform.origin))
	engine_glow.multimesh = multimesh
	visual.add_child(engine_glow)
	engine_glow_material = glow_material
	engine_glow_base_transforms.clear()
	for index in range(engine_points.size()):
		engine_glow_base_transforms.append(multimesh.get_instance_transform(index))

func _get_engine_color() -> Color:
	match faction:
		"zenith":
			return Color(0.2, 0.65, 1.0)
		"aurelia":
			return Color(0.35, 0.85, 1.0)
		"vanguard":
			return Color(1.0, 0.25, 0.08)
	return Color(0.45, 0.75, 1.0)

func _update_engine_glow() -> void:
	if engine_glow == null or not is_instance_valid(engine_glow):
		return
	if engine_glow_material == null:
		return
	var speed_ratio := clampf(velocity.length() / maxf(speed, 1.0), 0.0, 1.0)
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.012) * 0.15
	var alpha := lerpf(0.3, 0.9, speed_ratio) * pulse
	var emission_mult := lerpf(2.0, 6.0, speed_ratio) * pulse
	engine_glow_material.albedo_color.a = alpha
	engine_glow_material.emission_energy_multiplier = emission_mult
	var mm := engine_glow.multimesh
	if mm == null:
		return
	var s := lerpf(0.6, 1.4, speed_ratio) * pulse
	for i in range(mini(engine_glow_base_transforms.size(), mm.instance_count)):
		var base := engine_glow_base_transforms[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)), base.origin))

func _refresh_role_patrol_center() -> void:
	var desired_group := ""
	if ship_role == "Logistics":
		desired_group = "station"
	elif ship_role == "MiningHauler":
		desired_group = "asteroid"
	else:
		return

	var system_root := GlobalState.get_system_root()
	var scene_tree := get_tree()
	if not system_root or not scene_tree:
		return

	var closest: Node3D = null
	var closest_distance := INF
	for candidate in scene_tree.get_nodes_in_group(desired_group):
		if candidate is Node3D and is_instance_valid(candidate) and system_root.is_ancestor_of(candidate):
			var candidate_distance := global_position.distance_squared_to(candidate.global_position)
			if candidate_distance < closest_distance:
				closest = candidate
				closest_distance = candidate_distance
	if closest:
		patrol_center = closest.global_position

func _apply_tint(node: Node, tint_color: Color):
	if node is MeshInstance3D:
		var mat = node.get_active_material(0)
		if mat:
			var new_mat = mat.duplicate()
			new_mat.albedo_color = tint_color
			node.set_surface_override_material(0, new_mat)
	for child in node.get_children():
		_apply_tint(child, tint_color)

func _setup_amarr_hardpoints(node: Node):
	var gun_names = ["TopRightGun", "BottomRightGun.001", "TopLeftGun", "BottomLeftGun.001"]
	if gun_names.has(node.name) and node is Node3D:
		hardpoints.append(node)
		# Hide the placeholder cube
		node.visible = false
	for child in node.get_children():
		_setup_amarr_hardpoints(child)

func _physics_process(delta: float):
	if GlobalState.paused or destroyed:
		return
	_update_engine_glow()

	role_patrol_refresh_timer -= delta
	if role_patrol_refresh_timer <= 0.0:
		role_patrol_refresh_timer = 8.0
		_refresh_role_patrol_center()
		
	if fire_cooldown > 0.0:
		fire_cooldown -= delta
		
	# Check target distance leash
	if target and is_instance_valid(target):
		var dist = global_position.distance_to(target.global_position)
		if dist > 150.0:
			target = null
		
	# Scanning and targeting
	if ceasefire:
		target = null
	elif target == null or not is_instance_valid(target) or target.get("destroyed") or (target == GlobalState.player and GlobalState.player.get("is_docked")):
		target = null

		# Elite reinforcements target the player immediately
		if is_reinforcement:
			var p = GlobalState.player
			if p and is_instance_valid(p) and not p.get("destroyed") and not p.get("is_docked"):
				target = p
				
		var is_combat_role: bool = ship_role in ["Gunner", "Interceptor"] \
			or GlobalState.is_minor_faction(faction) \
			or is_reinforcement \
			or bool(get_meta("is_quest_target", false))
		if target == null and is_combat_role:
			# Find closest enemy within range (could be player or other NPC)
			var min_dist = 130.0
			var best_target: Node3D = null
			
			# 1. Check if player is an enemy and in range
			var p = GlobalState.player
			if p and is_instance_valid(p) and not p.get("destroyed") and not p.get("is_docked"):
				var is_player_enemy = false
				
				# Minor factions are always hostile to the player
				if GlobalState.is_minor_faction(faction):
					is_player_enemy = true
				elif GlobalState.reputations.has(faction) and GlobalState.reputations[faction] < -10.0:
					is_player_enemy = true
				
				# Station safe zone: major factions stand down near station if rep isn't terrible
				if is_player_enemy and not GlobalState.is_minor_faction(faction):
					if GlobalState.is_in_safe_zone(global_position):
						if GlobalState.reputations.get(faction, -100.0) > GlobalState.SAFE_ZONE_REP_THRESHOLD:
							is_player_enemy = false  # Stand down near station
				
				if is_player_enemy:
					var dist_to_player = global_position.distance_to(p.global_position)
					if dist_to_player < min_dist:
						min_dist = dist_to_player
						best_target = p
						
			# 2. Check other active system entities (NPC ships)
			for entity in GlobalState.active_system_entities:
				if entity and is_instance_valid(entity) and entity != self and not entity.get("destroyed"):
					if entity.get("faction") != faction:
						var dist = global_position.distance_to(entity.global_position)
						if dist < min_dist:
							min_dist = dist
							best_target = entity
							
			if best_target:
				target = best_target
							
	if target != null and not is_instance_valid(target):
		target = null

	# Movement & Combat Logic
	if target:
		steer_towards(target.global_position, delta)
		var dist = global_position.distance_to(target.global_position)
		
		# Move towards target if we are beyond our stopping cushion
		if dist > 30.0:
			velocity = -global_transform.basis.z * speed
			move_and_slide()
		else:
			velocity = Vector3.ZERO
			
		# Fire at the target if within weapon range (60.0m) and aligned (within 30 degrees)
		if dist <= 60.0:
			var to_target = (target.global_position - global_position).normalized()
			var forward = -global_transform.basis.z.normalized()
			var angle = forward.angle_to(to_target)
			if angle < deg_to_rad(30.0):
				if fire_cooldown <= 0.0:
					fire()
	else:
		# Patrol center behavior
		var dist_to_center = global_position.distance_to(patrol_center)
		if dist_to_center > 70.0:
			steer_towards(patrol_center, delta)
		else:
			# Orbit around patrol center
			rotation.y += 0.2 * delta
		
		# Move forward at full speed if far from patrol center, otherwise slowly
		var speed_factor = 1.0 if dist_to_center > 150.0 else 0.5
		velocity = -global_transform.basis.z * (speed * speed_factor)
		move_and_slide()

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

func fire():
	fire_cooldown = randf_range(fire_cooldown_min, fire_cooldown_max)
	AudioManager.play_laser(global_position)
	
	# If targeting the player, trigger hostile taunt
	if target == GlobalState.player:
		if not taunted_player:
			taunted_player = true
			var taunt = LLMInterface.get_chatter_line("hostile_taunt", {
				"attacker_faction": faction
			})
			var fac_color = _get_faction_color()
			GlobalState.emit_chatter(name, taunt, fac_color)
	
	# Determine laser start position
	var spawn_pos = global_position + (-global_transform.basis.z * 1.8)
	if hardpoints.size() > 0:
		var hp = hardpoints[current_hp_index]
		if is_instance_valid(hp):
			spawn_pos = hp.global_position
		current_hp_index = (current_hp_index + 1) % hardpoints.size()
		
	# Spawn projectile
	var proj_scene = load("res://scenes/projectile.tscn")
	if proj_scene:
		var p = proj_scene.instantiate()
		p.direction = -global_transform.basis.z
		p.damage = randf_range(damage_min, damage_max)
		p.faction = faction
		
		# Projectile color
		if GlobalState.is_minor_faction(faction):
			p.color = GlobalState.minor_faction_data(faction).get(
				"projectile",
				Color.RED
			)
		elif faction == "zenith":
			p.color = Color.BLUE
		elif faction == "aurelia":
			p.color = Color.GOLD
		else:
			p.color = Color.RED
			
		get_parent().add_child(p)
		p.global_position = spawn_pos

func take_damage(amount: float, attacker_faction: String = ""):
	if destroyed: return
	RuntimeTraceType.event("combat", "npc_damage", {
		"ship": name,
		"faction": faction,
		"health_before": health,
		"damage": amount,
		"attacker_faction": attacker_faction,
	})
	health -= amount
	if attacker_faction == "player" and not GlobalState.is_minor_faction(faction):
		GlobalState.adjust_reputation(faction, -2.0) # Aggro drop rep on hit
		last_attacker_faction = "player"
		
		# Immediately target the player to defend itself!
		var p = GlobalState.player
		if p and is_instance_valid(p) and not p.get("destroyed"):
			target = p
	elif attacker_faction != "":
		last_attacker_faction = attacker_faction
		
	if health <= 0.0:
		die()

func die():
	if destroyed:
		return
	destroyed = true
	RuntimeTraceType.event("combat", "npc_death_started", {
		"ship": name,
		"faction": faction,
		"last_attacker_faction": last_attacker_faction,
		"system_id": GlobalState.current_system_id,
		"position": [
			global_position.x,
			global_position.y,
			global_position.z,
		],
	})
	if get_meta("is_quest_target", false):
		_record_persistent_state()
	AudioManager.play_explosion(global_position)

	if engine_glow and is_instance_valid(engine_glow):
		engine_glow.get_parent().remove_child(engine_glow)
		engine_glow.queue_free()
		engine_glow = null

	# Spawn wreckage
	var wreck_script = load("res://scripts/Wreckage.gd")
	if wreck_script:
		var wreck = StaticBody3D.new()
		wreck.set_script(wreck_script)
		wreck.name = name + "_Wreck"
		get_parent().add_child(wreck)
		wreck.global_position = global_position
		wreck.global_rotation = global_rotation
		wreck.add_to_group("wreckage")
		wreck.call("initialize", visual)
		wreck.last_attacker_faction = last_attacker_faction  # Salvager uses this to know if player killed it
		
	GlobalState.destroyed_ships_pool += 1
	
	# Award credits and apply reputation changes if killed by player
	if last_attacker_faction == "player":
		GlobalState.player_credits += 15
		_apply_reputation_changes()

		# Trigger death cry chatter
		var cry = LLMInterface.get_chatter_line("death_cry", {
			"attacker_faction": faction
		})
		var fac_color = _get_faction_color()
		GlobalState.emit_chatter(name, cry, fac_color)

		GlobalState.record_kill(faction)

	# Always emit ship_destroyed so quest progress counts NPC kills too.
	# Previously this only fired inside the player-killed branch (via
	# record_kill), so an NPC killing a quest target left the quest count
	# stuck and the contract unfinishable.
	GlobalState.ship_destroyed.emit(faction)
	
	# Remove from entities list
	GlobalState.active_system_entities.erase(self)
	GlobalState.entities_changed.emit()
	RuntimeTraceType.event("combat", "npc_death_completed", {
		"ship": name,
		"faction": faction,
		"faction_kills": int(GlobalState.faction_kills.get(faction, 0)),
	})
	
	ImpactEffect.spawn_explosion(get_parent(), global_position, _get_engine_color())
	queue_free()

func get_persistent_id() -> String:
	return get_world_id()

func get_world_id() -> String:
	return persistent_id

func get_world_type_id() -> String:
	return "entity_type.ship"

func get_state_schema_version() -> int:
	return 1

func capture_state() -> Dictionary:
	return {
		"type": "mission_ship",
		"destroyed": destroyed,
		"health": health,
		"faction": faction,
		"ship_role": ship_role,
		"position": [global_position.x, global_position.y, global_position.z],
		"rotation": [global_rotation.x, global_rotation.y, global_rotation.z],
	}

func restore_state(state: Dictionary) -> void:
	if bool(state.get("destroyed", false)):
		queue_free()
		return
	var saved_role := str(state.get("ship_role", ship_role))
	if saved_role != "" and saved_role != ship_role:
		ship_role = saved_role
		_configure_role(ship_role)
		for child in visual.get_children():
			child.queue_free()
		hardpoints.clear()
		engine_points.clear()
		engine_glow = null
		_setup_hull()
	health = clampf(float(state.get("health", max_health)), 0.0, max_health)
	var saved_position: Array = state.get("position", [])
	if saved_position.size() == 3:
		global_position = Vector3(float(saved_position[0]), float(saved_position[1]), float(saved_position[2]))
	var saved_rotation: Array = state.get("rotation", [])
	if saved_rotation.size() == 3:
		global_rotation = Vector3(float(saved_rotation[0]), float(saved_rotation[1]), float(saved_rotation[2]))

func _record_persistent_state() -> void:
	var game_root := get_tree().current_scene
	if game_root and game_root.has_method("record_persistent_entity_state"):
		game_root.record_persistent_entity_state(self)

func _apply_reputation_changes():
	# Minor factions don't affect reputation when killed
	if GlobalState.is_minor_faction(faction):
		return
	
	# Decrease reputation with the killed faction
	GlobalState.adjust_reputation(faction, -20.0)
	
	# Increase reputation with enemies
	match faction:
		"zenith":
			GlobalState.adjust_reputation("vanguard", 10.0)
		"aurelia":
			GlobalState.adjust_reputation("vanguard", 10.0)
		"vanguard":
			GlobalState.adjust_reputation("zenith", 10.0)
			GlobalState.adjust_reputation("aurelia", 10.0)

func _get_faction_color() -> Color:
	if GlobalState.is_minor_faction(faction):
		return GlobalState.minor_faction_data(faction).get("color", Color.WHITE)
	match faction:
		"zenith": return Color(1.0, 0.6, 0.1)
		"aurelia": return Color(0.85, 0.2, 0.2)
		"vanguard": return Color(0.2, 0.7, 1.0)
	return Color(1.0, 1.0, 1.0)
