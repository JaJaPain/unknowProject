extends SceneTree

## Mission twists: some story kill jobs turn mid-mission (a counter-offer or
## a surrender), the choice resolves the job, and the answer becomes story
## (the arc outcome and a deed).
##   Godot --headless --path . --script res://tests/story/run_mission_twist_tests.gd --log-file <path> -- --baseline-offline

const Twists := preload("res://scripts/story/premise/MissionTwists.gd")
const Arcs := preload("res://scripts/story/premise/ArcEngine.gd")
const Adapter := preload("res://scripts/domain/MissionAdapter.gd")

var _failures: Array[String] = []


class FakeShip extends CharacterBody3D:
	var is_docked := false
	var destroyed := false


func _kill_offer() -> Dictionary:
	return {"title": "Stop the Raven", "faction": "neutral", "agent_name": "Vessa Orl", "dialogue": "Stop them.",
		"objective": {"type": "KILL_SHIPS", "target_faction": "reavers", "count_required": 3, "reward_credits": 400},
		"choices": [{"text": "Accept contract.", "consequence": {"credits_immediate": 0, "reputation_change": {},
			"combat_multiplier": 1.0, "reward_credits_multiplier": 1.0, "dialogue_response": "Good."}}]}


func _initialize() -> void:
	await process_frame
	# Rolls: about a third of kill jobs, never other verbs, seeded.
	var hits := 0
	var kinds := {}
	for i in 600:
		var t := Twists.roll("kill_ships", "s|%d" % i)
		if not t.is_empty():
			hits += 1
			kinds[t["id"]] = true
			_check(not str(t["hail"]).is_empty(), "a twist has a hail line")
	_check(hits > 150 and hits < 270, "about a third of kill jobs twist (%d/600)" % hits)
	_check(kinds.has("counter_offer") and kinds.has("surrender"), "both twists appear")
	_check(Twists.roll("delivery_courier", "s|1").is_empty(), "couriers do not (yet)")
	_check(Twists.roll("kill_ships", "same") == Twists.roll("kill_ships", "same"), "seeded per job")

	var by_id := {}
	for t in Twists.deck()["twists"]:
		by_id[t["id"]] = (t as Dictionary).duplicate(true)
	var offer_t: Dictionary = by_id["counter_offer"]
	offer_t["hail"] = offer_t["hails"][0]
	var counter := Twists.apply(_kill_offer(), offer_t, "Vessa Orl", "the Raven")
	var obj: Dictionary = counter["objective"]
	_check(obj["type"] == "TARGET_WITH_COMMS_REVERSAL" and int(obj["bribe_amount"]) == 520, "a counter-offer beats the fee: %s" % str(obj))
	_check(str(obj["comms_reversal_line"]).contains("Vessa Orl"), "and names the client: %s" % obj["comms_reversal_line"])
	var built := Adapter.build_active_state(counter, counter["choices"][0], "mission.runtime.twist", "system.test", 0)
	_check(built["validation"].is_valid() and built["state"]["twist_id"] == "counter_offer" and built["state"]["reversal_kind"] == "bribe", "it builds a real mission that remembers the twist")

	var surrender_t: Dictionary = by_id["surrender"]
	surrender_t["hail"] = surrender_t["hails"][0]
	var surrender := Twists.apply(_kill_offer(), surrender_t, "Vessa Orl", "the Raven")
	_check(surrender["objective"]["reversal_kind"] == "surrender" and int(surrender["objective"]["spare_amount"]) == 240, "a surrender pays part of the fee to spare")

	# Playing it: the hail comes before the last kill; sparing closes the job.
	var qm: Node = root.get_node("QuestManager")
	var gs: Node = root.get_node("GlobalState")
	qm.restore_active_quest({})
	var hailed := [false]
	qm.comms_reversal_triggered.connect(func(_d: Dictionary) -> void: hailed[0] = true)
	var accepted: bool = qm.accept_quest(surrender, surrender["choices"][0])
	_check(accepted, "the twisted job is accepted: %s" % qm.last_validation_error)
	if accepted:
		gs.player_kill.emit("reavers")
		gs.player_kill.emit("reavers")
		_check(hailed[0], "the target hails before the last kill")
		var credits: int = gs.player_credits
		var finished := [{}]
		qm.quest_completed_details.connect(func(d: Dictionary) -> void: finished[0] = d, CONNECT_ONE_SHOT)
		qm.resolve_comms_branch("spare")
		_check(gs.player_credits == credits + 240 and not qm.is_quest_active(), "sparing pays part of the fee and closes the job")
		_check(str(finished[0].get("outcome_detail", "")) == "spared" and str(finished[0].get("twist_target_name", "")) == "the Raven", "and reports it: %s" % str(finished[0].get("outcome_detail")))

	# Wrong cargo: a courier crate that is not what the manifest says.
	var cargo_t: Dictionary = by_id["wrong_cargo"]
	cargo_t["hail"] = cargo_t["hails"][0]
	cargo_t["true_cargo_pick"] = "military targeting cores"
	var courier_offer := {"title": "Courier to Kova", "faction": "neutral", "agent_name": "Vessa Orl", "dialogue": "Move it.",
		"objective": {"type": "DELIVERY_COURIER", "item_name": "Grain samples", "origin_station_id": "station.a", "origin_display": "A",
			"destination_station_id": "station.b", "destination_display": "B", "reward_credits": 300},
		"choices": _kill_offer()["choices"]}
	var wrong := Twists.apply(courier_offer, cargo_t, "Vessa Orl", "")
	_check(str(wrong["objective"]["twist_reveal"]).contains("Grain samples") and str(wrong["objective"]["twist_reveal"]).contains("military targeting cores"), "the reveal names both: %s" % wrong["objective"]["twist_reveal"])
	var ship := FakeShip.new()
	root.add_child(ship)
	var saved_player = gs.player
	gs.player = ship
	for choice in ["deliver", "dump"]:
		qm.restore_active_quest({})
		gs.clear_cargo()
		var ok: bool = qm.accept_quest(wrong, wrong["choices"][0])
		_check(ok, "the courier job is accepted: %s" % qm.last_validation_error)
		if not ok:
			continue
		var revealed := [{}]
		qm.reveal_twist_triggered.connect(func(d: Dictionary) -> void: revealed[0] = d, CONNECT_ONE_SHOT)
		qm._tick_reveal_twist(30.0)
		_check(revealed[0].is_empty(), "not yet: half a minute in")
		qm._tick_reveal_twist(31.0)
		_check(str(revealed[0].get("twist_state", "")) == "revealed", "a minute into the flight N.O.V.A. scans the crate")
		qm.resolve_reveal_twist(choice)
		if choice == "deliver":
			_check(qm.is_quest_active() and str(qm.active_quest.get("twist_state", "")) == "delivering", "delivering it keeps the job")
		else:
			_check(not qm.is_quest_active(), "dumping it ends the job")
	# Only hidden truths that read as a fact about someone can be read aloud.
	_check(Twists.is_readable_fact("She is skimming the relief fund to pay her brother's debts."), "a plain hidden truth reads fine")
	_check(not Twists.is_readable_fact("The pilot discovers the survivor sitting calmly at a desk."), "narration of the pilot does not")
	_check(not Twists.is_readable_fact("He is stalling the pilot until the enforcers arrive."), "nor anything about the pilot")
	_check(not Twists.is_readable_fact(""), "nor nothing")

	# The client's lie: needs a hidden truth on the card mission.
	_check(Twists.roll("delivery_courier", "lie|x", false).get("id", "") != "client_lie", "no hidden truth, no client-lie twist")
	var lie_seen := false
	for i in 300:
		if str(Twists.roll("delivery_courier", "lie|%d" % i, true).get("id", "")) == "client_lie":
			lie_seen = true
	_check(lie_seen, "with one, it can come up")
	var lie_t: Dictionary = by_id["client_lie"]
	lie_t["hail"] = lie_t["hails"][0]
	var lied := Twists.apply(courier_offer, lie_t, "Vessa Orl", "", {"private_fact": "She is skimming the relief fund."})
	_check(str(lied["objective"]["twist_reveal"]).contains("skimming the relief fund"), "the reveal is the card's hidden truth: %s" % lied["objective"]["twist_reveal"])
	var rival_t: Dictionary = by_id["rival_on_the_job"]
	rival_t["hail"] = rival_t["hails"][0]
	var rivalled := Twists.apply(courier_offer, rival_t, "Vessa Orl", "", {"rival_name": "Kade Munro"})
	_check(str(rivalled["objective"]["twist_reveal"]).begins_with("Kade Munro here"), "the rival names themselves: %s" % rivalled["objective"]["twist_reveal"])

	# Expose the client: the job ends.
	qm.restore_active_quest({})
	gs.clear_cargo()
	if qm.accept_quest(lied, lied["choices"][0]):
		qm._tick_reveal_twist(61.0)
		_check(str(qm.active_quest.get("twist_state", "")) == "revealed", "the lie comes out a minute in")
		qm.resolve_reveal_twist("expose")
		_check(not qm.is_quest_active(), "exposing them ends the job")

	# The rival: split halves the pay; race runs a clock, and losing it expires the job.
	for choice in ["split", "race"]:
		qm.restore_active_quest({})
		gs.clear_cargo()
		if not qm.accept_quest(rivalled, rivalled["choices"][0]):
			_check(false, "rival job accepted: %s" % qm.last_validation_error)
			continue
		var full: int = qm.active_quest_payout()
		qm._tick_reveal_twist(61.0)
		qm.resolve_reveal_twist(choice)
		if choice == "split":
			_check(qm.active_quest_payout() == int(full / 2.0) or qm.active_quest_payout() == int(round(full / 2.0)), "splitting halves the fee (%d -> %d)" % [full, qm.active_quest_payout()])
		else:
			_check(str(qm.active_quest.get("twist_state", "")) == "racing", "racing starts the rival's clock")
			qm._tick_reveal_twist(qm.RIVAL_RACE_SECONDS - 10.0)
			_check(qm.is_quest_active(), "still in the race")
			qm._tick_reveal_twist(20.0)
			_check(not qm.is_quest_active(), "the rival got there first: the job is gone")

	# Stowaway, double booking, law change: the reveal names the stranger or
	# the law, and each answer changes the job.
	for id in ["stowaway", "double_booking", "law_change"]:
		var t: Dictionary = by_id[id]
		t["hail"] = t["hails"][0]
		t["law_pick"] = t.get("laws", [""])[0]
		var twisted := Twists.apply(courier_offer, t, "Vessa Orl", "", {"stranger_name": "Tamsin Rook"})
		var line := str(twisted["objective"]["twist_reveal"])
		_check(not line.contains("{"), "%s: every placeholder is filled: %s" % [id, line])
		_check(line.contains("Tamsin Rook") if id != "law_change" else line.contains("curfew"), "%s: the reveal names them: %s" % [id, line])
	var t_seen := {}
	for i in 900:
		t_seen[str(Twists.roll("deliver_ore", "new|%d" % i).get("id", ""))] = true
	_check(t_seen.has("stowaway") and t_seen.has("double_booking") and t_seen.has("law_change"), "all three can come up: %s" % str(t_seen.keys()))

	var cases := [["stowaway", "shelter"], ["stowaway", "turn_in"], ["double_booking", "honor"], ["double_booking", "switch"],
		["law_change", "comply"], ["law_change", "run"]]
	for c in cases:
		var t2: Dictionary = by_id[c[0]]
		t2["hail"] = t2["hails"][0]
		t2["law_pick"] = t2.get("laws", [""])[0]
		var job := Twists.apply(courier_offer, t2, "Vessa Orl", "", {"stranger_name": "Tamsin Rook"})
		qm.restore_active_quest({})
		gs.clear_cargo()
		if not qm.accept_quest(job, job["choices"][0]):
			_check(false, "%s job accepted: %s" % [c[0], qm.last_validation_error])
			continue
		var full: int = qm.active_quest_payout()
		var credits_before: int = gs.player_credits
		qm._tick_reveal_twist(61.0)
		_check(str(qm.active_quest.get("twist_state", "")) == "revealed", "%s: revealed a minute in" % c[0])
		qm.resolve_reveal_twist(c[1])
		match c[1]:
			"shelter", "honor":
				_check(qm.is_quest_active() and qm.active_quest_payout() == full, "%s keeps the job at full pay" % c[1])
			"turn_in":
				_check(qm.active_quest_payout() == int(round(full * 1.25)), "the bounty adds a quarter (%d -> %d)" % [full, qm.active_quest_payout()])
			"comply":
				_check(qm.active_quest_payout() == int(round(full * 0.75)), "the duty takes a quarter (%d -> %d)" % [full, qm.active_quest_payout()])
			"switch":
				_check(not qm.is_quest_active() and gs.player_credits == credits_before + 300, "switching pays the other side's fee now and drops the job")
			"run":
				_check(str(qm.active_quest.get("twist_state", "")) == "running", "running it keeps the job")
				qm._tick_reveal_twist(qm.LAW_SCAN_AFTER_SECONDS + 1.0)
				_check(bool(qm.active_quest.get("twist_scanned", false)), "a patrol scans us once")
				var fined := int(qm.active_quest.get("twist_fined", 0))
				_check(fined == 0 or gs.player_credits == credits_before - fined, "a catch is a fine (%d)" % fined)
	# Over many runs the patrol catches some and misses some.
	var caught := 0
	for i in 200:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("law_scan|mission.runtime.%d" % i)
		if rng.randf() < 0.4:
			caught += 1
	_check(caught > 50 and caught < 110, "about four in ten runs get fined (%d/200)" % caught)

	gs.player = saved_player
	ship.free()
	qm.restore_active_quest({})
	gs.clear_cargo()
	for branch in ["shelter", "turn_in", "switch", "run_law"]:
		var d := Twists.deed_for(branch, "Vessa Orl")
		_check(not d.is_empty() and not preload("res://scripts/story/premise/FactionDNA.gd").deed_signal(str(d["tag"])).is_empty(), "%s leaves a deed factions understand: %s" % [branch, str(d)])
	_check(Twists.deed_for("deliver", "Vessa Orl")["tag"] == "smuggled_undeclared_cargo", "running it anyway leaves a deed")
	_check(Twists.deed_for("expose", "Vessa Orl")["tag"] == "exposed_client" and Twists.deed_for("race_won", "Vessa Orl")["tag"] == "won_the_race", "exposing a client and winning a race are deeds too")

	# Story: a bribe on a kill job means the target got away.
	var mission := {"verb": "kill_ships", "outcome_tags": ["raven_stopped", "raven_escaped"]}
	_check(Arcs.outcome_tag_for(mission, "completed", "finish_kill") == "raven_stopped", "finishing the job stops them")
	_check(Arcs.outcome_tag_for(mission, "completed", "accept_bribe") == "raven_escaped", "taking their money lets them escape")
	_check(Arcs.outcome_tag_for(mission, "completed", "spare") == "raven_stopped", "sparing a surrender still stops them")
	var deed := Twists.deed_for("accept_bribe", "the Raven")
	_check(deed["tag"] == "sold_out_contract" and str(deed["public_summary"]).contains("the Raven"), "a bribe leaves a deed")
	_check(Twists.deed_for("finish_kill", "x").is_empty(), "finishing the job is just the job")

	qm.restore_active_quest({})
	if _failures.is_empty():
		print("[PASS] Mission twists")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
