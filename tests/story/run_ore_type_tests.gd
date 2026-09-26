extends SceneTree

## Ore types (vision plan, Phase 4): the hold and storage keep their mix by
## type, rarer ores sell for more, each system's belts carry silicate plus two
## other ores, rocks keep their type, and a delivery that names an ore counts
## only that ore.
##   Godot --headless --path . --script res://tests/story/run_ore_type_tests.gd --log-file <path> -- --baseline-offline

const Ores := preload("res://scripts/economy/OreTypes.gd")
const Profile := preload("res://scripts/story/premise/SystemProfile.gd")
const Adapter := preload("res://scripts/domain/MissionAdapter.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GlobalState")
	# Loaded at run time: these scripts name the GlobalState autoload.
	var AsteroidScript: GDScript = load("res://scripts/Asteroid.gd")
	var DeliverOre: GDScript = load("res://scripts/domain/capabilities/DeliverOreCapability.gd")

	# The mix maths.
	_check(Ores.reconcile({}, 12.0) == {"silicate": 12.0}, "unaccounted ore is silicate")
	var shrunk := Ores.reconcile({"ferrite": 10.0, "silicate": 10.0}, 10.0)
	_check(is_equal_approx(float(shrunk["ferrite"]), 5.0), "a mix bigger than the total shrinks evenly")
	_check(Ores.reconcile({"unobtainium": 4.0}, 4.0) == {"silicate": 4.0}, "unknown types are silicate")
	var taken: Array = Ores.take({"ferrite": 6.0, "silicate": 4.0}, 10.0, 5.0, "ferrite")
	_check(is_equal_approx(float(taken[1]), 5.0) and is_equal_approx(float(taken[0]["ferrite"]), 1.0), "taking a type takes only it")
	_check(Ores.value({"ferrite": 10.0, "silicate": 10.0}) == 26, "ferrite sells at 1.6x")
	_check(Ores.normalize("Water Ice") == "water_ice" and Ores.normalize("rock") == "silicate", "names normalize")

	# The hold.
	gs.clear_cargo()
	gs.add_ore(10.0, "ferrite")
	gs.add_ore(5.0)
	_check(is_equal_approx(gs.cargo, 15.0) and is_equal_approx(gs.cargo_ore_amount("ferrite"), 10.0), "the hold keeps its mix")
	_check(gs.cargo_ore_value() == 21, "and sells by type (16 + 5 = %d)" % gs.cargo_ore_value())
	_check(gs.cargo_display_text().contains("Ferrite"), "the HUD names the main ore: %s" % gs.cargo_display_text())
	gs.remove_ore(4.0, "ferrite")
	_check(is_equal_approx(gs.cargo, 11.0) and is_equal_approx(gs.cargo_ore_amount("ferrite"), 6.0), "removing a type removes only it")
	gs.remove_ore(5.5)
	_check(is_equal_approx(gs.cargo, 5.5) and is_equal_approx(gs.cargo_ore_amount("ferrite"), 3.0), "an untyped removal takes evenly")
	# Code that sets the total directly (old saves, tests) still reads sanely.
	gs.cargo = 2.0
	var mix: Dictionary = gs.cargo_ore_mix()
	_check(is_equal_approx(float(mix.get("ferrite", 0.0)) + float(mix.get("silicate", 0.0)), 2.0), "a total set directly stays consistent")
	gs.clear_cargo()
	_check(gs.cargo_ore_mix().is_empty(), "a cleared hold has no mix")

	# Storage: depositing moves the mix; upgrades spend from both.
	gs.player_storage_ore = 0.0
	gs.storage_ore_types = {}
	gs.add_ore(8.0, "cuprite")
	gs.add_ore(2.0)
	_check(gs.deposit_ore(10.0), "deposit works")
	var stored: Dictionary = gs.storage_ore_mix()
	_check(is_equal_approx(float(stored.get("cuprite", 0.0)), 8.0) and is_equal_approx(float(stored.get("silicate", 0.0)), 2.0), "the mix moves into storage: %s" % str(stored))
	gs.player_storage_ore = 0.0
	gs.storage_ore_types = {}

	# Belts: silicate plus two others, the same every time, tutorial plain.
	var seen := {}
	for i in 200:
		var quirks: Array = ["pulsar"] if i % 5 == 0 else []
		var m: Dictionary = Profile.ore_mix("system.gen_%d" % i, 100 + i, ["red", "white", "blue", "orange", "yellow"][i % 5], quirks)
		var sum := 0.0
		for k in m:
			sum += float(m[k])
			seen[k] = true
		_check(is_equal_approx(sum, 1.0) and m.size() >= 3 and m.size() <= 4 and float(m["silicate"]) >= 0.5, "a belt is mostly silicate plus two others (and ice for fuel): %s" % str(m))
		_check(float(m.get("thorium", 0.0)) <= Profile.THORIUM_MAX_SHARE + 0.0001, "thorium stays rare")
	for ore in Ores.TYPES:
		_check(seen.has(ore), "%s turns up somewhere" % ore)
	_check(Profile.ore_mix("system.x", 5, "red", []) == Profile.ore_mix("system.x", 5, "red", []), "a system's belts never change")
	_check(Profile.generate("system.start", 1, "yellow", true)["ores"] == {"silicate": 1.0}, "the tutorial belt is plain silicate")

	# Rare ore grows with distance from the start (Abe): mostly plain rock
	# early on, no thorium until three jumps out.
	for i in 60:
		var id := "system.depth_%d" % i
		var star: String = ["red", "white", "blue", "orange", "yellow"][i % 5]
		var q: Array = ["pulsar"]
		_check(Profile.ore_mix(id, i, star, q, 0) == {"silicate": 1.0}, "the start system's belts are plain rock")
		var one: Dictionary = Profile.ore_mix(id, i, star, q, 1)
		var rare_one := 0.0
		for k in one:
			if k != "silicate" and k != "water_ice":
				rare_one += float(one[k])
		_check(rare_one <= 0.0801 and float(one.get("water_ice", 0.0)) >= Profile.ICE_FLOOR - 0.0001, "one jump out: 8%% rare at most, and ice for fuel: %s" % str(one))
		for d in [1, 2]:
			_check(not Profile.ore_mix(id, i, star, q, d).has("thorium"), "no thorium %d jumps out" % d)
		_check(Profile.ore_mix(id, i, star, q, 9) == Profile.ore_mix(id, i, star, q, -1), "far out: full rarity")
	var rare_by_depth: Array = []
	for d in 7:
		var total := 0.0
		for i in 40:
			total += 1.0 - float(Profile.ore_mix("system.r%d" % i, i, "yellow", [], d)["silicate"])
		rare_by_depth.append(total / 40.0)
	for d in range(1, 7):
		_check(float(rare_by_depth[d]) > float(rare_by_depth[d - 1]), "rarer ore grows with every jump: %s" % str(rare_by_depth))
	var links := {"start": ["a", "b"], "a": ["start", "c"], "b": ["start"], "c": ["a", "d"], "d": ["c"]}
	_check(Profile.gate_depth(links, "start", "start") == 0 and Profile.gate_depth(links, "start", "c") == 2 and Profile.gate_depth(links, "start", "d") == 3, "jumps from the start")
	_check(Profile.gate_depth(links, "start", "nowhere") == -1, "unreachable is unknown")

	# Rocks draw from the mix by id.
	var belt := {"silicate": 0.6, "ferrite": 0.28, "water_ice": 0.12}
	var counts := {}
	for i in 2000:
		var t: String = AsteroidScript.ore_type_for("asteroid.%d" % i, belt)
		counts[t] = int(counts.get(t, 0)) + 1
	_check(abs(int(counts.get("ferrite", 0)) - 560) < 90 and abs(int(counts.get("water_ice", 0)) - 240) < 70, "rocks follow the belt mix: %s" % str(counts))
	_check(AsteroidScript.ore_type_for("asteroid.7", belt) == AsteroidScript.ore_type_for("asteroid.7", belt), "a rock keeps its type")

	# A delivery that names an ore counts only that ore.
	var offer := {"title": "Ferrite run", "faction": "neutral", "agent_name": "Vessa Orl", "dialogue": "Bring ferrite.",
		"objective": {"type": "DELIVER_ORE", "amount_required": 10.0, "ore_type": "ferrite", "reward_credits": 300},
		"choices": [{"text": "Accept contract.", "consequence": {"credits_immediate": 0, "reputation_change": {},
			"combat_multiplier": 1.0, "reward_credits_multiplier": 1.0, "dialogue_response": "Good."}}]}
	var built := Adapter.build_active_state(offer, offer["choices"][0], "mission.runtime.ore", "system.test", 0)
	_check(built["validation"].is_valid() and str(built["state"].get("ore_type", "")) == "ferrite", "the job remembers its ore")
	var cap = DeliverOre.new()
	var data: Dictionary = built["state"]
	gs.clear_cargo()
	gs.add_ore(12.0)
	_check(not cap.is_completed(data), "silicate does not fill a ferrite order")
	_check(cap.format_tracker_text(data).begins_with("Ferrite: 0"), "the tracker names the ore: %s" % cap.format_tracker_text(data))
	gs.clear_cargo()
	gs.add_ore(5.0)
	gs.add_ore(10.0, "ferrite")
	_check(cap.is_completed(data), "ferrite does")
	var hints: Dictionary = cap.on_complete(data)
	_check(str(hints.get("remove_ore_type", "")) == "ferrite", "and only ferrite is taken on completion")
	var untyped := offer.duplicate(true)
	untyped["objective"].erase("ore_type")
	var any_ore: Dictionary = Adapter.build_active_state(untyped, untyped["choices"][0], "mission.runtime.ore2", "system.test", 0)["state"]
	gs.clear_cargo()
	gs.add_ore(12.0, "water_ice")
	_check(cap.is_completed(any_ore), "a job naming no ore takes any ore")
	gs.clear_cargo()

	# Story cards only ask for ore the belts here carry.
	var Selector: GDScript = load("res://scripts/story/premise/PremiseCardSelector.gd")
	var card := {"id": "test.ferrite", "requirements": {}, "beats": [{"n": 1, "missions": [{"verb": "deliver_ore", "ore": "ferrite"}]}]}
	var here := {"faction_count": 3, "ores": ["silicate", "water_ice", "cuprite"]}
	_check(str(Selector.rejection(card, here)) == "needs ore ferrite", "no ferrite belt, no ferrite story")
	here["ores"] = ["silicate", "ferrite", "cuprite"]
	_check(str(Selector.rejection(card, here)).is_empty(), "a ferrite belt allows it")
	_check(str(Selector.rejection(card, {"faction_count": 3})).is_empty(), "without belt data, ore is not checked")
	var Library: GDScript = load("res://scripts/story/premise/PremiseCardLibrary.gd")
	var lib = Library.new()
	lib.load_from_dir()
	var needing := 0
	for id in lib.ids():
		if not (Selector.needed_ores(lib.get_card(id)) as Array).is_empty():
			needing += 1
	_check(needing > 0, "some cards ask for other ores")
	print("[OreTypes] %d of %d approved cards ask for an ore other than silicate" % [needing, lib.size()])

	if _failures.is_empty():
		print("[PASS] Ore types")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
