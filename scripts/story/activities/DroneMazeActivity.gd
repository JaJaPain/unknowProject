extends Node

## The drone maze in the running game. With an asteroid or a wreck targeted
## and close, G sends the drone in and the captain flies it (DroneMazeView).
## Each asteroid and wreck can be worked once.
##
## Asteroids hold crystal seams, sold as rare samples. Wrecks hold salvage,
## and when a story in this system left a clue in a wreck, a flight recorder:
## bringing it home puts the clue on the Loose ends board.
## Every flight uses up one piloted survey drone (a store consumable), home
## or lost (Abe, 2026-09-24): that keeps the maze a treat rather than the
## whole game. A lost drone also loses its load.

const ViewType := preload("res://scripts/ui/DroneMazeView.gd")
const Maze := preload("res://scripts/story/activities/DroneMazeModel.gd")

const LAUNCH_KEY := KEY_G
const LAUNCH_RANGE := 300.0
## High risk, high reward (Abe, 2026-09-24): the drone costs 150 and is
## used up either way, so a clean run pays well and a poor one loses money.
## Cracked ore sells for its remaining share.
const PAY := {"mineral": 90, "salvage": 70, "recorder": 0}
const CLEAN_BONUS := 80
## Each seam or crate brought home may also carry an expensive material.
const MATERIAL_CHANCE := 0.35
const MATERIALS := {
	"asteroid": ["fusion_cell", "power_coils", "sensor_cluster"],
	"wreck": ["hull_plating", "memory_bank", "encrypted_core", "power_coils"],
}
const DRONE_ITEM := "survey_drone"

const RESULT_LINES := {
	"clean": ["Everything's aboard. Nicely flown.", "Full haul, and the drone's still in one piece. I'm almost impressed."],
	"partial": ["Drone's home with part of it. Better than nothing.", "Some of it. The rest can stay in the dark."],
	"failed_empty": ["Drone's home, hands empty.", "Nothing worth the trip. The drone's back, at least."],
	"lost": ["Lost the drone, and everything it was carrying.", "Signal's gone. So is the drone. And its load."],
	"recorder": ["The recorder's intact. I'm putting what's on it on the loose ends board.", "Got the flight recorder. There's something on it you'll want to see."],
}

var director: Node = null
var world_provider: Callable = Callable()
var _worked: Dictionary = {}
var _hinted: Dictionary = {}
var _view: Node = null
var _target_ref: WeakRef = null
var _recorder_item: Dictionary = {}


func _process(_delta: float) -> void:
	if _view != null:
		return
	var target := eligible_target()
	if target != null:
		var id := _id_for(target)
		if not _hinted.has(id):
			_hinted[id] = true
			var gs := get_node_or_null("/root/GlobalState")
			if gs != null:
				var drones := drones_aboard()
				var hint := "Press G to fly a survey drone inside (%d aboard)." % drones if drones > 0 					else "A piloted survey drone could get inside. Stations sell them."
				gs.emit_chatter("DRONE BAY", hint, Color(0.5, 0.95, 0.85))


func _unhandled_input(event: InputEvent) -> void:
	if _view != null or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.physical_keycode == LAUNCH_KEY and eligible_target() != null:
		get_viewport().set_input_as_handled()
		if not launch(eligible_target()):
			var gs := get_node_or_null("/root/GlobalState")
			if gs != null:
				gs.emit_chatter("DRONE BAY", "No survey drones aboard. Stations sell them.", Color(1.0, 0.6, 0.4))


func drones_aboard() -> int:
	var gs := get_node_or_null("/root/GlobalState")
	return int(gs.inventory.get_quantity(DRONE_ITEM)) if gs != null and gs.inventory != null else 0


## The targeted asteroid or wreck, close enough and not yet worked, or null.
func eligible_target() -> Node3D:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null or bool(gs.get("intro_cinematic_active")):
		return null
	var player = gs.player
	var target = gs.active_target
	if not is_instance_valid(player) or not is_instance_valid(target) or bool(player.get("is_docked")) or bool(player.get("destroyed")):
		return null
	var combat := get_node_or_null("/root/CombatManager")
	if combat != null and int(combat.get("state")) != 0:
		return null
	if kind_of(target).is_empty() or _worked.has(_id_for(target)):
		return null
	if (player as Node3D).global_position.distance_to((target as Node3D).global_position) > LAUNCH_RANGE:
		return null
	return target


static func kind_of(node: Node) -> String:
	if node == null:
		return ""
	if node.is_in_group("asteroid"):
		return "asteroid"
	var script: Script = node.get_script()
	if script != null and script.resource_path.ends_with("Wreckage.gd"):
		return "wreck"
	return ""


static func _id_for(node: Node) -> String:
	var pid := str(node.get("persistent_id")) if node.get("persistent_id") != null else ""
	return pid if not pid.is_empty() else "node.%d" % node.get_instance_id()


## Spends one drone and sends it in. False (and nothing spent) without one.
func launch(target: Node3D) -> bool:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null or gs.inventory == null or not gs.inventory.remove(DRONE_ITEM, 1):
		return false
	var kind := kind_of(target)
	_worked[_id_for(target)] = true
	_target_ref = weakref(target)
	_recorder_item = {}
	if kind == "wreck" and director != null and is_instance_valid(director) and world_provider.is_valid():
		var world: Dictionary = world_provider.call()
		if not world.is_empty():
			_recorder_item = director.recorder_thread(world)
	_view = ViewType.new()
	add_child(_view)
	_view.finished.connect(_on_finished)
	_view.begin(hash(_id_for(target)) ^ randi(), kind, not _recorder_item.is_empty())
	return true


## Pays out and reports. Public so tests can feed a finished state.
func _on_finished(outcome_id: String, state: Dictionary) -> void:
	_view = null
	var gs := get_node_or_null("/root/GlobalState")
	var lost := str(state.get("end", "")) in ["wrecked", "timed_out"]
	if lost:
		if gs != null:
			gs.emit_chatter("DRONE BAY", "Drone lost with its load.", Color(1.0, 0.5, 0.4))
		_nova(_line("lost"))
		return
	var pay := 0
	var materials: Array[String] = []
	var kind := str(state.get("kind", "asteroid"))
	for t in state.get("targets", []):
		if bool(t["extracted"]):
			pay += int(PAY.get(str(t["kind"]), 0))
			var pool: Array = MATERIALS.get(kind, [])
			if str(t["kind"]) != "recorder" and not pool.is_empty() and randf() < MATERIAL_CHANCE:
				materials.append(str(pool[randi() % pool.size()]))
	var integrity := float(state.get("ore_integrity", 1.0))
	pay = int(round(pay * integrity))
	if outcome_id == "clean":
		pay += CLEAN_BONUS
	if pay > 0 and gs != null:
		gs.add_credits(pay)
		var cracked := "" if integrity >= 1.0 else " (%d%% of the ore survived)" % int(integrity * 100.0)
		gs.emit_chatter("DRONE BAY", "Haul sold: %d credits%s." % [pay, cracked], Color(0.5, 0.95, 0.85))
	for item in materials:
		if gs != null and gs.inventory != null and gs.inventory.add(item, 1, 10):
			gs.emit_chatter("DRONE BAY", "Recovered: %s." % item.capitalize(), Color(1.0, 0.85, 0.3))
	if Maze.has_extracted(state, "recorder") and not _recorder_item.is_empty():
		var now := int(get_node("/root/CampaignClock").total_minutes) if has_node("/root/CampaignClock") else 0
		director.overhear(_recorder_item, now)
		if gs != null:
			gs.emit_chatter("FLIGHT RECORDER", str(_recorder_item["text"]), Color(0.6, 0.85, 0.8))
		_nova(_line("recorder"))
		return
	_nova(_line("failed_empty" if outcome_id == "failed" else outcome_id))


func _line(key: String) -> String:
	var pool: Array = RESULT_LINES.get(key, RESULT_LINES["partial"])
	return str(pool[randi() % pool.size()])


func _nova(text: String) -> void:
	var nova := get_node_or_null("/root/Nova")
	if nova != null and nova.has_method("ask_captain"):
		nova.ask_captain(text, "companion")
