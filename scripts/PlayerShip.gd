extends CharacterBody3D

const NavigationRoutePlannerType := preload(
	"res://scripts/navigation/NavigationRoutePlanner.gd"
)
const ThrusterBankType := preload("res://scripts/visuals/ThrusterBank.gd")
const WORLD_PICK_DISTANCE := 100000.0

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
const BOOST_SPEED_MULTIPLIER := 1.25
const BOOST_DURATION_SECONDS := 5.0
const BOOST_COOLDOWN_SECONDS := 60.0
const BOOST_HEAT_DAMAGE := 2.0
const MINING_RANGE := 75.0
const MINING_TRACTOR_LOCK_SECONDS := 1.15
const MINING_TRACTOR_RADIUS := 0.075
const MINING_CUTTER_RADIUS := 0.07
const AUTOPILOT_BELT_CLEARANCE_Y := 180.0
var boost_timer: float = 0.0
var boost_cooldown_timer: float = 0.0
var boost_effect_meshes: Array[MeshInstance3D] = []
var boost_effect_lights: Array[OmniLight3D] = []
var boost_effect_material: StandardMaterial3D
var exhaust_flames: Array[MeshInstance3D] = []
var thruster_bank: Node = null
var _generated_thruster_sockets: Array[Node3D] = []

# Drawback tracking variables
var engine_stall_timer: float = 0.0
var mining_cycles: int = 0
var _mine_particles: GPUParticles3D = null

var _drone_active_idx: int = 0
var _drone_collect_t: Array[float] = [0.0, 0.0]
var _drone_collect_from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _drone_collecting: Array[bool] = [false, false]
var _drone_returning: Array[bool] = [false, false]
var _mining_target_pos: Vector3 = Vector3.ZERO
var _was_mining: bool = false
var _mining_tractor_laser: MeshInstance3D = null
var _mining_tractor_target_id: int = 0
var _mining_tractor_lock_timer: float = 0.0
var mining_continuous_timer: float = 0.0

# Salvage drone state
var _salvage_active: bool = false
var _salvage_target: Node3D = null
var _salvage_ore_remaining: float = 0.0
var _salvage_rare_dropped: bool = false
var _salvage_drone_idx: int = 0
var _salvage_collect_t: float = 0.0
var _salvage_collect_from: Vector3 = Vector3.ZERO
var _salvage_going_out: bool = false
const SALVAGE_ORE_PER_RETURN := 2.0
const SALVAGE_RARE_CHANCE_PER_RETURN := 0.008

# Navigation variables
var target_position: Variant = null # null or Vector3
var navigation_target: Node3D = null
var planned_route: Array[Vector3] = []
var planned_route_index: int = 0
var planned_destination: Vector3 = Vector3.ZERO
var route_plan_count: int = 0
var route_notice_sent: bool = false
var route_notice_override: String = ""
var route_progress_distance: float = INF
var route_stall_timer: float = 0.0
var route_stall_replans: int = 0
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
			if val in ["MOVE_TO_POINT", "APPROACH", "APPROACH_1K", "JUMP_APPROACH", "ORBIT", "MINE", "ATTACK", "DOCK"]:
				if val != "MOVE_TO_POINT" \
						and GlobalState.active_target != null \
						and is_instance_valid(GlobalState.active_target):
					navigation_target = GlobalState.active_target
					_clear_planned_route()
				is_aligning = false
				is_aligning = true

var fire_cooldown: float = 0.0

# Camera controls
var camera_aligned: bool = true
var last_nav_mode: String = "MANUAL"

# ── Combat cinematic camera ─────────────────────────────────────────────────────
# Modes: 0 = off (normal follow), 1 = orbit (planning), 2 = action (punch-in).
var _cam_mode:        int     = 0
var _orbit_angle:     float   = 0.0
var _orbit_radius:    float   = 40.0
var _orbit_midpoint:  Vector3 = Vector3.ZERO
var _cam_goal_pos:    Vector3 = Vector3.ZERO   # action-mode pivot goal
var _cam_look_at:     Vector3 = Vector3.ZERO   # point the pivot looks at
var _cam_look_cur:    Vector3 = Vector3.ZERO   # smoothed look target (lerps toward _cam_look_at)
var _cam_lerp_speed:  float   = 3.0
var _cam_entry_t:     float   = 1.0            # 0→1 ramp over _CAM_ENTRY_DUR at combat start
const _ORBIT_SPEED    := 0.10   # rad/s, wall-clock
const _ORBIT_HEIGHT   := 14.0   # units above midpoint
const _ACTION_LERP    := 8.5    # snappier glide for punch-in framing (was 6.5)
const _ORBIT_LERP     := 3.0
const _CAM_ENTRY_DUR  := 0.7    # seconds to ease from normal follow into orbit
const _CAM_LOOK_LERP  := 2.5    # look-target lerp speed (separate from position)
# The execute-phase framing was tuned for the original ~8-unit hero hull. The
# kitbash upgrade is ~2x larger, so all punch-in offsets scale off this so the
# bigger ship is framed at the same proportion (and the camera never sits inside
# the hull). Stays parametric for future ship swaps.
const _CAM_REF_SHIP_EXTENT := 8.0
# Camera shake (decaying thud, applied via camera h/v offset)
var _shake_strength: float = 0.0
var _shake_decay:    float = 0.0
# FOV punch (quick zoom kick that springs back — adds snap to action beats)
var _base_fov:   float = 75.0
var _fov_punch:  float = 0.0   # additive offset on base fov; negative = zoom-in
# Repeated-action framing variety: when the same attack telegraphs twice in a
# row, flip the over-the-shoulder side so the second shot reads from a new angle.
var _last_telegraph_action: int  = -1
var _frame_flip:            bool = false
var dock_stuck_timer: float = 0.0
var last_dock_distance: float = INF
var last_dock_target: Node3D = null
var staged_jump_gate_id: int = 0
var avoidance_obstacle_id: int = 0
var avoidance_side: Vector3 = Vector3.ZERO
var avoidance_waypoint: Vector3 = Vector3.ZERO
var avoidance_orbit_sign: float = 0.0
var avoidance_exit_index: int = -1
var avoidance_exits_visited: int = 0
var avoidance_full_lap_reassessments: int = 0
var navigation_notice_obstacle_id: int = 0
var last_navigation_status_message: String = ""
var navigation_obstruction_notice_count: int = 0
var navigation_route_clear_notice_count: int = 0
var rmb_down_time: float = 0.0
var rmb_press_position: Vector2 = Vector2.ZERO
var rmb_dragging: bool = false
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
	_configure_mining_laser_material()
	_mining_tractor_laser = _create_mining_tractor_laser()
	_mining_tractor_laser.visible = false
	_mine_particles = _create_mine_particles()
	current_shield = GlobalState.shield_capacity
	
	# Decouple camera pivot transform from player's parent transform
	camera_pivot.top_level = true
	camera_pivot.global_position = global_position
	camera_pivot.rotation_degrees = Vector3(-15, 0, 0) # Pitch down, looking at player
	_base_fov = camera.fov   # rest FOV; combat punch-ins kick off this baseline
	
	GlobalState.target_changed.connect(_on_target_changed)
	CombatManager.combat_started.connect(_on_combat_started_orbit)
	CombatManager.combat_ended.connect(_on_combat_ended_orbit)
	CombatManager.planning_started.connect(_on_planning_started_orbit)
	CombatManager.action_telegraphed.connect(_on_action_telegraphed_cam)
	CombatManager.action_impact.connect(_on_action_impact_cam)
	CombatManager.combat_kill.connect(_on_combat_kill_cam)

	_build_player_ship_model()
	_create_drones()
	_create_boost_effects()
	_create_nose_raycast()


func _create_mining_tractor_laser() -> MeshInstance3D:
	var beam := MeshInstance3D.new()
	beam.name = "MiningTractorBeam"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 10
	mesh.rings = 1
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.02, 0.08, 0.42, 0.48)
	mat.emission_enabled = true
	mat.emission = Color(0.02, 0.08, 0.55)
	mat.emission_energy_multiplier = 2.4
	mesh.material = mat
	beam.mesh = mesh
	add_child(beam)
	return beam


func _configure_mining_laser_material() -> void:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.08, 1.0, 0.26, 0.62)
	mat.emission_enabled = true
	mat.emission = Color(0.08, 1.0, 0.26)
	mat.emission_energy_multiplier = 3.2
	mining_laser.material_override = mat

# ── Kitbash player ship ──────────────────────────────────────────────────────
const PLAYER_SHIP_TARGET_SIZE := 16.0   # largest visual extent in world units
const PLAYER_SHIP_TILT_DEG := 0.0       # upright (vertical) — was close enough
var _player_model_size: Vector3 = Vector3(8, 4.5, 8)   # scaled model AABB (fallback ~old box)
var _drone_orbit_radius: float = 6.8
var _drone_size: float = 0.12
var hardpoints: Array[Node3D] = []   # combat-fire origins (weapon_* markers on the model)
var _hp_idx: int = 0

## Build the gunmetal hull.tall hero ship and fit it into the Visual node.
func _build_player_ship_model() -> void:
	var model := ShipAssembler.build_special(0)   # ★ Gunmetal — Tall
	if model == null:
		push_warning("[PlayerShip] Assembler failed; keeping empty Visual.")
		return
	visual.add_child(model)
	var box := _model_aabb(model)
	var longest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest < 0.01:
		return
	var s: float = PLAYER_SHIP_TARGET_SIZE / longest
	model.scale = Vector3(s, s, s)
	# Center the model's AABB on the ship origin.
	model.position = -(box.position + box.size * 0.5) * s
	_player_model_size = box.size * s
	# Drones fit to the new hull: orbit just outside the widest half-extent.
	var half_w: float = maxf(_player_model_size.x, _player_model_size.z) * 0.5
	_drone_orbit_radius = half_w + 2.5
	_drone_size = clampf(longest * s * 0.04, 0.25, 0.6)
	# Lean the (centered) ship off-vertical so the exhaust + top read in the
	# behind-and-above camera. Visual only holds the model, so this pivots clean.
	visual.rotation_degrees.x = PLAYER_SHIP_TILT_DEG
	_refit_collision()
	_collect_hardpoints(model)

## Gather the model's weapon_* markers as combat-fire origins (turrets).
func _collect_hardpoints(node: Node) -> void:
	hardpoints.clear()
	_walk_hardpoints(node)

func _walk_hardpoints(node: Node) -> void:
	if node is Node3D:
		var n := str(node.name).to_lower()
		if n.begins_with("weapon_") or "hardpoint" in n:
			hardpoints.append(node as Node3D)
	for c in node.get_children():
		_walk_hardpoints(c)


func _get_mining_beam_origin(offset_index: int = 0) -> Vector3:
	if offset_index == 0:
		return global_position \
			+ (-global_transform.basis.z * 2.0) \
			- (global_transform.basis.x * 2.6) \
			+ (global_transform.basis.y * 0.6)
	if offset_index == 1:
		return global_position \
			+ (-global_transform.basis.z * 2.0) \
			+ (global_transform.basis.x * 0.65) \
			+ (global_transform.basis.y * 0.25)
	if not hardpoints.is_empty():
		var hp := hardpoints[abs(offset_index) % hardpoints.size()]
		if is_instance_valid(hp):
			return hp.global_position
	var side := -1.0 if offset_index % 2 == 0 else 1.0
	return global_position \
		+ (-global_transform.basis.z * 2.0) \
		+ (global_transform.basis.x * side * 1.4)


func _set_beam_between(
		beam: MeshInstance3D,
		start: Vector3,
		end: Vector3,
		radius: float
) -> void:
	if beam == null or not is_instance_valid(beam):
		return
	var length := start.distance_to(end)
	if length <= 0.05:
		beam.visible = false
		return
	beam.visible = true
	beam.global_position = (start + end) * 0.5
	beam.look_at(end, Vector3.UP)
	beam.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	beam.scale = Vector3(radius, length / 2.0, radius)


func _hide_mining_beams(reset_lock: bool = true) -> void:
	mining_laser.visible = false
	if _mining_tractor_laser:
		_mining_tractor_laser.visible = false
	if _mine_particles:
		_mine_particles.emitting = false
	AudioManager.stop_mining_audio()
	if reset_lock:
		_mining_tractor_target_id = 0
		_mining_tractor_lock_timer = 0.0


func _get_mining_target_point(target_node: Node3D) -> Vector3:
	var origin := _get_mining_beam_origin(0)
	if target_node.has_method("get_mining_contact_point"):
		return target_node.call("get_mining_contact_point", origin) as Vector3
	return target_node.global_position


func _get_tractor_target_point(target_node: Node3D, tractor_origin: Vector3) -> Vector3:
	var to_ship := (tractor_origin - target_node.global_position).normalized()
	if to_ship == Vector3.ZERO:
		to_ship = -global_transform.basis.z.normalized()
	var side := -global_transform.basis.x.normalized()
	if side == Vector3.ZERO or abs(side.dot(to_ship)) > 0.85:
		side = global_transform.basis.y.normalized()
	return target_node.global_position + side * 3.8 + to_ship * 0.9


func _get_desired_mining_asteroid_position(target_node: Node3D) -> Vector3:
	var origin := _get_mining_beam_origin(1)
	var from_ship := target_node.global_position - origin
	if from_ship == Vector3.ZERO:
		from_ship = -global_transform.basis.z
	return origin + from_ship.normalized() * 35.0

func _refit_collision() -> void:
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs and cs.shape is BoxShape3D:
		var box := cs.shape.duplicate() as BoxShape3D
		box.size = Vector3(
			maxf(_player_model_size.x * 0.7, 2.0),
			maxf(_player_model_size.y * 0.55, 2.0),
			maxf(_player_model_size.z * 0.8, 2.0))
		cs.shape = box

func _model_aabb(node: Node3D) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_collect_player_meshes(node, meshes)
	var combined := AABB()
	var first := true
	for mi in meshes:
		var rel := node.global_transform.affine_inverse() * mi.global_transform
		var b := rel * mi.get_aabb()
		if first:
			combined = b; first = false
		else:
			combined = combined.merge(b)
	return combined

func _collect_player_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect_player_meshes(c, out)

var _nose_ray: ShapeCast3D = null

func _create_nose_raycast() -> void:
	_nose_ray = ShapeCast3D.new()
	# Sphere radius gives the whisker its vertical + lateral reach.
	# 10u catches obstacles the underbelly or wingtips would clip before the center does.
	var sphere := SphereShape3D.new()
	sphere.radius = 10.0
	_nose_ray.shape = sphere
	_nose_ray.target_position = Vector3(0, 0, -55)  # 55 units forward (-Z = ship nose)
	_nose_ray.collision_mask = 1
	_nose_ray.exclude_parent = true
	_nose_ray.enabled = false    # only active during autopilot
	add_child(_nose_ray)

func sync_camera_to_ship() -> void:
	camera_pivot.global_position = global_position

# ── Combat cinematic camera ─────────────────────────────────────────────────────
func _on_combat_started_orbit(enemy: Node) -> void:
	_release_mouse_capture()
	if not is_instance_valid(enemy):
		return
	_enter_orbit(enemy)

func _on_planning_started_orbit(_ap: int, _max: int, _intent: Dictionary, _taunts: Dictionary) -> void:
	# Re-settle into the slow planning orbit each turn (ships may have moved).
	if _cam_mode == 0:
		return
	if is_instance_valid(CombatManager.enemy_node):
		_enter_orbit(CombatManager.enemy_node)
	else:
		_cam_mode = 1

func _enter_orbit(enemy: Node) -> void:
	_orbit_midpoint = (global_position + (enemy as Node3D).global_position) * 0.5
	var sep := global_position.distance_to((enemy as Node3D).global_position)
	_orbit_radius = _find_safe_orbit_radius(enemy, sep)
	# Start orbit angle from current camera yaw so the transition is seamless.
	var to_cam := camera_pivot.global_position - _orbit_midpoint
	_orbit_angle = atan2(to_cam.x, to_cam.z)
	# Seed the smoothed look from where the camera is currently pointing so
	# the rotation eases in rather than snapping to the orbit midpoint.
	_cam_look_cur = camera_pivot.global_position + (-camera_pivot.basis.z) * 20.0
	_cam_entry_t  = 0.0   # triggers slow entry ramp
	_cam_mode = 1
	# New turn settles back into orbit — start the repeat-framing streak fresh.
	_last_telegraph_action = -1
	_cam_lerp_speed = _ORBIT_LERP

func _on_combat_ended_orbit(_won: bool) -> void:
	_release_mouse_capture()
	_cam_mode = 0
	# Snap pivot back above the ship so the next frame resumes normal follow
	camera_pivot.global_position = global_position
	# Clear any leftover cinematic FOV/shake so normal flight isn't zoomed or jittery.
	_fov_punch = 0.0
	_shake_strength = 0.0
	camera.fov = _base_fov
	camera.h_offset = 0.0
	camera.v_offset = 0.0


func _release_mouse_capture() -> void:
	rmb_dragging = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# Punch in to frame the acting ship firing toward its target.
func _on_action_telegraphed_cam(action_type: int, source: Node, target: Node) -> void:
	if _cam_mode == 0 or not is_instance_valid(source):
		return
	# Same attack twice in a row → flip the framing side for a fresh angle.
	if action_type == _last_telegraph_action:
		_frame_flip = not _frame_flip
	else:
		_frame_flip = false
	_last_telegraph_action = action_type
	_frame_action(source, target, _frame_flip)
	AudioManager.play_sfx(CombatManager.SFX.get("cam_whoosh"), -8.0)

# Quick push toward the impact point (shake added in Phase 3).
func _on_action_impact_cam(_target: Node, world_pos: Vector3, dmg: float, _lethal: bool, blocked: bool, crit: bool) -> void:
	if _cam_mode != 2:
		return
	# Nudge the look + goal a touch toward the impact for a reactive feel.
	_cam_look_at = _cam_look_at.lerp(world_pos, 0.5)
	_cam_goal_pos = _cam_goal_pos.lerp(world_pos, 0.12)
	# Shake scales with damage; blocked hits barely rattle, crits hit hard.
	var mag := clampf(dmg / 30.0, 0.15, 1.0)
	if blocked:
		mag *= 0.4
	if crit:
		mag *= 1.4
	_trigger_shake(mag)
	# Snap-zoom punch on the hit — sharper for crits, barely there on a block.
	_punch_fov(-clampf(mag * 6.0, 1.5, 7.0))

func _trigger_shake(strength: float) -> void:
	_shake_strength = maxf(_shake_strength, clampf(strength, 0.0, 1.5))
	_shake_decay = _shake_strength

# Punch in tight on the kill and rattle the camera for the death beat.
func _on_combat_kill_cam(_victim: Node, world_pos: Vector3) -> void:
	if _cam_mode == 0:
		return
	# Pull the camera close to the explosion along its current view direction.
	var dir := (camera_pivot.global_position - world_pos)
	if dir.length() < 0.01:
		dir = Vector3(0, 6, 14)
	dir = dir.normalized()
	# Pull distance scales with hull size so a bigger ship's death blast still
	# frames tight rather than overflowing the view.
	var scale := _cam_ship_scale()
	_cam_goal_pos = world_pos + dir * (16.0 * scale) + Vector3(0, 5.0 * scale, 0)
	_cam_look_at = world_pos
	_cam_mode = 2
	_cam_lerp_speed = 5.5
	# Hard snap toward the kill, then the biggest zoom punch + rattle of the fight.
	camera_pivot.global_position = camera_pivot.global_position.lerp(_cam_goal_pos, 0.4)
	_trigger_shake(1.1)
	_punch_fov(-9.0)

# Punch-in framing scale relative to the original hero ship. ~1.0 for the old
# hull, ~2.0 for the upgraded kitbash hull. Clamped so an extreme ship can't
# fling the camera into the next county.
func _cam_ship_scale() -> float:
	var ext: float = maxf(_player_model_size.x, maxf(_player_model_size.y, _player_model_size.z))
	return clampf(ext / _CAM_REF_SHIP_EXTENT, 1.0, 2.6)

# Kick the FOV for a snap-zoom punch; springs back to _base_fov in _process.
func _punch_fov(amount: float) -> void:
	_fov_punch = amount

func _frame_action(source: Node, target: Node, flip: bool = false) -> void:
	var src: Vector3 = (source as Node3D).global_position
	var tgt: Vector3 = (target as Node3D).global_position if is_instance_valid(target) else src
	var axis := tgt - src
	if axis.length() < 0.01:
		axis = -global_transform.basis.z
	axis = axis.normalized()
	var side := axis.cross(Vector3.UP).normalized()
	if side.length() < 0.01:
		side = Vector3.RIGHT
	# Offsets scale with hull size so the larger ship frames like the original did
	# instead of clipping the camera into the hull or sitting too tight.
	var scale := _cam_ship_scale()
	var sep := clampf(src.distance_to(tgt), 18.0, 60.0)
	var back := sep * 0.30 * scale
	var sideways := sep * 0.50 * scale
	var height := sep * 0.28 * scale
	var look := src.lerp(tgt, 0.55)   # bias toward target so the shot is in frame
	var space := get_world_3d().direct_space_state
	var excl := [get_rid()]
	if is_instance_valid(target) and target is CollisionObject3D:
		excl.append((target as CollisionObject3D).get_rid())
	# Preferred shoulder flips on a repeated attack, and the flipped shot rides a
	# little higher/tighter so the new angle reads as a distinct camera position.
	var lead_sign := -1.0 if flip else 1.0
	if flip:
		height *= 1.25
		back   *= 0.85
	# Try the preferred shoulder, then the opposite, then a pulled-back fallback.
	var candidates: Array[Vector3] = [
		src - axis * back + side * sideways * lead_sign + Vector3.UP * height,
		src - axis * back - side * sideways * lead_sign + Vector3.UP * height,
		src - axis * (back + sep * 0.4 * scale) + Vector3.UP * (height + sep * 0.3 * scale),
	]
	var chosen := candidates[0]
	for pos in candidates:
		if _cam_pos_clear(space, excl, pos, [src, tgt]):
			chosen = pos
			break
	_cam_goal_pos = chosen
	_cam_look_at = look
	_cam_mode = 2
	_cam_lerp_speed = _ACTION_LERP
	# Sharp cut-in: jump the pivot a third of the way to the goal immediately so
	# the move starts fast and snaps to a settle, plus a quick zoom + rattle for
	# kinetic energy that decays before the shot fires.
	camera_pivot.global_position = camera_pivot.global_position.lerp(_cam_goal_pos, 0.35)
	_punch_fov(-4.0)
	_trigger_shake(0.3)

func _process(delta: float) -> void:
	if _cam_mode == 0:
		return
	# Wall-clock delta so camera speed is constant regardless of time_scale slow-mo.
	var real_delta := delta / maxf(Engine.time_scale, 0.01)
	if _cam_mode == 1:
		_orbit_angle += _ORBIT_SPEED * real_delta
		var x := sin(_orbit_angle) * _orbit_radius
		var z := cos(_orbit_angle) * _orbit_radius
		_cam_goal_pos = _orbit_midpoint + Vector3(x, _ORBIT_HEIGHT, z)
		_cam_look_at  = _orbit_midpoint
		# Ramp position lerp from slow entry speed up to normal orbit speed.
		_cam_entry_t  = minf(1.0, _cam_entry_t + real_delta / _CAM_ENTRY_DUR)
		_cam_lerp_speed = lerpf(1.0, _ORBIT_LERP, _cam_entry_t)
	# Smooth look-target: slow ease during orbit entry, snappy during action punch-ins.
	var _look_speed := _ACTION_LERP if _cam_mode == 2 \
		else _CAM_LOOK_LERP * lerpf(0.25, 1.0, _cam_entry_t)
	_cam_look_cur = _cam_look_cur.lerp(_cam_look_at, minf(real_delta * _look_speed, 1.0))
	# Common glide toward goal (action mode keeps its fixed goal).
	camera_pivot.global_position = camera_pivot.global_position.lerp(
		_cam_goal_pos, minf(real_delta * _cam_lerp_speed, 1.0))
	if camera_pivot.global_position.distance_to(_cam_look_cur) > 0.5:
		camera_pivot.look_at(_cam_look_cur, Vector3.UP)
	# Decaying camera shake on top of the framing.
	if _shake_strength > 0.0:
		_shake_strength = maxf(0.0, _shake_strength - _shake_decay * real_delta * 2.5)
		camera.h_offset = randf_range(-_shake_strength, _shake_strength)
		camera.v_offset = randf_range(-_shake_strength, _shake_strength)
	elif camera.h_offset != 0.0 or camera.v_offset != 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	# FOV punch springs back to rest — snaps in instantly, eases out.
	if not is_equal_approx(_fov_punch, 0.0):
		_fov_punch = lerpf(_fov_punch, 0.0, minf(real_delta * 7.0, 1.0))
		if absf(_fov_punch) < 0.05:
			_fov_punch = 0.0
		camera.fov = _base_fov + _fov_punch
	elif not is_equal_approx(camera.fov, _base_fov):
		camera.fov = _base_fov

func _find_safe_orbit_radius(enemy: Node, ship_sep: float) -> float:
	var min_r := maxf(ship_sep * 0.9, 28.0)
	var max_r := maxf(ship_sep * 2.2, 90.0)
	var space  := get_world_3d().direct_space_state
	var excl   := [get_rid()]
	if is_instance_valid(enemy) and enemy is CollisionObject3D:
		excl.append((enemy as CollisionObject3D).get_rid())
	for ri in range(4):
		var r := lerpf(min_r, max_r, float(ri) / 3.0)
		for ai in range(8):
			var angle := TAU * float(ai) / 8.0
			var pos   := _orbit_midpoint + Vector3(sin(angle) * r, _ORBIT_HEIGHT, cos(angle) * r)
			if _cam_pos_clear(space, excl, pos, [_orbit_midpoint, global_position]):
				_orbit_angle = angle
				return r
	return min_r  # fallback

# A camera position is "clear" if it has line of sight to every look target.
func _cam_pos_clear(space: PhysicsDirectSpaceState3D, excl: Array, pos: Vector3, targets: Array) -> bool:
	for t in targets:
		var q := PhysicsRayQueryParameters3D.create(pos, t)
		q.exclude = excl
		if not space.intersect_ray(q).is_empty():
			return false
	return true

func _on_target_changed(new_target: Node3D):
	last_target = new_target


func begin_target_navigation(mode: String) -> bool:
	var selected := GlobalState.active_target
	if selected == null or not is_instance_valid(selected):
		return false
	navigation_target = selected
	_clear_planned_route()
	route_notice_sent = false
	route_notice_override = ""
	route_stall_replans = 0
	nav_mode = mode
	if _nose_ray:
		_nose_ray.enabled = true
	return true


func cancel_autopilot(clear_motion: bool = false) -> void:
	nav_mode = "MANUAL"
	navigation_target = null
	target_position = null
	staged_jump_gate_id = 0
	_clear_planned_route()
	route_notice_sent = false
	route_notice_override = ""
	route_stall_replans = 0
	_clear_avoidance_state()
	if _nose_ray:
		_nose_ray.enabled = false
	_hide_mining_beams()
	if clear_motion:
		current_speed = 0.0
		velocity = Vector3.ZERO


func hard_stop() -> void:
	boost_timer = 0.0
	cancel_autopilot(true)


func activate_boost() -> bool:
	if destroyed or is_docked or boost_timer > 0.0 or boost_cooldown_timer > 0.0:
		return false
	boost_timer = BOOST_DURATION_SECONDS
	boost_cooldown_timer = BOOST_COOLDOWN_SECONDS
	health = maxf(1.0, health - BOOST_HEAT_DAMAGE)
	AudioManager.play_align()
	return true


func boost_cooldown_remaining() -> float:
	return boost_cooldown_timer


func boost_active_remaining() -> float:
	return boost_timer


func can_activate_boost() -> bool:
	return not destroyed and not is_docked and boost_timer <= 0.0 and boost_cooldown_timer <= 0.0

func _unhandled_input(event: InputEvent):
	# While docked the dock UI owns the screen — block any world-bound
	# input (LMB fly-to, RMB targeting, camera orbit, autopilot keys).
	# Control children of the dock menu still get their own _gui_input
	# before this runs, so dock buttons keep working.
	if is_docked:
		return
	# CombatPanel owns input during turn-based planning and execution.
	if CombatManager.state != CombatManager.State.IDLE:
		return
	if event.is_action_pressed("hard_stop"):
		hard_stop()
		return
	# Autopilot override keys
	if event.is_action_pressed("override_approach"):
		var t = GlobalState.active_target
		if t and is_instance_valid(t):
			begin_target_navigation(
				"JUMP_APPROACH" if t.is_in_group("jumpgate") else "APPROACH"
			)
			var ui = GlobalState.get_ui_manager()
			if ui and ui.has_method("show_target_marker"):
				ui.show_target_marker(t.global_position)
	elif event.is_action_pressed("override_orbit"):
		var t = GlobalState.active_target
		if t and is_instance_valid(t):
			begin_target_navigation("ORBIT")
			var ui = GlobalState.get_ui_manager()
			if ui and ui.has_method("show_target_marker"):
				ui.show_target_marker(t.global_position)
	elif event.is_action_pressed("override_action"):
		var t = GlobalState.active_target
		if t and is_instance_valid(t):
			if t.is_in_group("asteroid"):
				begin_target_navigation("MINE")
			elif t.is_in_group("station"):
				begin_target_navigation("DOCK")
			elif t.is_in_group("jumpgate"):
				var ui = GlobalState.get_ui_manager()
				if ui and ui.has_method("activate_selected_jumpgate"):
					ui.activate_selected_jumpgate()
				return
			else:
				begin_target_navigation("ATTACK")
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
			rmb_press_position = event.position
			rmb_dragging = false
		else:
			var hold_duration = Time.get_unix_time_from_system() - rmb_down_time
			if rmb_dragging:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			elif hold_duration < 0.35:
				# Short RMB click: Try targeting / open context menu
				var hit = get_mouse_raycast_hit(rmb_press_position)
				if hit.has("collider"):
					var entity: Node = hit.collider
					var system_root := GlobalState.get_system_root()
					while entity and system_root and entity.get_parent() != system_root:
						entity = entity.get_parent()
					if entity and entity != self:
						var ui = GlobalState.get_ui_manager()
						if ui and ui.has_method("show_context_menu"):
							ui.show_context_menu(
								entity,
								rmb_press_position
							)
			rmb_dragging = false
							
	# Drag Camera Orbit
	if event is InputEventMouseMotion \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if not rmb_dragging \
				and event.position.distance_to(rmb_press_position) >= 6.0:
			rmb_dragging = true
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if rmb_dragging:
			camera_pivot.rotation.y -= event.relative.x * 0.003
			camera_pivot.rotation.x -= event.relative.y * 0.003
			camera_pivot.rotation.x = clamp(
				camera_pivot.rotation.x,
				-deg_to_rad(80),
				deg_to_rad(80)
			)
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

func get_mouse_raycast_hit(
	screen_position: Variant = null
) -> Dictionary:
	var mouse_pos := (
		screen_position as Vector2
		if screen_position is Vector2
		else get_viewport().get_mouse_position()
	)
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_normal: Vector3 = camera.project_ray_normal(mouse_pos)
	
	var space_state = get_world_3d().direct_space_state
	var ray_end := ray_origin + ray_normal * WORLD_PICK_DISTANCE
	var excluded_rids: Array[RID] = [get_rid()]
	for _attempt in range(8):
		var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
		query.collide_with_areas = true
		query.exclude = excluded_rids
		var result = space_state.intersect_ray(query)
		if result.is_empty():
			return result
		var collider = result.get("collider")
		if not _mouse_pick_should_pass_through(collider):
			return result
		if collider is CollisionObject3D:
			excluded_rids.append((collider as CollisionObject3D).get_rid())
		else:
			return result
	return {}


func _mouse_pick_should_pass_through(collider: Variant) -> bool:
	if not collider is Node3D:
		return false
	var node := collider as Node3D
	if not node.is_in_group("station"):
		return false
	var ring_node := node.get_node_or_null("Ring") as MeshInstance3D
	if ring_node == null or not ring_node.visible:
		return false
	return node.get_node_or_null("CoreSelection") != null

func _physics_process(delta: float):
	if boost_timer > 0.0:
		boost_timer = maxf(0.0, boost_timer - delta)
	if boost_cooldown_timer > 0.0:
		boost_cooldown_timer = maxf(0.0, boost_cooldown_timer - delta)
	_update_boost_effects(delta)

	if not mining_laser.visible:
		if _mine_particles:
			_mine_particles.emitting = false

	if GlobalState.paused:
		_hide_mining_beams()
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
		
	# Animate orbiting drones and collection behavior
	_update_drones(delta)
	_update_salvage(delta)

	# Update drone colors based on health
	_update_drone_colors()
			
	# Follow player position (suppressed while the combat camera is driving)
	if _cam_mode == 0:
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
		_hide_mining_beams()
		if nav_mode == "MINE":
			nav_mode = "MANUAL"
			target_position = null
	# When a special item is loaded, hide the mining laser entirely —
	# the player can't mine until they deliver or jettison the special.
	elif GlobalState.cargo_type == GlobalState.CargoType.SPECIAL:
		_hide_mining_beams()
			
	if fire_cooldown > 0.0:
		fire_cooldown -= delta
		
	# Autopilot updates
	var active_target := navigation_target
	if active_target == null or not is_instance_valid(active_target):
		active_target = null
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
					_hide_mining_beams()
				else:
					var mining_point := _get_mining_target_point(active_target)
					var mining_dist := global_position.distance_to(mining_point)
					target_position = mining_point
					if mining_dist < MINING_RANGE + 18.0:
						steer_towards(mining_point, delta)
						perform_action(active_target, delta)
					else:
						_hide_mining_beams()

			"ATTACK":
				target_position = active_target.global_position
				if dist < MINING_RANGE:
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
		_hide_mining_beams()
		if nav_mode in ["APPROACH", "APPROACH_1K", "JUMP_APPROACH", "ORBIT", "MINE", "ATTACK", "DOCK"]:
			cancel_autopilot()

	# Move and steer
	if target_position != null:
		var dest := target_position as Vector3
		var steer_target := dest
		if nav_mode == "MINE":
			steer_target = dest
		elif nav_mode != "ORBIT":
			# Nose whisker: sphere-cast 55u forward + 10u radius (covers underbelly
			# and wingtips). If anything other than the nav target is in the volume,
			# force an immediate replan without waiting for the stall timer.
			if _nose_ray and _nose_ray.is_colliding():
				var hit_obj := _nose_ray.get_collider(0)
				if hit_obj != active_target and hit_obj != self:
					_clear_planned_route()

			var route_result := _route_steer_target(dest, active_target)
			if not bool(route_result.get("ok", false)):
				_emit_route_failure(str(route_result.get("error", "")))
				cancel_autopilot()
				return
			steer_target = route_result.get("steer_target", dest)
			if not _update_route_progress(steer_target, delta):
				return

			# Real-time avoidance: scan for obstacles along the current heading
			# and override the steer target if something is in the way.
			var avoidance := _get_autopilot_avoidance(steer_target, active_target)
			if avoidance.get("is_avoiding", false):
				steer_target = avoidance.get("steer_target", steer_target)

		steer_towards(steer_target, delta)
		
		var speed_limit: float = max_speed * GlobalState.engine_speed_mult
		if boost_timer > 0.0:
			speed_limit *= BOOST_SPEED_MULTIPLIER
		var target_speed: float = speed_limit
		
		# Proportional speed controller to maintain safe distance from targets
		if active_target and is_instance_valid(active_target):
			var dist = global_position.distance_to(active_target.global_position)
			
			if nav_mode == "APPROACH":
				var target_stop_dist = 60.0
				if active_target.is_in_group("celestial"):
					target_stop_dist = _get_obstacle_radius(active_target) \
						+ _get_obstacle_safety_margin(active_target)
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
				var mining_point := _get_mining_target_point(active_target)
				var mining_dist := global_position.distance_to(mining_point)
				if _mining_tractor_target_id == active_target.get_instance_id() \
						and _mining_tractor_laser \
						and _mining_tractor_laser.visible:
					target_speed = 0.0
				else:
					target_speed = clamp((mining_dist - 35.0) * 3.0, -speed_limit, speed_limit)
			elif nav_mode == "ATTACK" and active_target.is_in_group("ship"):
				# Keep 45m from attacked hostile NPC ships
				target_speed = clamp((dist - 45.0) * 3.0, -speed_limit, speed_limit)
			elif nav_mode == "DOCK":
				var remaining_dock_distance := global_position.distance_to(target_position as Vector3)
				target_speed = clamp(remaining_dock_distance * 2.0, 0.0, speed_limit)
			elif nav_mode == "MOVE_TO_POINT":
				target_speed = clamp(
					global_position.distance_to(dest) * 2.0,
					0.0,
					speed_limit
				)
			
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
		
		if global_position.distance_to(dest) < 2.0 \
				and nav_mode == "MOVE_TO_POINT":
			cancel_autopilot()
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

func _route_steer_target(
	destination: Vector3,
	route_target: Node3D
) -> Dictionary:
	var needs_plan := planned_route.is_empty() \
		or planned_route_index >= planned_route.size() \
		or planned_destination.distance_to(destination) > 35.0
	if needs_plan:
		var hazards := _navigation_hazards(route_target)
		var planned := _plan_route_with_belt_clearance(
			destination,
			route_target,
			hazards
		)
		if planned.is_empty():
			planned = NavigationRoutePlannerType.plan_route(
				global_position,
				destination,
				hazards
			)
		if not bool(planned.get("ok", false)):
			planned = _plan_route_with_vertical_clearance(
				destination,
				route_target,
				hazards
			)
		if not bool(planned.get("ok", false)):
			return planned
		planned_route.clear()
		for waypoint in planned.get("waypoints", []):
			planned_route.append(waypoint as Vector3)
		planned_route_index = 0
		planned_destination = destination
		route_plan_count += 1
		route_stall_replans = 0
		route_notice_override = str(planned.get("notice", ""))
		if planned_route.size() > 1:
			_emit_planned_route_notice(planned_route.size())
	var prev_index := planned_route_index
	while planned_route_index < planned_route.size() - 1 \
			and global_position.distance_to(
				planned_route[planned_route_index]
			) < 18.0:
		planned_route_index += 1
		route_progress_distance = INF
		route_stall_timer = 0.0
	# After advancing to a new waypoint, verify the remaining path is still clear.
	# If an obstacle has moved into it since we planned, replan immediately.
	if planned_route_index != prev_index and planned_route_index < planned_route.size():
		var remaining: Array[Vector3] = []
		for i in range(planned_route_index, planned_route.size()):
			remaining.append(planned_route[i])
		var hazards := _navigation_hazards(route_target)
		if not NavigationRoutePlannerType.route_is_clear(global_position, remaining, hazards):
			_clear_planned_route()
			return _route_steer_target(destination, route_target)
	if planned_route_index >= planned_route.size():
		return {"ok": true, "steer_target": destination}
	return {
		"ok": true,
		"steer_target": planned_route[planned_route_index],
	}


func _plan_route_with_belt_clearance(
	destination: Vector3,
	route_target: Node3D,
	hazards: Array
) -> Dictionary:
	var belt_planet := _find_belt_planet_crossing_route(destination, route_target)
	if belt_planet == null:
		return {}
	var clearance_y := float(
		belt_planet.get_meta("belt_clearance_y", AUTOPILOT_BELT_CLEARANCE_Y)
	)
	clearance_y = maxf(clearance_y, AUTOPILOT_BELT_CLEARANCE_Y)
	for y_sign in [-1.0, 1.0]:
		var lane_y: float = belt_planet.global_position.y + clearance_y * y_sign
		var waypoints: Array[Vector3] = [
			Vector3(global_position.x, lane_y, global_position.z),
			Vector3(destination.x, lane_y, destination.z),
			destination,
		]
		if NavigationRoutePlannerType.route_is_clear(
			global_position,
			waypoints,
			hazards
		):
			return {
				"ok": true,
				"waypoints": waypoints,
				"notice": (
					"NAVIGATION: Moving clear of the asteroid field. "
					+ "Replanning safe destination checkpoints."
				),
			}
	return {}


func _find_belt_planet_crossing_route(
	destination: Vector3,
	route_target: Node3D
) -> Node3D:
	if (
		route_target == null
		or not is_instance_valid(route_target)
		or not route_target.is_in_group("station")
	):
		return null
	var best_planet: Node3D = null
	var best_distance := INF
	for candidate in get_tree().get_nodes_in_group("celestial"):
		if not candidate is Node3D:
			continue
		var planet := candidate as Node3D
		if not planet.has_meta("belt_clearance_y") \
				or not _planet_has_orbiting_asteroids(planet):
			continue
		var route_distance := _distance_point_to_segment(
			planet.global_position,
			global_position,
			destination
		)
		var ring_clearance := float(
			planet.get_meta("navigation_clearance_radius", 0.0)
		)
		if ring_clearance <= 0.0 or route_distance > ring_clearance + 120.0:
			continue
		if route_distance < best_distance:
			best_distance = route_distance
			best_planet = planet
	return best_planet


func _plan_route_with_vertical_clearance(
	destination: Vector3,
	route_target: Node3D,
	hazards: Array
) -> Dictionary:
	if route_target != null \
			and is_instance_valid(route_target) \
			and route_target.is_in_group("asteroid"):
		return {
			"ok": false,
			"error": "No safe route is available.",
			"waypoints": [],
		}
	var blocker := _find_celestial_crossing_route(destination, route_target)
	if blocker == null:
		return {
			"ok": false,
			"error": "No safe route is available.",
			"waypoints": [],
		}
	var clearance_y := maxf(
		float(blocker.get_meta("belt_clearance_y", AUTOPILOT_BELT_CLEARANCE_Y)),
		_get_obstacle_radius(blocker) + _get_obstacle_safety_margin(blocker) + 80.0
	)
	for y_sign in [-1.0, 1.0]:
		var lane_y: float = blocker.global_position.y + clearance_y * y_sign
		var waypoints: Array[Vector3] = [
			Vector3(global_position.x, lane_y, global_position.z),
			Vector3(destination.x, lane_y, destination.z),
			destination,
		]
		if NavigationRoutePlannerType.route_is_clear(
			global_position,
			waypoints,
			hazards
		):
			return {
				"ok": true,
				"waypoints": waypoints,
				"notice": (
					"NAVIGATION: Direct path obstructed. "
					+ "Replanning safe destination checkpoints."
				),
			}
	return {
		"ok": false,
		"error": "No safe route is available.",
		"waypoints": [],
	}


func _find_celestial_crossing_route(
	destination: Vector3,
	route_target: Node3D
) -> Node3D:
	var best_body: Node3D = null
	var best_distance := INF
	for candidate in get_tree().get_nodes_in_group("celestial"):
		if not candidate is Node3D or candidate == route_target:
			continue
		var body := candidate as Node3D
		var clearance := _get_navigation_clearance_for_destination(
			body,
			destination,
			route_target
		)
		var route_distance := _distance_point_to_segment(
			body.global_position,
			global_position,
			destination
		)
		if route_distance > clearance:
			continue
		if route_distance < best_distance:
			best_distance = route_distance
			best_body = body
	return best_body


func _planet_has_orbiting_asteroids(planet: Node3D) -> bool:
	for candidate in get_tree().get_nodes_in_group("asteroid"):
		if candidate is Node and candidate.get("navigation_parent") == planet:
			return true
	return false


func _distance_point_to_segment(
	point: Vector3,
	start: Vector3,
	finish: Vector3
) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared < 0.001:
		return point.distance_to(start)
	var along := clampf(
		(point - start).dot(segment) / length_squared,
		0.0,
		1.0
	)
	return point.distance_to(start + segment * along)


func _navigation_hazards(route_target: Node3D) -> Array:
	var hazards: Array = []
	var seen: Dictionary = {}
	for group_name in ["celestial", "station", "jumpgate", "asteroid"]:
		for candidate in get_tree().get_nodes_in_group(group_name):
			if not candidate is Node3D \
					or candidate == self \
					or candidate == route_target:
				continue
			var obstacle := candidate as Node3D
			if obstacle.get("destroyed"):
				continue
			if obstacle.is_in_group("asteroid") \
					and obstacle.get("navigation_parent") is Node3D:
				continue
			var obstacle_id := obstacle.get_instance_id()
			if seen.has(obstacle_id):
				continue
			seen[obstacle_id] = true
			hazards.append({
				"id": obstacle_id,
				"center": obstacle.global_position,
				"radius": _get_obstacle_radius(obstacle)
					+ _get_obstacle_safety_margin(obstacle),
			})
	return hazards


func _clear_planned_route() -> void:
	planned_route.clear()
	planned_route_index = 0
	planned_destination = Vector3.ZERO
	route_progress_distance = INF
	route_stall_timer = 0.0


func _update_route_progress(steer_target: Vector3, delta: float) -> bool:
	var remaining := global_position.distance_to(steer_target)
	if remaining < route_progress_distance - 0.5:
		route_progress_distance = remaining
		route_stall_timer = 0.0
		return true
	route_stall_timer += delta
	if route_stall_timer < 2.5:
		return true
	if route_stall_replans >= 2:
		_emit_route_failure(
			"Autopilot cancelled after the route remained obstructed."
		)
		cancel_autopilot()
		return false
	route_stall_replans += 1
	_clear_planned_route()
	current_speed = 0.0
	velocity = Vector3.ZERO
	return false


func _emit_planned_route_notice(waypoint_count: int) -> void:
	if route_notice_sent:
		return
	route_notice_sent = true
	last_navigation_status_message = route_notice_override
	if last_navigation_status_message.is_empty():
		last_navigation_status_message = (
			"NAVIGATION: Safe route confirmed through %d waypoints."
			% waypoint_count
		)
	GlobalState.emit_chatter(
		"SYSTEM",
		last_navigation_status_message,
		Color(0.0, 0.9, 0.9)
	)


func _emit_route_failure(message: String) -> void:
	last_navigation_status_message = (
		message
		if not message.is_empty()
		else "No safe route is available."
	)
	var ui := GlobalState.get_ui_manager()
	if ui and ui.has_method("show_hud_warning"):
		ui.call("show_hud_warning", last_navigation_status_message)


func get_planned_route() -> Array[Vector3]:
	return planned_route.duplicate()


func planned_route_is_clear() -> bool:
	if planned_route.is_empty():
		return false
	var remaining: Array[Vector3] = []
	for index in range(planned_route_index, planned_route.size()):
		remaining.append(planned_route[index])
	return NavigationRoutePlannerType.route_is_clear(
		global_position,
		remaining,
		_navigation_hazards(navigation_target)
	)


func _get_autopilot_avoidance(destination: Vector3, navigation_target: Node3D) -> Dictionary:
	var route := destination - global_position
	var route_length := route.length()
	if route_length < 1.0:
		_clear_avoidance_state()
		return {"steer_target": destination, "is_avoiding": false}

	var locked_obstacle := _get_locked_avoidance_obstacle()
	if locked_obstacle != null:
		var locked_clearance := _get_navigation_clearance_for_destination(
			locked_obstacle,
			destination,
			navigation_target
		)
		if locked_obstacle.is_in_group("celestial"):
			var reached_exit := (
				avoidance_waypoint != Vector3.ZERO
				and global_position.distance_to(avoidance_waypoint) < 22.0
			)
			if avoidance_waypoint == Vector3.ZERO:
				_set_initial_celestial_exit(
					locked_obstacle,
					locked_clearance,
					destination
				)
			elif reached_exit:
				# Only the celestial currently being circled decides whether
				# this route remains blocked. Other obstacles are acquired
				# after this orbit is released.
				if _is_route_clear_of_obstacle(
					destination,
					locked_obstacle,
					locked_clearance
				):
					_emit_navigation_route_clear(locked_obstacle)
					_clear_avoidance_state()
				else:
					_advance_celestial_exit(
						locked_obstacle,
						locked_clearance,
						destination
					)
			if avoidance_obstacle_id != 0:
				return {
					"steer_target": avoidance_waypoint,
					"is_avoiding": true,
					"obstacle_distance": maxf(
						global_position.distance_to(
							locked_obstacle.global_position
						) - locked_clearance,
						0.0
					),
					"obstacle": locked_obstacle,
				}
		else:
			if avoidance_waypoint == Vector3.ZERO:
				avoidance_waypoint = _build_avoidance_waypoint(
					locked_obstacle.global_position,
					locked_clearance
				)
			if global_position.distance_to(avoidance_waypoint) >= 20.0:
				return {
					"steer_target": avoidance_waypoint,
					"is_avoiding": true,
					"obstacle_distance": maxf(
						global_position.distance_to(
							locked_obstacle.global_position
						) - locked_clearance,
						0.0
					),
					"obstacle": locked_obstacle,
				}
			# Small and moving obstacles use one lateral bypass. Recalculate
			# after reaching it instead of orbiting the object indefinitely.
			_clear_avoidance_state()

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
		var required_clearance := _get_navigation_clearance_for_destination(
			obstacle,
			destination,
			navigation_target
		)
		if distance_to_route >= required_clearance:
			continue

		# Favor the first obstacle on the route. The normalized penetration is a
		# tiebreaker when large safety envelopes overlap.
		var penetration: float = (required_clearance - distance_to_route) / maxf(required_clearance, 1.0)
		var score: float = distance_along_route - penetration * 20.0
		var best_score: float = best_distance_along_route - (
			(best_clearance - best_distance_to_route) / maxf(best_clearance, 1.0)
		) * 20.0
		var obstacle_is_celestial := obstacle.is_in_group("celestial")
		var best_is_celestial := (
			best_obstacle != null
			and best_obstacle.is_in_group("celestial")
		)
		if best_is_celestial and not obstacle_is_celestial:
			continue
		if (
			best_obstacle == null
			or (obstacle_is_celestial and not best_is_celestial)
			or score < best_score
		):
			best_obstacle = obstacle
			best_clearance = required_clearance
			best_distance_to_route = distance_to_route
			best_distance_along_route = distance_along_route

	if best_obstacle == null:
		_clear_avoidance_state()
		return {"steer_target": destination, "is_avoiding": false}

	var obstacle_id: int = best_obstacle.get_instance_id()
	if avoidance_obstacle_id != obstacle_id:
		avoidance_obstacle_id = obstacle_id
		avoidance_side = _choose_avoidance_side(
			best_obstacle.global_position,
			route_direction
		)
		var initial_radial := global_position - best_obstacle.global_position
		initial_radial.y = 0.0
		var clockwise_tangent := Vector3.UP.cross(
			initial_radial.normalized()
		)
		avoidance_orbit_sign = (
			1.0
			if clockwise_tangent.dot(avoidance_side) >= 0.0
			else -1.0
		)
		if best_obstacle.is_in_group("celestial"):
			_emit_navigation_obstruction(best_obstacle)
			avoidance_orbit_sign = _choose_celestial_orbit_sign(
				best_obstacle,
				best_clearance,
				destination,
				avoidance_orbit_sign,
				navigation_target
			)
			_set_initial_celestial_exit(
				best_obstacle,
				best_clearance,
				destination
			)
		else:
			avoidance_waypoint = _build_avoidance_waypoint(
				best_obstacle.global_position,
				best_clearance
			)
	elif (
		avoidance_waypoint == Vector3.ZERO
		or global_position.distance_to(avoidance_waypoint) < 20.0
	):
		if best_obstacle.is_in_group("celestial"):
			_set_initial_celestial_exit(
				best_obstacle,
				best_clearance,
				destination
			)
		else:
			avoidance_waypoint = _build_avoidance_waypoint(
				best_obstacle.global_position,
				best_clearance
			)

	if not best_obstacle.is_in_group("celestial"):
		var blocking_celestial := _find_celestial_blocking_route(
			avoidance_waypoint,
			destination,
			navigation_target
		)
		if blocking_celestial != null:
			var celestial_clearance := _get_navigation_clearance_for_destination(
				blocking_celestial,
				destination,
				navigation_target
			)
			_clear_avoidance_state()
			avoidance_obstacle_id = blocking_celestial.get_instance_id()
			_emit_navigation_obstruction(blocking_celestial)
			var celestial_route := destination - global_position
			avoidance_side = _choose_avoidance_side(
				blocking_celestial.global_position,
				celestial_route.normalized()
			)
			avoidance_orbit_sign = 1.0
			avoidance_orbit_sign = _choose_celestial_orbit_sign(
				blocking_celestial,
				celestial_clearance,
				destination,
				avoidance_orbit_sign,
				navigation_target
			)
			_set_initial_celestial_exit(
				blocking_celestial,
				celestial_clearance,
				destination
			)
			return {
				"steer_target": avoidance_waypoint,
				"is_avoiding": true,
				"obstacle_distance": maxf(
					global_position.distance_to(
						blocking_celestial.global_position
					) - celestial_clearance,
					0.0
				),
				"obstacle": blocking_celestial,
			}

	return {
		"steer_target": avoidance_waypoint,
		"is_avoiding": true,
		"obstacle_distance": best_distance_along_route,
		"obstacle": best_obstacle,
	}

func _get_locked_avoidance_obstacle() -> Node3D:
	if avoidance_obstacle_id == 0:
		return null
	var candidate := instance_from_id(avoidance_obstacle_id)
	if candidate is Node3D and is_instance_valid(candidate):
		return candidate as Node3D
	_clear_avoidance_state()
	return null

func _has_clear_navigation_line(navigation_target: Node3D) -> bool:
	return is_navigation_target_visible(navigation_target)

func _is_route_clear_of_obstacle(
	destination: Vector3,
	obstacle: Node3D,
	required_clearance: float
) -> bool:
	var route := destination - global_position
	var route_length_squared := route.length_squared()
	if route_length_squared < 1.0:
		return true
	var along := clampf(
		(obstacle.global_position - global_position).dot(route)
			/ route_length_squared,
		0.0,
		1.0
	)
	var closest_point := global_position + route * along
	return closest_point.distance_to(obstacle.global_position) \
		>= required_clearance + 10.0

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

func _find_celestial_blocking_route(
	route_target: Vector3,
	destination: Vector3,
	navigation_target: Node3D
) -> Node3D:
	var closest: Node3D = null
	var closest_distance := INF
	for candidate in get_tree().get_nodes_in_group("celestial"):
		if not candidate is Node3D:
			continue
		var celestial := candidate as Node3D
		var clearance := _get_navigation_clearance_for_destination(
			celestial,
			destination,
			navigation_target
		)
		if _is_route_clear_of_obstacle(
			route_target,
			celestial,
			clearance
		):
			continue
		var distance := global_position.distance_to(celestial.global_position)
		if distance < closest_distance:
			closest = celestial
			closest_distance = distance
	return closest

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

func _choose_celestial_orbit_sign(
	obstacle: Node3D,
	required_clearance: float,
	destination: Vector3,
	preferred_sign: float,
	navigation_target: Node3D = null
) -> float:
	var target_orbit_sign := _get_target_orbit_sign(
		navigation_target,
		obstacle
	)
	if not is_zero_approx(target_orbit_sign):
		return target_orbit_sign

	var original_sign := avoidance_orbit_sign
	var best_sign := preferred_sign
	var best_score := INF
	for candidate_sign in [preferred_sign, -preferred_sign]:
		avoidance_orbit_sign = candidate_sign
		var candidate := _build_avoidance_waypoint(
			obstacle.global_position,
			required_clearance
		)
		var score := candidate.distance_to(destination)
		for other in get_tree().get_nodes_in_group("celestial"):
			if not other is Node3D or other == obstacle:
				continue
			var other_body := other as Node3D
			var other_clearance := _get_obstacle_radius(other_body) \
				+ _get_obstacle_safety_margin(other_body)
			if not _is_route_clear_of_obstacle(
				candidate,
				other_body,
				other_clearance
			):
				score += 1000000.0
		if score < best_score:
			best_score = score
			best_sign = candidate_sign
	avoidance_orbit_sign = original_sign
	return best_sign

func _get_target_orbit_sign(
	navigation_target: Node3D,
	celestial: Node3D
) -> float:
	if (
		navigation_target == null
		or celestial == null
		or not is_instance_valid(navigation_target)
		or not navigation_target.is_in_group("asteroid")
		or not _target_orbits_celestial(navigation_target, celestial)
		or not bool(navigation_target.get("is_orbiting"))
	):
		return 0.0

	var orbit_speed := float(navigation_target.get("orbit_speed"))
	if is_zero_approx(orbit_speed):
		return 0.0
	return signf(orbit_speed)

func _set_initial_celestial_exit(
	obstacle: Node3D,
	required_clearance: float,
	destination: Vector3
) -> void:
	var best_index := 0
	var best_score := INF
	for index in range(6):
		var candidate := _celestial_exit_position(
			obstacle.global_position,
			required_clearance,
			index
		)
		if not _is_route_clear_of_obstacle(
			candidate,
			obstacle,
			required_clearance
		):
			continue
		var crosses_other_celestial := false
		for other in get_tree().get_nodes_in_group("celestial"):
			if not other is Node3D or other == obstacle:
				continue
			var other_body := other as Node3D
			var other_clearance := _get_obstacle_radius(other_body) \
				+ _get_obstacle_safety_margin(other_body)
			if not _is_route_clear_of_obstacle(
				candidate,
				other_body,
				other_clearance
			):
				crosses_other_celestial = true
				break
		if crosses_other_celestial:
			continue
		var score := global_position.distance_to(candidate) \
			+ candidate.distance_to(destination)
		if score < best_score:
			best_score = score
			best_index = index
	avoidance_exit_index = best_index
	avoidance_exits_visited = 0
	avoidance_waypoint = _celestial_exit_position(
		obstacle.global_position,
		required_clearance,
		avoidance_exit_index
	)

func _advance_celestial_exit(
	obstacle: Node3D,
	required_clearance: float,
	destination: Vector3
) -> void:
	avoidance_exits_visited += 1
	if avoidance_exits_visited >= 6:
		# A moving target or changed clearance can invalidate the original
		# choice. Reassess once per lap and reverse direction rather than
		# silently beginning the same endless orbit.
		avoidance_full_lap_reassessments += 1
		avoidance_orbit_sign *= -1.0
		_set_initial_celestial_exit(
			obstacle,
			required_clearance,
			destination
		)
		return
	var step := 1 if avoidance_orbit_sign >= 0.0 else -1
	avoidance_exit_index = posmod(avoidance_exit_index + step, 6)
	avoidance_waypoint = _celestial_exit_position(
		obstacle.global_position,
		required_clearance,
		avoidance_exit_index
	)

func _celestial_exit_position(
	obstacle_position: Vector3,
	required_clearance: float,
	exit_index: int
) -> Vector3:
	var angle := TAU * float(posmod(exit_index, 6)) / 6.0
	var radial := Vector3(cos(angle), 0.0, sin(angle))
	# Six straight chords remain outside the protected circle when their
	# vertices use the circumscribed-hexagon radius.
	var exit_radius := required_clearance / cos(PI / 6.0) + 25.0
	return obstacle_position + radial * exit_radius

func _emit_navigation_obstruction(obstacle: Node3D) -> void:
	var obstacle_id := obstacle.get_instance_id()
	if navigation_notice_obstacle_id == obstacle_id:
		return
	navigation_notice_obstacle_id = obstacle_id
	var display_name := str(
		obstacle.get_meta("display_name", obstacle.name)
	).replace("_", " ")
	last_navigation_status_message = (
		"NAVIGATION: Direct route obstructed by %s. "
		+ "Plotting a safe orbital bypass."
	) % display_name
	navigation_obstruction_notice_count += 1
	GlobalState.emit_chatter(
		"SYSTEM",
		last_navigation_status_message,
		Color(0.0, 0.9, 0.9)
	)

func _emit_navigation_route_clear(obstacle: Node3D) -> void:
	if navigation_notice_obstacle_id != obstacle.get_instance_id():
		return
	last_navigation_status_message = (
		"NAVIGATION: Obstruction cleared. Resuming direct course."
	)
	navigation_route_clear_notice_count += 1
	GlobalState.emit_chatter(
		"SYSTEM",
		last_navigation_status_message,
		Color(0.0, 0.9, 0.9)
	)
	navigation_notice_obstacle_id = 0

func _build_avoidance_waypoint(
	obstacle_position: Vector3,
	required_clearance: float,
	waypoint_padding: float = 15.0
) -> Vector3:
	var from_obstacle := global_position - obstacle_position
	if absf(from_obstacle.y) < required_clearance:
		from_obstacle.y = 0.0
	var distance := from_obstacle.length()
	var waypoint_radius := required_clearance + waypoint_padding
	if distance < required_clearance + 1.0:
		var escape_direction := from_obstacle.normalized()
		if escape_direction.length_squared() < 0.5:
			escape_direction = avoidance_side
		return obstacle_position + escape_direction * waypoint_radius

	var radial := from_obstacle / distance
	var angle_step := deg_to_rad(10.0)

	# First join the circle at a tangent. Once on it, advance around the chosen
	# side in small arcs until the direct route to the destination is clear.
	if distance > waypoint_radius + 20.0:
		angle_step = acos(clampf(waypoint_radius / distance, 0.0, 1.0))
	var next_radial := Basis(
		Vector3.UP,
		avoidance_orbit_sign * angle_step
	) * radial
	return obstacle_position + next_radial.normalized() * waypoint_radius

func _get_obstacle_safety_margin(obstacle: Node3D) -> float:
	if obstacle.is_in_group("celestial"):
		var radius := _get_obstacle_radius(obstacle)
		var navigation_radius := float(
			obstacle.get_meta("navigation_clearance_radius", 0.0)
		)
		if navigation_radius > radius:
			return navigation_radius - radius
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

func _get_navigation_clearance_for_destination(
	obstacle: Node3D,
	destination: Vector3,
	navigation_target: Node3D
) -> float:
	var physical_radius := _get_obstacle_radius(obstacle)
	var configured_clearance := physical_radius \
		+ _get_obstacle_safety_margin(obstacle)
	if (
		not obstacle.is_in_group("celestial")
		or navigation_target == null
		or not is_instance_valid(navigation_target)
	):
		return configured_clearance

	var destination_radius := destination.distance_to(obstacle.global_position)
	if destination_radius >= configured_clearance:
		return configured_clearance
	var target_uses_celestial_corridor := (
		navigation_target.is_in_group("station")
		or _target_orbits_celestial(navigation_target, obstacle)
	)
	if not target_uses_celestial_corridor:
		return configured_clearance

	# Orbital stations and ring targets intentionally sit inside a planet's
	# broad navigation circle. Preserve a physical buffer while opening a
	# narrow final approach corridor on the target-facing side.
	var physical_clearance := physical_radius + maxf(
		100.0,
		physical_radius * 0.15
	)
	return physical_clearance

func _target_orbits_celestial(
	navigation_target: Node3D,
	celestial: Node3D
) -> bool:
	if navigation_target == null or celestial == null:
		return false
	var parent_value = navigation_target.get("navigation_parent")
	return (
		parent_value is Node3D
		and is_instance_valid(parent_value)
		and parent_value == celestial
	)

func is_navigation_target_visible(navigation_target: Node3D) -> bool:
	if navigation_target == null or not is_instance_valid(navigation_target):
		return false
	for obstacle in get_tree().get_nodes_in_group("celestial"):
		if not obstacle is Node3D or obstacle == navigation_target:
			continue
		var body := obstacle as Node3D
		var clearance := _get_navigation_clearance_for_destination(
			body,
			navigation_target.global_position,
			navigation_target
		)
		if not _is_route_clear_of_obstacle(
			navigation_target.global_position,
			body,
			clearance
		):
			return false
	return true

func is_target_physically_visible(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	for obstacle in get_tree().get_nodes_in_group("celestial"):
		if not obstacle is Node3D or obstacle == target:
			continue
		var body := obstacle as Node3D
		var physical_radius := _get_obstacle_radius(body) + 5.0
		if not _is_route_clear_of_obstacle(
			target.global_position,
			body,
			physical_radius
		):
			return false
	return true

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
	avoidance_waypoint = Vector3.ZERO
	avoidance_orbit_sign = 0.0
	avoidance_exit_index = -1
	avoidance_exits_visited = 0

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
			_hide_mining_beams()
			return

		var target_id := target_node.get_instance_id()
		if _mining_tractor_target_id != target_id:
			_mining_tractor_target_id = target_id
			_mining_tractor_lock_timer = 0.0
		var tractor_was_visible := _mining_tractor_laser != null and _mining_tractor_laser.visible
		if not tractor_was_visible:
			GlobalState.emit_chatter(
				"SYSTEM",
				"Tractor beam engaged. Stabilizing asteroid mass.",
				Color(0.0, 0.9, 0.9)
			)
			AudioManager.start_tractor_loop(global_position)

		# Position laser beam cylinder
		var ship_front = _get_mining_beam_origin(1)
		var tractor_origin = _get_mining_beam_origin(0)
		var asteroid_pos = target_node.global_position
		var tractor_pos = _get_tractor_target_point(target_node, tractor_origin)
		if target_node.has_method("get_mining_contact_point"):
			var contact := target_node.call("get_mining_contact_point", ship_front) as Vector3
			asteroid_pos = contact.lerp(target_node.global_position, 0.45)
		_set_beam_between(_mining_tractor_laser, tractor_origin, tractor_pos, MINING_TRACTOR_RADIUS)
		AudioManager.update_mining_audio_position(global_position)
		if target_node.has_method("hold_mining_tractor"):
			target_node.call("hold_mining_tractor", tractor_origin)
		current_speed = 0.0
		velocity = Vector3.ZERO
		var tractor_positioned := true
		if target_node.has_method("pull_to_mining_tractor_position"):
			var desired_position := _get_desired_mining_asteroid_position(target_node)
			tractor_positioned = bool(target_node.call(
				"pull_to_mining_tractor_position",
				desired_position,
				delta
			))
		var tractor_stable := true
		if target_node.has_method("is_mining_tractor_stable"):
			tractor_stable = bool(target_node.call("is_mining_tractor_stable"))
		if tractor_stable and tractor_positioned:
			_mining_tractor_lock_timer = minf(
				_mining_tractor_lock_timer + delta,
				MINING_TRACTOR_LOCK_SECONDS
			)
		else:
			_mining_tractor_lock_timer = 0.0
		var tractor_locked := _mining_tractor_lock_timer >= MINING_TRACTOR_LOCK_SECONDS

		if not tractor_locked:
			mining_laser.visible = false
			if _mine_particles:
				_mine_particles.emitting = false
			AudioManager.stop_mining_loop()
			return

		var mining_was_visible := mining_laser.visible
		_set_beam_between(mining_laser, ship_front, asteroid_pos, MINING_CUTTER_RADIUS)
		if not mining_was_visible:
			GlobalState.emit_chatter(
				"SYSTEM",
				"Asteroid held still. Mining laser commencing cut.",
				Color(0.0, 0.9, 0.9)
			)
			AudioManager.start_mining_loop(global_position)

		# Laser Pulse FX
		var pulse = 0.12 + sin(Time.get_ticks_msec() * 0.025) * 0.04
		mining_laser.scale.x = pulse
		mining_laser.scale.z = pulse

		if _mine_particles:
			_mine_particles.global_position = asteroid_pos
			_mine_particles.emitting = true

		_mining_target_pos = asteroid_pos
		if target_node.has_method("show_mining_heat_spot"):
			target_node.show_mining_heat_spot(ship_front)
		
		if fire_cooldown <= 0.0:
			fire_cooldown = GlobalState.mining_cooldown
			if GlobalState.has_max_bulwark_shield:
				fire_cooldown *= 1.05
				
			if target_node.has_method("mine"):
				target_node.mine()
				
			if GlobalState.has_max_rapid_mining:
				mining_cycles += 1
				if mining_cycles >= 10:
					GlobalState.remove_ore(1.0)
					mining_cycles = 0
	
	elif target_node.has_method("take_damage") and target_node.get("faction") != "player":
		_hide_mining_beams()
		# Player fires first — trigger turn-based combat if not already in one.
		if CombatManager.state == CombatManager.State.IDLE:
			CombatManager.start_combat(self, target_node)
		# Real-time fire is fully replaced by CombatManager — no direct projectile spawn.
	else:
		_hide_mining_beams()

func spawn_projectile(target_node: Node3D, visual_only: bool = false):
	if target_node == null or not is_instance_valid(target_node):
		return
	if GlobalState.has_max_heavy_weapon:
		engine_stall_timer = max(engine_stall_timer, 0.1)

	var proj_scene = load("res://scenes/projectile.tscn")
	if proj_scene:
		var p = proj_scene.instantiate()
		# Fire from a hardpoint (turret) if available, cycling through them.
		var origin := global_position
		if not hardpoints.is_empty():
			var hp := hardpoints[_hp_idx % hardpoints.size()]
			_hp_idx += 1
			if is_instance_valid(hp):
				origin = hp.global_position
		# Aim at the target so the cosmetic shot actually crosses the gap.
		p.direction = (target_node.global_position - origin).normalized()
		# In combat, damage is resolved by CombatManager — keep the shot cosmetic.
		p.damage = 0.0 if visual_only else GlobalState.weapon_damage
		p.faction = "player"
		p.color = Color.CYAN
		get_parent().add_child(p)
		p.global_position = origin + p.direction * 1.0


func launch_combat_drone(target_node: Node3D) -> void:
	if target_node == null or not is_instance_valid(target_node):
		return
	var parent := get_parent()
	if parent == null:
		return
	var target_pos: Vector3 = target_node.global_position + Vector3(0.0, 1.5, 0.0)
	var launch_dir: Vector3 = (target_pos - global_position).normalized()
	if launch_dir.length() <= 0.01:
		launch_dir = -global_transform.basis.z.normalized()
	var start_pos: Vector3 = global_position + launch_dir * 4.0 + global_transform.basis.x * 2.5 + Vector3(0.0, 1.4, 0.0)
	var travel_time: float = clampf(start_pos.distance_to(target_pos) / 95.0, 0.18, 0.75)

	var drone := Node3D.new()
	drone.name = "CombatDroneVisual"
	parent.add_child(drone)
	drone.global_position = start_pos
	drone.look_at(target_pos, Vector3.UP)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.15, 0.95, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.15, 0.95, 1.0)
	mat.emission_energy_multiplier = 7.0

	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.45
	body_mesh.height = 0.9
	body_mesh.material = mat

	var body := MeshInstance3D.new()
	body.name = "DroneCore"
	body.mesh = body_mesh
	drone.add_child(body)

	var streak_mesh := CylinderMesh.new()
	streak_mesh.top_radius = 0.08
	streak_mesh.bottom_radius = 0.28
	streak_mesh.height = 3.5
	streak_mesh.material = mat
	var streak := MeshInstance3D.new()
	streak.name = "DroneStreak"
	streak.mesh = streak_mesh
	streak.rotation_degrees.x = 90.0
	streak.position = Vector3(0.0, 0.0, 1.8)
	drone.add_child(streak)

	var light := OmniLight3D.new()
	light.name = "DroneStrikeLight"
	light.light_color = Color(0.15, 0.95, 1.0)
	light.light_energy = 6.0
	light.omni_range = 18.0
	drone.add_child(light)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(drone, "global_position", target_pos, travel_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(drone, "scale", Vector3(1.8, 1.8, 1.8), travel_time * 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(streak, "scale", Vector3(1.0, 1.0, 2.4), travel_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.finished.connect(func():
		if is_instance_valid(target_node):
			ImpactEffect.spawn_hit(parent, target_pos, Color(0.15, 0.95, 1.0))
		if is_instance_valid(drone):
			drone.queue_free()
	)

func double_click_move(click_pos: Vector3):
	cancel_autopilot()
	route_notice_sent = false
	route_notice_override = ""
	target_position = click_pos
	nav_mode = "MOVE_TO_POINT"
	var ui = GlobalState.get_ui_manager()
	if ui and ui.has_method("show_target_marker"):
		ui.show_target_marker(click_pos)

func die(death_source: String = ""):
	destroyed = true
	AudioManager.play_explosion(global_position)
	ImpactEffect.spawn_explosion(get_parent(), global_position, Color(0.15, 0.75, 1.0), 1.5)
	var game_root := get_tree().current_scene
	if game_root and game_root.has_method("record_player_death"):
		game_root.call("record_player_death", death_source)
	var ui = GlobalState.get_ui_manager()
	if ui and ui.has_method("show_death_screen"):
		ui.show_death_screen()
	queue_free()


func _create_mine_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "MineParticles"
	p.emitting = false
	p.amount = 18
	p.lifetime = 0.6
	p.explosiveness = 0.1
	p.fixed_fps = 30
	p.top_level = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3.ZERO
	proc.spread = 180.0
	proc.initial_velocity_min = 5.0
	proc.initial_velocity_max = 15.0
	proc.gravity = Vector3.ZERO
	proc.scale_min = 0.3
	proc.scale_max = 0.8
	proc.damping_min = 5.0
	proc.damping_max = 12.0

	var grad := Gradient.new()
	grad.set_color(0, Color(0.8, 0.7, 0.5, 1.0))
	grad.set_color(1, Color(0.5, 0.4, 0.3, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	proc.color_ramp = grad_tex

	p.process_material = proc

	var mesh := SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.3
	mesh.radial_segments = 4
	mesh.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.7, 0.5)
	mat.emission_energy_multiplier = 3.0
	mesh.material = mat
	p.draw_pass_1 = mesh

	add_child(p)
	return p


func _create_boost_effects() -> void:
	boost_effect_meshes.clear()
	boost_effect_lights.clear()
	exhaust_flames.clear()
	for socket in _generated_thruster_sockets:
		if is_instance_valid(socket):
			socket.queue_free()
	_generated_thruster_sockets.clear()
	if thruster_bank == null:
		thruster_bank = ThrusterBankType.new()
		thruster_bank.name = "ThrusterBank"
		add_child(thruster_bank)
	else:
		thruster_bank.clear()

	var thruster_points: Array[Node3D] = []
	_find_thruster_points(visual, thruster_points)
	if thruster_points.is_empty():
		_create_fallback_thruster_socket(Vector3(-1.4, -0.1, 4.7))
		_create_fallback_thruster_socket(Vector3(1.4, -0.1, 4.7))
		_find_thruster_points(self, thruster_points)
	else:
		thruster_points = _expand_player_thruster_sockets(thruster_points)
	thruster_bank.setup(thruster_points, Color(0.18, 0.72, 1.0), 1.0)
	_update_boost_effects(0.0)


func _find_thruster_points(node: Node, out: Array[Node3D]) -> void:
	var lower_name := str(node.name).to_lower()
	if node is Marker3D and (
			lower_name.begins_with("engine_")
			or lower_name.begins_with("thruster_")
			or lower_name.begins_with("exhaust_")
			or lower_name.begins_with("nozzle_")
	):
		out.append(node as Node3D)
	for child in node.get_children():
		_find_thruster_points(child, out)


func _create_fallback_thruster_socket(local_position: Vector3) -> void:
	var anchor := Marker3D.new()
	anchor.name = "FallbackThrusterSocket"
	anchor.position = local_position
	anchor.set_meta("thruster_radius", 0.55)
	add_child(anchor)
	_generated_thruster_sockets.append(anchor)


func _expand_player_thruster_sockets(base_points: Array[Node3D]) -> Array[Node3D]:
	if base_points.size() >= 10:
		for point in base_points:
			point.set_meta("thruster_radius", 0.42)
		return base_points
	if base_points.size() == 2:
		return _create_player_ten_thruster_bank(base_points)

	var expanded: Array[Node3D] = []
	var socket_offsets: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(-0.34, 0.18, 0.0),
		Vector3(0.34, 0.18, 0.0),
		Vector3(-0.26, -0.25, 0.0),
		Vector3(0.26, -0.25, 0.0),
	]
	for base in base_points:
		for i in range(socket_offsets.size()):
			var socket := Marker3D.new()
			socket.name = "ThrusterSocket_%s_%d" % [base.name, i]
			socket.position = socket_offsets[i]
			socket.set_meta("thruster_radius", 0.38 if i == 0 else 0.27)
			base.add_child(socket)
			_generated_thruster_sockets.append(socket)
			expanded.append(socket)
	return expanded


func _create_player_ten_thruster_bank(base_points: Array[Node3D]) -> Array[Node3D]:
	var parent := base_points[0].get_parent() as Node3D
	if parent == null:
		return base_points

	var left := parent.to_local(base_points[0].global_position)
	var right := parent.to_local(base_points[1].global_position)
	if left.x > right.x:
		var tmp := left
		left = right
		right = tmp

	var center := (left + right) * 0.5
	var half_span := maxf(abs(right.x - left.x) * 0.5, 0.45)
	var top_y := center.y + half_span * 0.34
	var bottom_y := center.y - half_span * 0.34
	var z := center.z + half_span * 0.04
	var specs: Array[Dictionary] = [
		{"x": -1.45, "y": top_y, "r": 0.32},
		{"x": -0.82, "y": top_y, "r": 0.29},
		{"x": -0.28, "y": top_y, "r": 0.30},
		{"x": 0.82, "y": top_y, "r": 0.29},
		{"x": 1.45, "y": top_y, "r": 0.32},
		{"x": -1.12, "y": bottom_y, "r": 0.36},
		{"x": -0.48, "y": bottom_y, "r": 0.42},
		{"x": 0.0, "y": bottom_y, "r": 0.44},
		{"x": 0.48, "y": bottom_y, "r": 0.42},
		{"x": 1.12, "y": bottom_y, "r": 0.36},
	]

	var sockets: Array[Node3D] = []
	for i in range(specs.size()):
		var spec := specs[i]
		var socket := Marker3D.new()
		socket.name = "PlayerThrusterSocket_%02d" % i
		socket.position = Vector3(
			center.x + half_span * float(spec["x"]),
			float(spec["y"]),
			z
		)
		socket.set_meta("thruster_radius", float(spec["r"]))
		parent.add_child(socket)
		_generated_thruster_sockets.append(socket)
		sockets.append(socket)
	return sockets


func _update_boost_effects(_delta: float) -> void:
	var active := boost_timer > 0.0
	var speed_limit: float = max_speed * GlobalState.engine_speed_mult
	if thruster_bank:
		thruster_bank.update_intensity(current_speed / maxf(speed_limit, 1.0), active)


func _create_drones():
	randomize()
	
	var orbit_radius = _drone_orbit_radius   # parametric: fits current ship size
	var sphere_radius = _drone_size          # parametric: scales with ship
	
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

	# Abort salvage run on any hit that actually connects (shields reduced or hull hit).
	if _salvage_active:
		_abort_salvage("hit")

	if health <= 0.0:
		die(attacker_faction)

func _update_drones(delta: float) -> void:
	var is_mining := mining_laser.visible

	# Mining just stopped — destroy old drones and spawn fresh ones from the hull
	if _was_mining and not is_mining:
		_respawn_drones()
	_was_mining = is_mining

	const DRONE_SPEED := 45.0

	for i in range(drones.size()):
		var pivot = drones[i]
		if not is_instance_valid(pivot):
			continue

		if is_mining:
			# Collecting behavior: one drone at a time flies to asteroid and back
			var mesh := pivot.get_child(0) as MeshInstance3D
			if not mesh:
				continue

			if _drone_collecting[i] or _drone_returning[i]:
				if not mesh.top_level:
					mesh.top_level = true
				var target := _mining_target_pos if _drone_collecting[i] else global_position
				var dist := _drone_collect_from[i].distance_to(target)
				var rate := DRONE_SPEED * delta / maxf(dist, 1.0)
				_drone_collect_t[i] = minf(_drone_collect_t[i] + rate, 1.0)
				var t := _drone_collect_t[i] * _drone_collect_t[i] * (3.0 - 2.0 * _drone_collect_t[i])
				mesh.global_position = _drone_collect_from[i].lerp(target, t)

				if _drone_collect_t[i] >= 1.0:
					if _drone_collecting[i]:
						_drone_collecting[i] = false
						_drone_returning[i] = true
						_drone_collect_from[i] = mesh.global_position
						_drone_collect_t[i] = 0.0
					else:
						_drone_returning[i] = false
						mesh.top_level = false
						mesh.position = Vector3(_drone_orbit_radius * (1.0 if i == 0 else -1.0), 0.0, 0.0)
						_drone_active_idx = 1 - i
			elif i == _drone_active_idx:
				var mesh_world_pos := mesh.global_position
				mesh.top_level = true
				mesh.global_position = mesh_world_pos
				_drone_collecting[i] = true
				_drone_collect_from[i] = mesh_world_pos
				_drone_collect_t[i] = 0.0
			else:
				# Non-active drone keeps orbiting
				var rot_speed = drone_rotations[i]
				pivot.rotate_x(rot_speed.x * delta)
				pivot.rotate_y(rot_speed.y * delta)
				pivot.rotate_z(rot_speed.z * delta)
		else:
			# Normal orbiting
			var rot_speed = drone_rotations[i]
			pivot.rotate_x(rot_speed.x * delta)
			pivot.rotate_y(rot_speed.y * delta)
			pivot.rotate_z(rot_speed.z * delta)


func _respawn_drones() -> void:
	for pivot in drones:
		if is_instance_valid(pivot):
			pivot.queue_free()
	drones.clear()
	drone_rotations.clear()
	_drone_collecting = [false, false]
	_drone_returning = [false, false]
	_drone_collect_t = [0.0, 0.0]
	_drone_active_idx = 0
	_create_drones()


func begin_salvage(wreck: Node3D, total_ore: float) -> void:
	if is_docked or _salvage_active or not is_instance_valid(wreck):
		return
	_salvage_active = true
	_salvage_target = wreck
	_salvage_ore_remaining = total_ore
	_salvage_rare_dropped = false
	# Pick whichever drone is currently orbiting (not mid-mining-trip) to be the salvage drone.
	_salvage_drone_idx = _drone_active_idx
	_salvage_going_out = false
	_salvage_collect_t = 1.0  # Force an immediate dispatch on the first _update_salvage tick.
	GlobalState.emit_chatter("Drone Bay", "Salvage drone deployed.", Color(0.4, 0.9, 0.6))


func _update_salvage(delta: float) -> void:
	if not _salvage_active:
		return

	if not is_instance_valid(_salvage_target):
		_abort_salvage("wreck_gone")
		return

	if global_position.distance_to(_salvage_target.global_position) >= MINING_RANGE:
		_abort_salvage("out_of_range")
		return

	if drones.is_empty():
		return

	var pivot = drones[_salvage_drone_idx]
	if not is_instance_valid(pivot):
		return
	var mesh := pivot.get_child(0) as MeshInstance3D
	if not mesh:
		return

	const DRONE_SPEED := 45.0

	if _salvage_going_out or _salvage_collect_t < 1.0:
		if not mesh.top_level:
			mesh.top_level = true
		var target_pos := _salvage_target.global_position if _salvage_going_out else global_position
		var dist := _salvage_collect_from.distance_to(target_pos)
		var rate := DRONE_SPEED * delta / maxf(dist, 1.0)
		_salvage_collect_t = minf(_salvage_collect_t + rate, 1.0)
		var t := _salvage_collect_t * _salvage_collect_t * (3.0 - 2.0 * _salvage_collect_t)
		mesh.global_position = _salvage_collect_from.lerp(target_pos, t)

		if _salvage_collect_t >= 1.0:
			if _salvage_going_out:
				# Reached wreck — turn around
				_salvage_going_out = false
				_salvage_collect_from = mesh.global_position
				_salvage_collect_t = 0.0
			else:
				# Returned to ship — grant ore and check for rare
				mesh.top_level = false
				mesh.position = Vector3(_drone_orbit_radius * (1.0 if _salvage_drone_idx == 0 else -1.0), 0.0, 0.0)
				_salvage_collect_t = 1.0
				_salvage_collect_from = Vector3.ZERO
				_salvage_going_out = false
				_salvage_collect_return()
	else:
		# Drone is orbiting — dispatch it
		var mesh_world_pos := mesh.global_position
		mesh.top_level = true
		mesh.global_position = mesh_world_pos
		_salvage_going_out = true
		_salvage_collect_from = mesh_world_pos
		_salvage_collect_t = 0.0


func _salvage_collect_return() -> void:
	var give := minf(SALVAGE_ORE_PER_RETURN, _salvage_ore_remaining)
	var added := GlobalState.add_ore(give)
	if added <= 0.0:
		_abort_salvage("hold_full")
		return

	_salvage_ore_remaining -= added

	if not _salvage_rare_dropped and randf() < SALVAGE_RARE_CHANCE_PER_RETURN:
		_salvage_rare_dropped = true
		_salvage_grant_wreck_bonus()

	if _salvage_ore_remaining <= 0.0:
		_end_salvage()


func _salvage_grant_wreck_bonus() -> void:
	# story_loot_plant: StoryManager can guarantee a specific item in the next wreck.
	var plant: Dictionary = GlobalState.story_loot_plant
	if not plant.is_empty():
		var item_id: String = str(plant.get("item_id", ""))
		if not item_id.is_empty() and GlobalState.inventory.add(item_id, 1, 10):
			GlobalState.emit_chatter("Drone Bay", "Recovered salvage: %s." % item_id.capitalize().replace("_", " "), Color(1.0, 0.85, 0.3))
		if bool(plant.get("consumed_on_pickup", true)):
			GlobalState.story_loot_plant = {}
		return

	var roll := randf()
	if roll < 0.30:
		# Credit pouch — 40–180 SC
		var credits := randi_range(40, 180)
		GlobalState.add_credits(credits)
		GlobalState.emit_chatter("Drone Bay", "Loose credits recovered: %d SC." % credits, Color(1.0, 0.85, 0.3))
	elif roll < 0.55:
		# Damaged transponder (common)
		if GlobalState.inventory.add("damaged_transponder", 1, 20):
			GlobalState.emit_chatter("Drone Bay", "Recovered salvage: Damaged Transponder.", Color(1.0, 0.85, 0.3))
	elif roll < 0.68:
		# Encrypted core (uncommon)
		if GlobalState.inventory.add("encrypted_core", 1, 5):
			GlobalState.emit_chatter("Drone Bay", "Recovered salvage: Encrypted Data Core.", Color(1.0, 0.85, 0.3))
	elif roll < 0.78:
		# Repair kit
		if GlobalState.inventory.add("repair_kit", 1, 10):
			GlobalState.emit_chatter("Drone Bay", "Recovered salvage: Emergency Repair Kit.", Color(1.0, 0.85, 0.3))
	elif roll < 0.87:
		# Shield cell
		if GlobalState.inventory.add("shield_cell", 1, 10):
			GlobalState.emit_chatter("Drone Bay", "Recovered salvage: Shield Cell.", Color(1.0, 0.85, 0.3))
	elif roll < 0.95:
		# Scanner probe
		if GlobalState.inventory.add("scanner_probe", 1, 5):
			GlobalState.emit_chatter("Drone Bay", "Recovered salvage: Scanner Probe.", Color(1.0, 0.85, 0.3))
	else:
		# Rare: data chip
		if GlobalState.inventory.add("data_chip", 1, 10):
			GlobalState.emit_chatter("Drone Bay", "Recovered salvage: Data Chip — intact.", Color(1.0, 0.85, 0.3))


func _abort_salvage(reason: String) -> void:
	var messages := {
		"hit":          "Salvage drone lost — you took damage!",
		"hold_full":    "Cargo hold full — drone recalled.",
		"out_of_range": "Moved out of range — drone lost.",
		"wreck_gone":   "Salvage target lost.",
	}
	GlobalState.emit_chatter("Drone Bay", messages.get(reason, "Salvage aborted."), Color(1.0, 0.5, 0.2))
	_salvage_active = false
	_salvage_target = null
	_salvage_ore_remaining = 0.0
	_salvage_rare_dropped = false
	_salvage_going_out = false
	_salvage_collect_t = 1.0
	_respawn_drones()


func _end_salvage() -> void:
	var wreck := _salvage_target
	_salvage_active = false
	_salvage_target = null
	_salvage_ore_remaining = 0.0
	_salvage_rare_dropped = false
	_salvage_going_out = false
	_salvage_collect_t = 1.0
	_respawn_drones()
	GlobalState.emit_chatter("Drone Bay", "Wreck stripped.", Color(0.4, 0.9, 0.6))
	if is_instance_valid(wreck):
		wreck.queue_free()


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
