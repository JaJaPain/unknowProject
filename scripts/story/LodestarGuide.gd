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

## Swappable for tests.
var depth_of: Callable = func(system_id: String) -> int:
	return preload("res://scripts/story/premise/PremiseWorldSnapshot.gd")._system_depth(system_id)

var _poll := 0.0


func _process(delta: float) -> void:
	_poll += delta
	if _poll < POLL_S:
		return
	_poll = 0.0
	try_introduce()


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
