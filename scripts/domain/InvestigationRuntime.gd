extends RefCounted

## Runtime authority around the pure capability. UI commands supply identities
## and intent only; pose, combat, time, hold completion and inventory come here.
const Registry := preload("res://scripts/domain/MissionCapabilityRegistry.gd")
const Validator := preload("res://scripts/domain/InvestigationStateValidator.gd")
const Hold := preload("res://scripts/domain/ScanHoldController.gd")

var _hold := Hold.new()
var _scan := {}
var _busy := false

func reset() -> void:
	_hold = Hold.new()
	_scan.clear()

func _mission(owner: Node, id: String):
	var mission = owner.get_mission_collection().get_by_id(id)
	if mission == null or mission.is_terminal() or str(mission.data.get("objective_type", "")) != "INVESTIGATE_SIGNAL":
		return null
	return mission

func begin_scan(owner: Node, mission_id: String, site_id: String) -> Dictionary:
	reset()
	var mission = _mission(owner, mission_id)
	if mission == null:
		return {"ok": false, "reason": "mission_not_active"}
	var state: Dictionary = mission.data.get("investigation", {})
	var cap = Registry.get_for_type("INVESTIGATE_SIGNAL")
	var site: Dictionary = cap._site(state, site_id)
	if site.is_empty() or state.get("phase", "") in ["ready", "closed"]:
		return {"ok": false, "reason": "site_unavailable"}
	if site.get("role", "") == "verification" and not cap._role_scanned(state, "primary"):
		return {"ok": false, "reason": "verification_locked"}
	if state.get("scanned_site_ids", []).has(site_id):
		return {"ok": true, "reason": "already_scanned"}
	_scan = {"mission_id": mission_id, "site_id": site_id, "revision": int(state.get("investigation_revision", 0))}
	return {"ok": true, "reason": "holding"}

func tick(owner: Node, delta: float) -> Dictionary:
	if _scan.is_empty():
		return {}
	var mission = _mission(owner, str(_scan["mission_id"]))
	if mission == null or owner.get_tree().paused:
		reset()
		return {"ok": false, "reason": "scan_cancelled"}
	var state: Dictionary = mission.data["investigation"]
	if int(state["investigation_revision"]) != int(_scan["revision"]):
		reset()
		return {"ok": false, "reason": "stale_revision"}
	var cap = Registry.get_for_type("INVESTIGATE_SIGNAL")
	var site: Dictionary = cap._site(state, str(_scan["site_id"]))
	var pose := _pose(owner, mission.data, site)
	if not bool(pose.get("ok", false)):
		_hold.reset()
		return pose
	var progress := _hold.update(delta, str(site["id"]), float(pose["distance"]), float(pose["speed"]), bool(pose["combat"]))
	if progress["state"] != Hold.STATE_COMPLETE:
		return progress
	var command := {
		"mission_id": _scan["mission_id"], "site_id": site["id"],
		"action": "scan_complete", "expected_revision": _scan["revision"],
		"hold_token": progress["token"],
	}
	var result := dispatch(owner, command)
	reset()
	return result

func _pose(owner: Node, data: Dictionary, site: Dictionary) -> Dictionary:
	var gs = owner.get_node("/root/GlobalState")
	var player = gs.player
	if not is_instance_valid(player) or str(gs.current_system_id) != str(data.get("system_id", "")) or str(site.get("system_id", "")) != str(gs.current_system_id):
		return {"ok": false, "reason": "wrong_system_or_missing_player"}
	if not player is CharacterBody3D or bool(player.get("is_docked")) or bool(player.get("destroyed")):
		return {"ok": false, "reason": "ship_unavailable"}
	var pos: Array = site.get("position", [])
	if not Validator._position(pos):
		return {"ok": false, "reason": "invalid_site_position"}
	var distance: float = player.global_position.distance_to(Vector3(float(pos[0]), float(pos[1]), float(pos[2])))
	var speed: float = player.velocity.length()
	if not is_finite(distance) or not is_finite(speed):
		return {"ok": false, "reason": "invalid_player_pose"}
	var combat = owner.get_node("/root/CombatManager")
	return {"ok": true, "distance": distance, "speed": speed, "combat": int(combat.state) != 0}

func dispatch(owner: Node, command: Dictionary) -> Dictionary:
	if _busy:
		return {"ok": false, "reason": "command_in_progress"}
	var mission_id := str(command.get("mission_id", ""))
	var mission = _mission(owner, mission_id)
	if mission == null:
		return {"ok": false, "reason": "mission_not_active"}
	var data: Dictionary = mission.data
	var validation = Validator.validate(data)
	if not validation.is_valid():
		return {"ok": false, "reason": "invalid_investigation_state"}
	var state: Dictionary = data["investigation"]
	var action := str(command.get("action", ""))
	if action not in ["scan_complete", "resolve"]:
		return {"ok": false, "reason": "unsupported_runtime_action"}
	var site_id := str(command.get("site_id", ""))
	var id := "%s:%s:scan" % [mission_id, site_id] if action == "scan_complete" else "%s:resolve" % mission_id
	# Do not accept client-selected command IDs, inventory flags or side effects.
	var applied: Dictionary = state.get("applied_commands", {})
	if applied.has(id):
		var replay: Dictionary = applied[id].duplicate(true)
		replay.merge({"ok": true, "replayed": true, "revision": state["investigation_revision"], "phase": state["phase"]}, true)
		return replay
	if int(command.get("expected_revision", -1)) != int(state["investigation_revision"]):
		return {"ok": false, "reason": "stale_revision", "revision": state["investigation_revision"]}
	var cap = Registry.get_for_type("INVESTIGATE_SIGNAL")
	var site: Dictionary = cap._site(state, site_id)
	# Resolve from either already scanned site. Visiting the verification site
	# need not require flying back just to compare records.
	if action == "resolve" and site_id not in state["scanned_site_ids"]:
		return {"ok": false, "reason": "missing_scan"}
	var pose := _pose(owner, data, site)
	if not bool(pose.get("ok", false)):
		return pose
	var blocker := _hold._blocking_reason(float(pose["distance"]), float(pose["speed"]), bool(pose["combat"]))
	if not blocker.is_empty():
		return {"ok": false, "reason": blocker}
	if action == "scan_complete":
		if _scan.get("mission_id", "") != mission_id or _scan.get("site_id", "") != site_id or int(_scan.get("revision", -1)) != int(state["investigation_revision"]) or not _hold.consume_token(str(command.get("hold_token", "")), site_id):
			return {"ok": false, "reason": "scan_hold_required"}
	var gs = owner.get_node("/root/GlobalState")
	var item := str(cap.BRANCH_CONSUMABLE.get(str(command.get("branch_id", "")), ""))
	var draft := data.duplicate(true)
	var result: Dictionary = cap.handle_event(draft, "investigation_command", {
		"command_id": id, "action": action, "site_id": site_id,
		"branch_id": str(command.get("branch_id", "")),
		"expected_revision": command["expected_revision"],
		"minute": int(owner.get_node("/root/CampaignClock").total_minutes),
		"has_consumable": not item.is_empty() and gs.inventory.has_item(item),
	})
	if not bool(result.get("accepted", false)):
		result["ok"] = false
		return result
	if not Validator.validate(draft).is_valid():
		return {"ok": false, "reason": "invalid_command_result"}
	_busy = true
	var spent := str(result.get("spend_consumable", ""))
	# No await or observer may see only half the inventory/mission commit.
	var was_blocked: bool = gs.inventory.is_blocking_signals()
	gs.inventory.set_block_signals(true)
	if not spent.is_empty() and not gs.inventory.remove(spent, 1):
		gs.inventory.set_block_signals(was_blocked)
		_busy = false
		return {"ok": false, "reason": "missing_consumable"}
	mission.data = draft
	gs.inventory.set_block_signals(was_blocked)
	owner._mark_objective_ready_if_completed(mission)
	if not spent.is_empty() and not was_blocked:
		gs.inventory.item_changed.emit(spent, gs.inventory.get_quantity(spent))
	owner.quest_progress_updated.emit()
	_busy = false
	result.merge({"ok": true, "revision": draft["investigation"]["investigation_revision"], "phase": draft["investigation"]["phase"]}, true)
	return result
