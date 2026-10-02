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
## A clean run (everything out, drone home intact) brings home at least this
## many of the rock's material (Abe, 2026-10-02: drones stay 800 SC and
## special, a good dive pays double; the economy sim showed one per dive made
## the climb need ~65 drones).
const MATERIALS_PER_CLEAN_DIVE := 2
## Wreck crates rarely carry one.
const CRATE_MATERIAL_CHANCE := 0.1
## The top-tier material: sometimes, from a clean run with the ore nearly whole.
const CRYSTAL_ITEM := "resonant_crystal"
const CRYSTAL_CHANCE := 0.5
const CRYSTAL_INTEGRITY := 0.8
## A free drone from an enemy's debris.
const KILL_DRONE_CHANCE := 0.03
## The first rung is guided (core loop 3.4): until the first rock dive is done,
## red rocks carry the material Shields Mk II needs, so the walkthrough never
## sends the captain into the wrong rock.
const FIRST_DIVE_FLAG := "first_rock_dive_done"
const FIRST_DIVE_MATERIAL := "rad_quartz"
## If that first dive comes home without it, N.O.V.A. produces a spare, once
## (Abe, 2026-10-02: "make up a reason she has a spare... give it some flair").
const SPARE_FLAG := "nova_spare_drone_given"
## ...and if it does bring it home, she makes sure the captain knows that was
## the easy one (Abe, 2026-10-02).
const LUCKY_LINES := [
	"Don't get used to that. We lucked out: the seam was sitting right by the mouth of the crack. They're never that easy. Next time it'll be deep in, and the rock will fight you for every gram.",
]
const SPARE_LINES := [
	"Don't panic. I have a spare. Back at our first dock there was a survey drone drifting loose past the cargo ring, blinking its little light at nobody. It looked lonely. So I nicked it. It's in the bay. Please don't crash this one, I've named it Pebble.",
]

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
## Taught like the receiver (Abe, 2026-09-30: players never knew it existed).
## A prompt stays on screen while a target is in reach; the first time ever,
## N.O.V.A. explains the drone bay once (saved in story_state).
const TAUGHT_FLAG := "drone_maze_taught"
const TEACH_LINE := "That one's worth a closer look, and not with the mining laser. We carry piloted survey drones for this. Press %s and I'll hand you one: fly it in slowly, pick up what you find, and bring it back out. Each flight uses up a drone, and if you crash it, its load is gone with it."
var _prompt_layer: CanvasLayer = null
var _prompt: PanelContainer = null
var _prompt_label: Label = null
var _prompt_t := 0.0
var _recorder_item: Dictionary = {}
var _material := ""


func _ready() -> void:
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null and gs.has_signal("player_kill"):
		gs.player_kill.connect(_on_player_kill)


func _process(delta: float) -> void:
	_update_prompt(delta)
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
			_maybe_teach()


func _maybe_teach() -> void:
	var story := get_node_or_null("/root/StoryManager")
	if story == null or bool(story.story_state.get(TAUGHT_FLAG, false)):
		return
	story.story_state[TAUGHT_FLAG] = true
	_nova(TEACH_LINE % OS.get_keycode_string(LAUNCH_KEY))


## "[G] LAUNCH SURVEY DRONE" at the bottom of the screen while a target is in
## reach (above the receiver prompt when both show). With no drones aboard it
## says where to get one instead.
func _update_prompt(delta: float) -> void:
	var show := _view == null and eligible_target() != null
	if show and _prompt == null:
		_build_prompt()
	if _prompt == null:
		return
	_prompt.visible = show
	if not show:
		return
	var drones := drones_aboard()
	if drones > 0:
		_prompt_label.text = "[%s]  LAUNCH SURVEY DRONE   ·   %d aboard" % [OS.get_keycode_string(LAUNCH_KEY), drones]
		_prompt_t += delta
		_prompt.modulate.a = 0.75 + 0.25 * sin(_prompt_t * 3.0)
	else:
		_prompt_label.text = "No survey drones aboard   ·   station stores sell them"
		_prompt.modulate.a = 0.7


func _build_prompt() -> void:
	_prompt_layer = CanvasLayer.new()
	_prompt_layer.layer = 5
	add_child(_prompt_layer)
	_prompt = PanelContainer.new()
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.offset_top = -205.0
	_prompt.offset_bottom = -165.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.08, 0.1, 0.85)
	style.border_color = Color(0.5, 0.95, 0.85, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_prompt.add_theme_stylebox_override("panel", style)
	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", 18)
	_prompt_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.92))
	_prompt.add_child(_prompt_label)
	_prompt_layer.add_child(_prompt)


func _hint_for(target: Node) -> String:
	var drones := drones_aboard()
	var what := ""
	if kind_of(target) == "asteroid":
		what = " Tech-grade %s in its cracks; a mining laser would shatter it." % material_name(rock_material(target))
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


## What this rock's cracks carry in this campaign: the first rock dive is
## always FIRST_DIVE_MATERIAL, after that the rock's own.
func rock_material(node: Node) -> String:
	return FIRST_DIVE_MATERIAL if not _story_flag(FIRST_DIVE_FLAG) else material_for(node)


func _story_flag(flag: String) -> bool:
	var story := get_node_or_null("/root/StoryManager")
	return story != null and bool(story.story_state.get(flag, false))


func _set_story_flag(flag: String) -> void:
	var story := get_node_or_null("/root/StoryManager")
	if story != null:
		story.story_state[flag] = true


static func material_name(item_id: String) -> String:
	return item_id.replace("_", " ").capitalize().replace("Rad Quartz", "Rad-Quartz").replace("Cryo Ferrite", "Cryo-Ferrite")


## Spends one drone and sends it in. False (and nothing spent) without one.
func launch(target: Node3D) -> bool:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null or gs.inventory == null or not gs.inventory.remove(DRONE_ITEM, 1):
		return false
	var kind := kind_of(target)
	_worked[_id_for(target)] = true
	_material = rock_material(target) if kind == "asteroid" else ""
	_recorder_item = {}
	if kind == "wreck" and director != null and is_instance_valid(director) and world_provider.is_valid():
		var world: Dictionary = world_provider.call()
		if not world.is_empty():
			_recorder_item = director.recorder_thread(world)
	_view = ViewType.new()
	add_child(_view)
	_view.finished.connect(_on_finished)
	# The campaign's first rock dive is an easy one (Maze.EASY).
	var easy := kind == "asteroid" and not _story_flag(FIRST_DIVE_FLAG)
	_view.begin(hash(_id_for(target)) ^ randi(), kind, not _recorder_item.is_empty(), _material, easy)
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
		# A clean run through the cracks always brings home at least two.
		if not material.is_empty() and integrity >= MATERIAL_MIN_INTEGRITY:
			while materials.count(material) < MATERIALS_PER_CLEAN_DIVE:
				materials.append(material)
		if not material.is_empty() and integrity >= CRYSTAL_INTEGRITY and rng.randf() < CRYSTAL_CHANCE:
			materials.append(CRYSTAL_ITEM)
	return {"credits": credits, "materials": materials}


## Pays out and reports. Public so tests can feed a finished state.
func _on_finished(outcome_id: String, state: Dictionary, rng: RandomNumberGenerator = null) -> void:
	_view = null
	var gs := get_node_or_null("/root/GlobalState")
	var first_rock_dive := not _material.is_empty() and not _story_flag(FIRST_DIVE_FLAG)
	if not _material.is_empty():
		_set_story_flag(FIRST_DIVE_FLAG)
	if str(state.get("end", "")) in ["wrecked", "timed_out"]:
		if gs != null:
			gs.emit_chatter("DRONE BAY", "Drone lost with its load.", Color(1.0, 0.5, 0.4))
		if not (first_rock_dive and _give_spare()):
			_nova(_line("lost"))
		return
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var result := haul(outcome_id, state, _material, rng)
	if first_rock_dive and not (result["materials"] as Array).has(_material) and _give_spare():
		# She speaks for this one; the haul below still pays out quietly.
		_pay_out(result, state, gs)
		return
	_pay_out(result, state, gs)
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
	if first_rock_dive and (result["materials"] as Array).has(_material):
		_nova(str(LUCKY_LINES[randi() % LUCKY_LINES.size()]))
		return
	_nova(_line("failed_empty" if outcome_id == "failed" else outcome_id))


func _pay_out(result: Dictionary, state: Dictionary, gs: Node) -> void:
	var integrity := float(state.get("ore_integrity", 1.0))
	var pay := int(result["credits"])
	if pay > 0 and gs != null:
		gs.add_credits(pay)
		var cracked := "" if integrity >= 1.0 else " (%d%% of the ore survived)" % int(integrity * 100.0)
		gs.emit_chatter("DRONE BAY", "Common ore and salvage sold: %d credits%s." % [pay, cracked], Color(0.5, 0.95, 0.85))
	for item: String in result["materials"]:
		if gs != null and gs.inventory != null and gs.inventory.add(item, 1, 10):
			gs.emit_chatter("DRONE BAY", "Tech-grade material recovered: %s." % material_name(item), Color(1.0, 0.85, 0.3))


## N.O.V.A.'s stolen spare, once per campaign. True if she handed it over.
func _give_spare() -> bool:
	if _story_flag(SPARE_FLAG):
		return false
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null or gs.inventory == null or not gs.inventory.add(DRONE_ITEM, 1, 3):
		return false
	_set_story_flag(SPARE_FLAG)
	gs.emit_chatter("DRONE BAY", "N.O.V.A. put a survey drone in the bay. It has a name written on it.", Color(1.0, 0.85, 0.3))
	_nova(str(SPARE_LINES[randi() % SPARE_LINES.size()]))
	return true


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
