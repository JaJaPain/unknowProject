extends SceneTree

const LoungeConversationType := preload("res://scripts/story/LoungeConversation.gd")

const AGENT_OFFER_COUNT := 30
const LOUNGE_CONVERSATION_COUNT := 12
const NOVA_EVENT_COUNT := 30
const KAELEN_TURN_IN_COUNT := 12
const RESULT_ARTIFACT_PATH := "res://logs/narrative_baseline_capture.json"

var _agent_results: Array[Dictionary] = []
var _lounge_results: Array[Dictionary] = []
var _nova_results: Array[Dictionary] = []
var _kaelen_results: Array[Dictionary] = []
var _run_started_msec := 0
var _phase_index := 0
var _item_started_msec := 0


func _initialize() -> void:
	_run_started_msec = Time.get_ticks_msec()
	print("[NarrativeBaseline] Starting scripted baseline capture.")
	_run_next_agent_offer()


func _run_next_agent_offer() -> void:
	if _agent_results.size() >= AGENT_OFFER_COUNT:
		_run_next_lounge_conversation()
		return
	_item_started_msec = Time.get_ticks_msec()
	var factions := ["zenith", "aurelia", "vanguard", "neutral"]
	var faction: String = factions[_agent_results.size() % factions.size()]
	LLMInterface.request_quest_generation(
		faction,
		"",
		500,
		{"zenith": 20.0, "aurelia": 0.0, "vanguard": -10.0},
		func(quest_data: Dictionary, is_fallback: bool) -> void:
			_agent_results.append(_agent_offer_row(quest_data, faction, is_fallback))
			_run_next_agent_offer()
	)


func _run_next_lounge_conversation() -> void:
	if _lounge_results.size() >= LOUNGE_CONVERSATION_COUNT:
		_run_next_nova_event()
		return
	_item_started_msec = Time.get_ticks_msec()
	var npc := _lounge_fixture(_lounge_results.size())
	var flavor := "Current campaign mood: frontier pressure, old debts, and nervous station traffic."
	var opener_prompt := LoungeConversationType.build_opener_prompt(npc, flavor)
	LLMInterface.request_lounge_conversation_turn(
		opener_prompt,
		func(opener_result: Dictionary) -> void:
			var opener := LoungeConversationType.parse_turn(
				str(opener_result.get("inner_text", "")),
				str(npc.get("name", ""))
			)
			if not bool(opener.get("ok", false)) or (opener.get("replies", []) as Array).is_empty():
				_lounge_results.append(_lounge_row(npc, opener, {}, "opener_only"))
				_run_next_lounge_conversation()
				return
			var reply := str((opener.get("replies", []) as Array)[0])
			var turns := [
				{"speaker": "npc", "text": str(opener.get("line", ""))},
				{"speaker": "you", "text": reply},
			]
			var reply_prompt := LoungeConversationType.build_reply_prompt(
				npc,
				flavor,
				LoungeConversationType.transcript_block(turns),
				reply,
				1
			)
			LLMInterface.request_lounge_conversation_turn(
				reply_prompt,
				func(reply_result: Dictionary) -> void:
					var parsed_reply := LoungeConversationType.parse_turn(
						str(reply_result.get("inner_text", "")),
						str(npc.get("name", ""))
					)
					_lounge_results.append(_lounge_row(npc, opener, parsed_reply, reply))
					_run_next_lounge_conversation()
			)
	)


func _run_next_nova_event() -> void:
	if _nova_results.size() >= NOVA_EVENT_COUNT:
		_run_next_kaelen_turn_in()
		return
	var event := _nova_event_fixture(_nova_results.size())
	var kind := str(event.get("event_kind", "idle"))
	_nova_results.append({
		"run": _nova_results.size() + 1,
		"event_kind": kind,
		"eligible": bool(event.get("eligible", true)),
		"severity": int(event.get("severity", 0)),
		"expression": Nova.expression_for_event(kind),
		"frame_index": Nova.frame_index_for(Nova.expression_for_event(kind)),
		"notes": str(event.get("notes", "")),
	})
	_run_next_nova_event()


func _run_next_kaelen_turn_in() -> void:
	if _kaelen_results.size() >= KAELEN_TURN_IN_COUNT:
		_finish()
		return
	_item_started_msec = Time.get_ticks_msec()
	var quest := _kaelen_quest_fixture(_kaelen_results.size())
	LLMInterface.request_kaelen_reaction(
		quest,
		func(completion_line: String, abandon_line: String) -> void:
			_kaelen_results.append({
				"run": _kaelen_results.size() + 1,
				"quest_title": str(quest.get("title", "")),
				"objective_type": str(quest.get("objective", {}).get("type", "")),
				"faction": str(quest.get("faction", "")),
				"completion": completion_line,
				"abandon": abandon_line,
				"generation_duration_seconds": _elapsed_item_seconds(),
				"source": "fallback" if _is_kaelen_fallback(completion_line, abandon_line) else "llm",
			})
			_run_next_kaelen_turn_in()
	)


func _agent_offer_row(quest_data: Dictionary, requested_faction: String, is_fallback: bool) -> Dictionary:
	var objective: Dictionary = quest_data.get("objective", {})
	return {
		"run": _agent_results.size() + 1,
		"requested_faction": requested_faction,
		"objective_type": str(objective.get("type", "")),
		"giver": str(quest_data.get("agent_name", "")),
		"cause_ids": {
			"story_thread_id": str(quest_data.get("story_thread_id", "")),
			"story_beat_id": str(quest_data.get("story_beat_id", "")),
			"story_hook_ref": str(quest_data.get("story_hook_ref", "")),
			"cause_id": str(quest_data.get("cause_id", "")),
		},
		"title": str(quest_data.get("title", "")),
		"opening": str(quest_data.get("dialogue", "")),
		"player_options": _player_options(quest_data),
		"generation_duration_seconds": _elapsed_item_seconds(),
		"source": "fallback" if is_fallback else "llm",
		"validation_repairs": _validation_repairs_since(_item_started_msec),
	}


func _player_options(quest_data: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for choice in quest_data.get("choices", []):
		if not choice is Dictionary:
			continue
		var data := choice as Dictionary
		var response := str(data.get("consequence", {}).get("dialogue_response", ""))
		rows.append({
			"text": str(data.get("text", "")),
			"response": response,
			"answer_relevance": {
				"has_response": not response.strip_edges().is_empty(),
				"mentions_objective": _mentions_objective(response, quest_data),
			},
		})
	return rows


func _lounge_row(npc: Dictionary, opener: Dictionary, reply: Dictionary, selected_reply: String) -> Dictionary:
	return {
		"run": _lounge_results.size() + 1,
		"npc": npc,
		"opener": opener,
		"selected_reply": selected_reply,
		"reply_result": reply,
		"generation_duration_seconds": _elapsed_item_seconds(),
	}


func _mentions_objective(text: String, quest_data: Dictionary) -> bool:
	var objective: Dictionary = quest_data.get("objective", {})
	var lower := text.to_lower()
	for key in ["type", "target_faction", "part_name", "target_npc", "target_outpost_display"]:
		var value := str(objective.get(key, "")).strip_edges().to_lower()
		if not value.is_empty() and lower.find(value) != -1:
			return true
	return false


func _validation_repairs_since(start_msec: int) -> Array[String]:
	var repairs: Array[String] = []
	for event in GenerationDiagnostics.summary().get("recent_events", []):
		if int(event.get("time_msec", 0)) < start_msec:
			continue
		var reason := str(event.get("reason", ""))
		if reason.begins_with("validation_") or reason.find("repaired") != -1:
			repairs.append(reason)
	return repairs


func _lounge_fixture(index: int) -> Dictionary:
	var factions := ["independent", "zenith", "aurelia", "vanguard"]
	return {
		"name": "Baseline Regular %02d" % (index + 1),
		"role": "dockside regular",
		"station": "Morrow Station",
		"mood": ["wary", "tired", "amused", "bitter"][index % 4],
		"faction": factions[index % factions.size()],
		"extra": "They have heard one rumor too many and trust half of it.",
	}


func _nova_event_fixture(index: int) -> Dictionary:
	var kinds: Array[String] = ["targeted", "ambush", "nav", "arrival", "idle", "mystery", "loss", "too_powerful"]
	var kind: String = kinds[index % kinds.size()]
	return {
		"event_kind": kind,
		"eligible": true,
		"severity": Nova.Severity.THREAT if kind in ["targeted", "ambush"] else Nova.Severity.NAV,
		"notes": "scripted baseline eligibility fixture",
	}


func _kaelen_quest_fixture(index: int) -> Dictionary:
	var types: Array[String] = ["KILL_SHIPS", "DELIVER_ORE", "PICKUP_SPECIAL"]
	var objective_type: String = types[index % types.size()]
	var objective := {"type": objective_type, "reward_credits": 250 + index * 10}
	match objective_type:
		"KILL_SHIPS":
			objective["target_faction"] = "zenith"
			objective["count_required"] = 2
		"DELIVER_ORE":
			objective["amount_required"] = 18.0
		"PICKUP_SPECIAL":
			objective["part_name"] = "sealed relay core"
			objective["target_npc"] = "Mara Venn"
			objective["target_outpost_display"] = "Morrow Station"
	return {
		"title": "Baseline Turn-In %02d" % (index + 1),
		"faction": ["zenith", "aurelia", "vanguard"][index % 3],
		"agent_name": ["Director Voss", "Liaison Ryn", "Captain Dask"][index % 3],
		"objective": objective,
		"dialogue": "A routine baseline contract with just enough trouble to measure the payoff line.",
	}


func _is_kaelen_fallback(completion_line: String, abandon_line: String) -> bool:
	return LLMInterface.fallback_completion_lines.has(completion_line) \
		or LLMInterface.fallback_abandon_lines.has(abandon_line)


func _elapsed_item_seconds() -> float:
	return float(Time.get_ticks_msec() - _item_started_msec) / 1000.0


func _finish() -> void:
	_write_results_artifact()
	print("[NarrativeBaseline] Complete. Wrote %s" % RESULT_ARTIFACT_PATH)
	quit(0)


func _write_results_artifact() -> void:
	var base_dir := RESULT_ARTIFACT_PATH.get_base_dir()
	var global_dir := ProjectSettings.globalize_path(base_dir)
	if not DirAccess.dir_exists_absolute(global_dir):
		DirAccess.make_dir_recursive_absolute(global_dir)
	var file := FileAccess.open(RESULT_ARTIFACT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[NarrativeBaseline] Could not write %s" % RESULT_ARTIFACT_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify({
		"counts": {
			"agent_offers": AGENT_OFFER_COUNT,
			"lounge_conversations": LOUNGE_CONVERSATION_COUNT,
			"nova_events": NOVA_EVENT_COUNT,
			"kaelen_turn_ins": KAELEN_TURN_IN_COUNT,
		},
		"elapsed_seconds": float(Time.get_ticks_msec() - _run_started_msec) / 1000.0,
		"agent_offers": _agent_results,
		"lounge_conversations": _lounge_results,
		"nova_events": _nova_results,
		"kaelen_turn_ins": _kaelen_results,
		"worst_examples": _worst_examples(),
	}, "\t"))
	file.close()


func _worst_examples() -> Dictionary:
	return {
		"disconnected_cause": _worst_disconnected_cause(),
		"assumed_knowledge": _worst_assumed_knowledge(),
		"irrelevant_question": _worst_irrelevant_question(),
		"persona_drift": _worst_persona_drift(),
		"repeated_premise": _worst_repeated_premise(),
		"repeated_phrasing": _worst_repeated_phrasing(),
		"generic_turn_in": _worst_generic_turn_in(),
		"visible_wait": _worst_visible_wait(),
	}


func _worst_disconnected_cause() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for offer in _agent_results:
		var cause: Dictionary = offer.get("cause_ids", {})
		if str(cause.get("story_thread_id", "")).is_empty() \
				and str(cause.get("story_beat_id", "")).is_empty() \
				and str(cause.get("story_hook_ref", "")).is_empty() \
				and str(cause.get("cause_id", "")).is_empty():
			rows.append(_example("agent_offer", offer, 10, "No cause/thread/story hook ID retained."))
	return _top_five(rows)


func _worst_assumed_knowledge() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for offer in _agent_results:
		var text := ("%s %s" % [str(offer.get("title", "")), str(offer.get("opening", ""))]).to_lower()
		var score := _count_any(text, ["you know", "remember", "as discussed", "again", "the usual", "obviously"])
		if score > 0:
			rows.append(_example("agent_offer", offer, score, "Opening may assume prior player knowledge."))
	for lounge in _lounge_results:
		var opener: Dictionary = lounge.get("opener", {})
		var line := str(opener.get("line", "")).to_lower()
		var score := _count_any(line, ["you know", "remember", "again", "obviously"])
		if score > 0:
			rows.append(_example("lounge", lounge, score, "Lounge line may assume prior player knowledge."))
	return _top_five(rows)


func _worst_irrelevant_question() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for offer in _agent_results:
		for option in offer.get("player_options", []):
			if not option is Dictionary:
				continue
			var relevance: Dictionary = (option as Dictionary).get("answer_relevance", {})
			if not bool(relevance.get("mentions_objective", false)):
				rows.append(_example("agent_option", {
					"offer_title": str(offer.get("title", "")),
					"giver": str(offer.get("giver", "")),
					"option": option,
				}, 5, "Player option/answer does not mention objective anchors."))
	return _top_five(rows)


func _worst_persona_drift() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for offer in _agent_results:
		var giver := str(offer.get("giver", ""))
		var text := str(offer.get("opening", "")).to_lower()
		var score := 0
		if giver != "Broker Kaelen" and text.find("shiny") != -1:
			score += 10
		if giver == "Director Voss" and _count_any(text, ["sweetheart", "darlin", "kid"]) > 0:
			score += 5
		if score > 0:
			rows.append(_example("agent_offer", offer, score, "Speaker voice may have drifted."))
	return _top_five(rows)


func _worst_repeated_premise() -> Array[Dictionary]:
	return _worst_repeated_by_key(_agent_results, "objective_type", "Repeated objective premise.")


func _worst_repeated_phrasing() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var seen := {}
	for offer in _agent_results:
		var signature := _phrase_signature(str(offer.get("opening", "")))
		if signature.is_empty():
			continue
		seen[signature] = int(seen.get(signature, 0)) + 1
		if int(seen.get(signature, 0)) > 1:
			rows.append(_example("agent_offer", offer, int(seen.get(signature, 0)), "Opening shares a repeated phrasing signature."))
	for turn_in in _kaelen_results:
		var signature := _phrase_signature(str(turn_in.get("completion", "")))
		if signature.is_empty():
			continue
		seen[signature] = int(seen.get(signature, 0)) + 1
		if int(seen.get(signature, 0)) > 1:
			rows.append(_example("kaelen_turn_in", turn_in, int(seen.get(signature, 0)), "Turn-in shares a repeated phrasing signature."))
	return _top_five(rows)


func _worst_generic_turn_in() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for turn_in in _kaelen_results:
		var completion := str(turn_in.get("completion", "")).to_lower()
		var score := _count_any(completion, ["good work", "payment transferred", "contract complete", "job done", "pleasure doing business"])
		if score > 0 or str(turn_in.get("source", "")) == "fallback":
			rows.append(_example("kaelen_turn_in", turn_in, score + 5, "Turn-in may be generic or fallback."))
	return _top_five(rows)


func _worst_visible_wait() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for offer in _agent_results:
		var seconds := float(offer.get("generation_duration_seconds", 0.0))
		if seconds >= 1.0:
			rows.append(_example("agent_offer", offer, int(round(seconds * 100.0)), "Generation took long enough to be visible if not hidden by cache."))
	for lounge in _lounge_results:
		var seconds := float(lounge.get("generation_duration_seconds", 0.0))
		if seconds >= 1.0:
			rows.append(_example("lounge", lounge, int(round(seconds * 100.0)), "Lounge generation took long enough to be visible if click-triggered."))
	for turn_in in _kaelen_results:
		var seconds := float(turn_in.get("generation_duration_seconds", 0.0))
		if seconds >= 1.0:
			rows.append(_example("kaelen_turn_in", turn_in, int(round(seconds * 100.0)), "Kaelen reaction took long enough to be visible if not precomputed."))
	return _top_five(rows)


func _worst_repeated_by_key(rows_to_scan: Array[Dictionary], key: String, reason: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var counts := {}
	for row in rows_to_scan:
		var value := str(row.get(key, ""))
		counts[value] = int(counts.get(value, 0)) + 1
		if int(counts.get(value, 0)) > 2:
			rows.append(_example("agent_offer", row, int(counts.get(value, 0)), reason))
	return _top_five(rows)


func _example(kind: String, payload: Dictionary, score: int, reason: String) -> Dictionary:
	return {
		"kind": kind,
		"score": score,
		"reason": reason,
		"payload": payload,
	}


func _top_five(rows: Array[Dictionary]) -> Array[Dictionary]:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("score", 0)) > int(b.get("score", 0))
	)
	return rows.slice(0, mini(5, rows.size()))


func _count_any(text: String, needles: Array[String]) -> int:
	var count := 0
	for needle in needles:
		if text.find(needle) != -1:
			count += 1
	return count


func _phrase_signature(text: String) -> String:
	var words := text.to_lower().split(" ", false)
	var kept: Array[String] = []
	for word in words:
		var clean := str(word).strip_edges().strip_escapes()
		if clean.length() >= 5:
			kept.append(clean)
		if kept.size() >= 6:
			break
	return " ".join(kept)
