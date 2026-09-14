class_name ShipMovementEvents
extends RefCounted

# Phase 8A registry of raw semantic movement events. Emitters (PlayerShip,
# GameRoot dock/gate flow) publish these through
# GlobalState.emit_ship_movement_event; ShipBehaviorObserver aggregates and
# rate-limits them before anything reaches N.O.V.A. No narrative code may
# poll ship state per frame — it must consume these events.

const BOOST_ACTIVATED := "boost_activated"
const BOOST_REJECTED := "boost_rejected"
const AUTOPILOT_STARTED := "autopilot_started"
const AUTOPILOT_RETARGETED := "autopilot_retargeted"
const AUTOPILOT_CANCELLED := "autopilot_cancelled"
const EVASIVE_MANEUVER := "evasive_maneuver"
const GATE_DEPARTURE := "gate_departure"
const SYSTEM_ARRIVAL := "system_arrival"
const DOCKED := "docked"
const UNDOCKED := "undocked"
const ROUTE_REPLANNED := "route_replanned"
const SEVERE_HULL_IMPACT := "severe_hull_impact"

const ALL: Array[String] = [
	BOOST_ACTIVATED,
	BOOST_REJECTED,
	AUTOPILOT_STARTED,
	AUTOPILOT_RETARGETED,
	AUTOPILOT_CANCELLED,
	EVASIVE_MANEUVER,
	GATE_DEPARTURE,
	SYSTEM_ARRIVAL,
	DOCKED,
	UNDOCKED,
	ROUTE_REPLANNED,
	SEVERE_HULL_IMPACT,
]


static func all() -> Array[String]:
	return ALL.duplicate()


static func is_valid(event_id: String) -> bool:
	return event_id.strip_edges() in ALL
