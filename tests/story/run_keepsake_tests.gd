extends SceneTree

# The Captain's story at the end (campaign spine plan, Section 5): every
# chapter comes from the records; retire and eulogy differ in framing; the
# people left behind carry their fates; nothing reserved is ever shown; the
# saved page is escaped and well named.

const Keepsake := preload("res://scripts/story/Keepsake.gd")
const ReservedTopicsType := preload("res://scripts/story/ReservedTopics.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_retire()
	_test_eulogy()
	_test_empty_campaign()
	_test_reserved_dropped()
	_test_html_and_name()
	if _failures.is_empty():
		print("[PASS] Keepsake (all cases)")
		quit(0)
		return
	for f in _failures:
		push_error(f)
	print("[FAIL] Keepsake: %d case(s)" % _failures.size())
	quit(1)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_failures.append(msg)


func _facts(mode: String) -> Dictionary:
	return {"mode": mode, "campaign": "The Long Quiet", "days": 41, "credits": 18250, "kills": 12,
		"journal": [
			{"minute": 9000, "system": "Kova", "title": "The Cold Ledger", "ended": true,
				"text": "The books were balanced, at a price.", "deeds": ["The Captain paid off a dock boss."]},
			{"minute": 100, "system": "Myrion", "title": "Spare Parts", "ended": true,
				"text": "Eric got his parts.", "deeds": []},
			{"minute": 12000, "system": "Ashis", "title": "The Last Signal", "ended": false,
				"text": "Someone is still listening.", "deeds": []},
		],
		"people": [
			{"entity_id": "p1", "name": "Eric Dahl", "story": "Spare Parts", "system": "Myrion", "minute": 100},
			{"entity_id": "p2", "name": "Oren Vask", "story": "The Cold Ledger", "system": "Kova", "minute": 9000},
			{"entity_id": "p1", "name": "Eric Dahl", "story": "Spare Parts", "system": "Myrion", "minute": 200},
			{"entity_id": "p3", "name": "Sela Moor", "story": "The Last Signal", "system": "Ashis", "minute": 12000},
		],
		"fates": {"p1": ["alive_grateful"], "p2": ["exposed", "dead"]},
		"hand": "Oren Vask", "destination": "The Lighthouse",
		"reached": [{"title": "The Humming Gate", "season": 1}], "lost_in": "Ashis"}


func _all_text(k: Dictionary) -> String:
	return Keepsake.to_text(k)


func _test_retire() -> void:
	var k := Keepsake.build(_facts("retire"))
	var text := _all_text(k)
	var headings: Array = k["chapters"].map(func(c): return c["heading"])
	_check(headings == ["How it started", "Who they met", "What they did", "The Destination", "How it ended"],
		"retire chapters in order: %s" % str(headings))
	_check(k["title"] == "The Long Quiet", "titled with the campaign")
	_check(text.contains("41 days") and text.contains("18,250 credits") and text.contains("12 fights"), "the tally is true")
	_check(text.contains("The first story on the record was Spare Parts, in Myrion."), "starts with the oldest story")
	_check(text.count("Eric Dahl") == 1, "each person once")
	_check(text.contains("Eric Dahl, who never forgot"), "a fate shapes how a person is remembered")
	_check(text.contains("Oren Vask, who did not live to see"), "the latest fate counts")
	_check(text.contains("Sela Moor, met in Ashis."), "people without a fate are still named")
	_check(text.find("Spare Parts (Myrion)") < text.find("The Cold Ledger (Kova)"), "deeds oldest first")
	_check(text.contains("Someone is still listening. It was still unfinished."), "unfinished stories say so")
	_check(text.contains("In season 1 the Captain reached The Humming Gate."), "Destinations reached")
	_check(text.contains("Behind it all was Oren Vask"), "the hand, once revealed")
	_check(text.contains("retired"), "a retirement ending")
	_check(not text.contains("lost in Ashis"), "retiring never mentions the loss")


func _test_eulogy() -> void:
	var k := Keepsake.build(_facts("eulogy"))
	var text := _all_text(k)
	var headings: Array = k["chapters"].map(func(c): return c["heading"])
	_check(headings[0] == "Who the Captain was" and headings.has("Who they left behind"), "eulogy framing: %s" % str(headings))
	_check(k["subtitle"] == "In memory of the Captain", "eulogy subtitle")
	_check(text.contains("The ship was lost in Ashis"), "where the ship was lost")
	_check(not text.contains("retired"), "no retirement in a eulogy")
	_check(ReservedTopicsType.is_clean(text), "the eulogy is clean: %s" % str(ReservedTopicsType.find_in(text)))


func _test_empty_campaign() -> void:
	var k := Keepsake.build({"mode": "eulogy", "days": 0})
	var text := _all_text(k)
	_check(k["title"] == "An unnamed campaign", "a fallback title")
	_check(text.contains("one day"), "at least one day")
	_check(text.contains("never learned where everyone was heading"), "no Destination yet still reads")
	_check(not text.contains("{") and not text.contains("<null>"), "nothing unfilled: %s" % text)
	var headings: Array = k["chapters"].map(func(c): return c["heading"])
	_check(not headings.has("What they did") and not headings.has("Who they left behind"), "empty chapters are left out")


func _test_reserved_dropped() -> void:
	var f := _facts("retire")
	f["journal"].append({"minute": 500, "system": "Vell", "title": "Odd", "ended": true,
		"text": "They said the Captain died there once.", "deeds": []})
	var text := _all_text(Keepsake.build(f))
	_check(not text.contains("Odd (Vell)"), "a reserved line is dropped, not shown")
	_check(ReservedTopicsType.is_clean(text), "the whole keepsake is clean")


func _test_html_and_name() -> void:
	var f := _facts("retire")
	f["campaign"] = "Rust & <Ruin>"
	var k := Keepsake.build(f)
	var html := Keepsake.to_html(k)
	_check(html.contains("Rust &amp; &lt;Ruin&gt;") and not html.contains("<Ruin>"), "html is escaped")
	_check(html.contains("<h2>What they did</h2>"), "chapters become headings")
	_check(Keepsake.file_name(k, 1700000000) == "rust-ruin-1700000000.html", "file name: %s" % Keepsake.file_name(k, 1700000000))
