class_name NovaLineBankCategories
extends RefCounted

# Phase 8B registry of N.O.V.A. line-bank categories: the semantic movement
# events from ShipBehaviorObserver plus her existing combat/hull/welcome/
# gate/arrival beats. Bank generation and consumption key on these ids so
# movement reactions can only ever draw prepared lines (never a live model
# call — see the movement-path tripwire test).

# Movement categories mirror ShipBehaviorObserver's semantic event ids.
const BOOST_AGAIN_QUICKLY := "boost_again_quickly"
const CHANGED_MIND_AGAIN := "changed_mind_again"
const RETURNED_TO_SAME_STATION := "returned_to_same_station"
const CLEAN_LONG_TRANSIT := "clean_long_transit"
const ROUGH_ARRIVAL := "rough_arrival"

# Existing N.O.V.A. beats (scripts/ai/Nova.gd).
const SYSTEM_ARRIVAL := "system_arrival"
const GATE_TRANSIT := "gate_transit"
const GATE_GLITCH := "gate_glitch"
const HULL_CRITICAL := "hull_critical"
const WELCOME_BACK := "welcome_back"
const DOCKED := "docked"
const COMBAT_VICTORY_CLEAN := "combat_victory_clean"
const COMBAT_VICTORY_BATTERED := "combat_victory_battered"
const COMBAT_RETREAT := "combat_retreat"

const ALL: Array[String] = [
	BOOST_AGAIN_QUICKLY,
	CHANGED_MIND_AGAIN,
	RETURNED_TO_SAME_STATION,
	CLEAN_LONG_TRANSIT,
	ROUGH_ARRIVAL,
	SYSTEM_ARRIVAL,
	GATE_TRANSIT,
	GATE_GLITCH,
	HULL_CRITICAL,
	WELCOME_BACK,
	DOCKED,
	COMBAT_VICTORY_CLEAN,
	COMBAT_VICTORY_BATTERED,
	COMBAT_RETREAT,
]

const MOVEMENT_CATEGORIES: Array[String] = [
	BOOST_AGAIN_QUICKLY,
	CHANGED_MIND_AGAIN,
	RETURNED_TO_SAME_STATION,
	CLEAN_LONG_TRANSIT,
	ROUGH_ARRIVAL,
]

# Protected special banks: only StoryManager's large-model path may write
# these (campaign gate-glitch shadows of the director-only memory flicker).
# Normal chapter/system bank generation must never produce them.
const PROTECTED_CATEGORIES: Array[String] = [
	GATE_GLITCH,
]

# Bank "kind" strings accepted when consuming a category. SYSTEM_ARRIVAL
# keeps the legacy "startup_navigation" kind so banks cached before this
# registry existed stay consumable.
const _LEGACY_KINDS: Dictionary = {
	SYSTEM_ARRIVAL: ["startup_navigation"],
}


static func all() -> Array[String]:
	return ALL.duplicate()


static func movement_categories() -> Array[String]:
	return MOVEMENT_CATEGORIES.duplicate()


static func is_valid(category: String) -> bool:
	return category.strip_edges() in ALL


static func is_movement(category: String) -> bool:
	return category.strip_edges() in MOVEMENT_CATEGORIES


static func is_protected(category: String) -> bool:
	return category.strip_edges() in PROTECTED_CATEGORIES


# Every kind string a consumer should accept for `category`, canonical first.
static func accepted_kinds(category: String) -> Array[String]:
	var clean := category.strip_edges()
	if not is_valid(clean):
		return []
	var kinds: Array[String] = [clean]
	for legacy in _LEGACY_KINDS.get(clean, []):
		kinds.append(str(legacy))
	return kinds


# The bank category for a ShipBehaviorObserver semantic event id, or "" if
# the event has no bank (unknown events stay silent by design).
static func for_semantic_event(event_id: String) -> String:
	var clean := event_id.strip_edges()
	return clean if clean in MOVEMENT_CATEGORIES else ""
