class_name KaelenInteractionPacketBuilder
extends RefCounted

const ContextBlockBuilderType := preload("res://scripts/ai/ContextBlockBuilder.gd")
const KaelenInteractionKindsType := preload(
	"res://scripts/story/KaelenInteractionKinds.gd"
)

const MAX_MEMORY_SNIPPETS := 6


static func build_packet(
	interaction_kind: String,
	mission_state: Dictionary,
	story_state: Dictionary,
	memories: Array = [],
	style_context: Dictionary = {}
) -> Dictionary:
	var kind := interaction_kind.strip_edges()
	if not KaelenInteractionKindsType.is_valid(kind):
		return {
			"ok": false,
			"error": "invalid_kaelen_interaction_kind",
			"interaction_kind": kind,
		}
	var packet := {
		"ok": true,
		"speaker_id": "kaelen",
		"speaker_name": "Broker Kaelen",
		"interaction_kind": kind,
		"mission": _mission_projection(mission_state),
		"safe_story_context": ContextBlockBuilderType.kaelen_block(story_state),
		"relevant_memory": _memory_projection(memories),
		"safe_kaelen_style": _style_projection(style_context, story_state),
		"allow_safe_after_completion_reveal":
			KaelenInteractionKindsType.allows_safe_after_completion_reveal(kind),
	}
	if bool(packet.get("allow_safe_after_completion_reveal", false)):
		packet["earned_aftermath"] = _earned_aftermath_projection(mission_state)
	return packet


static func turn_in_kind_for_mission(mission_state: Dictionary) -> String:
	var metadata: Dictionary = mission_state.get("narrative_metadata", {}) \
		if mission_state.get("narrative_metadata", {}) is Dictionary else {}
	var outcome: Dictionary = metadata.get("outcome_snapshot", {}) \
		if metadata.get("outcome_snapshot", {}) is Dictionary else {}
	var profile := _outcome_profile(mission_state, outcome)
	return str(profile.get(
		"turn_in_variant",
		KaelenInteractionKindsType.TURN_IN_CLEAN
	))


static func _mission_projection(mission_state: Dictionary) -> Dictionary:
	var metadata: Dictionary = mission_state.get("narrative_metadata", {}) \
		if mission_state.get("narrative_metadata", {}) is Dictionary else {}
	var outcome: Dictionary = metadata.get("outcome_snapshot", {}) \
		if metadata.get("outcome_snapshot", {}) is Dictionary else {}
	return {
		"mission_id": str(mission_state.get("runtime_id", "")),
		"title": str(mission_state.get("title", "")),
		"objective_type": str(mission_state.get("objective_type", "")),
		"giver_name": str(mission_state.get("agent_name", "")),
		"giver_id": str(mission_state.get("agent_id", "")),
		"faction": str(mission_state.get("faction", "")),
		"story_thread_id": str(mission_state.get(
			"story_thread_id",
			metadata.get("story_thread_id", "")
		)),
		"story_beat_id": str(mission_state.get(
			"story_beat_id",
			metadata.get("story_beat_id", "")
		)),
		"cause_id": str(mission_state.get("cause_id", metadata.get("cause_id", ""))),
		"public_because": str(metadata.get("public_because", "")),
		"stake": str(mission_state.get("stake", metadata.get("stake", ""))),
		"asked_question_intents": _string_array(
			mission_state.get("conversation_asked_intents", [])
		),
		"learned_fact_ids": _string_array(
			mission_state.get("conversation_learned_fact_ids", [])
		),
		"accepted_terms": {
			"choice_id": str(mission_state.get("choice_id_selected", "")),
			"choice_text": str(mission_state.get("choice_text_selected", "")),
			"conversation_intent_id": str(
				mission_state.get("conversation_intent_id_selected", "")
			),
			"urgent": bool(mission_state.get("is_urgent", false)),
			"timed": bool(mission_state.get("is_timed", false)),
			"deadline_time_minutes": int(
				mission_state.get("deadline_time_minutes", 0)
			),
		},
		"outcome_summary": _safe_outcome_summary(outcome),
		"outcome_profile": _outcome_profile(mission_state, outcome),
	}


static func _earned_aftermath_projection(mission_state: Dictionary) -> Dictionary:
	var metadata: Dictionary = mission_state.get("narrative_metadata", {}) \
		if mission_state.get("narrative_metadata", {}) is Dictionary else {}
	var outcome: Dictionary = metadata.get("outcome_snapshot", {}) \
		if metadata.get("outcome_snapshot", {}) is Dictionary else {}
	return {
		"public_because": str(metadata.get("public_because", "")),
		"world_consequence": str(outcome.get("world_consequence", "")),
		"completion_fact_ids": _string_array(metadata.get("completion_fact_ids", [])),
	}


static func _safe_outcome_summary(outcome: Dictionary) -> Dictionary:
	return {
		"world_consequence": str(outcome.get("world_consequence", "")),
		"completion_status": str(outcome.get("completion_status", "")),
		"outcome_band": str(outcome.get("outcome_band", "")),
	}


static func _outcome_profile(
	mission_state: Dictionary,
	outcome: Dictionary
) -> Dictionary:
	var timing := _timing_profile(mission_state, outcome)
	var partial_delivery := _partial_delivery_profile(mission_state)
	var terms := _accepted_term_profile(mission_state)
	var learned_fact_ids := _string_array(
		mission_state.get("conversation_learned_fact_ids", [])
	)
	var tone := _outcome_tone(
		outcome,
		timing,
		partial_delivery,
		learned_fact_ids
	)
	return {
		"turn_in_variant": _turn_in_kind_for_tone(tone),
		"outcome_tone": tone,
		"timing": timing,
		"partial_delivery": partial_delivery,
		"accepted_term_variant": terms,
		"learned_fact_ids": learned_fact_ids,
		"learned_story_fact": not learned_fact_ids.is_empty(),
	}


static func _timing_profile(
	mission_state: Dictionary,
	outcome: Dictionary
) -> Dictionary:
	var timed := bool(mission_state.get("is_timed", false))
	var deadline := int(mission_state.get("deadline_time_minutes", 0))
	var completion_time := int(mission_state.get(
		"completed_time_minutes",
		mission_state.get("objective_completed_time_minutes", 0)
	))
	var remaining := deadline - completion_time if timed and completion_time > 0 else 0
	var label := str(outcome.get("timing", "")).strip_edges()
	if label.is_empty():
		if not timed:
			label = "untimed"
		elif completion_time <= 0:
			label = "pending_turn_in"
		elif remaining < 0:
			label = "late"
		elif remaining <= 10:
			label = "close_call"
		else:
			label = "on_time"
	return {
		"timed": timed,
		"deadline_time_minutes": deadline,
		"completion_time_minutes": completion_time,
		"minutes_remaining": remaining,
		"label": label,
	}


static func _partial_delivery_profile(mission_state: Dictionary) -> Dictionary:
	var required := float(mission_state.get("amount_required", 0.0))
	var delivered := float(mission_state.get("partial_delivered", 0.0))
	var count := int(mission_state.get("partial_delivery_count", 0))
	return {
		"had_partial_delivery": count > 0,
		"delivery_count": count,
		"delivered_amount": delivered,
		"required_amount": required,
		"completed_in_multiple_drops": count > 1,
	}


static func _accepted_term_profile(mission_state: Dictionary) -> Dictionary:
	var choice_id := str(mission_state.get("choice_id_selected", "")).to_lower()
	var choice_text := str(mission_state.get("choice_text_selected", "")).to_lower()
	var joined := "%s %s" % [choice_id, choice_text]
	var variant := "standard"
	if joined.contains("advance"):
		variant = "advance"
	elif joined.contains("hazard") or joined.contains("danger"):
		variant = "hazard"
	elif joined.contains("urgent") or bool(mission_state.get("is_urgent", false)):
		variant = "urgent"
	return {
		"variant": variant,
		"choice_id": str(mission_state.get("choice_id_selected", "")),
		"choice_text": str(mission_state.get("choice_text_selected", "")),
	}


static func _outcome_tone(
	outcome: Dictionary,
	timing: Dictionary,
	partial_delivery: Dictionary,
	learned_fact_ids: Array[String]
) -> String:
	var summary := (
		str(outcome.get("completion_status", "")) + " "
		+ str(outcome.get("outcome_band", "")) + " "
		+ str(outcome.get("world_consequence", ""))
	).to_lower()
	if str(timing.get("label", "")) == "late" or summary.contains("late"):
		return "late"
	for marker in ["rough", "damaged", "hazard", "partial", "messy"]:
		if summary.contains(marker):
			return "rough"
	if bool(partial_delivery.get("completed_in_multiple_drops", false)):
		return "rough"
	if not learned_fact_ids.is_empty():
		return "clean_with_story_fact"
	return "clean"


static func _turn_in_kind_for_tone(outcome_tone: String) -> String:
	match outcome_tone:
		"late":
			return KaelenInteractionKindsType.TURN_IN_LATE
		"rough":
			return KaelenInteractionKindsType.TURN_IN_ROUGH
		_:
			return KaelenInteractionKindsType.TURN_IN_CLEAN


static func _memory_projection(memories: Array) -> Array[Dictionary]:
	var projected: Array[Dictionary] = []
	for raw in memories:
		if projected.size() >= MAX_MEMORY_SNIPPETS:
			break
		if not raw is Dictionary:
			continue
		var memory: Dictionary = raw
		projected.append({
			"memory_id": str(memory.get("memory_id", "")),
			"category": str(memory.get("category", "")),
			"summary": str(memory.get("summary", "")),
			"fact_refs": _string_array(memory.get("fact_refs", [])),
		})
	return projected


static func _style_projection(
	style_context: Dictionary,
	story_state: Dictionary
) -> Dictionary:
	return {
		"relationship_tier": str(style_context.get("relationship_tier", "neutral")),
		"kaelen_mood": str(story_state.get("kaelen_current_mood", "")),
		"voice_profile_id": "voice.kaelen.v1",
	}


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item in value:
		var text := str(item).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result
