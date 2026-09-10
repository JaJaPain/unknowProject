extends SceneTree

# Verifies the GDScript port of the quiet-moment screening matches the
# behaviour measured in docs/research/quiet_moment/. Each case below is a
# real line from a real run, not a synthetic example.

const Checks := preload("res://scripts/story/QuietMomentChecks.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_accepts_shipped_lines()
	_test_rejects_known_defects()
	_test_echo_family()
	_test_nova_affection_guard()
	_test_smart_quote_normalisation()
	_test_number_licensing()
	if _failures.is_empty():
		print("[PASS] QuietMomentChecks (all cases)")
		quit(0)
	else:
		for f in _failures:
			push_error(f)
		print("[FAIL] QuietMomentChecks: %d case(s)" % _failures.size())
		quit(1)


func _expect_clean(line: String, context: Dictionary, label: String) -> void:
	var errors := Checks.screen(line, context)
	if not errors.is_empty():
		_failures.append("%s: expected clean, got %s -- %s" % [label, errors, line])


func _expect_flag(line: String, context: Dictionary, tag: String, label: String) -> void:
	var errors := Checks.screen(line, context)
	if not errors.has(tag):
		_failures.append("%s: expected '%s', got %s -- %s" % [label, tag, errors, line])


# Author-approved lines must survive screening. If a change here starts
# rejecting these, the change is wrong.
func _test_accepts_shipped_lines() -> void:
	var kaelen := {"speaker": "kaelen", "word_cap": 25}
	for line in [
		"This one didn't cost much. That's the problem — it didn't move anything.",
		"Bullets cost money, Shiny. This one paid enough to cover the holes.",
		"I lose the fee, but I lose the trust worse.",
		"They were told it's not happening. I don't get paid for ghosts, Shiny.",
	]:
		_expect_clean(line, kaelen, "approved_kaelen")

	var nova := {"speaker": "nova", "word_cap": 45}
	for line in [
		"You'll still need to scrape that burn out of my aft struts. Not that I mind the attention.",
		"I'm stuffed to the seams, and I don't mean the cargo holds.",
		"Mrs. Kross had her hands on me for hours. Warm solvent, slow work.",
		"They're still holding me. I don't mind being held.",
	]:
		_expect_clean(line, nova, "approved_nova")


func _test_rejects_known_defects() -> void:
	_expect_flag(
		"You bailed mid-job. That's what I'm charging for.",
		{"speaker": "kaelen"}, "tts_hyphen_compound", "hyphen")
	_expect_flag(
		"Filter's loose... you could swap it.",
		{"speaker": "nova"}, "tts_ellipsis", "ellipsis")
	_expect_flag(
		"This one paid right. You're good at that part, Shiny.",
		{"speaker": "kaelen"}, "generic_praise", "praise")
	_expect_flag(
		"This one paid right. More of that, Captain.",
		{"speaker": "kaelen"}, "wrong_address", "kaelen_says_captain")
	_expect_flag(
		"My hips are full. The hold is full. My knees are full. My spine is full.",
		{"speaker": "nova", "word_cap": 45}, "word_echo", "intra_line_repeat")
	_expect_flag(
		"That was a FUBAR run.", {"speaker": "kaelen"}, "tts_all_caps", "all_caps")
	# from a live Godot run: both are character violations her bible forbids
	_expect_flag("This trade paid well. You got hurt. I wanted that.",
		{"speaker": "kaelen"}, "cruel_to_captain", "wished_harm")
	_expect_flag("You got paid for safe work. Do better next time.",
		{"speaker": "kaelen"}, "cruel_to_captain", "instructive_scolding")
	_expect_clean("Danger's the only thing that pays this well. Glad you came back in one piece, Shiny.",
		{"speaker": "kaelen"}, "warmth_still_passes")


func _test_echo_family() -> void:
	_expect_flag(
		"They shot at you out there, and the number was worth it.",
		{"speaker": "kaelen", "packet": "They shot at you out there, and the number was worth it."},
		"packet_echo", "packet_echo")
	_expect_flag(
		"My seams are tight. You didn't have to do that by hand. I noticed you did anyway.",
		{"speaker": "nova", "word_cap": 45,
		"demos": ["My plating's buffed out. You didn't have to do that by hand. I noticed you did anyway."]},
		"demo_echo", "demo_echo")
	# short lead-ins are missed by an n-word run, hence the prefix comparison
	_expect_flag(
		"They're finished. My waist's got a fresh scar.",
		{"speaker": "nova", "word_cap": 45, "lead_in": "They're finished."},
		"lead_in_echo", "short_lead_in_echo")
	_expect_flag(
		"Captain, my paint's peeled.",
		{"speaker": "nova", "word_cap": 45, "lead_in": "Enemy ship is down, Captain."},
		"double_address", "double_address")
	_expect_clean(
		"They'll be scraping my paint off like it's a bad habit.",
		{"speaker": "nova", "word_cap": 45, "lead_in": "That's them dealt with."},
		"lead_in_ok")


func _test_nova_affection_guard() -> void:
	_expect_flag("You didn't look this lost.",
		{"speaker": "nova", "word_cap": 45}, "belittles_captain", "belittles")
	_expect_flag("I'm waiting for someone to apologize for it.",
		{"speaker": "nova", "word_cap": 45}, "demands_apology", "apology")
	_expect_flag("They'd remember how much I hate being touched.",
		{"speaker": "nova", "word_cap": 45}, "inverts_affection", "inversion")
	# "slow work" is fine; the guard anchors on "you"
	_expect_clean("Warm solvent, slow work. I almost lost pressure entirely.",
		{"speaker": "nova", "word_cap": 45}, "slow_work_ok")
	# the deficiency word must describe HIM, not the task
	_expect_clean("This valve's been stubborn. You'll want to work it slow. It likes being coaxed.",
		{"speaker": "nova", "word_cap": 45}, "slow_describes_the_task")
	_expect_flag("You're slower this time. Not that I'm counting.",
		{"speaker": "nova", "word_cap": 45}, "belittles_captain", "slower_describes_him")

	# he/his is legitimate when it belongs to a named third party
	_expect_clean("Ferro had his hands on me once. He used a heated seal iron.",
		{"speaker": "nova", "word_cap": 45, "third_parties": ["old Ferro"]},
		"named_third_party")
	_expect_flag("You brought him in hard.",
		{"speaker": "nova", "word_cap": 45}, "assumes_captain_gender", "captain_gender")


func _test_smart_quote_normalisation() -> void:
	# U+2019 apostrophe: this silently defeated two checks before it was caught
	_expect_flag("You’re good at that part, Shiny.",
		{"speaker": "kaelen"}, "generic_praise", "smart_quote_praise")


func _test_number_licensing() -> void:
	_expect_flag("Second burn in ten hours.",
		{"speaker": "nova", "word_cap": 45}, "invented_number", "unlicensed_number")
	# licensed when the packet supplied it
	_expect_clean("They took six hours, and I'm still warm where they touched me.",
		{"speaker": "nova", "word_cap": 45,
		"packet": "Somebody spent six hours on her and has now gone home."},
		"licensed_number")
	# "one" is a demonstrative here, not a quantity
	_expect_clean("This one paid small. No tricks, no traps. Just small.",
		{"speaker": "kaelen"}, "one_is_demonstrative")
