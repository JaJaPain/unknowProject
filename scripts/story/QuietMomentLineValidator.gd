class_name QuietMomentLineValidator
extends RefCounted

# Narrow deterministic review for optional fixed-cast quiet moments. It covers
# facts and presentation that an LLM can occasionally embellish even when its
# input packet is intentionally small. Character voice remains owned by the
# fixed-cast validator/soul bible once quiet moments become a runtime feature.

const MAX_WORDS := 28
const VoiceBankType := preload("res://scripts/story/FixedCastVoiceBank.gd")
const EARTH_CALENDAR_TERMS := [
	"monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
]
const REFERENCE_RUNS := {
	"kaelen:safe_low_pay_completion": ["we both get to keep breathing", "good money messy work"],
	"nova:post_fight_stable_hull": ["dull minute", "no pursuit no alarms no new dents"],
}


static func validate_line(
	character_id: String,
	moment_id: String,
	line: String
) -> Dictionary:
	var clean := line.strip_edges()
	var lower := clean.to_lower()
	var errors: Array[String] = []
	if clean.is_empty():
		errors.append("empty_line")
	if clean.split(" ", false).size() > MAX_WORDS:
		errors.append("too_many_words")
	if clean.contains("\n"):
		errors.append("multiline")
	if _contains_reference_run(lower, REFERENCE_RUNS.get("%s:%s" % [character_id, moment_id], [])):
		errors.append("copied_style_reference")
	if VoiceBankType.matches_curated_line(character_id, "quiet_moment", clean):
		errors.append("copied_curated_quiet_reference")
	match "%s:%s" % [character_id, moment_id]:
		"kaelen:safe_low_pay_completion":
			if not _contains_any(lower, ["pay", "payout", "credit", "margin", "terms", "receipt"]):
				errors.append("missing_modest_payout_anchor")
			if _contains_any(lower, EARTH_CALENDAR_TERMS):
				errors.append("earth_calendar_reference")
			if lower.contains("crew"):
				errors.append("invented_unnamed_crew")
			if _contains_any(lower, ["next", "on me"]):
				errors.append("invented_future_offer")
			if _contains_any(lower, ["no drama", "all good", "job well done", "no surprises"]):
				errors.append("generic_empty_closer")
			if _contains_any(lower, ["coffee", "drink", "last time", "prior job", "fee"]):
				errors.append("invented_personal_or_accounting_detail")
		"nova:post_fight_stable_hull":
			if not lower.contains("hull"):
				errors.append("missing_hull_anchor")
			if not _contains_any(lower, ["sensor", "pursuit"]):
				errors.append("missing_clear_space_anchor")
			if _contains_any(lower, ["breathing", "breathe", "safe", "comms", "communications", "alarm", "alarms", "streak", "threat", "nominal"]):
				errors.append("invented_player_or_comms_condition")
			if _contains_any(lower, ["no need to", "you should", "do not ", "don't ", "i recommend", "let's ", "we should", "report ", "move", "check ", "hold ", "engage ", "use ", "reroute", "ready"]):
				errors.append("unrequested_directive")
			if lower.contains("%"):
				errors.append("invented_numeric_condition")
	return {"ok": errors.is_empty(), "errors": errors}


static func _contains_any(text: String, terms: Array) -> bool:
	for term in terms:
		if text.contains(str(term).to_lower()):
			return true
	return false


static func _contains_reference_run(text: String, phrases: Array) -> bool:
	var normalized_text := _normalize(text)
	for phrase in phrases:
		var normalized_phrase := _normalize(str(phrase))
		if not normalized_phrase.is_empty() and normalized_text.contains(normalized_phrase):
			return true
	return false


static func _normalize(value: String) -> String:
	var clean := value.to_lower()
	for punctuation in [".", ",", "!", "?", ";", ":", "'", "\"", "-", "â€”"]:
		clean = clean.replace(punctuation, " ")
	return " ".join(clean.split(" ", false))
