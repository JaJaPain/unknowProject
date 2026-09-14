extends SceneTree

const Director := preload("res://scripts/story/LocalPressureDirector.gd")
const Store := preload("res://scripts/persistence/StoryStateStore.gd")

var failures: Array[String] = []
var catalog: Dictionary = {}

func _initialize():
	call_deferred("_run")

func _run():
	catalog = Director.load_catalog()
	_expect(catalog.get("ok", false), "Shipped pressure catalog failed to load: %s" % catalog.get("reason", ""))
	if catalog.get("ok", false):
		_test_catalog()
		_test_activation()
		_test_deltas()
		_test_inactivity_and_cooldown()
		_test_idempotency()
		_test_constraints_and_payouts()
		_test_determinism_and_persistence()
		_test_pacing_families()
	if failures.is_empty():
		print("[PASS] Local pressure reducer: activation, deltas, inactivity, cooldown, idempotency, payouts, determinism")
	else:
		for message in failures: push_error("[FAIL] " + message)
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _candidate(kind: String, suffix: String = "a", system_id: String = "system.local") -> Dictionary:
	return {"kind": kind, "system_id": system_id, "station_id": "station.local",
		"faction_id": "faction.%s" % suffix, "desire_id": "desire.%s.%s" % [kind, suffix], "cause_id": "cause.%s.%s" % [kind, suffix]}

func _context(candidates: Array, unlocked: bool = true) -> Dictionary:
	return {"post_tutorial_unlocked": unlocked, "campaign_seed": 4242, "catalog": catalog, "candidates": candidates}

func _outcome(mission_id: String, terminal: String, pressure_id: String = "", tag: String = "", relief: bool = false) -> Dictionary:
	return {"id": "%s:%s" % [mission_id, terminal], "mission_id": mission_id, "terminal_state": terminal,
		"pressure_id": pressure_id, "outcome_tag": tag, "relief": relief, "shape_id": "", "objective_type": "INVESTIGATE_SIGNAL",
		"branch_id": "", "verified": false, "forged": false, "credits_paid": 0, "consumable_id": "", "at_minute": 0}

func _track_of(state: Dictionary, kind: String) -> Dictionary:
	for track: Dictionary in state.get("tracks", []):
		if str(track["kind"]) == kind: return track
	return {}

func _test_catalog() -> void:
	var kinds: Dictionary = catalog["kinds"]
	_expect(kinds.has("signals") and kinds.has("claims") and kinds.has("supply"), "Catalog is missing a P3 kind.")
	_expect(not bool(kinds["supply"].get("runtime_eligible", true)), "Supply must stay runtime-ineligible without a validated ore cause.")
	for kind_id in kinds:
		_expect(not bool(kinds[kind_id].get("forced_forged", false)), "%s advertises forced forgery; the lure recipe is a prototype." % kind_id)
		for level in ["1", "2", "3"]:
			for shape in kinds[kind_id]["shape_ids_by_level"][level]:
				_expect(str(shape) in ["mission_shape.survey_discrepancy", "mission_shape.competing_claims"],
					"%s level %s offers unsupported prototype shape %s." % [kind_id, level, shape])
	_expect(not Director.parse_catalog({"version": 9, "kinds": []}).get("ok", true), "Unsupported catalog version was accepted.")
	_expect(not Director.parse_catalog({"version": 1, "kinds": []}).get("ok", true), "Empty catalog was accepted.")

func _test_activation() -> void:
	var locked := Director.refresh_slots({}, _context([_candidate("signals"), _candidate("claims")], false))
	_expect(locked.get("ok", false) and not locked.get("changed", true), "Tutorial guard should refuse silently, not error.")
	_expect(locked["state"]["tracks"].is_empty(), "A track activated before tutorial completion.")
	var opened := Director.refresh_slots({}, _context([_candidate("signals"), _candidate("claims")]))
	_expect(opened.get("changed", false), "No track activated after tutorial completion.")
	var state: Dictionary = opened["state"]
	_expect(state["tracks"].size() == 2, "Expected two activated tracks, got %d." % state["tracks"].size())
	for track: Dictionary in state["tracks"]:
		_expect(int(track["level"]) == 1 and int(track["untouched_steps"]) == 0, "A new track did not start at level 1 / count 0.")
	_expect(Director.validate(state).is_valid(), "Activated pressure state failed validation.")
	# Supply is catalogued but runtime-ineligible: its slot stays pending.
	var sparse := Director.refresh_slots({}, _context([_candidate("supply"), _candidate("signals")]))
	_expect(sparse["state"]["tracks"].size() == 1, "Runtime-ineligible supply filled a slot.")
	_expect(_track_of(sparse["state"], "supply").is_empty(), "Supply activated without a validated ore cause.")
	var pending := false
	for delta: Dictionary in sparse["deltas"]:
		if str(delta.get("kind", "")) == "slot_pending": pending = true
	_expect(pending, "A missing slot was not reported pending.")
	# An incomplete binding is never completed from a name.
	var broken := _candidate("claims"); broken["desire_id"] = ""
	_expect(Director.refresh_slots({}, _context([broken]))["state"]["tracks"].is_empty(), "An unbound candidate activated a track.")
	# No duplicate active kind, and no second draw of a cause already bound.
	var again := Director.refresh_slots(state, _context([_candidate("signals"), _candidate("claims")]))
	_expect(again["state"]["tracks"].size() == 2, "Refreshing rebound an already-active kind.")

func _two_track_state() -> Dictionary:
	return Director.refresh_slots({}, _context([_candidate("signals"), _candidate("claims")]))["state"]

func _test_deltas() -> void:
	var base := _two_track_state()
	var signals_id := str(_track_of(base, "signals")["id"])
	var claims_id := str(_track_of(base, "claims")["id"])
	# signals: correct certification relieves, incorrect worsens, report is neutral.
	var relieved := Director.apply_outcome(base, _outcome("m.1", "completed", signals_id, "verified"), {"catalog": catalog})
	_expect(relieved.get("changed", false), "A verified certification did not commit.")
	_expect(int(_track_of(relieved["state"], "signals")["level"]) == 0, "Correct certification did not relieve signals.")
	var worsened := Director.apply_outcome(base, _outcome("m.2", "completed", signals_id, "mistaken"), {"catalog": catalog})
	_expect(int(_track_of(worsened["state"], "signals")["level"]) == 2, "Incorrect certification did not worsen signals.")
	var reported := Director.apply_outcome(base, _outcome("m.3", "completed", signals_id, "unverified"), {"catalog": catalog})
	_expect(int(_track_of(reported["state"], "signals")["level"]) == 1, "A report changed the signals level.")
	_expect(int(_track_of(reported["state"], "signals")["untouched_steps"]) == 1, "A neutral report did not advance inactivity.")
	# claims: preserve relieves, report is neutral, liquidation is not offered.
	var preserved := Director.apply_outcome(base, _outcome("m.4", "completed", claims_id, "preserved"), {"catalog": catalog})
	_expect(int(_track_of(preserved["state"], "claims")["level"]) == 0, "Preserve did not relieve claims.")
	# Abandon/fail/expire carry no direct delta for these two kinds.
	for terminal in ["abandoned", "failed", "expired"]:
		var ended := Director.apply_outcome(base, _outcome("m.%s" % terminal, terminal, claims_id, ""), {"catalog": catalog})
		_expect(int(_track_of(ended["state"], "claims")["level"]) == 1, "%s applied a direct delta to claims." % terminal)
		_expect(int(_track_of(ended["state"], "claims")["untouched_steps"]) == 1, "%s did not fall through to inactivity." % terminal)
	# Other active tracks take exactly one neutral step regardless of system.
	_expect(int(_track_of(relieved["state"], "claims")["untouched_steps"]) == 1, "The unbound track missed its neutral step.")
	# Clamp boundaries.
	var high := base.duplicate(true)
	_track_of(high, "signals")["level"] = 3
	var over := Director.apply_outcome(high, _outcome("m.5", "completed", signals_id, "mistaken"), {"catalog": catalog})
	_expect(int(_track_of(over["state"], "signals")["level"]) == 3, "Worsening exceeded the level clamp.")
	# A worsened track does not also escalate from inactivity on the same event.
	var primed := base.duplicate(true)
	_track_of(primed, "signals")["untouched_steps"] = 1
	var single := Director.apply_outcome(primed, _outcome("m.6", "completed", signals_id, "mistaken"), {"catalog": catalog})
	_expect(int(_track_of(single["state"], "signals")["level"]) == 2, "A worsened track double-escalated on one event.")
	_expect(int(_track_of(single["state"], "signals")["untouched_steps"]) == 0, "A worsening outcome did not reset the untouched count.")
	# Unbound work advances inactivity only.
	var unbound := Director.apply_outcome(base, _outcome("m.7", "completed", "", "verified"), {"catalog": catalog})
	_expect(int(_track_of(unbound["state"], "signals")["level"]) == 1, "An unbound mission relieved a track.")
	_expect(int(_track_of(unbound["state"], "signals")["untouched_steps"]) == 1, "An unbound mission skipped inactivity.")
	var reported_kind := false
	for delta: Dictionary in unbound["deltas"]:
		if str(delta.get("kind", "")) == "unbound_activity": reported_kind = true
	_expect(reported_kind, "Unbound activity was not reported.")
	# Tutorial missions are excluded from activity entirely.
	var tutorial := _outcome("m.tutorial", "completed", signals_id, "verified"); tutorial["tutorial"] = true
	var skipped := Director.apply_outcome(base, tutorial, {"catalog": catalog})
	_expect(not skipped.get("changed", true) and int(skipped["state"]["activity_step"]) == 0, "A tutorial mission advanced pressure.")
	# Supply's relief marking is exercised with a typed fixture only.
	var supply_state := base.duplicate(true)
	var supply_track := _track_of(supply_state, "claims").duplicate(true)
	supply_track["kind"] = "supply"; supply_track["id"] = "pressure.supply.fixture"; supply_track["level"] = 2
	supply_state["tracks"] = [supply_track]
	var delivered := Director.apply_outcome(supply_state, _outcome("m.8", "completed", "pressure.supply.fixture", "", true), {"catalog": catalog})
	_expect(int(_track_of(delivered["state"], "supply")["level"]) == 1, "A marked ore delivery did not relieve supply.")
	var dropped := Director.apply_outcome(supply_state, _outcome("m.9", "abandoned", "pressure.supply.fixture", "", true), {"catalog": catalog})
	_expect(int(_track_of(dropped["state"], "supply")["level"]) == 3, "Abandoning a marked relief job did not worsen supply.")
	var unmarked := Director.apply_outcome(supply_state, _outcome("m.10", "abandoned", "pressure.supply.fixture", "", false), {"catalog": catalog})
	_expect(int(_track_of(unmarked["state"], "supply")["level"]) == 2, "An unmarked job worsened supply.")

func _test_inactivity_and_cooldown() -> void:
	var state := _two_track_state()
	var signals_id := str(_track_of(state, "signals")["id"])
	# Two neutral steps escalate exactly once, then the count resets.
	for i in range(2):
		state = Director.apply_outcome(state, _outcome("n.%d" % i, "completed", "", ""), {"catalog": catalog})["state"]
	_expect(int(_track_of(state, "signals")["level"]) == 2, "Two inactive steps did not escalate the track.")
	_expect(int(_track_of(state, "signals")["untouched_steps"]) == 0, "The untouched count did not reset after escalating.")
	# Resolve, then confirm cooldown is counted in resolved jobs, not minutes.
	var resolving := state.duplicate(true)
	_track_of(resolving, "signals")["level"] = 1
	var resolved := Director.apply_outcome(resolving, _outcome("r.1", "completed", signals_id, "verified"), {"catalog": catalog})
	var track := _track_of(resolved["state"], "signals")
	var step := int(resolved["state"]["activity_step"])
	_expect(int(track["level"]) == 0, "Relief did not resolve the track.")
	_expect(int(track["cooldown_until_step"]) == step + 4, "Cooldown must end four activity steps after the resolving event.")
	_expect(not Director.is_active(track), "A resolved track is still active.")
	# A cooling entry does not escalate from inactivity.
	var cooling: Dictionary = resolved["state"]
	for i in range(3):
		cooling = Director.apply_outcome(cooling, _outcome("c.%d" % i, "completed", "", ""), {"catalog": catalog})["state"]
	_expect(int(_track_of(cooling, "signals")["level"]) == 0, "A cooling track escalated.")
	var early := Director.refresh_slots(cooling, _context([_candidate("signals", "b")]))
	_expect(_track_of(early["state"], "signals").get("cooldown_until_step", 0) > 0, "Cooldown released a step early.")
	cooling = Director.apply_outcome(cooling, _outcome("c.3", "completed", "", ""), {"catalog": catalog})["state"]
	var replaced := Director.refresh_slots(cooling, _context([_candidate("signals", "b")]))
	_expect(replaced.get("changed", false), "An expired cooldown did not release its slot.")
	var fresh := false
	for t: Dictionary in replaced["state"]["tracks"]:
		if Director.is_active(t) and str(t["kind"]) == "signals" and str(t["cause_id"]) == "cause.signals.b": fresh = true
	_expect(fresh, "No replacement bound after cooldown expired.")
	# An expired cooldown with no valid current cause remains pending.
	var pending := Director.refresh_slots(cooling, _context([]))
	var still_pending := true
	for t: Dictionary in pending["state"]["tracks"]:
		if Director.is_active(t) and str(t["kind"]) == "signals": still_pending = false
	_expect(still_pending, "A slot was filled without an eligible cause.")
	# A fulfilled cause cannot reappear under a new station or after cooldown.
	var recycled := Director.refresh_slots(cooling, _context([_candidate("signals", "a")]))
	for t: Dictionary in recycled["state"]["tracks"]:
		_expect(not (Director.is_active(t) and str(t["cause_id"]) == "cause.signals.a"), "A retired cause was resurrected as a replacement.")

func _test_idempotency() -> void:
	var state := _two_track_state()
	var signals_id := str(_track_of(state, "signals")["id"])
	var first := Director.apply_outcome(state, _outcome("dup.1", "completed", signals_id, "mistaken"), {"catalog": catalog})
	var repeat := Director.apply_outcome(first["state"], _outcome("dup.1", "completed", signals_id, "mistaken"), {"catalog": catalog})
	_expect(repeat.get("ok", false) and not repeat.get("changed", true), "A duplicate outcome was reapplied.")
	_expect(str(repeat["reason"]) == "duplicate_outcome", "Duplicate outcome reported '%s'." % repeat["reason"])
	_expect(int(repeat["state"]["activity_step"]) == int(first["state"]["activity_step"]), "A duplicate outcome advanced activity.")
	# A different terminal suffix must not bypass the ledger.
	var conflicting := Director.apply_outcome(first["state"], _outcome("dup.1", "failed", signals_id, ""), {"catalog": catalog})
	_expect(not conflicting.get("ok", true), "A conflicting terminal outcome for the same mission was accepted.")
	_expect(str(conflicting["reason"]) == "conflicting_terminal_outcome", "Conflict reported '%s'." % conflicting["reason"])
	_expect(int(first["state"]["applied_outcome_ids"].size()) == 1, "The applied ledger did not retain exactly one ID.")
	# Malformed outcomes fail closed without mutating anything.
	for bad: Dictionary in [{}, {"id": "x", "mission_id": "x", "terminal_state": "completed"},
			{"id": "x:completed", "mission_id": "x", "terminal_state": "accepted"},
			{"id": "x:completed", "mission_id": "", "terminal_state": "completed"}]:
		var rejected := Director.apply_outcome(state, bad, {"catalog": catalog})
		_expect(not rejected.get("ok", true), "A malformed outcome was accepted: %s" % JSON.stringify(bad))
		_expect(int(rejected["state"]["activity_step"]) == 0, "A rejected outcome advanced activity.")
	# Malformed saved state is a recoverable load error, never a reset.
	var corrupt := state.duplicate(true); corrupt["tracks"] = "not-an-array"
	var refused := Director.apply_outcome(corrupt, _outcome("z.1", "completed", "", ""), {"catalog": catalog})
	_expect(not refused.get("ok", true), "Malformed pressure state was silently accepted.")
	_expect(refused["state"].get("tracks") == "not-an-array", "A malformed load reset saved data.")

func _test_constraints_and_payouts() -> void:
	var state := _two_track_state()
	var constraints := Director.offer_constraints(state, "system.local", {"catalog": catalog})
	_expect(constraints.size() == 2, "Expected one constraint per active track, got %d." % constraints.size())
	_expect(Director.offer_constraints(state, "system.elsewhere", {"catalog": catalog}).is_empty(), "A track leaked a card into another system.")
	for constraint: Dictionary in constraints:
		_expect(int(constraint["escalates_after"]) == 2, "Escalates-after should start at 2 resolved jobs.")
		_expect(not bool(constraint["forced_forged"]), "A constraint forced forgery.")
		for shape in constraint["preferred_shape_ids"]:
			_expect(str(shape) in ["mission_shape.survey_discrepancy", "mission_shape.competing_claims"], "A constraint offered a prototype shape.")
		_expect(not str(constraint["cause_id"]).is_empty() and not str(constraint["desire_id"]).is_empty(), "A constraint lost its causal binding.")
	# Prototype recipes stay unavailable at every level, including level 3.
	var maxed := state.duplicate(true)
	for track: Dictionary in maxed["tracks"]: track["level"] = 3
	for constraint: Dictionary in Director.offer_constraints(maxed, "system.local", {"catalog": catalog}):
		for shape in constraint["preferred_shape_ids"]:
			_expect(str(shape) in ["mission_shape.survey_discrepancy", "mission_shape.competing_claims"], "Level 3 exposed a prototype shape.")
		_expect(not bool(constraint["forced_forged"]), "Level 3 advertised elevated fraud with no lure to back it.")
	# Claims base 400: preserve pays 500 at level 3, report stays 200.
	var claims: Dictionary = {}
	for constraint: Dictionary in Director.offer_constraints(maxed, "system.local", {"catalog": catalog}):
		if str(constraint["kind"]) == "claims": claims = constraint
	_expect(not claims.is_empty(), "No claims constraint at level 3.")
	var preserve: Dictionary = claims["branch_modifiers"].get("preserve", {"numerator": 1, "denominator": 1})
	_expect(Director.snapshot_payout(400, int(preserve["numerator"]), int(preserve["denominator"])) == 500, "Level 3 preserve did not snapshot 500.")
	_expect(Director.snapshot_payout(200, int(claims["payout_numerator"]), int(claims["payout_denominator"])) == 200, "A report payout was modified.")
	# Survey payouts are untouched at every level: 400 / 100 / 200.
	var signals: Dictionary = {}
	for constraint: Dictionary in Director.offer_constraints(maxed, "system.local", {"catalog": catalog}):
		if str(constraint["kind"]) == "signals": signals = constraint
	for base in [400, 100, 200]:
		_expect(Director.snapshot_payout(base, int(signals["payout_numerator"]), int(signals["payout_denominator"])) == base, "Survey payout %d was modified." % base)
	# Modifiers never stack: a branch rule and a wildcard rule take the maximum.
	var stacking := Director.parse_catalog({"version": 1, "kinds": [{"id": "stack", "runtime_eligible": true,
		"shape_ids_by_level": {"1": [], "2": [], "3": []}, "completed_deltas": [], "terminal_deltas": [],
		"payout_modifiers": [{"level": 3, "branch_id": "*", "numerator": 5, "denominator": 4},
			{"level": 3, "branch_id": "preserve", "numerator": 3, "denominator": 2}]}]})
	var stack_state := maxed.duplicate(true)
	stack_state["tracks"] = [_track_of(maxed, "claims").duplicate(true)]
	stack_state["tracks"][0]["kind"] = "stack"
	var stacked: Dictionary = Director.offer_constraints(stack_state, "system.local", {"catalog": stacking})[0]
	var branch: Dictionary = stacked["branch_modifiers"]["preserve"]
	_expect(Director.snapshot_payout(400, int(branch["numerator"]), int(branch["denominator"])) == 600, "Modifiers multiplied instead of taking the maximum.")
	# Snapshotted terms use an integer floor and never reapply at settlement.
	_expect(Director.snapshot_payout(333, 5, 4) == 416, "Payout snapshot did not floor to an integer.")

func _test_determinism_and_persistence() -> void:
	var sequence := [_outcome("d.1", "completed", "", ""), _outcome("d.2", "completed", "", ""), _outcome("d.3", "failed", "", "")]
	var runs: Array = []
	for attempt in range(2):
		var state := _two_track_state()
		for outcome: Dictionary in sequence:
			state = Director.apply_outcome(state, outcome, {"catalog": catalog})["state"]
		runs.append(state)
	_expect(JSON.stringify(runs[0]) == JSON.stringify(runs[1]), "The same seed and terminal sequence produced different state.")
	# A different valid action sequence changes actual builder output, not only levels.
	var relieving := _two_track_state()
	var signals_id := str(_track_of(relieving, "signals")["id"])
	relieving = Director.apply_outcome(relieving, _outcome("d.1", "completed", signals_id, "verified"), {"catalog": catalog})["state"]
	var a := Director.offer_constraints(runs[0], "system.local", {"catalog": catalog})
	var b := Director.offer_constraints(relieving, "system.local", {"catalog": catalog})
	_expect(a.size() != b.size(), "Relieving a track did not change which cards the builder may draw.")
	# Saved RNG survives a JSON roundtrip and reproduces the same replacement draw.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(runs[0]))
	_expect(Director.validate(saved).is_valid(), "A JSON roundtrip invalidated pressure state.")
	var choices := [_candidate("signals", "x"), _candidate("claims", "y")]
	var live := Director.refresh_slots(runs[0], _context(choices))
	var reloaded := Director.refresh_slots(saved, _context(choices))
	_expect(JSON.stringify(live["state"]) == JSON.stringify(reloaded["state"]), "Save/load changed the replacement draw.")
	# Story state accepts and validates the additive field.
	var default_state: Dictionary = Store._default_state()
	_expect(default_state.has("local_pressures"), "Story state default is missing local_pressures.")
	default_state["local_pressures"] = runs[0]
	_expect(Store._validate_data(default_state).is_valid(), "Story state rejected valid pressure records.")
	var broken := default_state.duplicate(true)
	broken["local_pressures"] = {"version": 1, "activity_step": 0, "rng_state": 0, "tracks": [{}], "applied_outcome_ids": [], "recent_accepted_families": []}
	_expect(not Store._validate_data(broken).is_valid(), "Story state accepted a malformed pressure track.")
	var legacy: Dictionary = Store._migrate_legacy_state({"chapter": 2})
	_expect(legacy.get("local_pressures", null) is Dictionary and (legacy["local_pressures"] as Dictionary).is_empty(),
		"An old save without pressures did not migrate to uninitialized.")

func _test_pacing_families() -> void:
	var state := Director.empty_state(1)
	for family in ["investigation", "investigation"]:
		state = Director.record_accepted_family(state, family)["state"]
	_expect(not Director.may_offer_family(state, "investigation"), "A third investigation in four accepted jobs was allowed.")
	state = Director.record_accepted_family(state, "delivery")["state"]
	_expect(not Director.may_offer_family(state, "investigation"),
		"Two investigations still sit in the inspected window; a third was allowed.")
	state = Director.record_accepted_family(state, "delivery")["state"]
	_expect(Director.may_offer_family(state, "investigation"), "The window did not slide as older accepted work aged out.")
	state = Director.record_accepted_family(state, "delivery")["state"]
	_expect(state["recent_accepted_families"].size() == 4, "The accepted-family window is not capped at four.")
	_expect(not Director.may_offer_family(state, "delivery"), "The cap ignored the retained window.")
