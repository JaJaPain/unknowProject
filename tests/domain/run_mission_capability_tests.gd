extends SceneTree

const Registry := preload("res://scripts/domain/MissionCapabilityRegistry.gd")
const MissionCap := preload("res://scripts/domain/MissionCapability.gd")
const KillCap := preload("res://scripts/domain/capabilities/KillShipsCapability.gd")
const RecoverCap := preload("res://scripts/domain/capabilities/RecoverCombatDropCapability.gd")
const DeliveryCap := preload("res://scripts/domain/capabilities/DeliveryCourierCapability.gd")
const PurchaseCap := preload("res://scripts/domain/capabilities/PurchaseDeliveryCapability.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_registry_extension_register_and_lookup()
	_test_registry_default_new_mission_types()
	_test_extension_handle_event()
	_test_extension_is_completed()
	_test_extension_format_tracker_text()
	_test_extension_on_complete()
	_test_kill_ships_is_completed()
	_test_kill_ships_handle_event_increments()
	_test_kill_ships_handle_event_wrong_faction()
	_test_kill_ships_handle_event_no_respawn_when_done()
	_test_kill_ships_format_tracker()
	_test_kill_ships_format_tracker_generated_faction()
	_test_recover_handle_event_increments()
	_test_recover_handle_event_wrong_faction()
	_test_recover_handle_event_recovered_sets_flag()
	_test_recover_on_complete_blocks_if_not_recovered()
	_test_recover_on_complete_allows_if_recovered()
	_test_recover_format_tracker_hunting()
	_test_recover_format_tracker_recovered()
	_test_delivery_courier_requires_matching_special_cargo()
	_test_delivery_courier_clears_matching_cargo()
	_test_purchase_delivery_requires_inventory_item()
	_test_purchase_delivery_removes_inventory_quantity()

	if _failures.is_empty():
		print("[PASS] Mission capability tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


# --- Extension test: TEST_ECHO capability (Checkpoint 2 requirement) ---

func _test_registry_extension_register_and_lookup() -> void:
	Registry.reset()
	var cap := _TestEchoCapability.new()
	Registry.register(cap)
	_expect(Registry.has_type("TEST_ECHO"), "TEST_ECHO not registered")
	_expect(not Registry.has_type("NONEXISTENT"), "NONEXISTENT should not exist")
	var found = Registry.get_for_type("TEST_ECHO")
	_expect(found != null, "TEST_ECHO lookup returned null")
	_expect(found.capability_id() == "test_echo", "wrong capability_id")
	Registry.reset()


func _test_registry_default_new_mission_types() -> void:
	Registry.reset()
	_expect(
		Registry.has_type("DELIVERY_COURIER"),
		"DELIVERY_COURIER default capability not registered"
	)
	_expect(
		Registry.has_type("PURCHASE_DELIVERY"),
		"PURCHASE_DELIVERY default capability not registered"
	)
	Registry.reset()


func _test_extension_handle_event() -> void:
	var cap := _TestEchoCapability.new()
	var data := {"echo_count": 0}
	var hints := cap.handle_event(data, "ping", {})
	_expect(hints.get("echoed", false), "handle_event missing echoed hint")
	_expect(int(data["echo_count"]) == 1, "handle_event didn't increment")
	var ignore := cap.handle_event(data, "wrong_event", {})
	_expect(ignore.is_empty(), "wrong event should return empty")
	_expect(int(data["echo_count"]) == 1, "wrong event shouldn't increment")


func _test_extension_is_completed() -> void:
	var cap := _TestEchoCapability.new()
	_expect(not cap.is_completed({"echo_count": 0, "echo_target": 3}), "0/3 should not complete")
	_expect(not cap.is_completed({"echo_count": 2, "echo_target": 3}), "2/3 should not complete")
	_expect(cap.is_completed({"echo_count": 3, "echo_target": 3}), "3/3 should complete")
	_expect(cap.is_completed({"echo_count": 5, "echo_target": 3}), "5/3 should complete")


func _test_extension_format_tracker_text() -> void:
	var cap := _TestEchoCapability.new()
	var text := cap.format_tracker_text({"echo_count": 2, "echo_target": 5})
	_expect(text == "Echo: 2 / 5", "format wrong: '%s'" % text)


func _test_extension_on_complete() -> void:
	var cap := _TestEchoCapability.new()
	var blocked := cap.on_complete({"echo_count": 1, "echo_target": 3})
	_expect(blocked.has("block"), "incomplete should block")
	var ok := cap.on_complete({"echo_count": 3, "echo_target": 3})
	_expect(not ok.has("block"), "complete should not block")
	_expect(ok.get("reward_tag", "") == "test_echo_done", "missing reward_tag")


# --- KillShipsCapability ---

func _test_kill_ships_is_completed() -> void:
	var cap := KillCap.new()
	_expect(not cap.is_completed({"current_count": 2, "count_required": 3}), "2/3 not done")
	_expect(cap.is_completed({"current_count": 3, "count_required": 3}), "3/3 done")
	_expect(cap.is_completed({"current_count": 4, "count_required": 3}), "4/3 done")


func _test_kill_ships_handle_event_increments() -> void:
	var cap := KillCap.new()
	var data := {"current_count": 0, "count_required": 3, "target_faction": "zenith"}
	var hints := cap.handle_event(data, "ship_destroyed", {"faction": "zenith"})
	_expect(int(data["current_count"]) == 1, "didn't increment")
	_expect(hints.get("progress_changed", false), "missing progress_changed")
	_expect(hints.get("needs_respawn", false), "should need respawn at 1/3")


func _test_kill_ships_handle_event_wrong_faction() -> void:
	var cap := KillCap.new()
	var data := {"current_count": 0, "count_required": 2, "target_faction": "zenith"}
	var hints := cap.handle_event(data, "ship_destroyed", {"faction": "aurelia"})
	_expect(hints.is_empty(), "wrong faction should be ignored")
	_expect(int(data["current_count"]) == 0, "wrong faction incremented")


func _test_kill_ships_handle_event_no_respawn_when_done() -> void:
	var cap := KillCap.new()
	var data := {"current_count": 2, "count_required": 3, "target_faction": "zenith"}
	var hints := cap.handle_event(data, "ship_destroyed", {"faction": "zenith"})
	_expect(int(data["current_count"]) == 3, "should reach 3")
	_expect(not hints.get("needs_respawn", false), "should not respawn at 3/3")


func _test_kill_ships_format_tracker() -> void:
	var cap := KillCap.new()
	var text := cap.format_tracker_text({"current_count": 1, "count_required": 3, "target_faction": "zenith"})
	_expect("1 / 3" in text, "missing count: %s" % text)
	_expect("Zenith" in text, "missing faction: %s" % text)


func _test_kill_ships_format_tracker_generated_faction() -> void:
	var cap := KillCap.new()
	var text := cap.format_tracker_text({
		"current_count": 1,
		"count_required": 2,
		"target_faction": "gen_latch_parish_02",
	})
	_expect(text.contains("Latch Parish"), "generated faction display leaked raw ID: %s" % text)
	_expect(
		not text.contains("GEN_LATCH"),
		"generated faction tracker used raw uppercase ID: %s" % text
	)


# --- RecoverCombatDropCapability ---

func _test_recover_handle_event_increments() -> void:
	var cap := RecoverCap.new()
	var data := {"current_count": 0, "target_faction": "vanguard",
		"drop_chance": 0.0, "ship_log_recovered": false}
	var hints := cap.handle_event(data, "ship_destroyed", {"faction": "vanguard"})
	_expect(int(data["current_count"]) == 1, "didn't increment")
	_expect(hints.get("progress_changed", false), "missing progress_changed")
	_expect(hints.get("needs_respawn", false), "0% drop should need respawn")


func _test_recover_handle_event_wrong_faction() -> void:
	var cap := RecoverCap.new()
	var data := {"current_count": 0, "target_faction": "vanguard",
		"drop_chance": 1.0, "ship_log_recovered": false}
	var hints := cap.handle_event(data, "ship_destroyed", {"faction": "aurelia"})
	_expect(hints.is_empty(), "wrong faction should be ignored")


func _test_recover_handle_event_recovered_sets_flag() -> void:
	var cap := RecoverCap.new()
	var data := {"current_count": 0, "target_faction": "vanguard",
		"drop_chance": 1.0, "ship_log_recovered": false,
		"item_name": "black box", "turn_in_location": "Grease Monkeys"}
	var hints := cap.handle_event(data, "ship_destroyed", {"faction": "vanguard"})
	_expect(bool(data.get("ship_log_recovered", false)), "100% drop should recover")
	_expect(data.has("ship_log_entry"), "should set ship_log_entry")
	_expect(hints.has("chatter"), "should emit chatter on recovery")
	_expect(not hints.get("needs_respawn", false), "should not respawn after recovery")


func _test_recover_on_complete_blocks_if_not_recovered() -> void:
	var cap := RecoverCap.new()
	var hints := cap.on_complete({"ship_log_recovered": false})
	_expect(hints.has("block"), "should block if not recovered")


func _test_recover_on_complete_allows_if_recovered() -> void:
	var cap := RecoverCap.new()
	var hints := cap.on_complete({"ship_log_recovered": true})
	_expect(not hints.has("block"), "should allow if recovered")


func _test_recover_format_tracker_hunting() -> void:
	var cap := RecoverCap.new()
	var text := cap.format_tracker_text({"current_count": 2, "ship_log_recovered": false,
		"target_faction": "vanguard"})
	_expect("Wrecks searched: 2" in text, "hunting text wrong: %s" % text)
	_expect("Vanguard" in text, "missing faction: %s" % text)


func _test_recover_format_tracker_recovered() -> void:
	var cap := RecoverCap.new()
	var text := cap.format_tracker_text({"ship_log_recovered": true,
		"item_name": "black box", "turn_in_location": "Grease Monkeys"})
	_expect("Recovered: black box" in text, "recovered text wrong: %s" % text)
	_expect("Grease Monkeys" in text, "missing turn-in: %s" % text)


# --- DeliveryCourierCapability ---

func _test_delivery_courier_requires_matching_special_cargo() -> void:
	var cap := DeliveryCap.new()
	var gs = root.get_node("GlobalState")
	var previous_type: int = gs.cargo_type
	var previous_special: Dictionary = gs.cargo_special.duplicate(true)
	var previous_cargo: float = gs.cargo
	gs.clear_cargo()
	var data := {
		"item_name": "Sealed Evidence Tube",
		"cargo_loaded": true,
		"destination_display": "Kova Station",
	}
	_expect(not cap.is_completed(data), "Courier should not complete with empty hold.")
	gs.accept_special("Wrong Package", "test", "Main Station", "Kova Station")
	_expect(not cap.is_completed(data), "Courier should not complete with wrong cargo.")
	gs.clear_cargo()
	gs.accept_special("Sealed Evidence Tube", "test", "Main Station", "Kova Station")
	_expect(cap.is_completed(data), "Courier should complete with matching special cargo.")
	gs.clear_cargo()
	gs.cargo = previous_cargo
	gs.cargo_type = previous_type
	gs.cargo_special = previous_special


func _test_delivery_courier_clears_matching_cargo() -> void:
	var cap := DeliveryCap.new()
	var gs = root.get_node("GlobalState")
	var previous_type: int = gs.cargo_type
	var previous_special: Dictionary = gs.cargo_special.duplicate(true)
	var previous_cargo: float = gs.cargo
	gs.clear_cargo()
	gs.accept_special("Sealed Evidence Tube", "test", "Main Station", "Kova Station")
	var complete_hints := cap.on_complete({
		"item_name": "Sealed Evidence Tube",
		"cargo_loaded": true,
	})
	var cleanup_hints := cap.on_cleanup({"item_name": "Sealed Evidence Tube"})
	_expect(
		bool(complete_hints.get("clear_cargo", false)),
		"Courier completion should request cargo clearing."
	)
	_expect(
		bool(cleanup_hints.get("clear_cargo", false)),
		"Courier cleanup should request matching cargo clearing."
	)
	gs.clear_cargo()
	gs.cargo = previous_cargo
	gs.cargo_type = previous_type
	gs.cargo_special = previous_special


# --- PurchaseDeliveryCapability ---

func _test_purchase_delivery_requires_inventory_item() -> void:
	var cap := PurchaseCap.new()
	var gs = root.get_node("GlobalState")
	var previous_inventory = gs.inventory
	gs.inventory = gs.PlayerInventoryScript.new()
	var data := {
		"item_id": "data_chip",
		"item_name": "Data Chip",
		"quantity_required": 2,
		"destination_display": "Main Station",
	}
	_expect(not cap.is_completed(data), "Purchase should not complete without item.")
	gs.inventory.add("data_chip", 1)
	_expect(not cap.is_completed(data), "Purchase should not complete with too few items.")
	gs.inventory.add("data_chip", 1)
	_expect(cap.is_completed(data), "Purchase should complete with required quantity.")
	gs.inventory = previous_inventory


func _test_purchase_delivery_removes_inventory_quantity() -> void:
	var cap := PurchaseCap.new()
	var gs = root.get_node("GlobalState")
	var previous_inventory = gs.inventory
	gs.inventory = gs.PlayerInventoryScript.new()
	gs.inventory.add("data_chip", 3)
	var hints := cap.on_complete({
		"item_id": "data_chip",
		"item_name": "Data Chip",
		"quantity_required": 2,
	})
	_expect(
		str(hints.get("remove_inventory_item", "")) == "data_chip"
			and int(hints.get("remove_inventory_quantity", 0)) == 2,
		"Purchase completion should request inventory removal."
	)
	gs.inventory.remove(
		str(hints.get("remove_inventory_item", "")),
		int(hints.get("remove_inventory_quantity", 0))
	)
	_expect(
		gs.inventory.get_quantity("data_chip") == 1,
		"Purchase removal should leave remaining stack quantity."
	)
	gs.inventory = previous_inventory


# --- Test-only capability (Checkpoint 2: extension test) ---

class _TestEchoCapability:
	extends MissionCapability

	func capability_id() -> String:
		return "test_echo"

	func supported_objective_types() -> Array[String]:
		return ["TEST_ECHO"]

	func is_completed(data: Dictionary) -> bool:
		return int(data.get("echo_count", 0)) >= int(data.get("echo_target", 1))

	func handle_event(data: Dictionary, event: String, _event_data: Dictionary) -> Dictionary:
		if event != "ping":
			return {}
		data["echo_count"] = int(data.get("echo_count", 0)) + 1
		return {"echoed": true, "progress_changed": true}

	func format_tracker_text(data: Dictionary) -> String:
		return "Echo: %d / %d" % [
			int(data.get("echo_count", 0)),
			int(data.get("echo_target", 0)),
		]

	func on_complete(data: Dictionary) -> Dictionary:
		if not is_completed(data):
			return {"block": "not enough echoes"}
		return {"reward_tag": "test_echo_done"}
