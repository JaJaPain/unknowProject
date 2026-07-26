extends SceneTree

# Phase 9 real-model gate.  This is intentionally separate from deterministic
# tests: it records the complete writer/reviewer protocol for human review.

const RESULT_ARTIFACT_PATH_FORMAT := "res://logs/lounge_bundle_live_fire_%02d.json"

var _rows: Array[Dictionary] = []
var _started_msec := 0
var _item_started_msec := 0
var _llm: Node = null
var _convo: GDScript = null
var _fixture_index := 0
var _run_count := 1


func _initialize() -> void:
	_started_msec = Time.get_ticks_msec()
	await process_frame
	_llm = get_root().get_node_or_null("LLMInterface")
	if _llm == null:
		push_error("[LoungeLiveFire] LLMInterface autoload is unavailable.")
		quit(1)
		return
	# The game is launched with --llm-live-fire, which suppresses unrelated
	# startup refills. Wait for its ordinary readiness probe before the first
	# writer request so this tool never races a cold model.
	while not bool(_llm.get("small_model_verified")):
		await process_frame
	# Runtime loading preserves autoload ordering in standalone headless tools.
	_convo = load("res://scripts/story/LoungeConversation.gd")
	if _convo == null:
		push_error("[LoungeLiveFire] LoungeConversation could not load.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture-index="):
			_fixture_index = maxi(0, int(arg.trim_prefix("--fixture-index=")))
		elif arg.begins_with("--count="):
			_run_count = clampi(int(arg.trim_prefix("--count=")), 1, 20)
	print("[LoungeLiveFire] Starting %d serial fixture(s) at %d." % [_run_count, _fixture_index + 1])
	_run_next()


func _run_next() -> void:
	if _rows.size() >= _run_count:
		_finish()
		return
	_item_started_msec = Time.get_ticks_msec()
	var fixture := _fixture(_fixture_index + _rows.size())
	var npc: Dictionary = fixture.get("npc", {})
	var intents: Array = fixture.get("intents", [])
	var prompt: String = _convo.build_bundle_prompt(
		npc, str(fixture.get("flavor", "")), intents
	)
	_llm.call(
		"request_lounge_exchange_bundle",
		prompt,
		func(writer_result: Dictionary) -> void:
			_on_writer_result(fixture, prompt, writer_result)
	)


func _on_writer_result(
	fixture: Dictionary,
	prompt: String,
	writer_result: Dictionary,
	retry_count: int = 0
) -> void:
	var npc: Dictionary = fixture.get("npc", {})
	var intents: Array = fixture.get("intents", [])
	var parsed: Dictionary = {"ok": false, "reason": str(writer_result.get("reason", "transport_failed"))}
	if bool(writer_result.get("ok", false)):
		parsed = _convo.parse_bundle(
			str(writer_result.get("inner_text", "")), str(npc.get("name", "")), intents.size()
		)
		parsed = _convo.validate_bundle_answers(parsed, intents)
	var row := _base_row(fixture, prompt, writer_result, parsed)
	if not bool(parsed.get("ok", false)):
		if retry_count < 1:
			_llm.call(
				"request_lounge_exchange_bundle",
				prompt + "\nYour prior response was structurally invalid. Return every required JSON field, with no prose before or after the object.",
				func(retry_result: Dictionary) -> void:
					_on_writer_result(fixture, prompt, retry_result, retry_count + 1)
			)
			return
		row["final_status"] = "writer_rejected"
		_rows.append(row)
		_run_next()
		return
	var review_prompt: String = _convo.build_bundle_review_prompt(
		str(npc.get("name", "")), intents, parsed
	)
	row["review_prompt"] = review_prompt
	_llm.call(
		"request_lounge_exchange_bundle_review",
		review_prompt,
		func(review_result: Dictionary) -> void:
			row["review_result"] = review_result
			row["review_approved"] = bool(review_result.get("ok", false)) \
				and _convo.parse_bundle_review(str(review_result.get("inner_text", "")))
			row["final_status"] = "accepted" if bool(row["review_approved"]) else "review_rejected"
			row["duration_seconds"] = _elapsed_seconds()
			_rows.append(row)
			_run_next()
	)


func _base_row(fixture: Dictionary, prompt: String, writer_result: Dictionary, parsed: Dictionary) -> Dictionary:
	return {
		"run": _rows.size() + 1,
		"fixture": str(fixture.get("label", "")),
		"relationship": str(fixture.get("relationship", "")),
		"npc": fixture.get("npc", {}),
		"intents": fixture.get("intents", []),
		"writer_prompt": prompt,
		"writer_result": writer_result,
		"parsed_bundle": parsed,
		"duration_seconds": _elapsed_seconds(),
	}


func _fixture(index: int) -> Dictionary:
	var situations := [
		["convoy delay", "convoy", "Why are the convoy delays getting worse?", "Traffic control is marking the convoy delays as unscheduled."],
		["fabrication shortage", "shortage", "What is the fabrication shortage doing to this station?", "The fabrication shops are rationing parts."],
		["patrol inspections", "patrol", "Why are patrol inspections stopping freighters?", "Patrols have been holding cargo crews for paperwork."],
		["relay outage", "relay", "What caused the relay outage near the gate?", "The relay went dark just before the last departure."],
		["fuel rationing", "fuel", "Who decided to ration fuel here?", "Fuel allotments changed before the station announced it."],
	]
	var roles := ["bartender", "dock controller", "freight clerk", "salvage broker"]
	var relationships := ["stranger", "neutral", "warm", "hostile"]
	var situation: Array = situations[index % situations.size()]
	var relationship: String = relationships[index % relationships.size()]
	var name := "Live Fire %s %02d" % [roles[index % roles.size()].capitalize(), index + 1]
	var extra := "%s contact. " % relationship.capitalize()
	if relationship == "warm":
		extra += "Last player stance: warm. The pilot helped with a small problem before; acknowledge it incidentally, never recap it."
	elif relationship == "hostile":
		extra += "Last player stance: pushback. The speaker remains professional but guarded."
	else:
		extra += "The pilot has not earned a long explanation."
	return {
		"label": "%s / %s" % [relationship, str(situation[0])],
		"relationship": relationship,
		"npc": {
			"name": name, "role": roles[index % roles.size()], "station": "Morrow Station",
			"mood": ["tired", "wary", "amused", "bitter"][index % 4],
			"faction": ["independent", "zenith", "aurelia", "vanguard"][index % 4], "extra": extra,
		},
		"flavor": "Campaign tone: dry, wary, and practical. Known local fact: %s" % str(situation[3]),
		"intents": [
			{"id": "ask_%s" % str(situation[1]), "text": str(situation[2]), "anchors": [str(situation[1])]},
			{"id": "ask_personal_read", "text": "Does that change how you work?", "anchors": []},
		],
	}


func _elapsed_seconds() -> float:
	return float(Time.get_ticks_msec() - _item_started_msec) / 1000.0


func _finish() -> void:
	var accepted := 0
	for row in _rows:
		if str(row.get("final_status", "")) == "accepted":
			accepted += 1
	var artifact := {
		"purpose": "Phase 9 reviewed real-model lounge-bundle gate",
		"completed_at_utc": Time.get_datetime_string_from_system(true, true),
		"count": _rows.size(), "accepted": accepted,
		"acceptance_rate": float(accepted) / float(maxi(1, _rows.size())),
		"required_rate": 0.95,
		"elapsed_seconds": float(Time.get_ticks_msec() - _started_msec) / 1000.0,
		"rows": _rows,
	}
	var artifact_path := RESULT_ARTIFACT_PATH_FORMAT % (_fixture_index + 1)
	var global_path := ProjectSettings.globalize_path(artifact_path)
	DirAccess.make_dir_recursive_absolute(global_path.get_base_dir())
	var file := FileAccess.open(artifact_path, FileAccess.WRITE)
	if file == null:
		push_error("[LoungeLiveFire] Could not write %s" % artifact_path)
		quit(1)
		return
	file.store_string(JSON.stringify(artifact, "\t"))
	file.close()
	print("[LoungeLiveFire] %d/%d accepted (%.1f%%). Wrote %s" % [accepted, _rows.size(), artifact["acceptance_rate"] * 100.0, artifact_path])
	quit(0 if float(artifact["acceptance_rate"]) >= 0.95 else 1)
