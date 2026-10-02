extends SceneTree

## Core loop step 11: short pulls. The map teaser says one TRUE thing about a
## system (from the profile it will have), survey data pays for exploring
## (more from deeper out), and each kind of system gets N.O.V.A.'s reaction and
## a wiki entry the first time.
##   Godot --headless --path . --script res://tests/story/run_short_pulls_tests.gd --log-file <path>

const Pulls := preload("res://scripts/domain/ShortPulls.gd")
const Profile := preload("res://scripts/story/premise/SystemProfile.gd")

var _failures: Array[String] = []


class FakeConfig:
	var seed_value := 0
	var star_type := "yellow"


func _initialize() -> void:
	# --- Teasers ------------------------------------------------------------------
	_check(Pulls.richest_ore({"silicate": 0.6, "ferrite": 0.28, "cuprite": 0.12}) == "ferrite", "richest ore skips silicate")
	_check(Pulls.teaser_from_profile({"quirks": [], "ores": {"silicate": 1.0}}, "sys.x") == "", "nothing to say about plain rock")
	var nebula_teaser := Pulls.teaser_from_profile({"quirks": ["nebula"], "ores": {"silicate": 1.0}}, "sys.x")
	_check(nebula_teaser == Pulls.QUIRK_TEASERS["nebula"], "a nebula shows on the scans: %s" % nebula_teaser)
	_check(Pulls.teaser_from_profile({"quirks": ["nebula"], "ores": {"silicate": 0.7, "thorium": 0.3}}, "sys.y")
		== Pulls.teaser_from_profile({"quirks": ["nebula"], "ores": {"silicate": 0.7, "thorium": 0.3}}, "sys.y"), "the same system always says the same thing")
	# It's TRUE: whatever it says matches the profile the system will have on arrival.
	var said_something := 0
	for i in 200:
		var config := FakeConfig.new()
		config.seed_value = i * 7919
		config.star_type = ["red", "white", "blue", "orange", "yellow"][i % 5]
		var id := "sys.gen_%d" % i
		var depth := 1 + i % 8
		var truth := Profile.generate(id, config.seed_value, config.star_type, false, depth)
		var teaser := Pulls.teaser_from_profile(Pulls.profile_for_system(config, id, depth), id)
		if teaser.is_empty():
			continue
		said_something += 1
		var true_things: Array = []
		for q in truth["quirks"]:
			true_things.append(Pulls.QUIRK_TEASERS[str(q)])
		var ore := Pulls.richest_ore(truth["ores"])
		if not ore.is_empty():
			true_things.append("Its belts carry %s" % preload("res://scripts/economy/OreTypes.gd").display(ore).to_lower())
		_check(teaser in true_things, "%s: the teaser '%s' is true of the system" % [id, teaser])
	_check(said_something > 150, "most systems have something to tease (%d/200)" % said_something)

	# --- Survey data ----------------------------------------------------------------
	var story := {}
	_check(Pulls.record_visit(story, "start_system", 0).is_empty(), "the start system is no survey")
	var first: Dictionary = Pulls.record_visit(story, "sys.a", 2)
	_check(int(first.get("value", 0)) == 60, "a system two deep: 40 x 1.5 = 60 (%d)" % int(first.get("value", 0)))
	_check(Pulls.record_visit(story, "sys.a", 2).is_empty(), "charted once")
	_check(int(Pulls.record_visit(story, "sys.deep", 8).get("value", 0)) > 60, "deeper data pays more")
	_check(int(Pulls.record_anomaly(story, "anomaly.1", 2).get("value", 0)) == 45, "an anomaly two deep: 30 x 1.5 = 45")
	_check(Pulls.record_anomaly(story, "anomaly.1", 2).is_empty(), "each anomaly once")
	var waiting: Dictionary = Pulls.unsold(story)
	_check(int(waiting["count"]) == 3, "three entries waiting")
	var paid := Pulls.sell_all(story)
	_check(paid == int(waiting["value"]) and int(Pulls.unsold(story)["count"]) == 0, "Kaelen buys the lot (%d SC)" % paid)
	_check(Pulls.record_visit(story, "sys.a", 2).is_empty(), "selling doesn't make a system new again")

	# --- Firsts ---------------------------------------------------------------------
	var seen := {}
	var firsts: Dictionary = Pulls.note_firsts(seen, ["nebula", "pulsar"])
	_check(firsts["new"] == ["nebula", "pulsar"] and str(firsts["line"]) == Pulls.FIRST_LINES["nebula"], "two new kinds; she reacts to the first")
	_check(Pulls.note_firsts(seen, ["nebula"])["new"].is_empty() and str(Pulls.note_firsts(seen, ["nebula"])["line"]).is_empty(), "the second nebula is old news")
	_check(Pulls.note_firsts(seen, ["not_a_quirk"])["new"].is_empty(), "unknown kinds are ignored")
	# Every kind has a first line, a teaser and a wiki entry in a listed category.
	var wiki = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/wiki_entries.json"))
	var entries := {}
	for e in wiki["entries"]:
		entries[str(e["id"])] = e
	for quirk in Profile.QUIRKS:
		_check(Pulls.FIRST_LINES.has(quirk) and Pulls.QUIRK_TEASERS.has(quirk), "%s has a first line and a teaser" % quirk)
		var entry: Dictionary = entries.get(Pulls.wiki_id(quirk), {})
		_check(not entry.is_empty() and str(entry["category"]) in wiki["categories"], "%s has a wiki entry in a listed category" % quirk)
	_check(entries.has("survey_data"), "survey data has a wiki entry")
	if _failures.is_empty():
		print("[PASS] Short pulls")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
