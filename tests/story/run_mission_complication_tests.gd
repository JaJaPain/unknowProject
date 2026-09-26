extends SceneTree

## Mission complications: about half the jobs get one, seeded per mission,
## filtered by verb and quirk, and each one really changes the job (and still
## makes a valid mission).
##   Godot --headless --path . --script res://tests/story/run_mission_complication_tests.gd --log-file <path>

const Comp := preload("res://scripts/story/premise/MissionComplications.gd")
const Adapter := preload("res://scripts/domain/MissionAdapter.gd")

var _failures: Array[String] = []


func _offer(objective: Dictionary) -> Dictionary:
	return {"title": "Test job", "faction": "neutral", "agent_name": "Vessa Orl", "dialogue": "Needs it moved.",
		"objective": objective, "choices": [{"text": "Accept contract.", "consequence": {"credits_immediate": 0,
		"reputation_change": {}, "combat_multiplier": 1.0, "reward_credits_multiplier": 1.0, "dialogue_response": "Good."}}]}


func _initialize() -> void:
	await process_frame
	# Seeded, and about half the time.
	var hits := 0
	for i in 400:
		if not Comp.roll("delivery_courier", [], "seed|%d" % i).is_empty():
			hits += 1
	_check(hits > 160 and hits < 240, "about half the jobs are complicated (%d/400)" % hits)
	_check(Comp.roll("kill_ships", [], "same") == Comp.roll("kill_ships", [], "same"), "the same job always rolls the same")
	var storm_any := false
	var storm_calm := false
	for i in 200:
		if str(Comp.roll("delivery_courier", ["ion_storm"], "k|%d" % i).get("id", "")) == "storm_window":
			storm_any = true
		if str(Comp.roll("delivery_courier", [], "k|%d" % i).get("id", "")) == "storm_window":
			storm_calm = true
	_check(storm_any and not storm_calm, "a storm window only where storms are")
	for i in 100:
		_check(Comp.roll("investigate_signal", ["ion_storm"], "inv|%d" % i).is_empty(), "investigations stay uncomplicated for now")

	var courier := {"type": "DELIVERY_COURIER", "item_name": "Sealed cargo", "origin_station_id": "station.a", "origin_display": "A",
		"destination_station_id": "station.b", "destination_display": "B", "reward_credits": 400}
	var by_id := {}
	for c in Comp.deck()["complications"]:
		by_id[c["id"]] = c

	var timed := Comp.apply(_offer(courier), by_id["deadline"], "Vessa Orl")
	_check(timed["timing"]["timed"] and int(timed["timing"]["duration_minutes"]) == 240, "a deadline is a real timer")
	_check(str(timed["dialogue"]).contains("within 4 hours"), "and the briefing says so: %s" % timed["dialogue"])
	var built := Adapter.build_active_state(timed, timed["choices"][0], "mission.runtime.comp", "system.test", 1000)
	_check(built["validation"].is_valid() and bool(built["state"]["is_timed"]) and int(built["state"]["deadline_time_minutes"]) == 1240, "and the mission expires on time")
	var built_advance := Adapter.build_active_state(Comp.apply(_offer(courier), by_id["advance_paid"], "V"), _offer(courier)["choices"][0], "mission.runtime.comp2", "system.test", 0)
	_check(built_advance["validation"].is_valid(), "an advance makes a valid mission")

	var advance := Comp.apply(_offer(courier), by_id["advance_paid"], "Vessa Orl")
	_check(int(advance["choices"][0]["consequence"]["credits_immediate"]) == 120 and int(advance["objective"]["reward_credits"]) == 320, "an advance: 120 now, 320 later")
	_check(str(advance["dialogue"]).contains("Vessa Orl pays part of it up front, 120 credits"), "named in the briefing: %s" % advance["dialogue"])

	var kill := Comp.apply(_offer({"type": "KILL_SHIPS", "target_faction": "reavers", "count_required": 3, "reward_credits": 400}), by_id["heavy_escort"], "")
	_check(int(kill["objective"]["count_required"]) == 4 and int(kill["objective"]["reward_credits"]) == 500, "one more ship, more pay")
	var ore := Comp.apply(_offer({"type": "DELIVER_ORE", "amount_required": 20.0, "ore_type": "silicate", "reward_credits": 300}), by_id["bigger_load"], "")
	_check(is_equal_approx(float(ore["objective"]["amount_required"]), 30.0) and int(ore["objective"]["reward_credits"]) == 390, "a bigger load, more pay")
	_check(Comp.apply(_offer(courier), {}, "x") == _offer(courier), "no complication, no change")

	# Twelve, and every one makes a valid mission on every verb it names.
	_check(by_id.size() >= 12, "the starter deck has 12 (%d)" % by_id.size())
	var objectives := {
		"delivery_courier": courier,
		"purchase_delivery": courier,
		"pickup_special": courier,
		"deliver_ore": {"type": "DELIVER_ORE", "amount_required": 20.0, "ore_type": "silicate", "reward_credits": 300,
			"destination_station_id": "station.b", "destination_display": "B"},
		"kill_ships": {"type": "KILL_SHIPS", "target_faction": "reavers", "count_required": 3, "reward_credits": 400},
	}
	for id in by_id:
		for verb in by_id[id]["verbs"]:
			if not objectives.has(verb):
				continue
			var job := Comp.apply(_offer(objectives[verb]), by_id[id], "Vessa Orl")
			var made := Adapter.build_active_state(job, job["choices"][0], "mission.runtime.all.%s" % id, "system.test", 0)
			_check(made["validation"].is_valid(), "%s on %s makes a valid mission: %s" % [id, verb, str(made["validation"].errors)])
			_check(not str(job["dialogue"]).contains("{"), "%s: the briefing is filled in: %s" % [id, job["dialogue"]])
	# Quirk-bound ones only where the quirk is, and they win there.
	for pair in [["nebula_ambush", "delivery_courier", "nebula"], ["pulsar_window", "kill_ships", "pulsar"], ["evacuation_window", "pickup_special", "dying_star"]]:
		var seen_with := false
		var seen_without := false
		for i in 200:
			seen_with = seen_with or str(Comp.roll(pair[1], [pair[2]], "q|%d" % i).get("id", "")) == pair[0]
			seen_without = seen_without or str(Comp.roll(pair[1], [], "q|%d" % i).get("id", "")) == pair[0]
		_check(seen_with and not seen_without, "%s only with %s" % [pair[0], pair[2]])

	# Ambush: raiders come once, that far into undocked flight on the job.
	var ambushed := Comp.apply(_offer(courier), by_id["ambush_en_route"], "Vessa Orl")
	_check(int(ambushed["objective"]["ambush_count"]) == 2 and int(ambushed["objective"]["reward_credits"]) == 480, "an ambush: two raiders, more pay")
	var qm: Node = root.get_node("QuestManager")
	var gs: Node = root.get_node("GlobalState")
	var ship := CharacterBody3D.new()
	ship.set("is_docked", false)
	root.add_child(ship)
	var saved_player = gs.player
	gs.player = ship
	qm.restore_active_quest({})
	gs.clear_cargo()
	if qm.accept_quest(ambushed, ambushed["choices"][0]):
		qm._tick_ambush(30.0)
		_check(not bool(qm.active_quest.get("ambush_done", true)), "no ambush half a minute in")
		qm._tick_ambush(25.0)
		_check(bool(qm.active_quest.get("ambush_done", false)), "the ambush lands at 50 s, once")
	else:
		_check(false, "ambush job accepted: %s" % qm.last_validation_error)
	# A favour: less pay, standing with the client's faction on accepting.
	var fav_offer := _offer(courier)
	fav_offer["faction"] = "zenith"
	var fav := Comp.apply(fav_offer, by_id["favour"], "Vessa Orl")
	_check(int(fav["objective"]["reward_credits"]) == 280 and is_equal_approx(float(fav["choices"][0]["consequence"]["reputation_change"].get("zenith", 0.0)), 3.0), "a favour: 70% pay, +3 standing")
	var before: float = float(gs.reputations.get("zenith", 0.0))
	qm.restore_active_quest({})
	gs.clear_cargo()
	if qm.accept_quest(fav, fav["choices"][0]):
		_check(float(gs.reputations.get("zenith", 0.0)) > before, "taking it raises standing (%.1f -> %.1f)" % [before, float(gs.reputations.get("zenith", 0.0))])
	else:
		_check(false, "favour job accepted: %s" % qm.last_validation_error)
	qm.restore_active_quest({})
	gs.clear_cargo()
	gs.player = saved_player
	ship.free()

	if _failures.is_empty():
		print("[PASS] Mission complications")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
