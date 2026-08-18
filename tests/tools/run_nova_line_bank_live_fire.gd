extends SceneTree

# Phase 8B real-model gate for N.O.V.A. line-bank batches.
#
# Runs the EXACT two seed batches GameRoot dispatches on campaign load
# (movement/arrival, then combat/hull/welcome/dock) against the live small
# model, and reports what the parser actually accepted. Deterministic tests
# cover the parser; this covers the prompt surviving contact with qwen3.
#
#   Godot ... --script res://tests/tools/run_nova_line_bank_live_fire.gd \
#     --log-file .tmp_godot_user\test_logs\nova_bank_live.log -- \
#     --llm-live-fire --rounds=2

const RESULT_ARTIFACT_PATH := "res://logs/nova_line_bank_live_fire.json"
const REQUIRED_ACCEPT_RATE := 0.9

var _llm: Node = null
var _rows: Array[Dictionary] = []
var _started_msec := 0
var _batch_started_msec := 0
var _rounds := 1
var _queue: Array[Dictionary] = []


func _initialize() -> void:
	_started_msec = Time.get_ticks_msec()
	await process_frame
	_llm = get_root().get_node_or_null("LLMInterface")
	if _llm == null:
		push_error("[NovaBankLiveFire] LLMInterface autoload is unavailable.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rounds="):
			_rounds = clampi(int(arg.trim_prefix("--rounds=")), 1, 10)
	print("[NovaBankLiveFire] Waiting for the small model to verify...")
	while not bool(_llm.get("small_model_verified")):
		await process_frame
	print("[NovaBankLiveFire] Small model verified. Running %d round(s)." % _rounds)
	for round_index in range(_rounds):
		_queue.append({"round": round_index + 1, "batch": "movement_arrival", "fields": _movement_fields()})
		_queue.append({"round": round_index + 1, "batch": "combat_dock", "fields": _combat_fields()})
	_run_next()


# Mirrors GameRoot._nova_refill_batch_fields().
func _movement_fields() -> Array:
	return [
		{"category": "boost_again_quickly", "count": 1},
		{"category": "changed_mind_again", "count": 1},
		{"category": "returned_to_same_station", "count": 1},
		{"category": "clean_long_transit", "count": 1},
		{"category": "rough_arrival", "count": 1},
		{"category": "system_arrival", "count": 3},
	]


# Mirrors GameRoot._nova_seed_combat_batch_fields().
func _combat_fields() -> Array:
	return [
		{"category": "combat_victory_clean", "count": 2},
		{"category": "combat_victory_battered", "count": 2},
		{"category": "combat_retreat", "count": 1},
		{"category": "hull_critical", "count": 2},
		{"category": "welcome_back", "count": 1},
		{"category": "docked", "count": 1},
	]


# The same context shape GameRoot._nova_line_bank_generation_context() builds,
# assembled from live autoloads where they exist and a representative fixture
# where a campaign has not been loaded (this tool boots no save).
func _context() -> Dictionary:
	var context := {}
	var nova := get_root().get_node_or_null("Nova")
	context["persona"] = str(nova.get("PERSONA")) if nova != null else ""
	if str(context["persona"]).strip_edges().is_empty():
		context["persona"] = str(load("res://scripts/ai/Nova.gd").PERSONA)
	var soul := load("res://scripts/story/FixedCastSoulRegistry.gd")
	context["fixed_cast_soul"] = soul.prompt_block(
		"nova", "baseline", "arrival", "neutral", "", [] as Array[String]
	)
	context["campaign_quirk"] = "counts the captain's course changes out loud"
	context["system_tone"] = "dry, wary, and practical"
	context["known_facts"] = ["The ship is currently in the Kepler Reach system."]
	context["recent_events"] = [
		"boosted twice in under a minute",
		"retargeted the autopilot mid-burn",
		"docked at the station it undocked from",
	]
	return context


func _run_next() -> void:
	if _queue.is_empty():
		_finish()
		return
	var job: Dictionary = _queue.pop_front()
	_batch_started_msec = Time.get_ticks_msec()
	var labels: Array = _llm.call("nova_line_bank_labels", job.get("fields", []))
	_llm.call(
		"request_nova_line_bank_batch",
		job.get("fields", []),
		_context(),
		func(result: Dictionary) -> void:
			_on_batch_result(job, labels, result)
	)


func _on_batch_result(job: Dictionary, labels: Array, result: Dictionary) -> void:
	var lines: Array = result.get("lines", []) if result.get("lines", []) is Array else []
	var rejected: Array = result.get("rejected", []) if result.get("rejected", []) is Array else []
	var row := {
		"round": int(job.get("round", 0)),
		"batch": str(job.get("batch", "")),
		"expected_labels": labels.size(),
		"ok": bool(result.get("ok", false)),
		"reason": str(result.get("reason", "")),
		"accepted": lines.size(),
		"rejected": rejected,
		"lines": lines,
		"duration_seconds": float(Time.get_ticks_msec() - _batch_started_msec) / 1000.0,
	}
	_rows.append(row)
	print("[NovaBankLiveFire] round %d %s: %s %d/%d accepted in %.1fs%s" % [
		row["round"], row["batch"],
		("OK" if row["ok"] else "FAIL(%s)" % row["reason"]),
		row["accepted"], row["expected_labels"], row["duration_seconds"],
		("" if rejected.is_empty() else "  rejected=%s" % JSON.stringify(rejected)),
	])
	for line in lines:
		print("    [%s] %s" % [str((line as Dictionary).get("kind", "")), str((line as Dictionary).get("text", ""))])
	_run_next()


func _finish() -> void:
	var expected_total := 0
	var accepted_total := 0
	var failed_batches := 0
	var reason_counts: Dictionary = {}
	for row in _rows:
		expected_total += int(row.get("expected_labels", 0))
		accepted_total += int(row.get("accepted", 0))
		if not bool(row.get("ok", false)):
			failed_batches += 1
			var reason := str(row.get("reason", "unknown"))
			reason_counts[reason] = int(reason_counts.get(reason, 0)) + 1
		for rejection in (row.get("rejected", []) as Array):
			var why := str((rejection as Dictionary).get("reason", "unknown"))
			reason_counts[why] = int(reason_counts.get(why, 0)) + 1
	var accept_rate := float(accepted_total) / float(maxi(1, expected_total))
	var artifact := {
		"purpose": "Phase 8B real-model N.O.V.A. line-bank batch gate",
		"completed_at_utc": Time.get_datetime_string_from_system(true, true),
		"batches": _rows.size(),
		"failed_batches": failed_batches,
		"expected_lines": expected_total,
		"accepted_lines": accepted_total,
		"accept_rate": accept_rate,
		"required_rate": REQUIRED_ACCEPT_RATE,
		"reason_counts": reason_counts,
		"elapsed_seconds": float(Time.get_ticks_msec() - _started_msec) / 1000.0,
		"rows": _rows,
	}
	var global_path := ProjectSettings.globalize_path(RESULT_ARTIFACT_PATH)
	DirAccess.make_dir_recursive_absolute(global_path.get_base_dir())
	var file := FileAccess.open(RESULT_ARTIFACT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(artifact, "\t"))
		file.close()
	print("[NovaBankLiveFire] %d/%d lines accepted (%.1f%%), %d batch failure(s). Wrote %s" % [
		accepted_total, expected_total, accept_rate * 100.0, failed_batches, RESULT_ARTIFACT_PATH,
	])
	if not reason_counts.is_empty():
		print("[NovaBankLiveFire] rejection reasons: %s" % JSON.stringify(reason_counts))
	var passed := failed_batches == 0 and accept_rate >= REQUIRED_ACCEPT_RATE
	print("[PASS] N.O.V.A. line-bank live fire" if passed else "[FAIL] N.O.V.A. line-bank live fire")
	quit(0 if passed else 1)
