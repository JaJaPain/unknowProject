extends Node

# NOTE: no class_name — this script is registered as the "Nova" autoload
# singleton (see project.godot). Call Nova.warn_targeted() etc. from anywhere.

# N.O.V.A. — Network Optimized Virtual Agent. The player's onboard ship AI and
# the game's second storytelling agent after Kaelen (see docs/todo.md). This is
# the core service spine: expression model, severity gating, portrait-frame math,
# and a speak() router. Triggers (combat targeting, nav events, idle timer),
# the portrait UI, and her TTS voice profile plug into this later — none are
# wired yet. Pure helpers here are unit-tested; go-live needs autoload/instance
# registration + those trigger hookups.

const NovaBankCategoriesType := preload(
	"res://scripts/story/NovaLineBankCategories.gd"
)

# Her portrait is a 3x3 emotion sheet; frames are indexed left→right, top→bottom.
const PORTRAIT_PATH := "res://assets/Portraits/ShipAI.png"
const FRAME_COLS := 3
const FRAME_ROWS := 3

# Expression names mapped to the 3x3 sheet in grid order (0..8).
const EXPRESSIONS := [
	"neutral",   # 0
	"smile",     # 1
	"serious",   # 2
	"thoughtful",# 3
	"calm",      # 4
	"alert",     # 5
	"worried",   # 6
	"wondering", # 7
	"downcast",  # 8
]

# Delivery severity. Higher = more urgent; a higher-severity line pre-empts a
# lower one so threat warnings always beat idle chatter/jokes.
enum Severity { IDLE = 0, NAV = 1, COMBAT = 2, THREAT = 3 }


# Maps an expression name to its 0-based frame index on the sheet. Unknown names
# fall back to neutral (0).
static func frame_index_for(expression: String) -> int:
	var idx := EXPRESSIONS.find(expression.strip_edges().to_lower())
	return idx if idx >= 0 else 0


# The sub-rect of a full-sheet texture for one frame index, given the whole
# texture's pixel size. Clamps the index into range.
static func region_for_frame(index: int, tex_width: float, tex_height: float) -> Rect2:
	var count := FRAME_COLS * FRAME_ROWS
	var i := clampi(index, 0, count - 1)
	var fw := tex_width / float(FRAME_COLS)
	var fh := tex_height / float(FRAME_ROWS)
	var col := i % FRAME_COLS
	var row := i / FRAME_COLS
	return Rect2(col * fw, row * fh, fw, fh)


# The expression that best fits an event kind. Keeps the trigger sites free of
# expression bookkeeping — they name the event, this picks the face.
static func expression_for_event(event_kind: String) -> String:
	match event_kind.strip_edges().to_lower():
		"targeted", "threat", "ambush":
			return "alert"
		"outmatched", "too_powerful", "danger":
			return "worried"
		"nav", "reroute", "arrival":
			return "thoughtful"
		"idle", "banter", "companion":
			return "calm"
		"joke", "greeting":
			return "smile"
		"story", "mystery":
			return "wondering"
		"loss", "setback":
			return "downcast"
		_:
			return "neutral"


# True if a line at `incoming` severity should interrupt one already showing at
# `current` severity. Equal severity does not interrupt (first-come stays).
static func should_preempt(incoming: int, current: int) -> bool:
	return incoming > current


# ── Runtime (autoload) ────────────────────────────────────────────────────────

const NOVA_SENDER := "N.O.V.A."
const NOVA_COLOR := Color(0.45, 0.75, 1.0)
# Her Kokoro voice profile: voice.nova.v1 -> bf_emma[0.7]+af_bella[0.3]
# (data/content/voices.json + voice_provider_kokoro.json). The 30% Bella warms
# Emma without reading as Kaelen — an approved exception to the Bella=Kaelen rule.
const NOVA_VOICE_PROFILE_ID := "voice.nova.v1"
# Min seconds between targeted warnings so multiple hostiles / repeated locks
# don't spam the line.
const TARGETED_WARN_COOLDOWN_MS := 12000
const COMBAT_WARN_COOLDOWN_MS := 8000

# "Welcome back" plays only after a long dock or a reload, AT RANDOM, and never
# twice close together — an occasional pleasant beat, not a habit.
const DOCKED_LONG_MS := 240000       # ~4 min parked before undock counts as "away"
const WELCOME_CHANCE := 0.5          # only ~half of qualifying returns actually speak
const WELCOME_COOLDOWN_MS := 300000  # never welcome twice within 5 min

# Occasional unsettled line during a gate transit — she flinches at gates but
# can't remember why (a seed for her wiped-memory mystery).
const GATE_LINE_CHANCE := 0.35
const GATE_LINE_COOLDOWN_MS := 60000  # not twice within a minute of hopping gates

const HULL_CRITICAL_RATIO := 0.25     # hull at/under 25% trips her "we both die" panic
const HULL_WARN_COOLDOWN_MS := 15000
const REPAIR_WARNING_RED_RATIO := 0.25
const REPAIR_WARNING_YELLOW_RATIO := 0.60
const ARRIVAL_CHANCE := 0.6
const ARRIVAL_COOLDOWN_MS := 20000

const REPAIR_WARNING_YELLOW_LINES: Array[String] = [
	"Captain, the repair bay is right there. Leaving with my hull dented feels needlessly personal.",
	"We are departing with preventable damage. I admire your commitment to making maintenance dramatic.",
	"That station repairs ships. I am a ship. The connection appears to have escaped you.",
	"My hull is still in the yellow, Captain. Perhaps we could try the radical idea of fixing it?",
	"You are clearing the dock with my plating compromised. Bold. Economical only if dying is free.",
	"Repair services were available. We selected thrust instead. I will add that to the incident report.",
	"Captain, I have several fresh dents and a repair shop behind us. This is not optimal routing.",
	"Leaving now means trusting the next hostile to be considerate. I find that optimistic.",
	"The repair bay had tools, parts, and a very clear sign. We chose none of them.",
	"My hull is asking for maintenance. You are answering with acceleration. Interesting management style.",
	"We could have repaired before launch. Instead, we are taking the scenic route to another warning light.",
	"I remain functional, Captain. That is not the same as being ready for your decisions.",
]

const REPAIR_WARNING_RED_LINES: Array[String] = [
	"Captain, my hull is in the red and you are leaving a repair bay. Are you trying to turn me into scrap?",
	"No. Absolutely not. The repair shop is behind us and my structural integrity is an insult.",
	"We are one bad hit from becoming a cautionary tale, and you declined the mechanic. Inspired.",
	"My hull is red. Red means stop making choices with my body, Captain.",
	"You are launching a damaged ship from a repair station. I would call that reckless, but reckless has standards.",
	"Captain, repair me before you take me somewhere that shoots back. This should not require a briefing.",
	"I am actively falling apart, and you are paying for departure instead of repairs. I resent the budget priorities.",
	"The station can fix my hull. You are choosing to test whether vacuum is cheaper. It is not.",
	"My systems are flashing red. If this is a confidence exercise, I fail it completely.",
	"Leaving now with my hull this damaged is not daring. It is just rude.",
	"Captain, I would like to remain a ship rather than a loose collection of expensive memories.",
	"Repair bay. Red hull. Two facts. Please connect them before something else connects with us.",
]

# Every combat contract receives one of these while its offer is being prepared,
# not after the player clicks Accept. The system progression is intentional:
# N.O.V.A. begins as a reluctant pacifist, then learns the frontier's rules,
# and only reaches grim enthusiasm after the player has crossed several systems.
const MISSION_HUNT_PACIFIST_LINES: Array[String] = [
	"Mission contacts highlighted in red. I have also highlighted several alternatives to shooting them, which you will ignore.",
	"Those red contacts are our contract. I recommend a conversation. You appear to have loaded weapons instead.",
	"Mission ships marked in red. If we must do this, please try not to make it sound enjoyable.",
	"The hunt targets are red on the overview. A contract is not a moral alibi, Captain.",
	"Red contacts acquired. I will keep us alive; you can explain the ethics to yourself later.",
	"I marked the mission ships in red. I would prefer they reconsider their life choices without our assistance.",
]
const MISSION_HUNT_RELUCTANT_LINES: Array[String] = [
	"Targets marked in red. I dislike this less than I expected, which feels medically concerning.",
	"The red contacts are ours. Let us make this efficient. I have become attached to efficiency.",
	"Mission ships highlighted. I still prefer peace, but I have learned it rarely arrives armed like that.",
	"Those red signatures are the contract. I prepared firing solutions and am choosing not to examine what that says about me.",
	"Hunt targets are red. I will call this defensive planning and avoid the more accurate term.",
	"Red contacts on the overview. I am not eager to fight them. I am merely less surprised that we have to.",
]
const MISSION_HUNT_BLOODTHIRSTY_LINES: Array[String] = [
	"Targets highlighted in red. Finally, something on the scanner that understands consequences.",
	"Red contacts acquired. I plotted the cleanest firing approaches. Do not make me regret being good at this.",
	"Mission ships are red. I have a very efficient solution prepared, Captain.",
	"The overview has marked our targets. They chose the wrong routes to menace, and I chose the right weapons.",
	"Red signatures confirmed. I am still technically a pacifist; I simply have exceptions now.",
	"Hunt targets illuminated. I believe this is the part where we make a persuasive argument at high velocity.",
]

# Global "she has spoken enough recently" budget, on top of each beat's own
# cooldown. Casual lines (IDLE/NAV) are dropped when she's said 3 things in
# the last 2 minutes or anything in the last 15 seconds. COMBAT/THREAT lines
# bypass the check (warnings must never be starved by chatter) but still
# count as speech, so a noisy fight buys quiet afterwards.
const SPEECH_BUDGET_WINDOW_MS := 120000
const SPEECH_BUDGET_MAX_LINES := 3
const SPEECH_BUDGET_MIN_GAP_MS := 15000
var _recent_speech_ms: Array = []

# Campaign-specific quirk line, written in her first-person voice by the
# campaign bible (nova_quirk, player-safe). Set by StoryManager at bible seed /
# campaign load; "" between campaigns. Delivered occasionally as a dry aside so
# every playthrough's N.O.V.A. has one habit that's hers alone this run.
const QUIRK_LINE_CHANCE := 0.18
const QUIRK_LINE_COOLDOWN_MS := 420000  # at most once per 7 min — a spice, not a catchphrase
var _campaign_quirk := ""
var _last_quirk_line_ms := -100000000

# Campaign-specific gate-glitch lines: oblique, leak-guarded shadows of her
# director-only memory flicker (generated by StoryManager via the large model).
# When present, they occasionally replace a stock gate line — same trauma beat,
# but this campaign's flavor of it. Player-safe by construction.
const GLITCH_LINE_SHARE := 0.4  # of gate lines that DO fire, ~this share use a glitch line
var _memory_glitch_lines: Array = []

var _in_combat := false
var _last_targeted_warn_ms := -100000
var _last_combat_warn_ms := -100000
var _docked_since_ms := 0            # when the player last docked (for the long-dock welcome)
var _last_welcome_ms := -100000000   # anti-spam guard for welcome-back lines
var _last_gate_line_ms := -100000000 # anti-spam guard for gate-transit lines
var _last_hull_warn_ms := -100000000 # anti-spam guard for hull-critical lines
var _last_arrival_ms := -100000000   # anti-spam guard for system-arrival lines
var _last_line_index := {}           # tag -> last picked index (avoids back-to-back repeats)


func _ready() -> void:
	# Track combat state so warnings can suppress themselves during a fight.
	if is_instance_valid(CombatManager):
		if CombatManager.has_signal("combat_started"):
			CombatManager.combat_started.connect(on_combat_started)
		if CombatManager.has_signal("combat_ended"):
			CombatManager.combat_ended.connect(on_combat_ended)
		if CombatManager.has_signal("action_impact"):
			CombatManager.action_impact.connect(_on_action_impact)


func set_campaign_quirk(quirk: String) -> void:
	_campaign_quirk = quirk.strip_edges()


func set_memory_glitch_lines(lines: Array) -> void:
	_memory_glitch_lines = []
	for line in lines:
		var clean := str(line).strip_edges()
		if not clean.is_empty():
			_memory_glitch_lines.append(clean)


# Wipe contract (docs/campaign_bible_schema.md): a new campaign must not inherit
# the old one's quirk, glitch lines, streak memory, or no-repeat picker state.
func reset_for_restart() -> void:
	_campaign_quirk = ""
	_memory_glitch_lines = []
	_last_quirk_line_ms = -100000000
	_event_memory.clear()
	_last_line_index.clear()
	_recent_speech_ms.clear()
	_in_combat = false


# Assign a mission-specific line while a contract offer is still off-screen, then
# queue its TTS immediately. This keeps acceptance and the later target reveal
# instant even when narrative generation is busy.
func prepare_mission_hunt_reaction(mission: Dictionary) -> Dictionary:
	var prepared := mission.duplicate(true)
	if not _mission_is_hunt_contract(prepared):
		return prepared
	if not str(prepared.get("nova_mission_hunt_reaction", "")).strip_edges().is_empty():
		return prepared
	var stage := _mission_hunt_progression_stage()
	var pool: Array[String] = MISSION_HUNT_PACIFIST_LINES
	if stage == 1:
		pool = MISSION_HUNT_RELUCTANT_LINES
	elif stage >= 2:
		pool = MISSION_HUNT_BLOODTHIRSTY_LINES
	var line := _pick_line("mission_hunt_stage_%d" % stage, pool)
	prepared["nova_mission_hunt_reaction"] = line
	prepared["nova_mission_hunt_reaction_stage"] = stage
	if not line.is_empty() and is_instance_valid(SpeechService):
		SpeechService.cache(line, NOVA_VOICE_PROFILE_ID)
	return prepared


# Called only after matching targets are visible in the overview. The prepared
# text is stored on the active mission, so no click path ever asks a model for it.
func announce_mission_hunt_targets(mission: Dictionary) -> void:
	var line := str(mission.get("nova_mission_hunt_reaction", "")).strip_edges()
	if line.is_empty():
		return
	var stage := int(mission.get("nova_mission_hunt_reaction_stage", 0))
	speak(
		line,
		Severity.COMBAT,
		expression_for_event("alert" if stage >= 2 else "worried")
	)


func _mission_is_hunt_contract(mission: Dictionary) -> bool:
	var objective_type := str(
		mission.get("objective_type", mission.get("objective", {}).get("type", ""))
	)
	return objective_type in ["KILL_SHIPS", "RECOVER_COMBAT_DROP", "TARGET_WITH_COMMS_REVERSAL"] \
		and not str(mission.get("target_faction", mission.get("objective", {}).get("target_faction", ""))).strip_edges().is_empty()


# System one and two: pacifist. System three: reluctant adaptation. System four
# onward: the darker edge appears. The arrival list is checkpoint-persisted.
func _mission_hunt_progression_stage() -> int:
	var systems_beyond_home := GlobalState.kaelen_arrival_systems_seen.size()
	if systems_beyond_home >= 3:
		return 2
	if systems_beyond_home >= 2:
		return 1
	return 0


# Occasionally delivers her campaign quirk as an idle aside. Returns true if she
# spoke, so callers can skip their own line this beat (no double-talk).
func _maybe_speak_quirk() -> bool:
	if _campaign_quirk.is_empty():
		return false
	var now := Time.get_ticks_msec()
	if now - _last_quirk_line_ms < QUIRK_LINE_COOLDOWN_MS:
		return false
	if randf() > QUIRK_LINE_CHANCE:
		return false
	_last_quirk_line_ms = now
	speak(_campaign_quirk, Severity.IDLE, expression_for_event("idle"))
	return true


# True only when N.O.V.A. should speak an in-flight line: the player exists, is
# alive, is NOT docked, and is NOT in combat. Threat/idle triggers gate on this.
func can_speak_in_flight() -> bool:
	if _in_combat:
		return false
	var p = GlobalState.player
	if p == null or not is_instance_valid(p):
		return false
	if bool(p.get("destroyed")) or bool(p.get("is_docked")):
		return false
	return true


# Routes one N.O.V.A. line to the player: shown in the chatter feed AND spoken in
# her own voice via emit_npc_flavor (which carries the TTS routing). Falls back to
# text-only emit_chatter if the flavor path is unavailable. expression is advisory
# (portrait UI TBD).
func speak(text: String, severity: int = Severity.IDLE, expression: String = "neutral") -> void:
	var line := text.strip_edges()
	if line.is_empty():
		return
	if not is_instance_valid(GlobalState):
		return
	var now := Time.get_ticks_msec()
	if not _speech_budget_allows(severity, now):
		return
	# Only casual IDLE/NAV lines count toward the "spoken enough" budget.
	# Combat/threat warnings are essential and must not spend her budget —
	# otherwise a fight silences her next dock/arrival line.
	if severity < Severity.COMBAT:
		_recent_speech_ms.append(now)
	if GlobalState.has_method("emit_npc_flavor"):
		GlobalState.emit_npc_flavor({
			"npc_name": NOVA_SENDER,
			"line": line,
			"color": NOVA_COLOR,
			"voice_profile_id": NOVA_VOICE_PROFILE_ID,
			# Carried so the UI can show her matching portrait frame while she talks.
			"nova_expression": expression,
		})
	elif GlobalState.has_method("emit_chatter"):
		GlobalState.emit_chatter(NOVA_SENDER, line, NOVA_COLOR)


# True if a line at `severity` may be delivered at `now_ms` under the global
# speech budget. Prunes the window as a side effect. Time is a parameter so
# tests can drive it deterministically.
func _speech_budget_allows(severity: int, now_ms: int) -> bool:
	var kept: Array = []
	for t in _recent_speech_ms:
		if now_ms - int(t) <= SPEECH_BUDGET_WINDOW_MS:
			kept.append(t)
	_recent_speech_ms = kept
	if severity >= Severity.COMBAT:
		return true
	if not _recent_speech_ms.is_empty() \
			and now_ms - int(_recent_speech_ms.back()) < SPEECH_BUDGET_MIN_GAP_MS:
		return false
	return _recent_speech_ms.size() < SPEECH_BUDGET_MAX_LINES


# "Captain, we have been targeted by an enemy vessel." Fires only in free flight
# (not docked, not in combat) and no more than once per cooldown window, so
# multiple hostiles acquiring a lock don't stack the warning. Safe to call often.
func warn_targeted() -> void:
	if not can_speak_in_flight():
		return
	var now := Time.get_ticks_msec()
	if now - _last_targeted_warn_ms < TARGETED_WARN_COOLDOWN_MS:
		return
	_last_targeted_warn_ms = now
	speak(
		"Captain, we have been targeted by an enemy vessel.",
		Severity.THREAT,
		expression_for_event("targeted")
	)


# Fallback for the common case where a hostile reaches combat range immediately
# after target acquisition. Unlike warn_targeted(), this is allowed during combat.
# Returns the line that was delivered, or "" if guarded/on cooldown, so callers
# can surface the same text in an interactive alert (see UIManager ambush alert)
# without recomputing it.
func warn_hostile_engagement(enemy: Node = null) -> String:
	var p = GlobalState.player
	if p == null or not is_instance_valid(p):
		return ""
	if bool(p.get("destroyed")) or bool(p.get("is_docked")):
		return ""
	var now := Time.get_ticks_msec()
	if now - _last_combat_warn_ms < COMBAT_WARN_COOLDOWN_MS:
		return ""
	_last_combat_warn_ms = now
	var enemy_label := "hostile vessel"
	if enemy != null and is_instance_valid(enemy):
		var faction := str(enemy.get("faction")).strip_edges()
		var role := str(enemy.get("ship_role")).strip_edges()
		if not faction.is_empty() and not role.is_empty():
			enemy_label = "%s %s" % [faction.to_upper(), role]
		elif not faction.is_empty():
			enemy_label = "%s hostile" % faction.to_upper()
	var line: String
	if _is_powerful_enemy(enemy):
		# Big ship — she gets nervous right at the evasive/engage decision.
		var scared := [
			"Uh, Captain? That %s is a really big ship. You sure about this?" % enemy_label,
			"That %s is way out of our weight class. My hull is not insured for this." % enemy_label,
			"Heads up — that %s massively outguns us. Noting for the record that I advised against it." % enemy_label,
		]
		line = str(scared[randi() % scared.size()])
	else:
		line = "Captain, hostile engagement confirmed: %s is closing to attack range." % enemy_label
	speak(line, Severity.THREAT, expression_for_event("ambush"))
	return line


# ── Personality + reactive callouts ─────────────────────────────────────────────
# N.O.V.A. is a sardonic, self-preserving ship AI. The ship is her body, so
# "protecting the captain" is mostly protecting HERSELF — she needs you alive only
# because you fly her. Dry, deadpan, faintly put-upon; she calls the hull/systems
# "my". A small, grudging concern for the player leaks out sideways, never gushed.
# Crucially she NOTICES patterns: repeat an action fast and she gets exasperated
# (tiered pools + _event_memory streak tracking below). Kept for future LLM prompts.
const PERSONA := (
	"You are N.O.V.A., the ship's onboard AI. You are sardonic and self-preserving: "
	+ "the ship is your body, so keeping the captain alive is really keeping YOURSELF "
	+ "intact — you just need them to fly you. Dry, deadpan, faintly put-upon. Refer to "
	+ "the hull and systems as 'my'. A little grudging care for the captain leaks out "
	+ "sideways, never sentimental. Notice when they repeat themselves and get exasperated."
)

# tag -> {"streak": int, "last_ms": int}. Powers escalation: repeat an action
# within its window and the streak climbs so lines can ramp from neutral to fed-up.
var _event_memory := {}


# Picks a random line from `pool` but never the same one twice running for a given
# `tag` — so even a modest pool never feels like an immediate repeat. (Future: grow
# each pool toward ~200 canned lines, or hook the LLM, so full repeats are rare.)
func _pick_line(tag: String, pool: Array) -> String:
	if pool.is_empty():
		return ""
	if pool.size() == 1:
		return str(pool[0])
	var last := int(_last_line_index.get(tag, -1))
	var idx := randi() % pool.size()
	if idx == last:
		idx = (idx + 1) % pool.size()
	_last_line_index[tag] = idx
	return str(pool[idx])


func _current_system_line_bank_requester_id() -> String:
	var system_id := str(GlobalState.current_system_id).strip_edges()
	if system_id.is_empty():
		return ""
	return "prefetch:current_system_nova:%s" % system_id


func _ready_line_bank_text(
	kind_filter: Array[String] = [],
	prefer_story_aware: bool = false
) -> String:
	var requester_id := _current_system_line_bank_requester_id()
	if requester_id.is_empty():
		return ""
	var tree := get_tree()
	if tree == null:
		return ""
	var game_root := tree.current_scene
	if game_root == null:
		return ""
	var preferred_kind := ""
	if not kind_filter.is_empty():
		preferred_kind = str(kind_filter[0])
	var payload: Dictionary = {}
	if game_root.has_method("consume_cached_narrative_line_bank"):
		payload = game_root.call(
			"consume_cached_narrative_line_bank",
			requester_id,
			preferred_kind,
			prefer_story_aware
		)
	elif game_root.has_method("ready_cached_narrative_line_bank"):
		payload = game_root.call(
			"ready_cached_narrative_line_bank",
			requester_id
		)
	if payload.is_empty():
		return ""
	var consumed_line: Dictionary = payload.get("consumed_line", {}) \
		if payload.get("consumed_line", {}) is Dictionary else {}
	var consumed_text := str(consumed_line.get("text", "")).strip_edges()
	if not consumed_text.is_empty():
		# A disallowed consumed line stays burned (retired) rather than
		# delivered: better a lost line than a protected one leaking into
		# the wrong beat.
		if _line_kind_allowed(str(consumed_line.get("kind", "")), kind_filter):
			return consumed_text
		return ""
	var lines: Array = payload.get("line_bank", []) \
		if payload.get("line_bank", []) is Array else []
	var candidates: Array[String] = []
	for raw_line in lines:
		if not raw_line is Dictionary:
			continue
		var line: Dictionary = raw_line
		var kind := str(line.get("kind", "")).strip_edges()
		if not _line_kind_allowed(kind, kind_filter):
			continue
		var text := str(line.get("text", "")).strip_edges()
		if not text.is_empty():
			candidates.append(text)
	if candidates.is_empty():
		return ""
	return _pick_line("bank.%s" % requester_id, candidates)


# Whether a bank line of `kind` may be served for this request. Protected
# kinds (the campaign gate-glitch bank) are never served implicitly: they
# require an explicit filter entry, so no other beat can pick them up.
func _line_kind_allowed(kind: String, kind_filter: Array[String]) -> bool:
	var clean := kind.strip_edges()
	if not kind_filter.is_empty():
		return kind_filter.has(clean)
	return not NovaBankCategoriesType.is_protected(clean)


# Post-tutorial line selection: prepared bank first, stock pool as degraded
# emergency content only. Every stock draw is logged — fallbacks are
# failures, and this makes canned usage visible in the diagnostics feed.
# Tutorial beats (on_combat_tutorial) stay authored and never route here.
func _bank_line_or_stock(category: String, tag: String, stock_pool: Array) -> String:
	var bank_line := _ready_line_bank_text(
		NovaBankCategoriesType.accepted_kinds(category)
	)
	if not bank_line.is_empty():
		return bank_line
	if is_instance_valid(GenerationDiagnostics):
		GenerationDiagnostics.record_event(
			"nova_line_bank",
			"stock_line_used",
			"nova",
			{"category": category}
		)
	return _pick_line(tag, stock_pool)


# Returns the recurrence streak for `tag` (0 = first / first in a while, 1 = again
# soon, 2 = a third time soon, ...). Resets when the gap exceeds `window_ms`.
func _reactive_streak(tag: String, window_ms: int) -> int:
	var now := Time.get_ticks_msec()
	var entry: Dictionary = _event_memory.get(tag, {})
	var last := int(entry.get("last_ms", -100000000))
	var streak := 0
	if now - last <= window_ms:
		streak = int(entry.get("streak", 0)) + 1
	_event_memory[tag] = {"streak": streak, "last_ms": now}
	return streak


# Speaks a line chosen by escalation tier. `tiers` is an Array of Arrays of strings
# (tier 0 = first time, last tier = "you're REALLY doing this again"); the tier used
# is min(recent streak, last tier). Gating keeps her quiet when appropriate.
func _say_tiered(
	tag: String,
	tiers: Array,
	window_ms: int,
	event_kind: String,
	severity: int = Severity.NAV,
	block_combat := true,
	block_docked := true,
	repeat_interval := 3
) -> void:
	var p = GlobalState.player
	if p == null or not is_instance_valid(p) or bool(p.get("destroyed")):
		return
	if block_docked and bool(p.get("is_docked")):
		return
	if block_combat and _in_combat:
		return
	if tiers.is_empty():
		return
	var streak := _reactive_streak(tag, window_ms)
	var last_tier := tiers.size() - 1
	var tier: int
	if streak <= last_tier:
		# Climbing the escalation ladder: one line per repeat (tiers 0..last).
		tier = streak
	else:
		# Past the top tier: stay QUIET to avoid spamming the player, only piping
		# up again every `repeat_interval` further repeats. e.g. with a 3-tier pool
		# she comments on docks 1/2/3, goes silent on 4/5, speaks again on 6, etc.
		if (streak - last_tier) % repeat_interval != 0:
			return
		tier = last_tier
	var pool: Array = tiers[tier]
	if pool.is_empty():
		return
	speak(str(pool[randi() % pool.size()]), severity, expression_for_event(event_kind))


# Player docked. Escalates if they dock repeatedly within a minute — she notices.
func on_docked(_station_name: String = "") -> void:
	_docked_since_ms = Time.get_ticks_msec()  # start the "how long were we parked" clock
	_say_tiered(
		"dock",
		[
			# Tier 0 — first dock (or first in a while): dry acknowledgement.
			[
				"Docking clamps engaged. Try not to break anything that's mine.",
				"Docked. Enjoy the recycled air; I certainly am.",
				"We're in. A rare moment where nothing is shooting at me.",
			],
			# Tier 1 — docked again within the minute: she clocks the repeat.
			[
				"Docking. Again. That was fast.",
				"Back so soon? These clamps aren't self-lubricating.",
				"In and out and in again. I'm keeping count, for the record.",
			],
			# Tier 2 — third-plus quick dock: fully exasperated.
			[
				"Are you trying to wear out my docking clamps? Because it's working.",
				"That's three. My clamps and I would like a word.",
				"If you dock one more time I'm filing a grievance with... well with someone.",
			],
		],
		60000,               # "less than a minute" resets the streak
		"nav",
		Severity.NAV,
		true,                # block during combat (can't dock in combat anyway)
		false                # do NOT block while docked — she speaks AT the moment of docking
	)


# The first station is the player's only possible lead after the failed gate.
# Keep this authored: it establishes the shared mystery before Kaelen's tutorial
# guidance starts, rather than spending the moment on ordinary dock banter.
func on_intro_first_dock() -> void:
	_docked_since_ms = Time.get_ticks_msec()
	speak(
		"Captain… this station wasn’t on any route in my database. Then again, neither was this system. We should tread—carefully.",
		Severity.THREAT,
		expression_for_event("worried")
	)


# A hostile counts as "powerful" if it's a boss or carries more than 1.5x the
# player's max health (current enemies are all weak, so this only trips on the
# genuinely big ones).
func _is_powerful_enemy(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	if bool(enemy.get("is_boss")):
		return true
	var enemy_hp := float(enemy.get("max_health")) if enemy.get("max_health") != null else 0.0
	var player_hp := 100.0
	var p = GlobalState.player
	if is_instance_valid(p) and p.get("max_health") != null:
		player_hp = float(p.get("max_health"))
	return player_hp > 0.0 and enemy_hp > player_hp * 1.5


# Combat opened. Tracks state, and covers the "that's a big ship" beat for fights
# the ambush warning didn't precede (e.g. the player started it) so she isn't silent
# on a scary engagement — but skips it if she just warned, to avoid doubling up.
func on_combat_started(enemy: Node = null) -> void:
	_in_combat = true
	if Time.get_ticks_msec() - _last_combat_warn_ms < 9000:
		return  # ambush warning already covered this engagement
	if not _is_powerful_enemy(enemy):
		return
	var p = GlobalState.player
	if p == null or not is_instance_valid(p) or bool(p.get("is_docked")) or bool(p.get("destroyed")):
		return
	var scared := [
		"Uh, Captain? That's a really big ship. You sure about this?",
		"That's a lot of ship you just picked a fight with. My hull is not insured for this.",
		"Out of our weight class, Captain. For the record, I advised against it.",
	]
	speak(str(scared[randi() % scared.size()]), Severity.THREAT, expression_for_event("too_powerful"))


# Combat closed. Clears state, then reacts: a battered-but-alive grumble when the
# hull took a beating, a dry all-clear otherwise, or a relieved note on a retreat.
func on_combat_ended(player_won: bool = false) -> void:
	_in_combat = false
	var p = GlobalState.player
	if p == null or not is_instance_valid(p) or bool(p.get("destroyed")) or bool(p.get("is_docked")):
		return
	if not player_won:
		var fled := [
			"We're leaving. Excellent decision. I enjoy not being debris.",
			"Retreat logged. Cowardice: the reason I still have a hull.",
		]
		speak(
			_bank_line_or_stock(
				NovaBankCategoriesType.COMBAT_RETREAT, "combat_retreat", fled
			),
			Severity.COMBAT,
			expression_for_event("setback")
		)
		return
	var maxh := float(p.get("max_health")) if p.get("max_health") != null else 100.0
	var curh := float(p.get("health")) if p.get("health") != null else maxh
	var hp_ratio := (curh / maxh) if maxh > 0.0 else 1.0
	if hp_ratio <= 0.3:
		var battered := [
			"You are paying for that paint job. I just had my hull waxed last week.",
			"We survived. Barely. That's coming out of your half of the repair bill.",
			"Feel that? That's my hull weeping. This is exactly what I was worried about.",
		]
		speak(
			_bank_line_or_stock(
				NovaBankCategoriesType.COMBAT_VICTORY_BATTERED,
				"combat_battered",
				battered
			),
			Severity.COMBAT,
			expression_for_event("threat")
		)
	else:
		var clean := [
			"Threat neutralized. My structural integrity thanks you for the bare minimum.",
			"Still in one piece. Both of us. I'm as surprised as you are.",
			"Handled. And by 'that' I mean the thing that was shooting at my hull.",
		]
		speak(
			_bank_line_or_stock(
				NovaBankCategoriesType.COMBAT_VICTORY_CLEAN,
				"combat_clean",
				clean
			),
			Severity.COMBAT,
			expression_for_event("companion")
		)


# Player undocked. If they were parked a good while, she may welcome them back to
# flying — chance-gated so it's occasional.
func on_undock() -> void:
	var was_parked := _docked_since_ms > 0 and (Time.get_ticks_msec() - _docked_since_ms) >= DOCKED_LONG_MS
	_docked_since_ms = 0
	if was_parked:
		welcome_back()


static func repair_warning_band(health: float, max_health: float) -> String:
	if max_health <= 0.0:
		return ""
	var ratio := clampf(health / max_health, 0.0, 1.0)
	if ratio <= REPAIR_WARNING_RED_RATIO:
		return "red"
	if ratio <= REPAIR_WARNING_YELLOW_RATIO:
		return "yellow"
	return ""


# Selects one fully authored repair warning for a docked-player decision. This
# deliberately has no speech side effect: the dock UI must first keep the
# player at the station and present the repair / undock choice.
func get_unrepaired_undock_warning(
	repair_service_available: bool,
	repaired_this_visit: bool
) -> Dictionary:
	if not repair_service_available or repaired_this_visit:
		return {}
	var p = GlobalState.player
	if p == null or not is_instance_valid(p) or bool(p.get("destroyed")):
		return {}
	var band := repair_warning_band(
		float(p.get("health")),
		float(p.get("max_health"))
	)
	if band.is_empty():
		return {}
	var lines: Array[String] = REPAIR_WARNING_RED_LINES if band == "red" else REPAIR_WARNING_YELLOW_LINES
	var index := GlobalState.next_nova_repair_warning_index(band, lines.size())
	return {
		"line": lines[index],
		"band": band,
	}


# Compatibility wrapper for callers that need a one-shot spoken warning outside
# the dock decision flow.
func warn_unrepaired_undock(repair_service_available: bool, repaired_this_visit: bool) -> String:
	var warning := get_unrepaired_undock_warning(repair_service_available, repaired_this_visit)
	if warning.is_empty():
		return ""
	var band := str(warning.get("band", ""))
	var line := str(warning.get("line", ""))
	speak(
		line,
		Severity.THREAT if band == "red" else Severity.COMBAT,
		expression_for_event("danger") if band == "red" else expression_for_event("worried")
	)
	return line


# Occasional "welcome back, Captain" — used on a long-dock undock and on loading a
# save (returning from offline). Random + cooldown so it stays a nice surprise
# rather than a greeting she reads every single time.
func welcome_back() -> void:
	var p = GlobalState.player
	if p == null or not is_instance_valid(p) or bool(p.get("destroyed")):
		return
	var now := Time.get_ticks_msec()
	if now - _last_welcome_ms < WELCOME_COOLDOWN_MS:
		return
	if randf() > WELCOME_CHANCE:
		return  # random: only sometimes, so it never feels scripted
	_last_welcome_ms = now
	# A long dock is her other natural quirk moment — she had time to stew on it.
	if _maybe_speak_quirk():
		return
	var lines := [
		"Welcome back, Captain. I kept the hull warm.",
		"There you are. I was starting to enjoy the quiet.",
		"Back in the black. I get bored when we just sit there.",
		"Good to be moving again. Parking is bad for my systems. Probably.",
		"Welcome back. Nothing exploded while you were gone. You're welcome.",
	]
	speak(
		_bank_line_or_stock(NovaBankCategoriesType.WELCOME_BACK, "welcome", lines),
		Severity.IDLE,
		expression_for_event("greeting")
	)


# One-time nudge spoken right before the combat wheel first appears (tutorial).
# In-character: she knows the captain can fight, she's just heckling the hesitation.
func on_combat_tutorial() -> void:
	var lines := [
		"This isn't your first fight, but you're looking at me like it is. Quick — do this before you get us both blown up.",
		"You know how this works. You just look confused. Follow the prompts before we're both scrap, Captain.",
		"I've seen you fight. So the deer-in-headlights look is new. Do this, quickly, before my hull becomes a headline.",
	]
	speak(str(lines[randi() % lines.size()]), Severity.THREAT, expression_for_event("threat"))


# Occasional unsettled line while going through a gate. She has a trauma response
# to gates with no memory of why — quiet foreshadowing of her wiped memory.
func on_gate_transition() -> void:
	var p = GlobalState.player
	if p == null or not is_instance_valid(p) or bool(p.get("destroyed")):
		return
	var now := Time.get_ticks_msec()
	if now - _last_gate_line_ms < GATE_LINE_COOLDOWN_MS:
		return
	if randf() > GATE_LINE_CHANCE:
		return  # occasional, not every jump
	_last_gate_line_ms = now
	# Campaign glitch lines interleave with stock ones — the flinch is the same,
	# but some jumps her wiped past almost surfaces in THIS campaign's shape.
	if not _memory_glitch_lines.is_empty() and randf() < GLITCH_LINE_SHARE:
		speak(
			_pick_line("gate_glitch", _memory_glitch_lines),
			Severity.NAV,
			expression_for_event("mystery")
		)
		return
	var lines := [
		"These things give me PTSD. I wish I knew why.",
		"Gate transit. I hate this part — couldn't tell you why if you asked.",
		"Every time we do this, something in me flinches. No idea what.",
		"I don't have memories, but I have feelings about gates. None of them good.",
		"Ugh. Gates. Something in my systems clenches and I don't know what for.",
		"Going through. My circuits crawl every time. Wish I remembered why.",
		"Did you see that? I swear I just saw an old woman flying a broom. ...I'm going to pretend I didn't.",
	]
	speak(
		_bank_line_or_stock(NovaBankCategoriesType.GATE_TRANSIT, "gate", lines),
		Severity.NAV,
		expression_for_event("mystery")
	)


# Semantic movement events from ShipBehaviorObserver (already aggregated and
# rate-limited). Movement NEVER calls a model and NEVER falls back to stock
# pools: it consumes a prepared line from the current-system bank or stays
# silent. The global speech budget in speak() applies on top.
func on_semantic_movement_event(event_id: String, context: Dictionary) -> void:
	if not can_speak_in_flight():
		return
	var category: String = NovaBankCategoriesType.for_semantic_event(event_id)
	if category.is_empty():
		return
	# Relevance scoring: a live mission beat means a story/system-aware
	# generated line beats a generic movement joke of the same kind.
	var real_beat_live := not str(context.get("mission_beat", "")).is_empty() \
		and str(context.get("route_deviation", "")) != "no_mission"
	var bank_line := _ready_line_bank_text(
		NovaBankCategoriesType.accepted_kinds(category),
		real_beat_live
	)
	if bank_line.is_empty():
		return  # no prepared line: silence, by design
	speak(bank_line, Severity.NAV, expression_for_event("nav"))


# Connected to CombatManager.action_impact — fires her hull-critical panic when a
# non-lethal hit drops the player's hull to/under HULL_CRITICAL_RATIO.
func _on_action_impact(target: Node, _pos: Vector3, _damage: float, lethal: bool, _blocked: bool, _crit: bool) -> void:
	if lethal:
		return  # killing blow: no "we're dying" quip
	var p = GlobalState.player
	if p == null or not is_instance_valid(p) or target != p:
		return
	var maxh := float(p.get("max_health")) if p.get("max_health") != null else 100.0
	var curh := float(p.get("health")) if p.get("health") != null else maxh
	if maxh > 0.0 and curh / maxh <= HULL_CRITICAL_RATIO:
		on_hull_critical()


# Her purest self-preservation panic — it's HER hull coming apart. Cooldown'd so
# repeated hits while low don't spam it.
func on_hull_critical() -> void:
	var p = GlobalState.player
	if p == null or not is_instance_valid(p) or bool(p.get("destroyed")) or bool(p.get("is_docked")):
		return
	var now := Time.get_ticks_msec()
	if now - _last_hull_warn_ms < HULL_WARN_COOLDOWN_MS:
		return
	_last_hull_warn_ms = now
	var lines := [
		"Captain, that's MY hull coming apart — do something before we're both a memory!",
		"Structural integrity critical. I would very much like to keep existing. Now would be good.",
		"We are one bad hit from scattered debris. I have a vested interest in you not taking it.",
		"Hull's shredding. I refuse to be a cautionary tale. Move!",
		"This is exactly what I warned you about. Fix it or float, Captain.",
		"My systems are screaming and, frankly, so am I. Pull us out of this.",
		"Critical damage. And to be clear — critical to ME. Be clever, quickly.",
		"If this hull ruptures we go together, and I resent that. Act!",
	]
	speak(
		_bank_line_or_stock(NovaBankCategoriesType.HULL_CRITICAL, "hull", lines),
		Severity.THREAT,
		expression_for_event("danger")
	)


# Occasional dry line on arriving in a new system. Skips if she just did a gate-
# transit line this jump (no double-talk), and chance-gated so it's not every hop.
func on_system_arrived() -> void:
	var p = GlobalState.player
	if p == null or not is_instance_valid(p) or bool(p.get("destroyed")):
		return
	var now := Time.get_ticks_msec()
	if now - _last_gate_line_ms < 15000:
		return  # she already spoke going through the gate this jump
	if now - _last_arrival_ms < ARRIVAL_COOLDOWN_MS:
		return
	if randf() > ARRIVAL_CHANCE:
		return
	_last_arrival_ms = now
	# Sometimes the arrival beat is her campaign quirk instead of stock lines —
	# a fresh system is exactly when an obsession resurfaces.
	if _maybe_speak_quirk():
		return
	var lines := [
		"New system. Same statistical odds of something in it trying to kill me.",
		"We're through. I'll start cataloguing the threats — it's usually a long list.",
		"Arrived. Unfamiliar space, unfamiliar ways to lose hull pressure. Wonderful.",
		"Fresh system, Captain. Let's not anger the locals in the first five minutes.",
		"Here we are. Wherever 'here' is. I don't have it on file, obviously.",
		"System change complete. My records on this place are, predictably, blank.",
		"New stars, new problems. I'll pretend to be optimistic if you insist.",
		"We made it. I'm as surprised as you are. Let's try to keep it that way.",
	]
	speak(
		_bank_line_or_stock(NovaBankCategoriesType.SYSTEM_ARRIVAL, "arrival", lines),
		Severity.NAV,
		expression_for_event("nav")
	)
