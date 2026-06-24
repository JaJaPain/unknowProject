extends Node

const CombatActionType := preload("res://scripts/combat/CombatAction.gd")

enum State { IDLE, PLANNING, EXECUTING }

signal combat_started(enemy: Node)
signal planning_started(ap: int, max_ap: int, intent: Dictionary, taunts: Dictionary)
signal execution_started
signal combat_ended(player_won: bool)
signal ap_changed(current: int, max_ap: int)
signal action_queued(action: Dictionary)
signal action_dequeued

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

# Called by CombatPanel EXECUTE button.
func commit_turn() -> void:
	if state != State.PLANNING:
		return
	state = State.EXECUTING
	_lerp_timescale(1.0, 1.0, 200)
	emit_signal("execution_started")
	_run_player_actions()

# ── Execution ─────────────────────────────────────────────────────────────────
func _run_player_actions() -> void:
	for action in queued_actions:
		if not is_instance_valid(enemy_node) or not is_instance_valid(player_node):
			break
		_dispatch_action(action)

	queued_actions.clear()

	# Check if enemy died from player actions before NPC gets to act.
	if not is_instance_valid(enemy_node) or enemy_node.get("destroyed"):
		end_combat(true)
		return

	_execute_npc_intent()

func _dispatch_action(action: Dictionary) -> void:
	match action.get("type"):
		CombatActionType.Type.FIRE:          _exec_fire()
		CombatActionType.Type.BOOST:         _exec_boost(action.get("params", {}))
		CombatActionType.Type.SHIELD_REROUTE: _exec_shield_reroute(action.get("params", {}))
		CombatActionType.Type.ATTACK_DRONE:  _exec_attack_drone()
		CombatActionType.Type.MICRO_WARP:    _exec_micro_warp()
		CombatActionType.Type.REPAIR_KIT:    _exec_repair_kit()
		CombatActionType.Type.FLEE:          _exec_flee()

# ── Action handlers ───────────────────────────────────────────────────────────
func _exec_fire() -> void:
	if not is_instance_valid(enemy_node):
		return
	var dmg := _resolve_player_hit(_fire_damage * _fire_multiplier)
	AudioManager.play_laser(player_node.global_position)
	if player_node.has_method("spawn_projectile"):
		player_node.spawn_projectile(enemy_node)
	if enemy_node.has_method("take_damage"):
		enemy_node.take_damage(dmg, "player")
	GlobalState.emit_chatter("COMBAT", "You fire — %d damage." % int(dmg), Color(1.0, 0.55, 0.2))

func _exec_boost(params: Dictionary) -> void:
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
	var face_idx: int = params.get("face", CombatActionType.Face.FRONT)
	player_shield_face = face_idx as CombatActionType.Face

func _exec_attack_drone() -> void:
	if not is_instance_valid(enemy_node):
		return
	if player_node.has_method("launch_combat_drone"):
		player_node.launch_combat_drone(enemy_node)
	var drone_dmg := _resolve_player_hit(GlobalState.weapon_damage * 0.4)
	if enemy_node.has_method("take_damage"):
		enemy_node.take_damage(drone_dmg, "player")
	GlobalState.emit_chatter("COMBAT", "Drone hits for %d damage." % int(drone_dmg), Color(0.3, 0.9, 0.9))

func _exec_micro_warp() -> void:
	if micro_warp_cooldown > 0 or not is_instance_valid(enemy_node):
		return
	# Teleport player to enemy flank — visual snap, no physics.
	if is_instance_valid(player_node):
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
	# repair_kit heals 25hp normally (ConsumableEffects.gd) — combat use is half that.
	var heal_amount: float = 12.5
	if player_node.has_method("heal"):
		player_node.heal(heal_amount)
	elif player_node.has("health"):
		var max_hp: float = player_node.get("max_health") if player_node.get("max_health") != null else 100.0
		player_node.health = min(player_node.health + heal_amount, max_hp)
	GlobalState.emit_chatter("Drone Bay", "Repair kit deployed — hull patched.", Color(0.4, 0.9, 0.6))

func _exec_flee() -> void:
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
		_after_npc_turn()
		return

	var intent := current_intent
	var itype: String = intent.get("type", "fire")

	match itype:
		"fire", "hull_shot", "suppression":
			var npc_dmg := _resolve_npc_hit(intent.get("damage", 10.0), intent)
			if enemy_node.has_method("spawn_projectile"):
				enemy_node.spawn_projectile(player_node)
			if player_node.has_method("take_damage"):
				player_node.take_damage(npc_dmg, enemy_node.get("faction") if enemy_node.get("faction") else "enemy")
			GlobalState.emit_chatter("COMBAT", "Enemy hits you for %d damage." % int(npc_dmg), Color(1.0, 0.3, 0.3))
		"flank":
			range_band = CombatActionType.RangeBand.CLOSE
			intent["flanking"] = true
			var npc_dmg := _resolve_npc_hit(intent.get("damage", 8.0), intent)
			if enemy_node.has_method("spawn_projectile"):
				enemy_node.spawn_projectile(player_node)
			if player_node.has_method("take_damage"):
				player_node.take_damage(npc_dmg, enemy_node.get("faction") if enemy_node.get("faction") else "enemy")
			GlobalState.emit_chatter("COMBAT", "Flanking hit — %d damage." % int(npc_dmg), Color(1.0, 0.3, 0.3))
		"disable_engines":
			# Costs player 1 AP next turn (clamped in _restore_ap).
			ap_max = max(2, ap_max - 1)
			GlobalState.emit_chatter("SYSTEM", "Engine disruption — AP reduced by 1 next turn.", Color(1.0, 0.5, 0.2))
		"repair":
			var npc_hp: float = enemy_node.get("health") if enemy_node.get("health") else 0.0
			var npc_max: float = enemy_node.get("max_health") if enemy_node.get("max_health") else 50.0
			enemy_node.health = min(npc_hp + 8.0, npc_max)
		"broadcast":
			GlobalState.emit_chatter(enemy_node.get("faction") if enemy_node.get("faction") else "ENEMY",
				"Calling for reinforcements...", Color(1.0, 0.3, 0.3))
		"surrender", "panic":
			pass  # MiningHauler — does nothing this turn, handled by low-health flee

	_after_npc_turn()

func _after_npc_turn() -> void:
	# Check for deaths.
	var player_dead: bool = not is_instance_valid(player_node) or player_node.get("destroyed") == true
	var enemy_dead: bool  = not is_instance_valid(enemy_node)  or enemy_node.get("destroyed")  == true

	if player_dead:
		end_combat(false)
		return
	if enemy_dead:
		_play_kaelen_line("kaelen_kill_confirm")
		end_combat(true)
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
