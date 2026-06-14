class_name MissionTimingDefinition
extends RefCounted

const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

var timed: bool = false
var duration_seconds: float = 0.0


func load_from_dict(source: Dictionary) -> ValidationResult:
	var result := ValidationResultType.new()
	timed = bool(source.get("timed", false))
	duration_seconds = float(source.get("duration_seconds", 0.0))
	if timed and duration_seconds <= 0.0:
		result.add_error(
			"invalid_timing",
			"Timed missions require a positive duration_seconds value.",
			"duration_seconds"
		)
	if not timed:
		duration_seconds = 0.0
	return result


func to_dict() -> Dictionary:
	return {
		"timed": timed,
		"duration_seconds": duration_seconds,
	}
