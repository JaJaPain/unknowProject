extends SceneTree

# Baked audio is an ENGLISH-ONLY quality cache; the game must always be able to
# speak these lines live through Kokoro. These pin the two ways this layer could
# fail SILENTLY: serving English audio to a translated build, and serving one
# character's voice for another.

const IndexType := preload("res://scripts/domain/BakedAudioIndex.gd")
const KAELEN := "af_bella"

var _failures: Array[String] = []


func _initialize() -> void:
	if IndexType.lead_voice_of("a[1]") != "a":
		push_error("[FAIL] BakedAudioIndex did not compile or parse.")
		quit(1)
		return
	_test_english_gate()
	_test_cast_identification()
	_test_no_one_else_is_mistaken_for_the_cast()
	_test_lead_extraction()
	_test_keys_never_match_on_empty_input()
	if _failures.is_empty():
		print("[PASS] Baked audio index tests")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _test_english_gate() -> void:
	for yes in ["en", "en_US", "en_GB", "EN_us"]:
		_expect(IndexType.is_english(yes), "'%s' should count as English" % yes)
	# The important half: a translated build must NOT be served English audio,
	# because the live path would have produced the right words.
	for no in ["fr", "de_DE", "es", "ja", "pt_BR", "zh_CN", ""]:
		_expect(not IndexType.is_english(no), "'%s' must NOT be served English audio" % no)


func _test_cast_identification() -> void:
	for kaelen in ["voice.kaelen.v1", KAELEN, "AF_BELLA", " voice.kaelen.v1 "]:
		_expect(
			IndexType.cast_character_for_voice(kaelen, KAELEN) == "kaelen",
			"'%s' should resolve to kaelen" % kaelen
		)
	for nova in ["voice.nova.v1", "bf_emma[0.7]+af_bella[0.3]", "bf_emma"]:
		_expect(
			IndexType.cast_character_for_voice(nova, KAELEN) == "nova",
			"'%s' should resolve to nova" % nova
		)


func _test_no_one_else_is_mistaken_for_the_cast() -> void:
	# This is the canon rule in code form: a main character's cloned voice must
	# never come out of an NPC.
	for other in ["af_sarah", "am_michael", "voice.neutral.v1", "am_onyx[0.7]+am_michael[0.3]",
			"af_aoede[0.5]+af_nova[0.5]", "", "   "]:
		_expect(
			IndexType.cast_character_for_voice(other, KAELEN).is_empty(),
			"'%s' must NOT be identified as a fixed-cast voice" % other
		)


func _test_lead_extraction() -> void:
	_expect(IndexType.lead_voice_of("am_onyx[0.7]+am_michael[0.3]") == "am_onyx",
		"The lead must be parsed out of a blend.")
	# Non-blend voices skip the taunt layer instead of being matched against it.
	for plain in ["af_bella", "voice.nova.v1", "", "am_onyx"]:
		_expect(IndexType.lead_voice_of(plain).is_empty(),
			"'%s' is not a blend and must not resolve to a lead" % plain)
	# Every mapped lead resolves; an unmapped one falls through rather than guessing.
	for lead in IndexType.ORPHEUS_VOICE_FOR_LEAD.keys():
		_expect(not IndexType.orpheus_voice_for_lead(lead).is_empty(),
			"lead '%s' should map to an Orpheus voice" % lead)
	for unmapped in ["bm_george", "not_a_lead", ""]:
		_expect(IndexType.orpheus_voice_for_lead(unmapped).is_empty(),
			"'%s' must not map to an Orpheus voice" % unmapped)


func _test_keys_never_match_on_empty_input() -> void:
	# An empty key could collide with a malformed manifest entry and serve the
	# wrong audio, so empties must produce no key at all.
	_expect(IndexType.cast_key("", "some text").is_empty(), "No character -> no key.")
	_expect(IndexType.cast_key("nova", "").is_empty(), "No text -> no key.")
	_expect(IndexType.cast_key("nova", "   ").is_empty(), "Blank text -> no key.")
	_expect(IndexType.orpheus_key("", "some text").is_empty(), "No voice -> no key.")
	_expect(IndexType.orpheus_key("leo", "").is_empty(), "No text -> no key.")
	_expect(IndexType.cast_key("Nova", "Docked.") == "nova|Docked.",
		"A real key should be lowercase character + literal text.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
