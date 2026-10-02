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


## The class of the system the ship is in.
func _current_class() -> int:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null:
		return 1
	return GateClassType.class_for_depth(int(depth_of.call(str(gs.current_system_id))))


## The index of the bearing findable here and now, or -1.
func pending_bearing() -> int:
	var s := current()
	if s.is_empty() or not bool(s.get("known", false)):
		return -1
	var found := LodestarType.bearings_found(s)
	if found >= LodestarType.BEARINGS:
		return -1
	return found if _current_class() >= LodestarType.bearing_class(found) else -1


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
		nova.ask_captain("%s %s" % [str(card["nova_first"]), MAP_LINE], "nav")
	load("res://scripts/ui/Wiki.gd").unlock("lodestar")
	return true
