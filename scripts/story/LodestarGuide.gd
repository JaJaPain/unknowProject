extends Node

## Brings the Lodestar into play (core loop step 9). After the tutorial, on
## the first arrival in a system away from home, N.O.V.A. passes on this
## campaign's first hint and puts the wedge on the star map. Bearings (step 10)
## and the arrival (step 12) build on the same state (Lodestar.gd).
##
## Hand-written lines from data/content/lodestars.json; no model.

const LodestarType := preload("res://scripts/domain/Lodestar.gd")
const MAP_LINE := "I've marked the rough direction on the star map."
const POLL_S := 1.0
const GateClassType := preload("res://scripts/domain/GateClass.gd")

## Bearings (core loop step 10, plan 4.2): bearing N becomes findable once the
## ship is in a system of gate class N + 2 or deeper, and the first activity
## the captain finishes there carries it. Where it came from, for the feed:
const SOURCES := {
	"receiver": "Buried in the intercept",
	"drone": "In what the drone brought back",
	"anomaly": "In the anomaly's readings",
	"investigation": "Among the investigation's findings",
	"kaelen": "Kaelen mentioned, in passing",
	"rumour": "Dockside rumour",
}
## Never missed for good: after this many new systems of the right class with
## the bearing still unfound, it arrives as a rumour.
const RUMOUR_AFTER_SYSTEMS := 2
## N.O.V.A. reacts after the activity's own lines have had their say.
const NOVA_DELAY_S := 6.0

## Swappable for tests.
var depth_of: Callable = func(system_id: String) -> int:
	return preload("res://scripts/story/premise/PremiseWorldSnapshot.gd")._system_depth(system_id)

var _poll := 0.0
## After a Lodestar is reached, the next one waits a while (step 12).
var _quiet_until_msec := 0


func _ready() -> void:
	var qm := get_node_or_null("/root/QuestManager")
	if qm != null and qm.has_signal("quest_completed_details"):
		qm.quest_completed_details.connect(_on_quest_completed)


func _process(delta: float) -> void:
	_poll += delta
	if _poll < POLL_S:
		return
	_poll = 0.0
	try_introduce()
	note_arrival()
	try_pin()
	check_arrival()


## Called by activities when the captain finishes one (SOURCES keys). True if
## it carried a bearing.
static func offer_from(source: String) -> bool:
	var loop := Engine.get_main_loop()
	var scene = (loop as SceneTree).current_scene if loop is SceneTree else null
	var guide = scene.get("lodestar_guide") if scene != null and "lodestar_guide" in scene else null
	return guide.offer(source) if guide != null and is_instance_valid(guide) else false


func _on_quest_completed(quest_data: Dictionary) -> void:
	var investigation = quest_data.get("investigation", {})
	if investigation is Dictionary and not (investigation as Dictionary).is_empty():
		offer("investigation")


## The index of the bearing findable here and now, or -1.
func pending_bearing() -> int:
	var s := current()
	if s.is_empty() or not bool(s.get("known", false)):
		return -1
	var found := LodestarType.bearings_found(s)
	if found >= LodestarType.BEARINGS:
		return -1
	var gs := get_node_or_null("/root/GlobalState")
	var depth := int(depth_of.call(str(gs.current_system_id))) if gs != null else 0
	return found if LodestarType.bearing_ready(s, found, depth) else -1


## An activity finished: if a bearing is waiting here, this one carries it.
func offer(source: String) -> bool:
	var index := pending_bearing()
	if index < 0:
		return false
	var s := current()
	var card := LodestarType.card_of(s)
	(s["bearings"] as Array).append(index)
	s["pending_seen"] = []
	var bearing: Dictionary = card["bearings"][index]
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null:
		gs.emit_chatter("LODESTAR", "%s: %s" % [str(SOURCES.get(source, SOURCES["rumour"])), str(bearing["text"])], Color(1.0, 0.82, 0.45))
		var ui = gs.get_ui_manager() if gs.has_method("get_ui_manager") else null
		if ui != null and ui.has_method("show_reward_banner"):
			var found := LodestarType.bearings_found(s)
			ui.show_reward_banner("%s  ·  BEARING %d OF %d" % [str(card["title"]).to_upper(), found, LodestarType.BEARINGS],
				"The star map's wedge is narrower." if found < LodestarType.BEARINGS else "It's marked on the star map.")
	var reaction := str(bearing["nova"])
	if is_inside_tree():
		get_tree().create_timer(NOVA_DELAY_S).timeout.connect(func() -> void: _nova(reaction))
	return true


## Each new system of the right class with a bearing still waiting counts;
## after RUMOUR_AFTER_SYSTEMS it turns up as a rumour (plan 4.2: it can't be
## missed for good).
func note_arrival() -> void:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null or pending_bearing() < 0:
		return
	var s := current()
	var seen: Array = s.get("pending_seen", [])
	var here := str(gs.current_system_id)
	if not seen.has(here):
		seen.append(here)
		s["pending_seen"] = seen
	if seen.size() >= RUMOUR_AFTER_SYSTEMS and _calm():
		offer("rumour")


## Undocked, alive and out of combat.
func _calm() -> bool:
	var gs := get_node_or_null("/root/GlobalState")
	var player = gs.player if gs != null else null
	if is_instance_valid(player) and (bool(player.get("is_docked")) or bool(player.get("destroyed"))):
		return false
	var combat := get_node_or_null("/root/CombatManager")
	return combat == null or int(combat.get("state")) == 0


func _nova(text: String) -> void:
	var nova := get_node_or_null("/root/Nova")
	if nova != null and nova.has_method("ask_captain"):
		nova.ask_captain(text, "nav")


## The campaign's Lodestar state ({} without a StoryManager).
func current() -> Dictionary:
	var story := get_node_or_null("/root/StoryManager")
	var gs := get_node_or_null("/root/GlobalState")
	if story == null or gs == null:
		return {}
	return LodestarType.state(story.story_state, int(gs.campaign_seed))


## Says the first hint once, when the moment is right. True if it did.
func try_introduce() -> bool:
	var story := get_node_or_null("/root/StoryManager")
	var gs := get_node_or_null("/root/GlobalState")
	if story == null or gs == null:
		return false
	if not bool(story.story_state.get("first_contract_handed_in", false)):
		return false
	if Time.get_ticks_msec() < _quiet_until_msec:
		return false
	var s := current()
	if s.is_empty() or bool(s.get("known", false)):
		return false
	if int(depth_of.call(str(gs.current_system_id))) < 1:
		return false
	var player = gs.player
	if is_instance_valid(player) and (bool(player.get("is_docked")) or bool(player.get("destroyed"))):
		return false
	var combat := get_node_or_null("/root/CombatManager")
	if combat != null and int(combat.get("state")) != 0:
		return false
	var card := LodestarType.card_of(s)
	if card.is_empty():
		return false
	s["known"] = true
	gs.emit_chatter("LODESTAR", "%s: %s" % [str(card["title"]), str(card["first_hint"])], Color(1.0, 0.82, 0.45))
	var nova := get_node_or_null("/root/Nova")
	if nova != null and nova.has_method("ask_captain"):
		# A later season's Lodestar: she knows the feeling by now.
		var opener := NEXT_SEASON_OPENER + " " if LodestarType.season(s) > 1 else ""
		nova.ask_captain("%s%s %s" % [opener, str(card["nova_first"]), MAP_LINE], "nav")
	load("res://scripts/ui/Wiki.gd").unlock("lodestar")
	return true


# --- The pin, the arrival and the next season (core loop step 12) -------------

const LandmarkScript := preload("res://scripts/story/LodestarLandmark.gd")
const KaelenLockedGateType := preload("res://scripts/story/KaelenLockedGate.gd")
const NEXT_SEASON_OPENER := "Here we go again, Captain."
## The scene plays when the ship is this close to the place.
const ARRIVAL_RANGE := 900.0
## Where the place sits, from the system's centre.
const LANDMARK_DISTANCE := 2200.0
## Seconds between the place's lines.
const LINE_GAP_S := 6.0
## The next Lodestar's rumour waits this long after the scene.
const NEXT_RUMOUR_DELAY_MS := 60000

var _landmark: Node3D = null
var _landmark_system := ""
var _approach_said_in := ""
var _playing := false


## The resolved id of the system the ship is in ("" without a registry).
func _here() -> String:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null:
		return ""
	var registry = _registry()
	return str(registry.resolve_system_id(gs.current_system_id)) if registry != null else str(gs.current_system_id)


func _registry():
	var scene = get_tree().current_scene if is_inside_tree() else null
	return scene.system_registry if scene != null and "system_registry" in scene else null


## Every bearing found and nothing marked yet: mark one of this system's
## gates out as the way there (deeper, unvisited if possible, never the gate
## Kaelen is holding back) and put it on the charts. If no gate here fits, it
## tries again in the next system. True if it pinned.
func try_pin() -> bool:
	var s := current()
	if s.is_empty() or not bool(s.get("known", false)) or LodestarType.is_pinned(s):
		return false
	if LodestarType.bearings_found(s) < LodestarType.BEARINGS:
		return false
	var registry = _registry()
	var gs := get_node_or_null("/root/GlobalState")
	var story := get_node_or_null("/root/StoryManager")
	if registry == null or gs == null or story == null:
		return false
	var here_def = registry.get_system(gs.current_system_id)
	if here_def == null:
		return false
	var visited: Array = story.story_state.get("surveyed_systems", [])
	var gates: Array = []
	for gate in here_def.gates:
		var dest := str(registry.resolve_system_id(gate.destination_system_id))
		gates.append({"gate_id": str(gate.id), "dest": dest, "dest_depth": int(depth_of.call(dest)),
			"visited": visited.has(dest), "withheld": KaelenLockedGateType.is_withheld(story.story_state, str(gate.id))})
	var chosen := LodestarType.pick_pin(gates, int(depth_of.call(str(gs.current_system_id))))
	if chosen.is_empty():
		return false
	LodestarType.pin(s, str(chosen["dest"]), str(chosen["gate_id"]))
	var gd := get_node_or_null("/root/GateDiscovery")
	if gd != null and gd.has_method("mark_known"):
		gd.mark_known(str(chosen["gate_id"]))
	var dest_def = registry.get_system(chosen["dest"])
	var where := str(dest_def.display_name) if dest_def != null else "the next system out"
	print("[Lodestar] pinned %s at %s via %s" % [str(s["id"]), str(chosen["dest"]), str(chosen["gate_id"])])
	gs.emit_chatter("LODESTAR", "%s is marked on the star map: %s, through a gate out of this system." % [str(LodestarType.card_of(s)["title"]), where], Color(1.0, 0.82, 0.45))
	return true


## In the Lodestar's system: the place is there, N.O.V.A. points it out, and
## the scene plays once the ship is close. Places already reached stay put.
func check_arrival() -> void:
	var here := _here()
	if here.is_empty():
		return
	var s := current()
	var card := {}
	var live := false
	if not s.is_empty() and str(s.get("pinned_system", "")) == here:
		card = LodestarType.card_of(s)
		live = true
	else:
		for p in LodestarType.past(s):
			if str(p.get("system", "")) == here:
				card = LodestarType.by_id(str(p.get("id", "")))
	if card.is_empty():
		return
	if not is_instance_valid(_landmark) or _landmark_system != here:
		if not _spawn_landmark(card, here):
			return
	if not live or _playing:
		return
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null or not _calm():
		return
	if _approach_said_in != here:
		_approach_said_in = here
		var scene_data: Dictionary = card.get("arrival_scene", {})
		_nova(str(scene_data.get("approach", "There it is, Captain.")))
		gs.emit_chatter("LODESTAR", "%s is on the overview. Fly in close." % str(card["title"]), Color(1.0, 0.82, 0.45))
	var player = gs.player
	if is_instance_valid(player) and (player as Node3D).global_position.distance_to(_landmark.global_position) <= ARRIVAL_RANGE:
		play_arrival()


func _spawn_landmark(card: Dictionary, here: String) -> bool:
	var gs := get_node_or_null("/root/GlobalState")
	var root: Node3D = gs.get_system_root() if gs != null and gs.has_method("get_system_root") else null
	if root == null:
		return false
	if is_instance_valid(_landmark):
		_landmark.queue_free()
	var mark := LandmarkScript.new()
	mark.name = "Lodestar"
	mark.kind = str((card.get("arrival_scene", {}) as Dictionary).get("landmark", "beacon"))
	mark.display_name = str(card["title"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("lodestar_place:" + here)
	var a := rng.randf() * TAU
	mark.position = Vector3(cos(a) * LANDMARK_DISTANCE, 60.0, sin(a) * LANDMARK_DISTANCE)
	root.add_child(mark)
	_landmark = mark
	_landmark_system = here
	return true


## The Lodestar reached: the place's scene, the reward, and the season rolls
## over to a new Lodestar further out. State changes first (a save mid-scene
## keeps it); the lines follow on timers.
func play_arrival() -> bool:
	var s := current()
	var gs := get_node_or_null("/root/GlobalState")
	var story := get_node_or_null("/root/StoryManager")
	if s.is_empty() or gs == null or story == null or not LodestarType.is_pinned(s) or _playing:
		return false
	var card := LodestarType.card_of(s)
	var scene_data := LodestarType.arrival_scene(s)
	var reward := LodestarType.reward_credits(s)
	var finished_season := LodestarType.season(s)
	var depth := int(depth_of.call(str(gs.current_system_id)))
	_playing = true
	gs.add_credits(reward)
	var next := LodestarType.next_season(story.story_state, int(gs.campaign_seed), depth)
	_quiet_until_msec = Time.get_ticks_msec() + NEXT_RUMOUR_DELAY_MS
	print("[Lodestar] reached %s (season %d), +%d SC; next: %s, depth %d+" % [str(card["id"]), finished_season, reward, str(next["id"]), int(next["target_depth"])])
	load("res://scripts/ui/Wiki.gd").unlock("lodestar_reached")
	var ui = gs.get_ui_manager() if gs.has_method("get_ui_manager") else null
	if ui != null and ui.has_method("show_reward_banner"):
		ui.show_reward_banner("%s  ·  REACHED" % str(card["title"]).to_upper(), "+%d SC. Season %d complete." % [reward, finished_season])
	var gold := Color(1.0, 0.82, 0.45)
	var speaker := str(scene_data.get("speaker", str(card["title"]).to_upper()))
	var beats: Array = []
	for line in scene_data.get("lines", []):
		beats.append(func() -> void: gs.emit_chatter(speaker, str(line), gold))
	var reaction := str(scene_data.get("nova", ""))
	if not reaction.is_empty():
		beats.append(func() -> void: _nova(reaction))
	var farewell := str(scene_data.get("farewell", ""))
	if not farewell.is_empty():
		beats.append(func() -> void: gs.emit_chatter(speaker, farewell, gold))
	beats.append(func() -> void: _playing = false)
	if not is_inside_tree():
		for beat in beats:
			beat.call()
		return true
	for i in beats.size():
		get_tree().create_timer(2.0 + LINE_GAP_S * i).timeout.connect(beats[i])
	return true
