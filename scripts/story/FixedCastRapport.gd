class_name FixedCastRapport
extends RefCounted

# Emotional seasoning, not a romance or morality system. Scores never affect
# rewards, mechanics, or player agency; they only select the public rapport
# lens supplied to fixed-cast dialogue.
const MIN_SCORE := -5
const MAX_SCORE := 5
const CHARACTER_IDS := ["kaelen", "nova"]


static func default_ledger() -> Dictionary:
	return {
		"initialized_after_tutorial": false,
		"kaelen": _entry(0),
		"nova": _entry(0),
	}


static func normalize_ledger(source: Dictionary) -> Dictionary:
	var ledger := default_ledger()
	ledger["initialized_after_tutorial"] = bool(source.get("initialized_after_tutorial", false))
	for character_id in CHARACTER_IDS:
		var raw: Dictionary = source.get(character_id, {}) if source.get(character_id, {}) is Dictionary else {}
		var entry := _entry(clampi(int(raw.get("score", 0)), MIN_SCORE, MAX_SCORE))
		entry["revision"] = maxi(0, int(raw.get("revision", 0)))
		entry["last_reason"] = str(raw.get("last_reason", ""))
		entry["last_changed_minute"] = maxi(0, int(raw.get("last_changed_minute", 0)))
		ledger[character_id] = entry
	return ledger


static func initialize_after_tutorial(ledger: Dictionary, campaign_seed: String) -> Dictionary:
	var next := normalize_ledger(ledger)
	if bool(next.get("initialized_after_tutorial", false)):
		return next
	for character_id in CHARACTER_IDS:
		# Small starting variance only: tutorial establishes trust before personal
		# history has any room to grow.
		var seed_text := "%s|fixed_cast_rapport|%s" % [campaign_seed, character_id]
		# Use only the first eight hexadecimal characters so conversion never
		# overflows Godot's signed 64-bit integer.
		var score := seed_text.sha256_text().substr(0, 8).hex_to_int() % 3 - 1
		next[character_id] = _entry(score)
	next["initialized_after_tutorial"] = true
	return next


static func apply_mission_event(
	ledger: Dictionary,
	event_type: String,
	mission: Dictionary,
	minute: int
) -> Dictionary:
	var next := normalize_ledger(ledger)
	if not bool(next.get("initialized_after_tutorial", false)):
		return next
	var deltas := _mission_deltas(event_type, mission)
	for character_id in CHARACTER_IDS:
		var delta := int(deltas.get(character_id, 0))
		if delta == 0:
			continue
		var entry: Dictionary = next.get(character_id, {})
		entry["score"] = clampi(int(entry.get("score", 0)) + delta, MIN_SCORE, MAX_SCORE)
		entry["band"] = band_for_score(int(entry.get("score", 0)))
		entry["revision"] = int(entry.get("revision", 0)) + 1
		entry["last_reason"] = "%s:%s" % [event_type, _objective_type(mission)]
		entry["last_changed_minute"] = maxi(0, minute)
		next[character_id] = entry
	return next


static func band_for_score(score: int) -> String:
	if score <= -3:
		return "irritated"
	if score <= -1:
		return "guarded"
	if score <= 1:
		return "neutral"
	if score <= 3:
		return "warm"
	if score <= 4:
		return "fond"
	return "infatuated"


static func _mission_deltas(event_type: String, mission: Dictionary) -> Dictionary:
	var objective := _objective_type(mission)
	var reward := _reward_credits(mission)
	var kaelen := 0
	var nova := 0
	# An attachment opportunity is optional by design. Choosing not to take it
	# cannot reduce rapport; a later broadly eligible action can still advance
	# the same code-owned attachment beat.
	if event_type == "declined" and _is_attachment_opportunity(mission):
		return {"kaelen": 0, "nova": 0}
	match event_type:
		"completed":
			kaelen = 1
			nova = 1
			if reward >= 300:
				kaelen += 1
			# N.O.V.A. does not punish ordinary combat. Her concern rises only
			# when the contract advertised serious danger before the Captain chose it.
			if objective in ["KILL_SHIPS", "TARGET_WITH_COMMS_REVERSAL"] \
					and _is_known_tough(mission):
				nova -= 2
		"abandoned":
			kaelen = -2
			nova = -1
		"declined":
			kaelen = -1
			if objective in ["KILL_SHIPS", "TARGET_WITH_COMMS_REVERSAL"] \
					and _is_known_tough(mission):
				nova = 1
		"expired", "failed":
			kaelen = -1
			nova = -1
	return {"kaelen": kaelen, "nova": nova}


static func _is_attachment_opportunity(mission: Dictionary) -> bool:
	var metadata: Dictionary = mission.get("narrative_metadata", {}) \
		if mission.get("narrative_metadata", {}) is Dictionary else {}
	var attachment_beats: Array = metadata.get("attachment_beats", []) \
		if metadata.get("attachment_beats", []) is Array else []
	return not attachment_beats.is_empty()


static func _objective_type(mission: Dictionary) -> String:
	var objective: Dictionary = mission.get("objective", {}) if mission.get("objective", {}) is Dictionary else {}
	return str(mission.get("objective_type", objective.get("type", ""))).strip_edges()


static func _reward_credits(mission: Dictionary) -> int:
	var objective: Dictionary = mission.get("objective", {}) if mission.get("objective", {}) is Dictionary else {}
	return int(mission.get("reward_credits", objective.get("reward_credits", 0)))


static func _is_known_tough(mission: Dictionary) -> bool:
	if bool(mission.get("known_tough", false)):
		return true
	var metadata: Dictionary = mission.get("narrative_metadata", {}) \
		if mission.get("narrative_metadata", {}) is Dictionary else {}
	var snapshot: Dictionary = metadata.get("outcome_snapshot", {}) \
		if metadata.get("outcome_snapshot", {}) is Dictionary else {}
	var budget: Dictionary = snapshot.get("challenge_budget", {}) \
		if snapshot.get("challenge_budget", {}) is Dictionary else {}
	return str(mission.get("difficulty_band", budget.get("difficulty_band", ""))) \
		in ["dangerous", "story_climax"]


static func _entry(score: int) -> Dictionary:
	return {"score": score, "band": band_for_score(score), "revision": 0, "last_reason": "", "last_changed_minute": 0}
