extends SceneTree

const CauseType := preload("res://scripts/combat/TauntCause.gd")
const BagType := preload("res://scripts/combat/TauntBag.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	# A compile failure in either script yields null instances whose method
	# calls merely log errors, which once let this suite print [PASS] while
	# nothing had actually run. Fail loudly instead.
	if CauseType == null or BagType == null or BagType.new(1) == null:
		push_error("[FAIL] Taunt scripts failed to load -- see compile errors above.")
		quit(1)
		return
	_test_cause_derivation()
	_test_cause_briefs()
	_test_bag_is_exhaustive()
	_test_bag_survives_restart()
	_test_bag_growth()
	_test_exhaustive_after_growth()
	_test_authored_lines_load_from_data()
	_test_delivery_overrides()

	if _failures.is_empty():
		print("[PASS] Taunt cause + bag tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


# Every cause must come from state the game actually tracks, and the most
# specific provable reason has to win -- an enforcement ship is also a faction
# ship, and a contract target is also a stranger who just got shot.
func _test_cause_derivation() -> void:
	_expect(
		CauseType.derive(true, {"is_quest_target": true}) == CauseType.CONTRACT_HIT,
		"Shooting a marked target is a contract hit."
	)
	_expect(
		CauseType.derive(true, {"is_minor_faction": true}) == CauseType.PREEMPTIVE_STRIKE,
		"Shooting an already-hostile pirate is pre-emptive, not unprovoked."
	)
	_expect(
		CauseType.derive(true, {"reputation": -40.0}) == CauseType.PREEMPTIVE_STRIKE,
		"Shooting a faction that already hates you is pre-emptive."
	)
	_expect(
		CauseType.derive(true, {"reputation": 5.0}) == CauseType.UNPROVOKED,
		"Shooting a neutral is unprovoked."
	)
	# Contract beats hostility: the player took a job on this specific ship.
	_expect(
		CauseType.derive(true, {"is_quest_target": true, "is_minor_faction": true}) \
			== CauseType.CONTRACT_HIT,
		"A marked pirate is still a contract hit."
	)
	_expect(
		CauseType.derive(false, {"is_code_enforcement": true, "is_minor_faction": true}) \
			== CauseType.CODE_ENFORCEMENT,
		"Enforcement outranks faction classification."
	)
	_expect(
		CauseType.derive(false, {"is_reinforcement": true, "reputation": -80.0}) \
			== CauseType.REINFORCEMENT,
		"Being called in as backup outranks a standing grudge."
	)
	_expect(
		CauseType.derive(false, {"is_minor_faction": true}) == CauseType.PIRATE_PREDATION,
		"An unprompted pirate attack is predation."
	)
	_expect(
		CauseType.derive(false, {"reputation": -40.0}) == CauseType.REPUTATION_GRUDGE,
		"A major faction with bad standing attacks over reputation."
	)
	# The honest default: they started it and we cannot prove why, so the
	# speaker must not claim a specific grievance.
	_expect(
		CauseType.derive(false, {"reputation": 0.0}) == CauseType.OPPORTUNIST,
		"No provable reason must fall to OPPORTUNIST, not an invented motive."
	)
	# Just above the hostility threshold is not a grudge.
	_expect(
		CauseType.derive(false, {"reputation": -5.0}) == CauseType.OPPORTUNIST,
		"Mild dislike is not a standing grudge."
	)


func _test_cause_briefs() -> void:
	for cause in CauseType.ALL:
		var data: Dictionary = CauseType.brief(cause)
		_expect(
			not str(data.get("situation", "")).is_empty() \
				and not str(data.get("register", "")).is_empty(),
			"Cause %s must carry a situation and a register." % cause
		)
		var block: String = CauseType.prompt_block(cause)
		_expect(
			block.contains("WHY THIS FIGHT IS HAPPENING"),
			"Cause %s prompt block is malformed." % cause
		)
	# An unknown cause must degrade to the one that claims nothing, never crash.
	_expect(
		CauseType.describe("nonsense_cause") == CauseType.describe(CauseType.OPPORTUNIST),
		"An unknown cause must fall back to OPPORTUNIST."
	)
	# Cause-specific true facts reach the prompt so lines cite something real
	# instead of inventing a grievance.
	var with_facts: String = CauseType.prompt_block(
		CauseType.REPUTATION_GRUDGE, {"facts": ["Their standing with the pilot is: sworn enemy."]}
	)
	_expect(
		with_facts.contains("sworn enemy"),
		"Supplied facts must reach the prompt block."
	)


# The whole point of the bag: a full pass over the pool before anything repeats.
func _test_bag_is_exhaustive() -> void:
	var pool := _pool(40)
	var bag := BagType.new(pool.size())
	var seen: Dictionary = {}
	for i in range(pool.size()):
		var entry: Dictionary = bag.next(pool)
		var text := str(entry.get("text", ""))
		_expect(
			not seen.has(text),
			"Line '%s' repeated before the pool was exhausted (draw %d)." % [text, i + 1]
		)
		seen[text] = true
	_expect(
		seen.size() == pool.size(),
		"A full cycle should cover every line, saw %d of %d." % [seen.size(), pool.size()]
	)


# Quitting mid-cycle must not restart the rotation. This is the failure the
# player would actually notice: relaunch, hear the same opening taunt again.
func _test_bag_survives_restart() -> void:
	var pool := _pool(40)
	var bag := BagType.new(pool.size())
	var before: Array[String] = []
	for i in range(15):
		before.append(str(bag.next(pool).get("text", "")))
	# Simulate a save, a quit, and a relaunch.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(bag.to_dict()))
	var restored: RefCounted = BagType.from_dict(saved, pool.size())
	_expect(
		restored.remaining() == bag.remaining(),
		"Restored bag should resume at the same point (%d vs %d)." % [
			restored.remaining(), bag.remaining()
		]
	)
	# Finish the cycle on the restored bag; nothing already played may return.
	var played: Dictionary = {}
	for text in before:
		played[text] = true
	for i in range(pool.size() - before.size()):
		var text := str(restored.next(pool).get("text", ""))
		_expect(
			not played.has(text),
			"'%s' replayed after a restart -- the cursor did not persist." % text
		)
		played[text] = true
	_expect(
		played.size() == pool.size(),
		"The cycle should still complete across the restart, got %d of %d." % [
			played.size(), pool.size()
		]
	)


# Background refills append lines for the rest of the campaign, and a pool that
# grows must not immediately replay what was just heard.
func _test_bag_growth() -> void:
	var pool := _pool(20)
	var bag := BagType.new(pool.size())
	var recent: Array[String] = []
	for i in range(10):
		recent.append(str(bag.next(pool).get("text", "")))
	var grown := pool.duplicate()
	for i in range(20, 60):
		grown.append({"text": "line_%d" % i})
	var last_five := recent.slice(recent.size() - 5, recent.size())
	for i in range(12):
		var text := str(bag.next(grown).get("text", ""))
		_expect(
			not last_five.has(text),
			"'%s' replayed right after the pool grew." % text
		)
	# A restored bag whose pool changed size must still not crash or stall.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(bag.to_dict()))
	var restored: RefCounted = BagType.from_dict(saved, grown.size())
	_expect(
		not str(restored.next(grown).get("text", "")).is_empty(),
		"A restored bag on a resized pool must still deliver a line."
	)


# Regression: the recent-lines guard used to SKIP entries, which burned cursor
# positions, so a cycle wrapped before covering the pool and repeated. It only
# showed up once a real bank had grown past the authored floor -- the small
# fixed pools in the other tests never triggered it.
func _test_exhaustive_after_growth() -> void:
	var pool := _pool(12)
	var bag := BagType.new(pool.size())
	for i in range(8):
		bag.next(pool)
	# Pool grows the way a background refill grows it.
	var grown := pool.duplicate()
	for i in range(12, 60):
		grown.append({"text": "line_%d" % i})
	# A full cycle over the GROWN pool must still cover every line exactly once.
	var seen: Dictionary = {}
	for i in range(grown.size()):
		var text := str(bag.next(grown).get("text", ""))
		if seen.has(text):
			_failures.append(
				"'%s' repeated at draw %d of a %d-line cycle after growth."
				% [text, i + 1, grown.size()]
			)
		seen[text] = true
	_expect(
		seen.size() == grown.size(),
		"A grown pool's cycle must cover all %d lines, saw %d." % [
			grown.size(), seen.size()
		]
	)
	# And the cycle after that must also be complete.
	var second: Dictionary = {}
	for i in range(grown.size()):
		second[str(bag.next(grown).get("text", ""))] = true
	_expect(
		second.size() == grown.size(),
		"The second cycle must also cover every line, saw %d." % second.size()
	)


# The authored lines are hand-edited content in data/content/taunt_lines.json.
# A typo there must degrade to a shorter pool, never to a crash or a spoken
# fragment, so the loader is checked as carefully as the code paths.
func _test_authored_lines_load_from_data() -> void:
	CauseType.reload_lines()
	for cause in CauseType.ALL:
		var lines: Array = CauseType.authored_lines(str(cause))
		_expect(
			not lines.is_empty(),
			"Cause %s must have authored lines to fall back on." % cause
		)
		var seen: Dictionary = {}
		for line in lines:
			var text := str(line)
			_expect(
				text.strip_edges().length() >= 8,
				"Cause %s has a too-short authored line: '%s'." % [cause, text]
			)
			_expect(
				not seen.has(text),
				"Cause %s repeats an authored line: '%s'." % [cause, text]
			)
			seen[text] = true
			# These are spoken mid-fight; a paragraph would be cut off.
			_expect(
				text.split(" ").size() <= 24,
				"Cause %s has an over-long authored line: '%s'." % [cause, text]
			)
	# An unknown cause must still yield something speakable.
	_expect(
		not (CauseType.authored_lines("nonsense_cause") as Array).is_empty(),
		"An unknown cause must fall back to a usable set."
	)


# A line can be a plain string or an object carrying delivery overrides. Both
# forms must load, the override must be found by TEXT (so the persisted pool can
# stay a list of plain strings), and a line without overrides must report the
# defaults rather than nothing.
func _test_delivery_overrides() -> void:
	CauseType.reload_lines()
	var overridden := ""
	var plain := ""
	for cause in CauseType.ALL:
		for line in (CauseType.authored_lines(str(cause)) as Array):
			var text := str(line)
			var delivery: Dictionary = CauseType.delivery_for(text)
			if float(delivery.get("speed", -1.0)) > 0.0 					or float(delivery.get("pause", -1.0)) >= 0.0:
				overridden = text
			elif plain.is_empty():
				plain = text
	_expect(
		not overridden.is_empty(),
		"At least one line should carry a delivery override to exercise this path."
	)
	# An object-form line must still appear as ordinary text in the pool, or it
	# would never be spoken.
	_expect(
		overridden.length() > 8 and not overridden.begins_with("{"),
		"An override line must load as its text, not as a serialised object: '%s'" % overridden
	)
	var plain_delivery: Dictionary = CauseType.delivery_for(plain)
	_expect(
		float(plain_delivery.get("speed", 0.0)) < 0.0 			and float(plain_delivery.get("pause", 0.0)) < 0.0,
		"A line with no overrides must report defaults, got %s" % str(plain_delivery)
	)
	# Unknown text must not crash or invent a delivery.
	var unknown: Dictionary = CauseType.delivery_for("this line does not exist anywhere")
	_expect(
		float(unknown.get("speed", 0.0)) < 0.0,
		"Unknown text must report the default speed."
	)


func _pool(count: int) -> Array:
	var out: Array = []
	for i in range(count):
		out.append({"text": "taunt_%d" % i})
	return out


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
