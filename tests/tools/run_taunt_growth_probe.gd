extends SceneTree

# Exercises the real background refill against the live model: repeatedly fills
# whichever cause is leanest, then reports pool sizes. This is what turns the
# rotation from a few authored lines into a pool the player has to work at to
# exhaust, so it needs to be watched actually growing, not assumed.
#
#   ... --script res://tests/tools/run_taunt_growth_probe.gd -- \
#       --llm-live-fire --rounds=8

const CauseType := preload("res://scripts/combat/TauntCause.gd")

var _cm: Node = null
var _llm: Node = null
var _rounds := 8
var _done := 0


func _initialize() -> void:
	await process_frame
	_cm = get_root().get_node_or_null("CombatManager")
	_llm = get_root().get_node_or_null("LLMInterface")
	if _cm == null or _llm == null:
		push_error("[TauntGrowth] Autoloads unavailable.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rounds="):
			_rounds = clampi(int(arg.trim_prefix("--rounds=")), 1, 40)
	while not bool(_llm.get("small_model_verified")):
		await process_frame
	_report("before")
	_next()


func _next() -> void:
	if _done >= _rounds:
		_report("after")
		var total := _total()
		print("[TauntGrowth] %d refill round(s) took the pools to %d lines." % [_rounds, total])
		# Each round asks for 8 lines; anything close to zero means refill is
		# not actually reaching the pools.
		var passed := total > _initial_total
		print("[PASS] Taunt growth probe" if passed else "[FAIL] Taunt growth probe")
		quit(0 if passed else 1)
		return
	_done += 1
	var cause: String = _cm.call("_leanest_cause")
	_cm.call("_request_cause_refill", cause)
	# The refill guard is a single in-flight flag; wait for it to clear.
	await _wait_for_idle()
	_next()


func _wait_for_idle() -> void:
	var waited := 0
	while bool(_cm.get("_general_taunt_fetch_in_flight")) and waited < 1200:
		waited += 1
		await process_frame
	# One extra frame so the callback's pool append lands before the next read.
	await process_frame


var _initial_total := 0


func _total() -> int:
	var total := 0
	for cause in CauseType.ALL:
		total += ((_cm.get("_cause_pools") as Dictionary).get(cause, []) as Array).size()
	return total


func _report(label: String) -> void:
	var total := _total()
	if label == "before":
		_initial_total = total
	print("[TauntGrowth] pools %s refill (total %d):" % [label, total])
	for cause in CauseType.ALL:
		print("    %-20s %d" % [
			cause, ((_cm.get("_cause_pools") as Dictionary).get(cause, []) as Array).size(),
		])
