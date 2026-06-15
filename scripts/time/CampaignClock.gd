extends Node

signal time_changed(total_minutes: int)

const START_DAY := 1
const START_HOUR := 8
const MINUTES_PER_HOUR := 60
const HOURS_PER_DAY := 24
const MINUTES_PER_DAY := HOURS_PER_DAY * MINUTES_PER_HOUR

var total_minutes: int = START_HOUR * MINUTES_PER_HOUR


func reset_for_restart() -> void:
	total_minutes = START_HOUR * MINUTES_PER_HOUR
	time_changed.emit(total_minutes)


func advance_minutes(minutes: int) -> void:
	if minutes <= 0:
		return
	total_minutes += minutes
	time_changed.emit(total_minutes)


func advance_hours(hours: int) -> void:
	advance_minutes(hours * MINUTES_PER_HOUR)


func capture_state() -> Dictionary:
	return {
		"total_minutes": total_minutes,
	}


func restore_state(state: Dictionary) -> void:
	total_minutes = max(
		0,
		int(state.get("total_minutes", START_HOUR * MINUTES_PER_HOUR))
	)
	time_changed.emit(total_minutes)


func formatted_datetime() -> String:
	var day := START_DAY + int(total_minutes / MINUTES_PER_DAY)
	var minutes_in_day: int = total_minutes % MINUTES_PER_DAY
	var hour := int(minutes_in_day / MINUTES_PER_HOUR)
	var minute: int = minutes_in_day % MINUTES_PER_HOUR
	return "Day %03d %02d:%02d" % [day, hour, minute]


func format_duration(minutes: int) -> String:
	var clamped: int = maxi(0, minutes)
	var hours := int(clamped / MINUTES_PER_HOUR)
	var mins: int = clamped % MINUTES_PER_HOUR
	if hours <= 0:
		return "%dm" % mins
	if mins <= 0:
		return "%dh" % hours
	return "%dh %dm" % [hours, mins]
