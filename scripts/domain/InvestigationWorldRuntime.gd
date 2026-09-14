extends RefCounted

## Transient projection of saved missions. Only revealed, public markers become
## nodes. Mission truth stays in the mission; nodes never activate ordinary anomalies.
const Reveal := preload("res://scripts/domain/SiteRevealModel.gd")
const Validator := preload("res://scripts/domain/InvestigationStateValidator.gd")
var markers: Dictionary = {}

func reset(owner: Node) -> void:
	for key in markers.keys():
		_remove(owner, str(key))

func reconcile(owner: Node) -> bool:
	var wanted := {}
	var gs: Node = owner.get_node("/root/GlobalState")
	var scene := owner.get_tree().current_scene
	if scene != null and is_instance_valid(gs.player):
		for mission in owner.get_mission_collection().get_all_active():
			var data: Dictionary = mission.data
			if mission.is_terminal() or str(data.get("objective_type", "")) != "INVESTIGATE_SIGNAL" \
					or str(data.get("system_id", "")) != str(gs.current_system_id) or not Validator.validate(data).is_valid():
				continue
			var state: Dictionary = data["investigation"]
			if state["phase"] in ["ready", "closed"]:
				continue
			var scanned: Array = state["scanned_site_ids"]
			var primary_scanned := false
			for site: Dictionary in state["sites"]:
				if site["role"] == "primary" and site["id"] in scanned:
					primary_scanned = true
			if not primary_scanned and Validator._position(state.get("search_center", [])):
				wanted[_key(mission.runtime_id, "search")] = {"mission_id": mission.runtime_id, "site_id": "search",
					"label": "Investigation search area", "position": state["search_center"], "radius": float(state.get("search_radius", 1500.0))}
			for site: Dictionary in state["sites"]:
				var key := _key(mission.runtime_id, str(site["id"]))
				if site["role"] == "verification" and not primary_scanned:
					continue
				var position := _vector(site["position"])
				var tier: String = ["basic", "improved", "advanced"][clampi(int(gs.sensor_tier), 0, 2)]
				var known := markers.has(key) and is_instance_valid(markers[key])
				var distance: float = gs.player.global_position.distance_to(position)
				var range_limit := Reveal.drop_range_for_tier(tier, true, Reveal.SIZE_SMALL, "wreckage") if known else Reveal.detection_range(tier, true, Reveal.SIZE_SMALL, "wreckage")
				if site["role"] == "primary" and not primary_scanned and distance > range_limit:
					continue
				wanted[key] = {"mission_id": mission.runtime_id, "site_id": site["id"], "position": site["position"],
					"label": "Verification site" if site["role"] == "verification" else "Investigation signal", "radius": 0.0}
	var changed := false
	for key in markers.keys():
		var node: Variant = markers[key]
		if not wanted.has(key) or not is_instance_valid(node) or node.get_parent() != scene:
			_remove(owner, str(key))
			changed = true
	for key in wanted:
		var record: Dictionary = wanted[key]
		if not markers.has(key):
			var node := _create_marker(record)
			scene.add_child(node)
			markers[key] = node
			changed = true
		markers[key].global_position = _vector(record["position"])
	return changed

func target(mission_id: String, site_id: String) -> Node3D:
	var node: Variant = markers.get(_key(mission_id, site_id))
	return node if is_instance_valid(node) else null

func public_sites(mission_id: String) -> Array:
	var sites: Array = []
	for node: Variant in markers.values():
		if not is_instance_valid(node) or str(node.get_meta("mission_id")) != mission_id:
			continue
		sites.append({"site_id": str(node.get_meta("site_id")), "label": str(node.get_meta("label"))})
	return sites

func _remove(owner: Node, key: String) -> void:
	var node: Variant = markers.get(key)
	markers.erase(key)
	if not is_instance_valid(node): return
	var gs: Node = owner.get_node("/root/GlobalState")
	if gs.active_target == node: gs.active_target = null
	if is_instance_valid(gs.player) and "navigation_target" in gs.player and gs.player.navigation_target == node:
		if gs.player.has_method("hard_stop"): gs.player.hard_stop()
	node.free()

func _create_marker(record: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = str(record["label"])
	node.add_to_group("mission_investigation_marker")
	for field in ["mission_id", "site_id", "label"]: node.set_meta(field, record[field])
	var visual := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.15, 0.85, 0.95)
	if float(record["radius"]) > 0.0:
		var ring := ImmediateMesh.new()
		ring.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for i in range(97):
			var angle := TAU * i / 96.0
			ring.surface_add_vertex(Vector3(cos(angle), 0, sin(angle)) * float(record["radius"]))
		ring.surface_end()
		visual.mesh = ring
	else:
		var sphere := SphereMesh.new()
		sphere.radius = 9.0
		sphere.height = 18.0
		visual.mesh = sphere
	visual.material_override = material
	node.add_child(visual)
	return node

static func _vector(p: Array) -> Vector3:
	return Vector3(float(p[0]), float(p[1]), float(p[2]))

static func _key(mission_id: String, site_id: String) -> String:
	return mission_id + ":" + site_id
