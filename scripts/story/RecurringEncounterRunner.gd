extends Node

## Makes recurring-cast encounters happen in flight (RecurringEncounters).
## Each arrival in a system asks the premise director whether someone from an
## earlier story shows up; if so, after a little calm flight they hail in
## their own voice. A bitter one then comes at the captain in a ship named for
## them (destroy it and the feud ends); a warm one hands over a gift.

const VoiceType := preload("res://scripts/story/premise/VoiceDNA.gd")

## Seconds of calm flight in the system before they appear.
const DELAY_MIN_S := 25.0
const DELAY_MAX_S := 55.0
const SPAWN_DISTANCE := 650.0
const HOSTILE_FACTION := "reavers"

var director: Node = null
var _system_id := ""
var _pending: Dictionary = {}
var _wait := 0.0


func _process(delta: float) -> void:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null or director == null or not is_instance_valid(director):
		return
	var system_id := str(gs.current_system_id)
	if system_id != _system_id:
		var first := _system_id.is_empty()
		_system_id = system_id
		_pending = {}
		# The system the campaign loads into is not an arrival.
		if not first:
			_pending = director.on_arrival_encounter(system_id)
			_wait = randf_range(DELAY_MIN_S, DELAY_MAX_S)
	if _pending.is_empty() or not _can_happen(gs):
		return
	_wait -= delta
	if _wait <= 0.0:
		var encounter := _pending
		_pending = {}
		play(encounter)


func _can_happen(gs: Node) -> bool:
	var player = gs.player
	if not is_instance_valid(player) or player.get("is_docked") == true or player.get("destroyed") == true:
		return false
	if bool(gs.get("intro_cinematic_active")):
		return false
	var combat := get_node_or_null("/root/CombatManager")
	return combat == null or int(combat.get("state")) == 0


## The hail, then the ship (bitter) or the gift (warm). Public for tests.
func play(encounter: Dictionary) -> Node:
	var gs := get_node_or_null("/root/GlobalState")
	var name_text := str(encounter.get("display_name", "Someone"))
	var line := str(encounter.get("line", ""))
	if gs != null:
		gs.emit_chatter(name_text.to_upper(), line, Color(1.0, 0.75, 0.45))
	var speech := get_node_or_null("/root/SpeechService")
	if speech != null and speech.has_method("play_on_comms"):
		speech.play_on_comms(line, VoiceType.register(VoiceType.for_person(str(encounter.get("person_id", "")))), name_text)
	if str(encounter.get("attitude", "")) == "warm":
		_give(encounter.get("gift", {}), name_text)
		return null
	return _spawn_enemy(encounter)


func _give(gift: Dictionary, from_name: String) -> void:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null:
		return
	if gift.has("item") and gs.inventory != null and gs.inventory.add(str(gift["item"]), 1, 3):
		gs.emit_chatter("DRONE BAY", "%s sent over a survey drone." % from_name, Color(1.0, 0.85, 0.3))
	elif int(gift.get("credits", 0)) > 0:
		gs.add_credits(int(gift["credits"]))
		gs.emit_chatter("TRANSFER", "%s sent %d credits." % [from_name, int(gift["credits"])], Color(1.0, 0.85, 0.3))


## A ship with their name, coming in from ahead of the captain. When it is
## destroyed by the captain, the feud is over.
func _spawn_enemy(encounter: Dictionary) -> Node:
	var gs := get_node_or_null("/root/GlobalState")
	if gs == null or DisplayServer.get_name() == "headless":
		return null
	var root_node = gs.active_system_root
	var player = gs.player
	if root_node == null or not is_instance_valid(root_node) or not is_instance_valid(player):
		return null
	var scene: PackedScene = load("res://scenes/npc_ship.tscn")
	if scene == null:
		return null
	var npc = scene.instantiate()
	npc.faction = HOSTILE_FACTION
	npc.speed = 14.0
	npc.ship_role = "Raider"
	npc.name = str(encounter.get("display_name", "Old enemy"))
	npc.set_meta("recurring_person_id", str(encounter.get("person_id", "")))
	root_node.add_child(npc)
	var ahead := -(player as Node3D).global_transform.basis.z.normalized()
	npc.global_position = (player as Node3D).global_position + ahead * SPAWN_DISTANCE
	var person_id := str(encounter.get("person_id", ""))
	var display := str(encounter.get("display_name", ""))
	var system_id := str(gs.current_system_id)
	npc.tree_exiting.connect(func() -> void:
		if bool(npc.get("destroyed")) and str(npc.get("last_attacker_faction")) == "player":
			feud_over(person_id, display, system_id))
	return npc


## The captain destroyed them: the feud is over for good.
func feud_over(person_id: String, display_name: String, system_id: String) -> void:
	if director != null and is_instance_valid(director):
		director.end_feud(person_id, display_name, system_id)
	var nova := get_node_or_null("/root/Nova")
	if nova != null and nova.has_method("ask_captain"):
		nova.ask_captain("That's the end of %s, then. I'd rather it hadn't come to that." % display_name, "loss")
