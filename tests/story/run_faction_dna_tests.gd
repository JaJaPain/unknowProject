extends SceneTree

const DNA := preload("res://scripts/story/premise/FactionDNA.gd")
const Radio := preload("res://scripts/story/premise/RadioBroadcaster.gd")
const Reserved := preload("res://scripts/story/ReservedTopics.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_records()
	_test_names()
	_test_deeds()
	if _failures.is_empty():
		print("[PASS] Faction DNA tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_records() -> void:
	var languages := {}
	var doctrines := {}
	for i in 80:
		var id := "faction.generated.abc%d.f%d" % [i, i % 3]
		var d := DNA.for_faction(id)
		_check(d == DNA.for_faction(id), "DNA is stable per faction")
		languages[d["language"]] = true
		doctrines[d["doctrine"]] = true
		for axis in ["order", "profit", "mercy"]:
			_check(absf(float(d["axes"][axis])) <= 1.0, "axes stay in range")
	_check(languages.size() == DNA.LANGUAGES.size(), "every naming language turns up (%d)" % languages.size())
	_check(doctrines.size() >= 5, "doctrines vary")


func _test_names() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seen := {}
	for lang in DNA.LANGUAGES.keys():
		var dna := {"language": lang}
		for i in 200:
			var person := DNA.person_name(dna, rng)
			var ship := DNA.ship_name(dna, rng)
			for n in [person, ship]:
				_check(Reserved.is_clean(n) and not n.to_lower().contains("shiny"), "clean name: %s" % n)
				_check(n.length() >= 5 and n.length() <= 40, "sane length: %s" % n)
			_check(person.split(" ").size() == 2, "given and family name: %s" % person)
			seen[person] = true
		print("[FactionDNA] %s: %s, %s, %s" % [lang, DNA.person_name(dna, rng), DNA.person_name(dna, rng), DNA.ship_name(dna, rng)])
	_check(seen.size() > 1000, "names rarely repeat (%d distinct of 1200)" % seen.size())


func _test_deeds() -> void:
	var gentle := {"axes": {"order": 0.2, "profit": -0.3, "mercy": 0.9}}
	var hard := {"axes": {"order": 0.1, "profit": 0.4, "mercy": -0.9}}
	var outlaws := {"axes": {"order": -0.9, "profit": 0.5, "mercy": 0.0}}
	_check(DNA.judge_deed(gentle, "saved_the_convoy") == "admire", "the merciful admire a rescue")
	_check(DNA.judge_deed(hard, "saved_the_convoy") == "condemn", "the ruthless think a rescue is weakness")
	_check(DNA.judge_deed(gentle, "staged_an_assassination") in ["condemn", "disapprove"], "the merciful condemn a killing")
	_check(DNA.judge_deed(outlaws, "broke_the_blockade") == "admire", "outlaws love a broken blockade")
	_check(DNA.judge_deed(gentle, "won_the_death_race") in ["shrug", "disapprove"], "profit deeds leave the dutiful cold")
	_check(DNA.judge_deed(gentle, "the_zzz_thing") == "shrug", "unknown deeds are shrugged off")
	# How much of the real deck's deed vocabulary the verb table understands.
	var tags := {}
	for file in DirAccess.get_files_at("res://data/content/premise_cards/approved"):
		var card: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/premise_cards/approved/" + file))
		for r in card.get("resolutions", []):
			for q in r.get("consequences", []):
				if str(q.get("type", "")) == "deed":
					tags[str(q.get("tag", ""))] = true
	var known := tags.keys().filter(func(t): return not DNA.deed_signal(t).is_empty())
	var unknown := tags.keys().filter(func(t): return DNA.deed_signal(t).is_empty())
	print("[FactionDNA] deed tags understood: %d of %d" % [known.size(), tags.size()])
	print("[FactionDNA] not understood (sample): %s" % str(unknown.slice(0, 40)))
	_check(float(known.size()) / maxf(1.0, float(tags.size())) >= 0.6, "most deck deeds should carry meaning")
	var factions := [{"id": "faction.generated.x.f0", "display_name": "the Ash Choir"}]
	var any_reaction := false
	for t in ["saved_the_convoy", "broke_the_blockade", "staged_an_assassination", "sold_the_cure"]:
		var r := Radio.deed_reaction(t, factions, 0)
		if not r.is_empty():
			any_reaction = true
			_check(r.begins_with(" The Ash Choir"), "reactions name the faction, capitalised: %s" % r)
	_check(any_reaction, "a faction reacts to at least one strong deed")
	_check(Radio.deed_reaction("saved_the_convoy", [], 0) == "", "no factions, no reaction")
