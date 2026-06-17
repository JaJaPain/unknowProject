extends SceneTree

const PlannerType := preload(
	"res://scripts/navigation/NavigationRoutePlanner.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	_test_direct_route()
	_test_blocked_route()
	_test_three_dimensional_route()
	if failures.is_empty():
		print("[PASS] Navigation preflight route planner tests")
		quit(0)
		return
	for failure in failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_direct_route() -> void:
	var planned := PlannerType.plan_route(
		Vector3.ZERO,
		Vector3(500, 0, 0),
		[]
	)
	_expect(
		bool(planned.get("ok", false))
			and planned.get("waypoints", []).size() == 1,
		"A clear route did not remain direct."
	)


func _test_blocked_route() -> void:
	var hazards := [{
		"id": "planet",
		"center": Vector3(250, 0, 0),
		"radius": 120.0,
	}]
	var planned := PlannerType.plan_route(
		Vector3.ZERO,
		Vector3(500, 0, 0),
		hazards
	)
	_expect(
		bool(planned.get("ok", false))
			and planned.get("waypoints", []).size() > 1,
		"A blocked route did not receive a preflight detour."
	)
	_expect(
		PlannerType.route_is_clear(
			Vector3.ZERO,
			planned.get("waypoints", []),
			hazards
		),
		"The planned detour crosses its exclusion sphere."
	)


func _test_three_dimensional_route() -> void:
	var hazards := [
		{
			"id": "planet_a",
			"center": Vector3(200, 0, 0),
			"radius": 105.0,
		},
		{
			"id": "planet_b",
			"center": Vector3(390, 0, 60),
			"radius": 105.0,
		},
	]
	var planned := PlannerType.plan_route(
		Vector3.ZERO,
		Vector3(620, 0, 0),
		hazards
	)
	_expect(
		bool(planned.get("ok", false)),
		"The 3D planner could not route around multiple hazards."
	)
	_expect(
		PlannerType.route_is_clear(
			Vector3.ZERO,
			planned.get("waypoints", []),
			hazards
		),
		"The multi-hazard route contains an invalid segment."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
