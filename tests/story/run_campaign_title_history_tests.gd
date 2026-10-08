extends SceneTree

## Campaign titles across campaigns (Abe, 2026-10-07: titles repeated, several
## with "ledger"): the history survives deleted saves, the model is shown
## recent titles and overused words, and a title reusing a recent main word
## is sent back.

const History := preload("res://scripts/story/CampaignTitleHistory.gd")
const Director := preload("res://scripts/ai/NarrativeDirector.gd")
const TEST_PATH := "user://test_campaign_title_history.json"

var _failures: Array = []


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	History.path = TEST_PATH
	_test_words()
	_test_history()
	_test_prompt_and_gate()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	History.path = ""
	if _failures.is_empty():
		print("[PASS] Campaign title history")
		quit(0)
	else:
		for f in _failures:
			push_error("[FAIL] " + str(f))
		quit(1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)


func _test_words() -> void:
	_check(History.words("The Ledger of Ash") == ["ledger"], "small words dropped: %s" % [History.words("The Ledger of Ash")])
	_check(History.words("Kessler's Ledger") == ["kessler", "ledger"], "possessives trimmed: %s" % [History.words("Kessler's Ledger")])
	_check(History.overused(["The Hollow Ledger", "Ledger of Embers", "Cold Meridian"]) == ["ledger"], "a word in two titles is overused")
	_check(History.shared_word("A Ledger in Red", ["Cold Meridian", "The Iron Ledger"]) == "ledger", "a shared main word is found")
	_check(History.shared_word("Saltwater Psalm", ["Cold Meridian", "The Iron Ledger"]) == "", "no shared word, none found")


func _test_history() -> void:
	_check(History.recent("title").is_empty(), "empty to start")
	for i in History.KEEP + 5:
		History.record("Title %d Word%d" % [i, i], "reveal %d" % i, "lane%d" % (i % 3))
	var recent := History.recent("title")
	_check(recent.size() == History.RECENT, "recent is capped")
	_check(str(recent[0]) == "Title %d Word%d" % [History.KEEP + 4, History.KEEP + 4], "newest first")
	_check(History.entries().size() == History.KEEP, "the file keeps KEEP entries")
	_check(History.recent("lane", 2).size() == 2, "lanes recall")


func _test_prompt_and_gate() -> void:
	var titles := ["The Hollow Ledger", "Ledger of Embers"]
	var prompt := Director.build_campaign_bible_prompt({"campaign_seed": "abc", "_avoid_titles": titles})
	_check(prompt.contains("The Hollow Ledger") and prompt.contains("never use them in the title: ledger"), "the prompt lists recent titles and bans 'ledger'")
	var note := Director.motif_collision_note({"campaign_title": "Ledger at Dawn"}, titles, [])
	_check(not note.is_empty(), "a reused main word is sent back")
	_check(Director.motif_collision_note({"campaign_title": "Red Ledger Rising"}, titles, []).contains("ledger"), "even when it isn't the first word")
	_check(Director.motif_collision_note({"campaign_title": "Saltwater Psalm"}, titles, []).is_empty(), "a fresh title passes")
