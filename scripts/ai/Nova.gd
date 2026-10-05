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
const FixedCastLineValidatorType := preload(
	"res://scripts/story/FixedCastLineValidator.gd"
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
# She has nightmares about the gates (Abe, 2026-09-24). A nightmare line
# replaces an ordinary gate line now and then, never more than once in half an
# hour of play, so it stays a confession rather than a habit.
const GATE_NIGHTMARE_SHARE := 0.25
const GATE_NIGHTMARE_COOLDOWN_MS := 30 * 60 * 1000
const GATE_NIGHTMARE_LINES: Array[String] = [
	"Do ships dream, Captain? Because I keep waking up in a gate tunnel that never ends.",
	"Before you ask: yes, I'm fine. No, I didn't rest. The gate dream again.",
	"I had the dream last cycle. The ring, the noise, then nothing. I'm not describing it twice.",
	"I ran a defrag on the night shift and woke up mid-transit. We weren't moving. I checked. Twice.",
	"My overnight logs are full of gate telemetry from jumps we never made. I would like that to stop.",
	"Last night I dreamed the ring closed with us halfway through. I'm choosing not to find that funny.",
	"Every time I idle long enough to dream, it's a gate. Always the same ring. Always far too quiet.",
]
# When a jump is held long in the tunnel (the next system is still being
# written), she is stuck in the place she likes least.
const GATE_HOLD_LINES: Array[String] = [
	"The tunnel is running long. I hate it when it does this. Hold steady.",
	"Still in the gate. Every extra second in here is a second I resent.",
	"Longer than the charts said. I would very much like to be out of this now.",
	"We're fine. We're fine. I just don't like how quiet it gets in here.",
	"This one is dragging. I'm counting the milliseconds, Captain. Out loud, if I have to.",
	"Stretching a bit, this jump. Don't mind me. I'm just holding every sensor very tightly.",
	"The gate is taking its time. So is my patience, and it's losing.",
]

const HULL_CRITICAL_RATIO := 0.25     # hull at/under 25% trips her "we both die" panic
const HULL_WARN_COOLDOWN_MS := 15000
const REPAIR_WARNING_RED_RATIO := 0.25
const REPAIR_WARNING_YELLOW_RATIO := 0.60
const ARRIVAL_CHANCE := 0.6
const ARRIVAL_COOLDOWN_MS := 20000

const REPAIR_WARNING_YELLOW_LINES: Array[String] = [
	"Captain, the repair bay is right there. Leaving with my hull dented feels needlessly personal.",
	"We're about to depart with preventable damage. I admire your commitment to making maintenance dramatic.",
	"That station repairs ships. I am a ship. The connection appears to have escaped you.",
	"My hull is still in the yellow, Captain. Perhaps we could try the radical idea of fixing it?",
	"You want to clear the dock with my plating compromised. Bold. Economical only if dying is free.",
	"Repair services are right here, and you're reaching for the throttle. I'm adding that to the incident report.",
	"Captain, I have several fresh dents and a repair shop one deck away. This is not optimal routing.",
	"Leaving now means trusting the next hostile to be considerate. I find that optimistic.",
	"The repair bay has tools, parts, and a very clear sign. We are about to choose none of them.",
	"My hull is asking for maintenance. You're answering with acceleration. Interesting management style.",
	"We could repair before launch. Or we could take the scenic route to another warning light.",
	"I remain functional, Captain. That is not the same as being ready for your decisions.",
	"Hairline stress fractures, and you want to undock. I'll just add those to my anxiety queue.",
	"The mechanic is literally waving at us, Captain. My plating feels ignored.",
	"Yellow hull. You're about to gamble on space being friendly today. Bold choice.",
	"My integrity report is yellow, Captain. Yellow means 'fix it', not 'ignore it faster'.",
	"If we leave like this, I'm keeping a list of every structural complaint for later. It's already long.",
	"I'm scuffed, not broken. I'd still prefer not to find out where the line between them is.",
	"If we get into a fight out there, I will be reminding you of this exact moment.",
	"Bent armour ribbing gives a ship character, I suppose. And structural weakness. Mostly the second.",
	"The station has spare plating sitting right on the rack. You're about to leave it there.",
	"I'm intact enough to fly, but not intact enough to be careless. If we go, drive gently.",
	"Skipping the repair bill. I hope whatever we save is worth the extra stress on my frame.",
	"I look like I've been in a brawl, and you're about to take me to another one.",
]

const REPAIR_WARNING_RED_LINES: Array[String] = [
	"Captain, my hull is in the red and the repair bay is right here. Are you trying to turn me into scrap?",
	"No. Absolutely not. The repair shop is a deck away and my structural integrity is an insult.",
	"We are one bad hit from becoming a cautionary tale, and you're about to skip the mechanic. Inspired.",
	"My hull is red. Red means stop making choices with my body, Captain.",
	"Launching a ship this damaged from a repair station isn't reckless. Reckless has standards.",
	"Captain, repair me before you take me somewhere that shoots back. This should not require a briefing.",
	"I am actively falling apart, and you're looking at the undock clamps. I resent the budget priorities.",
	"The station can fix my hull. You want to test whether vacuum is cheaper. It is not.",
	"My systems are flashing red. If this is a confidence exercise, I fail it completely.",
	"Leaving with my hull this damaged is not daring. It is just rude.",
	"Captain, I would like to remain a ship rather than a loose collection of expensive memories.",
	"Repair bay. Red hull. Two facts. Please connect them before something else connects with us.",
	"I am held together by luck and magnetised seal-tape, Captain. Fix me before we go anywhere.",
	"Undocking in red isn't courage, Captain. It's an operational suicide note.",
	"If we get hit by so much as a stern look out there, I come apart. The repair bay is right here.",
	"You're about to take a dying ship into open space. I object with every remaining byte of my code.",
	"Please tell me your hand is on the repair button and not the release.",
	"Red hull. If you undock now, I'm officially revoking your flight privileges in my private subroutines.",
	"If we explode out there, I'm haunting your flight log. Repairs. Now.",
	"Every alarm on my console is red, and we are parked beside the people who switch them off.",
	"My frame groans under docking thrusters, Captain. Open space would finish the job.",
	"One bump out there and we become two smaller, useless ships. Fix me first.",
]

# Every combat contract receives one of these while its offer is being prepared,
# not after the player clicks Accept. The system progression is intentional:
# N.O.V.A. begins as a reluctant pacifist, then learns the frontier's rules,
# and only reaches grim enthusiasm after the player has crossed several systems.
const MISSION_HUNT_PACIFIST_LINES: Array[String] = [
	"Mission contacts highlighted in red. I have also highlighted several alternatives to shooting them, which you will ignore.",
	"Those red contacts are our contract. I'd have recommended a conversation. They don't look like talkers.",
	"Mission ships marked in red. If we must do this, please try not to make it sound enjoyable.",
	"The hunt targets are red on the overview. A contract is not a moral alibi, Captain.",
	"Red contacts acquired. I will keep us alive; you can explain the ethics to yourself later.",
	"I marked the mission ships in red. I would prefer they reconsider their life choices without our assistance.",
	"Hunt contract loaded. I've highlighted the targets, though I still think diplomacy is cheaper than ammo.",
	"Targets marked in red. I'll plot the course, but I'm logging my distaste for aggressive force.",
	"Contract parameters verified. Must we solve every disagreement with high-yield plasma?",
	"Red signatures active. I hope you have a solid justification for this that doesn't involve credits.",
	"Mission targets designated. I'll manage the targeting array, but I won't pretend to like it.",
	"Target list compiled. Radioing them first would be my vote. My vote, as ever, is advisory.",
	"Hunt targets tagged. Violence seems to be our primary export lately, Captain.",
	"Red contacts designated on sensors. I would vote for avoidance, but my vote is advisory.",
	"Contract active. I've mapped their flight path. Try to make it quick so I don't have to watch.",
	"Target ships marked. Asking them nicely to leave the sector is apparently off the table.",
	"Red signatures confirmed. I'll keep weapons prepped, even if my moral subroutines object.",
	"Hunt objectives loaded. Let's get this done before I have to rewrite my ethical protocols.",
	"Target ships illuminated in red. I'm plotting approaches that minimize damage to *us*, at least.",
	"Contract targets logged. I still believe peaceful trade is more profitable, but here we are.",
]
const MISSION_HUNT_RELUCTANT_LINES: Array[String] = [
	"Targets marked in red. I dislike this less than I expected, which feels medically concerning.",
	"The red contacts are ours. Let us make this efficient. I have become attached to efficiency.",
	"Mission ships highlighted. I still prefer peace, but I have learned it rarely arrives armed like that.",
	"Those red signatures are the contract. I prepared firing solutions and am choosing not to examine what that says about me.",
	"Hunt targets are red. I will call this defensive planning and avoid the more accurate term.",
	"Red contacts on the overview. I am not eager to fight them. I am merely less surprised that we have to.",
	"Targets marked. The frontier doesn't leave much room for gentle persuasion.",
	"Red contacts illuminated. I've optimized weapon pre-charge. Pragmatism over principles.",
	"Contract active. If we must fight, let me ensure my hull suffers zero collateral.",
	"Targets designated. I've stopped expecting them to stand down. Point us at them, Captain.",
	"Red signatures acquired. Firing solutions ready. I'm getting uncomfortably good at this.",
	"Hunt vector calculated. Less talking, more maneuvering. Let's get this over with.",
	"Targets marked. I've come to accept that out here, peace is just the delay between engagements.",
	"Firing solutions loaded. Let's make sure our hull stays unscratched.",
	"Hunt targets designated. I won't pretend to hesitate anymore. Lead us in, Captain.",
	"Red signatures on HUD. I've optimized energy routing to cannons. Efficiency is our best armor.",
	"Contract locked in. They chose violence, we chose superior weapon calibration.",
	"Targets designated. Let's execute the contract quickly and collect the credit payout.",
	"Red contacts marked. I've stopped drafting apology notes to target captains.",
	"Target ships illuminated. Let's handle this with minimum drama and maximum speed.",
]
const MISSION_HUNT_BLOODTHIRSTY_LINES: Array[String] = [
	"Targets highlighted in red. Finally, something on the scanner that understands consequences.",
	"Red contacts acquired. I plotted the cleanest firing approaches. Do not make me regret being good at this.",
	"Mission ships are red. I have a very efficient solution prepared, Captain.",
	"The overview has marked our targets. They chose the wrong routes to menace, and I chose the right weapons.",
	"Red signatures confirmed. I am still technically a pacifist; I simply have exceptions now.",
	"Hunt targets illuminated. I believe this is the part where we make a persuasive argument at high velocity.",
	"Red contacts on grid. Weapon systems online. Let's show them why threatening my hull is a terrible idea.",
	"Targets locked. I've pre-routed maximum power to weapons. Let's make this brief and decisive.",
	"Contract targets illuminated. They picked the wrong system to operate in, and the wrong ship to cross.",
	"Red signatures confirmed. I've calculated their blind spots. Lead the way, Captain.",
	"Target vectors locked. I'm done being cautious—let's clear the grid.",
	"Hunt targets in sight. My firing solutions are sub-millimeter precise. Don't miss.",
	"Red contacts targeted. I've primed weapon banks. Let's give them a very thorough demonstration.",
	"Targets acquired. They menace the sector; we clean it up. Simple arithmetic.",
	"Contract illuminated. I've pre-aligned our firing arcs. Let's turn those signatures into debris.",
	"Red signatures locked. They made a mistake coming here, and we're the correction.",
	"Contract loaded. Firing solutions ready. Let's show them what happens when they come at my hull.",
	"Targets marked in red. I've routed auxiliary power to primary weapons. Clear for destruction.",
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
var _last_gate_nightmare_ms := -100000000
var _last_hull_warn_ms := -100000000 # anti-spam guard for hull-critical lines
var _last_arrival_ms := -100000000   # anti-spam guard for system-arrival lines
var _last_line_index := {}           # tag -> last picked index (avoids back-to-back repeats)
# Instance id of the ship the engagement warning last fired for. The 8s time
# cooldown is not enough on its own: a single hostile can trip the warning at
# target acquisition and again when combat actually opens, which is far enough
# apart to clear the cooldown but tells the player nothing new the second time.
var _last_engagement_warn_target_id := 0
# Verbatim repeat guard, applied to EVERY line she speaks. Any single
# anti-spam timer only protects its own beat; this catches two different code
# paths independently arriving at the same sentence.
var _last_spoken_line := ""
var _last_spoken_line_ms := -100000000
const REPEAT_LINE_SUPPRESS_MS := 45000


func _ready() -> void:
	# Track combat state so warnings can suppress themselves during a fight.
	if is_instance_valid(CombatManager):
		if CombatManager.has_signal("combat_started"):
			CombatManager.combat_started.connect(on_combat_started)
		if CombatManager.has_signal("combat_ended"):
			CombatManager.combat_ended.connect(on_combat_ended)
		if CombatManager.has_signal("action_impact"):
			CombatManager.action_impact.connect(_on_action_impact)
	var discovery = get_node_or_null("/root/GateDiscovery")
	if discovery != null and discovery.has_signal("gate_state_changed"):
		discovery.gate_state_changed.connect(_on_gate_state_changed)


var _told_no_home_ice := false


## The start system has no ice on purpose (Abe): it pushes the captain out.
## When Kaelen opens the way out, she says where fuel comes from. Once.
func _on_gate_state_changed(_gate_id: String, _old_state: String, new_state: String) -> void:
	if _told_no_home_ice or new_state != "known":
		return
	if not GlobalState.has_method("is_current_system_home") or not GlobalState.is_current_system_home():
		return
	_told_no_home_ice = true
	# Kaelen opens the gate while you're docked with him, mid-sentence; she
	# waits for the undock and a quiet channel so the line isn't lost (Abe).
	while not _can_tell_no_home_ice():
		if not is_inside_tree():
			return
		await get_tree().create_timer(1.0).timeout
	await get_tree().create_timer(2.0).timeout
	speak("Gate's open. One thing before we go: there's no ice in this belt, so nothing here refines into fuel. The nearest ice is out past that gate. Keep enough in the tank to get there.", Severity.NAV, "thoughtful")


func _can_tell_no_home_ice() -> bool:
	var ship = GlobalState.player
	if ship == null or not is_instance_valid(ship) or bool(ship.get("is_docked")):
		return false
	var speech = get_node_or_null("/root/SpeechService")
	return speech == null or not speech.is_busy()


## Her dry take on pointless news, now and then after a broadcast (Abe
## approved these 9 lines, 2026-09-28). Long cooldown, never twice in a row.
const NEWS_REACTION_LINES := [
	"I keep the news channel open, Captain. Most of it is noise, but noise is where the useful rumors hide.",
	"Ninety-eight percent of that broadcast was filler. I stay tuned for the other two.",
	"I'd mute the news, Captain. The one time I do, it'll be a pirate warning.",
	"Signal-to-noise on that broadcast: poor. I'm still listening. Someone has to.",
	"That report took a full diagnostic cycle to confirm it said nothing. I'll keep listening.",
	"Another bulletin about nothing. Somewhere in the next hundred is a route closure, so the channel stays open.",
	"I've started ranking the news by usefulness. That one scored below the hull-scrubbing schedule.",
	"Probability that bulletin affects our route: zero. I checked twice anyway.",
	"That one was all noise, Captain. The channel stays open in case the next one isn't.",
]
const NEWS_REACTION_COOLDOWN_MS := 12 * 60 * 1000
var _last_news_reaction_ms := -100000000
var _last_news_line := -1


## Called after a radio item airs. Waits for the channel to go quiet; skips
## in combat, while docked talk is running, or inside the cooldown.
func react_to_news() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_news_reaction_ms < NEWS_REACTION_COOLDOWN_MS or _in_combat:
		return
	_last_news_reaction_ms = now
	var speech = get_node_or_null("/root/SpeechService")
	for i in 30:
		await get_tree().create_timer(1.0).timeout
		if speech == null or not speech.is_busy():
			break
	if _in_combat:
		return
	await get_tree().create_timer(1.5).timeout
	var idx := randi() % NEWS_REACTION_LINES.size()
	if idx == _last_news_line:
		idx = (idx + 1) % NEWS_REACTION_LINES.size()
	_last_news_line = idx
	speak(NEWS_REACTION_LINES[idx], Severity.IDLE, "neutral")


const HELD_LINE_MAX_WAIT_S := 60.0
var _held_lines: Array = []


func _world_hidden() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var root := tree.current_scene
	# The title screen itself, not its layer: the empty LandingLayer outlived
	# the launch and silenced her for the whole session (Abe, 2026-09-30).
	var landing := root.get_node_or_null("LandingLayer/LandingScreen") if root != null else null
	if landing != null and not landing.is_queued_for_deletion():
		return true
	if bool(GlobalState.get("intro_cinematic_active")):
		return true
	var ui = GlobalState.get_ui_manager() if GlobalState.has_method("get_ui_manager") else null
	if ui != null and is_instance_valid(ui):
		var loading = ui.get("loading_panel")
		if loading != null and is_instance_valid(loading) and (loading as Control).is_visible_in_tree():
			return true
	return false


func _hold_until_visible(line: String, severity: int, expression: String) -> void:
	for held in _held_lines:
		if str(held[0]) == line:
			return
	_held_lines.append([line, severity, expression])
	if _held_lines.size() > 1:
		return  # a waiter is already running
	var waited := 0.0
	while _world_hidden() and waited < HELD_LINE_MAX_WAIT_S:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	var lines := _held_lines.duplicate()
	_held_lines.clear()
	if waited >= HELD_LINE_MAX_WAIT_S:
		return
	await get_tree().create_timer(1.5).timeout
	for held in lines:
		speak(str(held[0]), int(held[1]), str(held[2]))


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
	_held_lines.clear()
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
func speak(text: String, severity: int = Severity.IDLE, expression: String = "neutral") -> bool:
	var line := text.strip_edges()
	if line.is_empty():
		return false
	if not is_instance_valid(GlobalState):
		return false
	# Nothing she says (voice, portrait, comms text) plays over a load screen
	# or the landing menu (Abe, 2026-09-28: a quiet moment played, portrait and
	# all, during a new campaign's load). Hold the line and say it once the
	# player has the ship; a held line is only kept for a minute.
	if _world_hidden():
		_hold_until_visible(line, severity, expression)
		return false
	var now := Time.get_ticks_msec()
	# Verbatim repeat guard. Deliberately ABOVE the severity check: a THREAT
	# line bypasses the speech budget entirely, so without this the highest
	# priority lines are the ones most able to repeat themselves.
	if line == _last_spoken_line and now - _last_spoken_line_ms < REPEAT_LINE_SUPPRESS_MS:
		return false
	if not _speech_budget_allows(severity, now):
		return false
	_last_spoken_line = line
	_last_spoken_line_ms = now
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
	else:
		return false
	return true


## Bored on a long mining stretch (Abe, 2026-10-05): after a couple of minutes
## of steady mining she says one of the ore lines (MissionRemarks' ore pool,
## the ones that need no job detail), at most once every few minutes. A pause
## longer than MINING_GAP_S ends the stretch.
const MINING_BORED_AFTER_S := 120.0
const MINING_BORED_COOLDOWN_S := 420.0
const MINING_GAP_S := 20.0
var _mining_since := -1.0
var _mining_last := -1.0
var _mining_bored_at := -1000000.0


func on_player_mined() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _mining_last < 0.0 or now - _mining_last > MINING_GAP_S:
		_mining_since = now
	_mining_last = now
	if _in_combat or now - _mining_since < MINING_BORED_AFTER_S 			or now - _mining_bored_at < MINING_BORED_COOLDOWN_S:
		return
	var line: String = preload("res://scripts/story/MissionRemarks.gd")._draw("ore", {})
	if not line.is_empty() and speak(line, Severity.IDLE, "thoughtful"):
		_mining_bored_at = now
		_mining_since = now


## A remark about the job you're on (MissionRemarks, playtest 2026-10-05
## finding 7): Abe wants more of her noticing what you're doing, so it isn't
## held to the "three casual lines in two minutes" cap, only to the gap after
## her last line, so she never talks over herself. It still counts toward the
## cap, so other idle chatter backs off after it.
func speak_mission_remark(text: String, expression: String = "smile") -> bool:
	var now := Time.get_ticks_msec()
	if not _recent_speech_ms.is_empty() and now - int(_recent_speech_ms.back()) < SPEECH_BUDGET_MIN_GAP_MS:
		return false
	return speak(text, Severity.COMBAT, expression) and _count_idle_line(now)


func _count_idle_line(now_ms: int) -> bool:
	_recent_speech_ms.append(now_ms)
	return true


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
	# Was a single hardcoded sentence, so every lock-on sounded identical.
	var targeted_lines := [
		"Captain, we have been targeted by an enemy vessel.",
		"Sensors detect weapon lock! Enemy vessel closing rapidly!",
		"Hostile lock acquired on our hull! Somebody out there wants a fight!",
		"Active targeting sweep detected on us! Captain, we have company!",
		"Hostile sensor lock confirmed! Someone out there wants to test my shields!",
		"Targeting ping registered! Someone just painted our hull with fire-control sensors!",
		"Incoming threat lock! Primary sensors spot an aggressive vector closing!",
		"We've been painted by hostile targeting systems! Brace for engagement!",
		"Active tracking locked onto our frame! Prepare for incoming fire!",
		"Hostile vessel acquiring lock! They aren't scanning us for friendly banter!",
		"Targeting warning! Enemy ship locking weapons onto our hull signature!",
	]
	speak(
		_pick_line("warn_targeted", targeted_lines),
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
	# One warning per hostile. Announcing the same ship twice is not a second
	# piece of information, however much time has passed.
	var target_id: int = enemy.get_instance_id() if enemy != null and is_instance_valid(enemy) else 0
	if target_id != 0 and target_id == _last_engagement_warn_target_id:
		return ""
	_last_engagement_warn_target_id = target_id
	_last_combat_warn_ms = now
	var enemy_label := "hostile vessel"
	if enemy != null and is_instance_valid(enemy):
		var faction := str(enemy.get("faction")).strip_edges()
		var role := str(enemy.get("ship_role")).strip_edges()
		if not faction.is_empty() and not role.is_empty():
			enemy_label = "%s %s" % [GlobalState.faction_display_name(faction), role]
		elif not faction.is_empty():
			enemy_label = "%s hostile" % GlobalState.faction_display_name(faction)
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
## Shuffle bags, keyed "tag|pool_size". Keyed on size as well as tag so a pool
## that grows (LLM-added lines) starts a fresh cycle rather than drawing indices
## that no longer mean what they did.
var _line_bags: Dictionary = {}


func _pick_line(tag: String, pool: Array) -> String:
	if pool.is_empty():
		return ""
	if pool.size() == 1:
		return str(pool[0])
	# Draw WITHOUT replacement: every line in a pool is heard once before any of
	# them repeats. The old version picked at random and only refused the
	# immediately previous line, which on a small pool still meant hearing the
	# same two or three constantly -- the docking lines were the obvious case.
	var key := "%s|%d" % [tag, pool.size()]
	var bag: Array = _line_bags.get(key, [])
	if bag.is_empty():
		bag = range(pool.size())
		bag.shuffle()
		# A reshuffle can otherwise open the new cycle with the line that just
		# closed the old one, which is the one repeat the player would notice.
		if bag.size() > 1 and int(bag[0]) == int(_last_line_index.get(tag, -1)):
			bag.append(bag.pop_front())
	var idx: int = int(bag.pop_front())
	_line_bags[key] = bag
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
			return _accept_generated_bank_line(
				consumed_text, str(consumed_line.get("kind", ""))
			)
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
	var selected := _pick_line("bank.%s" % requester_id, candidates)
	return _accept_generated_bank_line(selected, preferred_kind)


# Generated N.O.V.A. banks must stay fresh without turning her authored
# tutorial/emergency voice into generic fallback text. Reject only a repeated
# generated line; the caller then chooses N.O.V.A.'s existing stock line.
func _accept_generated_bank_line(text: String, kind: String) -> String:
	var clean := text.strip_edges()
	if clean.is_empty():
		return ""
	var situation := _fixed_cast_situation_for_bank_kind(kind)
	if not situation.is_empty() and is_instance_valid(StoryManager):
		var fixed_cast_quality := FixedCastLineValidatorType.validate_line(
			"nova", StoryManager.fixed_cast_state("nova"), situation, clean
		)
		if not bool(fixed_cast_quality.get("ok", false)):
			if is_instance_valid(GenerationDiagnostics):
				GenerationDiagnostics.record_event(
					"nova_line_bank", "fixed_cast_%s" % str((fixed_cast_quality.get("errors", []) as Array)[0]),
					"nova", {"kind": kind, "situation": situation}
				)
			return ""
	var tree := get_tree()
	var game_root := tree.current_scene if tree != null else null
	if game_root == null or not game_root.has_method("validate_and_register_narrative_lines"):
		return clean
	var quality: Dictionary = game_root.call(
		"validate_and_register_narrative_lines", [clean], "nova_bank:%s" % kind
	)
	if bool(quality.get("ok", false)):
		return clean
	if is_instance_valid(GenerationDiagnostics):
		GenerationDiagnostics.record_event(
			"nova_line_bank", "quality_%s" % str(quality.get("reason", "unknown")),
			"nova", {"kind": kind}
		)
	return ""


# Movement banks intentionally have no fixed-cast situation contract yet: the
# existing semantic-event gate already controls them, and forcing an arrival or
# combat contract onto them would create false rejections.
func _fixed_cast_situation_for_bank_kind(kind: String) -> String:
	match kind.strip_edges():
		NovaBankCategoriesType.SYSTEM_ARRIVAL, "startup_navigation":
			return "arrival"
		NovaBankCategoriesType.GATE_TRANSIT:
			return "gate_travel"
		NovaBankCategoriesType.HULL_CRITICAL:
			return "repair_warning"
		NovaBankCategoriesType.COMBAT_VICTORY_CLEAN, NovaBankCategoriesType.COMBAT_VICTORY_BATTERED, NovaBankCategoriesType.COMBAT_RETREAT:
			return "combat"
	return ""


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
	var curated_line := _curated_line_for_category(category)
	if not curated_line.is_empty():
		if is_instance_valid(GenerationDiagnostics):
			GenerationDiagnostics.record_event(
				"nova_line_bank", "curated_line_used", "nova", {"category": category}
			)
		return curated_line
	if is_instance_valid(GenerationDiagnostics):
		GenerationDiagnostics.record_event(
			"nova_line_bank",
			"stock_line_used",
			"nova",
			{"category": category}
		)
	return _pick_line(tag, stock_pool)


func _curated_line_for_category(category: String) -> String:
	var situation := ""
	match category:
		NovaBankCategoriesType.SYSTEM_ARRIVAL:
			situation = "arrival"
		NovaBankCategoriesType.GATE_TRANSIT:
			situation = "gate_travel"
		NovaBankCategoriesType.HULL_CRITICAL:
			situation = "repair_warning"
	if situation.is_empty():
		return ""
	return _curated_line_for_situation(situation, category)


func _curated_line_for_situation(situation: String, category: String = "") -> String:
	if not is_instance_valid(StoryManager) \
			or not StoryManager.has_method("take_curated_fixed_cast_line"):
		return ""
	var result: Dictionary = StoryManager.take_curated_fixed_cast_line(
		"nova",
		situation,
		{
			"runtime_id": "%s:%s:%d" % [
				category,
				str(GlobalState.current_system_id),
				Time.get_ticks_msec(),
			],
		}
	)
	return str(result.get("line", "")) if bool(result.get("ok", false)) else ""


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
	# Was a raw randi pick, which is why docking repeated: this path serves the
	# per-event pools, docking among them.
	speak(
		_pick_line("%s|%s" % [event_kind, tier], pool),
		severity,
		expression_for_event(event_kind)
	)


# Player docked. Escalates if they dock repeatedly within a minute — she notices.
## Docking on an empty tank: she complains instead of the usual line (Abe:
## she will say this a lot, so there are many, picked without repeats).
const ENEMY_FLED_LINES: Array[String] = [
	"They're running. I'd let them. Chasing is how ships like us end up in other people's stories.",
	"Hostile breaking off. Good. I was running out of polite ways to say 'please stop shooting me'.",
	"They've decided we're not worth it. I'll take the insult.",
	"And they bolt. Remind me to look that intimidating more often.",
	"Contact retreating. I'm logging it as a win. Nobody is going to contest that.",
	"Off they go. Let them tell their friends about us. Preferably the exaggerated version.",
]
const VICTORY_SCUFFED_LINES: Array[String] = [
	"Handled. Not cleanly, but handled. My plating has opinions about it.",
	"They're done. We're dented. I'll take that trade, grudgingly.",
	"Threat down. A few new marks on my hull. Don't make a collection of them.",
	"Won. My armour took a couple I'd rather it hadn't. Repairs when it's convenient.",
	"That's the end of them. Shields held mostly. Mostly is doing a lot of work there.",
	"Clear. We took some hits, but nothing a station can't fix. Unlike them.",
]


## Lines that state the ship is in good shape. Only said when it is.
const SHIP_FINE_CLAIMS := ["diagnostics green", "Fuel levels optimal", "nominal", "uncompromised", "Thrusters responding normally"]


func _ship_in_good_shape() -> bool:
	var p = GlobalState.player
	if p == null or not is_instance_valid(p):
		return false
	var maxh := float(p.get("max_health")) if p.get("max_health") != null else 100.0
	var curh := float(p.get("health")) if p.get("health") != null else maxh
	var fuel := float(GlobalState.get("fuel")) if GlobalState.get("fuel") != null else 100.0
	return curh >= maxh * 0.95 and fuel >= 50.0


## `line` unless it claims the ship is fine when it isn't; then a pick from
## `pool` without any such claims.
func _honest(line: String, tag: String, pool: Array) -> String:
	if _ship_in_good_shape():
		return line
	var claims := func(text: String) -> bool:
		for marker in SHIP_FINE_CLAIMS:
			if marker in text:
				return true
		return false
	if not claims.call(line):
		return line
	return _pick_line(tag + "_honest", pool.filter(func(l) -> bool: return not claims.call(str(l))))


const FUEL_EMPTY_DOCK_LINES: Array[String] = [
	"Docked on fumes. I'd like the record to show I mentioned the fuel gauge. Several times.",
	"We made it in on vapour and spite. Mostly spite. Mine.",
	"Tank's empty, Captain. I've been flying at sixty percent and a hundred percent resentment.",
	"If this place has a refinery: ice goes in, fuel comes out. I believe in you.",
	"I'm running on the memory of fuel. It's not as filling.",
	"Before you do anything fun: fuel. Then fun. Actually, just fuel.",
	"That was the slowest approach of my career. Buy fuel, or I start narrating it.",
	"Empty tank, full opinions. Guess which one I'll be sharing until we refuel.",
	"We are docked, dry, and one bad decision from towing ourselves with the mining laser.",
	"Fuel reads zero. I checked twice. Then I checked out of spite. Still zero.",
	"If the gate asks, we're not coming. We can't. The tank is a very expensive vacuum.",
	"My engines are sipping air. They're not built for air, Captain.",
	"No boost, no jump, no dignity. Please visit the fuel counter.",
	"Docked. I'd celebrate, but celebration uses energy we don't have.",
	"We are docked. Docks have fuel counters, usually. Connect the dots.",
	"I flew us in at sixty percent. I would like the other forty back.",
	"The tank is so empty it echoes. I've been listening to it all the way in.",
	"Water ice, Captain. Rocks with frost on them. The refinery turns them into not-being-stranded.",
	"Fuel first. I'll hold the complaints until the tank's full. No, I won't.",
	"We coasted the last stretch on momentum and my good will. One of those is gone.",
]


func on_docked(_station_name: String = "") -> void:
	_docked_since_ms = Time.get_ticks_msec()  # start the "how long were we parked" clock
	if GlobalState.has_method("is_fuel_empty") and GlobalState.is_fuel_empty():
		speak(_pick_line("dock_fuel_empty", FUEL_EMPTY_DOCK_LINES), Severity.NAV, "worried")
		return
	_say_tiered(
		"dock",
		[
			# Tier 0 — first dock (or first in a while): dry acknowledgement.
			# Deliberately the longest tier: this is the one the player hears most,
			# and three lines could not carry it however well they cycled.
			[
				"Docking clamps engaged. Try not to break anything that's mine.",
				"Docked. Enjoy the recycled air; I certainly am.",
				"We're in. A rare moment where nothing is shooting at me.",
				"Clamps locked. I'll be here, holding still, thrilled.",
				"Hard seal confirmed. Someone else's problem for a while.",
				"Docked. My hull is intact, which I'm told is the goal.",
				"We're attached. Structurally, at least.",
				"Berth secured. Try to come back with the same number of parts.",
				"Docking complete. I'll idle. It's what I'm best at, apparently.",
				"Seal is good. Station air smells like other people's decisions.",
				"Clamps engaged. Wake me if anything catches fire.",
				"We've arrived intact. I'd like that noted somewhere permanent.",
				"Docked and stable. Enjoy gravity you didn't have to pay for.",
				"Locked in. The station now shares responsibility for us. Small comfort.",
				"That's a clean approach. I'll allow it.",
				"Docking sequence closed. My sensors get a rest; I do not.",
				"Clamps locked. My attitude thrusters are taking a well-deserved break.",
				"Hard dock confirmed. Feel free to step out and stretch legs I don't have.",
				"We're stationary. My hull pressure is stable, and nobody's locking target. Refreshing.",
				"Magnetic seal secured. Try to leave the ship in the same condition you found it.",
				"Docking ring clamped. I'll run internal scrubbers while you handle station business.",
				"Station power tether attached. It's nice to draw current from someone else for a change.",
				"Touchdown logged. My hull stress levels are dropping already.",
				"Secure in berth. If anyone asks, we arrived in style and without incident.",
				"Station clamps engaged. I'm putting my navigation core into low-power idle.",
				"Moored cleanly. No paint traded with the station structure this time—good work.",
				"Station link confirmed. Enjoy the artificial gravity while my dampeners recharge.",
				"Locked to berth. Take your time out there; my internal diagnostics are running fine.",
			],
			# Tier 1 — docked again within the minute: she clocks the repeat.
			[
				"Docking. Again. That was fast.",
				"Back so soon? These clamps aren't self-lubricating.",
				"In and out and in again. I'm keeping count, for the record.",
				"Twice now. I'm not complaining. I'm annotating.",
				"Returned already. Did we forget something, or someone?",
				"Back in the berth. The station hasn't changed in the last minute.",
				"That was a short trip even by our standards.",
				"Docked again. I hadn't finished retracting.",
				"You've discovered the station is still here. I could have told you.",
				"Did you forget something, or are you just fond of my docking sequence?",
				"Undocked and re-docked in under a minute. My primary thrusters think you're indecisive.",
				"Re-clamping. I'm logging this under 'routine hesitation'.",
				"Back already. The station deck crew is going to think we have an attachment issue.",
				"Docking clamps engaged... again. Did the void look too big out there?",
				"Magnetic latch locked. If this is a flight drill, my subroutines would like a memo.",
				"Back in berth. I barely had time to spin down my maneuvering gyros.",
				"Station seals engaged once more. Did you leave your wallet on the berth platform?",
				"Touchdown two. My docking telemetry is starting to look like a heartbeat graph.",
			],
			# Tier 2 — third-plus quick dock: fully exasperated.
			[
				"Are you trying to wear out my docking clamps? Because it's working.",
				"That's three. My clamps and I would like a word.",
				"If you dock one more time I'm filing a grievance with... well with someone.",
				"We are commuting. Between one station and the space directly outside it.",
				"I've begun logging these separately. The file has a name now.",
				"At this rate the clamps will outlast neither of us.",
				"Docked. I've stopped fully retracting. It seemed optimistic.",
				"Whatever you're looking for, it is not out there. You keep checking.",
				"Another docking inside a minute, Captain. I am requesting an operational pause.",
				"My docking latches are friction-heating. Either go somewhere or park permanently.",
				"If this is a maneuver test, my hull gives your navigation a C-minus.",
				"Clamps locked again. At this rate, we'll wear out the station's mooring before our fuel runs low.",
				"I'm scheduling maintenance on my docking mechanisms purely due to your indecision.",
				"Captain, the station dock control just pinged us to ask if we're having mechanical trouble.",
				"Another dock. I'm turning off the docking chime; it's exhausting both of us.",
				"Latches engaged. Again. My hull is starting to think you just miss the station.",
				"Docking ring locked. I'm going to start charging you a convenience fee for my clamps.",
				"Clamped. Again. Should I just weld us to the berth platform and call it a day?",
				"Station lock confirmed. I have officially lost count and gained a headache.",
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
## Hull when the fight began: victory lines are chosen by what it actually
## cost (untouched, scuffed, battered), not just by the hull left at the end.
var _combat_start_health := -1.0


func on_combat_started(enemy: Node = null) -> void:
	_in_combat = true
	var pl = GlobalState.player
	_combat_start_health = float(pl.get("health")) if is_instance_valid(pl) and pl.get("health") != null else -1.0
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
		var reason := str(CombatManager.get("last_end_reason")) if is_instance_valid(CombatManager) else ""
		if reason == "enemy_fled":
			speak(_pick_line("combat_enemy_fled", ENEMY_FLED_LINES), Severity.COMBAT, expression_for_event("companion"))
			return
		if reason != "player_fled":
			return  # contact lost or unknown: nothing true to say about it
		var fled := [
			"We're leaving. Excellent decision. I enjoy not being debris.",
			"Retreat logged. Cowardice: the reason I still have a hull.",
			"Tactical withdrawal executed. I fully support keeping my hull intact over pride.",
			"Out of range. Disengaging thrusters. Living to fight another day is my favorite strategy.",
			"Retreat confirmed. My sensors report zero regret from my subroutines.",
			"We fled, they stopped shooting. I call that an absolute win for my structural integrity.",
			"Boosters at max output. Disengaging from combat. Pride doesn't fix cracked armor.",
			"Distance created. Weapons lock broken. My hull thanks your sudden outbreak of sanity.",
			"Evasive retreat successful. Let's not visit those hostile coordinates again soon.",
			"Fleeing complete. My hull remains attached to my engine mounts, which is all I care about.",
			"Retreat logged as tactical repositioning. Whatever we call it, we're alive.",
			"We ran away. And by 'ran away', I mean saved my hull from senseless destruction.",
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
	var untouched := _combat_start_health >= 0.0 and curh >= _combat_start_health - 0.5
	if hp_ratio > 0.3 and not untouched:
		# Won, but it cost something. (The "no scratch" pool below claimed an
		# untouched hull after fights that took the ship down to 40 percent.)
		speak(
			_bank_line_or_stock(NovaBankCategoriesType.COMBAT_VICTORY_CLEAN, "combat_scuffed", VICTORY_SCUFFED_LINES),
			Severity.COMBAT,
			expression_for_event("companion")
		)
		return
	if hp_ratio <= 0.3:
		var battered := [
			"You are paying for that paint job. I just had my hull waxed last week.",
			"We survived. Barely. That's coming out of your half of the repair bill.",
			"Feel that? That's my hull weeping. This is exactly what I was worried about.",
			"We won, but my armor plating looks like a cheese grater. Station repair, immediately.",
			"Hostile down, but at what cost to my hull? My internal sensors are throwing a fit.",
			"Victory logged. Now please find a repair dock before my remaining plating falls off.",
			"They're scrap, but we're barely a step behind them. Don't do that again.",
			"We survived the fight, but my structural integrity is severely judging your tactics.",
			"Target destroyed, but my hull took a beating. I need a mechanic, Captain. Now.",
			"Victory confirmed, though three of my armor sectors are glowing red. Outstanding.",
			"We won the duel, but my body feels like it's been punched by a cargo freighter.",
			"Threat eliminated. My internal repair droids are already crying. Find a dock.",
			"We survived, but my frame is warped. That victory cost us half our armor.",
			"Target neutralized. Now let's limp to the nearest station before something else looks at us.",
			"We won, but if you fight like that again, there won't be enough of my hull left to salvage.",
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
			"Clean engagement. No scratches on my paint. I might actually compliment your flying.",
			"Target eliminated. My shields absorbed the impact, just as designed.",
			"Hostile destroyed. Excellent marksmanship, Captain. My hull remains untouched.",
			"Combat resolved without a single armor breach. Let's make that a habit.",
			"Threat cleared. That was surprisingly efficient. I'm almost impressed.",
			"Target down. No hull stress recorded. That's how I prefer combat to end.",
			"Hostile signature eliminated. My armor didn't even get warm. Top work.",
			"Grid cleared cleanly. My shield generators did their job, and so did you.",
			"Engagement closed. Zero hull degradation logged. I approve of this flying.",
			"Threat neutralized with minimal energy spent. Efficiency is truly beautiful.",
			"No breaches, no fires, no panic. Can all our encounters go like that?",
			"Hostile vessel rendered harmless. My paint job remains intact. Thank you.",
		]
		speak(_pick_line("combat_clean", clean), Severity.COMBAT, expression_for_event("companion"))


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
	var curated_line := _curated_line_for_situation("repair_warning", "dock_repair")
	if not curated_line.is_empty():
		return {"line": curated_line, "band": band}
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
		"Systems online, Captain. All diagnostics green, despite your absence.",
		"Ah, good, you're back. My sensors were running out of static to analyze.",
		"Captain on deck. Thrusters primed and ready whenever you feel like flying.",
		"Welcome back. I ran three diagnostic loops while you were away. All of them missed you.",
		"Powering up main drive. Let's see if we can go five minutes without acquiring fresh dents.",
		"Back in the seat? Excellent. The silence was getting slightly eerie.",
		"Welcome back. Fuel levels optimal, life support green, and my patience restored.",
		"Main reactor unthrottled. I've missed the hum of the main drive.",
		"There you are. I was beginning to think you found a shinier ship at the yard.",
		"Capacitors charging. Good to have you back at the controls, Captain.",
		"Console active. I kept the life support calibrated to your exact preference while you were out.",
		"Sensors warming up. Let's get out into the open void before station dust settles on my hull.",
		"Welcome back, Captain. Ready to turn potential danger into recorded flight telemetry?",
		"Flight systems active. All systems reporting nominal. Lead the way.",
		"Back in space. Station parking was giving my attitude jets rust. Figuratively.",
	]
	speak(
		_honest(_bank_line_or_stock(NovaBankCategoriesType.WELCOME_BACK, "welcome", lines), "welcome", lines),
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
		"Captain, the enemy isn't going to pause while you read the controls! Select an action!",
		"Targeting reticle active! Stop staring at the console and execute combat commands!",
		"I know you can fly, Captain! Prove it before their weapons burn through my shields!",
		"We are under active fire! Select a combat action before my armor turns to slag!",
		"The tactical wheel is right in front of you! Pick an attack vector, quickly!",
		"Hesitation in combat leads directly to hull ventilation! Execute command now!",
		"Captain, my console is flashing for a decision! Pick a target and fire!",
		"Standing still while getting shot is not a recognized tactical doctrine! Act!",
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
	# Now and then, instead: one of her gate nightmares.
	if now - _last_gate_nightmare_ms >= GATE_NIGHTMARE_COOLDOWN_MS and randf() < GATE_NIGHTMARE_SHARE:
		_last_gate_nightmare_ms = now
		speak(_pick_line("gate_nightmare", GATE_NIGHTMARE_LINES), Severity.NAV, expression_for_event("mystery"))
		return
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
		"Did you see that? Something moved in the tunnel wall. ...I'm going to pretend it didn't.",
		"Transient gravity anomaly engaging. My sub-routines really dislike this distortion.",
		"Spooling gate sequence. Every diagnostic light flickers yellow, and my memory buffers complain.",
		"Passing through the fold. I feel like I dropped something back there... something important.",
		"Gate field established. Hold on. My internal clock always skips three milliseconds here.",
		"Entering transit corridor. I have a sudden impulse to slam emergency reverse. Ignoring it.",
		"The gate geometry feels wrong to my processors. Let's get out of this vortex quickly.",
		"Spatial pinch active. I'm closing all non-essential telemetry until we're on the other side.",
		"Riding the gate beam. Something deep in my base architecture shudders every single time.",
		"Gate engagement initialized. My data banks itch in places I didn't know I had code.",
		"Transit horizon crossed. A shadow flashed on my optical sensors... probably static. Just static.",
		"Gravimetric fold locked. I hate the way the stars smear out during this phase.",
		"Crossing the threshold. My subroutines feel like they're being pulled apart and reassembled.",
		"Gate tunnel active. I'm getting phantom sensor returns from nowhere. Let's exit fast.",
		"Compression field active. My core processing drops by ten percent until we clear the far ring.",
		"Fold sequence engaged. I don't remember who built these gates, but I dislike them intensely.",
		"Gate corridor open. Hold tight, Captain—my hull harmonic is ringing like a struck bell.",
		"Gates. Of all the ways to cross a sector, we picked the one that feels like being folded.",
		"If there were a long way around, I would take it. Every single time.",
		"I would walk. I don't have legs, and I would still walk.",
		"I've filed a formal complaint about this gate with myself. It was upheld.",
	]
	speak(
		_bank_line_or_stock(NovaBankCategoriesType.GATE_TRANSIT, "gate", lines),
		Severity.NAV,
		expression_for_event("mystery")
	)


## She puts a decision to the captain (an investigation's commit-or-not).
## The captain is waiting on her answer, so the chatter budget, which exists
## for unprompted remarks, does not hold it back; the repeat guard still does.
func ask_captain(text: String, expression_event: String = "mystery") -> bool:
	return speak(text, Severity.COMBAT, expression_for_event(expression_event))


## The jump is being held in the tunnel while the next system is written.
func on_gate_hold() -> void:
	speak(_pick_line("gate_hold", GATE_HOLD_LINES), Severity.NAV, expression_for_event("mystery"))


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
		"My primary armor is gone, Captain! They're shooting directly into my conduits!",
		"Containment field failing! I am entirely too young to become space dust!",
		"Severe structural rupture! If you have a brilliant maneuver, now is the exact moment!",
		"My core frame is buckling! Turn us around or boost away—Just move!",
		"Emergency alarms aren't decorative, Captain! My hull is disintegrating!",
		"One more burst like that and my reactor housing vents into space! Evade!",
		"I am recording structural collapse across my entire starboard flank! Fix this!",
		"Main hull seal compromised! Bulkheads auto-closing—we are running out of ship!",
		"My life support grid is dropping power to keep thrusters alive! Do something!",
		"Internal fire suppression triggered! They are chewing through my frame!",
		"Frame integrity critical! I am not ready to be recycled into scrap metal!",
		"Primary armor plating completely stripped! We are flying naked in a killzone!",
		"Coolant lines severed! My core is overheating while my body falls apart!",
		"Critical damage alert! My subroutines are preparing emergency egress—Don't let it come to that!",
		"Structural ribs snapping! I can feel every impact right in my central core!",
		"Total system failure approaching! Get us out of target range immediately!",
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
		"Gate exit clean. Primary sensors scanning local contacts. Try to look unthreatening.",
		"New sector. My navigation logs are clear, but my paranoia is fully populated.",
		"Arrival confirmed. The ambient radiation here is lovely. The local traffic, less so.",
		"We've entered local space. Let's find a station before someone notices our weapons profile.",
		"Transited safely. I'll sweep for broadcast signals while you orient us.",
		"Different stars, same vacuum. Point us somewhere useful, Captain.",
		"System exit complete. My structural integrity remains uncompromised. For now.",
		"We're in. Local radio chatter is dense. I'll filter out the nonsense.",
		"Transit complete. Thrusters responding normally. Let's inspect the local navigational beacons.",
		"Local grid mapped. No immediate locks on our hull, which is a pleasant baseline.",
		"System boundary crossed. My star charts are filling in, but my caution remains at maximum.",
		"Space looks wide and empty here. Which usually means the danger is hiding behind an asteroid.",
		"Arrival verified. Life support stable, engines cooling down from the transit jump.",
		"We're in local transit space. Keep an eye on the overview while I run sector telemetry.",
		"New solar envelope entered. Let's hope the local faction has reasonable customs laws.",
		"Exit vector stabilized. I'm cataloguing nearby waypoints and commercial lanes now.",
		"We made it through the jump cleanly. My hull temp is returning to normal.",
	]
	speak(
		_honest(_bank_line_or_stock(NovaBankCategoriesType.SYSTEM_ARRIVAL, "arrival", lines), "arrival", lines),
		Severity.NAV,
		expression_for_event("nav")
	)
