extends SceneTree

const Builder := preload("res://scripts/domain/InvestigationOfferBuilder.gd")
const Planner := preload("res://scripts/domain/InvestigationSitePlanner.gd")
const Shapes := preload("res://scripts/domain/MissionShapeRegistry.gd")
const Validator := preload("res://scripts/domain/InvestigationStateValidator.gd")

class Pilot extends CharacterBody3D:
	var is_docked := false
	var destroyed := false
	var obstacles: Array = []
	func navigation_obstacle_snapshot() -> Array:
		return obstacles.duplicate(true)

class DockUI extends Control:
	var current_station: Node3D
	var command := ""
	func _command_selected_target(value: String) -> bool:
		command = value
		return true

class Dock extends Node3D:
	var world_id := "station.test"
	func get_world_id() -> String:
		return world_id

var failures: Array[String] = []
var qm: Node
var gs: Node
var pilot: Pilot
var ui: DockUI

func _initialize():
	call_deferred("_run")

func _run():
	qm = root.get_node("QuestManager")
	gs = root.get_node("GlobalState")
	qm.set_physics_process(false)
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var canvas := CanvasLayer.new()
	canvas.name = "CanvasLayer"
	scene.add_child(canvas)
	ui = DockUI.new()
	ui.name = "UIManager"
	canvas.add_child(ui)
	ui.current_station = Dock.new()
	ui.current_station.name = "station.test"
	scene.add_child(ui.current_station)
	ui.current_station.add_to_group("station")
	pilot = Pilot.new()
	scene.add_child(pilot)
	gs.player = pilot
	gs.current_system_id = "system.test"
	_test_scan_authority_and_survey()
	_test_wrong_certification_and_report_escape()
	_test_inventory_replay_and_turn_in()
	_test_corrupt_restore_is_atomic()
	_test_canonical_save_roundtrip()
	_test_acceptance_placement_guard()
	_test_world_discovery_and_panel()
	qm.restore_active_quest({})
	gs.player = null
	if failures.is_empty():
		print("[PASS] Investigation runtime: acceptance, holds, live guards, replay, inventory, payout and restore")
	else:
		for failure in failures:
			push_error("[FAIL] " + failure)
	quit(0 if failures.is_empty() else 1)

func _accept(recipe: String, expected := true) -> bool:
	qm.restore_active_quest({})
	pilot.is_docked = false
	var registry := Shapes.new()
	registry.load_from_path()
	var shape = registry.shape_for_recipe(recipe)
	var placement := Planner.plan_sites(42, [{"id": "station.test", "position": Vector3.ZERO}], [])
	var built := Builder.build_objective("mission.offer.test", {"id": str(shape.id), "recipe": recipe, "branch_ids": shape.branch_ids}, 42, placement, 401, "station.test", ["faction.local.a", "faction.local.b"], "system.test")
	var choice := {"id": "choice.accept", "text": "Accept", "consequence": {}}
	var accepted: bool = qm.accept_quest({"id": "mission.offer.test", "title": "Investigation fixture", "faction": "neutral", "agent_name": "Local Survey Clerk", "objective": built["objective"], "choices": [choice]}, choice)
	_expect(accepted == expected, "Unexpected investigation acceptance: %s" % qm.last_validation_error)
	return accepted

func _test_acceptance_placement_guard():
	gs.current_system_id = "system.test"
	ui.current_station.world_id = "station.test"
	ui.current_station.add_to_group("station")
	if not _accept("survey_discrepancy"):
		return
	var saved_truth: Dictionary = qm.active_quest["investigation"].duplicate(true)
	var p: Array = saved_truth["sites"][0]["position"]
	pilot.obstacles = [{"center": Vector3(p[0], p[1], p[2]), "radius": 500.0, "physical": 100.0}]
	var credits_before: int = gs.player_credits
	_accept("survey_discrepancy", false)
	_expect(qm.last_validation_error.contains("site_obstructed"), "Unsafe site did not report obstruction.")
	_expect(qm.active_quest.is_empty() and gs.player_credits == credits_before, "Rejected placement changed mission or credits.")
	pilot.obstacles.clear()
	var verification: Array = saved_truth["sites"][1]["position"]
	var gate := Node3D.new()
	current_scene.add_child(gate)
	gate.global_position = Vector3(verification[0], verification[1], verification[2])
	gate.add_to_group("jumpgate")
	_accept("survey_discrepancy", false)
	_expect(qm.last_validation_error.contains("site_obstructed"), "Verification site overlapping gate was accepted.")
	gate.free()
	gs.player = null
	_accept("survey_discrepancy", false)
	_expect(qm.last_validation_error.contains("navigation_unavailable"), "Absent navigation was treated as empty space.")
	gs.player = pilot
	ui.current_station.remove_from_group("station")
	_accept("survey_discrepancy", false)
	_expect(qm.last_validation_error.contains("turn_in_station_unavailable"), "Missing station was accepted.")
	ui.current_station.add_to_group("station")
	if _accept("survey_discrepancy"):
		_expect(qm.active_quest["investigation"] == saved_truth, "Placement check rerolled mission truth.")

func _site(role: String) -> Dictionary:
	for site: Dictionary in qm.active_quest["investigation"]["sites"]:
		if site["role"] == role:
			return site
	return {}

func _test_world_discovery_and_panel():
	if not _accept("survey_discrepancy"): return
	var mission_id: String = qm.active_quest["runtime_id"]
	var primary := _site("primary")
	var verification := _site("verification")
	pilot.global_position = Vector3(90000, 0, 0)
	qm.reconcile_investigation_sites()
	_expect(qm.investigation_revealed_sites(mission_id).size() == 1, "Hidden sites were spawned outside sensor range.")
	_expect(qm.investigation_site_target(mission_id, verification["id"]) == null, "Verification node leaked before first scan.")
	var view: Dictionary = qm.investigation_panel_view(mission_id)
	_expect(view["evidence"].is_empty() and not JSON.stringify(view).contains("observed_code"), "Panel exposed hidden truth.")
	_move(primary)
	qm.reconcile_investigation_sites()
	var marker: Node3D = qm.investigation_site_target(mission_id, primary["id"])
	_expect(marker != null and not marker.is_in_group("anomaly"), "Detected mission site missing or ordinary anomaly activated.")
	_expect(not marker.has_meta("code") and not marker.has_meta("owner_faction_id"), "World marker carries hidden truth.")
	qm.reconcile_investigation_sites()
	_expect(qm.investigation_site_target(mission_id, primary["id"]) == marker, "Reconcile duplicated the mission site.")
	var position: Vector3 = marker.global_position
	pilot.global_position = position + Vector3(1900, 0, 0)
	qm.reconcile_investigation_sites()
	_expect(qm.investigation_site_target(mission_id, primary["id"]) == marker, "Contact dropped inside hysteresis range.")
	pilot.global_position = position + Vector3(9000, 0, 0)
	qm.reconcile_investigation_sites()
	_expect(qm.investigation_site_target(mission_id, primary["id"]) == null, "Unscanned contact stayed revealed outside drop range.")
	_move(primary)
	qm.reconcile_investigation_sites()
	marker = qm.investigation_site_target(mission_id, primary["id"])
	var panel = load("res://scripts/ui/InvestigationPanel.gd").new()
	ui.add_child(panel)
	panel.setup(ui, qm)
	panel.open_mission(mission_id)
	var scan := _panel_button(panel, "Scan Investigation signal")
	_expect(scan != null and not scan.disabled, "Visible nearby site has no usable Scan button.")
	if scan != null: scan.pressed.emit()
	for frame in range(31): qm._physics_process(0.1)
	qm.reconcile_investigation_sites()
	panel._refresh()
	_expect(qm.investigation_site_target(mission_id, verification["id"]) != null, "First scan did not reveal verification marker.")
	_expect(qm.investigation_site_target(mission_id, "search") == null, "Completed search retained its search circle.")
	view = qm.investigation_panel_view(mission_id)
	_expect(view["evidence"].size() == 1 and "Primary route code: A" in view["evidence"], "Panel failed to expose observed evidence.")
	var saved: Array = qm.capture_all_quests()
	gs.active_target = marker
	gs.current_system_id = "system.away"
	qm.reconcile_investigation_sites()
	_expect(qm.investigation_revealed_sites(mission_id).is_empty() and gs.active_target == null, "Leaving system retained mission targets.")
	gs.current_system_id = "system.test"
	_expect(qm.restore_all_quests(JSON.parse_string(JSON.stringify(saved))), "World mission failed saved restore.")
	qm.reconcile_investigation_sites()
	_expect(qm.investigation_site_target(mission_id, verification["id"]) != null, "Restored scan lost verification marker.")
	_move(verification)
	panel._refresh()
	scan = _panel_button(panel, "Scan Verification site")
	_expect(scan != null and not scan.disabled, "Verification scan button missing after restore.")
	if scan != null: scan.pressed.emit()
	for frame in range(31): qm._physics_process(0.1)
	panel._refresh()
	var branch := "Certify that the codes match" if primary["code"] == verification["code"] else "Certify that the codes differ"
	var resolve := _panel_button(panel, branch)
	_expect(resolve != null and not resolve.disabled, "Verified evidence has no usable resolution button.")
	if resolve != null: resolve.pressed.emit()
	_expect(qm.is_quest_completed() and qm.active_quest_payout() == 401, "Panel resolution failed or paid incorrect reward.")
	qm.reconcile_investigation_sites()
	_expect(qm.investigation_revealed_sites(mission_id).is_empty(), "Resolved sites were not cleaned up.")
	panel.free()
	qm.restore_active_quest({})
	_expect(get_nodes_in_group("mission_investigation_marker").is_empty(), "Reset left orphan mission nodes.")
	if _accept("survey_discrepancy"):
		var corrupt: Dictionary = qm.active_quest.duplicate(true)
		corrupt["investigation"]["search_center"] = [90000, 90000, 90000]
		_expect(not qm.can_restore_active_quest(corrupt), "Search region excluded its own primary site.")
		qm.reconcile_investigation_sites()
		qm.abandon_quest()
		qm.reconcile_investigation_sites()
		_expect(get_nodes_in_group("mission_investigation_marker").is_empty(), "Abandonment left orphan mission nodes.")

func _panel_button(panel: Control, label: String) -> Button:
	for child in panel.rows.get_children():
		if child is Button and child.text == label: return child
	return null

func _move(site: Dictionary):
	var p: Array = site["position"]
	pilot.global_position = Vector3(p[0], p[1], p[2])
	pilot.velocity = Vector3.ZERO

func _command(action: String, site: Dictionary, branch := "") -> Dictionary:
	return {"mission_id": qm.active_quest["runtime_id"], "site_id": site["id"], "action": action, "branch_id": branch, "expected_revision": qm.active_quest["investigation"]["investigation_revision"]}

func _scan(role: String):
	var site := _site(role)
	_move(site)
	var started: Dictionary = qm.begin_investigation_scan(qm.active_quest["runtime_id"], site["id"])
	_expect(started.get("ok", false), "Scan did not begin.")
	for frame in range(31):
		qm._physics_process(0.1)
	_expect(site["id"] in qm.active_quest["investigation"]["scanned_site_ids"], "Completed hold did not commit evidence.")

func _test_scan_authority_and_survey():
	if not _accept("survey_discrepancy"):
		return
	var primary := _site("primary")
	_move(primary)
	var forged := _command("scan_complete", primary)
	forged["hold_token"] = "invented"
	_expect(not qm.dispatch_investigation_command(forged).get("ok", true), "Forged scan token passed.")
	_expect(not qm.begin_investigation_scan(qm.active_quest["runtime_id"], _site("verification")["id"]).get("ok", true), "Hidden verification scanned first.")
	qm.begin_investigation_scan(qm.active_quest["runtime_id"], primary["id"])
	qm._physics_process(2.0)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(qm.capture_active_quest()))
	_expect(qm.restore_active_quest(saved), "Mid-scan restore failed.")
	qm._physics_process(2.0)
	_expect(qm.active_quest["investigation"]["evidence"].is_empty(), "Reload banked scan progress.")
	_scan("primary")
	var pending := _command("resolve", _site("primary"), "certify_match")
	_expect(not qm.dispatch_investigation_command(pending).get("ok", true), "Certification skipped verification.")
	_scan("verification")
	_expect(not qm.is_quest_completed(), "Scanning completed the job without a decision.")
	var branch := "certify_match" if _site("primary")["code"] == _site("verification")["code"] else "certify_mismatch"
	var command := _command("resolve", _site("verification"), branch)
	var combat = root.get_node("CombatManager")
	combat.state = 1
	_expect(not qm.dispatch_investigation_command(command).get("ok", true), "Combat bypassed live guard.")
	combat.state = 0
	pilot.global_position += Vector3(301, 0, 0)
	_expect(not qm.dispatch_investigation_command(command).get("ok", true), "Remote resolution bypassed range guard.")
	_move(_site("verification"))
	pilot.velocity = Vector3(11, 0, 0)
	_expect(not qm.dispatch_investigation_command(command).get("ok", true), "Moving ship bypassed current pose guard.")
	pilot.velocity = Vector3.ZERO
	var resolved: Dictionary = qm.dispatch_investigation_command(command)
	_expect(resolved.get("ok", false) and qm.is_quest_completed(), "Correct certification did not ready the mission.")
	_expect(qm.active_quest_payout() == 401, "Correct survey payout changed.")
	_expect(qm.dispatch_investigation_command(command).get("replayed", false), "Retry did not return original result.")

func _test_wrong_certification_and_report_escape():
	if not _accept("survey_discrepancy"):
		return
	_scan("primary")
	_scan("verification")
	var wrong := "certify_mismatch" if _site("primary")["code"] == _site("verification")["code"] else "certify_match"
	var command := _command("resolve", _site("verification"), wrong)
	_expect(qm.dispatch_investigation_command(command).get("ok", false), "Wrong conclusion stranded the job.")
	_expect(qm.active_quest_payout() == 100, "Wrong certification must floor one quarter of the approved budget.")
	if not _accept("competing_claims"):
		return
	gs.inventory.clear()
	_scan("primary")
	command = _command("resolve", _site("primary"), "report")
	_expect(qm.dispatch_investigation_command(command).get("ok", false) and qm.active_quest_payout() == 200, "Missing consumables stranded the no-cost report path.")

func _test_inventory_replay_and_turn_in():
	if not _accept("competing_claims"):
		return
	gs.inventory.clear()
	_scan("primary")
	var command := _command("resolve", _site("primary"), "liquidate")
	command["has_consumable"] = true
	var before := JSON.stringify(qm.capture_active_quest())
	_expect(not qm.dispatch_investigation_command(command).get("ok", true), "UI inventory flag was trusted.")
	_expect(before == JSON.stringify(qm.capture_active_quest()), "Failed spend mutated mission.")
	gs.inventory.add("salvage_drone", 2)
	var resolved: Dictionary = qm.dispatch_investigation_command(command)
	_expect(resolved.get("ok", false) and gs.inventory.get_quantity("salvage_drone") == 1, "Liquidation did not spend exactly one drone.")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(qm.capture_active_quest()))
	_expect(qm.restore_active_quest(saved), "Resolved mission did not restore.")
	_expect(qm.dispatch_investigation_command(command).get("replayed", false) and gs.inventory.get_quantity("salvage_drone") == 1, "Reload/retry spent twice.")
	_expect(qm.active_quest_payout() == 601, "Fractional payout was not floored once.")
	var credits: int = gs.player_credits
	qm.complete_quest()
	_expect(gs.player_credits == credits and qm.is_quest_active(), "Undocked turn-in paid.")
	pilot.is_docked = true
	ui.current_station.world_id = "station.wrong"
	qm.complete_quest()
	_expect(gs.player_credits == credits, "Wrong station paid.")
	ui.current_station.world_id = "station.test"
	var reentrant := func(_credits): qm.complete_quest()
	gs.credits_changed.connect(reentrant)
	qm.complete_quest()
	gs.credits_changed.disconnect(reentrant)
	qm.complete_quest()
	_expect(gs.player_credits == credits + 601 and not qm.is_quest_active(), "Turn-in failed or paid twice.")

func _test_corrupt_restore_is_atomic():
	if not _accept("survey_discrepancy"):
		return
	var before := JSON.stringify(qm.capture_all_quests())
	var broken: Array = JSON.parse_string(before)
	broken[0]["investigation"]["sites"][0]["position"] = [1, 2]
	_expect(not qm.restore_all_quests(broken), "Corrupt sites restored.")
	_expect(before == JSON.stringify(qm.capture_all_quests()), "Failed restore erased current missions.")
	var data: Dictionary = qm.capture_active_quest().duplicate(true)
	data["investigation"]["phase"] = "ready"
	_expect(not Validator.validate(data).is_valid(), "Ready state without evidence/choice passed.")

func _expect(ok: bool, message: String):
	if not ok:
		failures.append(message)

func _test_canonical_save_roundtrip():
	if not _accept("survey_discrepancy"):
		return
	_scan("primary")
	var saved: Dictionary = qm.capture_active_quest().duplicate(true)
	saved["system_id"] = "start_system"
	for site: Dictionary in saved["investigation"]["sites"]:
		site["system_id"] = "start_system"
	var registry = load("res://scripts/registry/SystemRegistry.gd").load_default()
	var migrator = load("res://scripts/persistence/SaveMigrator.gd")
	var encoded: Dictionary = migrator.prepare_for_save({"current_system_id": "start_system", "player": {}, "global": {"inventory": gs.inventory.to_dict()}, "quest": [saved], "systems": {}}, registry)
	_expect(encoded.get("ok", false), "Real save encoding failed: %s" % encoded.get("error", ""))
	if not encoded.get("ok", false):
		return
	var decoded: Dictionary = migrator.decode_for_runtime(JSON.parse_string(JSON.stringify(encoded["data"])), registry)
	_expect(decoded.get("ok", false), "Real save decoding failed.")
	if not decoded.get("ok", false):
		return
	var restored: Dictionary = decoded["data"]["quest"][0]
	_expect(Validator.validate(restored).is_valid(), "Site scope did not roundtrip with its mission.")
	_expect(JSON.stringify(restored["investigation"]) == JSON.stringify(JSON.parse_string(JSON.stringify(saved["investigation"]))), "Save alias mapping changed investigation truth or evidence.")
