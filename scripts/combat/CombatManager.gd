extends Node

const CombatActionType := preload("res://scripts/combat/CombatAction.gd")
const CombatDamageNumber := preload("res://scripts/visuals/CombatDamageNumber.gd")

# ── Combat SFX (loaded by key) ──────────────────────────────────────────────────
const _SFX_DIR := "res://assets/CombatWheel/soundfxs/"
const SFX := {
	"weapon_fire":      preload("res://assets/CombatWheel/soundfxs/weapon_fire.wav"),
	"drone_launch":     preload("res://assets/CombatWheel/soundfxs/drone_launch.wav"),
	"microwarp":        preload("res://assets/CombatWheel/soundfxs/microwarp.wav"),
	"engine_boost":     preload("res://assets/CombatWheel/soundfxs/engine_boost.wav"),
	"shield_reroute":   preload("res://assets/CombatWheel/soundfxs/shield_reroute.wav"),
	"repair_kit":       preload("res://assets/CombatWheel/soundfxs/repair_kit.wav"),
	"hull_impact":      preload("res://assets/CombatWheel/soundfxs/hull_impact.wav"),
	"shield_deflect":   preload("res://assets/CombatWheel/soundfxs/shield_deflect.wav"),
	"impact_thud":      preload("res://assets/CombatWheel/soundfxs/sub_bass_thud.wav"),
	"hit_critical":     preload("res://assets/CombatWheel/soundfxs/hit_critical.wav"),
	"enemy_charge":     preload("res://assets/CombatWheel/soundfxs/enemy_charge.wav"),
	"death_explosion":  preload("res://assets/CombatWheel/soundfxs/death_explosion.wav"),
	"slowmo_riser":     preload("res://assets/CombatWheel/soundfxs/slowmo_riser.wav"),
	"low_health_alarm": preload("res://assets/CombatWheel/soundfxs/low_health_alarm.wav"),
	"cam_whoosh":       preload("res://assets/CombatWheel/soundfxs/cam_whoosh.wav"),
	"combat_sting":     preload("res://assets/CombatWheel/soundfxs/combat_sting.wav"),
}

# Play a combat SFX by key. If world_pos given, plays positionally; else 2D/global.
func _sfx(key: String, world_pos: Variant = null, db: float = 0.0) -> void:
	var stream: AudioStream = SFX.get(key)
	if stream == null:
		return
	if world_pos is Vector3:
		AudioManager.play_sfx_3d(stream, world_pos, db)
	else:
		AudioManager.play_sfx(stream, db)

enum State { IDLE, PLANNING, EXECUTING }

signal combat_started(enemy: Node)
signal planning_started(ap: int, max_ap: int, intent: Dictionary, taunts: Dictionary)
signal execution_started
signal combat_ended(player_won: bool)
signal ap_changed(current: int, max_ap: int)
signal action_queued(action: Dictionary)
signal action_dequeued
# ── Cinematic beat signals (drive camera + impact juice) ────────────────────────
signal action_telegraphed(action_type: int, source: Node, target: Node)
signal action_impact(target: Node, world_pos: Vector3, damage: float, lethal: bool, blocked: bool, crit: bool)
signal combat_kill(victim: Node, world_pos: Vector3)

# ── State ─────────────────────────────────────────────────────────────────────
var state: State = State.IDLE
var player_node: Node  = null
var enemy_node:  Node  = null

# ── AP pool ───────────────────────────────────────────────────────────────────
var ap_current: int = 6
var ap_max:     int = 6

# ── Action queue ──────────────────────────────────────────────────────────────
var queued_actions: Array[Dictionary] = []

# ── Per-fight state ───────────────────────────────────────────────────────────
var range_band         = CombatActionType.RangeBand.MID
var player_shield_face = CombatActionType.Face.FRONT
var micro_warp_cooldown: int  = 0   # turns remaining
var repair_used_this_turn: bool = false
var player_is_flanking: bool  = false
var current_intent: Dictionary = {}
var taunts: Dictionary = {}
var _taunts_ready: bool = false

# ── Upgrade-derived combat stats (set at start_combat) ────────────────────────
var _fire_ap_cost:   int   = 2
var _fire_damage:    float = 0.0
var _fire_multiplier: float = 1.0
var _shield_absorption: float = 0.30
var _shield_dual_face:  bool  = false
var _engine_tier:    int   = 1
var _flee_base_chance: float = 0.50

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	if not _lerp_active:
		return
	var elapsed_ms: int = Time.get_ticks_msec() - _lerp_start
	var t: float = clampf(float(elapsed_ms) / float(_lerp_dur_ms), 0.0, 1.0)
	Engine.time_scale      = lerpf(_ts_from,    _ts_to,    t)
	AudioManager.set_music_pitch(lerpf(_pitch_from, _pitch_to, t))
	if t >= 1.0:
		_lerp_active = false

func _lerp_timescale(to_scale: float, to_pitch: float, duration_ms: int = 400) -> void:
	_ts_from    = Engine.time_scale
	_ts_to      = to_scale
	_pitch_from = AudioManager.bgm_player.pitch_scale if AudioManager.bgm_player else 1.0
	_pitch_to   = to_pitch
	_lerp_dur_ms = duration_ms
	_lerp_start  = Time.get_ticks_msec()
	_lerp_active = true

func start_combat(player: Node, enemy: Node) -> void:
	if state != State.IDLE:
		return
	# Set state immediately so physics-frame re-entry can't spawn duplicate requests
	# while the async taunt fetch is in flight.
	state = State.PLANNING
	player_node = player
	enemy_node  = enemy
	_taunts_ready = false
	taunts = {}
	_load_upgrade_stats()
	_reset_fight_state()

	# Fetch taunts async; _on_taunts_ready finishes setup when they arrive.
	var faction:   String = enemy.get("faction") if enemy.get("faction") else "unknown"
	var archetype: String = enemy.get("ship_role") if enemy.get("ship_role") else "Gunner"
	LLMInterface.request_combat_taunts(faction, archetype, _on_taunts_ready)

	emit_signal("combat_started", enemy)

func _on_taunts_ready(data: Dictionary) -> void:
	# Guard against stale callbacks from duplicate requests (race with early state set)
	if state == State.IDLE or _taunts_ready:
		return
	taunts = data
	_taunts_ready = true
	_begin_planning()

func end_combat(player_won: bool) -> void:
	state = State.IDLE
	_lerp_timescale(1.0, 1.0, 600)
	player_node = null
	enemy_node  = null
	queued_actions.clear()
	emit_signal("combat_ended", player_won)

func _reset_fight_state() -> void:
	queued_actions.clear()
	range_band = CombatActionType.RangeBand.MID
	player_shield_face = CombatActionType.Face.FRONT
	micro_warp_cooldown = 0
	repair_used_this_turn = false
	player_is_flanking = false
	current_intent = {}

# ── AP helpers ────────────────────────────────────────────────────────────────
func _load_upgrade_stats() -> void:
	var power_tier: int = GlobalState.current_upgrades.get("power", {}).get("tier", 1)
	ap_max = 4 + power_tier  # tier 1=5 … tier 5=9
	ap_current = ap_max

	_fire_damage     = GlobalState.weapon_damage
	_fire_ap_cost    = 1 if GlobalState.has_max_rapid_weapon else (3 if GlobalState.has_max_heavy_weapon else 2)
	_fire_multiplier = 2.0 if GlobalState.has_max_heavy_weapon else 1.0

	_shield_absorption = 0.50 if GlobalState.has_max_bulwark_shield else 0.30
	_shield_dual_face  = GlobalState.has_max_bulwark_shield

	_engine_tier      = GlobalState.current_upgrades.get("engine", {}).get("tier", 1)
	_flee_base_chance = 0.30 + (_engine_tier * 0.10)  # tier 1=40% … tier 5=80%

func _spend_ap(amount: int) -> void:
	ap_current = max(0, ap_current - amount)
	emit_signal("ap_changed", ap_current, ap_max)

func _restore_ap() -> void:
	ap_current = ap_max
	if micro_warp_cooldown > 0:
		micro_warp_cooldown -= 1
	emit_signal("ap_changed", ap_current, ap_max)

# ── Action queue ──────────────────────────────────────────────────────────────
func queue_action(type: CombatActionType.Type, params: Dictionary = {}) -> bool:
	if state != State.PLANNING:
		return false

	var cost: int = CombatActionType.AP_COST[type]

	# Special-case overrides
	if type == CombatActionType.Type.FIRE:
		cost = _fire_ap_cost
	if type == CombatActionType.Type.REPAIR_KIT and repair_used_this_turn:
		return false
	if type == CombatActionType.Type.MICRO_WARP and micro_warp_cooldown > 0:
		return false

	if ap_current < cost:
		return false

	_spend_ap(cost)
	var action := CombatActionType.make(type, params)
	action["ap"] = cost  # reflect override cost
	queued_actions.append(action)
	if type == CombatActionType.Type.REPAIR_KIT:
		repair_used_this_turn = true
	emit_signal("action_queued", action)
	return true

func dequeue_last() -> void:
	if queued_actions.is_empty() or state != State.PLANNING:
		return
	var last: Dictionary = queued_actions.pop_back()
	var refund: int = last.get("ap", 0)
	if last.get("type") == CombatActionType.Type.REPAIR_KIT:
		repair_used_this_turn = false
	ap_current = min(ap_current + refund, ap_max)
	emit_signal("ap_changed", ap_current, ap_max)
	emit_signal("action_dequeued")

# ── Planning phase ────────────────────────────────────────────────────────────
const PLANNING_TIME_SCALE  := 0.15
const PLANNING_MUSIC_PITCH := 0.78

# Real-time lerp state (uses wall-clock ms so time_scale doesn't affect it).
var _ts_from:     float = 1.0
var _ts_to:       float = 1.0
var _pitch_from:  float = 1.0
var _pitch_to:    float = 1.0
var _lerp_dur_ms: int   = 400   # milliseconds
var _lerp_start:  int   = 0
var _lerp_active: bool  = false

func _begin_planning() -> void:
	if not is_instance_valid(enemy_node) or not is_instance_valid(player_node):
		end_combat(false)
		return
	state = State.PLANNING
	_restore_ap()
	repair_used_this_turn = false
	player_is_flanking = false

	_lerp_timescale(PLANNING_TIME_SCALE, PLANNING_MUSIC_PITCH, 500)

	current_intent = enemy_node.generate_intent() if enemy_node.has_method("generate_intent") else {}

	emit_signal("planning_started", ap_current, ap_max, current_intent, taunts)

# ── Cinematic sequencer timing (wall-clock seconds) ─────────────────────────────
const BEAT_TELEGRAPH    := 0.45   # after telegraph, before the action fires
const BEAT_POST_ACTION  := 0.35   # after an action resolves, before the next
const BEAT_TURN_GAP     := 0.55   # between player turn and NPC turn
const PROJECTILE_SPEED  := 85.0   # matches Projectile.gd
const TRAVEL_MIN        := 0.12
const TRAVEL_MAX        := 0.60

# Damage-dealing action types (camera frames the enemy; others frame self).
const _ATTACK_TYPES := [CombatActionType.Type.FIRE, CombatActionType.Type.ATTACK_DRONE]

# Wall-clock pause that survives Engine.time_scale slow-mo / hit-stop.
func _beat(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

# Pause for a projectile to cross the gap between two ships.
func _await_travel(from: Node, to: Node) -> void:
	var d := 0.0
	if is_instance_valid(from) and is_instance_valid(to):
		d = (from as Node3D).global_position.distance_to((to as Node3D).global_position)
	await _beat(clampf(d / PROJECTILE_SPEED, TRAVEL_MIN, TRAVEL_MAX))

# Apply damage at projectile-arrival time and emit the impact beat.
func _apply_hit(target: Node, attacker_faction: String, dmg: float, crit: bool, blocked: bool) -> void:
	if not is_instance_valid(target):
		return
	var hit_pos: Vector3 = (target as Node3D).global_position
	if target.has_method("take_damage"):
		target.take_damage(dmg, attacker_faction)
	var lethal := (not is_instance_valid(target)) or (target.get("destroyed") == true)
	if not lethal and is_instance_valid(target):
		var hp = target.get("health")
		if hp != null and float(hp) <= 0.0:
			lethal = true
	# Impact SFX: shield deflect vs hull hit, plus sub-bass thud and a crit layer.
	if blocked:
		_sfx("shield_deflect", hit_pos)
	else:
		_sfx("hull_impact", hit_pos)
		_sfx("impact_thud", hit_pos, -3.0)
	if crit:
		_sfx("hit_critical", hit_pos)
	_spawn_damage_number(target, hit_pos, dmg, blocked, crit)
	emit_signal("action_impact", target, hit_pos, dmg, lethal, blocked, crit)
	# Hit-stop freeze-frame (skip on lethal — the kill cinematic handles that).
	if not lethal:
		_hit_stop(0.07 + (0.05 if crit else 0.0))

# Floating 3D damage number at the hit point. Crit = big + gold, blocked =
# small + cyan "BLOCKED", normal = orange.
func _spawn_damage_number(target: Node, hit_pos: Vector3, dmg: float, blocked: bool, crit: bool) -> void:
	var parent: Node = null
	if is_instance_valid(target):
		parent = target.get_parent()
	if parent == null and is_instance_valid(player_node):
		parent = player_node.get_parent()
	if parent == null:
		return
	var text: String
	var color: Color
	if blocked:
		text = "BLOCKED %d" % int(dmg)
		color = Color(0.45, 0.85, 1.0)
	elif crit:
		text = "%d!" % int(dmg)
		color = Color(1.0, 0.85, 0.2)
	else:
		text = "%d" % int(dmg)
		color = Color(1.0, 0.55, 0.2)
	CombatDamageNumber.spawn(parent, hit_pos, text, color, crit)

# Brief freeze-frame on impact. Fire-and-forget; wall-clock restore so the
# sequencer's own beats (also wall-clock) keep running underneath.
func _hit_stop(freeze_sec: float) -> void:
	_lerp_active = false
	Engine.time_scale = 0.02
	await get_tree().create_timer(freeze_sec, true, false, true).timeout
	if state == State.EXECUTING:
		Engine.time_scale = 1.0

# Emit the kill beat then end combat (Phase 5 expands this with the cinematic).
func _kill_and_end(victim: Node, player_won: bool) -> void:
	var pos := Vector3.ZERO
	if is_instance_valid(victim):
		pos = (victim as Node3D).global_position
	emit_signal("combat_kill", victim, pos)
	if player_won:
		_play_kaelen_line("kaelen_kill_confirm")
	end_combat(player_won)

# Called by CombatPanel EXECUTE button.
func commit_turn() -> void:
	if state != State.PLANNING:
		return
	state = State.EXECUTING
	_lerp_timescale(1.0, 1.0, 200)
	emit_signal("execution_started")
	_run_turn_sequence()   # fire-and-forget coroutine

# ── Execution sequence (async) ──────────────────────────────────────────────────
func _run_turn_sequence() -> void:
	await _run_player_actions()
	if state == State.IDLE:
		return   # combat ended mid-player-turn (flee / kill)
	# Enemy died from player actions before NPC gets to act.
	if not is_instance_valid(enemy_node) or enemy_node.get("destroyed"):
		_kill_and_end(enemy_node, true)
		return
	await _beat(BEAT_TURN_GAP)
	if state == State.IDLE:
		return
	await _execute_npc_intent()
	if state == State.IDLE:
		return
	_after_npc_turn()

func _run_player_actions() -> void:
	for action in queued_actions:
		if not is_instance_valid(enemy_node) or not is_instance_valid(player_node):
			break
		await _dispatch_action(action)
		if state == State.IDLE:
			break
		if not is_instance_valid(enemy_node) or enemy_node.get("destroyed"):
			break
	queued_actions.clear()

func _dispatch_action(action: Dictionary) -> void:
	var t = action.get("type")
	var target: Node = enemy_node if t in _ATTACK_TYPES else player_node
	emit_signal("action_telegraphed", t, player_node, target)
	await _beat(BEAT_TELEGRAPH)
	if state == State.IDLE:
		return
	match t:
		CombatActionType.Type.FIRE:           await _exec_fire()
		CombatActionType.Type.BOOST:          _exec_boost(action.get("params", {}))
		CombatActionType.Type.SHIELD_REROUTE: _exec_shield_reroute(action.get("params", {}))
		CombatActionType.Type.ATTACK_DRONE:   await _exec_attack_drone()
		CombatActionType.Type.MICRO_WARP:     _exec_micro_warp()
		CombatActionType.Type.REPAIR_KIT:     _exec_repair_kit()
		CombatActionType.Type.FLEE:           _exec_flee()
	await _beat(BEAT_POST_ACTION)

# ── Action handlers ───────────────────────────────────────────────────────────
func _exec_fire() -> void:
	if not is_instance_valid(enemy_node):
		return
	var dmg := _resolve_player_hit(_fire_damage * _fire_multiplier)
	_sfx("weapon_fire", player_node.global_position)
	AudioManager.play_laser(player_node.global_position)
	if player_node.has_method("spawn_projectile"):
		player_node.spawn_projectile(enemy_node)
	await _await_travel(player_node, enemy_node)
	_apply_hit(enemy_node, "player", dmg, player_is_flanking, false)
	GlobalState.emit_chatter("COMBAT", "You fire — %d damage." % int(dmg), Color(1.0, 0.55, 0.2))

func _exec_boost(params: Dictionary) -> void:
	if is_instance_valid(player_node):
		_sfx("engine_boost", player_node.global_position)
	var dir: String = params.get("direction", "closer")
	if dir == "closer":
		if range_band == CombatActionType.RangeBand.LONG:
			range_band = CombatActionType.RangeBand.MID
		elif range_band == CombatActionType.RangeBand.MID:
			range_band = CombatActionType.RangeBand.CLOSE
	else:
		if range_band == CombatActionType.RangeBand.CLOSE:
			range_band = CombatActionType.RangeBand.MID
		elif range_band == CombatActionType.RangeBand.MID:
			range_band = CombatActionType.RangeBand.LONG

func _exec_shield_reroute(params: Dictionary) -> void:
	if is_instance_valid(player_node):
		_sfx("shield_reroute", player_node.global_position)
	var face_idx: int = params.get("face", CombatActionType.Face.FRONT)
	player_shield_face = face_idx as CombatActionType.Face

func _exec_attack_drone() -> void:
	if not is_instance_valid(enemy_node):
		return
	if player_node.has_method("launch_combat_drone"):
		player_node.launch_combat_drone(enemy_node)
	_sfx("drone_launch", player_node.global_position)
	var drone_dmg := _resolve_player_hit(GlobalState.weapon_damage * 0.4)
	await _await_travel(player_node, enemy_node)
	_apply_hit(enemy_node, "player", drone_dmg, player_is_flanking, false)
	GlobalState.emit_chatter("COMBAT", "Drone hits for %d damage." % int(drone_dmg), Color(0.3, 0.9, 0.9))

func _exec_micro_warp() -> void:
	if micro_warp_cooldown > 0 or not is_instance_valid(enemy_node):
		return
	# Teleport player to enemy flank — visual snap, no physics.
	if is_instance_valid(player_node):
		_sfx("microwarp", player_node.global_position)
		var enemy3d := enemy_node as Node3D
		if enemy3d:
			var flank_offset: Vector3 = enemy3d.global_transform.basis.x * 18.0
			player_node.global_position = enemy3d.global_position + flank_offset
	player_is_flanking = true
	micro_warp_cooldown = 3
	range_band = CombatActionType.RangeBand.CLOSE

func _exec_repair_kit() -> void:
	if not is_instance_valid(player_node):
		return
	if not GlobalState.inventory.has_item("repair_kit"):
		return
	GlobalState.inventory.remove("repair_kit", 1)
	_sfx("repair_kit", player_node.global_position)
	# repair_kit heals 25hp normally (ConsumableEffects.gd) — combat use is half that.
	var heal_amount: float = 12.5
	if player_node.has_method("heal"):
		player_node.heal(heal_amount)
	elif player_node.has("health"):
		var max_hp: float = player_node.get("max_health") if player_node.get("max_health") != null else 100.0
		player_node.health = min(player_node.health + heal_amount, max_hp)
	GlobalState.emit_chatter("Drone Bay", "Repair kit deployed — hull patched.", Color(0.4, 0.9, 0.6))

func _exec_flee() -> void:
	if is_instance_valid(player_node):
		_sfx("engine_boost", player_node.global_position)
	if not is_instance_valid(enemy_node):
		end_combat(false)
		return
	var archetype: String = enemy_node.get("ship_role") if enemy_node.get("ship_role") else ""
	var penalty := 0.20 if archetype == "Interceptor" else 0.0
	penalty += 0.15 if range_band == CombatActionType.RangeBand.CLOSE else 0.0
	var chance := clampf(_flee_base_chance - penalty, 0.05, 0.95)
	if randf() <= chance:
		_play_npc_taunt("npc_player_fled_success")
		_play_kaelen_line("kaelen_player_fled")
		end_combat(false)
	else:
		_play_npc_taunt("npc_player_fled_fail")
		GlobalState.emit_chatter("SYSTEM", "Escape failed — engines couldn't break their tractor lock.", Color(1.0, 0.4, 0.2))

# ── Hit resolution ────────────────────────────────────────────────────────────
func _resolve_player_hit(base_dmg: float) -> float:
	var dmg: float = base_dmg * float(CombatActionType.RANGE_DAMAGE_MULT[range_band])
	if player_is_flanking:
		dmg *= 1.25
	return dmg

func _resolve_npc_hit(base_dmg: float, intent: Dictionary) -> float:
	var dmg: float = base_dmg * float(CombatActionType.RANGE_DAMAGE_MULT[range_band])
	var attack_face_raw = intent.get("face")
	var attack_face: int = attack_face_raw if attack_face_raw != null else CombatActionType.Face.FRONT
	var flanking_raw = intent.get("flanking")
	var is_flanking: bool = flanking_raw if flanking_raw != null else false

	# Flanking bypasses front shield entirely.
	if is_flanking and int(player_shield_face) == CombatActionType.Face.FRONT:
		return dmg

	# Check if player's shield face matches the attack direction.
	var shields_up: bool = (attack_face == int(player_shield_face))
	if not shields_up and _shield_dual_face:
		# Bulwark Mk V blocks the adjacent face too.
		var adjacent: int = _adjacent_face(int(player_shield_face))
		shields_up = (attack_face == adjacent)

	if shields_up and GlobalState.shield_capacity > 0.0:
		dmg *= (1.0 - _shield_absorption)

	return dmg

func _adjacent_face(face: int) -> int:
	if face == CombatActionType.Face.FRONT:     return CombatActionType.Face.PORT
	if face == CombatActionType.Face.PORT:      return CombatActionType.Face.REAR
	if face == CombatActionType.Face.REAR:      return CombatActionType.Face.STARBOARD
	if face == CombatActionType.Face.STARBOARD: return CombatActionType.Face.FRONT
	return CombatActionType.Face.FRONT

# ── NPC execution ─────────────────────────────────────────────────────────────
func _execute_npc_intent() -> void:
	if not is_instance_valid(enemy_node) or not is_instance_valid(player_node):
		return

	var intent := current_intent
	var itype: String = intent.get("type", "fire")
	var npc_faction: String = enemy_node.get("faction") if enemy_node.get("faction") else "enemy"

	# Telegraph the NPC action (camera frames the enemy ship).
	emit_signal("action_telegraphed", -1, enemy_node, player_node)
	await _beat(BEAT_TELEGRAPH)
	if state == State.IDLE or not is_instance_valid(enemy_node) or not is_instance_valid(player_node):
		return

	match itype:
		"fire", "hull_shot", "suppression":
			var npc_dmg := _resolve_npc_hit(intent.get("damage", 10.0), intent)
			var blocked := _npc_hit_blocked(intent)
			_sfx("weapon_fire", enemy_node.global_position)
			AudioManager.play_laser(enemy_node.global_position)
			if enemy_node.has_method("spawn_projectile"):
				enemy_node.spawn_projectile(player_node)
			await _await_travel(enemy_node, player_node)
			_apply_hit(player_node, npc_faction, npc_dmg, false, blocked)
			GlobalState.emit_chatter("COMBAT", "Enemy hits you for %d damage." % int(npc_dmg), Color(1.0, 0.3, 0.3))
		"flank":
			range_band = CombatActionType.RangeBand.CLOSE
			intent["flanking"] = true
			var npc_dmg := _resolve_npc_hit(intent.get("damage", 8.0), intent)
			var blocked := _npc_hit_blocked(intent)
			_sfx("weapon_fire", enemy_node.global_position)
			AudioManager.play_laser(enemy_node.global_position)
			if enemy_node.has_method("spawn_projectile"):
				enemy_node.spawn_projectile(player_node)
			await _await_travel(enemy_node, player_node)
			_apply_hit(player_node, npc_faction, npc_dmg, true, blocked)
			GlobalState.emit_chatter("COMBAT", "Flanking hit — %d damage." % int(npc_dmg), Color(1.0, 0.3, 0.3))
		"disable_engines":
			# Costs player 1 AP next turn (clamped in _restore_ap).
			ap_max = max(2, ap_max - 1)
			_sfx("enemy_charge", enemy_node.global_position)
			GlobalState.emit_chatter("SYSTEM", "Engine disruption — AP reduced by 1 next turn.", Color(1.0, 0.5, 0.2))
		"repair":
			var npc_hp: float = enemy_node.get("health") if enemy_node.get("health") else 0.0
			var npc_max: float = enemy_node.get("max_health") if enemy_node.get("max_health") else 50.0
			enemy_node.health = min(npc_hp + 8.0, npc_max)
			_sfx("repair_kit", enemy_node.global_position)
		"broadcast":
			GlobalState.emit_chatter(npc_faction.to_upper(),
				"Calling for reinforcements...", Color(1.0, 0.3, 0.3))
		"surrender", "panic":
			pass  # MiningHauler — does nothing this turn, handled by low-health flee

# True when the player's current shield facing would absorb this NPC attack.
func _npc_hit_blocked(intent: Dictionary) -> bool:
	var attack_face_raw = intent.get("face")
	var attack_face: int = attack_face_raw if attack_face_raw != null else CombatActionType.Face.FRONT
	var flanking_raw = intent.get("flanking")
	var is_flanking: bool = flanking_raw if flanking_raw != null else false
	if is_flanking and int(player_shield_face) == CombatActionType.Face.FRONT:
		return false
	if GlobalState.shield_capacity <= 0.0:
		return false
	if attack_face == int(player_shield_face):
		return true
	if _shield_dual_face and attack_face == _adjacent_face(int(player_shield_face)):
		return true
	return false

func _after_npc_turn() -> void:
	# Check for deaths.
	var player_dead: bool = not is_instance_valid(player_node) or player_node.get("destroyed") == true
	var enemy_dead: bool  = not is_instance_valid(enemy_node)  or enemy_node.get("destroyed")  == true

	if player_dead:
		_kill_and_end(player_node, false)
		return
	if enemy_dead:
		_kill_and_end(enemy_node, true)
		return

	# Low-health taunts (fire once).
	var player_hp:  float = float(player_node.get("health"))     if player_node.get("health")     != null else 100.0
	var player_max: float = float(player_node.get("max_health")) if player_node.get("max_health") != null else 100.0
	var enemy_hp:   float = float(enemy_node.get("health"))      if enemy_node.get("health")      != null else 50.0
	var enemy_max:  float = float(enemy_node.get("max_health"))  if enemy_node.get("max_health")  != null else 50.0

	if player_hp / player_max <= 0.30:
		_play_npc_taunt("player_low_health")
		_play_kaelen_line("kaelen_player_low_health")
	if enemy_hp / enemy_max <= 0.30:
		_play_npc_taunt("npc_low_health")
		_play_kaelen_line("kaelen_winning")

	_begin_planning()

# ── Taunt / voice helpers ─────────────────────────────────────────────────────
func _play_npc_taunt(key: String) -> void:
	var taunts_on = GlobalState.get("combat_voice_taunts")
	if taunts_on != null and not taunts_on:
		return
	var line: String = taunts.get(key, "")
	if line.is_empty():
		return
	var faction: String = enemy_node.get("faction") if is_instance_valid(enemy_node) and enemy_node.get("faction") else "ENEMY"
	GlobalState.emit_chatter(faction.to_upper(), line, Color(1.0, 0.4, 0.3))

func _play_kaelen_line(key: String) -> void:
	var taunts_on = GlobalState.get("combat_voice_taunts")
	if taunts_on != null and not taunts_on:
		return
	var line: String = taunts.get(key, "")
	if line.is_empty():
		return
	GlobalState.emit_chatter("Kaelen", line, Color(0.6, 0.9, 1.0))

func play_player_reply() -> void:
	_play_kaelen_line("kaelen_open")
