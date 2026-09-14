extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var gs := root.get_node("GlobalState")
	var quests := root.get_node("QuestManager")
	var script := GDScript.new()
	script.source_code = 'extends "res://scripts/UIManager.gd"\nvar command := ""\nvar docked_id := ""\nfunc _command_selected_target(mode: String) -> bool:\n\tcommand = mode\n\treturn true\nfunc _update_first_turn_in_flash(_wanted: bool) -> void:\n\tpass\nfunc _station_contact_id_for_node(station: Node3D) -> String:\n\treturn str(station.get_meta("contact_id", ""))\nfunc _current_turn_in_station_id() -> String:\n\treturn docked_id\n'
	script.source_code += "\nfunc _ready() -> void:\n\tpass\n"
	var compiled := script.reload()
	if compiled != OK or not script.can_instantiate():
		push_error("[FAIL] Mission card UI probe did not compile")
		quit(1)
		return
	var ui: Node = script.new()
	root.add_child(ui)
	ui.quest_tracker_route_btn = Button.new()
	ui.quest_tracker_turn_in_btn = Button.new()
	ui.quest_tracker_progress = Label.new()
	ui.add_child(ui.quest_tracker_route_btn)
	ui.add_child(ui.quest_tracker_turn_in_btn)
	ui.add_child(ui.quest_tracker_progress)
	var system := Node3D.new()
	root.add_child(system)
	var home := Node3D.new()
	home.name = "Station"
	system.add_child(home)
	var outpost := Node3D.new()
	outpost.set_meta("contact_id", "iron_reach")
	system.add_child(outpost)
	outpost.add_to_group("station")
	gs.active_system_root = system
	gs.active_system_entities.clear()
	gs.active_system_entities.append(home)
	gs.active_system_entities.append(outpost)
	gs.current_system_id = "start_system"
	gs.cargo_type = gs.CargoType.SPECIAL
	gs.cargo_special = {"name": "Firmware Brick"}
	quests.active_quest = {
		"runtime_id": "mission.test.courier", "title": "Courier test",
		"public_board": true, "objective_type": "DELIVERY_COURIER",
		"cargo_loaded": true, "item_name": "Firmware Brick",
		"destination_station_id": "iron_reach", "destination_display": "Outpost Iron Reach",
	}
	var q: Dictionary = quests.active_quest
	_expect(quests.is_quest_completed(), "Fixture must reproduce cargo-ready state from the screenshot")
	ui.call("_update_quest_tracker_route_button", q)
	_expect(ui.quest_tracker_route_btn.visible and not ui.quest_tracker_route_btn.disabled, "Loaded courier must have a usable route")
	_expect(ui.quest_tracker_route_btn.text == "Dock at Outpost Iron Reach", "Button must name the delivery destination")
	ui.call("_on_quest_tracker_route_pressed")
	_expect(gs.active_target == outpost and ui.command == "DOCK", "Click must dock at the outpost, not the issuing main station")
	_expect(ui.call("_quest_tracker_route_target", q) == outpost, "Progress-text click must use the same outpost")
	var text: String = ui.call("_completed_contract_tracker_text", q)
	_expect(text.contains("Outpost Iron Reach") and not text.contains("satisfied"), "Cargo aboard must not be described as delivered")
	ui.current_station = home
	ui.docked_id = "start_system"
	ui.call("_update_quest_tracker_turn_in_button", q)
	_expect(ui.quest_tracker_turn_in_btn.disabled, "Wrong-station turn-in must remain disabled")
	ui.current_station = outpost
	ui.docked_id = "iron_reach"
	ui.call("_update_quest_tracker_turn_in_button", q)
	_expect(not ui.quest_tracker_turn_in_btn.disabled, "Destination turn-in must be enabled")
	q["destination_station_id"] = "station.start.iron_reach"
	_expect(ui.call("_quest_tracker_turn_in_target", q) == outpost, "Canonical station IDs must resolve through existing aliases")
	_expect(ui.call("_mission_can_turn_in_at_current_station", q), "Canonical destination aliases must also allow turn-in at the matching outpost")
	q["destination_station_id"] = "missing_outpost"
	_expect(ui.call("_quest_tracker_turn_in_target", q) == null, "Missing destination must not fall back to the main station")
	ui.call("_update_quest_tracker_route_button", q)
	_expect(ui.quest_tracker_route_btn.visible and ui.quest_tracker_route_btn.disabled, "Unavailable destination must disable the route button")
	q["destination_station_id"] = "start_system"
	_expect(ui.call("_quest_tracker_turn_in_target", q) == home, "System-ID delivery destinations must resolve to the primary station")
	q["objective_type"] = "PURCHASE_DELIVERY"
	q["destination_station_id"] = "iron_reach"
	_expect(ui.call("_quest_tracker_turn_in_target", q) == outpost, "Purchase deliveries must obey their destination too")
	q["objective_type"] = "KILL_SHIPS"
	_expect(ui.call("_quest_tracker_turn_in_target", q) == home, "Ordinary combat turn-ins must retain their main-station route")
	quests.active_quest = {}
	gs.active_target = null
	gs.active_system_entities.clear()
	gs.active_system_root = null
	gs.cargo_type = gs.CargoType.EMPTY
	gs.cargo_special = {}
	ui.free()
	system.free()
	if failures.is_empty():
		print("[PASS] Mission card delivery routes: courier click, destination label, turn-in gating, aliases, purchase delivery and combat regression")
	else:
		for failure in failures:
			push_error("[FAIL] " + failure)
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
