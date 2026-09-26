extends SceneTree

## Fuel (Abe, 2026-09-26): jumps and the boost burn hydrogen, jumps further
## out cost more, water ice refines into fuel at a station (cheaper than
## buying it), and an empty tank stops only jumps.
##   Godot --headless --path . --script res://tests/story/run_fuel_tests.gd --log-file <path> -- --baseline-offline

const Fuel := preload("res://scripts/economy/Fuel.gd")
const Profile := preload("res://scripts/story/premise/SystemProfile.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GlobalState")

	_check(Fuel.jump_cost(1) < Fuel.jump_cost(4) and Fuel.jump_cost(30) == Fuel.JUMP_MAX, "jumps further out cost more, up to a cap")
	_check(Fuel.TANK_MAX / Fuel.jump_cost(1) >= 8.0, "a full tank covers several early jumps")
	var r: Array = Fuel.refine(40.0, 90.0)
	_check(is_equal_approx(float(r[0]), 10.0) and is_equal_approx(float(r[1]), 10.0), "refining stops at a full tank and uses only the ice it needs")
	_check(Fuel.REFINE_FEE < Fuel.BUY_PRICE and Fuel.FUEL_PER_ICE * 1.3 < Fuel.BUY_PRICE, "mining ice is the cheap way (cheaper than buying, better than selling the ice)")
	var b: Array = Fuel.buy_to_full(50.0, 30)
	_check(is_equal_approx(float(b[0]), 10.0) and int(b[1]) == 30, "buying stops at what the captain can afford")

	# The tank.
	gs.fuel = Fuel.TANK_MAX
	_check(gs.spend_fuel(12.0) and is_equal_approx(gs.fuel, 88.0), "a jump spends fuel")
	gs.fuel = 5.0
	_check(not gs.spend_fuel(12.0) and is_equal_approx(gs.fuel, 5.0), "not enough: nothing is spent")
	gs.clear_cargo()
	gs.add_ore(20.0, "water_ice")
	gs.add_ore(10.0)
	gs.player_credits = 100
	var gained: float = gs.refine_ice_to_fuel()
	_check(is_equal_approx(gained, 20.0) and is_equal_approx(gs.fuel, 25.0) and gs.player_credits == 90, "the hold's ice becomes fuel for a small fee")
	_check(is_equal_approx(gs.cargo_ore_amount("water_ice"), 0.0) and is_equal_approx(gs.cargo, 10.0), "only the ice is used")
	_check(is_equal_approx(gs.refine_ice_to_fuel(), 0.0), "no ice, nothing to refine")
	gs.player_credits = 60
	var bought: float = gs.buy_fuel_to_full()
	_check(is_equal_approx(bought, 20.0) and gs.player_credits == 0, "buying fuel as far as credits allow")
	gs.clear_cargo()
	gs.fuel = Fuel.TANK_MAX

	# Cruising sips; an empty tank still flies (slower, no boost).
	gs.fuel = 10.0
	gs.sip_fuel(0.03)
	_check(is_equal_approx(gs.fuel, 10.0), "tiny sips wait until they add up")
	gs.sip_fuel(0.03)
	_check(is_equal_approx(gs.fuel, 9.94), "then come off the tank (%.3f)" % gs.fuel)
	_check(Fuel.CRUISE_SIP_PER_SECOND * 600.0 < Fuel.JUMP_BASE, "ten minutes of full-speed cruising costs less than one jump")
	gs.fuel = 0.2
	_check(gs.is_fuel_empty() and Fuel.EMPTY_SPEED_MULT == 0.6, "nearly dry counts as empty: 60% speed")
	gs.fuel = Fuel.TANK_MAX
	_check(not gs.is_fuel_empty(), "a full tank is not empty")
	# N.O.V.A. has plenty to say about it, never the same line twice in a row.
	var nova: Node = root.get_node_or_null("Nova")
	if nova != null:
		var lines: Array = nova.FUEL_EMPTY_DOCK_LINES
		var distinct := {}
		for l in lines:
			distinct[l] = true
		_check(lines.size() >= 20 and distinct.size() == lines.size(), "twenty different empty-tank dock lines")
		var heard := {}
		for i in lines.size():
			heard[nova._pick_line("dock_fuel_empty", lines)] = true
		_check(heard.size() == lines.size(), "each heard once before any repeats")
		# When Kaelen opens the start system's gate, she says where the ice is.
		var discovery: Node = root.get_node_or_null("GateDiscovery")
		if discovery != null:
			var saved_system = gs.current_system_id
			gs.current_system_id = "start_system"
			nova._told_no_home_ice = false
			discovery.gate_state_changed.emit("gate.test", "rumored", "known")
			_check(nova._told_no_home_ice, "opening the home gate brings the no-ice line")
			gs.current_system_id = saved_system

	# Fuel runs (Abe): someone is short on fuel for a reason, and something
	# happens if it does not arrive; the fuel comes out of the tank.
	var Board: GDScript = load("res://scripts/domain/PublicBoardOfferBuilder.gd")
	var Adapter: GDScript = load("res://scripts/domain/MissionAdapter.gd")
	var DeliverOre: GDScript = load("res://scripts/domain/capabilities/DeliverOreCapability.gd")
	var titles := {}
	var run: Dictionary = {}
	for i in 40:
		var offer: Dictionary = Board._build_fuel_offer(i * 120)
		if offer.is_empty():
			continue
		run = offer
		titles[str(offer["title"])] = true
		var q: Dictionary = offer["quest_data"]
		_check(str(q["objective"]["ore_type"]) == "fuel" and not str(q["dialogue"]).contains("{"), "a fuel run asks for fuel: %s" % q["dialogue"])
	_check(titles.size() >= 5, "fuel runs vary (%d kinds)" % titles.size())
	_check(Board._build_fuel_offer(360) == Board._build_fuel_offer(400), "the same posting within a board window")
	if not run.is_empty():
		var q2: Dictionary = run["quest_data"]
		var built: Dictionary = Adapter.build_active_state(q2, q2["choices"][0], "mission.runtime.fuelrun", "system.test", 0)
		_check(built["validation"].is_valid() and str(built["state"]["ore_type"]) == "fuel", "a fuel run makes a valid job: %s" % built["validation"].summary())
		var data: Dictionary = built["state"]
		var cap = DeliverOre.new()
		gs.clear_cargo()
		gs.add_ore(50.0)
		gs.fuel = 2.0
		_check(not cap.is_completed(data), "ore in the hold is not fuel")
		gs.fuel = Fuel.TANK_MAX
		_check(cap.is_completed(data) and cap.format_tracker_text(data).begins_with("Fuel:"), "a full tank covers it: %s" % cap.format_tracker_text(data))
		var need := float(data["amount_required"])
		var given: float = gs.hand_over_delivery(need, "fuel")
		_check(is_equal_approx(given, need) and is_equal_approx(gs.fuel, Fuel.TANK_MAX - need) and is_equal_approx(gs.cargo, 50.0), "handing it over drains the tank, not the hold")
		_check(int(q2["objective"]["reward_credits"]) > int(need * Fuel.BUY_PRICE), "a fuel run pays more than the fuel costs to buy")
		gs.clear_cargo()
		gs.fuel = Fuel.TANK_MAX

	# Every belt past the start carries ice for fuel.
	for i in 40:
		for d in [1, 2, 5]:
			var m: Dictionary = Profile.ore_mix("system.fuel%d" % i, i, "yellow", [], d)
			_check(float(m.get("water_ice", 0.0)) >= Profile.ICE_FLOOR - 0.0001, "ice at %d jumps: %s" % [d, str(m)])
	_check(Profile.ore_mix("system.fuel0", 0, "yellow", [], 0) == {"silicate": 1.0}, "the start system stays plain rock")

	if _failures.is_empty():
		print("[PASS] Fuel")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
