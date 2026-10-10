extends SceneTree

## GameWordGuard (playtests 2026-10-08 finding 7 and 2026-10-10 finding 10):
## designer words never reach the radio, and at an outpost nobody has just
## seen Kaelen.

const Guard := preload("res://scripts/story/GameWordGuard.gd")

var _failures: Array = []


func _initialize() -> void:
	_check(not Guard.is_clean("Player finds a dead ship with a valuable cargo manifest."), "'Player' is a designer's word")
	_check(not Guard.is_clean("Watch the player's ledger."), "possessives too")
	_check(Guard.is_clean("Coolant's steaming again. Nobody wants an audit."), "ordinary lines pass")
	_check(Guard.is_clean("He layered the plating."), "words that merely contain 'player' pass")
	_check(Guard.places_kaelen_here("Finished my drink. Saw Kaelen coming down the corridor. Back to work."), "seeing her here is caught")
	_check(Guard.places_kaelen_here("Kaelen's at the bar again."), "her at the bar is caught")
	_check(not Guard.places_kaelen_here("Kaelen's prices went up again. Typical broker."), "talking about her in general is fine")
	_check(not Guard.places_kaelen_here("Nothing much happening tonight."), "no Kaelen, nothing to catch")
	if _failures.is_empty():
		print("[PASS] Game word guard")
		quit(0)
	else:
		for f in _failures:
			push_error("[FAIL] " + str(f))
		quit(1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
