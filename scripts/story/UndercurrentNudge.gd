extends Node

## The undercurrent nudge (docs/core_loop_plan_2026_10_01.md 4.6, core loop
## step 11b): N.O.V.A. and Kaelen both keep nudging the Captain deeper, lightly
## and constantly, and never say why. Lines and timings as Abe approved them
## (docs/undercurrent_nudges_draft_2026_10_02.md).
##
## AUTHORED ONLY: these exact lines; no model writes or sees them. Light: at
## most one nudge from each per system visit, long cooldowns, and never two
## nudges on the same moment. N.O.V.A. never gives an order. Kaelen, never
## aboard, reaches us over comms (or in person at her own screen).
##
## The decisions are a pure step() over a state dictionary (saved in
## StoryManager.story_state["undercurrent"]), so every trigger is testable.

# --- N.O.V.A. -------------------------------------------------------------------
const NOVA_LINGER := [
	"We've been here a while. I don't like standing still.",
	"Same stars as last time. I'd memorised them already.",
	"I keep plotting routes out of here. Just habit. Ignore me.",
	"It's quiet back here. Too quiet for me, anyway.",
	"Do you ever get the feeling a place has already said everything it's going to say?",
]
const NOVA_CLASS_OPEN := [
	"That opens the next ring. Good. That's... good.",
	"There. Now the deeper gates will take us. I feel better than I should about that.",
	"Another class open. I still hate the gates. I hate them a little less when they lead somewhere new.",
	"Rating's up. The map just got bigger. I like it bigger.",
]
const NOVA_NEW_DEEPEST := [
	"Further than we've been. It's calmer out here. Don't ask me why I think so.",
	"New depth record. I've logged it. I may have logged it twice.",
	"This far out, everything's new. I could get used to that.",
]

# --- Kaelen ---------------------------------------------------------------------
const KAELEN_AFTER_UPGRADE := [
	"Good. Now go.",
	"New parts. Now take them somewhere worth the money, Shiny.",
	"That's paid for. Don't waste it on the same old lanes.",
	"Fitted? Good. The work's further out. It always is.",
]
const KAELEN_SHALLOW := [
	"You don't belong back here, Shiny.",
	"Still in the shallows? The money moved on. So should you.",
	"Nothing out there for you this close to home. Trust me on that.",
	"I'm not paying you to sightsee the places you've already seen.",
]
const KAELEN_OUTWARD_LEAD := [
	"This one goes deeper. I'll take less for it. Call it an investment.",
	"Outward lane. Cheaper than the rest. Don't read anything into it.",
]
const KAELEN_DEEP_SURVEY := [
	"Deep charts. Now that's worth something. Bring me more of these.",
	"Further out pays better. You've noticed that by now.",
]
const KAELEN_PITCH := [
	"Work like this is drying up back here. The good jobs are moving outward.",
	"Do this one well and I'll have something further out for you next.",
	"Small job. The real ones are a few jumps further out.",
	"Take it, get paid, then let's talk about lanes you haven't flown.",
	"Clients this close to home pay like it. Remember that.",
	"Think of this one as fuel money for somewhere further out.",
	"Everyone back here wants it cheap. Out there they pay for good pilots.",
]

const POOLS := {
	"nova_linger": NOVA_LINGER, "nova_class_open": NOVA_CLASS_OPEN, "nova_new_deepest": NOVA_NEW_DEEPEST,
	"kaelen_after_upgrade": KAELEN_AFTER_UPGRADE, "kaelen_shallow": KAELEN_SHALLOW,
	"kaelen_outward_lead": KAELEN_OUTWARD_LEAD, "kaelen_deep_survey": KAELEN_DEEP_SURVEY, "kaelen_pitch": KAELEN_PITCH,
}

# --- Timings (seconds of flight) -------------------------------------------------
const NOVA_LINGER_AFTER_S := 600.0
const NOVA_COOLDOWN_S := 1800.0
const KAELEN_SHALLOW_AFTER_S := 900.0
const KAELEN_SHALLOW_GAP := 2  # jumps shallower than the deepest
const KAELEN_COOLDOWN_S := 2700.0
## Never two nudges on the same moment.
const SAME_MOMENT_GAP_S := 60.0
## A new-depth line at most once per this many new depths.
const DEEPEST_LINE_EVERY := 2
const PITCH_CHANCE := 0.25
const OUTWARD_DISCOUNT := 0.7
const DEEP_SURVEY_DEPTH := 4
const STATE_KEY := "undercurrent"


static func fresh_state() -> Dictionary:
	return {
		"play_s": 0.0, "system_id": "", "system_s": 0.0, "deepest": -1, "last_deepest_line": -100,
		"nova_visit": false, "kaelen_visit": false, "last_nova": -1.0e9, "last_kaelen": -1.0e9, "last_any": -1.0e9,
		"next_class": -1, "upgrades": "", "upgrade_pending": false, "was_docked": false,
		"last_pitch_nudged": false, "rot": {},
	}


## One tick. `ctx`: {system_id, depth, flying, docked, next_class, upgrades}.
## Returns the nudges to deliver now: [{who: "nova"|"kaelen", line}].
static func step(s: Dictionary, ctx: Dictionary, delta: float) -> Array:
	var out: Array = []
	var flying := bool(ctx.get("flying", false))
	var depth := int(ctx.get("depth", 0))
	if flying:
		s["play_s"] = float(s["play_s"]) + delta
	var play := float(s["play_s"])
	# Arriving somewhere.
	var system_id := str(ctx.get("system_id", ""))
	if system_id != str(s["system_id"]):
		s["system_id"] = system_id
		s["system_s"] = 0.0
		s["nova_visit"] = false
		s["kaelen_visit"] = false
		if depth > int(s["deepest"]):
			if int(s["deepest"]) >= 0 and depth >= int(s["last_deepest_line"]) + DEEPEST_LINE_EVERY and _gap_ok(s):
				out.append(_say(s, "nova", "nova_new_deepest"))
				s["last_deepest_line"] = depth
			elif int(s["deepest"]) < 0:
				s["last_deepest_line"] = depth
			s["deepest"] = depth
	if flying:
		s["system_s"] = float(s["system_s"]) + delta
	# An upgrade fitted (any tier changed).
	var upgrades := str(ctx.get("upgrades", ""))
	if not str(s["upgrades"]).is_empty() and upgrades != str(s["upgrades"]):
		s["upgrade_pending"] = true
	s["upgrades"] = upgrades
	# A gate class opened. Class II is the guided rung: N.O.V.A. already has
	# her line there, so these start from Class III.
	var next_class := int(ctx.get("next_class", -1))
	if int(s["next_class"]) >= 3 and next_class > int(s["next_class"]) and _gap_ok(s):
		out.append(_say(s, "nova", "nova_class_open"))
	if next_class >= 0:
		s["next_class"] = next_class
	# Undocking after an upgrade: Kaelen.
	var docked := bool(ctx.get("docked", false))
	if bool(s["was_docked"]) and not docked and bool(s["upgrade_pending"]):
		s["upgrade_pending"] = false
		if play - float(s["last_kaelen"]) >= KAELEN_COOLDOWN_S and _gap_ok(s):
			out.append(_say(s, "kaelen", "kaelen_after_upgrade"))
	s["was_docked"] = docked
	# Lingering shallow.
	var deepest := int(s["deepest"])
	if flying and depth < deepest and float(s["system_s"]) >= NOVA_LINGER_AFTER_S and not bool(s["nova_visit"]) \
			and play - float(s["last_nova"]) >= NOVA_COOLDOWN_S and _gap_ok(s):
		out.append(_say(s, "nova", "nova_linger"))
	if flying and deepest - depth >= KAELEN_SHALLOW_GAP and float(s["system_s"]) >= KAELEN_SHALLOW_AFTER_S \
			and not bool(s["kaelen_visit"]) and play - float(s["last_kaelen"]) >= KAELEN_COOLDOWN_S and _gap_ok(s):
		out.append(_say(s, "kaelen", "kaelen_shallow"))
	return out


static func _gap_ok(s: Dictionary) -> bool:
	return float(s["play_s"]) - float(s["last_any"]) >= SAME_MOMENT_GAP_S


static func _say(s: Dictionary, who: String, pool: String) -> Dictionary:
	var play := float(s["play_s"])
	s["last_any"] = play
	if who == "nova":
		s["last_nova"] = play
		s["nova_visit"] = true
	else:
		s["last_kaelen"] = play
		s["kaelen_visit"] = true
	return {"who": who, "line": next_line(s, pool)}


## The next line of a pool: every line once before any repeats.
static func next_line(s: Dictionary, pool: String) -> String:
	var lines: Array = POOLS[pool]
	var rot: Dictionary = s.get("rot", {})
	var left: Array = rot.get(pool, [])
	if left.is_empty():
		left = range(lines.size())
		left.shuffle()
	var index := int(left.pop_back())
	rot[pool] = left
	s["rot"] = rot
	return str(lines[index])


## Kaelen's pitch tail: about 1 in 4 offers, never two in a row. `roll` 0..1.
static func pitch_tail(s: Dictionary, roll: float) -> String:
	if bool(s.get("last_pitch_nudged", false)) or roll >= PITCH_CHANCE:
		s["last_pitch_nudged"] = false
		return ""
	s["last_pitch_nudged"] = true
	return next_line(s, "kaelen_pitch")


# --- The node: gathers the context and delivers ----------------------------------

var _accum := 0.0


func current() -> Dictionary:
	var story := get_node_or_null("/root/StoryManager")
	if story == null:
		return fresh_state()
	var s = story.story_state.get(STATE_KEY)
	if not s is Dictionary or (s as Dictionary).is_empty():
		s = fresh_state()
		story.story_state[STATE_KEY] = s
	return s


func _process(delta: float) -> void:
	_accum += delta
	if _accum < 1.0:
		return
	var tick := _accum
	_accum = 0.0
	var story := get_node_or_null("/root/StoryManager")
	if story == null or not bool(story.story_state.get("first_contract_handed_in", false)):
		return
	for nudge in step(current(), _context(), tick):
		deliver(nudge)


func _context() -> Dictionary:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null:
		return {}
	var player = gs.player
	var docked := is_instance_valid(player) and bool(player.get("is_docked"))
	var flying := is_instance_valid(player) and not docked and not bool(player.get("destroyed")) \
		and not bool(gs.get("intro_cinematic_active"))
	var combat := get_node_or_null("/root/CombatManager")
	if combat != null and int(combat.get("state")) != 0:
		flying = false
	var nova := get_node_or_null("/root/Nova")
	if nova != null and nova.has_method("_world_hidden") and bool(nova.call("_world_hidden")):
		flying = false
	var scene := get_tree().current_scene
	var guide = scene.get("gate_rating_guide") if scene != null and "gate_rating_guide" in scene else null
	var next_class := int(guide.next_rung().get("next_class", -1)) if guide != null and is_instance_valid(guide) else -1
	var tiers := []
	for sys in ["weapons", "engine", "shields", "mining", "cargo", "power", "storage", "sensors"]:
		tiers.append(int((gs.current_upgrades.get(sys, {}) as Dictionary).get("tier", 1)))
	return {
		"system_id": str(gs.current_system_id),
		"depth": int(load("res://scripts/domain/DepthScaling.gd").current_depth()),
		"flying": flying, "docked": docked, "next_class": next_class,
		"upgrades": str(tiers),
	}


func deliver(nudge: Dictionary) -> void:
	var line := str(nudge.get("line", ""))
	if line.is_empty():
		return
	if str(nudge.get("who", "")) == "nova":
		var nova := get_node_or_null("/root/Nova")
		if nova != null and nova.has_method("ask_captain"):
			nova.ask_captain(line, "nav")
		return
	kaelen_over_comms(line)


static func kaelen_over_comms(line: String) -> void:
	var loop := Engine.get_main_loop()
	var gs: Node = (loop as SceneTree).root.get_node_or_null("GlobalState") if loop is SceneTree else null
	if gs == null:
		return
	gs.emit_npc_flavor({
		"npc_name": "Broker Kaelen",
		"voice_profile_id": gs.KAELEN_VOICE_PROFILE_ID,
		"line": line,
		"comms": true,
	})


# --- Hooks for her screen -----------------------------------------------------------

## Whether a gate leads deeper than where the ship is (unknown = deeper).
static func gate_is_outward(gate_id: String) -> bool:
	var loop := Engine.get_main_loop()
	var scene = (loop as SceneTree).current_scene if loop is SceneTree else null
	var registry = scene.get("system_registry") if scene != null and "system_registry" in scene else null
	if registry == null:
		return false
	var gate = registry.get_gate(gate_id)
	if gate == null:
		return false
	var Snapshot := load("res://scripts/story/premise/PremiseWorldSnapshot.gd")
	var gs: Node = (loop as SceneTree).root.get_node_or_null("GlobalState")
	var here := int(Snapshot._system_depth(str(gs.current_system_id))) if gs != null else 0
	var there := int(Snapshot._system_depth(str(registry.runtime_system_id(gate.destination_system_id))))
	return there < 0 or there > here
