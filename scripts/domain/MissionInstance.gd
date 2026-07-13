class_name MissionInstance
extends RefCounted

const StateType := preload("res://scripts/domain/MissionState.gd")

enum State {
	OFFERED,
	ACCEPTED,
	ACTIVE,
	READY_TO_TURN_IN,
	COMPLETED,
	FAILED,
	EXPIRED,
	ABANDONED,
	RESOLVED_BY_BRANCH,
}

enum SourceLane { AGENT, BOARD, STATION }

const _STATE_NAMES: Dictionary = {
	State.OFFERED: "OFFERED",
	State.ACCEPTED: "ACCEPTED",
	State.ACTIVE: "ACTIVE",
	State.READY_TO_TURN_IN: "READY_TO_TURN_IN",
	State.COMPLETED: "COMPLETED",
	State.FAILED: "FAILED",
	State.EXPIRED: "EXPIRED",
	State.ABANDONED: "ABANDONED",
	State.RESOLVED_BY_BRANCH: "RESOLVED_BY_BRANCH",
}

const _STATE_BY_NAME: Dictionary = {
	"OFFERED": State.OFFERED,
	"ACCEPTED": State.ACCEPTED,
	"ACTIVE": State.ACTIVE,
	"READY_TO_TURN_IN": State.READY_TO_TURN_IN,
	"COMPLETED": State.COMPLETED,
	"FAILED": State.FAILED,
	"EXPIRED": State.EXPIRED,
	"ABANDONED": State.ABANDONED,
	"RESOLVED_BY_BRANCH": State.RESOLVED_BY_BRANCH,
}

const VALID_TRANSITIONS: Dictionary = {
	State.OFFERED: [State.ACCEPTED, State.ABANDONED],
	State.ACCEPTED: [State.ACTIVE, State.ABANDONED],
	State.ACTIVE: [
		State.READY_TO_TURN_IN,
		State.FAILED,
		State.EXPIRED,
		State.ABANDONED,
		State.RESOLVED_BY_BRANCH,
	],
	State.READY_TO_TURN_IN: [
		State.COMPLETED,
		State.ABANDONED,
		State.ACTIVE,
		# A timed contract can still expire while waiting for the hand-in.
		State.EXPIRED,
	],
	State.COMPLETED: [],
	State.FAILED: [],
	State.EXPIRED: [],
	State.ABANDONED: [],
	State.RESOLVED_BY_BRANCH: [],
}

const TERMINAL_STATES: Array[int] = [
	State.COMPLETED,
	State.FAILED,
	State.EXPIRED,
	State.ABANDONED,
	State.RESOLVED_BY_BRANCH,
]

var state: State = State.OFFERED
var source_lane: SourceLane = SourceLane.AGENT
var data: Dictionary = {}


var runtime_id: String:
	get: return str(data.get("runtime_id", ""))

var definition_id: String:
	get: return str(data.get("definition_id", ""))

var objective_type: String:
	get: return str(data.get("objective_type", ""))

var title: String:
	get: return str(data.get("title", ""))


func transition_to(new_state: State) -> bool:
	var allowed: Array = VALID_TRANSITIONS.get(state, [])
	if new_state not in allowed:
		push_warning(
			"[MissionInstance] Invalid transition: %s -> %s"
			% [state_name(), state_name_of(new_state)]
		)
		return false
	state = new_state
	return true


func is_terminal() -> bool:
	return state in TERMINAL_STATES


func state_name() -> String:
	return _STATE_NAMES.get(state, "UNKNOWN")


static func state_name_of(s: State) -> String:
	return _STATE_NAMES.get(s, "UNKNOWN")


static func state_from_name(name: String) -> State:
	return _STATE_BY_NAME.get(name, State.OFFERED)


const _LANE_NAMES: Dictionary = {
	SourceLane.AGENT: "AGENT",
	SourceLane.BOARD: "BOARD",
	SourceLane.STATION: "STATION",
}

const _LANE_BY_NAME: Dictionary = {
	"AGENT": SourceLane.AGENT,
	"BOARD": SourceLane.BOARD,
	"STATION": SourceLane.STATION,
}


func lane_name() -> String:
	return _LANE_NAMES.get(source_lane, "AGENT")


func to_dict() -> Dictionary:
	var result := data.duplicate(true)
	result["_instance_state"] = state_name()
	result["_source_lane"] = lane_name()
	return result


static func from_dict(source: Dictionary) -> MissionInstance:
	var instance := MissionInstance.new()
	instance.data = source.duplicate(true)
	var saved_state := str(source.get("_instance_state", ""))
	if saved_state in _STATE_BY_NAME:
		instance.state = _STATE_BY_NAME[saved_state]
	else:
		instance.state = State.ACTIVE
	instance.data.erase("_instance_state")
	instance.data.erase("_source_lane")
	instance.source_lane = _detect_lane(source)
	return instance


static func create_active(state_dict: Dictionary) -> MissionInstance:
	var instance := MissionInstance.new()
	instance.data = state_dict.duplicate(true)
	instance.state = State.ACTIVE
	instance.source_lane = _detect_lane(state_dict)
	return instance


func get_field(key: String, default: Variant = null) -> Variant:
	return data.get(key, default)


static func _detect_lane(source: Dictionary) -> SourceLane:
	var lane_str := str(source.get("_source_lane", ""))
	if lane_str in _LANE_BY_NAME:
		return _LANE_BY_NAME[lane_str]
	if bool(source.get("station_errand", false)):
		return SourceLane.STATION
	if bool(source.get("public_board", false)):
		return SourceLane.BOARD
	return SourceLane.AGENT
