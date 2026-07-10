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
	var kinds := ["targeted", "ambush", "nav", "arrival", "idle", "mystery", "loss", "too_powerful"]
	var kind := kinds[index % kinds.size()]
	return {
		"event_kind": kind,
		"eligible": true,
		"severity": Nova.Severity.THREAT if kind in ["targeted", "ambush"] else Nova.Severity.NAV,
		"notes": "scripted baseline eligibility fixture",
	}


func _kaelen_quest_fixture(index: int) -> Dictionary:
	var types := ["KILL_SHIPS", "DELIVER_ORE", "PICKUP_SPECIAL"]
	var objective_type := types[index % types.size()]
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
	}, "\t"))
	file.close()
