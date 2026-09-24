extends SceneTree

const DirectorType := preload("res://scripts/story/undercurrent/UndercurrentDirector.gd")
const LedgerType := preload("res://scripts/story/undercurrent/EchoLedgerStore.gd")
const TEST_PATH := "user://test_echo_ledger.json"

var _failures: Array[String] = []


func _initialize() -> void:
	_test_never_early()
	_test_rarity()
	_test_once_per_machine()
	_test_audio_and_ledger_persist()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	if _failures.is_empty():
		print("[PASS] Undercurrent tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _director(play_hours: float, deaths: int, seed_value: int):
	var d = DirectorType.new()
	d.ledger_path = TEST_PATH
	d._lines = d._load_lines()
	d.ledger = LedgerType.empty()
	d.ledger["play_seconds"] = play_hours * 3600.0
	d.ledger["deaths"] = deaths
	d.rng.seed = seed_value
	return d


func _test_never_early() -> void:
	var fired := 0
	for i in 3000:
		var early = _director(2.0, 50, i)
		if early.on_player_death():
			fired += 1
		early.free()
		var green = _director(50.0, 1, i)
		if green.on_player_death():
			fired += 1
		green.free()
	_check(fired == 0, "the line must never play before 5 hours and 5 deaths (fired %d times)" % fired)


func _test_rarity() -> void:
	var fired := 0
	var trials := 20000
	for i in trials:
		var d = _director(6.0, 5, i)
		if d.on_player_death():
			fired += 1
		d.free()
	var rate := float(fired) / float(trials)
	print("  death line rate on eligible deaths: %.2f%% (%d of %d)" % [rate * 100.0, fired, trials])
	_check(rate > 0.045 and rate < 0.08, "the eligible rate should be about 6%%, got %.2f%%" % (rate * 100.0))


func _test_once_per_machine() -> void:
	var d = _director(6.0, 5, 1)
	var first := -1
	for i in 5000:
		if d.on_player_death():
			first = i
			break
	_check(first >= 0, "it should eventually fire for an eligible player")
	var moment: Dictionary = d.consume_death_moment()
	_check(moment.get("id") == "death_line_01" and str(moment.get("text", "")).begins_with("Damn it, Kaelen"), "the moment carries the canonical line")
	_check(d.consume_death_moment().is_empty(), "a moment is consumed once")
	d.ledger["play_seconds"] = float(d.ledger["play_seconds"]) + 100.0 * 3600.0
	var again := 0
	for i in 5000:
		if d.on_player_death():
			again += 1
	_check(again == 0, "with one approved line, it plays at most once per machine (played %d more times)" % again)
	d.free()
	# Drafts never play: with every approved line used up, nothing is eligible,
	# however many unapproved drafts sit in the file.
	var e = _director(6.0, 5, 2)
	var drafts := 0
	for line in e._lines:
		if not bool(line.get("approved_by_abe", false)):
			drafts += 1
		else:
			e.ledger["lines_shown"][str(line["id"])] = 1
	e.ledger["last_shown_play_seconds"] = -1.0
	_check(e._eligible_death_line(10).is_empty(), "unapproved drafts (%d in the file) are never eligible" % drafts)
	e.free()
	# Several approved lines: each moment picks one at random, never repeating.
	var firsts := {}
	for seed_value in 40:
		var f = _director(6.0, 5, seed_value)
		f._lines = [
			{"id": "a", "kind": "death_line", "approved_by_abe": true},
			{"id": "b", "kind": "death_line", "approved_by_abe": true},
			{"id": "c", "kind": "death_line", "approved_by_abe": true},
		]
		firsts[str(f._eligible_death_line(10)["id"])] = true
		f.ledger["lines_shown"] = {"a": 1, "b": 1}
		_check(f._eligible_death_line(10).get("id") == "c", "a heard line never comes back")
		f.free()
	_check(firsts.size() == 3, "the pick is random among unheard lines (saw %s)" % str(firsts.keys()))


func _test_audio_and_ledger_persist() -> void:
	var stream := DirectorType.load_line_audio("res://assets/audio/undercurrent/death_line_01.ogg")
	_check(stream != null and stream.get_length() > 1.0, "the baked line should load (run tools/bake_undercurrent_audio.py)")
	var ledger := LedgerType.empty()
	ledger["deaths"] = 7
	_check(LedgerType.save_ledger(ledger, TEST_PATH), "ledger saves")
	_check(int(LedgerType.load_ledger(TEST_PATH)["deaths"]) == 7, "ledger round trip")
