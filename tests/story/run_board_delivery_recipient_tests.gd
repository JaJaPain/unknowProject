extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var gs := root.get_node("GlobalState")
	var qm := root.get_node("QuestManager")
	var builder = load("res://scripts/domain/PublicBoardOfferBuilder.gd")
	var ui_script := GDScript.new()
	ui_script.source_code = 'extends "res://scripts/UIManager.gd"\nvar docked_id := ""\nvar receiver := ""\nfunc _ready() -> void:\n\tpass\nfunc _current_turn_in_station_id() -> String:\n\treturn docked_id\nfunc _render_dock_submenu() -> void:\n\t_refresh_board_delivery_button()\nfunc _show_lounge_card_line(card: Dictionary, _line: String, _speak: bool = true, _choices: Array = [], _memory: bool = false) -> void:\n\treceiver = str(card.get("name", ""))\n'
	if ui_script.reload() != OK:
		quit(1)
		return
	var ui: Node = ui_script.new()
	root.add_child(ui)
	ui.dock_panel = Panel.new()
	ui.board_delivery_btn = Button.new()
	ui.add_child(ui.dock_panel)
	ui.add_child(ui.board_delivery_btn)
	var station := Node3D.new()
	root.add_child(station)
	ui.current_station = station
	gs.current_system_id = "start_system"
	gs.cargo_type = gs.CargoType.EMPTY
	gs.cargo_special = {}
	var offer: Dictionary = builder._build_courier_offer(480)
	var data: Dictionary = offer["quest_data"]
	data["objective"]["destination_station_id"] = "missing.recipient"
	var credits_before: int = gs.player_credits
	_expect(not qm.accept_quest(data, data["choices"][0]), "Missing recipient must reject acceptance")
	_expect(gs.player_credits == credits_before and gs.cargo_special.is_empty() and not qm.is_lane_occupied("BOARD"), "Rejected offer must not change cargo, credits or lane")
	data["objective"]["destination_station_id"] = "kova"
	_expect(qm.accept_quest(data, data["choices"][0]), "Kova delivery must accept")
	# Accepted state is the focused mission.
	# Resolve via the accepted focus, independent of enum numeric values.
	var accepted: Dictionary = qm.active_quest
	var recipient := str(accepted.get("delivery_recipient_name", ""))
	_expect(recipient in gs.get_minor_npcs_at_outpost("kova"), "Accepted mission must name a local resident")
	_expect(gs.cargo_special.get("delivery_assignment", {}).get("recipient_name", "") == recipient, "Cargo must carry recipient assignment")
	ui.docked_id = "iron_reach"
	ui.call("_refresh_board_delivery_button")
	_expect(not ui.board_delivery_btn.visible, "Wrong dock must not offer handover")
	ui.docked_id = "station.start.kova"
	ui.call("_refresh_board_delivery_button")
	_expect(ui.board_delivery_btn.visible and ui.board_delivery_btn.text.contains(recipient), "Matching dock must expose named recipient")
	gs.cargo_special["delivery_assignment"]["destination_station_id"] = "iron_reach"
	ui.call("_refresh_board_delivery_button")
	_expect(not ui.board_delivery_btn.visible, "Cargo assignment mismatch must block handover")
	gs.cargo_special["delivery_assignment"]["destination_station_id"] = "kova"
	var adapter = load("res://scripts/domain/MissionAdapter.gd")
	var restored: Dictionary = adapter.normalize_legacy_state(accepted.duplicate(true))
	_expect(restored.get("delivery_recipient_name", "") == recipient, "Save normalization must retain the assigned person")
	gs.generated_outpost_npcs["kova"] = []
	ui.call("_refresh_board_delivery_button")
	_expect(not ui.board_delivery_btn.visible and not gs.cargo_special.is_empty(), "Missing recipient at dock must retain cargo and hide handover")
	gs.generated_outpost_npcs.erase("kova")
	# Existing saves with no assignment are repaired from mission and local roster.
	accepted.erase("delivery_recipient_name")
	gs.cargo_special.erase("delivery_assignment")
	ui.call("_refresh_board_delivery_button")
	_expect(ui.board_delivery_btn.visible and gs.cargo_special.has("delivery_assignment"), "Legacy delivery must acquire a usable assignment")
	var payout: int = qm.active_quest_payout()
	credits_before = gs.player_credits
	ui.call("_on_public_board_turn_in_pressed")
	_expect(not qm.is_lane_occupied("BOARD") and gs.cargo_special.is_empty(), "Handover must remove mission and cargo")
	_expect(gs.player_credits == credits_before + payout and ui.receiver == recipient, "Local recipient must acknowledge one correct payment")
	ui.call("_on_public_board_turn_in_pressed")
	_expect(gs.player_credits == credits_before + payout, "Repeated handover must not pay twice")
	gs.generated_outpost_npcs["station.generated.test"] = ["Generated Receiver"]
	gs.generated_outpost_npc_data["Generated Receiver"] = {"role": "Dock worker", "voice_profile_id": "voice.hana_quill.v1"}
	_expect(gs.get_delivery_recipient("station.generated.test").get("name", "") == "Generated Receiver", "Generated stations must use their stored local resident")
	_expect(gs.get_delivery_recipient("station.generated.test", "Foreign Person").is_empty(), "Assigned recipient cannot silently become someone else")
	var generated_system := Node3D.new()
	root.add_child(generated_system)
	var primary := Node3D.new()
	primary.name = "Station"
	primary.set_meta("world_id", "station.generated.test")
	generated_system.add_child(primary)
	gs.active_system_root = generated_system
	gs.current_system_id = "generated.test"
	_expect(gs.get_delivery_recipient("generated.test").get("name", "") == "Generated Receiver", "Generated primary station must resolve its local recipient from system destination ID")
	gs.active_system_root = null
	generated_system.free()
	gs.generated_outpost_npcs.erase("station.generated.test")
	gs.generated_outpost_npc_data.erase("Generated Receiver")
	ui.free()
	station.free()
	for failure in failures:
		push_error("[FAIL] " + failure)
	if failures.is_empty():
		print("[PASS] Board delivery recipient acceptance, cargo assignment, docking, legacy repair, local handover and single payout")
	quit(0 if failures.is_empty() else 1)

func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
