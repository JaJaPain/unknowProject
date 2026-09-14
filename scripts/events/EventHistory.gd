extends RefCounted

const MAX_ENTRIES := 50

var _entries: Array[Dictionary] = []


func record(event_type_id: String, campaign_time: int, details: Dictionary = {}) -> void:
	_entries.append({
		"type": event_type_id,
		"time": campaign_time,
		"details": details,
	})
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()


func last_time_for_type(event_type_id: String) -> int:
	for i in range(_entries.size() - 1, -1, -1):
		if _entries[i].get("type", "") == event_type_id:
			return int(_entries[i].get("time", 0))
	return -1


func minutes_since(event_type_id: String, current_time: int) -> int:
	var last = last_time_for_type(event_type_id)
	if last < 0:
		return 999999
	return current_time - last


func count_since(start_time: int) -> int:
	var count := 0
	for entry in _entries:
		if int(entry.get("time", 0)) >= start_time:
			count += 1
	return count


func get_entries() -> Array[Dictionary]:
	return _entries.duplicate()


func to_dict() -> Dictionary:
	return {"entries": _entries.duplicate(true)}


static func from_dict(data: Dictionary):
	var h = new()
	for entry in data.get("entries", []):
		h._entries.append(entry)
	return h
