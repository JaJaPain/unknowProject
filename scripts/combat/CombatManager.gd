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
signal planning_started(ap: int, max_ap: int, intent: Dictionary, taunts: Dictionary, npc_plan: Array)
signal execution_started
signal combat_ended(player_won: bool)
signal ap_changed(current: int, max_ap: int)
signal action_queued(action: Dictionary)
signal action_dequeued
signal enemy_status_changed(brace: bool, shield: bool)
signal combat_loot_dropped(loot: Dictionary)
signal boss_phase_changed(phase: int)
# ── Cinematic beat signals (drive camera + impact juice) ────────────────────────
signal action_telegraphed(action_type: int, source: Node, target: Node)
signal action_impact(target: Node, world_pos: Vector3, damage: float, lethal: bool, blocked: bool, crit: bool)
signal combat_kill(victim: Node, world_pos: Vector3)

# ── State ─────────────────────────────────────────────────────────────────────
var state: State = State.IDLE
var player_node: Node  = null
# Multi-enemy support: all enemies in the current fight.
# enemy_node property getter keeps all existing code working unchanged.
var enemy_nodes: Array = []
var _target_idx: int   = 0
var enemy_node: Node:
	get:
		if _target_idx < enemy_nodes.size():
			var _e = enemy_nodes[_target_idx]
			return _e if is_instance_valid(_e) else null
		return null

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
var current_intent: Dictionary = {}       # kept for telegraph UI (first action label)
var npc_action_plan: Array = []  # single-enemy plan — kept for backwards compat reads
var npc_action_plans: Array = [] # per-enemy plans (S3 multi-plan)
var taunts: Dictionary = {}
var _taunts_ready: bool = false
# Shield Reroute new mechanic: auto-faces enemy, blocks first hit 65%.
# Bypassed if enemy repositions before firing.
var player_shield_reroute_active: bool = false
var _shield_dome: MeshInstance3D = null
# Enemy defensive states — per-enemy arrays; property getters target _target_idx.
var _enemy_brace:  Array = []   # bool per enemy
var _enemy_shield: Array = []   # bool per enemy
var enemy_brace_active: bool:
	get: return _enemy_brace[_target_idx]  if _target_idx < _enemy_brace.size()  else false
	set(v):
		if _target_idx < _enemy_brace.size():
			_enemy_brace[_target_idx] = v
var enemy_shield_angle_active: bool:
	get: return _enemy_shield[_target_idx] if _target_idx < _enemy_shield.size() else false
	set(v):
		if _target_idx < _enemy_shield.size():
			_enemy_shield[_target_idx] = v
var _enemy_shield_dome: MeshInstance3D = null
# Kaelen hint flags — fire once per fight.
var _told_brace_hint: bool = false
var _told_shield_angle_hint: bool = false
# Low-health alarm fires once per side per fight.
var _player_low_alarmed: bool = false
var _enemy_low_alarmed: bool = false
# Boss phase-transition guards — prevent double-fire if a single hit crosses a threshold.
var _boss_phase_alarmed_2: bool = false
var _boss_phase_alarmed_3: bool = false
# Planning-phase counter, drives opening + between-round enemy jabs.
var _turn_number: int = 0
# Position of the last lethal hit — the victim may be freed before the kill beat.
var _last_kill_pos: Vector3 = Vector3.ZERO

# ── Upgrade-derived combat stats (set at start_combat) ────────────────────────
var _fire_ap_cost:   int   = 2
var _fire_damage:    float = 0.0
var _fire_multiplier: float = 1.0
var _shield_absorption: float = 0.30
var _shield_dual_face:  bool  = false
var _engine_tier:    int   = 1
var _flee_base_chance: float = 0.50

# ── Angry combat taunts (cached at startup, one per attacking ship) ─────────────
const TAUNT_SPEED := 1.18
const TAUNT_STYLE := 1.4
# Lead voices, each blended 70/30 with am_michael for an angry-but-varied read.
const TAUNT_LEAD_VOICES := [
	"am_onyx", "am_adam", "am_fenrir", "am_liam", "bm_george", "am_puck", "am_eric", "am_echo",
]
# Player struck first — the NPC is enraged at an unprovoked attack.
const TAUNT_RAGE_LINES := [
	"You fired on me? You're dead, you absolute idiot.",
	"Big mistake, scrap-rat. I'll tear you apart.",
	"Unprovoked? You've got a death wish.",
	"You'll regret pulling that trigger, moron.",
	"Wrong move. Now I'm angry.",
	"You shot first? Then I'll shoot last.",
]
# NPC struck first — they came for the player (generic motive for v1; see
# the REVISIT task for splitting this into reason buckets later).
const TAUNT_REASON_LINES := [
	"End of the line, scrap-rat. Nothing personal.",
	"You're worth more dead. Hold still.",
	"Wrong sector, wrong day. Eat plasma.",
	"Orders are orders. You lose.",
	"Should've stayed home, idiot.",
	"This is what you get for flying through here.",
]
# Comedic insults — occasionally fired instead of a straight taunt, regardless
# of who started it. Same angry delivery; the contrast is the joke.
const TAUNT_HUMOR_CHANCE := 0.22
const TAUNT_HUMOR_LINES := [
	"Hey, wait a minute! Your mom swore she wasn't married. Not my fault!",
	"Did your mother teach you to fly, or did she give up too?",
	"I'd insult your ship, but it already looks embarrassed.",
	"Was that an attack, or did your cat sit on the controls?",
	"Your mama's so dense, light bends around her cargo hold.",
	"I've seen escape pods with more fight in them than you.",
]
var _player_initiated: bool = false
# When the one-time combat tutorial popup is up, hold the opening enemy taunt so
# it doesn't talk over N.O.V.A.'s tutorial line. UIManager sets/clears the hold
# around the popup; a taunt that tries to fire while held is queued and flushed
# on release. (Only ever engages on the very first fight — the tutorial is once.)
var _opening_taunt_held: bool = false
var _opening_taunt_pending: bool = false
var _cached_rage:   Array = []   # [{text, voice}, ...] pre-cached audio pairs
var _cached_reason: Array = []
var _cached_humor:  Array = []
const _TAUNT_CACHE_PATH := "user://cached_taunts.json"
var _general_taunt_fetch_in_flight: bool = false

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_and_cache_taunts()
	_load_persisted_taunts()
	_request_general_taunt_pool()

# Build the two taunt pools, each line paired with a random angry blend, and
# pre-cache the audio so combat playback is instant (queues if TTS isn't up yet).
func _build_and_cache_taunts() -> void:
	_cached_rage   = _make_taunt_pool(TAUNT_RAGE_LINES)
	_cached_reason = _make_taunt_pool(TAUNT_REASON_LINES)
	_cached_humor  = _make_taunt_pool(TAUNT_HUMOR_LINES)

# Load lines saved from the previous session immediately — instant pool boost.
func _load_persisted_taunts() -> void:
	if not FileAccess.file_exists(_TAUNT_CACHE_PATH):
		return
	var f := FileAccess.open(_TAUNT_CACHE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		return
	for cat in ["rage", "reason", "humor"]:
		if parsed.has(cat) and parsed[cat] is Array:
			var target: Array = _cached_rage if cat == "rage" \
				else (_cached_reason if cat == "reason" else _cached_humor)
			for line in parsed[cat]:
				var s := str(line).strip_edges()
				if s.length() > 4 and not _pool_has_line(target, s):
					target.append(_make_taunt_entry(s))
	print("[CombatManager] Loaded %d persisted taunt lines." % (
		_cached_rage.size() + _cached_reason.size() + _cached_humor.size()))

# Fire an async Ollama request for generic taunts. Safe to call multiple times —
# skips if a fetch is already in flight.
func _request_general_taunt_pool() -> void:
	if _general_taunt_fetch_in_flight:
		return
	_general_taunt_fetch_in_flight = true
	LLMInterface.request_general_taunts(_on_general_taunts_ready)

func _on_general_taunts_ready(data: Dictionary) -> void:
	_general_taunt_fetch_in_flight = false
	if data.is_empty():
		return
	var added := 0
	var cat_map := {"rage": _cached_rage, "reason": _cached_reason, "humor": _cached_humor}
	for cat in cat_map.keys():
		if not data.has(cat):
			continue
		for line in data[cat]:
			var s := str(line).strip_edges()
			if s.length() > 4 and not _pool_has_line(cat_map[cat], s):
				cat_map[cat].append(_make_taunt_entry(s))
				TTSInterface.cache_dialogue_audio(s, _make_taunt_entry(s)["voice"],
					TAUNT_SPEED, TAUNT_STYLE)
				added += 1
	if added > 0:
		print("[CombatManager] +%d fresh general taunt lines cached." % added)
		_save_taunt_pool()

func _save_taunt_pool() -> void:
	var out := {"rage": [], "reason": [], "humor": []}
	for entry in _cached_rage:   out["rage"].append(entry["text"])
	for entry in _cached_reason: out["reason"].append(entry["text"])
	for entry in _cached_humor:  out["humor"].append(entry["text"])
	var f := FileAccess.open(_TAUNT_CACHE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(out, "\t"))
	f.close()

func _make_taunt_entry(line: String) -> Dictionary:
	var lead: String = TAUNT_LEAD_VOICES[randi() % TAUNT_LEAD_VOICES.size()]
	return {"text": line, "voice": "%s[0.7]+am_michael[0.3]" % lead}

func _pool_has_line(pool: Array, line: String) -> bool:
	for entry in pool:
		if entry is Dictionary and entry.get("text", "") == line:
			return true
	return false

func _make_taunt_pool(lines: Array) -> Array:
	var pool: Array = []
	for line in lines:
		var entry := _make_taunt_entry(line)
		entry["canned"] = true  # tag so we can detect fallback at playback time
		pool.append(entry)
		TTSInterface.cache_dialogue_audio(line, entry["voice"], TAUNT_SPEED, TAUNT_STYLE)
	return pool

# Holds the opening taunt (see _opening_taunt_held). Called by UIManager when it
# shows the one-time combat tutorial popup, so the enemy doesn't cut off N.O.V.A.
func hold_opening_taunt() -> void:
	_opening_taunt_held = true


# Releases the hold and plays the opening taunt if one tried to fire while held.
# Called when the player dismisses the combat tutorial popup. Safe no-op when
# nothing was held (e.g. the popup reopened later from the pause menu).
func release_opening_taunt() -> void:
	_opening_taunt_held = false
	if _opening_taunt_pending:
		_opening_taunt_pending = false
		_play_combat_taunt()


# Fire exactly one taunt for the attacking ship, voiced from the right pool.
func _play_combat_taunt() -> void:
	if not _combat_voice_on():
		return
	# Tutorial popup is up — queue the taunt and let it play once dismissed so it
	# doesn't step on N.O.V.A.'s tutorial line (release_opening_taunt flushes it).
	if _opening_taunt_held:
		_opening_taunt_pending = true
		return
	# Bribe / board-mission (comms-reversal) targets keep their own branching
	# dialog — skip the generic taunt for them.
	if _is_comms_reversal_target():
		return
	# Usually anger (aggressor-based); occasionally a comedic jab instead.
	var pool: Array
	if randf() < TAUNT_HUMOR_CHANCE and not _cached_humor.is_empty():
		pool = _cached_humor
	else:
		pool = _cached_rage if _player_initiated else _cached_reason
	if pool.is_empty():
		return
	var pick: Dictionary = pool[randi() % pool.size()]
	if pick.get("canned", false):
		var msg := "[TAUNT FALLBACK] opening taunt used canned line — LLM pool not ready yet. Text: \"%s\"" % pick["text"]
		push_warning(msg)
		print(msg)
		_record_combat_fallback(
			"combat_opening_taunt",
			"canned_pool_line",
			{"text": str(pick.get("text", ""))}
		)
	var faction: String = enemy_node.get("faction") if is_instance_valid(enemy_node) and enemy_node.get("faction") else "ENEMY"
	GlobalState.emit_chatter(faction.to_upper(), pick["text"], Color(1.0, 0.4, 0.3))
	TTSInterface.play_dialogue_audio(pick["text"], pick["voice"], TAUNT_SPEED, TAUNT_STYLE)

func _play_npc_action_taunt(key: String) -> void:
	if not _combat_voice_on() or not is_instance_valid(enemy_node):
		return
	var line: String = taunts.get(key, "")
	if line.is_empty():
		if _taunts_ready:
			_record_combat_fallback(
				"combat_action_taunt",
				"empty_action_key",
				{"key": key}
			)
		# Empty means this key was never filled — the per-fight LLM fetch failed or
		# Ollama returned a partial response. Log it so we can diagnose.
		if _taunts_ready:
			push_warning("[TAUNT FALLBACK] action taunt key '%s' is empty — per-fight fetch may have fallen back to canned dict" % key)
		return
	var faction: String = enemy_node.get("faction") if enemy_node.get("faction") else "ENEMY"
	GlobalState.emit_chatter(faction.to_upper(), line, Color(1.0, 0.4, 0.3))
	if not _cached_rage.is_empty():
		var pick: Dictionary = _cached_rage[randi() % _cached_rage.size()]
		TTSInterface.play_dialogue_audio(line, pick["voice"], TAUNT_SPEED, TAUNT_STYLE)

func _play_npc_flee_taunt() -> void:
	if not _combat_voice_on() or not is_instance_valid(enemy_node):
		return
	var line: String = taunts.get("npc_player_fled_success", "")
	if line.is_empty():
		return
	var faction: String = enemy_node.get("faction") if enemy_node.get("faction") else "ENEMY"
	GlobalState.emit_chatter(faction.to_upper(), line, Color(1.0, 0.4, 0.3))
	# Pick a voice from the cached rage pool (same angry blend the opening taunt uses).
	if not _cached_rage.is_empty():
		var pick: Dictionary = _cached_rage[randi() % _cached_rage.size()]
		TTSInterface.play_dialogue_audio(line, pick["voice"], TAUNT_SPEED, TAUNT_STYLE)


func _record_combat_fallback(content_type: String, reason: String, context: Dictionary = {}) -> void:
	var next_context := context.duplicate(true)
	if is_instance_valid(enemy_node):
		next_context["enemy"] = str(enemy_node.name)
		next_context["faction"] = str(enemy_node.get("faction")) if enemy_node.get("faction") else "unknown"
	GenerationDiagnostics.record_fallback(content_type, reason, "CombatManager", next_context)

# True if the enemy belongs to an active comms-reversal (bribe) mission target,
# whose branching transmission dialog should not be stepped on by a generic taunt.
func _is_comms_reversal_target() -> bool:
	if not is_instance_valid(enemy_node):
		return false
	var fac = enemy_node.get("faction")
	if fac == null:
		return false
	for m in QuestManager.get_mission_collection().get_all_active():
		if str(m.data.get("objective_type", "")) == "TARGET_WITH_COMMS_REVERSAL" \
				and str(m.data.get("target_faction", "")) == str(fac):
			return true
	return false

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

func start_combat(player: Node, enemy: Node, player_initiated: bool = true) -> void:
	if GlobalState.intro_cinematic_active:
		return
	if state != State.IDLE:
		return
	if not player_initiated and is_training_combat_active() \
			and not bool(enemy.get_meta("intro_tutorial_target", false)):
		if enemy.has_method("_redirect_from_combat_queue"):
			enemy.call("_redirect_from_combat_queue")
		return
	# Set state immediately so physics-frame re-entry can't spawn duplicate requests
	# while the async taunt fetch is in flight.
	state = State.PLANNING
	player_node  = player
	enemy_nodes  = [enemy]
	_target_idx  = 0
	_enemy_brace  = [false]
	_enemy_shield = [false]
	_player_initiated = player_initiated
	_taunts_ready = false
	taunts = {}
	_load_upgrade_stats()
	_reset_fight_state()

	# Fetch taunts async; _on_taunts_ready finishes setup when they arrive.
	var faction:   String = enemy.get("faction") if enemy.get("faction") else "unknown"
	var archetype: String = enemy.get("ship_role") if enemy.get("ship_role") else "Gunner"
	LLMInterface.request_combat_taunts(faction, archetype, _on_taunts_ready)

	emit_signal("combat_started", enemy)

## Cycles the player's target to the next live enemy in the squad.
## Called by the TARGET ▸ button in CombatPanel. Free action, 0 AP cost.
## Explicitly set the target by index. No-op if already targeted or index invalid.
func set_target(idx: int) -> void:
	if idx < 0 or idx >= enemy_nodes.size():
		return
	if not is_instance_valid(enemy_nodes[idx]) or enemy_nodes[idx].get("destroyed"):
		return
	if _target_idx == idx:
		return
	_target_idx = idx
	npc_action_plan = npc_action_plans[_target_idx] if _target_idx < npc_action_plans.size() else []
	_spawn_target_flash(enemy_nodes[_target_idx])

func cycle_target() -> void:
	if enemy_nodes.size() <= 1:
		return
	var start := _target_idx
	var next   := (_target_idx + 1) % enemy_nodes.size()
	while next != start:
		if is_instance_valid(enemy_nodes[next]) and not enemy_nodes[next].get("destroyed"):
			_target_idx = next
			npc_action_plan = npc_action_plans[_target_idx] if _target_idx < npc_action_plans.size() else []
			_spawn_target_flash(enemy_nodes[_target_idx])
			return
		next = (next + 1) % enemy_nodes.size()

func _spawn_target_flash(target: Node) -> void:
	if not is_instance_valid(target):
		return
	# Collect all MeshInstance3D children of the target ship.
	var meshes: Array = []
	_collect_meshes(target, meshes)
	if meshes.is_empty():
		return
	# White unshaded material, slightly transparent to start.
	var mat := StandardMaterial3D.new()
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color    = Color(1.0, 1.0, 1.0, 0.75)
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 1
	# For each mesh, spawn a slightly-scaled duplicate and tween it out.
	for mesh_inst: MeshInstance3D in meshes:
		if not is_instance_valid(mesh_inst):
			continue
		var ghost := MeshInstance3D.new()
		ghost.mesh = mesh_inst.mesh
		ghost.transform = mesh_inst.global_transform
		ghost.scale    *= 1.08
		ghost.material_override = mat
		target.get_parent().add_child(ghost)
		var tw := ghost.create_tween()
		tw.set_ignore_time_scale(true)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.35)
		tw.tween_callback(ghost.queue_free)

func _collect_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)

## Called by a squad wingman that wants to join an active fight.
## Only accepted during the PLANNING phase; guards against mid-execution joins.
func join_combat(enemy: Node) -> void:
	if state != State.PLANNING:
		return
	if is_training_combat_active() and not bool(enemy.get_meta("intro_tutorial_target", false)):
		if enemy.has_method("_redirect_from_combat_queue"):
			enemy.call("_redirect_from_combat_queue")
		return
	if enemy_nodes.size() >= 3:
		return
	if not is_instance_valid(enemy):
		return
	enemy_nodes.append(enemy)
	_enemy_brace.append(false)
	_enemy_shield.append(false)
	# Generate a plan for the joining enemy immediately so it acts this turn.
	var plan: Array = enemy.generate_action_plan() if enemy.has_method("generate_action_plan") else []
	npc_action_plans.append(plan)
	GlobalState.emit_chatter("SYSTEM", "Wingman joined the fight!", Color(1.0, 0.5, 0.2))

func _on_taunts_ready(data: Dictionary) -> void:
	# Guard against stale callbacks from duplicate requests (race with early state set)
	if state == State.IDLE or _taunts_ready:
		return
	taunts = data
	_taunts_ready = true
	# Detect if LLMInterface fell back to COMBAT_TAUNT_FALLBACKS for this fight.
	var canned_ref: Dictionary = LLMInterface.COMBAT_TAUNT_FALLBACKS
	var matched := 0
	for k in canned_ref.keys():
		if taunts.get(k, "") == canned_ref[k]:
			matched += 1
	if matched == canned_ref.size():
		var faction: String = enemy_nodes[0].get("faction") if not enemy_nodes.is_empty() and is_instance_valid(enemy_nodes[0]) else "unknown"
		_record_combat_fallback(
			"combat_taunts",
			"all_canned_defaults",
			{"faction": faction, "matched": matched, "total": canned_ref.size()}
		)
		var msg := "[TAUNT FALLBACK] per-fight taunts are ALL canned defaults for this fight (%s). Check Ollama." % faction
		push_warning(msg)
		print(msg)
	elif matched > 0:
		var partial_faction: String = enemy_nodes[0].get("faction") if not enemy_nodes.is_empty() and is_instance_valid(enemy_nodes[0]) else "unknown"
		_record_combat_fallback(
			"combat_taunts",
			"partial_canned_defaults",
			{"faction": partial_faction, "matched": matched, "total": canned_ref.size()}
		)
		push_warning("[TAUNT FALLBACK] per-fight taunts: %d/%d keys are canned fallback values — partial LLM fill." % [matched, canned_ref.size()])
	_begin_planning()

func end_combat(player_won: bool) -> void:
	state = State.IDLE
	_lerp_timescale(1.0, 1.0, 600)
	player_node   = null
	enemy_nodes.clear()
	_enemy_brace.clear()
	_enemy_shield.clear()
	_target_idx   = 0
	queued_actions.clear()
	# Notify queue first — it starts the 3-second buffer and releases the slot.
	PlayerInteractionQueue.notify_combat_ended()
	emit_signal("combat_ended", player_won)
	# Top up the general taunt pool in the background after each fight.
	_request_general_taunt_pool()

func _reset_fight_state() -> void:
	# Runs before combat_started is emitted, so any stale tutorial hold clears
	# here and UIManager re-arms it (if needed) during that emission.
	_opening_taunt_held = false
	_opening_taunt_pending = false
	queued_actions.clear()
	range_band = CombatActionType.RangeBand.MID
	player_shield_face = CombatActionType.Face.FRONT
	micro_warp_cooldown = 0
	repair_used_this_turn = false
	player_is_flanking = false
	current_intent = {}
	npc_action_plan = []
	npc_action_plans = []
	for _j in enemy_nodes.size():
		npc_action_plans.append([])
	player_shield_reroute_active = false
	_despawn_shield_dome()
	_enemy_brace  = []
	_enemy_shield = []
	for _i in enemy_nodes.size():
		_enemy_brace.append(false)
		_enemy_shield.append(false)
	_despawn_enemy_shield_dome()
	_told_brace_hint = false
	_told_shield_angle_hint = false
	_player_low_alarmed = false
	_enemy_low_alarmed = false
	_boss_phase_alarmed_2 = false
	_boss_phase_alarmed_3 = false
	_turn_number = 0

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
	if type == CombatActionType.Type.MICRO_WARP and is_training_combat_active():
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


func is_training_combat_active() -> bool:
	if not QuestManager.is_quest_active():
		return false
	if QuestManager.is_quest_completed():
		return false
	return str(QuestManager.active_quest.get("title", "")) == "Clean and Easy" \
		and str(QuestManager.active_quest.get("objective_type", "")) == "KILL_SHIPS" \
		and str(QuestManager.active_quest.get("target_faction", "")) == "reavers"

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
	# Time-stretch riser pairs with the slow-mo + music pitch drop.
	_sfx("slowmo_riser", null, -4.0)

	# Clear last turn's shield reroute and all enemy defensive states — per-turn commitments.
	player_shield_reroute_active = false
	_despawn_shield_dome()
	for i in _enemy_brace.size():
		_enemy_brace[i]  = false
		_enemy_shield[i] = false
	_despawn_enemy_shield_dome()
	emit_signal("enemy_status_changed", false, false)

	# Build each enemy's AP-driven action plan for this turn.
	npc_action_plans = []
	for i in enemy_nodes.size():
		var e: Node = enemy_nodes[i]
		var plan: Array = e.generate_action_plan() if is_instance_valid(e) and e.has_method("generate_action_plan") else []
		npc_action_plans.append(plan)
	# npc_action_plan kept pointing at the targeted enemy's plan for UI / compat.
	npc_action_plan = npc_action_plans[_target_idx] if _target_idx < npc_action_plans.size() else []
	# Keep current_intent pointing at the first action for the telegraph UI.
	current_intent = npc_action_plan[0] if not npc_action_plan.is_empty() else {}

	# Menacing charge cue when the targeted enemy telegraphs an attack this turn.
	if _intent_is_attack(current_intent):
		_sfx("enemy_charge", (enemy_node as Node3D).global_position, -3.0)

	emit_signal("planning_started", ap_current, ap_max, current_intent, taunts, npc_action_plan)

	# Exactly one voiced enemy taunt per fight, fired on the first planning phase.
	_turn_number += 1
	if _turn_number == 1:
		_play_combat_taunt()

# Whether an NPC intent will deal damage this turn (used for the charge cue).
func _intent_is_attack(intent: Dictionary) -> bool:
	return intent.get("type", "") in ["fire", "hull_shot", "suppression", "flank", "panic"]

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
# is_drone=true routes damage through drone_dmg_mult instead of weapon_dmg_mult.
func _apply_hit(target, attacker_faction: String, dmg: float, crit: bool, blocked: bool, is_drone: bool = false) -> void:
	if not is_instance_valid(target):
		return
	# Apply target's damage-type resistance if defined (set by apply_faction_profile).
	var damage_mult := 1.0
	if not blocked:
		var mult_key := "drone_dmg_mult" if is_drone else "weapon_dmg_mult"
		var resist = target.get(mult_key)
		if resist != null:
			damage_mult = float(resist)
			dmg *= damage_mult
	var hit_pos: Vector3 = (target as Node3D).global_position
	if target.has_method("take_damage"):
		target.take_damage(dmg, attacker_faction)
	var lethal: bool = (not is_instance_valid(target)) or (target.get("destroyed") == true)
	if not lethal and is_instance_valid(target):
		var hp = target.get("health")
		if hp != null and float(hp) <= 0.0:
			lethal = true
	if lethal:
		_last_kill_pos = hit_pos
	# Impact SFX: shield deflect vs hull hit, plus sub-bass thud and a crit layer.
	if blocked:
		_sfx("shield_deflect", hit_pos)
	else:
		_sfx("hull_impact", hit_pos)
		_sfx("impact_thud", hit_pos, -3.0)
	if crit:
		_sfx("hit_critical", hit_pos)
	_spawn_damage_number(target, hit_pos, dmg, blocked, crit, damage_mult)
	emit_signal("action_impact", target, hit_pos, dmg, lethal, blocked, crit)
	# Check boss phase transitions when the player damages the enemy.
	if target == enemy_node:
		_check_boss_phase_transition()
	# Hit-stop freeze-frame (skip on lethal — the kill cinematic handles that).
	if not lethal:
		_hit_stop(0.07 + (0.05 if crit else 0.0))

# Floating 3D damage number at the hit point. Crit = big + gold, blocked =
# small + cyan "BLOCKED", resistance = dim/small, vulnerability = bright/big.
func _spawn_damage_number(
	target: Node,
	hit_pos: Vector3,
	dmg: float,
	blocked: bool,
	crit: bool,
	damage_mult: float = 1.0
) -> void:
	var parent: Node = null
	if is_instance_valid(target):
		parent = target.get_parent()
	if parent == null and is_instance_valid(player_node):
		parent = player_node.get_parent()
	if parent == null:
		return
	var text: String
	var color: Color
	var big := crit
	var scale := 1.0
	if blocked:
		text = "BLOCKED %d" % int(dmg)
		color = Color(0.45, 0.85, 1.0)
	elif crit:
		text = "%d!" % int(dmg)
		color = Color(1.0, 0.85, 0.2)
	elif damage_mult < 0.95:
		text = "RESIST %d" % int(dmg)
		color = Color(0.55, 0.62, 0.7)
		scale = 0.78
	elif damage_mult > 1.05:
		text = "WEAK %d" % int(dmg)
		color = Color(1.0, 0.35, 0.16)
		big = true
		scale = 1.08
	else:
		text = "%d" % int(dmg)
		color = Color(1.0, 0.55, 0.2)
	CombatDamageNumber.spawn(parent, hit_pos, text, color, big, scale)

# Brief freeze-frame on impact. Fire-and-forget; wall-clock restore so the
# sequencer's own beats (also wall-clock) keep running underneath.
func _hit_stop(freeze_sec: float) -> void:
	_lerp_active = false
	Engine.time_scale = 0.02
	await get_tree().create_timer(freeze_sec, true, false, true).timeout
	if state == State.EXECUTING:
		Engine.time_scale = 1.0

# Cinematic kill: punch in on the victim, slow-mo, big explosion + sound, hold,
# sting, then end combat. victim is untyped — it may already be freed when a
# ship dies mid-turn, so we fall back to the last lethal-hit position.
# skip_end: true when this is one of multiple enemies dying (squad kill).
# The caller (_remove_dead_enemies) decides when to call end_combat.
func _kill_and_end(victim, player_won: bool, skip_end: bool = false) -> void:
	var v: Node = victim if is_instance_valid(victim) else null
	var pos := _last_kill_pos
	if v != null:
		pos = (v as Node3D).global_position
	# Roll loot before the node is freed — future systems connect to combat_loot_dropped.
	if v != null and v.has_method("roll_loot"):
		var loot: Dictionary = v.roll_loot()
		if not loot.is_empty():
			emit_signal("combat_loot_dropped", loot)
	# Camera punches in on the kill (PlayerShip listens to combat_kill).
	emit_signal("combat_kill", v, pos)
	# Death beat: slow-mo + a bigger explosion than the ship's own death puff.
	_lerp_timescale(0.25, 0.70, 250)
	_sfx("death_explosion", pos, 0.0)
	var fx_parent: Node = v.get_parent() if v != null else (
		player_node.get_parent() if is_instance_valid(player_node) else null)
	if fx_parent != null:
		ImpactEffect.spawn_explosion(fx_parent, pos, Color(1.0, 0.6, 0.2), 2.5)
	# Hold on the moment (wall-clock so slow-mo doesn't stretch it).
	await _beat(1.1)
	_sfx("combat_sting", null, -3.0)
	_lerp_timescale(1.0, 1.0, 300)
	if not skip_end:
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
		await _kill_and_end(enemy_node, true)
		return
	await _beat(BEAT_TURN_GAP)
	if state == State.IDLE:
		return
	await _execute_npc_intent()
	if state == State.IDLE:
		return
	await _after_npc_turn()

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
	if t in _ATTACK_TYPES:
		GlobalState.clear_intro_tutorial_player_protection()
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
		player_node.spawn_projectile(enemy_node, true)
	await _await_travel(player_node, enemy_node)
	if not is_instance_valid(enemy_node):
		return
	# Enemy brace: 40% reduction, halved to 20% when flanking. Drone bypasses (not this path).
	if enemy_brace_active:
		var reduction := 0.20 if player_is_flanking else 0.40
		dmg *= (1.0 - reduction)
		GlobalState.emit_chatter("COMBAT", "Brace absorbed %d%% — %d damage." % [int(reduction * 100), int(dmg)], Color(0.6, 0.8, 1.0))
	# Enemy shield angle: first hit blocked 65%, bypassed when flanking. Consume on hit.
	if enemy_shield_angle_active and not player_is_flanking:
		dmg *= 0.35
		enemy_shield_angle_active = false
		_despawn_enemy_shield_dome()
		emit_signal("enemy_status_changed", enemy_brace_active, false)
		GlobalState.emit_chatter("COMBAT", "Shield angle deflected — %d damage." % int(dmg), Color(1.0, 0.6, 0.2))
	_apply_hit(enemy_node, "player", dmg, player_is_flanking, false)
	GlobalState.emit_chatter("COMBAT", "You fire — %d damage." % int(dmg), Color(1.0, 0.55, 0.2))

# Floating status text at the player — feedback for non-damage actions.
func _player_status_float(text: String, color: Color) -> void:
	if not is_instance_valid(player_node):
		return
	var parent: Node = player_node.get_parent()
	if parent != null:
		# Half-size — status strings are long and were running off-screen.
		CombatDamageNumber.spawn(parent, (player_node as Node3D).global_position, text, color, false, 0.5)

# Floating status text above the enemy ship.
func _enemy_status_float(text: String, color: Color) -> void:
	if not is_instance_valid(enemy_node):
		return
	var parent: Node = enemy_node.get_parent()
	if parent != null:
		CombatDamageNumber.spawn(parent, (enemy_node as Node3D).global_position + Vector3(0, 4, 0), text, color, false, 0.5)

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
	var band_names := {
		CombatActionType.RangeBand.LONG: "LONG",
		CombatActionType.RangeBand.MID:  "MID",
		CombatActionType.RangeBand.CLOSE: "CLOSE",
	}
	_player_status_float("REPOSITION ▸ %s" % band_names.get(range_band, "MID"), Color(0.95, 0.6, 0.2))
	GlobalState.emit_chatter("COMBAT", "Reposition — range now %s." % str(band_names.get(range_band, "MID")), Color(0.95, 0.6, 0.2))

func _exec_shield_reroute(_params: Dictionary) -> void:
	if is_instance_valid(player_node):
		_sfx("shield_reroute", player_node.global_position)
	# New mechanic: auto-faces enemy, blocks first incoming hit by 65%.
	# Bypassed if the enemy repositions before firing (they change angle).
	player_shield_reroute_active = true
	_spawn_shield_dome()
	_player_status_float("SHIELD UP", Color(1.0, 0.85, 0.1))
	GlobalState.emit_chatter("COMBAT", "Shields raised — first enemy hit absorbed 65%.", Color(0.85, 0.78, 0.25))

func _exec_attack_drone() -> void:
	if not is_instance_valid(enemy_node):
		return
	if player_node.has_method("launch_combat_drone"):
		player_node.launch_combat_drone(enemy_node)
	_sfx("drone_launch", player_node.global_position)
	var drone_dmg := _resolve_player_hit(GlobalState.weapon_damage * 0.4)
	await _await_travel(player_node, enemy_node)
	if not is_instance_valid(enemy_node):
		return
	# Drone bypasses brace and shield angle — precision targeting ignores bulk defenses.
	if enemy_brace_active or enemy_shield_angle_active:
		GlobalState.emit_chatter("COMBAT", "Drone bypasses their defense.", Color(0.3, 0.9, 0.9))
	_apply_hit(enemy_node, "player", drone_dmg, player_is_flanking, false, true)
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
	# Flanking nullifies the enemy's shield angle — angle changed.
	if enemy_shield_angle_active:
		enemy_shield_angle_active = false
		_despawn_enemy_shield_dome()
		emit_signal("enemy_status_changed", enemy_brace_active, false)
		GlobalState.emit_chatter("SYSTEM", "Flank maneuver — enemy shield angle lost!", Color(1.0, 0.5, 0.2))
	_player_status_float("MICRO-WARP!", Color(0.6, 0.4, 1.0))
	GlobalState.emit_chatter("COMBAT", "Micro-warp — flanking the enemy.", Color(0.6, 0.4, 1.0))

func _exec_repair_kit() -> void:
	if not is_instance_valid(player_node):
		return
	if not GlobalState.inventory.has_item("repair_kit"):
		return
	GlobalState.inventory.remove("repair_kit", 1)
	_sfx("repair_kit", player_node.global_position)
	# Combat repair restores 30% of max hull — meatier than the 25hp field use.
	var max_hp: float = float(player_node.get("max_health")) if player_node.get("max_health") != null else 100.0
	var before:  float = float(player_node.get("health")) if player_node.get("health") != null else max_hp
	var after:   float = min(before + max_hp * 0.30, max_hp)
	var healed:  float = after - before
	if player_node.has_method("heal"):
		player_node.heal(after - before)
	else:
		player_node.health = after
	# Green floating heal number so the repair is visible during the cinematic.
	if healed > 0.5:
		var parent: Node = player_node.get_parent()
		if parent != null:
			CombatDamageNumber.spawn(parent, (player_node as Node3D).global_position,
				"+%d" % int(round(healed)), Color(0.45, 1.0, 0.55), false)
	GlobalState.emit_chatter("Drone Bay", "Repair kit deployed — hull patched (+%d)." % int(round(healed)), Color(0.4, 0.9, 0.6))

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
		GlobalState.emit_chatter("SYSTEM", "Engines burn hot — you break their lock and escape.", Color(0.5, 1.0, 0.5))
		# Enemy taunts the fleeing player in the NPC's voice, not Kaelen's.
		_play_npc_flee_taunt()
		_play_kaelen_line("kaelen_player_fled")
		# Physically boost the player away so the enemy can't instantly re-acquire.
		# Direction: away from the enemy; distance puts us outside the NPC's 130-unit
		# re-target range so the 3-second buffer has time to fully expire first.
		if is_instance_valid(player_node) and is_instance_valid(enemy_node):
			var flee_dir: Vector3 = (player_node.global_position - enemy_node.global_position).normalized()
			player_node.global_position += flee_dir * 160.0
			# Clear the enemy's target so it must re-acquire fresh after the buffer.
			if enemy_node.has_method("set") and enemy_node.get("target") != null:
				enemy_node.set("target", null)
		end_combat(false)
	else:
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
	# flanking is in params subdict for unified-format actions; fall back to top-level for old format.
	var params: Dictionary = intent.get("params", {}) as Dictionary
	var flanking_raw = params.get("flanking", intent.get("flanking"))
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

# True when the player's equipped shield face absorbs this NPC attack.
# Separate from Shield Reroute (which is an active ability this turn).
func _npc_hit_shield_blocked(action: Dictionary) -> bool:
	if GlobalState.shield_capacity <= 0.0:
		return false
	var attack_face: int = action.get("face", CombatActionType.Face.FRONT)
	var is_flanking: bool = action.get("flanking", false)
	if is_flanking and int(player_shield_face) == CombatActionType.Face.FRONT:
		return false  # flanking bypasses front shield
	if attack_face == int(player_shield_face):
		return true
	if _shield_dual_face and attack_face == _adjacent_face(int(player_shield_face)):
		return true
	return false

# ── NPC execution (AP-driven, simultaneous plan) ─────────────────────────────
# The NPC's plan was locked in at planning-start (same moment the player began
# choosing). We now execute each action in sequence.
func _execute_npc_intent() -> void:
	if not is_instance_valid(player_node):
		return
	# Execute each enemy's plan in sequence (target first, then wingmen).
	for i in enemy_nodes.size():
		if state == State.IDLE or not is_instance_valid(player_node):
			return
		var exec_enemy: Node = enemy_nodes[i]
		if not is_instance_valid(exec_enemy) or exec_enemy.get("destroyed"):
			continue
		var plan: Array = npc_action_plans[i] if i < npc_action_plans.size() else []
		if plan.is_empty():
			continue
		var npc_faction: String = exec_enemy.get("faction") if exec_enemy.get("faction") else "enemy"
		# Temporarily point _target_idx at this enemy so defensive state
		# getters (enemy_brace_active etc.) resolve to the right slot.
		var saved_idx := _target_idx
		_target_idx = i
		for action in plan:
			if state == State.IDLE or not is_instance_valid(exec_enemy) or not is_instance_valid(player_node):
				break
			# Per-action telegraph with context-aware target:
			# offensive actions frame toward the player; defensive ones frame
			# tight on the enemy ship so the camera reads the action clearly.
			var itype = action.get("type", CombatAction.Type.FIRE)
			var is_defensive: bool = itype in [
				CombatAction.Type.BRACE,
				CombatAction.Type.SHIELD_ANGLE,
				CombatAction.Type.REPAIR_KIT,
				CombatAction.Type.BOOST,
				CombatAction.Type.DISABLE_ENGINES,
				CombatAction.Type.FLEE,
			]
			var tele_target: Node = exec_enemy if is_defensive else player_node
			emit_signal("action_telegraphed", itype, exec_enemy, tele_target)
			await _beat(BEAT_TELEGRAPH)
			await _execute_npc_action(action, npc_faction)
			if state == State.IDLE:
				break
			await _beat(BEAT_POST_ACTION)
		_target_idx = saved_idx
		await _beat(BEAT_POST_ACTION)

func _execute_npc_action(action: Dictionary, npc_faction: String) -> void:
	var itype = action.get("type", CombatAction.Type.FIRE)
	var aparams: Dictionary = action.get("params", {}) as Dictionary
	match itype:
		CombatAction.Type.FIRE:
			var base_dmg: float = aparams.get("damage", 10.0)
			var npc_dmg := _resolve_npc_hit(base_dmg, action)
			var shield_blocked := _npc_hit_shield_blocked(action)
			if player_shield_reroute_active:
				npc_dmg *= 0.35  # 65% mitigation
				_consume_shield_reroute()
				GlobalState.emit_chatter("SYSTEM", "Shield absorbed the attack!", Color(0.85, 0.78, 0.25))
			_sfx("weapon_fire", enemy_node.global_position)
			AudioManager.play_laser(enemy_node.global_position)
			if enemy_node.has_method("spawn_projectile"):
				enemy_node.spawn_projectile(player_node, true)
			await _await_travel(enemy_node, player_node)
			if not is_instance_valid(player_node):
				return
			_apply_hit(player_node, npc_faction, npc_dmg, false, shield_blocked)
			if not shield_blocked:
				GlobalState.emit_chatter("COMBAT", "Enemy hits you for %d damage." % int(npc_dmg), Color(1.0, 0.3, 0.3))
		CombatAction.Type.FLANK:
			# Reposition to flank — bypasses Shield Reroute (angle changed).
			if player_shield_reroute_active:
				_consume_shield_reroute()
				GlobalState.emit_chatter("SYSTEM", "Enemy flanked — shield bypassed!", Color(1.0, 0.5, 0.2))
			range_band = CombatActionType.RangeBand.CLOSE
			var npc_dmg := _resolve_npc_hit(aparams.get("damage", 8.0), action)
			_sfx("weapon_fire", enemy_node.global_position)
			AudioManager.play_laser(enemy_node.global_position)
			if enemy_node.has_method("spawn_projectile"):
				enemy_node.spawn_projectile(player_node, true)
			await _await_travel(enemy_node, player_node)
			if not is_instance_valid(player_node):
				return
			_apply_hit(player_node, npc_faction, npc_dmg, true, false)
			GlobalState.emit_chatter("COMBAT", "Flanking hit — %d damage." % int(npc_dmg), Color(1.0, 0.3, 0.3))
		CombatAction.Type.BOOST:
			# Enemy repositions — if Shield Reroute is up, angle changed = bypassed.
			if player_shield_reroute_active:
				_consume_shield_reroute()
				GlobalState.emit_chatter("SYSTEM", "Enemy repositioned — shield angle lost!", Color(1.0, 0.5, 0.2))
			var dir: String = aparams.get("direction", "closer")
			var old_band: int = range_band
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
			_sfx("engine_boost", enemy_node.global_position)
			var band_names := {
				CombatActionType.RangeBand.CLOSE: "CLOSE",
				CombatActionType.RangeBand.MID: "MID",
				CombatActionType.RangeBand.LONG: "LONG",
			}
			var band_label: String = str(band_names.get(range_band, "MID"))
			var move_label := "CLOSING" if dir == "closer" else "EVADING"
			_enemy_status_float("%s ▸ %s" % [move_label, band_label], Color(0.95, 0.6, 0.2))
			if range_band != old_band:
				GlobalState.emit_chatter("COMBAT", "Enemy repositions — range now %s." % band_label, Color(0.95, 0.6, 0.2))
			else:
				GlobalState.emit_chatter("COMBAT", "Enemy burns hard but holds %s range." % band_label, Color(0.95, 0.6, 0.2))
			_play_npc_action_taunt("npc_reposition")
		CombatAction.Type.FLEE:
			_exec_enemy_flee()
		CombatAction.Type.DISABLE_ENGINES:
			ap_max = max(2, ap_max - 1)
			_sfx("enemy_charge", enemy_node.global_position)
			GlobalState.emit_chatter("SYSTEM", "Engine disruption — AP reduced by 1 next turn.", Color(1.0, 0.5, 0.2))
		CombatAction.Type.REPAIR_KIT:
			var npc_hp: float = float(enemy_node.get("health")) if enemy_node.get("health") else 0.0
			var npc_max: float = float(enemy_node.get("max_health")) if enemy_node.get("max_health") else 50.0
			var heal := npc_max * 0.20
			enemy_node.health = min(npc_hp + heal, npc_max)
			_sfx("repair_kit", enemy_node.global_position)
			GlobalState.emit_chatter("COMBAT", "Enemy repairs — hull patched.", Color(0.4, 0.9, 0.6))
		CombatAction.Type.BRACE:
			enemy_brace_active = true
			_sfx("shield_reroute", enemy_node.global_position)
			_enemy_status_float("BRACE", Color(0.4, 0.7, 1.0))
			GlobalState.emit_chatter("COMBAT", "Enemy braces — incoming damage reduced.", Color(0.4, 0.7, 1.0))
			emit_signal("enemy_status_changed", true, enemy_shield_angle_active)
			_play_npc_action_taunt("npc_brace")
			if not _told_brace_hint:
				_told_brace_hint = true
				GlobalState.emit_chatter("Kaelen", "They're braced. Drone punches right through it.", Color(0.85, 0.5, 1.0))
		CombatAction.Type.SHIELD_ANGLE:
			enemy_shield_angle_active = true
			_sfx("shield_reroute", enemy_node.global_position)
			_enemy_status_float("SHIELDED", Color(1.0, 0.5, 0.2))
			GlobalState.emit_chatter("COMBAT", "Enemy angles shields toward you.", Color(1.0, 0.5, 0.2))
			emit_signal("enemy_status_changed", enemy_brace_active, true)
			_spawn_enemy_shield_dome()
			_play_npc_action_taunt("npc_shield_angle")
			if not _told_shield_angle_hint:
				_told_shield_angle_hint = true
				GlobalState.emit_chatter("Kaelen", "They've angled shields. Flank or drone — both bypass it.", Color(0.85, 0.5, 1.0))

# ── Shield Reroute (new mechanic) ────────────────────────────────────────────
func _exec_enemy_flee() -> void:
	if not is_instance_valid(enemy_node):
		return
	_sfx("engine_boost", enemy_node.global_position)
	_enemy_status_float("FLEEING", Color(0.5, 1.0, 0.55))
	_play_npc_action_taunt("npc_enemy_fled")
	GlobalState.emit_chatter("COMBAT", "Enemy breaks off and runs.", Color(0.5, 1.0, 0.55))
	var fleeing_enemy := enemy_node as Node3D
	if fleeing_enemy != null and is_instance_valid(player_node):
		var flee_dir: Vector3 = (fleeing_enemy.global_position - (player_node as Node3D).global_position).normalized()
		if flee_dir.length() <= 0.01:
			flee_dir = -fleeing_enemy.global_transform.basis.z.normalized()
		fleeing_enemy.global_position += flee_dir * 180.0
		fleeing_enemy.set("target", null)
		fleeing_enemy.set("patrol_center", fleeing_enemy.global_position)
	end_combat(false)


func _consume_shield_reroute() -> void:
	player_shield_reroute_active = false
	_despawn_shield_dome()

func _spawn_shield_dome() -> void:
	_despawn_shield_dome()
	if not is_instance_valid(player_node) or not is_instance_valid(enemy_node):
		return
	var parent := player_node.get_parent()
	if parent == null:
		return
	_shield_dome = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius          = 8.0
	mesh.height          = 16.0
	mesh.rings           = 24
	mesh.radial_segments = 32
	mesh.is_hemisphere   = true
	_shield_dome.mesh = mesh
	var shader := Shader.new()
	shader.code = "shader_type spatial;\n" + \
		"render_mode blend_add, cull_disabled, unshaded, depth_draw_never;\n" + \
		"uniform vec4 rim_color : source_color = vec4(1.0, 0.88, 0.15, 1.0);\n" + \
		"uniform float rim_power : hint_range(1.0, 8.0) = 2.5;\n" + \
		"void fragment() {\n" + \
		"  float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));\n" + \
		"  rim = pow(rim, rim_power);\n" + \
		"  ALBEDO = rim_color.rgb;\n" + \
		"  ALPHA  = rim;\n" + \
		"}\n"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("rim_color", Color(1.0, 0.88, 0.15, 1.0))
	mat.set_shader_parameter("rim_power", 2.5)
	_shield_dome.material_override = mat
	_shield_dome.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(_shield_dome)
	_shield_dome.global_position = player_node.global_position
	# Orient dome toward the enemy — hemisphere +Y is the dome tip, so rotate
	# +Y to point at the enemy.
	var to_enemy: Vector3 = ((enemy_node as Node3D).global_position - (player_node as Node3D).global_position).normalized()
	var up: Vector3 = Vector3.UP
	var axis: Vector3 = up.cross(to_enemy)
	if axis.length_squared() > 0.001:
		_shield_dome.global_transform.basis = Basis(axis.normalized(), up.angle_to(to_enemy))
	elif to_enemy.dot(up) < 0.0:
		_shield_dome.rotate_object_local(Vector3.RIGHT, PI)

func _despawn_shield_dome() -> void:
	if is_instance_valid(_shield_dome):
		_shield_dome.queue_free()
	_shield_dome = null

func _despawn_enemy_shield_dome() -> void:
	if is_instance_valid(_enemy_shield_dome):
		_enemy_shield_dome.queue_free()
	_enemy_shield_dome = null

func _spawn_enemy_shield_dome() -> void:
	_despawn_enemy_shield_dome()
	if not is_instance_valid(enemy_node) or not is_instance_valid(player_node):
		return
	var parent := enemy_node.get_parent()
	if parent == null:
		return
	_enemy_shield_dome = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius          = 8.0
	mesh.height          = 16.0
	mesh.rings           = 24
	mesh.radial_segments = 32
	mesh.is_hemisphere   = true
	_enemy_shield_dome.mesh = mesh
	var shader := Shader.new()
	shader.code = "shader_type spatial;\n" + \
		"render_mode blend_add, cull_disabled, unshaded, depth_draw_never;\n" + \
		"uniform vec4 rim_color : source_color = vec4(1.0, 0.35, 0.1, 1.0);\n" + \
		"uniform float rim_power : hint_range(1.0, 8.0) = 2.5;\n" + \
		"void fragment() {\n" + \
		"  float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));\n" + \
		"  rim = pow(rim, rim_power);\n" + \
		"  ALBEDO = rim_color.rgb;\n" + \
		"  ALPHA  = rim;\n" + \
		"}\n"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("rim_color", Color(1.0, 0.35, 0.1, 1.0))
	mat.set_shader_parameter("rim_power", 2.5)
	_enemy_shield_dome.material_override = mat
	_enemy_shield_dome.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(_enemy_shield_dome)
	_enemy_shield_dome.global_position = enemy_node.global_position
	# Orient dome toward the player — flat face points at them.
	var to_player: Vector3 = ((player_node as Node3D).global_position - (enemy_node as Node3D).global_position).normalized()
	var up: Vector3 = Vector3.UP
	var axis: Vector3 = up.cross(to_player)
	if axis.length_squared() > 0.001:
		_enemy_shield_dome.global_transform.basis = Basis(axis.normalized(), up.angle_to(to_player))
	elif to_player.dot(up) < 0.0:
		_enemy_shield_dome.rotate_object_local(Vector3.RIGHT, PI)

# Checks if a boss has crossed a phase threshold and fires the transition moment.
# Safe to call multiple times — alarmed flags prevent double-fire.
func _check_boss_phase_transition() -> void:
	if not is_instance_valid(enemy_node):
		return
	if not enemy_node.get("is_boss"):
		return
	var hp: float     = float(enemy_node.get("health")     if enemy_node.get("health")     != null else 1.0)
	var max_hp: float = float(enemy_node.get("max_health") if enemy_node.get("max_health") != null else 1.0)
	var ratio: float  = hp / max(max_hp, 1.0)

	if ratio <= 0.60 and not _boss_phase_alarmed_2:
		_boss_phase_alarmed_2 = true
		enemy_node.set("boss_phase", 2)
		_transition_boss_phase(2)
	elif ratio <= 0.30 and not _boss_phase_alarmed_3:
		_boss_phase_alarmed_3 = true
		enemy_node.set("boss_phase", 3)
		_transition_boss_phase(3)

func _transition_boss_phase(phase: int) -> void:
	var chatter_text: String
	var taunt_key: String
	match phase:
		2:
			chatter_text = "TARGET ENTERING PHASE II — threat level escalating."
			taunt_key    = "npc_boss_phase_2"
		3:
			chatter_text = "TARGET ENTERING PHASE III — ALL WEAPONS FREE."
			taunt_key    = "npc_boss_phase_3"
		_:
			return

	GlobalState.emit_chatter("SYSTEM", chatter_text, Color(1.0, 0.2, 0.2))
	_play_npc_action_taunt(taunt_key)
	emit_signal("boss_phase_changed", phase)

func _after_npc_turn() -> void:
	# Player death check first.
	var player_dead: bool = not is_instance_valid(player_node) or player_node.get("destroyed") == true
	if player_dead:
		await _kill_and_end(player_node, false)
		return

	# Remove any dead enemies and play their kill cinematic.
	await _remove_dead_enemies()
	if state == State.IDLE:
		return  # all enemies dead — combat ended inside _remove_dead_enemies

	# Low-health cues (text + alarm only, no Kaelen voice mid-fight).
	var player_hp:  float = float(player_node.get("health"))     if player_node.get("health")     != null else 100.0
	var player_max: float = float(player_node.get("max_health")) if player_node.get("max_health") != null else 100.0
	if player_hp / player_max <= 0.30 and not _player_low_alarmed:
		_player_low_alarmed = true
		_sfx("low_health_alarm", null, -4.0)
		GlobalState.emit_chatter("SYSTEM", "WARNING: Hull integrity critical.", Color(1.0, 0.4, 0.2))

	# Targeted-enemy low-health cue.
	if is_instance_valid(enemy_node):
		var enemy_hp:  float = float(enemy_node.get("health"))     if enemy_node.get("health")     != null else 50.0
		var enemy_max: float = float(enemy_node.get("max_health")) if enemy_node.get("max_health") != null else 50.0
		if enemy_hp / enemy_max <= 0.30 and not _enemy_low_alarmed:
			_enemy_low_alarmed = true
			_sfx("low_health_alarm", (enemy_node as Node3D).global_position, -8.0)
			GlobalState.emit_chatter("SYSTEM", "Target hull failing — press the attack.", Color(0.5, 1.0, 0.5))

	_check_boss_phase_transition()
	_begin_planning()

# Scans enemy_nodes for dead/invalid entries and removes them.
# Plays kill cinematics for each dead enemy. If none remain → end_combat(true).
func _remove_dead_enemies() -> void:
	var dead_indices: Array = []
	for i in enemy_nodes.size():
		var e: Node = enemy_nodes[i]
		if not is_instance_valid(e) or e.get("destroyed") == true:
			dead_indices.append(i)

	# Remove in reverse order so indices stay valid as we remove.
	for i in range(dead_indices.size() - 1, -1, -1):
		var idx: int = dead_indices[i]
		var dead_enemy: Node = enemy_nodes[idx]
		enemy_nodes.remove_at(idx)
		if idx < _enemy_brace.size():  _enemy_brace.remove_at(idx)
		if idx < _enemy_shield.size(): _enemy_shield.remove_at(idx)
		if idx < npc_action_plans.size(): npc_action_plans.remove_at(idx)
		# Adjust target index if we removed at or before it.
		if _target_idx >= idx and _target_idx > 0:
			_target_idx -= 1
		# Play kill cinematic. skip_end=true so we can check if more enemies remain.
		await _kill_and_end(dead_enemy, true, true)

	# If all enemies are gone, end combat as a player win.
	if enemy_nodes.is_empty():
		end_combat(true)

# ── Taunt / voice helpers ─────────────────────────────────────────────────────
func _combat_voice_on() -> bool:
	var taunts_on = GlobalState.get("combat_voice_taunts")
	return taunts_on == null or bool(taunts_on)

func _play_kaelen_line(key: String) -> void:
	if not _combat_voice_on():
		return
	var line: String = taunts.get(key, "")
	if line.is_empty():
		return
	GlobalState.emit_npc_flavor({
		"npc_name": "Kaelen",
		"line": line,
		"color": Color(0.6, 0.9, 1.0),
		"voice_profile_id": GlobalState.KAELEN_VOICE_PROFILE_ID,
	})

func play_player_reply() -> void:
	_play_kaelen_line("kaelen_open")
