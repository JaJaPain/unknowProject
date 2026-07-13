extends SceneTree

# Phase 8B slice 1: the N.O.V.A. line-bank category registry covers the
# semantic movement events plus her existing beats, marks the campaign
# gate-glitch bank as protected, and keeps the legacy startup_navigation
# kind consumable for system arrivals.

const CategoriesType := preload(
	"res://scripts/story/NovaLineBankCategories.gd"
)
const ObserverType := preload("res://scripts/story/ShipBehaviorObserver.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_registry_contents()
	_test_movement_categories_mirror_observer_semantics()
	_test_protected_and_legacy_kinds()

	if _failures.is_empty():
		print("[PASS] Nova line bank category tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_registry_contents() -> void:
	var expected: Array[String] = [
		"boost_again_quickly",
		"changed_mind_again",
		"returned_to_same_station",
		"clean_long_transit",
		"rough_arrival",
		"system_arrival",
		"gate_transit",
		"gate_glitch",
		"hull_critical",
		"welcome_back",
		"docked",
		"combat_victory_clean",
		"combat_victory_battered",
		"combat_retreat",
	]
	_expect(
		CategoriesType.all() == expected,
		"Nova line-bank categories do not match the Phase 8B contract."
	)
	for category in expected:
		_expect(
			CategoriesType.is_valid(category),
			"Registered category was not valid: %s" % category
		)
	_expect(
		not CategoriesType.is_valid("director_memory_flicker"),
		"Unknown category was accepted."
	)


func _test_movement_categories_mirror_observer_semantics() -> void:
	var semantic: Array[String] = ObserverType.all_semantic()
	_expect(
		CategoriesType.movement_categories() == semantic,
		"Movement categories do not mirror ShipBehaviorObserver semantics."
	)
	for event_id in semantic:
		_expect(
			CategoriesType.for_semantic_event(event_id) == event_id
				and CategoriesType.is_movement(event_id),
			"Semantic event has no matching movement category: %s" % event_id
		)
	_expect(
		CategoriesType.for_semantic_event("docked").is_empty()
			and CategoriesType.for_semantic_event("player_sneezed").is_empty(),
		"Non-movement events should map to no bank (silence)."
	)


func _test_protected_and_legacy_kinds() -> void:
	_expect(
		CategoriesType.is_protected(CategoriesType.GATE_GLITCH),
		"Campaign gate-glitch bank is not protected."
	)
	for category in CategoriesType.all():
		if category == CategoriesType.GATE_GLITCH:
			continue
		_expect(
			not CategoriesType.is_protected(category),
			"Unexpected protected category: %s" % category
		)
	var arrival_kinds := CategoriesType.accepted_kinds(
		CategoriesType.SYSTEM_ARRIVAL
	)
	_expect(
		arrival_kinds == ["system_arrival", "startup_navigation"],
		"System arrival lost its legacy startup_navigation kind: %s"
			% str(arrival_kinds)
	)
	_expect(
		CategoriesType.accepted_kinds(CategoriesType.GATE_TRANSIT)
			== ["gate_transit"],
		"Plain category should accept exactly its own kind."
	)
	_expect(
		CategoriesType.accepted_kinds("unknown").is_empty(),
		"Unknown category should accept no kinds."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
