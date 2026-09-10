class_name ChallengeBudget
extends RefCounted

const BAND_ROUTINE := "routine"
const BAND_PRESSURED := "pressured"
const BAND_DANGEROUS := "dangerous"
const BAND_STORY_CLIMAX := "story_climax"
const VALID_BANDS := [
	BAND_ROUTINE,
	BAND_PRESSURED,
	BAND_DANGEROUS,
	BAND_STORY_CLIMAX,
]


static func budget_for_candidate(
	candidate: Dictionary,
	player_context: Dictionary = {},
	chapter_context: Dictionary = {}
) -> Dictionary:
	var band := _difficulty_band(candidate, player_context, chapter_context)
	var duration := target_duration_minutes(candidate, player_context, chapter_context, band)
	return {
		"difficulty_band": band,
		"target_duration_minutes": duration,
		"ore_amount": ore_amount_for_duration(duration, player_context)
			if str(candidate.get("objective_type", "")) == "DELIVER_ORE" else 0.0,
		"kill_count": kill_count_for_duration(duration, player_context)
			if str(candidate.get("objective_type", "")) == "KILL_SHIPS" else 0,
		"deadline_minutes": _deadline_for_band(duration, band),
		"reward_multiplier": _reward_multiplier_for_band(band),
	}


static func target_duration_minutes(
	candidate: Dictionary,
	player_context: Dictionary,
	chapter_context: Dictionary,
	band: String = ""
) -> int:
	var objective := str(candidate.get("objective_type", ""))
	var base := 24
	match objective:
		"DELIVER_ORE":
			base = 18 + int(ceilf(ore_amount_for_duration(18, player_context) / 12.0))
		"KILL_SHIPS":
			base = 20 + kill_count_for_duration(20, player_context) * 5
		"DELIVERY_COURIER", "PURCHASE_DELIVERY":
			base = 18 + int(player_context.get("route_minutes", 12))
		"RECOVER_COMBAT_DROP", "TARGET_WITH_COMMS_REVERSAL":
			base = 28 + kill_count_for_duration(28, player_context) * 6
	var chapter_pressure := clampi(int(chapter_context.get("pressure", 0)), 0, 5)
	base += chapter_pressure * 3
	var resolved_band := band if VALID_BANDS.has(band) else _difficulty_band(
		candidate,
		player_context,
		chapter_context
	)
	match resolved_band:
		BAND_ROUTINE:
			base = int(round(float(base) * 0.85))
		BAND_PRESSURED:
			base = int(round(float(base) * 1.0))
		BAND_DANGEROUS:
			base = int(round(float(base) * 1.25))
		BAND_STORY_CLIMAX:
			base = int(round(float(base) * 1.5))
	return clampi(base, 10, 120)


static func ore_amount_for_duration(
	target_minutes: int,
	player_context: Dictionary
) -> float:
	var cargo_capacity := maxf(5.0, float(player_context.get("cargo_capacity", 30.0)))
	var mining_rate := maxf(4.0, float(player_context.get("mining_rate_per_minute", 8.0)))
	var trip_factor := clampf(float(target_minutes) / 30.0, 0.5, 2.5)
	var desired := mining_rate * float(target_minutes) * 0.65
	return minf(cargo_capacity * trip_factor, desired)


static func kill_count_for_duration(
	target_minutes: int,
	player_context: Dictionary
) -> int:
	var combat_rating := maxf(0.5, float(player_context.get("combat_rating", 1.0)))
	var enemy_strength := maxf(0.5, float(player_context.get("enemy_strength", 1.0)))
	var minutes_per_kill := 6.0 * enemy_strength / combat_rating
	return clampi(int(floor(float(target_minutes) / minutes_per_kill)), 1, 8)


static func _difficulty_band(
	candidate: Dictionary,
	player_context: Dictionary,
	chapter_context: Dictionary
) -> String:
	if bool(candidate.get("story_climax", false)):
		return BAND_STORY_CLIMAX
	var pressure := int(chapter_context.get("pressure", 0))
	var hull_ratio := float(player_context.get("hull_ratio", 1.0))
	if hull_ratio < 0.35:
		return BAND_ROUTINE
	if pressure >= 4:
		return BAND_DANGEROUS
	if pressure >= 2 or bool(candidate.get("urgent", false)):
		return BAND_PRESSURED
	return BAND_ROUTINE


static func _deadline_for_band(duration: int, band: String) -> int:
	match band:
		BAND_ROUTINE:
			return 0
		BAND_PRESSURED:
			return duration * 3
		BAND_DANGEROUS:
			return duration * 2
		BAND_STORY_CLIMAX:
			return int(round(float(duration) * 1.5))
	return 0


static func _reward_multiplier_for_band(band: String) -> float:
	match band:
		BAND_ROUTINE:
			return 1.0
		BAND_PRESSURED:
			return 1.25
		BAND_DANGEROUS:
			return 1.6
		BAND_STORY_CLIMAX:
			return 2.0
	return 1.0
