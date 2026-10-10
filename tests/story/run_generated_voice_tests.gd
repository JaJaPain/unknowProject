extends SceneTree

## Voices made in code (VoiceDNA: receiver intercepts, story casts) resolve to
## themselves, not the neutral voice (playtest 2026-10-10 finding 8: every
## ambient intercept sounded the same).

const Voice := preload("res://scripts/story/premise/VoiceDNA.gd")

var _failures: Array = []


func _initialize() -> void:
	var speech = load("res://scripts/speech/SpeechService.gd").new()
	var ids := {}
	for i in 6:
		var profile := Voice.register(Voice.for_person("intercept.system.test.%d" % i))
		var resolved := str(speech.resolve_voice_profile(profile))
		_check(resolved == profile, "a generated voice resolves to itself (%s -> %s)" % [profile, resolved])
		ids[profile] = true
	_check(ids.size() >= 3, "six intercepts get at least three different voices (%d)" % ids.size())
	speech.free()
	if _failures.is_empty():
		print("[PASS] Generated voices")
		quit(0)
	else:
		for f in _failures:
			push_error("[FAIL] " + str(f))
		quit(1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
