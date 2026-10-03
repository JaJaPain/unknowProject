extends SceneTree

## Playtest 2026-10-03 finding 6: an engine sound in normal flight that
## follows the throttle, swells on boost, and is silent when docked.
##   Godot --headless --path . --script res://tests/audio/run_engine_loop_tests.gd --log-file <path>

var _failures: Array[String] = []

const FAKE_SHIP := """extends Node3D
var max_speed := 25.0
var current_speed := 0.0
var boost_timer := 0.0
var is_docked := false
var destroyed := false
"""


func _initialize() -> void:
	await process_frame
	var am: Node = root.get_node("AudioManager")
	var gs: Node = root.get_node("GlobalState")
	var script := GDScript.new()
	script.source_code = FAKE_SHIP
	script.reload()
	var ship: Node3D = script.new()
	root.add_child(ship)
	var saved_player = gs.player
	gs.player = ship
	gs.paused = false
	var idle: Array = am.engine_target()
	ship.current_speed = 25.0
	var full: Array = am.engine_target()
	ship.boost_timer = 1.0
	var boost: Array = am.engine_target()
	ship.boost_timer = 0.0
	_check(float(idle[0]) > am.ENGINE_SILENT_DB + 20.0, "a standstill still hums (%.1f dB)" % idle[0])
	_check(float(full[0]) > float(idle[0]) + 8.0 and float(full[1]) > float(idle[1]), "full speed: louder and higher")
	_check(float(boost[0]) > float(full[0]) and float(boost[1]) > float(full[1]), "boost swells on top")
	ship.is_docked = true
	_check(float(am.engine_target()[0]) == am.ENGINE_SILENT_DB, "docked: silent")
	ship.is_docked = false
	# Playing, looped, and it never jumps.
	var last: float = am._engine_db
	var biggest := 0.0
	for i in 90:
		await process_frame
		# Loudness, not dB: a dB step near silence is inaudible.
		biggest = maxf(biggest, absf(db_to_linear(am._engine_db) - db_to_linear(last)))
		last = am._engine_db
	_check(am.engine_player != null and am.engine_player.playing, "the loop plays in flight")
	_check(am.engine_player.stream is AudioStreamWAV and (am.engine_player.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "and loops")
	_check(am.engine_player.bus == "SFX", "on the SFX bus (the SFX slider and dialogue duck apply)")
	_check(biggest < 0.01, "the level glides (largest loudness step %.4f)" % biggest)
	gs.player = saved_player
	ship.queue_free()
	if _failures.is_empty():
		print("[PASS] Engine loop")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
