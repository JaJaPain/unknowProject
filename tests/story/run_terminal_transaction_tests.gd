extends SceneTree

## Drives the REAL QuestManager terminal paths, not a fake reducer: accept a
## mission, settle it, and prove a failed checkpoint leaves a coherent
## mission/world pair with the mission still retryable.

const Store := preload("res://scripts/persistence/StoryStateStore.gd")
const Director := preload("res://scripts/story/LocalPressureDirector.gd")

class World extends Node3D:
	var active_campaign_slot_id := "campaign.test"
	var checkpoint_ok := true
	var reasons: Array = []
	func request_safe_checkpoint(reason: String, _station: Node) -> bool:
		reasons.append(reason)
		return checkpoint_ok

class Pilot extends CharacterBody3D:
	var is_docked := true
	var destroyed := false
	func navigation_obstacle_snapshot() -> Array: return []

class Station extends Node3D:
	func get_world_id() -> String: return "station.local"

var failures: Array[String] = []
var scene: World
var station: Station
var ui: Control
var manager: Node
var quests: Node
var gs: Node

func _initialize():
	call_deferred("_run")

func _run():
	_install()
	_test_successful_settlement()
	_test_failed_checkpoint_rollback()
	_test_duplicate_terminal()
	_test_in_flight_pending()
	_teardown()
	if failures.is_empty():
		print("[PASS] Terminal transaction: settlement checkpoint, rollback, retry, duplicate guard, in-flight pending")
	else:
		for message in failures: push_error("[FAIL] " + message)
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _install() -> void:
	gs = root.get_node("GlobalState")
	manager = root.get_node("StoryManager")
	quests = root.get_node("QuestManager")
	scene = World.new()
	scene.name = "GameRoot"
	root.add_child(scene)
	current_scene = scene
	station = Station.new()
	scene.add_child(station)
	var canvas := CanvasLayer.new()
	canvas.name = "CanvasLayer"
	scene.add_child(canvas)
	var script := GDScript.new()
	script.source_code = 'extends "res://scripts/UIManager.gd"\nfunc _ready(): pass\nfunc _process(_delta): pass\nfunc _show_agent_portrait(_visible): pass\n'
	_expect(script.reload() == OK, "Settlement UI probe did not compile.")
	ui = script.new()
	ui.name = "UIManager"
	ui.current_station = station
	canvas.add_child(ui)
	var pilot := Pilot.new()
	scene.add_child(pilot)
	gs.player = pilot
	gs.current_system_id = "system.local"
	manager.story_state = Store._default_state()
	manager._story_state_store = Store.open("res://.tmp_godot_user/settlement_%d" % Time.get_ticks_usec())

func _teardown() -> void:
	current_scene = null
	if is_instance_valid(scene): scene.queue_free()

## One accepted KILL_SHIPS contract, forced to its completion condition.
## Built in the real offer shape so actual mission validation runs.
func _accept(title: String) -> String:
	var offer := {
		"title": title, "faction": "vanguard", "agent_name": "Captain Dask",
		"dialogue": "Clear them out.",
		"objective": {"type": "KILL_SHIPS", "target_faction": "reavers",
			"count_required": 1, "reward_credits": 400},
		"choices": [],
	}
	var choice := {"text": "Accepted.", "consequence": {"credits_immediate": 0,
		"reputation_change": {}, "combat_multiplier": 1.0, "reward_credits_multiplier": 1.0,
		"dialogue_response": "Proceed."}}
	if not quests.accept_quest(offer, choice):
		_expect(false, "Fixture mission was rejected: %s" % quests.last_validation_error)
		return ""
	var runtime_id := str(quests.active_quest["runtime_id"])
	quests.active_quest["current_count"] = int(quests.active_quest.get("count_required", 1))
	return runtime_id

func _test_successful_settlement() -> void:
	scene.checkpoint_ok = true
	scene.reasons.clear()
	var credits_before := int(gs.player_credits)
	var runtime_id := _accept("Settle OK")
	if runtime_id.is_empty(): return
	_expect(quests.is_quest_completed(), "Fixture mission did not reach its completion condition.")
	quests.complete_quest()
	_expect("mission_settled" in scene.reasons, "Settlement did not use its own checkpoint reason: %s" % str(scene.reasons))
	_expect(not quests.is_quest_active(), "A committed completion left the mission active.")
	_expect(int(gs.player_credits) > credits_before, "A committed completion paid nothing.")
	_expect(not manager.has_pending_consequence_save(), "A docked settlement left its save pending.")

func _test_failed_checkpoint_rollback() -> void:
	scene.checkpoint_ok = false
	scene.reasons.clear()
	var runtime_id := _accept("Rollback")
	if runtime_id.is_empty(): return
	var credits_before := int(gs.player_credits)
	var pressures_before := JSON.stringify(manager.story_state.get("local_pressures", {}))
	var inventory_before := JSON.stringify(gs.inventory.to_dict())
	quests.complete_quest()
	_expect(int(gs.player_credits) == credits_before, "A failed settlement still paid the player.")
	_expect(JSON.stringify(manager.story_state.get("local_pressures", {})) == pressures_before,
		"A failed settlement committed a pressure change.")
	_expect(JSON.stringify(gs.inventory.to_dict()) == inventory_before,
		"A failed settlement consumed inventory.")
	_expect(quests.is_quest_active(), "A failed settlement discarded the mission instead of leaving it retryable.")
	_expect(str(quests.active_quest.get("runtime_id", "")) == runtime_id, "Rollback restored the wrong mission.")
	# Retrying at a working checkpoint must commit exactly once.
	scene.checkpoint_ok = true
	quests.complete_quest()
	_expect(not quests.is_quest_active(), "A retry after a failed settlement did not complete the mission.")
	_expect(int(gs.player_credits) > credits_before, "A retry did not pay the player.")

func _test_duplicate_terminal() -> void:
	# The applied ledger is what stops a second payout for one runtime mission.
	var pressures: Dictionary = manager.story_state.get("local_pressures", {})
	var applied: Array = pressures.get("applied_outcome_ids", []) if pressures is Dictionary else []
	var seen: Dictionary = {}
	for raw in applied:
		var mission_id := str(raw).split(":")[0]
		_expect(not seen.has(mission_id), "Two terminal records were retained for one runtime mission.")
		seen[mission_id] = true

func _test_in_flight_pending() -> void:
	# Undocked: the change applies once in the running state and stays pending.
	scene.checkpoint_ok = true
	scene.reasons.clear()
	gs.player.is_docked = false
	var runtime_id := _accept("In flight")
	if runtime_id.is_empty(): return
	quests.abandon_quest()
	_expect(not quests.is_quest_active(), "An in-flight abandon did not terminate the mission.")
	_expect(scene.reasons.is_empty(), "An in-flight terminal pretended it was docked and checkpointed.")
	_expect(manager.has_pending_consequence_save(), "An in-flight terminal did not report its save as pending.")
	gs.player.is_docked = true
