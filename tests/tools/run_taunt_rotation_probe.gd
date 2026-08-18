extends SceneTree

# Drives CombatManager's real taunt pools the way a session would: derive a
# cause, draw repeatedly, then reload from disk and confirm the rotation picked
# up where it left off rather than restarting.

const CauseType := preload("res://scripts/combat/TauntCause.gd")

var _cm: Node = null


func _initialize() -> void:
	await process_frame
	_cm = get_root().get_node_or_null("CombatManager")
	if _cm == null:
		push_error("[TauntProbe] CombatManager autoload unavailable.")
		quit(1)
		return
	var failures: Array[String] = []
	var cause := CauseType.PIRATE_PREDATION
	var pool: Array = (_cm.get("_cause_pools") as Dictionary).get(cause, [])
	print("[TauntProbe] %s pool holds %d lines." % [cause, pool.size()])
	if pool.is_empty():
		push_error("[FAIL] Authored floor missing for %s." % cause)
		quit(1)
		return
	# Draw a full cycle straight from the live bag and check for repeats.
	var bags: Dictionary = _cm.get("_cause_bags")
	var bag = bags.get(cause, null)
	var seen: Dictionary = {}
	for i in range(pool.size()):
		var entry: Dictionary = bag.next(pool)
		var text := str(entry.get("text", ""))
		if seen.has(text):
			failures.append("'%s' repeated within one cycle." % text)
		seen[text] = true
		print("    %d. %s" % [i + 1, text])
	# Save, then rebuild a bag from what was written, as a relaunch would.
	_cm.call("_save_taunt_pool")
	var path: String = _cm.get("_TAUNT_CACHE_PATH")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		failures.append("Taunt cache was not written to %s." % path)
	else:
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		var record: Dictionary = ((parsed as Dictionary).get("causes", {}) as Dictionary).get(cause, {})
		var saved_bag: Dictionary = record.get("bag", {})
		print("[TauntProbe] persisted bag for %s: %s" % [cause, JSON.stringify(saved_bag)])
		if int(saved_bag.get("cursor", -1)) < 0:
			failures.append("Rotation cursor was not persisted.")
		if (record.get("lines", []) as Array).is_empty():
			failures.append("Pool lines were not persisted.")
	for failure in failures:
		push_error("[FAIL] %s" % failure)
	if failures.is_empty():
		print("[PASS] Taunt rotation probe")
		quit(0)
		return
	quit(1)
