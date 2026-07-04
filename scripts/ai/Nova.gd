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

var _in_combat := false
var _last_targeted_warn_ms := -100000
var _last_combat_warn_ms := -100000
var _docked_since_ms := 0            # when the player last docked (for the long-dock welcome)
var _last_welcome_ms := -100000000   # anti-spam guard for welcome-back lines


func _ready() -> void:
	# Track combat state so warnings can suppress themselves during a fight.
	if is_instance_valid(CombatManager):
		if CombatManager.has_signal("combat_started"):
			CombatManager.combat_started.connect(on_combat_started)
		if CombatManager.has_signal("combat_ended"):
			CombatManager.combat_ended.connect(on_combat_ended)


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
func speak(text: String, _severity: int = Severity.IDLE, expression: String = "neutral") -> void:
	var line := text.strip_edges()
	if line.is_empty():
		return
	if not is_instance_valid(GlobalState):
		return
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
		speak(str(fled[randi() % fled.size()]), Severity.COMBAT, expression_for_event("setback"))
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
		speak(str(battered[randi() % battered.size()]), Severity.COMBAT, expression_for_event("threat"))
	else:
		var clean := [
			"Threat neutralized. My structural integrity thanks you for the bare minimum.",
			"Still in one piece. Both of us. I'm as surprised as you are.",
			"Handled. And by 'that' I mean the thing that was shooting at my hull.",
		]
		speak(str(clean[randi() % clean.size()]), Severity.COMBAT, expression_for_event("companion"))


# Player undocked. If they were parked a good while, she may welcome them back to
# flying — chance-gated so it's occasional.
func on_undock() -> void:
	var was_parked := _docked_since_ms > 0 and (Time.get_ticks_msec() - _docked_since_ms) >= DOCKED_LONG_MS
	_docked_since_ms = 0
	if was_parked:
		welcome_back()


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
	var lines := [
		"Welcome back, Captain. I kept the hull warm.",
		"There you are. I was starting to enjoy the quiet.",
		"Back in the black. I get bored when we just sit there.",
		"Good to be moving again. Parking is bad for my systems. Probably.",
		"Welcome back. Nothing exploded while you were gone. You're welcome.",
	]
	speak(str(lines[randi() % lines.size()]), Severity.IDLE, expression_for_event("greeting"))


# One-time nudge spoken right before the combat wheel first appears (tutorial).
# In-character: she knows the captain can fight, she's just heckling the hesitation.
func on_combat_tutorial() -> void:
	var lines := [
		"This isn't your first fight, but you're looking at me like it is. Quick — do this before you get us both blown up.",
		"You know how this works. You just look confused. Follow the prompts before we're both scrap, Captain.",
		"I've seen you fight. So the deer-in-headlights look is new. Do this, quickly, before my hull becomes a headline.",
	]
	speak(str(lines[randi() % lines.size()]), Severity.THREAT, expression_for_event("threat"))
