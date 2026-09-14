extends RefCounted

## Acceptance checks saved positions; never rerolls already published evidence.
const Planner := preload("res://scripts/domain/InvestigationSitePlanner.gd")

static func capture(owner: Node) -> Dictionary:
	var gs := owner.get_node_or_null("/root/GlobalState")
	if gs == null or not is_instance_valid(gs.player) \
			or not gs.player.has_method("navigation_obstacle_snapshot"):
		return {"ok": false, "reason": "navigation_unavailable"}
	var stations: Array = []
	var gates: Array = []
	for node in owner.get_tree().get_nodes_in_group("station"):
		if not node is Node3D or node.is_queued_for_deletion():
			continue
		var ids: Array = [str(node.name), str(gs.resolve_outpost_id(node))]
		if node.has_method("get_world_id"):
			var world_id := str(node.get_world_id())
			if not world_id.is_empty():
				ids.push_front(world_id)
		stations.append({"id": ids[0], "ids": ids, "position": node.global_position})
	for node in owner.get_tree().get_nodes_in_group("jumpgate"):
		if node is Node3D and not node.is_queued_for_deletion():
			gates.append({"position": node.global_position})
	return {"ok": true, "system_id": str(gs.current_system_id), "stations": stations,
		"gates": gates, "hazards": gs.player.navigation_obstacle_snapshot()}

static func check_saved_sites(data: Dictionary, snapshot: Dictionary) -> Dictionary:
	if not bool(snapshot.get("ok", false)):
		return {"ok": false, "reason": "navigation_unavailable"}
	if str(data.get("system_id", "")) != str(snapshot.get("system_id", "")):
		return {"ok": false, "reason": "wrong_system"}
	var stations: Array = snapshot.get("stations", [])
	var station_found := false
	for station: Dictionary in stations:
		if str(data.get("turn_in_station_id", "")) in station.get("ids", [station.get("id", "")]):
			station_found = true
	if not station_found:
		return {"ok": false, "reason": "turn_in_station_unavailable"}
	var sites: Array = data.get("investigation", {}).get("sites", [])
	if sites.size() != 2:
		return {"ok": false, "reason": "invalid_sites"}
	for site: Dictionary in sites:
		var p: Array = site.get("position", [])
		if p.size() != 3:
			return {"ok": false, "reason": "invalid_position"}
		var position := Vector3(p[0], p[1], p[2])
		if not position.is_finite() or not Planner.is_position_safe(position,
				snapshot.get("hazards", []), stations, snapshot.get("gates", [])):
			return {"ok": false, "reason": "site_obstructed"}
	return {"ok": true}
