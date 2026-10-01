extends SceneTree

## Core loop step 7 (docs/core_loop_plan_2026_10_01.md 3.6): an automated
## captain climbs the gate ladder using the game's REAL numbers (upgrade
## costs and power, materials by tier, ore prices by depth, board pay and
## threat by depth, drone price) and the real purchase rules
## (GlobalState.purchase_upgrade, UpgradeGoal.suggest). It prints the
## simulated minutes to each rung against the plan's targets.
##
## Not a physics run: each action is a "trip" with an estimated duration. The
## estimates are the constants below, deliberately named so they're easy to
## argue with.
##   Godot --headless --path . --script res://tools/economy_sim.gd --log-file <path>

const GateClass := preload("res://scripts/domain/GateClass.gd")
const Goal := preload("res://scripts/domain/UpgradeGoal.gd")
const Scaling := preload("res://scripts/domain/DepthScaling.gd")

# ── Assumptions (seconds and credits) ──────────────────────────────────────
## Credits after the tutorial contract (Abe's screenshot showed ~310).
const START_CREDITS := 300
## Flying to a belt and back to a station, per trip.
const MINING_TRAVEL_S := 90.0
## Lining up the next rock, per rock (rocks hold ~20 m³).
const ROCK_SWITCH_S := 8.0
const ROCK_SIZE_M3 := 20.0
## A typical board job: time and base pay (before depth scaling).
const JOB_TIME_S := 420.0
const JOB_BASE_PAY := 140.0
## A drone dive: finding a red rock, flying out, the dive itself, back.
const DIVE_TIME_S := 360.0
const DRONE_PRICE := 800
## Clean-enough runs bring home one of the rock's material (a clean run also
## has a 50% crystal chance); some runs come home empty or lose the drone.
const DIVE_SUCCESS := 0.75
const DIVE_CRYSTAL := 0.35
## How often the red rock the captain finds holds the material they need
## (rocks show their material before diving).
const DIVE_RIGHT_MATERIAL := 0.6
## A fight (claim jumper, seam guard): time and repair bill.
const FIGHT_TIME_S := 180.0
const FIGHT_REPAIR := 60.0
## Share of mining trips that cut rare ore (and so draw a claim jumper).
const RARE_TRIP_SHARE_AT_DEPTH := 0.08
## Plan 3.6 targets: minutes to afford each rung from the previous one.
const TARGETS := {6: [20, 30], 8: [30, 40], 11: [45, 60], 15: [60, 75], 20: [75, 90]}
const MAX_HOURS := 40.0

var gs: Node
var _t := 0.0
var _drones := 1  # the first one is N.O.V.A.'s advance
var _depth := 0
var _log: Array[String] = []
## Scenario overrides from the command line (-- --drone-price=400 ...).
var drone_price := DRONE_PRICE
var ore_mult := 1.0
var job_mult := 1.0
var dive_yield := 2  # DroneMazeActivity.MATERIALS_PER_CLEAN_DIVE
var sim_seed := 12345
var label := "current numbers"
var _counts := {"mining_trips": 0, "jobs": 0, "dives": 0, "drones_bought": 0, "fights": 0, "upgrades": 0}


func _initialize() -> void:
	await process_frame
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"drone-price": drone_price = int(kv[1])
			"ore-mult": ore_mult = float(kv[1])
			"job-mult": job_mult = float(kv[1])
			"dive-yield": dive_yield = int(kv[1])
			"seed": sim_seed = int(kv[1])
			"label": label = kv[1].replace("_", " ")
	seed(sim_seed)
	gs = root.get_node("GlobalState")
	for sys in gs.current_upgrades:
		gs.current_upgrades[sys] = {"tier": 1, "path": "base"}
	gs.apply_upgrade_stats()
	gs.player_credits = START_CREDITS
	gs.player_storage_ore = 0.0
	gs.clear_cargo()
	for item in ["thermal_lattice", "rad_quartz", "cryo_ferrite", "resonant_crystal"]:
		gs.inventory.remove(item, gs.inventory.get_quantity(item))
	var rung_start := 0.0
	var reached := {}
	var rating := GateClass.ship_rating(GateClass.tiers_of(gs.current_upgrades))
	while _t < MAX_HOURS * 3600.0 and rating < 20:
		var goal: Dictionary = Goal.suggest(gs)
		if goal.is_empty():
			_log.append("No goal could be suggested at %.0f min." % (_t / 60.0))
			break
		_work_towards(goal)
		var now_rating := GateClass.ship_rating(GateClass.tiers_of(gs.current_upgrades))
		if now_rating != rating:
			rating = now_rating
			for threshold in TARGETS:
				if rating >= threshold and not reached.has(threshold):
					reached[threshold] = [(_t - rung_start) / 60.0, _t / 60.0]
					rung_start = _t
					_depth = _class_depth(threshold)
	_report(reached)
	quit(0)


## One step towards `goal`: whatever is shortest, or buy it.
func _work_towards(goal: Dictionary) -> void:
	var rows: Array = Goal.rows(gs, goal)
	var short := {}
	for row in rows:
		if int(row["have"]) < int(row["need"]):
			short[str(row["id"])] = int(row["need"]) - int(row["have"])
	if short.is_empty():
		if gs.purchase_upgrade(str(goal["sys"]), str(goal["path"])):
			_counts["upgrades"] += 1
			_log.append("%6.0f min  fitted %s (rating %d)" % [_t / 60.0, Goal.title(goal), GateClass.ship_rating(GateClass.tiers_of(gs.current_upgrades))])
		else:
			_log.append("%6.0f min  purchase refused for %s" % [_t / 60.0, Goal.title(goal)])
			_t += 60.0
		return
	# Materials first: they're the slow part.
	for id in short:
		if id in ["thermal_lattice", "rad_quartz", "cryo_ferrite", "resonant_crystal"]:
			if _drones <= 0:
				if gs.player_credits >= drone_price:
					gs.player_credits -= drone_price
					_drones += 1
					_counts["drones_bought"] += 1
				else:
					_earn_credits()
					return
			_dive(id)
			return
	if short.has("ore"):
		_mine(true)
		return
	if short.has("credits"):
		_earn_credits()
		return
	_t += 60.0  # power rows resolve through the goal changing


func _earn_credits() -> void:
	# Whichever pays more per second here: a board job, or mining and selling.
	var job_rate := JOB_BASE_PAY * job_mult * Scaling.pay_factor(_depth) / JOB_TIME_S
	var mine_rate := _hold_value() / _mining_trip_time(false)
	if job_rate >= mine_rate:
		_t += JOB_TIME_S
		gs.player_credits += int(JOB_BASE_PAY * job_mult * Scaling.pay_factor(_depth))
		_counts["jobs"] += 1
	else:
		_mine(false)


func _mine(bank: bool) -> void:
	_t += _mining_trip_time(bank)
	_counts["mining_trips"] += 1
	var hold: float = gs.cargo_max
	if bank:
		gs.player_storage_ore = minf(gs.player_storage_max, gs.player_storage_ore + hold)
	else:
		gs.player_credits += int(_hold_value())
	if _risk_active() and randf() < RARE_TRIP_SHARE_AT_DEPTH * maxf(1.0, float(_depth)) * 0.5:
		_fight()


func _dive(material: String) -> void:
	_t += DIVE_TIME_S
	_drones -= 1
	_counts["dives"] += 1
	if _risk_active() and randf() < preload("res://scripts/world/MiningRisk.gd").guard_chance(_depth):
		_fight()
	if randf() < DIVE_SUCCESS:
		var got: String = material if randf() < DIVE_RIGHT_MATERIAL or material == "resonant_crystal" else ["thermal_lattice", "rad_quartz", "cryo_ferrite"][randi() % 3]
		if got == "resonant_crystal":
			got = "rad_quartz" if randf() < 0.5 else "thermal_lattice"
			if randf() < DIVE_CRYSTAL:
				gs.inventory.add("resonant_crystal", 1, 99)
		gs.inventory.add(got, dive_yield, 99)
		if randf() < DIVE_CRYSTAL:
			gs.inventory.add("resonant_crystal", 1, 99)


func _fight() -> void:
	_t += FIGHT_TIME_S
	gs.player_credits = maxi(0, gs.player_credits - int(FIGHT_REPAIR * Scaling.threat_factor(_depth)))
	_counts["fights"] += 1


## The laser earns a fixed SC/s whatever the ore (rarer ore cuts slower). To
## bank, the captain cuts the fastest ore (silicate: the bank counts m³); to
## sell, a typical belt, which takes its value / SC-rate to fill.
func _mining_trip_time(bank: bool) -> float:
	var sc_rate: float = gs.mining_yield / maxf(gs.mining_cooldown, 0.05)
	var hold: float = gs.cargo_max
	var cutting := hold / sc_rate if bank else _hold_value() / ore_mult / sc_rate
	return MINING_TRAVEL_S + cutting + ceil(hold / ROCK_SIZE_M3) * ROCK_SWITCH_S


## A hold of this depth's typical belt, sold.
func _hold_value() -> float:
	var mix: Dictionary = preload("res://scripts/story/premise/SystemProfile.gd")._scale_rarity(
		{"silicate": 0.5, "water_ice": 0.2, "ferrite": 0.15, "cuprite": 0.1, "thorium": 0.05}, _depth)
	var per_m3 := 0.0
	for ore in mix:
		per_m3 += float(mix[ore]) * preload("res://scripts/economy/OreTypes.gd").price(str(ore))
	return per_m3 * float(gs.cargo_max) * ore_mult


func _risk_active() -> bool:
	return GateClass.ship_rating(GateClass.tiers_of(gs.current_upgrades)) > 5


## The shallowest depth whose gates need `rating`.
func _class_depth(rating: int) -> int:
	for depth in range(0, 40):
		if GateClass.rating_for_class(GateClass.class_for_depth(depth)) >= rating:
			return depth
	return 15


func _report(reached: Dictionary) -> void:
	print("")
	print("=== ECONOMY SIM (minutes) · %s · seed %d ===" % [label, sim_seed])
	print("rung  rating  this rung  total   target")
	for threshold in TARGETS:
		var target: Array = TARGETS[threshold]
		if reached.has(threshold):
			var r: Array = reached[threshold]
			var verdict := "ok" if float(r[0]) <= float(target[1]) * 1.25 else "SLOW"
			if float(r[0]) < float(target[0]) * 0.6:
				verdict = "FAST"
			print("%4d  %6d  %9.0f  %5.0f   %d-%d  %s" % [_rung_class(threshold), threshold, float(r[0]), float(r[1]), int(target[0]), int(target[1]), verdict])
		else:
			print("%4d  %6d  not reached in %.0f h            %d-%d  SLOW" % [_rung_class(threshold), threshold, MAX_HOURS, int(target[0]), int(target[1])])
	var cells: Array[String] = []
	for threshold in TARGETS:
		cells.append("%.0f" % float(reached[threshold][0]) if reached.has(threshold) else "-")
	print("SIMROW %s|%d|%s" % [label, sim_seed, ",".join(cells)])
	print("counts: %s" % str(_counts))
	print("first steps:")
	for line in _log.slice(0, 14):
		print("  " + line)
	print("=== END ECONOMY SIM ===")


func _rung_class(rating: int) -> int:
	for c in range(1, 10):
		if GateClass.rating_for_class(c) >= rating:
			return c
	return 0
