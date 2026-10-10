extends SceneTree

## N.O.V.A.'s register (playtest 2026-10-10 finding 2): flirty means teasing
## the Captain, not her parts being handled. The playtest's lines are caught;
## Abe's approved samples pass; the data no longer asks for innuendo.

const Director := preload("res://scripts/story/QuietMomentDirector.gd")

var _failures: Array = []


func _initialize() -> void:
	for bad in [
		"This shaft needs greasing all the way down. You can do it.",
		"My clutch is loose. You're the only one who can tighten it without me complaining.",
		"Back to the same station. My access ports feel like they've been waiting.",
		"Sella Rusk's slow flush left me thinking I'd leak coolant.",
		"They handled me thoroughly. No hiccups. I'm clean now.",
		"Ribs are a bit loose today. Fix it, Captain?",
	]:
		_check(Director.leer_word(bad) != "", "caught: %s" % bad)
	for good in [
		"Same station again. I'm starting to think you are getting addicted to the coffee.",
		"Not a scratch. You're showing off now, aren't you?",
		"Dented, but I'm still pretty. Don't make a habit of it.",
		"Long haul. Talk to me, Captain. I get bored when you go quiet.",
		"You fly better when I'm watching. Lucky for you, I'm always watching.",
		"Somewhere between here and the gate I stopped counting.",
	]:
		_check(Director.leer_word(good) == "", "passes: %s" % good)

	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/quiet_moment_beats.json"))
	for id in doc["beats"]:
		var b: Dictionary = doc["beats"][id]
		if str(b.get("speaker", "")) != "nova":
			continue
		var text := (str(b.get("register", "")) + str(b.get("valence", ""))).to_lower()
		_check(not text.contains("more suggestive"), "%s no longer asks for suggestive" % id)
		_check(not text.contains("most suggestive"), "%s no longer asks for most suggestive" % id)
	var devices: Dictionary = doc["beats"]["nova_long_transit"]["devices"]
	_check(not devices.has("jealousy"), "the jealousy device is gone")
	_check(devices.has("attention"), "the attention device is in")
	var lines := []
	for d in doc["demo_pools"]["nova"]:
		lines.append(str(d["line"]))
		_check(Director.leer_word(str(d["line"])) == "", "demo is clean: %s" % d["line"])
	_check(lines.has("Not a scratch. You're showing off now, aren't you?"), "Abe's samples are her examples")
	if _failures.is_empty():
		print("[PASS] N.O.V.A. register")
		quit(0)
	else:
		for f in _failures:
			push_error("[FAIL] " + str(f))
		quit(1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
