extends SceneTree

## Ore by type (Abe, playtest 2026-10-08 findings 1 and 5): upgrades climb a
## ladder from silicate to thorium, and ore jobs name an ore picked in code
## from what the system's belts carry, the text rewritten to match.

const Jobs := preload("res://scripts/economy/OreJobs.gd")
const GS := preload("res://scripts/economy/OreTypes.gd")

var _failures: Array = []


func _initialize() -> void:
	_test_ladder()
	_test_pick_local()
	_test_hard_jobs()
	_test_rewrite()
	_test_board_text()
	if _failures.is_empty():
		print("[PASS] Ore types in jobs and upgrades")
		quit(0)
	else:
		for f in _failures:
			push_error("[FAIL] " + str(f))
		quit(1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)


func _test_ladder() -> void:
	_check(GS.split_upgrade_ore(50, 2) == {"silicate": 50}, "tier 2 is all silicate: %s" % [GS.split_upgrade_ore(50, 2)])
	_check(GS.split_upgrade_ore(100, 3) == {"silicate": 60, "ferrite": 40}, "tier 3 silicate and ferrite: %s" % [GS.split_upgrade_ore(100, 3)])
	_check(GS.split_upgrade_ore(200, 4) == {"ferrite": 100, "cuprite": 100}, "tier 4 ferrite and cuprite")
	_check(GS.split_upgrade_ore(400, 5) == {"cuprite": 200, "thorium": 200}, "tier 5 cuprite and thorium")
	var odd := GS.split_upgrade_ore(51, 3)
	_check(int(odd.get("silicate", 0)) + int(odd.get("ferrite", 0)) == 51, "the split always adds up: %s" % [odd])
	_check(GS.split_upgrade_ore(0, 3).is_empty(), "no ore, no rows")


func _test_pick_local() -> void:
	var mix := {"silicate": 0.6, "ferrite": 0.3, "water_ice": 0.1}
	var seen := {}
	for i in 60:
		seen[Jobs.pick_local(mix, "job %d" % i)] = true
	_check(seen.has("silicate") and seen.has("ferrite"), "picks vary with the job: %s" % [seen.keys()])
	_check(not seen.has("water_ice"), "no water ice unless it's an ice job")
	_check(not seen.has("cuprite"), "only ores the belts carry")
	_check(Jobs.pick_local(mix, "same") == Jobs.pick_local(mix, "same"), "the same job keeps its ore")
	_check(Jobs.pick_local({}, "x") == "silicate", "an empty mix means silicate")


func _test_hard_jobs() -> void:
	var hard := 0
	for i in 600:
		if Jobs.is_hard("job %d" % i, Jobs.HARD_MIN_DEPTH):
			hard += 1
		_check(not Jobs.is_hard("job %d" % i, Jobs.HARD_MIN_DEPTH - 1), "never hard near home")
	_check(hard > 60 and hard < 140, "about 1 in %d deep jobs is hard (%d of 600)" % [Jobs.HARD_ONE_IN, hard])
	_check(Jobs.missing_rare({"silicate": 0.9, "ferrite": 0.1}) == "thorium", "the rarest missing ore first")
	_check(Jobs.missing_rare({"thorium": 0.1, "cuprite": 0.1, "ferrite": 0.1}) == "", "nothing missing")


func _test_rewrite() -> void:
	_check(Jobs.rewrite("Bring 35 m3 of ore to the main station.", "ferrite") == "Bring 35 m3 of ferrite to the main station.", "bare ore becomes the type: %s" % Jobs.rewrite("Bring 35 m3 of ore to the main station.", "ferrite"))
	_check(Jobs.rewrite("Silicate Run", "cuprite") == "Cuprite Run", "another ore's name becomes the type")
	_check(Jobs.rewrite("Ore's cheap here.", "ferrite") == "Ferrite's cheap here.", "capitals kept")
	_check(Jobs.rewrite("haul the silicate ore", "ferrite") == "haul the ferrite ore", "no doubled name: %s" % Jobs.rewrite("haul the silicate ore", "ferrite"))
	_check(Jobs.rewrite("the core is stored", "ferrite") == "the core is stored", "words containing 'ore' are left alone")
	var job := {"title": "Silicate Run", "agent_name": "Ore Baron", "objective": {"type": "DELIVER_ORE", "ore_type": ""}, "dialogue": "Ore, now."}
	var out: Dictionary = Jobs.rewrite_job(job, "thorium")
	_check(str(out["title"]) == "Thorium Run" and str(out["dialogue"]) == "Thorium, now.", "a job's text is rewritten")
	_check(str(out["agent_name"]) == "Ore Baron", "names are left alone")


# Playtest 2026-10-10 finding 6: the board's written text names the ore too.
func _test_board_text() -> void:
	var offer := {"title": "[URGENT] 35 m3 Ore Needed Before The Coolant Learns New Physics",
		"body": "Need 35 m3 ore delivered to the main station.",
		"generated_briefing": "Bring 35 m3 ore to the main station. Ignore any bucket labeled 'evidence'.",
		"quest_data": {"objective": {"type": "DELIVER_ORE", "ore_type": "silicate", "amount_required": 35.0},
			"dialogue_response": "Bring 35 m3 ore to the main station. Ignore any bucket labeled 'evidence'."}}
	var out: Dictionary = preload("res://scripts/domain/MissionTextGenerator.gd")._name_the_ore(offer)
	_check(str(out["title"]).contains("Silicate") and not str(out["title"]).contains(" Ore "), "the board title names the ore: %s" % out["title"])
	_check(str(out["body"]).contains("35 m3 silicate"), "the body too: %s" % out["body"])
	_check(str(out["generated_briefing"]).contains("silicate") and str(out["quest_data"]["dialogue_response"]).contains("silicate"), "the briefing and the accept line too")
	var fuel := {"title": "Fuel Run", "quest_data": {"objective": {"type": "DELIVER_ORE", "ore_type": "fuel"}}}
	_check(preload("res://scripts/domain/MissionTextGenerator.gd")._name_the_ore(fuel) == fuel, "fuel jobs are left alone")
