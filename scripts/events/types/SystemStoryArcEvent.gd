extends RefCounted

const MIN_SYSTEM_TIME_MINUTES := 60
const MAX_ARC_EVENTS := 8


func event_type_id() -> String:
	return "system_story_arc"


func is_eligible(context) -> bool:
	if context == null or context.just_arrived:
		return false
	if int(context.campaign_time) < MIN_SYSTEM_TIME_MINUTES:
		return false
	var config := _current_system_config(context)
	return config != null and not config.story_pack.is_empty()


func priority(_context) -> float:
	return 0.45


func execute(context) -> Dictionary:
	var config := _current_system_config(context)
	if config == null or config.story_pack.is_empty():
		return {"event": event_type_id(), "applied": false}
	var pack: Dictionary = config.story_pack.duplicate(true)
	var pressure := int(pack.get("arc_pressure", 0)) + 1
	pack["arc_pressure"] = pressure
	pack["last_arc_update_minutes"] = int(context.campaign_time)
	var note := _arc_note(pack, pressure)
	var events: Array = pack.get("arc_events", [])
	events.append({
		"time_minutes": int(context.campaign_time),
		"pressure": pressure,
		"note": note,
	})
	while events.size() > MAX_ARC_EVENTS:
		events.remove_at(0)
	pack["arc_events"] = events
	config.story_pack = pack
	var global_state := _global_state()
	if global_state != null and global_state.has_method("emit_chatter"):
		global_state.emit_chatter("SYSTEM", note, Color(0.7, 0.85, 0.95))
	return {
		"event": event_type_id(),
		"system": str(context.current_system_id),
		"pressure": pressure,
		"note": note,
	}


func _current_system_config(context):
	var registry = null
	if context != null and "system_registry" in context:
		registry = context.system_registry
	if registry == null:
		registry = _scene_system_registry()
	if registry == null or not registry.has_method("get_generated_config"):
		return null
	var config = registry.get_generated_config(str(context.current_system_id))
	if config != null:
		return config
	if registry.has_method("resolve_system_id"):
		config = registry.get_generated_config(str(registry.resolve_system_id(context.current_system_id)))
		if config != null:
			return config
	if registry.has_method("runtime_system_id"):
		var runtime_id := str(registry.runtime_system_id(context.current_system_id))
		if not runtime_id.is_empty():
			config = registry.get_generated_config(runtime_id)
	return config


func _scene_system_registry():
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	if tree.current_scene and "system_registry" in tree.current_scene:
		return tree.current_scene.system_registry
	for child in tree.root.get_children():
		if child and "system_registry" in child:
			return child.system_registry
	return null


func _global_state():
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("GlobalState")


func _arc_note(pack: Dictionary, pressure: int) -> String:
	var tension := str(pack.get("active_tension", "")).strip_edges()
	var problem := str(pack.get("station_economy_problem", "")).strip_edges()
	var danger := str(pack.get("danger_summary", "")).strip_edges()
	var nickname := str(pack.get("local_nickname", "")).strip_edges()
	var subject := tension
	if subject.is_empty():
		subject = problem
	if subject.is_empty():
		subject = danger
	if subject.is_empty():
		subject = "local pressure is building"
	var place_clause := ""
	if not nickname.is_empty():
		place_clause = " in %s" % nickname
	var severity := "is getting harder to ignore"
	if pressure >= 4:
		severity = "is starting to cost people money"
	if pressure >= 7:
		severity = "is close to boiling over"
	return "Local chatter%s says %s %s." % [place_clause, subject, severity]
