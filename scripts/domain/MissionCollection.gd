class_name MissionCollection
extends RefCounted

const MissionInstanceType := preload("res://scripts/domain/MissionInstance.gd")

var _missions: Array = []
var _focused_runtime_id: String = ""


func add(instance) -> bool:
	if instance == null:
		return false
	if is_lane_occupied(instance.source_lane):
		return false
	_missions.append(instance)
	if _focused_runtime_id.is_empty():
		_focused_runtime_id = instance.runtime_id
	return true


func remove(runtime_id: String) -> bool:
	for i in range(_missions.size()):
		if _missions[i].runtime_id == runtime_id:
			_missions.remove_at(i)
			if _focused_runtime_id == runtime_id:
				_focused_runtime_id = _missions[0].runtime_id if not _missions.is_empty() else ""
			return true
	return false


func get_by_id(runtime_id: String):
	for m in _missions:
		if m.runtime_id == runtime_id:
			return m
	return null


func get_by_lane(lane: MissionInstanceType.SourceLane):
	for m in _missions:
		if m.source_lane == lane:
			return m
	return null


func is_lane_occupied(lane: MissionInstanceType.SourceLane) -> bool:
	return get_by_lane(lane) != null


func get_focused():
	if _focused_runtime_id.is_empty() and not _missions.is_empty():
		return _missions[0]
	if _focused_runtime_id.is_empty():
		return null
	var found = get_by_id(_focused_runtime_id)
	if found == null and not _missions.is_empty():
		return _missions[0]
	return found


func focus(runtime_id: String) -> bool:
	if get_by_id(runtime_id) == null:
		return false
	_focused_runtime_id = runtime_id
	return true


func get_all_active() -> Array:
	var result: Array = []
	for m in _missions:
		if not m.is_terminal():
			result.append(m)
	return result


func size() -> int:
	return _missions.size()


func is_empty() -> bool:
	return _missions.is_empty()


func has_any_active() -> bool:
	for m in _missions:
		if not m.is_terminal():
			return true
	return false


func clear() -> void:
	_missions.clear()
	_focused_runtime_id = ""


func to_array() -> Array:
	var result: Array = []
	for m in _missions:
		var d: Dictionary = m.to_dict()
		if m.runtime_id == _focused_runtime_id:
			d["_focused"] = true
		result.append(d)
	return result


static func from_array(source: Array) -> MissionCollection:
	var collection := MissionCollection.new()
	for item in source:
		if item is Dictionary:
			var inst = MissionInstanceType.from_dict(item)
			collection._missions.append(inst)
			if bool(item.get("_focused", false)):
				collection._focused_runtime_id = inst.runtime_id
	if collection._focused_runtime_id.is_empty() and not collection._missions.is_empty():
		collection._focused_runtime_id = collection._missions[0].runtime_id
	return collection
