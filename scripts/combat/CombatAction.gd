extends RefCounted
class_name CombatAction

enum Type {
	FIRE,
	BOOST,
	SHIELD_REROUTE,
	ATTACK_DRONE,
	MICRO_WARP,
	REPAIR_KIT,
	FLEE,
}

const AP_COST := {
	Type.FIRE:          2,
	Type.BOOST:         1,
	Type.SHIELD_REROUTE: 1,
	Type.ATTACK_DRONE:  2,
	Type.MICRO_WARP:    3,
	Type.REPAIR_KIT:    2,
	Type.FLEE:          3,
}

const LABEL := {
	Type.FIRE:           "Fire Weapons",
	Type.BOOST:          "Boost / Reposition",
	Type.SHIELD_REROUTE: "Shield Reroute",
	Type.ATTACK_DRONE:   "Attack Drone",
	Type.MICRO_WARP:     "Micro-Warp",
	Type.REPAIR_KIT:     "Repair Kit",
	Type.FLEE:           "Flee",
}

static func make(type: Type, params: Dictionary = {}) -> Dictionary:
	return {
		"type":   type,
		"ap":     AP_COST[type],
		"label":  LABEL[type],
		"params": params,
	}

# Shield face constants used by SHIELD_REROUTE and hit resolution.
enum Face { FRONT, REAR, PORT, STARBOARD }

const FACE_LABEL := {
	Face.FRONT:     "Front",
	Face.REAR:      "Rear",
	Face.PORT:      "Port",
	Face.STARBOARD: "Starboard",
}

# Range band constants used by BOOST and hit resolution.
enum RangeBand { LONG, MID, CLOSE }

const RANGE_DAMAGE_MULT := {
	RangeBand.LONG:  0.6,
	RangeBand.MID:   1.0,
	RangeBand.CLOSE: 1.3,
}
