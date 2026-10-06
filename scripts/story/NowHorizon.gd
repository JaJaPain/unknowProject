extends Node

## The "Now" horizon (docs/core_loop_plan_2026_10_01.md 4.4, core loop step
## 13): the player should always have something to do next. When the ship has
## been flying a while with no job, N.O.V.A. points at one thing worth doing,
## in this order:
##   1. the upgrade goal is paid for: dock and fit it;
##   2. a Lodestar bearing is waiting in this system: an activity will carry it;
##   3. a loose end the Captain pinned: go chase it;
##   4. otherwise: the station board, or Kaelen.
## ("Next" is the goal card, "Far" the Lodestar wedge; both already always
## show something.)
##
## AUTHORED ONLY. Light: one line after a few minutes of jobless flight, then a
## long cooldown, never the same reason twice running, and never on top of an
## undercurrent nudge. The decisions are a pure step() over a state
## dictionary (StoryManager.story_state["now_horizon"]).

const POOLS := {
	"goal_ready": [
		"We've got everything for the upgrade, Captain. Next station, let's get it fitted.",
		"The bill's covered. Dock somewhere and we'll fit it.",
		"Parts money, ore, the lot. All that's missing is a station and a wrench.",
	],
	"bearing": [
		"I've got a feeling there's a bearing in this system. The receiver, a drone dive or an anomaly might turn it up.",
		"If our destination left a trace here, an activity will find it. Receiver, drones, anomalies. Your pick.",
		"This far out, the trail picks up. Let's do something here and see what comes back.",
	],
	"loose_end": [
		"That thread you pinned is still loose. Might be worth chasing while we're idle.",
		"You pinned a loose end, Captain. It's not going to tie itself.",
		"Nothing on the books. That pinned lead on the board would fill the time nicely.",
	],
	"board": [
		"No job on the books, Captain. The station board always has something.",
		"We're flying for free at the moment. Kaelen or the board could fix that.",
		"Nothing on the tracker. Dock and check the board? I'd like to be useful.",
		"Quiet day. Quiet days don't pay for upgrades. The board might.",
	],
}
const ORDER := ["goal_ready", "bearing", "loose_end", "board"]

## Jobless flight before she says anything (seconds, since the last undock
## or job).
const IDLE_AFTER_S := 150.0
const COOLDOWN_S := 600.0
const STATE_KEY := "now_horizon"


static func fresh_state() -> Dictionary:
	return {"play_s": 0.0, "idle_s": 0.0, "last_said": -1.0e9, "last_reason": "", "rot": {}}


## One tick. `ctx`: {flying, has_job, goal_ready, bearing_here, pinned_loose_end,
## quiet (no other nudge just now)}. Returns a line to say, or "".
static func step(s: Dictionary, ctx: Dictionary, delta: float) -> String:
	var flying := bool(ctx.get("flying", false))
	if flying:
		s["play_s"] = float(s["play_s"]) + delta
	if bool(ctx.get("has_job", false)) or not flying:
		# A job, or docked (the board is right there): start counting again.
		s["idle_s"] = 0.0
		return ""
	s["idle_s"] = float(s["idle_s"]) + delta
	if float(s["idle_s"]) < IDLE_AFTER_S or float(s["play_s"]) - float(s["last_said"]) < COOLDOWN_S:
		return ""
	if not bool(ctx.get("quiet", true)):
		return ""
	var reason := reason_for(ctx, str(s["last_reason"]))
	s["last_said"] = float(s["play_s"])
	s["last_reason"] = reason
	s["idle_s"] = 0.0
	return next_line(s, reason)


## The first reason that applies, skipping the one used last time unless it's
## the only one ("board" always applies).
static func reason_for(ctx: Dictionary, last: String) -> String:
	var keys := {"goal_ready": "goal_ready", "bearing": "bearing_here", "loose_end": "pinned_loose_end"}
	var applies: Array = []
	for reason in ORDER:
		if reason == "board" or bool(ctx.get(keys.get(reason, ""), false)):
			applies.append(reason)
	for reason in applies:
		if reason != last:
			return reason
	return str(applies[0])


## Every line of a pool once before any repeats.
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
	var line := step(current(), _context(), tick)
	if not line.is_empty():
		var nova := get_node_or_null("/root/Nova")
		if nova != null and nova.has_method("ask_captain"):
			nova.ask_captain(line, "nav")


func _context() -> Dictionary:
	var gs := get_node_or_null("/root/GlobalState")
	var story := get_node_or_null("/root/StoryManager")
	if gs == null or story == null:
		return {}
	var player = gs.player
	var flying := is_instance_valid(player) and not bool(player.get("is_docked")) and not bool(player.get("destroyed")) \
		and not bool(gs.get("intro_cinematic_active"))
	var combat := get_node_or_null("/root/CombatManager")
	if combat != null and int(combat.get("state")) != 0:
		flying = false
	var qm := get_node_or_null("/root/QuestManager")
	var has_job := qm != null and not (qm.active_quest as Dictionary).is_empty()
	var scene := get_tree().current_scene
	# The goal paid for (credits, ore and materials all in hand).
	var goal: Dictionary = load("res://scripts/ui/UpgradeGoalCard.gd").current_goal()
	var goal_ready := not goal.is_empty() and bool(load("res://scripts/domain/UpgradeGoal.gd").is_ready(gs, goal))
	var guide = scene.get("lodestar_guide") if scene != null and "lodestar_guide" in scene else null
	var bearing_here := guide != null and is_instance_valid(guide) and int(guide.pending_bearing()) >= 0
	var pinned := false
	if scene != null and scene.has_method("premise_main_story_threads"):
		for t in scene.premise_main_story_threads():
			if bool((t as Dictionary).get("pinned", false)):
				pinned = true
				break
	# Never on top of an undercurrent nudge.
	var under: Dictionary = story.story_state.get("undercurrent", {})
	var quiet := under.is_empty() or float(under.get("play_s", 0.0)) - float(under.get("last_any", -1.0e9)) >= 60.0
	return {"flying": flying, "has_job": has_job, "goal_ready": goal_ready, "bearing_here": bearing_here,
		"pinned_loose_end": pinned, "quiet": quiet}
