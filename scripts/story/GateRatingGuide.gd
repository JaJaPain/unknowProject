extends Node

## Pushes the captain into the upgrade system instead of leaving them to guess
## (Abe, 2026-09-25). Since 2026-10-01 this is the gate ladder of
## docs/core_loop_plan_2026_10_01.md: every gate has a class from the depth of
## the system it leads to (rules in scripts/domain/GateClass.gd). Going back,
## or sideways, is always open; going deeper checks the class every time, even
## into a system visited before. Class II (depth 3-4) is the tutorial rung: it
## needs Shields Mk II, because the deeper gates' transit field strips
## unhardened shields, and N.O.V.A. (who hates the gates anyway) will not go
## through without them. Higher classes need a Ship Rating.
##
## N.O.V.A. then walks them through it, one step at a time:
##   1. At the blocked gate she explains, and hands over a first survey drone
##      as an advance (once per campaign).
##   2. The first time a red rock (tech-grade seams) is targeted, she says
##      that is the one, and how to work it.
##   3. With the rad-quartz aboard, she sends them to the mechanic.
##   4. With the shields fitted, she grumbles and opens the gates.
## Hand-written lines; no model.

const GateClassType := preload("res://scripts/domain/GateClass.gd")
const UpgradeGoalType := preload("res://scripts/domain/UpgradeGoal.gd")
const UpgradeGoalCardType := preload("res://scripts/ui/UpgradeGoalCard.gd")
const KeystoneType := preload("res://scripts/domain/Keystone.gd")
## Seconds after the refusal before she names the rest of the bill.
const COST_LINE_DELAY_S := 22.0
const REQUIRED_SYSTEM := "shields"
const REQUIRED_TIER := 2
const MATERIAL := "rad_quartz"
const DRONE_ITEM := "survey_drone"

const BLOCK_REASON := "The transit field on this gate needs hardened shields (Shields Mk II)."
## Rating refusals start with this, so the jump code can tell them apart.
const RATING_BLOCK_PREFIX := "Class "

## Depth of a system id from the start (-1 unknown). Swappable for tests;
## defaults to the gate graph (PremiseWorldSnapshot._system_depth).
var depth_of: Callable = func(system_id: String) -> int:
	return preload("res://scripts/story/premise/PremiseWorldSnapshot.gd")._system_depth(system_id)
## This campaign's keystone card (Keystone.gd, drawn from the campaign seed).
## Swappable for tests.
var keystone_of: Callable = func() -> Dictionary:
	var loop := Engine.get_main_loop()
	var gs: Node = (loop as SceneTree).root.get_node_or_null("GlobalState") if loop is SceneTree else null
	return KeystoneType.draw(int(gs.campaign_seed)) if gs != null else {}
## The system the ship is in. Swappable for tests.
var current_system_of: Callable = func() -> String:
	var loop := Engine.get_main_loop()
	var gs: Node = (loop as SceneTree).root.get_node_or_null("GlobalState") if loop is SceneTree else null
	return str(gs.current_system_id) if gs != null else ""

const LINES := {
	"blocked": [
		"Captain, stop. This gate runs deeper than any we've used. Its transit field strips unhardened shields, and I'm not taking us through without Shields Mk II.",
		"Hardened shields need rad-quartz. Nobody sells it; you mine it. It grows in the cracks of the red rocks in the asteroid fields.",
		"A mining laser shatters those rocks, so it's a job for a survey drone. I've put one in the bay. Call it an advance.",
	],
	"red_rock": ["That red one. Tech-grade seams in the cracks. Get close, press G, and fly the drone in slowly. The ore is fragile."],
	"have_material": ["That's everything the mechanic needs: credits, ore and the rad-quartz. Dock and have them fit Shields Mk II, then we can talk about that gate."],
	# A little after the refusal: the rest of the bill (core loop step 5).
	# Built from what's actually short; see _cost_line().
	"costs_intro": ["The rad-quartz isn't the whole bill. The mechanic will want %s as well."],
	"costs_tail_ore": ["Any rock gives ore; bank it when we dock and it counts towards the upgrade."],
	"costs_tail_credits": ["The station boards pay credits, and so does ore you don't need."],
	"costs_card": ["I've pinned the whole list top right, so you don't have to remember it."],
	"rated": ["Shields hardened. Fine. The deeper gates will take us now. I still hate them."],
	"reminder": ["We still need Shields Mk II for that gate. Still short: %s. It's all on the card, top right."],
	# First refusal at each higher class: N.O.V.A. says what this class asks.
	# %s = class numeral, %d = rating needed, %d = ours.
	"class_3": ["Class %s gate. Older ring, rougher fold: a stock frame shakes apart in there. I want a Ship Rating of %d before I take it. We're at %d."],
	"class_4": ["Class %s. Deep gate. These ones don't forgive anything. Ship Rating %d, Captain; we're at %d."],
	"class_5": ["Class %s. Half the ring is dead and the other half is angry. Rating %d or we stay. We're at %d."],
	"class_6": ["Class %s. The edge of anything anyone charted. Rating %d. We're at %d. I'm not arguing about this one."],
	# The rating is fine but the keystone isn't (the keystone line follows).
	"class_rating_ok": ["Class %s. Deep gate. Our rating's good enough; that's not the problem."],
	"class_deep": ["Class %s. Further than the charts go. Rating %d; we're at %d. Every gate out here asks for more."],
	# Appended when one system is holding the rating back. %s = system name.
	"breadth": ["And upgrading the same thing again won't do it. Our %s is the weak spot; everything else counts only so far above it."],
}

var _visited: Array = []
var _stage := ""  # "", "need_material", "need_fit", "done"
var _drone_given := false
var _red_rock_told := false
var _material_told := false
var _last_reminder_ms := -100000000
var _poll := 0.0
## Gate classes N.O.V.A. has already explained (first refusal at each).
var _classes_told: Array = []
## The last refusal's details (GateClass.check), for on_refused().
var _last_check: Dictionary = {}
## Keystone lines already said: "rumour", "reveal", "refusal", "met".
var _keystone_told: Array = []


func to_dict() -> Dictionary:
	return {"visited": _visited.duplicate(), "stage": _stage, "drone_given": _drone_given, "red_rock_told": _red_rock_told, "material_told": _material_told, "classes_told": _classes_told.duplicate(), "keystone_told": _keystone_told.duplicate()}


func load_from_dict(data: Dictionary) -> void:
	_visited = (data.get("visited", []) as Array).duplicate() if data.get("visited", []) is Array else []
	_stage = str(data.get("stage", ""))
	_drone_given = bool(data.get("drone_given", false))
	_red_rock_told = bool(data.get("red_rock_told", false))
	_material_told = bool(data.get("material_told", false))
	_classes_told = (data.get("classes_told", []) as Array).duplicate() if data.get("classes_told", []) is Array else []
	_keystone_told = (data.get("keystone_told", []) as Array).duplicate() if data.get("keystone_told", []) is Array else []


## The ship's current tiers (GateClass shape).
func _tiers() -> Dictionary:
	var gs := get_node_or_null("/root/GlobalState")
	return GateClassType.tiers_of(gs.current_upgrades if gs != null else {})


func ship_rating() -> int:
	return GateClassType.ship_rating(_tiers())


## The class of a gate leading to `destination_system_id`.
func gate_class_to(destination_system_id: String) -> int:
	return GateClassType.class_for_depth(int(depth_of.call(destination_system_id)))


func reset_for_new_campaign() -> void:
	load_from_dict({})


func stage() -> String:
	return _stage


## The ship arrived in (or started in) a system.
func note_system(system_id: String) -> void:
	if not system_id.is_empty() and not _visited.has(system_id):
		_visited.append(system_id)
		_keystone_hint(int(depth_of.call(system_id)))


## The keystone never arrives as a surprise wall (plan 2.3): a rumour on first
## reaching depth 4-5, the reveal at depth 6, each once. Skipped when the ship
## already has it.
func _keystone_hint(depth: int) -> void:
	var card: Dictionary = keystone_of.call()
	if card.is_empty() or KeystoneType.is_met(card, _tiers()):
		return
	var key := ""
	if depth >= KeystoneType.REVEAL_DEPTH:
		key = "reveal"
	elif depth in KeystoneType.RUMOUR_DEPTHS:
		key = "rumour"
	if key.is_empty() or _keystone_told.has(key):
		return
	_keystone_told.append(key)
	if key == "reveal" and not _keystone_told.has("rumour"):
		_keystone_told.append("rumour")
	_say(str(card[key]))
	load("res://scripts/ui/Wiki.gd").unlock("keystone")


## The keystone the captain has heard of ({} before the first hint).
func known_keystone() -> Dictionary:
	return keystone_of.call() if not _keystone_told.is_empty() else {}


func is_rated() -> bool:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null:
		return true
	var info: Dictionary = gs.current_upgrades.get(REQUIRED_SYSTEM, {})
	return int(info.get("tier", 1)) >= REQUIRED_TIER


## Everything the UI shows about a gate to `destination_system_id`, from the
## same check the jump uses: GateClass.check's fields plus "back" (it leads
## shallower or level, so it is always open), "limiting" (the weakest system
## when it holds the rating back) and "label" (a short line for the target
## panel and the star map). No side effects.
func access_to(destination_system_id: String) -> Dictionary:
	var dest_depth := int(depth_of.call(destination_system_id))
	var from_depth := int(depth_of.call(str(current_system_of.call())))
	if dest_depth < 0:
		# Not on the graph yet: treat it as one step further out.
		dest_depth = maxi(from_depth, 0) + 1
	var tiers := _tiers()
	var card: Dictionary = keystone_of.call()
	var result: Dictionary = GateClassType.check(from_depth, dest_depth, tiers, card)
	result["back"] = from_depth >= 0 and dest_depth <= from_depth
	result["limiting"] = GateClassType.limiting_system(tiers)
	result["keystone"] = card
	var numeral := GateClassType.class_name_of(int(result["class"]))
	var rating_short := int(result["rating"]) < int(result["needs_rating"])
	if bool(result["back"]):
		result["label"] = "Class %s · back the way we came, open" % numeral
	elif bool(result["ok"]):
		result["label"] = "Class %s · open (Ship Rating %d)" % [numeral, int(result["rating"])]
	elif bool(result["needs_shields_mk2"]):
		result["label"] = "Class %s · needs Shields Mk II" % numeral
	elif bool(result["needs_keystone"]) and rating_short:
		result["label"] = "Class %s · needs Ship Rating %d (ours %d) + %s" % [numeral, int(result["needs_rating"]), int(result["rating"]), KeystoneType.requirement(card)]
	elif bool(result["needs_keystone"]):
		result["label"] = "Class %s · needs %s (%s)" % [numeral, KeystoneType.requirement(card), str(card["name"]).to_lower()]
	else:
		result["label"] = "Class %s · needs Ship Rating %d (ours %d)" % [numeral, int(result["needs_rating"]), int(result["rating"])]
	return result


## The ship's rating and the first gate class it can't open yet:
## {"rating", "next_class", "next_needs"}, for the HUD line.
func next_rung() -> Dictionary:
	var tiers := _tiers()
	var rating := GateClassType.ship_rating(tiers)
	var card: Dictionary = keystone_of.call()
	var keystone_short := not KeystoneType.is_met(card, tiers)
	var c := 2
	while c < 200:
		var blocked_by_shields := c == 2 and int(tiers.get("shields", 1)) < 2
		var blocked_by_keystone := KeystoneType.applies(c) and keystone_short
		if blocked_by_shields or blocked_by_keystone or rating < GateClassType.rating_for_class(c):
			break
		c += 1
	return {"rating": rating, "next_class": c, "next_needs": GateClassType.rating_for_class(c),
		"needs_shields_mk2": c == 2 and int(tiers.get("shields", 1)) < 2,
		"needs_keystone": KeystoneType.applies(c) and keystone_short, "keystone": card}


## "" when the ship may jump to `destination_system_id`, else why not. No
## side effects beyond remembering the details: the UI asks this every frame.
func block_reason(destination_system_id: String) -> String:
	var result := access_to(destination_system_id)
	if bool(result["ok"]):
		return ""
	_last_check = result
	if bool(result["needs_shields_mk2"]):
		return BLOCK_REASON
	var numeral := GateClassType.class_name_of(int(result["class"]))
	var rating_short := int(result["rating"]) < int(result["needs_rating"])
	var reason := ""
	if rating_short:
		reason = "Class %s gate: needs Ship Rating %d (ours is %d)." % [numeral, int(result["needs_rating"]), int(result["rating"])]
	if bool(result["needs_keystone"]):
		var card: Dictionary = result["keystone"]
		var keystone_line := "%s %s needed." % [str(card["reason"]), KeystoneType.requirement(card)]
		reason = (reason + " " + keystone_line) if rating_short else "Class %s gate: %s" % [numeral, keystone_line]
	if rating_short and not str(result["limiting"]).is_empty():
		reason += " %s is the weakest system; others count only two tiers above it." % str(result["limiting"]).capitalize()
	return reason


## True when `reason` is one of this guide's refusals.
func is_rating_block(reason: String) -> bool:
	return reason == BLOCK_REASON or reason.begins_with(RATING_BLOCK_PREFIX)


## The captain actually tried the gate and was refused: the first time starts
## N.O.V.A.'s walkthrough; later tries get a reminder now and then.
func on_refused() -> void:
	# A higher class with shields already hardened: explain that class once.
	if not _last_check.is_empty() and not bool(_last_check.get("needs_shields_mk2", false)):
		_explain_class(_last_check)
		return
	if _stage.is_empty():
		_start_walkthrough()
	elif _stage != "done":
		var now := Time.get_ticks_msec()
		if now - _last_reminder_ms > 60000:
			_last_reminder_ms = now
			var short := _short_list(true)
			_say(str(LINES["reminder"][0]) % (short if not short.is_empty() else "nothing; dock and fit it"))


func _explain_class(result: Dictionary) -> void:
	var gate_class := int(result.get("class", 3))
	var numeral := GateClassType.class_name_of(gate_class)
	var rating_short := int(result.get("rating", 0)) < int(result.get("needs_rating", 0))
	var parts: Array[String] = []
	if not _classes_told.has(gate_class):
		_classes_told.append(gate_class)
		if rating_short:
			var key := "class_%d" % gate_class if LINES.has("class_%d" % gate_class) else "class_deep"
			var line: String = str(LINES[key][0]) % [numeral, int(result.get("needs_rating", 0)), int(result.get("rating", 0))]
			var limiting := str(result.get("limiting", ""))
			if not limiting.is_empty():
				line += " " + str(LINES["breadth"][0]) % limiting
			parts.append(line)
		else:
			parts.append(str(LINES["class_rating_ok"][0]) % numeral)
	# The keystone, once: what this campaign's deep space wants, and it becomes
	# the goal on the HUD card.
	var card: Dictionary = result.get("keystone", {})
	if bool(result.get("needs_keystone", false)) and not card.is_empty() and not _keystone_told.has("refusal"):
		if parts.is_empty():
			parts.append("Class %s gate." % numeral)
		parts.append(str(card["refusal"]))
		for key in ["rumour", "refusal"]:
			if not _keystone_told.has(key):
				_keystone_told.append(key)
		load("res://scripts/ui/Wiki.gd").unlock("keystone")
		var gs := get_node_or_null("/root/GlobalState")
		if gs != null:
			var goal := UpgradeGoalType.next_tier_goal(gs, str(card["sys"]), false)
			if not goal.is_empty():
				UpgradeGoalCardType.set_goal(str(goal["sys"]), str(goal["path"]), int(goal["tier"]))
	if not parts.is_empty():
		_say(" ".join(parts))


## Once the keystone the captain was told about is fitted, she says so.
func _keystone_met_check() -> void:
	if _keystone_told.is_empty() or _keystone_told.has("met"):
		return
	var card: Dictionary = keystone_of.call()
	if card.is_empty() or not KeystoneType.is_met(card, _tiers()):
		return
	_keystone_told.append("met")
	_say(KeystoneType.MET_LINE % str(card["sys"]).capitalize())


## The Shields Mk II goal the walkthrough works towards.
func _shields_goal() -> Dictionary:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null:
		return {}
	return UpgradeGoalType.next_tier_goal(gs, REQUIRED_SYSTEM, false) if is_rated() == false else {}


## What the shields goal is still short of, as words: "200 credits and 100 ore".
func _short_list(include_material: bool = true) -> String:
	var gs := get_node_or_null("/root/GlobalState")
	var goal := _shields_goal()
	if gs == null or goal.is_empty():
		return ""
	var parts: Array[String] = []
	for row in UpgradeGoalType.rows(gs, goal):
		var missing := int(row["need"]) - int(row["have"])
		if missing <= 0 or str(row["id"]) == "power":
			continue
		if str(row["id"]) == "credits":
			parts.append("%d credits" % missing)
		elif str(row["id"]) == "ore":
			parts.append("%d ore" % missing)
		elif include_material:
			parts.append("%d %s" % [missing, str(row["label"]).to_lower()])
	if parts.size() > 1:
		return ", ".join(parts.slice(0, parts.size() - 1)) + " and " + parts[-1]
	return parts[0] if not parts.is_empty() else ""


## The rest of the bill, said once a little after the refusal.
func _cost_line() -> String:
	var short := _short_list(false)
	if short.is_empty():
		return ""
	var line := str(LINES["costs_intro"][0]) % short
	if short.contains("ore"):
		line += " " + str(LINES["costs_tail_ore"][0])
	if short.contains("credits"):
		line += " " + str(LINES["costs_tail_credits"][0])
	return line + " " + str(LINES["costs_card"][0])


func _start_walkthrough() -> void:
	_stage = "need_material"
	_last_reminder_ms = Time.get_ticks_msec()
	var lines: Array = LINES["blocked"]
	_say(" ".join(lines))
	# Shields Mk II becomes the goal on the HUD card, and a little later she
	# names the rest of the bill (core loop step 5).
	var goal := _shields_goal()
	if not goal.is_empty():
		UpgradeGoalCardType.set_goal(str(goal["sys"]), str(goal["path"]), int(goal["tier"]))
	if is_inside_tree():
		get_tree().create_timer(COST_LINE_DELAY_S).timeout.connect(func() -> void:
			if _stage != "done":
				var cost := _cost_line()
				if not cost.is_empty():
					_say(cost))
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
	_keystone_met_check()


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
		load("res://scripts/ui/Wiki.gd").unlock("upgrades")
		return
	var goal := _shields_goal()
	var ready := not goal.is_empty() and UpgradeGoalType.is_ready(gs, goal)
	if _stage == "need_fit" and not ready:
		_stage = "need_material"  # spent something on the way: back to gathering
	if _stage == "need_material":
		# "Dock and fit it" only when the whole bill is covered, not just the
		# rad-quartz (core loop step 5).
		if ready:
			_stage = "need_fit"
			_say(LINES["have_material"][0])
			return
		var needed: int = int(gs.upgrade_material_cost(REQUIRED_SYSTEM, REQUIRED_TIER).get(MATERIAL, 1))
		if not _material_told and gs.inventory != null and gs.inventory.get_quantity(MATERIAL) >= needed:
			_material_told = true
			var short := _short_list(false)
			_say("Rad-quartz aboard. That's the hard part done. Still short: %s." % short if not short.is_empty() else "Rad-quartz aboard.")
			return
		var target = gs.active_target
		if not _red_rock_told and is_instance_valid(target) and (target as Node).is_in_group("tech_seam_asteroid"):
			_red_rock_told = true
			_say(LINES["red_rock"][0])


func _say(text: String) -> void:
	var nova := get_node_or_null("/root/Nova")
	if nova != null and nova.has_method("ask_captain"):
		nova.ask_captain(text, "nav")
