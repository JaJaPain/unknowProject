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
	_test_delivery_rollback()
	_test_item_delivery_rollback()
	_test_duplicate_terminal()
	_test_abandoned_courier_cleanup()
	_test_reentrant_terminal_signal()
	_test_nonfocused_expiry_focus_restore()
	_test_compatibility_is_not_durable()
	_test_staged_callback_applies_once()
	_test_in_flight_pending()
	_test_checkpoint_beats_newer_loose_cache()
	_teardown()
	if failures.is_empty():
		print("[PASS] Terminal transaction: settlement checkpoint, rollback, retry, duplicate guard, courier cleanup, reentrancy, nonfocused expiry, compatibility handling, staged callbacks, in-flight pending")
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

## Reopening an older checkpoint restores its mission and its prior effects
## together; a newer loose story cache must not survive on top of it, and a
## pending in-flight write from the abandoned timeline must not commit later.
func _test_checkpoint_beats_newer_loose_cache() -> void:
	var checkpoint: Dictionary = manager.capture_story_state_for_checkpoint()
	var older_step := int(checkpoint.get("local_outcome_step", 0))
	# The loose cache moves on, and an in-flight terminal leaves a save pending.
	manager.story_state["local_outcome_step"] = older_step + 7
	manager.story_state["pending_hooks"] = ["Loose cache hook."]
	manager.mark_consequence_save_pending()
	_expect(manager.restore_story_state_from_checkpoint(checkpoint),
		"A valid checkpoint story state was rejected on restore.")
	_expect(int(manager.story_state.get("local_outcome_step", -1)) == older_step,
		"A newer loose story cache overrode the restored checkpoint.")
	_expect(not manager.has_pending_consequence_save(),
		"A restored checkpoint kept a pending write from the timeline it replaced.")


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

func _test_delivery_rollback() -> void:
	var offer := {"title": "Ore rollback", "faction": "vanguard", "agent_name": "Local buyer", "dialogue": "Deliver ore.", "objective": {"type": "DELIVER_ORE", "amount_required": 10.0, "reward_credits": 100}, "choices": []}
	var choice := {"text": "Accept", "consequence": {"credits_immediate": 0, "reputation_change": {}, "reward_credits_multiplier": 1.0}}
	_expect(quests.accept_quest(offer, choice), "Ore fixture rejected.")
	gs.cargo = 10.0
	gs.cargo_type = gs.CargoType.ORE
	scene.checkpoint_ok = false
	var credits_before: int = gs.player_credits
	quests.complete_quest()
	_expect(gs.cargo == 10.0 and quests.is_quest_completed(), "Failed ore settlement lost cargo or retry readiness.")
	_expect(gs.player_credits == credits_before, "Failed ore settlement paid credits.")
	scene.checkpoint_ok = true
	quests.complete_quest()
	_expect(gs.cargo == 0.0 and not quests.is_quest_active(), "Ore retry did not consume exactly once.")
	var paid: int = gs.player_credits
	quests.complete_quest()
	_expect(gs.player_credits == paid, "Repeated ore settlement paid twice.")

func _test_item_delivery_rollback() -> void:
	for objective_type in ["PURCHASE_DELIVERY", "DELIVERY_COURIER"]:
		var objective := {"type": objective_type, "item_name": "Review packet", "item_id": "item.review_packet", "quantity_required": 1, "store_station_id": "station.local", "origin_station_id": "station.local", "destination_station_id": "station.local", "destination_display": "Local Station", "reward_credits": 100}
		var offer := {"title": "Item rollback", "faction": "vanguard", "agent_name": "Local buyer", "dialogue": "Deliver the packet.", "objective": objective, "choices": []}
		var choice := {"text": "Accept", "consequence": {"credits_immediate": 0, "reputation_change": {}, "reward_credits_multiplier": 1.0}}
		if not quests.accept_quest(offer, choice):
			_expect(false, "Item fixture rejected: " + quests.last_validation_error)
			continue
		if objective_type == "PURCHASE_DELIVERY":
			gs.inventory.add("item.review_packet", 1)
		else:
			gs.cargo_special = {"name": "Review packet"}
			gs.cargo_type = gs.CargoType.SPECIAL
			quests.active_quest["cargo_loaded"] = true
		var before_inventory := JSON.stringify(gs.inventory.to_dict())
		var before_cargo := JSON.stringify(gs.cargo_special)
		scene.checkpoint_ok = false
		quests.complete_quest()
		_expect(JSON.stringify(gs.inventory.to_dict()) == before_inventory and JSON.stringify(gs.cargo_special) == before_cargo, "Failed item delivery lost its item: " + objective_type)
		_expect(quests.is_quest_completed(), "Failed item delivery cannot retry: " + objective_type)
		scene.checkpoint_ok = true
		quests.complete_quest()
		_expect(not quests.is_quest_active(), "Item delivery retry failed: " + objective_type)

func _test_duplicate_terminal() -> void:
	# The applied ledger is what stops a second payout for one runtime mission.
	var pressures: Dictionary = manager.story_state.get("local_pressures", {})
	var applied: Array = pressures.get("applied_outcome_ids", []) if pressures is Dictionary else []
	var seen: Dictionary = {}
	for raw in applied:
		var mission_id := str(raw).split(":")[0]
		_expect(not seen.has(mission_id), "Two terminal records were retained for one runtime mission.")
		seen[mission_id] = true

## Abandoning a courier must release the crate it is carrying, and a failed
## settlement must give that crate back rather than stranding the mission.
func _test_abandoned_courier_cleanup() -> void:
	var objective := {"type": "DELIVERY_COURIER", "item_name": "Sealed crate",
		"item_id": "item.sealed_crate", "quantity_required": 1,
		"origin_station_id": "station.local", "destination_station_id": "station.local",
		"destination_display": "Local Station", "reward_credits": 100}
	var offer := {"title": "Courier abandon", "faction": "vanguard", "agent_name": "Local buyer",
		"dialogue": "Carry this.", "objective": objective, "choices": []}
	var choice := {"text": "Accept", "consequence": {"credits_immediate": 0,
		"reputation_change": {}, "reward_credits_multiplier": 1.0}}
	if not quests.accept_quest(offer, choice):
		_expect(false, "Courier abandon fixture rejected: " + quests.last_validation_error)
		return
	gs.cargo_special = {"name": "Sealed crate"}
	gs.cargo_type = gs.CargoType.SPECIAL
	quests.active_quest["cargo_loaded"] = true
	scene.checkpoint_ok = false
	quests.abandon_quest()
	_expect(str(gs.cargo_special.get("name", "")) == "Sealed crate",
		"A failed courier abandon stranded the crate instead of restoring it.")
	_expect(quests.is_quest_active(), "A failed courier abandon discarded the mission.")
	scene.checkpoint_ok = true
	quests.abandon_quest()
	_expect(not quests.is_quest_active(), "Courier abandon retry did not terminate the mission.")
	_expect(gs.cargo_special.is_empty(),
		"Abandoning a courier left its crate in the hold.")


## A cargo/reputation handler firing synchronously inside settlement must not be
## able to start a second terminal transaction.
func _test_reentrant_terminal_signal() -> void:
	scene.checkpoint_ok = true
	var runtime_id := _accept("Reentrant")
	if runtime_id.is_empty(): return
	var reentered := {"count": 0}
	var probe := func(_amount: float) -> void:
		if quests.is_terminal_transaction_in_progress():
			reentered["count"] += 1
			quests.complete_quest()
			quests.abandon_quest()
	gs.cargo_changed.connect(probe)
	var credits_before := int(gs.player_credits)
	quests.complete_quest()
	gs.cargo_changed.disconnect(probe)
	_expect(not quests.is_quest_active(), "The reentrancy fixture did not settle.")
	var paid := int(gs.player_credits) - credits_before
	quests.complete_quest()
	_expect(int(gs.player_credits) - credits_before == paid,
		"A reentrant terminal call paid a second time.")


## A nonfocused mission expiring on a failed checkpoint must put the original
## focus back, not promote itself.
func _test_nonfocused_expiry_focus_restore() -> void:
	scene.checkpoint_ok = true
	var keeper := _accept("Focus keeper")
	if keeper.is_empty(): return
	var objective := {"type": "DELIVER_ORE", "amount_required": 5.0, "reward_credits": 50}
	var offer := {"title": "Expiring side job", "faction": "vanguard", "agent_name": "Local buyer",
		"dialogue": "Before the deadline.", "objective": objective, "choices": [],
		"station_errand": true, "is_timed": true, "time_limit_minutes": 1}
	var choice := {"text": "Accept", "consequence": {"credits_immediate": 0,
		"reputation_change": {}, "reward_credits_multiplier": 1.0}}
	if not quests.accept_quest(offer, choice):
		_expect(false, "Timed side-job fixture rejected: " + quests.last_validation_error)
		quests.abandon_quest()
		return
	var expiring = quests.get_mission_collection().get_by_id(str(quests.active_quest.get("runtime_id", "")))
	if expiring == null:
		_expect(false, "Timed side job did not enter the collection.")
		return
	quests.get_mission_collection().focus(keeper)
	expiring.data["deadline_time_minutes"] = 0
	expiring.data["is_timed"] = true
	scene.checkpoint_ok = false
	quests.check_active_quest_expiration()
	var focused = quests.get_mission_collection().get_focused()
	_expect(focused != null and str(focused.runtime_id) == keeper,
		"A failed nonfocused expiry stole focus from the original mission.")
	_expect(quests.get_mission_collection().get_by_id(str(expiring.runtime_id)) != null,
		"A failed nonfocused expiry dropped the mission instead of restoring it.")
	scene.checkpoint_ok = true
	quests.check_active_quest_expiration()
	_expect(quests.get_mission_collection().get_by_id(str(expiring.runtime_id)) == null,
		"A committed expiry left the mission in the collection.")
	quests.get_mission_collection().focus(keeper)
	quests.abandon_quest()


## An outcome that cannot be built is compatibility handling, not a durable
## record: it must never claim persistence.
func _test_compatibility_is_not_durable() -> void:
	var legacy := {"title": "Legacy", "objective_type": "KILL_SHIPS", "faction": "vanguard"}
	var settled: Dictionary = quests._settle_terminal(legacy, "completed", 0)
	_expect(bool(settled.get("ok", false)), "A legacy termination must still terminate.")
	_expect(not bool(settled.get("durable", true)),
		"An unbuildable outcome reported itself as durably saved.")
	_expect(bool(settled.get("compatibility", false)),
		"An unbuildable outcome did not declare itself as compatibility handling.")
	var typed := legacy.duplicate(true)
	typed["narrative_metadata"] = {"desire_id": "desire.local", "cause_id": "cause.local"}
	var typed_settled: Dictionary = quests._settle_terminal(typed, "completed", 0)
	_expect(not bool(typed_settled.get("ok", true)),
		"Invalid typed outcome data terminated the mission instead of failing closed.")


## The staged bookkeeping is the record; the post-commit callback must not
## replay it, on this run or after a reload.
func _test_staged_callback_applies_once() -> void:
	scene.checkpoint_ok = true
	var runtime_id := _accept("Staged once")
	if runtime_id.is_empty(): return
	manager.story_state["pending_hooks"] = ["A scavenger crew is overdue."]
	var ref := "hook:%s" % "A scavenger crew is overdue.".sha256_text().substr(0, 12)
	quests.active_quest["story_hook_ref"] = ref
	var step_before := int(manager.story_state.get("local_outcome_step", 0))
	quests.complete_quest()
	var step_after := int(manager.story_state.get("local_outcome_step", 0))
	_expect(step_after == step_before + 1,
		"Staged completion bookkeeping did not advance the activity step exactly once.")
	var hooks: Array = manager.story_state.get("pending_hooks", [])
	_expect(hooks.is_empty(), "The accepted story hook was not closed by its settlement.")
	var outcome_id := "%s:completed" % runtime_id
	_expect(manager.is_callback_outcome_applied(outcome_id),
		"The committed outcome recorded no callback marker.")
	# Replaying the post-commit callback (the reload case) must change nothing.
	manager.on_quest_completed({"runtime_id": runtime_id, "terminal_outcome_id": outcome_id,
		"title": "Staged once", "objective_type": "KILL_SHIPS", "faction": "vanguard"})
	_expect(int(manager.story_state.get("local_outcome_step", 0)) == step_after,
		"A replayed completion callback advanced the activity step again.")
	_expect((manager.story_state.get("pending_hooks", []) as Array).is_empty(),
		"A replayed completion callback disturbed the closed hook.")


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
