class_name MissionDirector
extends RefCounted

const MissionCapabilityRegistryType := preload(
	"res://scripts/domain/MissionCapabilityRegistry.gd"
)

const WEIGHT_CAUSAL_FIT := 40
const WEIGHT_BEAT_URGENCY := 20
const WEIGHT_VARIETY_PACING := 20
const WEIGHT_CHARACTER_STAKE := 10
const WEIGHT_PLAYER_SHIP_FIT := 10


static func feasible_candidates(
	packet: Dictionary,
	beat_states: Dictionary,
	local_givers: Array,
	valid_entity_ids: Array
) -> Array:
	var candidates: Array = []
	var valid_entities := {}
	for entity_id in valid_entity_ids:
		valid_entities[str(entity_id)] = true
	for beat in packet.get("beats", []):
		if not beat is Dictionary:
			continue
		var b: Dictionary = beat
		if not _beat_is_available(b, beat_states):
			continue
		for objective_type in _array_or_empty(b.get("supported_objective_types", [])):
			var objective := str(objective_type).strip_edges()
			if objective.is_empty() \
					or not MissionCapabilityRegistryType.has_type(objective):
				continue
			for giver in local_givers:
				if not giver is Dictionary:
					continue
				var g: Dictionary = giver
				var rejection := _candidate_rejection_reason(
					b,
					objective,
					g,
					valid_entities
				)
				if not rejection.is_empty():
					continue
				candidates.append(_candidate(packet, b, objective, g))
	return candidates


static func select_best_candidate(
	packet: Dictionary,
	beat_states: Dictionary,
	local_givers: Array,
	valid_entity_ids: Array,
	context: Dictionary = {},
	recent_agent_contracts: Array = [],
	declined_offer_cooldowns: Dictionary = {},
	current_minute: int = 0
) -> Dictionary:
	var feasible := feasible_candidates(
		packet,
		beat_states,
		local_givers,
		valid_entity_ids
	)
	if feasible.is_empty():
		return {
			"ok": false,
			"status": "no_feasible_candidates",
			"candidate": {},
			"rejections": rejected_candidate_reasons(
				packet,
				beat_states,
				local_givers,
				valid_entity_ids
			),
		}
	var not_declined := filter_by_decline_cooldowns(
		feasible,
		declined_offer_cooldowns,
		current_minute
	)
	if not_declined.is_empty():
		return {
			"ok": false,
			"status": "withheld_declined_offer_cooldown",
			"candidate": {},
			"needs_alternate_beat": true,
			"rejections": _decline_cooldown_rejections(
				feasible,
				declined_offer_cooldowns,
				current_minute
			),
		}
	var paced := filter_by_pacing_rules(not_declined, recent_agent_contracts)
	if paced.is_empty():
		return {
			"ok": false,
			"status": "withheld_pacing_rules",
			"candidate": {},
			"needs_alternate_beat": true,
			"rejections": _pacing_rejections(
				not_declined,
				recent_agent_contracts
			),
		}
	var scored := score_candidates(paced, context, recent_agent_contracts)
	if scored.is_empty():
		return {
			"ok": false,
			"status": "no_scored_candidates",
			"candidate": {},
		}
	return {
		"ok": true,
		"status": "selected",
		"candidate": scored[0],
		"candidate_count": scored.size(),
	}


static func rejected_candidate_reasons(
	packet: Dictionary,
	beat_states: Dictionary,
	local_givers: Array,
	valid_entity_ids: Array
) -> Array:
	var rejections: Array = []
	var valid_entities := {}
	for entity_id in valid_entity_ids:
		valid_entities[str(entity_id)] = true
	for beat in packet.get("beats", []):
		if not beat is Dictionary:
			continue
		var b: Dictionary = beat
		if not _beat_is_available(b, beat_states):
			rejections.append({
				"beat_id": str(b.get("beat_id", "")),
				"reason": "beat_not_available",
			})
			continue
		for objective_type in _array_or_empty(b.get("supported_objective_types", [])):
			var objective := str(objective_type).strip_edges()
			if objective.is_empty() \
					or not MissionCapabilityRegistryType.has_type(objective):
				rejections.append({
					"beat_id": str(b.get("beat_id", "")),
					"objective_type": objective,
					"reason": "unsupported_objective_type",
				})
				continue
			if local_givers.is_empty():
				rejections.append({
					"beat_id": str(b.get("beat_id", "")),
					"objective_type": objective,
					"reason": "no_local_giver",
				})
				continue
			for giver in local_givers:
				if not giver is Dictionary:
					continue
				var reason := _candidate_rejection_reason(
					b,
					objective,
					giver as Dictionary,
					valid_entities
				)
				if not reason.is_empty():
					rejections.append({
						"beat_id": str(b.get("beat_id", "")),
						"objective_type": objective,
						"giver_id": str((giver as Dictionary).get("giver_id", "")),
						"reason": reason,
					})
	return rejections


static func _decline_cooldown_rejections(
	candidates: Array,
	declined_offer_cooldowns: Dictionary,
	current_minute: int
) -> Array:
	var rejections: Array = []
	for candidate in candidates:
		if not candidate is Dictionary:
			continue
		var reason := decline_cooldown_rejection_reason(
			candidate as Dictionary,
			declined_offer_cooldowns,
			current_minute
		)
		_append_candidate_rejection(rejections, candidate as Dictionary, reason)
	return rejections


static func _pacing_rejections(
	candidates: Array,
	recent_agent_contracts: Array
) -> Array:
	var rejections: Array = []
	for candidate in candidates:
		if not candidate is Dictionary:
			continue
		var reason := pacing_rejection_reason(
			candidate as Dictionary,
			recent_agent_contracts
		)
		_append_candidate_rejection(rejections, candidate as Dictionary, reason)
	return rejections


static func _append_candidate_rejection(
	rejections: Array,
	candidate: Dictionary,
	reason: String
) -> void:
	var clean_reason := reason.strip_edges()
	if clean_reason.is_empty():
		return
	rejections.append({
		"beat_id": str(candidate.get("beat_id", "")),
		"objective_type": str(candidate.get("objective_type", "")),
		"giver_id": str(candidate.get("giver_id", "")),
		"reason": clean_reason,
	})


static func score_candidates(
	candidates: Array,
	context: Dictionary = {},
	recent_agent_contracts: Array = []
) -> Array:
	var scored: Array = []
	for candidate in candidates:
		if not candidate is Dictionary:
			continue
		scored.append(score_candidate(candidate as Dictionary, context, recent_agent_contracts))
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var score_a := int(a.get("score", 0))
		var score_b := int(b.get("score", 0))
		if score_a == score_b:
			return str(a.get("beat_id", "")) < str(b.get("beat_id", ""))
		return score_a > score_b
	)
	return scored


static func score_candidate(
	candidate: Dictionary,
	context: Dictionary = {},
	recent_agent_contracts: Array = []
) -> Dictionary:
	var breakdown := {
		"causal_fit": _score_causal_fit(candidate, context),
		"beat_urgency": _score_beat_urgency(candidate, context),
		"variety_pacing": _score_variety_pacing(candidate, recent_agent_contracts),
		"character_stake": _score_character_stake(candidate, context),
		"player_ship_fit": _score_player_ship_fit(candidate, context),
	}
	var total := 0
	for value in breakdown.values():
		total += int(value)
	var scored := candidate.duplicate(true)
	scored["score"] = total
	scored["score_breakdown"] = breakdown
	return scored


static func filter_by_pacing_rules(
	candidates: Array,
	recent_agent_contracts: Array
) -> Array:
	var kept: Array = []
	for candidate in candidates:
		if not candidate is Dictionary:
			continue
		if pacing_rejection_reason(candidate as Dictionary, recent_agent_contracts).is_empty():
			kept.append(candidate)
	return kept


static func filter_by_decline_cooldowns(
	candidates: Array,
	declined_offer_cooldowns: Dictionary,
	current_minute: int
) -> Array:
	var kept: Array = []
	for candidate in candidates:
		if not candidate is Dictionary:
			continue
		if decline_cooldown_rejection_reason(
			candidate as Dictionary,
			declined_offer_cooldowns,
			current_minute
		).is_empty():
			kept.append(candidate)
	return kept


static func decline_cooldown_rejection_reason(
	candidate: Dictionary,
	declined_offer_cooldowns: Dictionary,
	current_minute: int
) -> String:
	var key := declined_offer_cooldown_key(candidate)
	if key.is_empty() or not declined_offer_cooldowns.has(key):
		return ""
	if int(declined_offer_cooldowns.get(key, 0)) > current_minute:
		return "declined_offer_on_cooldown"
	return ""


static func declined_offer_cooldown_key(candidate: Dictionary) -> String:
	var explicit := str(candidate.get("decline_cooldown_key", "")).strip_edges()
	if not explicit.is_empty():
		return explicit
	var beat_id := str(candidate.get("beat_id", "")).strip_edges()
	var objective := str(candidate.get("objective_type", "")).strip_edges()
	var giver := str(candidate.get("giver_id", "")).strip_edges()
	if beat_id.is_empty() and objective.is_empty() and giver.is_empty():
		return ""
	return "%s|%s|%s" % [beat_id, objective, giver]


static func pacing_rejection_reason(
	candidate: Dictionary,
	recent_agent_contracts: Array
) -> String:
	var objective := str(candidate.get("objective_type", "")).strip_edges()
	if objective.is_empty():
		return "missing_objective_type"
	var last_two := recent_agent_contracts.slice(maxi(0, recent_agent_contracts.size() - 2))
	if last_two.size() >= 2 and _all_history_objective(last_two, objective):
		return "third_identical_objective_blocked"
	var last_four := recent_agent_contracts.slice(maxi(0, recent_agent_contracts.size() - 4))
	var same_in_four := 0
	for entry in last_four:
		if entry is Dictionary and str((entry as Dictionary).get("objective_type", "")) == objective:
			same_in_four += 1
	if same_in_four >= 2:
		return "objective_overrepresented_in_last_four"
	for entry in last_four:
		if entry is Dictionary \
				and str((entry as Dictionary).get("objective_type", "")) == objective:
			var changed := repeated_mechanic_change_count(candidate, entry as Dictionary)
			if changed < 3:
				return "repeated_mechanic_not_differentiated"
			break
	var fingerprint := str(candidate.get("premise_fingerprint", "")).strip_edges()
	if not fingerprint.is_empty():
		var last_eight := recent_agent_contracts.slice(maxi(0, recent_agent_contracts.size() - 8))
		for entry in last_eight:
			if entry is Dictionary \
					and str((entry as Dictionary).get("premise_fingerprint", "")) == fingerprint:
				return "repeated_premise_fingerprint"
	return ""


static func repeated_mechanic_change_count(
	candidate: Dictionary,
	prior_contract: Dictionary
) -> int:
	var changed := 0
	if _field_changed(candidate, prior_contract, "cause_id"):
		changed += 1
	if _field_changed(candidate, prior_contract, "stake"):
		changed += 1
	if _field_changed(candidate, prior_contract, "giver_id"):
		changed += 1
	if _field_changed(candidate, prior_contract, "location_id"):
		changed += 1
	if _field_changed(candidate, prior_contract, "complication"):
		changed += 1
	if _field_changed(candidate, prior_contract, "faction_id"):
		changed += 1
	if _array_fingerprint(candidate.get("disclosure_fact_ids", [])) \
			!= _array_fingerprint(prior_contract.get("disclosure_fact_ids", [])):
		changed += 1
	if _field_changed(candidate, prior_contract, "world_consequence"):
		changed += 1
	return changed


static func _field_changed(
	left: Dictionary,
	right: Dictionary,
	field: String
) -> bool:
	var left_value := str(left.get(field, "")).strip_edges()
	var right_value := str(right.get(field, "")).strip_edges()
	if left_value.is_empty() and right_value.is_empty():
		return false
	return left_value != right_value


static func _array_fingerprint(value: Variant) -> String:
	var parts: Array[String] = []
	for item in _array_or_empty(value):
		parts.append(str(item))
	parts.sort()
	return "|".join(parts)


static func _all_history_objective(history: Array, objective_type: String) -> bool:
	if history.is_empty():
		return false
	for entry in history:
		if not entry is Dictionary:
			return false
		if str((entry as Dictionary).get("objective_type", "")) != objective_type:
			return false
	return true


static func _score_causal_fit(candidate: Dictionary, context: Dictionary) -> int:
	var score := 0
	if not str(candidate.get("cause_id", "")).strip_edges().is_empty():
		score += 20
	if not str(candidate.get("stake", "")).strip_edges().is_empty():
		score += 10
	var preferred_causes: Array = _array_or_empty(context.get("preferred_cause_ids", []))
	if preferred_causes.has(str(candidate.get("cause_id", ""))):
		score += 10
	return mini(score, WEIGHT_CAUSAL_FIT)


static func _score_beat_urgency(candidate: Dictionary, context: Dictionary) -> int:
	var urgent_beats: Array = _array_or_empty(context.get("urgent_beat_ids", []))
	if urgent_beats.has(str(candidate.get("beat_id", ""))):
		return WEIGHT_BEAT_URGENCY
	var packet_consumed_ratio := float(context.get("packet_consumed_ratio", 0.0))
	return clampi(int(round(packet_consumed_ratio * float(WEIGHT_BEAT_URGENCY))), 0, WEIGHT_BEAT_URGENCY)


static func _score_variety_pacing(
	candidate: Dictionary,
	recent_agent_contracts: Array
) -> int:
	var objective := str(candidate.get("objective_type", ""))
	var same_recent := 0
	for entry in recent_agent_contracts.slice(maxi(0, recent_agent_contracts.size() - 4)):
		if entry is Dictionary and str((entry as Dictionary).get("objective_type", "")) == objective:
			same_recent += 1
	var score := WEIGHT_VARIETY_PACING - (same_recent * 8)
	return clampi(score, 0, WEIGHT_VARIETY_PACING)


static func _score_character_stake(candidate: Dictionary, context: Dictionary) -> int:
	var preferred_givers: Array = _array_or_empty(context.get("preferred_giver_ids", []))
	if preferred_givers.has(str(candidate.get("giver_id", ""))):
		return WEIGHT_CHARACTER_STAKE
	if not str(candidate.get("giver_display", "")).strip_edges().is_empty():
		return 5
	return 0


static func _score_player_ship_fit(candidate: Dictionary, context: Dictionary) -> int:
	var preferred_objectives: Array = _array_or_empty(context.get("preferred_objective_types", []))
	if preferred_objectives.has(str(candidate.get("objective_type", ""))):
		return WEIGHT_PLAYER_SHIP_FIT
	var ship_fit: Dictionary = context.get("ship_fit_by_objective", {}) \
		if context.get("ship_fit_by_objective", {}) is Dictionary else {}
	if ship_fit.has(str(candidate.get("objective_type", ""))):
		return clampi(int(ship_fit.get(str(candidate.get("objective_type", "")), 0)), 0, WEIGHT_PLAYER_SHIP_FIT)
	return 5


static func _beat_is_available(beat: Dictionary, beat_states: Dictionary) -> bool:
	var beat_id := str(beat.get("beat_id", "")).strip_edges()
	if beat_id.is_empty():
		return false
	var state: Dictionary = beat_states.get(beat_id, {}) \
		if beat_states.get(beat_id, {}) is Dictionary else {}
	var status := str(state.get("state", "available")).strip_edges()
	return status.is_empty() or ["available", "offered"].has(status)


static func _candidate_rejection_reason(
	beat: Dictionary,
	objective_type: String,
	giver: Dictionary,
	valid_entities: Dictionary
) -> String:
	var giver_id := str(giver.get("giver_id", "")).strip_edges()
	if giver_id.is_empty():
		return "missing_giver_id"
	if not bool(giver.get("available", true)):
		return "giver_unavailable"
	var giver_objectives: Array = _array_or_empty(giver.get("objective_types", []))
	if not giver_objectives.is_empty() and not giver_objectives.has(objective_type):
		return "giver_cannot_offer_objective"
	var eligible_entities: Array = _array_or_empty(beat.get("eligible_entity_ids", []))
	if eligible_entities.is_empty():
		return "missing_eligible_entity"
	for entity_id in eligible_entities:
		if not valid_entities.has(str(entity_id)):
			return "unknown_entity:%s" % str(entity_id)
	return ""


static func _candidate(
	packet: Dictionary,
	beat: Dictionary,
	objective_type: String,
	giver: Dictionary
) -> Dictionary:
	return {
		"packet_id": str(packet.get("packet_id", "")),
		"chapter": int(packet.get("chapter", 1)),
		"beat_id": str(beat.get("beat_id", "")),
		"thread_id": str(beat.get("thread_id", "")),
		"cause_id": str(beat.get("cause_id", "")),
		"objective_type": objective_type,
		"giver_id": str(giver.get("giver_id", "")),
		"giver_display": str(giver.get("display_name", giver.get("giver_id", ""))),
		"eligible_entity_ids": _array_or_empty(beat.get("eligible_entity_ids", [])),
		"location_id": str(beat.get("location_id", "")),
		"faction_id": str(beat.get("faction_id", "")),
		"complication": str(beat.get("complication", "")),
		"stake": str(beat.get("stake", "")),
		"disclosure_fact_ids": _array_or_empty(beat.get("disclosure_fact_ids", [])),
		"completion_fact_ids": _array_or_empty(beat.get("completion_fact_ids", [])),
		"decline_consequence": str(beat.get("decline_consequence", "")),
		"world_consequence": str(beat.get("world_consequence", "")),
		"premise_fingerprint": _premise_fingerprint(beat, objective_type, giver),
		"required": bool(beat.get("required", false)),
		"alternate_beat_id": str(beat.get("alternate_beat_id", "")),
		"decline_cooldown_key": declined_offer_cooldown_key({
			"beat_id": str(beat.get("beat_id", "")),
			"objective_type": objective_type,
			"giver_id": str(giver.get("giver_id", "")),
		}),
	}


static func _premise_fingerprint(
	beat: Dictionary,
	objective_type: String,
	giver: Dictionary
) -> String:
	var explicit := str(beat.get("premise_fingerprint", "")).strip_edges()
	if not explicit.is_empty():
		return explicit
	var parts := [
		objective_type,
		str(beat.get("cause_id", "")),
		str(beat.get("stake", "")),
		str(giver.get("giver_id", "")),
		_array_fingerprint(beat.get("eligible_entity_ids", [])),
	]
	return "|".join(parts).sha256_text().substr(0, 16)


static func _array_or_empty(value: Variant) -> Array:
	if value is Array:
		return value
	return []
