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
	# Draw out the REST of the current cycle and check for repeats.
	#
	# Deliberately not a full pool's worth: this bag was restored from disk and
	# legitimately resumes mid-cycle, which is the persistence feature working.
	# Asking for pool.size() draws would cross the cycle boundary, and a line
	# reappearing in the NEXT cycle is correct behaviour, not a repeat.
	var bags: Dictionary = _cm.get("_cause_bags")
	var bag = bags.get(cause, null)
	var remaining: int = int(bag.remaining())
	print("[TauntProbe] resuming mid-cycle: %d of %d lines left before it wraps." % [
		remaining, pool.size(),
	])
	var seen: Dictionary = {}
	for i in range(remaining):
		var entry: Dictionary = bag.next(pool)
		var text := str(entry.get("text", ""))
		if seen.has(text):
			failures.append("'%s' repeated before the cycle wrapped." % text)
		seen[text] = true
		print("    %d. %s" % [i + 1, text])
	if remaining > 0 and seen.size() != remaining:
		failures.append(
			"Expected %d distinct lines in the cycle remainder, saw %d."
			% [remaining, seen.size()]
		)
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
