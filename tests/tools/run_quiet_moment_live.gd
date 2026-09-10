extends SceneTree

# Live end-to-end check: real model, real gates, real anatomy correction.
#
# Serial by construction — one request at a time, each waiting on the last.
# Run alone, with a unique --log-file (see CLAUDE.md).
#
#   Godot --headless --path . --script res://tests/tools/run_quiet_moment_live.gd \
#         --log-file <abs>/qm_live.log -- --per-beat=2

const Director := preload("res://scripts/story/QuietMomentDirector.gd")
const Beats := preload("res://scripts/story/QuietMomentBeats.gd")

var _director: Node = null
var _queue: Array[String] = []
var _per_beat := 2
var _served: Array[Dictionary] = []
var _silences: Array[Dictionary] = []
var _pending := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--per-beat="):
			_per_beat = clampi(int(arg.trim_prefix("--per-beat=")), 1, 10)

	await process_frame
	var llm := get_root().get_node_or_null("LLMInterface")
	if llm == null:
		push_error("[QuietMomentLive] LLMInterface autoload unavailable.")
		quit(1)
		return
	var deadline := Time.get_ticks_msec() + 90000
	while not bool(llm.get("small_model_verified")) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not bool(llm.get("small_model_verified")):
		push_error("[QuietMomentLive] Small model never became ready.")
		quit(1)
		return

	_director = Director.new()
	get_root().add_child(_director)
	_director.quiet_moment_ready.connect(_on_ready)
	_director.quiet_moment_silent.connect(_on_silent)

	for beat_id in Beats.beat_ids():
		for i in _per_beat:
			_queue.append(str(beat_id))
	print("[QuietMomentLive] %d requests across %d beats"
		% [_queue.size(), Beats.beat_ids().size()])
	_next()


func _next() -> void:
	if _queue.is_empty():
		_finish()
		return
	var beat_id: String = _queue.pop_front()
	_pending = true
	# ignore_cooldown: this is a soak test, not a playthrough. Firing policy
	# is exercised by the director's own unit tests.
	if not _director.try_fire(beat_id, {"ignore_cooldown": true}):
		_pending = false
		_silences.append({"beat_id": beat_id, "reasons": ["declined_before_request"]})
		print("  -- %s (declined)" % beat_id)
		_next()


func _on_ready(speaker: String, beat_id: String, line: String) -> void:
	_served.append({"speaker": speaker, "beat_id": beat_id, "line": line})
	print("  %-28s %s" % [beat_id, line])
	_pending = false
	_next()


func _on_silent(beat_id: String, reasons: Array) -> void:
	_silences.append({"beat_id": beat_id, "reasons": reasons})
	print("  -- %-25s silent %s" % [beat_id, reasons])
	_pending = false
	_next()


func _finish() -> void:
	var total := _served.size() + _silences.size()
	var openers := {}
	var lines := {}
	for row in _served:
		lines[str(row["line"])] = true
		var words: PackedStringArray = str(row["line"]).to_lower().split(" ", false)
		if words.size() >= 2:
			openers["%s %s" % [words[0], words[1]]] = true

	print("\n[QuietMomentLive] served %d/%d, silent %d (%.0f%%)"
		% [_served.size(), total, _silences.size(),
		100.0 * float(_silences.size()) / maxf(1.0, float(total))])
	print("  exact duplicates: %d" % [_served.size() - lines.size()])
	print("  distinct openers: %d/%d" % [openers.size(), _served.size()])

	var artifact := {
		"tool": "quiet_moment_live",
		"run_at_unix": Time.get_unix_time_from_system(),
		"served": _served,
		"silences": _silences,
	}
	var file := FileAccess.open("res://logs/quiet_moment_live.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(artifact, "\t"))
		file.close()

	# A duplicate is a hard failure: it means the recency gate is not working,
	# which is the whole freshness guarantee.
	if _served.size() != lines.size():
		print("[FAIL] duplicate line served")
		quit(1)
		return
	if _served.is_empty():
		print("[FAIL] nothing served at all")
		quit(1)
		return
	print("[PASS] Quiet moment live")
	quit(0)
