class_name MissionCapability
extends RefCounted


func capability_id() -> String:
	return ""


func supported_objective_types() -> Array[String]:
	return []


func is_completed(data: Dictionary) -> bool:
	return false


func handle_event(data: Dictionary, event: String, event_data: Dictionary) -> Dictionary:
	return {}


func format_tracker_text(data: Dictionary) -> String:
	return ""


func on_complete(data: Dictionary) -> Dictionary:
	return {}


func on_cleanup(data: Dictionary) -> Dictionary:
	return {}
