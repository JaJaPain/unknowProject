extends SceneTree

# Tests BountyRegistry pure logic: cap enforcement, faction/system matching,
# payout return values. Does not test side-effects (credits, chat).

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	_test_check_kill_returns_payout()
	_test_cap_respected()
	_test_wrong_system_no_payout()
	_test_wrong_faction_no_payout()
	_test_get_active_bounties()
	_test_confirm_line_not_empty()
	_test_announcement_lines_single()
	_test_announcement_lines_empty()
	_print_results()
	quit(_failed)


func _make_registry() -> RefCounted:
	var script = load("res://scripts/economy/BountyRegistry.gd")
	return script.new()


func _test_check_kill_returns_payout() -> void:
	var reg: RefCounted = _make_registry()
	reg.set_bounties([{
		"faction": "dustborn",
		"system_id": "test_system",
		"payout_per_kill": 9,
		"cap": 5,
		"kills_credited": 0,
		"kaelen_line": "Test bounty.",
	}])
	var payout: int = reg.check_kill("dustborn", "test_system")
	if payout == 9:
		_pass("check_kill_returns_payout")
	else:
		_fail("check_kill_returns_payout", "expected 9 got %d" % payout)


func _test_cap_respected() -> void:
	var reg: RefCounted = _make_registry()
	reg.set_bounties([{
		"faction": "reavers",
		"system_id": "test_system",
		"payout_per_kill": 8,
		"cap": 2,
		"kills_credited": 0,
		"kaelen_line": "Test.",
	}])
	var a: int = reg.check_kill("reavers", "test_system")
	var b: int = reg.check_kill("reavers", "test_system")
	var third: int = reg.check_kill("reavers", "test_system")
	if a == 8 and b == 8 and third == 0:
		_pass("cap_respected")
	else:
		_fail("cap_respected", "a=%d b=%d third=%d" % [a, b, third])


func _test_wrong_system_no_payout() -> void:
	var reg: RefCounted = _make_registry()
	reg.set_bounties([{
		"faction": "ironclad",
		"system_id": "other_system",
		"payout_per_kill": 10,
		"cap": 5,
		"kills_credited": 0,
		"kaelen_line": "Test.",
	}])
	var payout: int = reg.check_kill("ironclad", "test_system")
	if payout == 0:
		_pass("wrong_system_no_payout")
	else:
		_fail("wrong_system_no_payout", "expected 0 got %d" % payout)


func _test_wrong_faction_no_payout() -> void:
	var reg: RefCounted = _make_registry()
	reg.set_bounties([{
		"faction": "dustborn",
		"system_id": "test_system",
		"payout_per_kill": 9,
		"cap": 5,
		"kills_credited": 0,
		"kaelen_line": "Test.",
	}])
	var payout: int = reg.check_kill("reavers", "test_system")
	if payout == 0:
		_pass("wrong_faction_no_payout")
	else:
		_fail("wrong_faction_no_payout", "expected 0 got %d" % payout)


func _test_get_active_bounties() -> void:
	var reg: RefCounted = _make_registry()
	reg.set_bounties([
		{"faction": "dustborn", "system_id": "s", "payout_per_kill": 8, "cap": 1, "kills_credited": 0, "kaelen_line": ""},
		{"faction": "reavers", "system_id": "s", "payout_per_kill": 8, "cap": 1, "kills_credited": 1, "kaelen_line": ""},
	])
	var active: Array = reg.get_active_bounties()
	if active.size() == 1 and active[0]["faction"] == "dustborn":
		_pass("get_active_bounties")
	else:
		_fail("get_active_bounties", "size=%d" % active.size())


func _test_confirm_line_not_empty() -> void:
	var reg: RefCounted = _make_registry()
	reg.set_bounties([{
		"faction": "dustborn", "system_id": "s", "payout_per_kill": 9, "cap": 5,
		"kills_credited": 0, "kaelen_line": "Test.",
	}])
	reg.check_kill("dustborn", "s")
	var line: String = reg.confirm_line("dustborn", 9)
	if not line.is_empty():
		_pass("confirm_line_not_empty")
	else:
		_fail("confirm_line_not_empty", "empty string returned")


func _test_announcement_lines_single() -> void:
	var reg: RefCounted = _make_registry()
	reg.set_bounties([{
		"faction": "dustborn", "system_id": "s", "payout_per_kill": 9, "cap": 5,
		"kills_credited": 0, "kaelen_line": "They owe me.",
	}])
	var lines: Array = reg.announcement_lines()
	if lines.size() == 1 and lines[0] == "They owe me.":
		_pass("announcement_lines_single")
	else:
		_fail("announcement_lines_single", "lines=%s" % str(lines))


func _test_announcement_lines_empty() -> void:
	var reg: RefCounted = _make_registry()
	var lines: Array = reg.announcement_lines()
	if lines.is_empty():
		_pass("announcement_lines_empty")
	else:
		_fail("announcement_lines_empty", "expected empty, got %s" % str(lines))


func _pass(label: String) -> void:
	_passed += 1
	print("[PASS] %s" % label)


func _fail(label: String, detail: String) -> void:
	_failed += 1
	print("[FAIL] %s — %s" % [label, detail])


func _print_results() -> void:
	print("\nBounty Registry Tests: %d passed, %d failed" % [_passed, _failed])
	if _failed == 0:
		print("[PASS] Bounty registry tests")
