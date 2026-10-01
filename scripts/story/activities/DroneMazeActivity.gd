extends Node

## The drone maze in the running game. With an asteroid or a wreck targeted
## and close, G sends the drone in and the captain flies it (DroneMazeView).
## Each asteroid and wreck can be worked once.
##
## Asteroids: every rock carries one tech-grade material in its cracks
## (Abe, 2026-09-25). These rare materials are what the ship's upgraded parts
## are made from: parts that must survive long radiation exposure, the
## extreme temperature swings of space, and the heat of the power plant and
## engines. Without them the ship cannot be upgraded. No station sells them,
## so the captain mines them; they are also worth a lot to sell. Upgrades need
## only a few, but each one is hard to get.
##
## Wrecks hold salvage, rarely a tech-grade material, and, when a story in
## this system left a clue in a wreck, a flight recorder: bringing it home
## puts the clue on the Loose ends board.
##
## Every flight uses up one piloted survey drone, home or lost. Drones are
## expensive at a station, and now and then one turns up intact in the debris
## of an enemy the captain destroyed.

const ViewType := preload("res://scripts/ui/DroneMazeView.gd")
const Maze := preload("res://scripts/story/activities/DroneMazeModel.gd")
const LeverageType := preload("res://scripts/story/premise/Leverage.gd")

const LAUNCH_KEY := KEY_G
const LAUNCH_RANGE := 300.0
const DRONE_ITEM := "survey_drone"

## Common ore and salvage pay a little; the materials are the prize.
const PAY := {"mineral": 120, "salvage": 110, "recorder": 0}
const CLEAN_BONUS := 100
## Tech-grade materials by the hazard they answer (see UPGRADE_MATERIALS in
## GlobalState). Each asteroid carries one, chosen by the rock.
const TECH_MATERIALS: Array[String] = ["thermal_lattice", "rad_quartz", "cryo_ferrite"]
## Each seam brought home yields the rock's material this often, provided
## the ore is at least this intact: cracked, it is only common ore.
const SEAM_MATERIAL_CHANCE := 0.5
const MATERIAL_MIN_INTEGRITY := 0.6
## Wreck crates rarely carry one.
const CRATE_MATERIAL_CHANCE := 0.1
## The top-tier material: sometimes, from a clean run with the ore nearly whole.
const CRYSTAL_ITEM := "resonant_crystal"
const CRYSTAL_CHANCE := 0.5
const CRYSTAL_INTEGRITY := 0.8
## A free drone from an enemy's debris.
const KILL_DRONE_CHANCE := 0.03

const RESULT_LINES := {
	"clean": ["Everything's aboard. Nicely flown.", "Full haul, and the drone's still in one piece. I'm almost impressed."],
	"partial": ["Drone's home with part of it. Better than nothing.", "Some of it. The rest can stay in the dark."],
	"failed_empty": ["Drone's home, hands empty.", "Nothing worth the trip. The drone's back, at least."],
	"lost": ["Lost the drone, and everything it was carrying.", "Signal's gone. So is the drone. And its load."],
	"recorder": ["The recorder's intact. I'm putting what's on it on the loose ends board.", "Got the flight recorder. There's something on it; it's on the loose ends board."],
	"free_drone": ["There's an intact survey drone in that debris. Free. I love free.", "Look at that. A survey drone, not a scratch on it. Their loss."],
}

var director: Node = null
var world_provider: Callable = Callable()
var _worked: Dictionary = {}
var _hinted: Dictionary = {}
var _view: Node = null
var _recorder_item: Dictionary = {}
var _material := ""


func _ready() -> void:
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null and gs.has_signal("player_kill"):
		gs.player_kill.connect(_on_player_kill)


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
				gs.emit_chatter("DRONE BAY", _hint_for(target), Color(0.5, 0.95, 0.85))
			load("res://scripts/ui/Wiki.gd").unlock("drone_maze")


func _hint_for(target: Node) -> String:
	var drones := drones_aboard()
	var what := ""
	if kind_of(target) == "asteroid":
		what = " Tech-grade %s in its cracks; a mining laser would shatter it." % material_name(material_for(target))
	if drones > 0:
		return "Press G to fly a survey drone inside (%d aboard).%s" % [drones, what]
	return "A piloted survey drone could get inside.%s" % what


func _unhandled_input(event: InputEvent) -> void:
	if _view != null or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.physical_keycode == LAUNCH_KEY and eligible_target() != null:
		get_viewport().set_input_as_handled()
		if not launch(eligible_target()):
			var gs := get_node_or_null("/root/GlobalState")
			if gs != null:
				gs.emit_chatter("DRONE BAY", "No survey drones aboard.", Color(1.0, 0.6, 0.4))


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
	# Only the rare red rocks with tech-grade seams (Asteroid.TECH_SEAM_GROUP).
	if node.is_in_group("tech_seam_asteroid"):
		return "asteroid"
	var script: Script = node.get_script()
	if script != null and script.resource_path.ends_with("Wreckage.gd"):
		return "wreck"
	return ""


static func _id_for(node: Node) -> String:
	var pid := str(node.get("persistent_id")) if node.get("persistent_id") != null else ""
	return pid if not pid.is_empty() else "node.%d" % node.get_instance_id()


## The tech-grade material an asteroid's cracks carry (fixed per rock).
static func material_for(node: Node) -> String:
	return TECH_MATERIALS[posmod(_id_for(node).hash(), TECH_MATERIALS.size())]


static func material_name(item_id: String) -> String:
	return item_id.replace("_", " ").capitalize().replace("Rad Quartz", "Rad-Quartz").replace("Cryo Ferrite", "Cryo-Ferrite")


## Spends one drone and sends it in. False (and nothing spent) without one.
func launch(target: Node3D) -> bool:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null or gs.inventory == null or not gs.inventory.remove(DRONE_ITEM, 1):
		return false
	var kind := kind_of(target)
	_worked[_id_for(target)] = true
	_material = material_for(target) if kind == "asteroid" else ""
	_recorder_item = {}
	if kind == "wreck" and director != null and is_instance_valid(director) and world_provider.is_valid():
		var world: Dictionary = world_provider.call()
		if not world.is_empty():
			_recorder_item = director.recorder_thread(world)
	_view = ViewType.new()
	add_child(_view)
	_view.finished.connect(_on_finished)
	_view.begin(hash(_id_for(target)) ^ randi(), kind, not _recorder_item.is_empty(), _material)
	return true


## What a finished run brings home: {credits, materials}. Rolls use `rng`.
static func haul(outcome_id: String, state: Dictionary, material: String, rng: RandomNumberGenerator) -> Dictionary:
	if str(state.get("end", "")) in ["wrecked", "timed_out"]:
		return {"credits": 0, "materials": []}
	var integrity := float(state.get("ore_integrity", 1.0))
	var credits := 0
	var materials: Array[String] = []
	for t in state.get("targets", []):
		if not bool(t["extracted"]):
			continue
		credits += int(PAY.get(str(t["kind"]), 0))
		match str(t["kind"]):
			"mineral":
				if not material.is_empty() and integrity >= MATERIAL_MIN_INTEGRITY and rng.randf() < SEAM_MATERIAL_CHANCE:
					materials.append(material)
			"salvage":
				if rng.randf() < CRATE_MATERIAL_CHANCE:
					materials.append(TECH_MATERIALS[rng.randi() % TECH_MATERIALS.size()])
	credits = int(round(credits * integrity))
	if outcome_id == "clean":
		credits += CLEAN_BONUS
		# A clean run through the cracks always brings home at least one.
		if not material.is_empty() and integrity >= MATERIAL_MIN_INTEGRITY and not materials.has(material):
			materials.append(material)
		if not material.is_empty() and integrity >= CRYSTAL_INTEGRITY and rng.randf() < CRYSTAL_CHANCE:
			materials.append(CRYSTAL_ITEM)
	return {"credits": credits, "materials": materials}


## Pays out and reports. Public so tests can feed a finished state.
func _on_finished(outcome_id: String, state: Dictionary, rng: RandomNumberGenerator = null) -> void:
	_view = null
	var gs := get_node_or_null("/root/GlobalState")
	if str(state.get("end", "")) in ["wrecked", "timed_out"]:
		if gs != null:
			gs.emit_chatter("DRONE BAY", "Drone lost with its load.", Color(1.0, 0.5, 0.4))
		_nova(_line("lost"))
		return
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var result := haul(outcome_id, state, _material, rng)
	var integrity := float(state.get("ore_integrity", 1.0))
	var pay := int(result["credits"])
	if pay > 0 and gs != null:
		gs.add_credits(pay)
		var cracked := "" if integrity >= 1.0 else " (%d%% of the ore survived)" % int(integrity * 100.0)
		gs.emit_chatter("DRONE BAY", "Common ore and salvage sold: %d credits%s." % [pay, cracked], Color(0.5, 0.95, 0.85))
	for item: String in result["materials"]:
		if gs != null and gs.inventory != null and gs.inventory.add(item, 1, 10):
			gs.emit_chatter("DRONE BAY", "Tech-grade material recovered: %s." % material_name(item), Color(1.0, 0.85, 0.3))
	if Maze.has_extracted(state, "recorder") and not _recorder_item.is_empty():
		var now := int(get_node("/root/CampaignClock").total_minutes) if has_node("/root/CampaignClock") else 0
		director.overhear(_recorder_item, now)
		# Leverage: what the recorder holds is something on the person it is about.
		if director.has_method("record_leverage_entry"):
			var system_id := str(gs.current_system_id) if gs != null else ""
			director.record_leverage_entry(LeverageType.make("recorder", str(_recorder_item.get("id", "")),
				str(_recorder_item.get("subject_name", "")), "Flight recorder: " + str(_recorder_item.get("text", "")), system_id, now))
		if gs != null:
			gs.emit_chatter("FLIGHT RECORDER", str(_recorder_item["text"]), Color(0.6, 0.85, 0.8))
		_nova(_line("recorder"))
		return
	_nova(_line("failed_empty" if outcome_id == "failed" else outcome_id))


## Now and then the debris of a kill holds an intact survey drone.
func _on_player_kill(_faction_name: String, roll: float = -1.0) -> void:
	if roll < 0.0:
		roll = randf()
	if roll >= KILL_DRONE_CHANCE:
		return
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null or gs.inventory == null or not gs.inventory.add(DRONE_ITEM, 1, 3):
		return
	gs.emit_chatter("DRONE BAY", "Recovered an intact survey drone from the wreckage.", Color(1.0, 0.85, 0.3))
	_nova(_line("free_drone"))


func _line(key: String) -> String:
	var pool: Array = RESULT_LINES.get(key, RESULT_LINES["partial"])
	return str(pool[randi() % pool.size()])


func _nova(text: String) -> void:
	var nova := get_node_or_null("/root/Nova")
	if nova != null and nova.has_method("ask_captain"):
		nova.ask_captain(text, "companion")
