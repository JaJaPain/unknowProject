extends RefCounted

func event_type_id() -> String:
	return ""


func is_eligible(_context) -> bool:
	return false


func priority(_context) -> float:
	return 1.0


func execute(_context) -> Dictionary:
	return {}
