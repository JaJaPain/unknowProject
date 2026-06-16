class_name MissionTimingDefinition
extends RefCounted

const ValidationResultType := preload(
	"res://scripts/domain/ValidationResult.gd"
)

var timed: bool = false
var duration_seconds: float = 0.0
var duration_minutes: int = 0
var urgent: bool = false
var expiration_policy: String = ""
var urgent_reward_multiplier: float = 1.0


func load_from_dict(source: Dictionary) -> ValidationResult:
	var result := ValidationResultType.new()
	timed = bool(source.get("timed", source.get("is_timed", false)))
	duration_seconds = float(source.get("duration_seconds", 0.0))
	duration_minutes = int(source.get("duration_minutes", 0))
	if duration_minutes <= 0 and duration_seconds > 0.0:
		duration_minutes = int(ceil(duration_seconds / 60.0))
	if duration_seconds <= 0.0 and duration_minutes > 0:
		duration_seconds = float(duration_minutes * 60)
	urgent = bool(source.get("urgent", source.get("is_urgent", false)))
	expiration_policy = str(source.get("expiration_policy", "expire"))
	urgent_reward_multiplier = maxf(
		1.0,
		float(source.get("urgent_reward_multiplier", 1.0))
	)
	if timed and duration_minutes <= 0:
		result.add_error(
			"invalid_timing",
			"Timed missions require a positive duration_minutes value.",
			"duration_minutes"
		)
	if not timed:
		duration_seconds = 0.0
		duration_minutes = 0
		urgent = false
		expiration_policy = ""
		urgent_reward_multiplier = 1.0
	return result


func to_dict() -> Dictionary:
	return {
		"timed": timed,
		"duration_seconds": duration_seconds,
		"duration_minutes": duration_minutes,
		"urgent": urgent,
		"expiration_policy": expiration_policy,
		"urgent_reward_multiplier": urgent_reward_multiplier,
	}
