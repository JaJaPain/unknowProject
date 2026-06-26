extends RefCounted
class_name CombatAction

enum Type {
	# ── Player actions ────────────────────────────────────────────────────────
	FIRE,
	BOOST,
	SHIELD_REROUTE,
	ATTACK_DRONE,
	MICRO_WARP,
	REPAIR_KIT,
	FLEE,
	# ── NPC / shared actions ──────────────────────────────────────────────────
	BRACE,           # absorbs 40% of next incoming hit; half effect when flanked
	FLANK,           # close to CLOSE range + attack, bypasses shield angle
	SHIELD_ANGLE,    # redirects shields to one face; consumed on hit
	DISABLE_ENGINES, # subsystem attack — reduces target AP next turn
}

const AP_COST := {
	Type.FIRE:            2,
	Type.BOOST:           1,
	Type.SHIELD_REROUTE:  1,
	Type.ATTACK_DRONE:    2,
	Type.MICRO_WARP:      3,
	Type.REPAIR_KIT:      2,
	Type.FLEE:            3,
	Type.BRACE:           2,
	Type.FLANK:           3,
	Type.SHIELD_ANGLE:    1,
	Type.DISABLE_ENGINES: 2,
}

const LABEL := {
	Type.FIRE:            "Fire Weapons",
	Type.BOOST:           "Boost / Reposition",
	Type.SHIELD_REROUTE:  "Shield Reroute",
	Type.ATTACK_DRONE:    "Attack Drone",
	Type.MICRO_WARP:      "Micro-Warp",
	Type.REPAIR_KIT:      "Repair Kit",
	Type.FLEE:            "Flee",
	Type.BRACE:           "Brace",
	Type.FLANK:           "Flanking Run",
	Type.SHIELD_ANGLE:    "Shield Angle",
	Type.DISABLE_ENGINES: "Disable Engines",
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
