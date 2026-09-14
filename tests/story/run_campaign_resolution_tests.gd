extends SceneTree

const Plan := preload("res://scripts/story/CampaignResolutionCompiler.gd")
const Outcome := preload("res://scripts/domain/MissionOutcome.gd")

var failures: Array[String] = []

func _initialize():
	call_deferred("_run")

func _run():
	_test_validation()
	_test_binding()
	_test_ambiguity_and_loss()
	_test_evaluation()
	_test_legacy_campaign()
	_test_composed_plan()
	if failures.is_empty():
		print("[PASS] Campaign resolution: validation, binding, guards, evaluation and factual record")
	else:
		for message in failures: push_error("[FAIL] " + message)
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _interest() -> Dictionary:
	return {"id": "interest.a", "system_id": "system.local", "faction_id": "faction.a",
		"desire_id": "desire.a", "supported_effect_ids": [Outcome.EFFECT_RECORDER_PRESERVED]}

func _plan(alternatives: Array = []) -> Dictionary:
	var alts: Array = alternatives
	if alts.is_empty():
		alts = [{"id": "alt.success", "result": "success", "public_fact_ids": [],
			"all_of": [{"kind": "desire_state", "desire_id": "desire.a",
				"system_id": "system.local", "state": "satisfied"}]}]
	return {"version": 1, "id": "plan.test", "status": "pending_bindings",
		"premise_fact_ids": [], "interests": [_interest()], "alternatives": alts}

func _test_validation() -> void:
	_expect(Plan.validate({}).is_valid(), "A campaign without a plan must validate as uninitialized.")
	_expect(Plan.validate(_plan()).is_valid(), "A well-formed plan failed validation.")
	_expect(not Plan.validate({"version": 9, "id": "x", "status": "active",
		"premise_fact_ids": [], "interests": [], "alternatives": []}).is_valid(), "An unsupported version was accepted.")
	# An empty condition set would resolve instantly and mean nothing.
	var empty_conditions := _plan([{"id": "alt.x", "result": "success", "all_of": [], "public_fact_ids": []}])
	_expect(not Plan.validate(empty_conditions).is_valid(), "An empty success condition was accepted.")
	var no_alternatives := _plan()
	no_alternatives["alternatives"] = []
	_expect(not Plan.validate(no_alternatives).is_valid(), "A plan with no alternatives was accepted.")
	# No freeform code, expression strings or numeric scores.
	for bad: Dictionary in [{"kind": "expression", "value": "score > 3"}, {"kind": "script", "code": "return true"},
			{"kind": "threshold", "score": 5}]:
		var invented := _plan([{"id": "alt.x", "result": "success", "all_of": [bad], "public_fact_ids": []}])
		_expect(not Plan.validate(invented).is_valid(), "An invented predicate kind was accepted: %s" % JSON.stringify(bad))
	# A predicate must be bound, and a desire predicate may only test a close.
	for bad: Dictionary in [{"kind": "effect_committed", "effect_id": ""},
			{"kind": "fact_known", "fact_id": ""},
			{"kind": "desire_state", "desire_id": "d", "system_id": "s", "state": "progressed"}]:
		var unbound := _plan([{"id": "alt.x", "result": "success", "all_of": [bad], "public_fact_ids": []}])
		_expect(not Plan.validate(unbound).is_valid(), "An unbound or non-closing predicate was accepted: %s" % JSON.stringify(bad))
	# An interest may only promise implemented effect kinds.
	var invented_effect := _plan()
	(invented_effect["interests"][0] as Dictionary)["supported_effect_ids"] = ["route_reopened"]
	_expect(not Plan.validate(invented_effect).is_valid(), "A plan promised an unimplemented effect kind.")

func _context() -> Dictionary:
	return {"desires": [{"system_id": "system.local", "faction_id": "faction.a", "desire_id": "desire.a"}],
		"system_ids": ["system.local"], "station_ids": ["station.local"],
		"known_fact_ids": [], "candidate_fact_ids": ["fact.premise"],
		"effect_ids": [Outcome.EFFECT_RECORDER_PRESERVED]}

func _test_binding() -> void:
	var bound := Plan.bind(_plan(), _context())
	_expect(bound.get("ok", false), "A bindable plan failed to bind: %s" % bound.get("reason", ""))
	_expect(str(bound.get("plan", {}).get("status", "")) == "active", "A fully bound plan did not activate.")
	_expect(bool(bound.get("plan", {}).get("frozen", false)), "An active plan did not freeze its predicates.")
	# A reference the campaign has not generated yet stays pending, not invented.
	var unbuilt := _context()
	unbuilt["desires"] = []
	var pending := Plan.bind(_plan(), unbuilt)
	_expect(pending.get("ok", false), "An unbuilt reference errored instead of pending.")
	_expect(str(pending.get("plan", {}).get("status", "")) == "pending_bindings", "An unbuilt reference did not stay pending.")
	_expect("interest.a" in (pending["plan"].get("pending_interest_ids", []) as Array), "Pending plan did not name its missing interest.")
	# A desire ID is only valid inside its owning faction and system.
	var wrong_owner := _context()
	wrong_owner["desires"] = [{"system_id": "system.local", "faction_id": "faction.other", "desire_id": "desire.a"}]
	_expect(str(Plan.bind(_plan(), wrong_owner).get("plan", {}).get("status", "")) == "pending_bindings",
		"A desire bound to the wrong faction was accepted.")
	# An unknown fact or effect reference fails closed.
	var unknown_fact := _plan([{"id": "alt.x", "result": "success", "public_fact_ids": [],
		"all_of": [{"kind": "fact_known", "fact_id": "fact.never_generated"}]}])
	_expect(not Plan.bind(unknown_fact, _context()).get("ok", true), "An unknown fact reference was accepted.")
	var unknown_effect := _plan([{"id": "alt.x", "result": "success", "public_fact_ids": [],
		"all_of": [{"kind": "effect_committed", "effect_id": "effect.never_committed"}]}])
	_expect(not Plan.bind(unknown_effect, _context()).get("ok", true), "An unknown effect reference was accepted.")
	# A desire predicate must reference one of the plan's own interests.
	var foreign := _plan([{"id": "alt.x", "result": "success", "public_fact_ids": [],
		"all_of": [{"kind": "desire_state", "desire_id": "desire.elsewhere", "system_id": "system.local", "state": "satisfied"}]}])
	_expect(not Plan.bind(foreign, _context()).get("ok", true), "A predicate referenced a desire outside the plan.")

func _satisfied_predicate() -> Dictionary:
	return {"kind": "desire_state", "desire_id": "desire.a", "system_id": "system.local", "state": "satisfied"}

func _test_ambiguity_and_loss() -> void:
	# Two alternatives that could both fire from the same world must be refused
	# rather than picking the first arbitrary array element.
	var ambiguous := _plan([
		{"id": "alt.success", "result": "success", "public_fact_ids": [], "all_of": [_satisfied_predicate()]},
		{"id": "alt.partial", "result": "partial", "public_fact_ids": [],
			"all_of": [_satisfied_predicate(), {"kind": "effect_committed", "effect_id": "recorder_preserved_and_delivered"}]},
	])
	var refused := Plan.bind(ambiguous, _context())
	_expect(not refused.get("ok", true), "Overlapping alternatives were activated.")
	_expect(str(refused.get("reason", "")) == "ambiguous_alternatives", "Overlap reported '%s'." % refused.get("reason", ""))
	# A loss must be established by a committed effect or a proven failed desire,
	# never assumed from absence. Reaching level 3 is not campaign failure.
	var unestablished := _plan([{"id": "alt.fail", "result": "failure", "public_fact_ids": [],
		"all_of": [{"kind": "fact_known", "fact_id": "fact.premise"}]}])
	var rejected := Plan.bind(unestablished, _context())
	_expect(not rejected.get("ok", true), "A failure alternative with no established loss was activated.")
	_expect(str(rejected.get("reason", "")) == "unestablished_loss_alternative",
		"Unestablished loss reported '%s'." % rejected.get("reason", ""))
	# A failure alternative backed by a proven failed desire is allowed.
	var established := _plan([{"id": "alt.fail", "result": "failure", "public_fact_ids": [],
		"all_of": [{"kind": "desire_state", "desire_id": "desire.a", "system_id": "system.local", "state": "failed"}]}])
	_expect(Plan.bind(established, _context()).get("ok", false), "A properly established loss was refused.")
	# One supported resolution is preferable to invented failure.
	_expect(Plan.bind(_plan(), _context()).get("ok", false), "A single-alternative plan was refused.")

func _active_plan() -> Dictionary:
	return Plan.bind(_plan(), _context())["plan"]

func _progress(state: String) -> Dictionary:
	return {"version": 1, "entries": {"system.local|faction.a|desire.a": {
		"system_id": "system.local", "faction_id": "faction.a", "desire_id": "desire.a",
		"cause_id": "cause.a", "state": state, "satisfied_by_predicate": "recorder_delivered_to_verified_owner",
		"records": [], "achieved_effect_ids": [], "source_outcome_ids": ["m.1:completed"],
		"last_outcome_id": "m.1:completed", "last_terminal_state": "completed", "revision": 1}}}

func _test_evaluation() -> void:
	var plan := _active_plan()
	# A pending plan never resolves, however good the world looks.
	var pending := plan.duplicate(true)
	pending["status"] = "pending_bindings"
	_expect(not Plan.evaluate(pending, {"desire_progress": _progress("satisfied")}).get("resolved", true),
		"A pending plan resolved.")
	# An unmet condition does not resolve.
	for unmet in ["open", "progressed"]:
		var result := Plan.evaluate(plan, {"desire_progress": _progress(unmet)})
		_expect(not result.get("resolved", true), "A plan resolved on a desire that was only '%s'." % unmet)
	# The proven state resolves it, and the record is factual.
	var resolved := Plan.evaluate(plan, {"desire_progress": _progress("satisfied"),
		"committed_effect_ids": [Outcome.EFFECT_RECORDER_PRESERVED],
		"source_outcome_ids": ["m.1:completed"], "activity_step": 7})
	_expect(resolved.get("resolved", false), "A proven desire state did not resolve the plan.")
	if not resolved.get("resolved", false): return
	var record: Dictionary = resolved["record"]
	_expect(str(record["result"]) == "success", "Resolution recorded the wrong result.")
	_expect(str(record["alternative_id"]) == "alt.success", "Resolution recorded the wrong alternative.")
	_expect("m.1:completed" in (record["source_outcome_ids"] as Array), "Record lost its source outcome IDs.")
	_expect(Outcome.EFFECT_RECORDER_PRESERVED in (record["achieved_effect_ids"] as Array), "Record lost its achieved effect.")
	_expect((record["unresolved_interest_ids"] as Array).is_empty(), "A satisfied interest was recorded unresolved.")
	_expect(int(record["committed_at_step"]) == 7, "Record lost the step it committed at.")
	# Two different action traces produce different records only when the actual
	# consequences differ.
	var other := Plan.evaluate(plan, {"desire_progress": _progress("satisfied"),
		"committed_effect_ids": [], "source_outcome_ids": ["m.2:completed"], "activity_step": 7})
	_expect(other.get("resolved", false), "The same proven state failed to resolve on a different trace.")
	_expect(JSON.stringify(other["record"]) != JSON.stringify(record), "Different consequences produced an identical record.")
	_expect((other["record"]["achieved_effect_ids"] as Array).is_empty(), "A record claimed an effect that was never committed.")
	# Resolving stops the arc refilling but the record survives verbatim.
	var closed := Plan.resolve(plan, record)
	_expect(str(closed["status"]) == "resolved", "A resolved plan did not change status.")
	# The stored record is JSON-frozen (the codebase's convention), so compare the
	# facts rather than the numeric representation.
	_expect(str(closed["record"]["alternative_id"]) == str(record["alternative_id"])
		and str(closed["record"]["result"]) == str(record["result"])
		and closed["record"]["source_outcome_ids"] == record["source_outcome_ids"]
		and closed["record"]["achieved_effect_ids"] == record["achieved_effect_ids"]
		and int(closed["record"]["committed_at_step"]) == int(record["committed_at_step"]),
		"Resolving rewrote the record's facts.")
	_expect(not Plan.evaluate(closed, {"desire_progress": _progress("satisfied")}).get("resolved", true),
		"A resolved plan resolved a second time.")
	# The summary states only what was committed.
	var lines: Array = Plan.summary_lines(record)
	_expect(lines.size() >= 2, "Summary produced no factual lines.")
	_expect(str(lines[0]).contains("resolved"), "Summary did not state the result.")

func _test_legacy_campaign() -> void:
	var Store := preload("res://scripts/persistence/StoryStateStore.gd")
	# An old campaign has no plan: progression is preserved and resolution
	# planning is simply unavailable. The old logline is NOT reinterpreted as
	# executable conditions.
	var legacy: Dictionary = Store._migrate_legacy_state({"chapter": 3, "pending_hooks": ["hook.a"]})
	_expect(int(legacy.get("chapter", 0)) == 3, "Migration lost an old campaign's chapter.")
	_expect((legacy.get("pending_hooks", []) as Array).size() == 1, "Migration lost an old campaign's hooks.")
	_expect((legacy.get("resolution_plan", {}) as Dictionary).is_empty(), "An old campaign was given a resolution plan.")
	_expect(Store._validate_data(legacy).is_valid(), "A migrated legacy campaign failed validation.")
	_expect(not Plan.evaluate(legacy.get("resolution_plan", {}), {}).get("resolved", true),
		"A campaign with no plan reported a resolution.")
	# A stored valid plan passes story-state validation; a malformed one does not.
	var with_plan: Dictionary = Store._default_state()
	with_plan["resolution_plan"] = _active_plan()
	_expect(Store._validate_data(with_plan).is_valid(), "Story state rejected a valid resolution plan.")
	var broken: Dictionary = Store._default_state()
	broken["resolution_plan"] = {"version": 1, "id": "", "status": "nonsense",
		"premise_fact_ids": [], "interests": [], "alternatives": []}
	_expect(not Store._validate_data(broken).is_valid(), "Story state accepted a malformed resolution plan.")

func _test_composed_plan() -> void:
	# Drive the REAL composer on the StoryManager autoload with actual generated
	# agendas, so a plan that cannot bind fails here rather than in play.
	var Desire := preload("res://scripts/persistence/GeneratedFactionDesire.gd")
	var Store := preload("res://scripts/persistence/StoryStateStore.gd")
	var manager: Node = root.get_node("StoryManager")
	var previous: Dictionary = manager.story_state.duplicate(true)
	var previous_store: Variant = manager._story_state_store
	manager.story_state = Store._default_state()
	manager._story_state_store = null
	var agendas: Array = []
	var found := {}
	for i in range(6000):
		var desire: Dictionary = Desire.build("resolution_fixture_%d" % i, "local", i)
		var key := ""
		if desire["need"] == "survey data from a drift it cannot reach": key = "survey"
		if desire["need"] == "filed claim evidence": key = "claims"
		if key.is_empty() or found.has(key): continue
		found[key] = true
		agendas.append({"faction_id": "faction.local." + key, "faction_name": "Local " + key, "desire": desire})
		if found.size() == 2: break
	var context := {"post_tutorial_unlocked": true, "system_id": "system.local",
		"station_id": "station.local", "agendas": agendas}
	var authored: Dictionary = manager.ensure_resolution_plan(context)
	_expect(authored.get("ok", false), "The composer could not author a plan: %s" % authored.get("reason", ""))
	if bool(authored.get("ok", false)):
		var plan: Dictionary = manager.story_state["resolution_plan"]
		_expect(str(plan.get("status", "")) == "active", "A composed plan did not activate against real interests.")
		_expect((plan.get("interests", []) as Array).size() == found.size(), "Composed plan lost an interest.")
		_expect(Plan.validate(plan).is_valid(), "A composed plan failed its own validation.")
		_expect(Store._validate_data(manager.story_state).is_valid(), "A composed plan failed story-state validation.")
		# Every interest must promise an implemented effect.
		for interest: Dictionary in plan["interests"]:
			for effect: Variant in interest["supported_effect_ids"]:
				_expect(str(effect) in Outcome.SUPPORTED_EFFECTS, "A composed interest promised an unimplemented effect.")
		# The tutorial guard holds.
		var locked := context.duplicate(true)
		locked["post_tutorial_unlocked"] = false
		_expect(not manager.ensure_resolution_plan(locked).get("ok", true), "A plan was authored before tutorial completion.")
		# Re-running is idempotent, not a reroll.
		var again: Dictionary = manager.ensure_resolution_plan(context)
		_expect(not again.get("changed", true), "Re-running the composer rerolled the plan.")
	# With no supported interest, no plan is invented.
	manager.story_state = Store._default_state()
	var barren: Dictionary = manager.ensure_resolution_plan({"post_tutorial_unlocked": true,
		"system_id": "system.local", "station_id": "station.local", "agendas": []})
	_expect(not barren.get("ok", true), "A plan was invented with no supported interest.")
	_expect((manager.story_state.get("resolution_plan", {}) as Dictionary).is_empty(), "A barren campaign stored a plan.")
	manager.story_state = previous
	manager._story_state_store = previous_store
