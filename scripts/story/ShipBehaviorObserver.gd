class_name ShipBehaviorObserver
extends Node

# Phase 8A aggregation layer. Consumes raw GlobalState.ship_movement_event
# entries and folds repeated low-level actions into the semantic events
# N.O.V.A. actually cares about. The observer reports state; whether speech
# is worth it stays N.O.V.A.'s decision. No model calls happen here or
# downstream of movement — semantic events may only consume prepared lines.
#
# Time is injected through observe() so aggregation is deterministic in
# headless tests; the live signal handler stamps wall-clock seconds.

signal semantic_movement_event(event_id: String, context: Dictionary)

const ShipMovementEventsType := preload(
	"res://scripts/story/ShipMovementEvents.gd"
)

# Boost cooldown is 60s, so re-boosting inside this window means the player
# slammed boost again almost as soon as it came back.
const BOOST_QUICK_WINDOW_SECONDS := 90.0
# This many retarget/cancel events inside the window reads as indecision.
const CHURN_WINDOW_SECONDS := 60.0
const CHURN_EVENT_THRESHOLD := 3
# Re-docking at the station left this recently reads as "back already?".
const RETURN_WINDOW_SECONDS := 600.0
# A gate transit must last at least this long to earn a clean-transit nod.
const CLEAN_TRANSIT_MIN_SECONDS := 20.0
# Trouble this close to an arrival colors the arrival as rough.
const ROUGH_ARRIVAL_WINDOW_SECONDS := 45.0
# Rate limits: minimum spacing between any two semantic emissions, and a
# longer per-event cooldown so the same observation cannot nag. Suppressed
# events still update state; N.O.V.A. can read state_snapshot() any time.
const SEMANTIC_GLOBAL_SPACING_SECONDS := 30.0
const SEMANTIC_EVENT_COOLDOWN_SECONDS := 180.0

const SEMANTIC_BOOST_AGAIN_QUICKLY := "boost_again_quickly"
const SEMANTIC_CHANGED_MIND_AGAIN := "changed_mind_again"
const SEMANTIC_RETURNED_TO_SAME_STATION := "returned_to_same_station"
const SEMANTIC_CLEAN_LONG_TRANSIT := "clean_long_transit"
const SEMANTIC_ROUGH_ARRIVAL := "rough_arrival"

const ALL_SEMANTIC: Array[String] = [
	SEMANTIC_BOOST_AGAIN_QUICKLY,
	SEMANTIC_CHANGED_MIND_AGAIN,
	SEMANTIC_RETURNED_TO_SAME_STATION,
	SEMANTIC_CLEAN_LONG_TRANSIT,
	SEMANTIC_ROUGH_ARRIVAL,
]

var _last_boost_time := -INF
var _churn_times: Array[float] = []
var _pending_dock_target := ""
var _last_dock_station := ""
var _last_undock_time := -INF
var _departure_time := -INF
var _rough_since_departure := false
var _last_rough_time := -INF
var _last_semantic_emit_time := -INF
var _last_emit_time_by_event: Dictionary = {}
var _suppressed_counts: Dictionary = {}

# How many raw event ids the recent-action streak keeps.
const RECENT_EVENT_LIMIT := 6

# Host-supplied safe context (hull band, mission beat, new/returning system,
# route deviation). Returns a Dictionary; merged into every semantic event
# without overwriting event-specific fields. Injectable so tests stay
# deterministic and the observer never hard-depends on live game state.
var context_provider: Callable = Callable()

var _recent_events: Array[String] = []


static func all_semantic() -> Array[String]:
	return ALL_SEMANTIC.duplicate()


# Safe aggregation state for N.O.V.A. to consult when deciding whether a
# line is worth it. Reporting state is the observer's job; speaking is not.
func state_snapshot() -> Dictionary:
	return {
		"last_boost_time": _last_boost_time,
		"churn_events_in_window": _churn_times.size(),
		"last_dock_station": _last_dock_station,
		"in_transit": _departure_time != -INF,
		"rough_since_departure": _rough_since_departure,
		"last_semantic_emit_time": _last_semantic_emit_time,
		"suppressed_counts": _suppressed_counts.duplicate(true),
		"recent_actions": _recent_events.duplicate(),
	}


func _emit_semantic(
	event_id: String,
	context: Dictionary,
	now_seconds: float
) -> bool:
	var last_for_event: float = _last_emit_time_by_event.get(event_id, -INF)
	if now_seconds - _last_semantic_emit_time \
			< SEMANTIC_GLOBAL_SPACING_SECONDS \
			or now_seconds - last_for_event < SEMANTIC_EVENT_COOLDOWN_SECONDS:
		_suppressed_counts[event_id] = int(
			_suppressed_counts.get(event_id, 0)
		) + 1
		return false
	_last_semantic_emit_time = now_seconds
	_last_emit_time_by_event[event_id] = now_seconds
	var enriched := context.duplicate(true)
	enriched["recent_actions"] = _recent_events.duplicate()
	if context_provider.is_valid():
		var extra: Variant = context_provider.call()
		if extra is Dictionary:
			enriched.merge(extra, false)
	semantic_movement_event.emit(event_id, enriched)
	return true


func _on_ship_movement_event(event_id: String, context: Dictionary) -> void:
	observe(event_id, context, float(Time.get_ticks_msec()) / 1000.0)


func observe(event_id: String, context: Dictionary, now_seconds: float) -> void:
	_recent_events.append(event_id)
	while _recent_events.size() > RECENT_EVENT_LIMIT:
		_recent_events.pop_front()
	match event_id:
		ShipMovementEventsType.BOOST_ACTIVATED:
			_observe_boost(now_seconds)
		ShipMovementEventsType.AUTOPILOT_STARTED:
			_note_dock_target(context)
		ShipMovementEventsType.AUTOPILOT_RETARGETED:
			_note_dock_target(context)
			_observe_churn(now_seconds)
		ShipMovementEventsType.AUTOPILOT_CANCELLED:
			_observe_churn(now_seconds)
		ShipMovementEventsType.DOCKED:
			_observe_dock(now_seconds)
		ShipMovementEventsType.UNDOCKED:
			_last_undock_time = now_seconds
		ShipMovementEventsType.GATE_DEPARTURE:
			_departure_time = now_seconds
			_rough_since_departure = false
		ShipMovementEventsType.SEVERE_HULL_IMPACT, \
		ShipMovementEventsType.EVASIVE_MANEUVER, \
		ShipMovementEventsType.ROUTE_REPLANNED:
			_rough_since_departure = true
			_last_rough_time = now_seconds
		ShipMovementEventsType.SYSTEM_ARRIVAL:
			_observe_arrival(context, now_seconds)


func _observe_boost(now_seconds: float) -> void:
	var since_last := now_seconds - _last_boost_time
	_last_boost_time = now_seconds
	if since_last <= BOOST_QUICK_WINDOW_SECONDS:
		_emit_semantic(
			SEMANTIC_BOOST_AGAIN_QUICKLY,
			{"seconds_since_last_boost": since_last},
			now_seconds
		)


func _observe_churn(now_seconds: float) -> void:
	_churn_times.append(now_seconds)
	var kept: Array[float] = []
	for t in _churn_times:
		if now_seconds - t <= CHURN_WINDOW_SECONDS:
			kept.append(t)
	_churn_times = kept
	if _churn_times.size() >= CHURN_EVENT_THRESHOLD:
		_emit_semantic(
			SEMANTIC_CHANGED_MIND_AGAIN,
			{"changes_in_window": _churn_times.size()},
			now_seconds
		)
		_churn_times.clear()


func _note_dock_target(context: Dictionary) -> void:
	if str(context.get("mode", "")) == "DOCK":
		_pending_dock_target = str(context.get("target_name", ""))


func _observe_dock(now_seconds: float) -> void:
	var station := _pending_dock_target
	_pending_dock_target = ""
	if station.is_empty():
		return
	if station == _last_dock_station \
			and now_seconds - _last_undock_time <= RETURN_WINDOW_SECONDS:
		_emit_semantic(
			SEMANTIC_RETURNED_TO_SAME_STATION,
			{"station_name": station},
			now_seconds
		)
	_last_dock_station = station


func _observe_arrival(context: Dictionary, now_seconds: float) -> void:
	if _departure_time == -INF:
		return
	var transit_seconds := now_seconds - _departure_time
	_departure_time = -INF
	var arrival_context := {
		"system_id": str(context.get("system_id", "")),
		"transit_seconds": transit_seconds,
	}
	if _rough_since_departure \
			or now_seconds - _last_rough_time <= ROUGH_ARRIVAL_WINDOW_SECONDS:
		_emit_semantic(
			SEMANTIC_ROUGH_ARRIVAL,
			arrival_context,
			now_seconds
		)
	elif transit_seconds >= CLEAN_TRANSIT_MIN_SECONDS:
		_emit_semantic(
			SEMANTIC_CLEAN_LONG_TRANSIT,
			arrival_context,
			now_seconds
		)
	_rough_since_departure = false
