extends SceneTree

const ClockType := preload("res://scripts/time/CampaignClock.gd")

var failures: Array[String] = []


func _init() -> void:
	var clock := ClockType.new()
	_expect(
		clock.formatted_datetime() == "Day 001 08:00",
		"Clock should start at campaign day 1 morning."
	)
	clock.advance_minutes(95)
	_expect(
		clock.formatted_datetime() == "Day 001 09:35",
		"Clock should advance by deterministic minutes."
	)
	var captured := clock.capture_state()
	clock.advance_hours(30)
	clock.restore_state(captured)
	_expect(
		clock.formatted_datetime() == "Day 001 09:35",
		"Clock restore should return to the captured campaign time."
	)
	clock.restore_state({"total_minutes": -50})
	_expect(
		clock.formatted_datetime() == "Day 001 00:00",
		"Clock restore should clamp negative campaign time."
	)
	_expect(
		clock.format_duration(185) == "3h 5m",
		"Clock should format mixed durations."
	)
	if failures.is_empty():
		print("[PASS] Campaign clock tests")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
