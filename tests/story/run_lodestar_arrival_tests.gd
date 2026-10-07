extends SceneTree

## Core loop step 12: the last bearing marks the Lodestar's system (a gate out
## of where the Captain stands), the place's scene when the ship reaches it,
## and the season rolling over to a new Lodestar further out. Every arrival
## line is checked against the reserved topics.
##   Godot --headless --path . --script res://tests/story/run_lodestar_arrival_tests.gd --log-file <path> -- --baseline-offline

const Lodestar := preload("res://scripts/domain/Lodestar.gd")
const ReservedTopics := preload("res://scripts/story/ReservedTopics.gd")
const GuideType := preload("res://scripts/story/LodestarGuide.gd")
const LandmarkScript := preload("res://scripts/story/LodestarLandmark.gd")

var _failures: Array[String] = []

## A registry with just what the guide asks of one.
const FAKE_REGISTRY := """extends RefCounted
var systems := {}
func get_system(id):
	return systems.get(str(id))
func resolve_system_id(id):
	return StringName(str(id))
"""
const FAKE_DEF := """extends RefCounted
var id := &""
var display_name := ""
var gates: Array = []
"""
const FAKE_GATE := """extends RefCounted
var id := &""
var destination_system_id := &""
"""


func _initialize() -> void:
	# Never touch the player's Destination history (Lodestar.draw_for_new_campaign).
	load("res://scripts/domain/Lodestar.gd").history_path = ""
	await process_frame
	# --- Every card's scene -------------------------------------------------------
	var kinds := {}
	for card in Lodestar.deck():
		var id := str(card["id"])
		var scene: Dictionary = card.get("arrival_scene", {})
		_check(not scene.is_empty(), "%s has an arrival scene" % id)
		_check(str(scene.get("landmark", "")) in ["beacon", "fleet", "ring", "survey", "garden", "wrecks"], "%s: a landmark kind the builder knows" % id)
		kinds[str(scene.get("landmark", ""))] = true
		var lines: Array = scene.get("lines", [])
		_check(lines.size() >= 3, "%s: the place says its piece (3+ lines)" % id)
		var texts: Array = [str(scene.get("approach", "")), str(scene.get("nova", "")), str(scene.get("farewell", "")), str(scene.get("speaker", ""))]
		texts.append_array(lines)
		for text in texts:
			_check(not str(text).is_empty(), "%s: no empty line" % id)
			_check(ReservedTopics.is_clean(str(text)), "%s stays clear of the canon: %s" % [id, ReservedTopics.find_in(str(text))])
			for motif in ["callsign", "ship id", "your ship's name", "kaelen"]:
				_check(not str(text).to_lower().contains(motif), "%s's scene doesn't touch '%s'" % [id, motif])
	_check(kinds.size() == 6, "six different landmarks (%d)" % kinds.size())
	for kind in kinds:
		var mark = LandmarkScript.new()
		mark.kind = kind
		root.add_child(mark)
		_check(mark.get_child_count() > 1 and mark.is_in_group("lodestar"), "the %s landmark builds" % kind)
		mark.free()

	# --- Seasons (pure) -------------------------------------------------------------
	var first := {"id": "lighthouse", "known": true, "bearings": []}
	_check(Lodestar.season(first) == 1 and Lodestar.target_depth(first) == 13 and Lodestar.target_class(first) == 6, "season 1: Class VI, depth 13")
	_check(Lodestar.season_wedge_angle(5, first) == Lodestar.wedge_angle(5), "season 1 keeps its wedge")
	_check(Lodestar.bearing_ready(first, 0, 3) and not Lodestar.bearing_ready(first, 1, 3), "season 1 keeps step 10's classes")
	var story := {Lodestar.STATE_KEY: first.duplicate(true)}
	story[Lodestar.STATE_KEY]["pinned_system"] = "deep14"
	var second := Lodestar.next_season(story, 5, 14)
	_check(Lodestar.season(second) == 2 and str(second["id"]) != "lighthouse" and not bool(second["known"]), "season 2: a different card, not heard of yet")
	_check(Lodestar.target_depth(second) == 20 and Lodestar.target_class(second) >= 7, "season 2 lies further out (depth %d)" % Lodestar.target_depth(second))
	_check(Lodestar.past(second) == [{"id": "lighthouse", "season": 1, "system": "deep14"}], "the reached one is remembered with its system")
	var last_depth := 14
	for i in Lodestar.BEARINGS:
		var d := Lodestar.bearing_depth(second, i)
		_check(d > last_depth and d < Lodestar.target_depth(second), "season 2 bearing %d at depth %d, spread between start and target" % [i, d])
		_check(Lodestar.bearing_ready(second, i, d) and not Lodestar.bearing_ready(second, i, d - 1), "season 2 bearing %d waits for its depth" % i)
		last_depth = d
	_check(Lodestar.season_wedge_angle(5, second) != Lodestar.wedge_angle(5), "a new season points somewhere new")
	var deep := Lodestar.next_season({Lodestar.STATE_KEY: {"id": "garden", "season": 2, "target_depth": 20}}, 5, 30)
	_check(Lodestar.target_depth(deep) >= 30 + Lodestar.MIN_DEPTH_AHEAD, "always ahead of the Captain (%d)" % Lodestar.target_depth(deep))
	# Six seasons: every card once before any repeats, and none twice running.
	var run := {Lodestar.STATE_KEY: {"id": "lighthouse", "known": true, "bearings": []}}
	var seen := {"lighthouse": true}
	for i in 5:
		var nxt := Lodestar.next_season(run, 9, 13 + 7 * i)
		_check(not seen.has(str(nxt["id"])), "season %d: a card not yet reached (%s)" % [i + 2, nxt["id"]])
		seen[str(nxt["id"])] = true
	var seventh := Lodestar.next_season(run, 9, 60)
	_check(not str(seventh["id"]).is_empty() and Lodestar.past(seventh).size() == 6 and str(seventh["id"]) != str(Lodestar.past(seventh)[-1]["id"]), "after all six, the deck starts over, never the same twice running")
	_check(Lodestar.reward_credits(second) == 2 * Lodestar.reward_credits(first), "later Lodestars pay more")

	# --- Choosing the gate (pure) ---------------------------------------------------
	var gates := [
		{"gate_id": "back", "dest": "home", "dest_depth": 12, "visited": true},
		{"gate_id": "seen", "dest": "old", "dest_depth": 14, "visited": true},
		{"gate_id": "held", "dest": "kaelen", "dest_depth": 14, "visited": false, "withheld": true},
		{"gate_id": "new", "dest": "fresh", "dest_depth": 14, "visited": false},
	]
	_check(str(Lodestar.pick_pin(gates, 13)["gate_id"]) == "new", "deeper and unvisited, never back, never Kaelen's held gate")
	_check(str(Lodestar.pick_pin(gates.slice(0, 3), 13)["gate_id"]) == "seen", "a visited deeper system if that's all")
	_check(Lodestar.pick_pin(gates.slice(0, 1), 13).is_empty(), "no way deeper here: try the next system")

	# --- The guide: pin, place, scene, rollover ------------------------------------
	var gs: Node = root.get_node("GlobalState")
	var sm: Node = root.get_node("StoryManager")
	var saved_story: Dictionary = sm.story_state.duplicate(true)
	var saved_system := str(gs.current_system_id)
	var saved_credits := int(gs.player_credits)
	var registry = _make(FAKE_REGISTRY)
	registry.systems["deep13"] = _system("deep13", "Ashfall", [["g.back", "deep12"], ["g.out", "deep14"]])
	registry.systems["deep14"] = _system("deep14", "Lantern Reach", [["g.ret", "deep13"]])
	var scene_script := GDScript.new()
	scene_script.source_code = "extends Node\nvar lodestar_guide: Node = null\nvar system_registry = null\n"
	scene_script.reload()
	var fake_scene: Node = scene_script.new()
	fake_scene.system_registry = registry
	root.add_child(fake_scene)
	current_scene = fake_scene
	var depths := {"deep12": 12, "deep13": 13, "deep14": 14}
	var guide = GuideType.new()
	guide.set_process(false)
	guide.depth_of = func(id: String) -> int: return int(depths.get(id, -1))
	fake_scene.add_child(guide)
	fake_scene.lodestar_guide = guide
	sm.story_state["first_contract_handed_in"] = true
	sm.story_state[Lodestar.STATE_KEY] = {"id": "lighthouse", "known": true, "bearings": [0, 1, 2, 3]}
	gs.current_system_id = "deep13"
	_check(not guide.try_pin(), "four bearings: nothing to mark yet")
	guide.current()["bearings"].append(4)
	_check(guide.try_pin() and str(guide.current()["pinned_system"]) == "deep14" and str(guide.current()["pinned_gate"]) == "g.out", "the fifth: the gate out to deep14 is marked")
	_check(not guide.try_pin(), "marked once")
	gs.current_system_id = "deep14"
	var credits_before := int(gs.player_credits)
	var reached := guide.play_arrival()
	var now: Dictionary = guide.current()
	_check(reached and Lodestar.season(now) == 2 and str(now["id"]) != "lighthouse", "arriving rolls the season to a new card")
	_check(int(gs.player_credits) == credits_before + Lodestar.REWARD_PER_SEASON, "the place pays (%d)" % (int(gs.player_credits) - credits_before))
	_check(not bool(now["known"]) and not guide.try_introduce(), "the next rumour waits a while")
	_check(not guide.play_arrival(), "and it plays once")
	_check(Lodestar.past(now)[-1]["system"] == "deep14", "the place stays on the map")

	# Wiring.
	_check(FileAccess.get_file_as_string("res://scripts/story/LodestarGuide.gd").contains("check_arrival()"), "the guide watches for the arrival")
	var map_text := FileAccess.get_file_as_string("res://scripts/ui/BranchMapUI.gd")
	_check(map_text.contains("_lodestar_title_at(sys_id)") and map_text.contains("season_wedge_angle"), "the star map rings the place and follows the season")
	_check(FileAccess.get_file_as_string("res://scripts/UIManager.gd").contains("is_in_group(\"lodestar\")"), "the overview lists it as Lodestar")
	_check(preload("res://scripts/domain/SiteRevealModel.gd").LARGE_GROUPS.has("lodestar"), "sensors never hide it")

	current_scene = null
	sm.story_state = saved_story
	gs.current_system_id = saved_system
	gs.player_credits = saved_credits
	fake_scene.free()
	if _failures.is_empty():
		print("[PASS] Lodestar arrival and seasons")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _make(source: String):
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	return script.new()


func _system(id: String, display: String, links: Array):
	var def = _make(FAKE_DEF)
	def.id = StringName(id)
	def.display_name = display
	for link in links:
		var gate = _make(FAKE_GATE)
		gate.id = StringName(str(link[0]))
		gate.destination_system_id = StringName(str(link[1]))
		def.gates.append(gate)
	return def


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
