extends SceneTree

const LibraryType := preload("res://scripts/story/premise/PremiseCardLibrary.gd")
const Arcs := preload("res://scripts/story/premise/ArcEngine.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_two_mission_beat_waits_for_both()
	_test_competing_contracts()
	_test_finding_then_choice_then_resolution()
	_test_comms_reversal_mapping()
	_test_failure_falls_to_default_or_failure_tag()
	_test_consequences_applied_to_cast()
	_test_whole_deck_always_resolves()
	if _failures.is_empty():
		print("[PASS] Arc engine tests")
		quit(0)
		return
	for failure in _failures:
		push_error("[FAIL] %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _m(verb: String, tags: Array, routes: Dictionary) -> Dictionary:
	return {"verb": verb, "requester": "asker", "target": "dock", "reason": "Test reason.", "outcome_tags": tags, "routes": routes}


func _library_with(card: Dictionary):
	var lib = LibraryType.new()
	lib.load_from_array([card])
	_check(lib.has_card(str(card["id"])), "test card rejected: %s" % str(lib.skipped))
	return lib


func _base(card_id: String, beats: Array, resolutions: Array, default_res: String) -> Dictionary:
	return {"id": card_id, "schema_version": 1, "scale": "local",
		"roles": [{"id": "asker", "kind": "person"}, {"id": "dock", "kind": "place"},
			{"id": "guild", "kind": "faction"}, {"id": "foe", "kind": "ship"}],
		"beats": beats, "resolutions": resolutions, "default_resolution": default_res}


func _cast() -> Dictionary:
	return {"asker": {"entity_id": "npc.asker_1"}, "dock": {"entity_id": "station.dock_1"},
		"guild": {"entity_id": "faction.generated.guild_1"}, "foe": {"entity_id": "ship.foe_1"}}


func _start(lib, card_id: String) -> Dictionary:
	return Arcs.start_arc(Arcs.empty_state(), lib.get_card(card_id), "system.test", _cast(), 100)


func _test_two_mission_beat_waits_for_both() -> void:
	var card := _base("premise.two", [
		{"n": 1, "function": "setup", "missions": [
			_m("delivery_courier", ["done"], {"done": "next"}),
			_m("deliver_ore", ["done"], {"done": "next"})]},
		{"n": 2, "function": "climax", "missions": [_m("kill_ships", ["won"], {"won": "resolution:win"})]}],
		[{"id": "win"}, {"id": "lose"}], "lose")
	var lib = _library_with(card)
	var started := _start(lib, "premise.two")
	var s: Dictionary = started["state"]
	var arc_id: String = started["arc_id"]
	_check(Arcs.current_offers(s, lib, arc_id).size() == 2, "both beat-1 missions should be offered")
	s = Arcs.apply_mission_result(s, lib, arc_id, 1, 0, "completed", "", 110)
	_check(int(Arcs.arc(s, arc_id)["beat"]) == 1, "beat 1 must wait for its second mission")
	_check(Arcs.current_offers(s, lib, arc_id).size() == 1, "only the unfinished mission should still be offered")
	s = Arcs.apply_mission_result(s, lib, arc_id, 1, 1, "completed", "", 120)
	_check(int(Arcs.arc(s, arc_id)["beat"]) == 2, "both missions done should start beat 2")
	s = Arcs.apply_mission_result(s, lib, arc_id, 2, 0, "completed", "", 130)
	_check(Arcs.arc(s, arc_id)["resolution_id"] == "win", "the climax should resolve to win")


func _test_competing_contracts() -> void:
	var card := _base("premise.compete", [
		{"n": 1, "function": "setup", "missions_mode": "one_of", "missions": [
			_m("deliver_ore", ["to_clinic"], {"to_clinic": "resolution:clinic"}),
			_m("deliver_ore", ["to_temple"], {"to_temple": "resolution:temple"})]}],
		[{"id": "clinic"}, {"id": "temple"}, {"id": "nobody"}], "nobody")
	var lib = _library_with(card)
	var started := _start(lib, "premise.compete")
	var s: Dictionary = started["state"]
	var offers := Arcs.current_offers(s, lib, started["arc_id"])
	_check(offers.size() == 2 and bool(offers[0]["competing"]), "competing contracts should both be offered and flagged")
	s = Arcs.apply_mission_result(s, lib, started["arc_id"], 1, 1, "completed", "", 110)
	_check(Arcs.arc(s, started["arc_id"])["resolution_id"] == "temple", "the contract taken decides the story")


func _test_finding_then_choice_then_resolution() -> void:
	var card := _base("premise.finding", [
		{"n": 1, "function": "setup", "missions": [
			_m("investigate_signal", ["rigged", "honest"], {"rigged": "next", "honest": "resolution:quiet"})],
		 "player_choice": {"prompt": "What now?", "options": [
			{"id": "expose", "label": "Expose it", "leads_to": "resolution:exposed"},
			{"id": "sell", "label": "Sell it", "leads_to": "resolution:sold"}]}}],
		[{"id": "exposed"}, {"id": "sold"}, {"id": "quiet"}], "quiet")
	var lib = _library_with(card)
	var started := _start(lib, "premise.finding")
	var s: Dictionary = started["state"]
	var arc_id: String = started["arc_id"]
	s = Arcs.apply_mission_result(s, lib, arc_id, 1, 0, "completed", "", 110)
	var decision := Arcs.pending_decision(s, lib, arc_id)
	_check(decision.get("kind") == "finding" and (decision["options"] as Array).size() == 2, "a two-tag scan should ask for a finding: %s" % str(decision))
	_check(Arcs.current_offers(s, lib, arc_id).is_empty(), "no offers while a finding is pending")
	s = Arcs.apply_finding(s, lib, arc_id, "rigged", 115)
	decision = Arcs.pending_decision(s, lib, arc_id)
	_check(decision.get("kind") == "choice" and decision.get("prompt") == "What now?", "after the finding, the beat's choice is due")
	s = Arcs.apply_choice(s, lib, arc_id, "sell", 120)
	_check(Arcs.arc(s, arc_id)["resolution_id"] == "sold", "the choice should resolve the arc")
	_check((s["ledger"] as Array).size() >= 3, "the ledger should record the story")


func _test_comms_reversal_mapping() -> void:
	var mission := _m("comms_reversal", ["enforcer_destroyed", "took_the_offer"], {})
	_check(Arcs.outcome_tag_for(mission, "completed", "accept_bribe") == "took_the_offer", "accepting the offer maps to the offer tag")
	_check(Arcs.outcome_tag_for(mission, "completed", "finish_kill") == "enforcer_destroyed", "finishing the fight maps to the fight tag")
	var reversed := _m("comms_reversal", ["took_bribe", "enforcers_destroyed"], {})
	_check(Arcs.outcome_tag_for(reversed, "completed", "accept_bribe") == "took_bribe", "tag order must not matter")


func _test_failure_falls_to_default_or_failure_tag() -> void:
	var with_failure := _m("delivery_courier", ["delivered", "abandoned"], {})
	_check(Arcs.outcome_tag_for(with_failure, "abandoned") == "abandoned", "an abandoned mission uses the card's failure tag")
	_check(Arcs.outcome_tag_for(with_failure, "completed") == "delivered", "completion ignores failure tags")
	var plain := _m("delivery_courier", ["delivered"], {})
	_check(Arcs.outcome_tag_for(plain, "failed").is_empty(), "no failure tag means the default resolution")
	var card := _base("premise.fail", [
		{"n": 1, "function": "setup", "missions": [_m("delivery_courier", ["delivered"], {"delivered": "resolution:good"})]}],
		[{"id": "good"}, {"id": "world_moves_on"}], "world_moves_on")
	var lib = _library_with(card)
	var started := _start(lib, "premise.fail")
	var s := Arcs.apply_mission_result(started["state"], lib, started["arc_id"], 1, 0, "expired", "", 200)
	_check(Arcs.arc(s, started["arc_id"])["resolution_id"] == "world_moves_on", "an expired mission should fail forward to the default")


func _test_consequences_applied_to_cast() -> void:
	var card := _base("premise.effects", [
		{"n": 1, "function": "setup", "missions": [_m("kill_ships", ["won"], {"won": "resolution:win"})]}],
		[{"id": "win", "seeds": ["power_vacuum"], "consequences": [
			{"type": "standing", "target": "guild", "delta": 2},
			{"type": "cast_fate", "target": "asker", "fate": "promoted"},
			{"type": "deed", "tag": "broke_the_blockade", "public_summary": "Someone broke it."},
			{"type": "system_state", "add": ["strike"], "remove": ["festival"]},
			{"type": "law_change", "law": "curfew", "change": "repealed"},
			{"type": "economy", "good": "ore", "ore": "ferrite", "price": "spike"}]},
		 {"id": "lose"}], "lose")
	var lib = _library_with(card)
	var started := _start(lib, "premise.effects")
	var s := Arcs.apply_mission_result(started["state"], lib, started["arc_id"], 1, 0, "completed", "", 150)
	_check(int(s["standing"].get("faction.generated.guild_1", 0)) == 2, "standing should land on the cast faction entity")
	_check(s["fates"].get("npc.asker_1", []) == ["promoted"], "fate should land on the cast person entity")
	_check((s["deeds"] as Array).size() == 1 and s["deeds"][0]["tag"] == "broke_the_blockade", "deed recorded")
	var base := {"system_id": "system.test", "quirks": [], "states": ["festival"]}
	_check(Arcs.live_states(s, base) == ["strike"], "system states should reflect the resolution: %s" % str(Arcs.live_states(s, base)))
	_check(s["system_laws"]["system.test"]["curfew"] == "repealed", "law change recorded")
	_check(Arcs.seed_tags(s, "system.test") == ["power_vacuum"], "seeds left for later cards")
	_check(s["used_card_ids"] == ["premise.effects"], "card marked used in this campaign")
	_check(started["state"]["deeds"].is_empty(), "the engine must never modify its input state")


## Random playthroughs of every approved card: each must resolve, never stall.
func _test_whole_deck_always_resolves() -> void:
	var lib = LibraryType.new()
	lib.load_from_dir()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260924
	var terminals := ["completed", "completed", "completed", "abandoned", "expired"]
	var stalled: Array[String] = []
	for card_id in lib.ids():
		for run in 6:
			var started := Arcs.start_arc(Arcs.empty_state(), lib.get_card(card_id), "system.x", {}, 0)
			var s: Dictionary = started["state"]
			var arc_id: String = started["arc_id"]
			var steps := 0
			while Arcs.arc(s, arc_id)["status"] == "active" and steps < 40:
				steps += 1
				var decision := Arcs.pending_decision(s, lib, arc_id)
				if not decision.is_empty():
					var options: Array = decision["options"]
					var pick := str(options[rng.randi_range(0, options.size() - 1)]["id"])
					s = Arcs.apply_finding(s, lib, arc_id, pick, steps) if decision["kind"] == "finding" else Arcs.apply_choice(s, lib, arc_id, pick, steps)
					continue
				var offers := Arcs.current_offers(s, lib, arc_id)
				if offers.is_empty():
					break
				var offer: Dictionary = offers[rng.randi_range(0, offers.size() - 1)]
				var branch := "accept_bribe" if rng.randi_range(0, 1) == 0 else "finish_kill"
				s = Arcs.apply_mission_result(s, lib, arc_id, int(offer["beat"]), int(offer["mission_index"]),
					terminals[rng.randi_range(0, terminals.size() - 1)], branch, steps)
			if Arcs.arc(s, arc_id)["status"] != "resolved":
				stalled.append("%s (run %d, stage %s, beat %s)" % [card_id, run, Arcs.arc(s, arc_id)["stage"], Arcs.arc(s, arc_id)["beat"]])
	_check(stalled.is_empty(), "arcs stalled: %s" % str(stalled.slice(0, 8)))
