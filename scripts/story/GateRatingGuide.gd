extends Node

## Pushes the captain into the upgrade system instead of leaving them to guess
## (Abe, 2026-09-25). After the first two jumps, gates into systems the ship
## has never visited need hardened shields (Shields Mk II): the transit field
## on the deeper gates strips unhardened shields, and N.O.V.A. (who hates the
## gates anyway) will not go through without them. Going back to a system the
## ship has already visited is always allowed, so nobody is ever stranded.
##
## N.O.V.A. then walks them through it, one step at a time:
##   1. At the blocked gate she explains, and hands over a first survey drone
##      as an advance (once per campaign).
##   2. The first time a red rock (tech-grade seams) is targeted, she says
##      that is the one, and how to work it.
##   3. With the rad-quartz aboard, she sends them to the mechanic.
##   4. With the shields fitted, she grumbles and opens the gates.
## Hand-written lines; no model.

const REQUIRED_SYSTEM := "shields"
const REQUIRED_TIER := 2
## Systems the ship may reach before the rating is needed (the start system
## and the first two jumps).
const FREE_SYSTEMS := 3
const MATERIAL := "rad_quartz"
const DRONE_ITEM := "survey_drone"

const BLOCK_REASON := "The transit field on this gate needs hardened shields (Shields Mk II)."

const LINES := {
	"blocked": [
		"Captain, stop. This gate runs deeper than any we've used. Its transit field strips unhardened shields, and I'm not taking us through without Shields Mk II.",
		"Hardened shields need rad-quartz. Nobody sells it; you mine it. It grows in the cracks of the red rocks in the asteroid fields.",
		"A mining laser shatters those rocks, so it's a job for a survey drone. I've put one in the bay. Call it an advance.",
	],
	"red_rock": ["That red one. Tech-grade seams in the cracks. Get close, press G, and fly the drone in slowly. The ore is fragile."],
	"have_material": ["Rad-quartz aboard. Dock and have the mechanic fit Shields Mk II, then we can talk about that gate."],
	"rated": ["Shields hardened. Fine. The deeper gates will take us now. I still hate them."],
	"reminder": ["We still need Shields Mk II for that gate. Rad-quartz, from a red rock's cracks."],
}

var _visited: Array = []
var _stage := ""  # "", "need_material", "need_fit", "done"
var _drone_given := false
var _red_rock_told := false
var _last_reminder_ms := -100000000
var _poll := 0.0


func to_dict() -> Dictionary:
	return {"visited": _visited.duplicate(), "stage": _stage, "drone_given": _drone_given, "red_rock_told": _red_rock_told}


func load_from_dict(data: Dictionary) -> void:
	_visited = (data.get("visited", []) as Array).duplicate() if data.get("visited", []) is Array else []
	_stage = str(data.get("stage", ""))
	_drone_given = bool(data.get("drone_given", false))
	_red_rock_told = bool(data.get("red_rock_told", false))


func reset_for_new_campaign() -> void:
	load_from_dict({})


func stage() -> String:
	return _stage


## The ship arrived in (or started in) a system.
func note_system(system_id: String) -> void:
	if not system_id.is_empty() and not _visited.has(system_id):
		_visited.append(system_id)


func is_rated() -> bool:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null:
		return true
	var info: Dictionary = gs.current_upgrades.get(REQUIRED_SYSTEM, {})
	return int(info.get("tier", 1)) >= REQUIRED_TIER


## "" when the ship may jump to `destination_system_id`, else why not. No
## side effects: the UI asks this every frame.
func block_reason(destination_system_id: String) -> String:
	if is_rated() or _visited.has(destination_system_id) or _visited.size() < FREE_SYSTEMS:
		return ""
	return BLOCK_REASON


## The captain actually tried the gate and was refused: the first time starts
## N.O.V.A.'s walkthrough; later tries get a reminder now and then.
func on_refused() -> void:
	if _stage.is_empty():
		_start_walkthrough()
	elif _stage != "done":
		var now := Time.get_ticks_msec()
		if now - _last_reminder_ms > 60000:
			_last_reminder_ms = now
			_say(LINES["reminder"][0])


func _start_walkthrough() -> void:
	_stage = "need_material"
	_last_reminder_ms = Time.get_ticks_msec()
	var lines: Array = LINES["blocked"]
	_say(" ".join(lines))
	var gs := get_node_or_null("/root/GlobalState")
	if not _drone_given and gs != null and gs.inventory != null and gs.inventory.add(DRONE_ITEM, 1, 3):
		_drone_given = true
		gs.emit_chatter("DRONE BAY", "N.O.V.A. put a survey drone in the bay.", Color(1.0, 0.85, 0.3))
	if gs != null:
		gs.emit_chatter("N.O.V.A.", "Find a red asteroid, target it, press G.", Color(0.5, 0.95, 0.85))


func _process(delta: float) -> void:
	_poll += delta
	if _poll < 1.0:
		return
	_poll = 0.0
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null:
		note_system(str(gs.current_system_id))
	advance()


## One step of the walkthrough (public for tests).
func advance() -> void:
	if _stage.is_empty() or _stage == "done":
		if _stage.is_empty() and is_rated():
			_stage = "done"  # upgraded before ever meeting the gate: nothing to say
		return
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null:
		return
	if is_rated():
		_stage = "done"
		_say(LINES["rated"][0])
		return
	if _stage == "need_material":
		var needed: int = int(gs.upgrade_material_cost(REQUIRED_SYSTEM, REQUIRED_TIER).get(MATERIAL, 1))
		if gs.inventory != null and gs.inventory.get_quantity(MATERIAL) >= needed:
			_stage = "need_fit"
			_say(LINES["have_material"][0])
			return
		var target = gs.active_target
		if not _red_rock_told and is_instance_valid(target) and (target as Node).is_in_group("tech_seam_asteroid"):
			_red_rock_told = true
			_say(LINES["red_rock"][0])


func _say(text: String) -> void:
	var nova := get_node_or_null("/root/Nova")
	if nova != null and nova.has_method("ask_captain"):
		nova.ask_captain(text, "nav")
