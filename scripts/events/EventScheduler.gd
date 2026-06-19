extends RefCounted

signal event_triggered(event_type_id: String, details: Dictionary)

const EventHistoryScript = preload("res://scripts/events/EventHistory.gd")
const EventTypeScript = preload("res://scripts/events/EventType.gd")

const GLOBAL_COOLDOWN_MINUTES := 30
const DEFAULT_TYPE_COOLDOWN_MINUTES := 90

var history = EventHistoryScript.new()
var _event_types: Array = []
var _type_cooldowns: Dictionary = {}
var _just_arrived: bool = false

static var _shared = null


static func shared():
	if _shared == null:
		_shared = new()
	return _shared


static func reset() -> void:
	_shared = null


func register_event_type(event_type, cooldown_minutes: int = DEFAULT_TYPE_COOLDOWN_MINUTES) -> void:
	_event_types.append(event_type)
	_type_cooldowns[event_type.event_type_id()] = cooldown_minutes


func set_just_arrived(value: bool) -> void:
	_just_arrived = value


func tick(campaign_time: int, context) -> void:
	if history.count_since(campaign_time - GLOBAL_COOLDOWN_MINUTES) > 0:
		return
	context.just_arrived = _just_arrived
	context.event_history = history.get_entries()
	var candidates = _evaluate_eligible(context, campaign_time)
	if candidates.is_empty():
		return
	var selected = _select(candidates, campaign_time, context.current_system_id)
	if selected == null:
		return
	var details = selected.execute(context)
	if not bool(details.get("applied", true)):
		return
	history.record(selected.event_type_id(), campaign_time, details)
	event_triggered.emit(selected.event_type_id(), details)
	_just_arrived = false


func _evaluate_eligible(context, campaign_time: int) -> Array:
	var result: Array = []
	for event_type in _event_types:
		var type_id: String = event_type.event_type_id()
		var cooldown: int = _type_cooldowns.get(type_id, DEFAULT_TYPE_COOLDOWN_MINUTES)
		if history.minutes_since(type_id, campaign_time) < cooldown:
			continue
		if event_type.is_eligible(context):
			result.append(event_type)
	return result


func _select(candidates: Array, campaign_time: int, system_id: String):
	if candidates.is_empty():
		return null
	var seed_val: int = campaign_time * 31 + system_id.hash()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var total_weight := 0.0
	var weights: Array[float] = []
	for c in candidates:
		var w: float = maxf(0.01, c.priority(null))
		weights.append(w)
		total_weight += w
	var roll: float = rng.randf() * total_weight
	var acc := 0.0
	for i in range(candidates.size()):
		acc += weights[i]
		if roll <= acc:
			return candidates[i]
	return candidates[candidates.size() - 1]


func save_state() -> Dictionary:
	return {
		"history": history.to_dict(),
		"just_arrived": _just_arrived,
	}


func restore_state(data: Dictionary) -> void:
	history = EventHistoryScript.from_dict(data.get("history", {}))
	_just_arrived = bool(data.get("just_arrived", false))
