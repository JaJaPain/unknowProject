extends SceneTree

# Non-Kaelen speakers address the player directly but never by nickname: it is
# implied, not stated, which is how people actually speak. Nobody says a name in
# every sentence of a conversation they never left.
#
# The prompts say not to. This suite covers the structural guarantee behind
# them, because a model asked not to do something still does it sometimes.

var _failures: Array[String] = []
# Runtime load, not the autoload identifier: in --script mode the autoload is
# not registered when this file compiles, and referencing it by name is a hard
# compile error. The functions under test are static, so the script is enough.
var GS: GDScript = null


func _initialize() -> void:
	GS = load("res://scripts/GlobalState.gd")
	# load() returns a GDScript even when the file failed to PARSE, and calling a
	# missing static on it only logs an error and returns null -- which once let
	# this suite print [PASS] against a script that had not compiled. Prove the
	# function is really there before asserting anything about it.
	if GS == null or str(GS.strip_player_address("Indy, test line here.")) != "Test line here.":
		push_error("[FAIL] GlobalState.strip_player_address unavailable -- see parse errors above.")
		quit(1)
		return
	_test_strips_every_position()
	_test_the_reported_shape()
	_test_kaelen_keeps_her_signature()
	_test_leaves_ordinary_text_alone()

	if _failures.is_empty():
		print("[PASS] Player address tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _test_strips_every_position() -> void:
	var cases := {
		"Indy, the convoy is late.": "The convoy is late.",
		"The convoy is late, Indy.": "The convoy is late.",
		"Listen, Indy, the convoy is late.": "Listen, the convoy is late.",
		"Shiny, the convoy is late.": "The convoy is late.",
		"The job pays well, Indy": "The job pays well",
	}
	for input in cases.keys():
		var got: String = GS.strip_player_address(str(input))
		_expect(
			got == str(cases[input]),
			"Expected '%s' -> '%s', got '%s'." % [input, cases[input], got]
		)


# The reported failure, verbatim in shape: the nickname in every clause of one
# paragraph. Not one occurrence may survive.
func _test_the_reported_shape() -> void:
	var spam := "Indy, we have a problem. The raiders are probing our perimeter, Indy, and Indy, I need this handled quietly. So Indy, take the job."
	var got: String = GS.strip_player_address(spam)
	_expect(
		not got.to_lower().contains("indy"),
		"Every occurrence must go, got '%s'." % got
	)
	# Stripping must not shred the sentence -- the content has to survive.
	_expect(
		got.contains("raiders are probing our perimeter") \
			and got.contains("take the job"),
		"The line's content must survive the strip, got '%s'." % got
	)
	_expect(
		not got.contains(" ,") and not got.contains(",,") and not got.contains("  "),
		"Stripping must not leave dangling punctuation or doubled spaces: '%s'." % got
	)


# "Shiny" is Kaelen's, and only hers. Her lines must come through untouched by
# both the tone guard and the address strip.
func _test_kaelen_keeps_her_signature() -> void:
	var line := "Shiny, don't get sentimental. Just get paid."
	var kaelen_voice: String = GS.KAELEN_VOICE_PROFILE_ID
	_expect(
		GS.apply_tone_guard(line, kaelen_voice) == line,
		"Kaelen's line must not be rewritten by the tone guard."
	)
	# A non-Kaelen speaker saying "Shiny" is still converted to the neutral
	# nickname first, and then stripped entirely.
	var converted: String = GS.apply_tone_guard(line, "voice.neutral.v1")
	_expect(
		not converted.contains("Shiny"),
		"A non-Kaelen speaker must not keep Kaelen's nickname: '%s'." % converted
	)
	_expect(
		not GS.strip_player_address(converted).to_lower().contains("indy"),
		"The converted nickname must then be stripped for non-Kaelen speakers."
	)


# The strip must not chew on ordinary words, including a genuine sentence that
# merely contains similar punctuation.
func _test_leaves_ordinary_text_alone() -> void:
	var untouched := [
		"The convoy is late and the escort never showed.",
		"Independent haulers, mostly. Nothing worth flagging.",
		"Take it or leave it, pilot.",
		"Cargo's clean, quiet, off the books.",
	]
	for line in untouched:
		_expect(
			GS.strip_player_address(str(line)) == str(line),
			"Ordinary text must pass through unchanged: '%s' -> '%s'." % [
				line, GS.strip_player_address(str(line))
			]
		)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
