extends Node

## The twin wreck field event (docs/wreck_field_event_plan_2026_10_07.md).
## Once per campaign, mid-season, N.O.V.A. picks up two dead transponders on
## arrival in a deeper system; the field (WreckField) sits far out there,
## ringed by radiation. Four scan points at its edge each tell part of what
## happened (matched to the Hidden Hand's method when it can) and the first
## two also turn up a real story thread from the wreck's logs. The last one
## carries a Destination bearing if one is waiting, otherwise salvage.
##
## State: StoryManager.story_state["wreck_field"] =
##   {system, kind, scanned: [ids], done, arrived}.
## LINES ARE DRAFTS until Abe approves them (plan, section 5).

const STATE_KEY := "wreck_field"
const POLL_S := 0.25
## When it can start: a system this deep or deeper, after this many systems
## visited, while the main story is still hidden (so its clues count).
const MIN_DEPTH := 2
const MIN_VISITS := 5
## Where the field sits, from the system's centre (beyond the Destination's
## place, LodestarGuide.LANDMARK_DISTANCE).
const FIELD_DISTANCE := 3400.0 * preload("res://scripts/domain/WorldScale.gd").TRAVEL
## N.O.V.A.'s arrival line plays this close to the zone's edge.
const ARRIVAL_MARGIN := 1500.0
## Scan points that also carry a story thread from the logs.
const THREAD_POINTS := 2
## Salvage when no bearing is waiting: credits per system depth.
const SALVAGE_PER_DEPTH := 600
const LINE_DELAY_S := 4.0
const HoldType := preload("res://scripts/domain/ScanHoldController.gd")
const LodestarType := preload("res://scripts/domain/Lodestar.gd")
const HandType := preload("res://scripts/story/premise/HiddenHand.gd")
const FieldScript := preload("res://scripts/world/WreckField.gd")
const GREY := Color(0.75, 0.85, 0.9)

# --- Draft lines (Abe to approve) ---------------------------------------------
const LINE_DETECT := "Two transponders out past the edge of this system, Captain. Both dead, both on the same heading. Ships that size don't just stop. I've put them on the overview."
const LINE_ARRIVAL := "Two of them. Broken clean in half. Give me a moment, Captain."
const LINE_RADIATION := "Radiation, Captain. Whatever broke them is still hot in there. Back out and scan from the edge."
const LINE_FIRST_THREAD := "Whoever kept that log knew more than they should have. I'm keeping it."
const LINE_DONE := "That's everything the wreck will tell us from out here. If anything's worth carrying home, the drones can dive for it."
## What happened, by kind, one clue per scan point.
const CLUES := {
	"battle": {
		"bow": "Scorched entry holes along the bow, all from one side. They were fired on before they could turn.",
		"stern": "The drive is cold, not wrecked. They never tried to run.",
		"decks": "Blast doors sealed from inside. The crews were waiting for boarders.",
		"radiators": "The radiators were shot away first. Someone wanted them blind and overheating.",
	},
	"sabotage": {
		"bow": "No impact marks on the bow. The hull failed from the inside out.",
		"stern": "Both reactors shut down in the same second, on a command neither bridge sent.",
		"decks": "A maintenance hatch left open on each ship, in the same spot. Someone had a key to both.",
		"radiators": "The coolant lines were cut clean. Tools, not weapons.",
	},
	"collision": {
		"bow": "The bows are crumpled into each other. They met head on, at speed.",
		"stern": "Both drives were burning hard toward each other when they hit.",
		"decks": "Both nav decks were following the same course plot. It ran them straight into each other.",
		"radiators": "Radiator wings torn off sideways. Nobody braced. Nobody saw it coming.",
	},
	"mutiny": {
		"bow": "The bridge doors were cut open from the corridor side. Someone took the bow by force.",
		"stern": "The engine room was barricaded. Whoever held it held out longest.",
		"decks": "Crew quarters split down the middle: half the bunks stripped, half left.",
		"radiators": "One escape pod launched from each ship. Only one.",
	},
}
## The Hidden Hand's method -> what happened at the wreck.
const KIND_FOR_METHOD := {
	"proxy_violence": "battle", "false_flag": "battle",
	"sabotage": "sabotage", "manufactured_crisis": "sabotage",
	"forged_records": "collision", "information_control": "collision", "impersonation": "collision",
	"slow_infiltration": "mutiny", "bribery": "mutiny", "blackmail": "mutiny",
}
const KINDS := ["battle", "sabotage", "collision", "mutiny"]

## Swappable for tests.
var depth_of: Callable = func(system_id: String) -> int:
	return preload("res://scripts/story/premise/PremiseWorldSnapshot.gd")._system_depth(system_id)

var _poll := 0.0
var _field: Node3D = null
var _field_system := ""
var _hold := HoldType.new()
var _holding_point := ""
var _warned_in := ""


# --- Pure rules (tested) --------------------------------------------------------

## What happened at the wreck: matched to the Hidden Hand's method when one
## fits, else drawn from the seed.
static func kind_for(method: String, seed_value: int) -> String:
	if KIND_FOR_METHOD.has(method):
		return str(KIND_FOR_METHOD[method])
	return str(KINDS[posmod(seed_value, KINDS.size())])


## Whether the event can begin here and now. `ctx`: {started, tutorial_done,
## depth, visits, stage, lodestar_id, calm}.
static func can_start(ctx: Dictionary) -> bool:
	if bool(ctx.get("started", false)) or not bool(ctx.get("tutorial_done", false)) or not bool(ctx.get("calm", false)):
		return false
	# The Quiet War's Destination is these same wrecks.
	if str(ctx.get("lodestar_id", "")) == "quiet_war":
		return false
	return int(ctx.get("depth", 0)) >= MIN_DEPTH and int(ctx.get("visits", 0)) >= MIN_VISITS \
		and str(ctx.get("stage", "")) == "hidden"


static func clue(kind: String, point_id: String) -> String:
	return str((CLUES.get(kind, CLUES["battle"]) as Dictionary).get(point_id, ""))


# --- Runtime --------------------------------------------------------------------

func _process(delta: float) -> void:
	_poll += delta
	if _poll < POLL_S:
		return
	var step := _poll
	_poll = 0.0
	try_start()
	check_field()
	_scan_step(step)


## The campaign's wreck field state ({} without a StoryManager).
func current() -> Dictionary:
	var story := get_node_or_null("/root/StoryManager")
	if story == null:
		return {}
	if not story.story_state.get(STATE_KEY) is Dictionary:
		story.story_state[STATE_KEY] = {}
	return story.story_state[STATE_KEY]


func _director():
	var scene = get_tree().current_scene if is_inside_tree() else null
	return scene.get("premise_director") if scene != null and "premise_director" in scene else null


func _here() -> String:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null:
		return ""
	var scene = get_tree().current_scene if is_inside_tree() else null
	var registry = scene.system_registry if scene != null and "system_registry" in scene else null
	return str(registry.resolve_system_id(gs.current_system_id)) if registry != null else str(gs.current_system_id)


func _calm() -> bool:
	var gs := get_node_or_null("/root/GlobalState")
	var player = gs.player if gs != null else null
	if not is_instance_valid(player) or bool(player.get("is_docked")) or bool(player.get("destroyed")):
		return false
	var combat := get_node_or_null("/root/CombatManager")
	return combat == null or int(combat.get("state")) == 0


## Begins the event here when the moment is right. True if it did.
func try_start(force := false) -> bool:
	var s := current()
	var story := get_node_or_null("/root/StoryManager")
	var gs := get_node_or_null("/root/GlobalState")
	if story == null or gs == null:
		return false
	var director = _director()
	var dstate: Dictionary = director.state if director != null else {}
	var lodestar := LodestarType.state(story.story_state, int(gs.campaign_seed))
	var here := _here()
	var ctx := {
		"started": not str(s.get("system", "")).is_empty(),
		"tutorial_done": bool(story.story_state.get("first_contract_handed_in", false)),
		"depth": int(depth_of.call(here)),
		"visits": int(dstate.get("visits", 0)),
		"stage": str(HandType.main_story(dstate).get("stage", "")),
		"lodestar_id": str(lodestar.get("id", "")),
		"calm": _calm(),
	}
	if force:
		ctx.merge({"started": not str(s.get("system", "")).is_empty(), "tutorial_done": true, "depth": MIN_DEPTH, "visits": MIN_VISITS, "stage": "hidden", "lodestar_id": "", "calm": true}, true)
	if not can_start(ctx):
		return false
	s["system"] = here
	s["kind"] = kind_for(str(HandType.main_story(dstate).get("method", "")), int(gs.campaign_seed))
	s["scanned"] = []
	s["done"] = false
	print("[WreckField] started in %s (%s)" % [here, s["kind"]])
	check_field()
	_nova(LINE_DETECT)
	gs.emit_chatter("SENSORS", "Two dead transponders, far out in this system. On the overview as Twin wrecks.", GREY)
	return true


## In the field's system the field is there (it stays after it's done, for
## the drone dive).
func check_field() -> void:
	var s := current()
	var here := _here()
	if s.is_empty() or str(s.get("system", "")) != here or here.is_empty():
		return
	if not is_instance_valid(_field) or _field_system != here:
		_spawn_field(here)
		if not is_instance_valid(_field):
			return
	var gs := get_node_or_null("/root/GlobalState")
	var player = gs.player if gs != null else null
	if not bool(s.get("arrived", false)) and is_instance_valid(player) and _calm() \
			and (player as Node3D).global_position.distance_to(_field.global_position) <= FieldScript.ZONE_RADIUS + ARRIVAL_MARGIN:
		s["arrived"] = true
		_nova(LINE_ARRIVAL)


func field() -> Node3D:
	return _field


func _spawn_field(here: String) -> void:
	var gs := get_node_or_null("/root/GlobalState")
	var root: Node3D = gs.get_system_root() if gs != null and gs.has_method("get_system_root") else null
	if root == null:
		return
	if is_instance_valid(_field):
		_field.queue_free()
	var f := FieldScript.new()
	f.name = "WreckField"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("wreck_field:" + here)
	var a := rng.randf() * TAU
	f.position = Vector3(cos(a) * FIELD_DISTANCE, -120.0, sin(a) * FIELD_DISTANCE)
	root.add_child(f)
	f.zone_entered.connect(_on_zone_entered.bind(here))
	_field = f
	_field_system = here
	for id in current().get("scanned", []):
		f.mark_scanned(str(id))


func _on_zone_entered(here: String) -> void:
	if _warned_in == here:
		return
	_warned_in = here
	_nova(LINE_RADIATION)
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null:
		gs.emit_chatter("WARNING", "Radiation zone. Hull damage while inside.", Color(1.0, 0.45, 0.35))


## Holding close and slow at an unscanned point scans it (ScanHoldController's
## rules: within 300 m, under 10 m/s, out of combat, 3 seconds).
func _scan_step(delta: float) -> void:
	var s := current()
	if not is_instance_valid(_field) or bool(s.get("done", false)):
		return
	var gs := get_node_or_null("/root/GlobalState")
	var player = gs.player if gs != null else null
	if not is_instance_valid(player) or bool(player.get("is_docked")) or bool(player.get("destroyed")):
		return
	var nearest := ""
	var nearest_d := INF
	for id in _field.scan_point_ids():
		if (s.get("scanned", []) as Array).has(id):
			continue
		var d: float = (player as Node3D).global_position.distance_to(_field.scan_point(id).global_position)
		if d < nearest_d:
			nearest_d = d
			nearest = str(id)
	if nearest.is_empty() or nearest_d > HoldType.MAX_RANGE:
		if not _holding_point.is_empty():
			_holding_point = ""
			_hold.update(0.0, "", INF, 0.0, false)
		return
	var speed := (player.get("velocity") as Vector3).length() if player.get("velocity") is Vector3 else 0.0
	var combat := get_node_or_null("/root/CombatManager")
	var fighting := combat != null and int(combat.get("state")) != 0
	var report := _hold.update(delta, nearest, nearest_d, speed, fighting)
	if nearest != _holding_point and str(report.get("state", "")) == HoldType.STATE_HOLDING:
		_holding_point = nearest
		gs.emit_chatter("SCAN", "Scanning the %s… hold steady." % _field.call("_point_name", nearest).to_lower(), GREY)
	if str(report.get("state", "")) == HoldType.STATE_COMPLETE:
		_holding_point = ""
		complete_scan(nearest)


## A scan point done: its clue, a story thread from the logs on the first
## THREAD_POINTS, and the reward once all four are in. True if it counted.
func complete_scan(point_id: String) -> bool:
	var s := current()
	var scanned: Array = s.get("scanned", [])
	if scanned.has(point_id) or bool(s.get("done", false)):
		return false
	scanned.append(point_id)
	s["scanned"] = scanned
	if is_instance_valid(_field):
		_field.mark_scanned(point_id)
	var gs := get_node_or_null("/root/GlobalState")
	var title := str(_field.call("_point_name", point_id)) if is_instance_valid(_field) else point_id
	if gs != null:
		gs.emit_chatter("WRECK", "%s: %s" % [title, clue(str(s.get("kind", "battle")), point_id)], GREY)
	var director = _director()
	if scanned.size() <= THREAD_POINTS and director != null and director.has_method("wreck_field_clue"):
		var item: Dictionary = director.wreck_field_clue()
		if not item.is_empty():
			var now := int(get_node("/root/CampaignClock").total_minutes) if has_node("/root/CampaignClock") else 0
			director.overhear(item, now)
			if gs != null:
				gs.emit_chatter("WRECK", "In the logs: %s" % str(item["text"]), Color(1.0, 0.82, 0.45))
			if not bool(s.get("thread_said", false)):
				s["thread_said"] = true
				_later(func() -> void: _nova(LINE_FIRST_THREAD))
	if scanned.size() >= FieldScript.SCAN_POINTS.size():
		_finish()
	return true


func _finish() -> void:
	var s := current()
	s["done"] = true
	var gs := get_node_or_null("/root/GlobalState")
	print("[WreckField] all scanned (%s)" % str(s.get("kind", "")))
	var carried: bool = load("res://scripts/story/LodestarGuide.gd").offer_from("wreck")
	if not carried and gs != null:
		var credits := SALVAGE_PER_DEPTH * maxi(1, int(depth_of.call(_here())))
		gs.add_credits(credits)
		var ui = gs.get_ui_manager() if gs.has_method("get_ui_manager") else null
		if ui != null and ui.has_method("show_reward_banner"):
			ui.show_reward_banner("TWIN WRECKS  ·  SCANNED", "+%d SC in salvage data." % credits)
	_later(func() -> void: _nova(LINE_DONE), 2.0)


func _later(f: Callable, extra := 0.0) -> void:
	if is_inside_tree():
		get_tree().create_timer(LINE_DELAY_S + extra).timeout.connect(f)
	else:
		f.call()


func _nova(text: String) -> void:
	var nova := get_node_or_null("/root/Nova")
	if nova != null and nova.has_method("ask_captain"):
		nova.ask_captain(text, "nav")
