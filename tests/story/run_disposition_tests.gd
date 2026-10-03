extends SceneTree

## Playtest 2026-10-03 findings 10/10b (Abe): Hostile = attacks on sight;
## Territorial = only if you get too close; safeguards (the receiver) count
## hostile ships, never territorial ones keeping to themselves.
##   Godot --headless --path . --script res://tests/story/run_disposition_tests.gd --log-file <path> -- --baseline-offline

const NPC_SCENE := "res://scenes/npc_ship.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GlobalState")
	var saved_reps: Dictionary = gs.reputations.duplicate(true)
	# Factions.
	for pirate in ["reavers", "obsidian", "wraiths", "faction.reavers"]:
		_check(gs.faction_disposition(pirate) == "hostile" and gs.is_pirate_faction(pirate), "%s: hostile pirates" % pirate)
	for guard in ["dustborn", "ironclad"]:
		_check(gs.faction_disposition(guard) == "territorial" and not gs.is_pirate_faction(guard), "%s: territorial" % guard)
	_check(gs.faction_disposition("gen_salvage_compact_00") == "territorial", "a generated frontier faction: territorial")
	gs.reputations["gen_salvage_compact_00"] = -55.0
	_check(gs.faction_disposition("gen_salvage_compact_00") == "hostile", "...until pushed to -50")
	gs.reputations["zenith"] = 0.0
	_check(gs.faction_disposition("zenith") == "peaceful", "a major in good standing: peaceful")
	gs.reputations["zenith"] = -20.0
	_check(gs.faction_disposition("zenith") == "territorial", "a major out of favour: territorial")
	gs.reputations["zenith"] = -60.0
	_check(gs.faction_disposition("zenith") == "hostile", "a major that hates you: hostile")
	gs.reputations = saved_reps

	# Registry ids to runtime keys (finding 11: every generated faction became "generated").
	_check(gs.faction_runtime_key("faction.zenith") == "zenith", "faction.zenith -> zenith")
	_check(gs.faction_runtime_key("faction.generated.89d3b557db62.f2") == "gen_89d3b557db62_f2", "a generated id -> its gen_ key")
	_check(gs.faction_runtime_key("gen_89d3b557db62_f2") == "gen_89d3b557db62_f2", "a gen_ key stays")

	# Ships: roles and provocation.
	var scene := load(NPC_SCENE) as PackedScene
	var hauler: Node3D = _ship(scene, "gen_pilgrim_fleet_01", "Logistics")
	var gunner: Node3D = _ship(scene, "gen_pilgrim_fleet_01", "Gunner")
	var reaver: Node3D = _ship(scene, "reavers", "Logistics")
	var traffic: Node3D = _ship(scene, "zenith", "Logistics")
	traffic.set_meta("civilian_traffic", true)
	_check(gs.ship_disposition(hauler) == "peaceful", "a frontier hauler never starts it")
	_check(gs.ship_disposition(gunner) == "territorial", "a frontier gunship guards its patch")
	_check(gs.ship_disposition(reaver) == "hostile", "a Reaver is hostile whatever it flies")
	_check(gs.ship_disposition(traffic) == "peaceful", "station traffic is peaceful")
	gunner.set("last_attacker_faction", "player")
	_check(gs.ship_disposition(gunner) == "hostile", "shoot first and they defend themselves")
	gunner.set("last_attacker_faction", "")

	# Territorial: hail inside the perimeter, strike when crowded or after a while.
	var g = gunner
	_check(not g._territorial_engage(g.TERRITORIAL_WARN + 50.0, 1.0), "outside the perimeter: nothing")
	_check(not g._territorial_engage(g.TERRITORIAL_WARN - 20.0, 1.0) and g._perimeter_hailed, "inside it: a warning, no shots")
	_check(g._territorial_engage(g.TERRITORIAL_STRIKE - 10.0, 1.0), "too close: they strike")
	g._perimeter_since_msec = Time.get_ticks_msec() - int(g.TERRITORIAL_PATIENCE_S * 1000.0) - 10
	_check(g._territorial_engage(g.TERRITORIAL_WARN - 20.0, 1.0), "lingering inside: they strike")
	_check(g.HOSTILE_NOTICE > g.TERRITORIAL_WARN and g.HOSTILE_LEASH > g.HOSTILE_NOTICE and g.TERRITORIAL_LEASH > g.TERRITORIAL_WARN, "ranges in order")

	# The receiver: a territorial ship nearby doesn't block it; a hostile one does.
	var player: Node3D = Node3D.new()
	root.add_child(player)
	var saved_player = gs.player
	gs.player = player
	var receiver = load("res://scripts/story/activities/SignalTuningActivity.gd").new()
	root.add_child(receiver)
	for ship in [hauler, reaver, traffic]:
		ship.global_position = Vector3(100000, 0, 0)
	gunner.global_position = Vector3(450, 0, 0)
	_check(receiver.threat_label().is_empty(), "a territorial gunship at 450 m keeping to itself: the receiver works")
	reaver.global_position = Vector3(800, 0, 0)
	var label: String = receiver.threat_label()
	_check(label.contains("800 m"), "a Reaver at 800 m blocks it, by name and distance: %s" % label)
	reaver.global_position = Vector3(2000, 0, 0)
	_check(receiver.threat_label().is_empty(), "a Reaver far off doesn't")
	gunner.set("target", player)
	_check(not receiver.threat_label().is_empty(), "a territorial ship actually on us does")
	gunner.set("target", null)
	gs.player = saved_player

	if _failures.is_empty():
		print("[PASS] Hostile and territorial")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _ship(scene: PackedScene, faction: String, role: String) -> Node3D:
	var ship: Node3D = scene.instantiate()
	ship.set("faction", faction)
	ship.set("ship_role", role)
	ship.set("persistent_id", "test.%s.%s.%d" % [faction, role, randi()])
	root.add_child(ship)
	ship.set_physics_process(false)
	ship.set_process(false)
	return ship


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
