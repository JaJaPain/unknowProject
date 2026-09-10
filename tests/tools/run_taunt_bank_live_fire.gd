extends SceneTree

# Real-model gate for cause-keyed enemy taunts. Prints every line under its
# cause so the output can be READ as dialogue -- the whole point of the feature
# is that a line fits the reason the fight started, and no pass count can tell
# you that.
#
#   Godot ... --script res://tests/tools/run_taunt_bank_live_fire.gd \
#     --log-file .tmp_godot_user\test_logs\taunt_live.log -- \
#     --llm-live-fire --count=8

const CauseType := preload("res://scripts/combat/TauntCause.gd")
const RESULT_ARTIFACT_PATH := "res://logs/taunt_bank_live_fire.json"

var _llm: Node = null
var _rows: Array[Dictionary] = []
var _queue: Array[String] = []
var _count := 6
var _started_msec := 0
var _batch_started_msec := 0


func _initialize() -> void:
	_started_msec = Time.get_ticks_msec()
	await process_frame
	_llm = get_root().get_node_or_null("LLMInterface")
	if _llm == null:
		push_error("[TauntLiveFire] LLMInterface autoload unavailable.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			_count = clampi(int(arg.trim_prefix("--count=")), 1, 20)
	print("[TauntLiveFire] Waiting for the small model...")
	while not bool(_llm.get("small_model_verified")):
		await process_frame
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cause="):
			only = arg.trim_prefix("--cause=").strip_edges()
	for cause in CauseType.ALL:
		if only.is_empty() or str(cause) == only:
			_queue.append(str(cause))
	print("[TauntLiveFire] Generating %d lines for each of %d causes." % [_count, _queue.size()])
	_run_next()


func _context_for(cause: String) -> Dictionary:
	var context := {"faction_label": "the Vanguard", "archetype": "gunner"}
	match cause:
		CauseType.PIRATE_PREDATION:
			context["faction_label"] = "a scavenger crew with no flag"
		CauseType.REPUTATION_GRUDGE:
			context["faction_label"] = "the Zenith Combine"
			context["facts"] = ["Their standing with this pilot is: sworn enemy."]
		CauseType.CODE_ENFORCEMENT:
			context["faction_label"] = "the Aurelia mining authority"
			context["facts"] = [
				"The pilot owes an unpaid fine of 500 credits for mining a belt without a permit.",
			]
		CauseType.CONTRACT_HIT:
			context["faction_label"] = "a small independent outfit"
	return context


func _run_next() -> void:
	if _queue.is_empty():
		_finish()
		return
	var cause: String = _queue.pop_front()
	_batch_started_msec = Time.get_ticks_msec()
	_llm.call(
		"request_taunt_bank_batch",
		cause,
		_count,
		_context_for(cause),
		func(result: Dictionary) -> void:
			_on_result(cause, result)
	)


func _on_result(cause: String, result: Dictionary) -> void:
	var lines: Array = result.get("lines", []) if result.get("lines", []) is Array else []
	var rejected: Array = result.get("rejected", []) if result.get("rejected", []) is Array else []
	_rows.append({
		"cause": cause,
		"situation": CauseType.describe(cause),
		"ok": bool(result.get("ok", false)),
		"reason": str(result.get("reason", "")),
		"requested": _count,
		"accepted": lines.size(),
		"lines": lines,
		"rejected": rejected,
		"duration_seconds": float(Time.get_ticks_msec() - _batch_started_msec) / 1000.0,
	})
	print("\n=== %s (%s) — %s %d/%d in %.1fs" % [
		cause.to_upper(), CauseType.describe(cause),
		("OK" if bool(result.get("ok", false)) else "FAIL(%s)" % str(result.get("reason", ""))),
		lines.size(), _count,
		float(Time.get_ticks_msec() - _batch_started_msec) / 1000.0,
	])
	for line in lines:
		print("    %s" % str(line))
	if not rejected.is_empty():
		print("    rejected: %s" % JSON.stringify(rejected))
	if result.has("stop_reason"):
		print("    stop_reason=%s eval_count=%d" % [
			str(result.get("stop_reason", "")), int(result.get("eval_count", 0)),
		])
	_run_next()


func _finish() -> void:
	var requested := 0
	var accepted := 0
	var failed := 0
	var reason_counts: Dictionary = {}
	for row in _rows:
		requested += int(row.get("requested", 0))
		accepted += int(row.get("accepted", 0))
		if not bool(row.get("ok", false)):
			failed += 1
			var why := str(row.get("reason", "unknown"))
			reason_counts[why] = int(reason_counts.get(why, 0)) + 1
		for rejection in (row.get("rejected", []) as Array):
			var reason := str((rejection as Dictionary).get("reason", "unknown"))
			reason_counts[reason] = int(reason_counts.get(reason, 0)) + 1
	var artifact := {
		"purpose": "Cause-keyed enemy taunt real-model gate",
		"completed_at_utc": Time.get_datetime_string_from_system(true, true),
		"causes": _rows.size(),
		"failed_causes": failed,
		"requested_lines": requested,
		"accepted_lines": accepted,
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
	print("\n[TauntLiveFire] %d/%d lines accepted across %d causes, %d cause failure(s)." % [
		accepted, requested, _rows.size(), failed,
	])
	if not reason_counts.is_empty():
		print("[TauntLiveFire] reasons: %s" % JSON.stringify(reason_counts))
	var passed := failed == 0 and accepted >= int(float(requested) * 0.6)
	print("[PASS] Taunt bank live fire" if passed else "[FAIL] Taunt bank live fire")
	quit(0 if passed else 1)
