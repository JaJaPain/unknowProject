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
	_test_v2_binding()
	_test_v2_evaluation()
	_test_v1_stays_v1()
	if failures.is_empty():
		print("[PASS] Campaign resolution: validation, binding, guards, evaluation, factual record, v2 collection milestones and v1 compatibility")
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
		"records": [], "achieved_effect_ids": ["effect.recorder.1"], "source_outcome_ids": ["m.1:completed"],
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
		"committed_effect_ids": ["effect.recorder.1"],
		"source_outcome_ids": ["m.1:completed"], "activity_step": 7})
	_expect(resolved.get("resolved", false), "A proven desire state did not resolve the plan.")
	if not resolved.get("resolved", false): return
	var record: Dictionary = resolved["record"]
	_expect(str(record["result"]) == "success", "Resolution recorded the wrong result.")
	_expect(str(record["alternative_id"]) == "alt.success", "Resolution recorded the wrong alternative.")
	_expect("m.1:completed" in (record["source_outcome_ids"] as Array), "Record lost its source outcome IDs.")
	_expect("effect.recorder.1" in (record["achieved_effect_ids"] as Array), "Record lost its achieved effect ID.")
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
		if desire.get("obstacle_binding_id", "") != "dispatch_backlog": continue
		var key := ""
		if desire["need"] == "survey data from a drift it cannot reach": key = "survey"
		if desire["need"] == "filed claim evidence" and desire["goal"] == "clear its name on a salvage claim": key = "claims"
		if key.is_empty() or found.has(key): continue
		found[key] = true
		agendas.append({"faction_id": "faction.local." + key, "faction_name": "Local " + key, "desire": desire})
		if found.size() == 2: break
	var context := {"post_tutorial_unlocked": true, "system_id": "system.local",
		"station_id": "station.local", "agendas": agendas}
	var authored: Dictionary = manager.ensure_resolution_plan(context)
	_expect(not authored.get("ok", true) and manager.story_state.get("resolution_plan", {}).is_empty(), "Board visit invented a campaign ending.")
	# A persisted explicit proposal can bind; the board cannot author it.
	manager.story_state["resolution_plan"] = manager._compose_resolution_plan(manager._resolution_interest_candidates(context))
	authored = manager.ensure_resolution_plan(context)
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
		var elsewhere := context.duplicate(true)
		elsewhere["system_id"] = "system.other"
		elsewhere["agendas"] = []
		manager.ensure_resolution_plan(elsewhere)
		_expect(manager.story_state["resolution_plan"] == plan, "Travel changed the frozen active plan.")
	_expect(not Plan.validate({"version": 1, "id": "bad", "status": "pending_bindings"}).is_valid(), "Missing plan lists were accepted.")
	# With no supported interest, no plan is invented.
	manager.story_state = Store._default_state()
	var barren: Dictionary = manager.ensure_resolution_plan({"post_tutorial_unlocked": true,
		"system_id": "system.local", "station_id": "station.local", "agendas": []})
	_expect(not barren.get("ok", true), "A plan was invented with no supported interest.")
	_expect((manager.story_state.get("resolution_plan", {}) as Dictionary).is_empty(), "A barren campaign stored a plan.")
	manager.story_state = previous
	manager._story_state_store = previous_store
	_test_cumulative_consumer()

func _test_cumulative_consumer() -> void:
	var manager: Node = root.get_node("StoryManager")
	var previous: Dictionary = manager.story_state.duplicate(true)
	var plan := _active_plan()
	plan["alternatives"][0]["all_of"] = [{"kind": "effect_committed", "effect_id": "effect.recorder.1"}, {"kind": "effect_committed", "effect_id": "effect.recorder.2"}]
	var progress := _progress("progressed")
	progress["entries"]["system.local|faction.a|desire.a"]["achieved_effect_ids"].append("effect.recorder.2")
	manager.story_state["resolution_plan"] = plan
	manager.story_state["desire_progress"] = progress
	var delta: Dictionary = manager._evaluate_resolution({"effects": []})
	_expect(delta.get("kind", "") == "campaign_resolved", "Consumer ignored cumulative effects outside the current outcome.")
	_expect(manager.story_state["resolution_record"]["achieved_effect_ids"].size() == 2, "Resolution lost earlier effect provenance.")
	manager.story_state = previous


## ---------------------------------------------------------------------------
## Package 4: campaign collection milestones, separate from faction goals.
## ---------------------------------------------------------------------------

const LedgerType := preload("res://scripts/story/DesireProgressLedger.gd")
const ContractType := preload("res://scripts/domain/CollectionContract.gd")

func _v2_interest(overrides: Dictionary = {}) -> Dictionary:
	var value := {"id": "interest.collection", "system_id": "system.local",
		"faction_id": "faction.a", "desire_id": "desire.a",
		"collection_id": "collection.abc", "station_id": "station.local",
		"recipient_id": "npc.local.clerk", "completion_kind": "item_delivered",
		"supported_effect_ids": [Outcome.EFFECT_ITEM_DELIVERED]}
	for key in overrides: value[key] = overrides[key]
	return value


func _v2_plan(interest: Dictionary = {}) -> Dictionary:
	var bound: Dictionary = interest if not interest.is_empty() else _v2_interest()
	return {"version": 2, "id": "resolution.v2", "status": "pending_bindings",
		"premise_fact_ids": [], "interests": [bound],
		"alternatives": [{"id": "alt.success", "result": "success",
			"all_of": [{"kind": "collection_satisfied", "collection_id": str(bound["collection_id"])}],
			"public_fact_ids": []}]}


func _delivery_progress(overrides: Dictionary = {}) -> Dictionary:
	var record := {"kind": "item_delivered", "effect_id": "effect.delivered.1",
		"outcome_id": "m.delivery:completed", "at_minute": 40, "cause_id": "cause.a",
		"collection_id": "collection.abc", "item_id_or_special_name": "Sealed Manifest Bundle",
		"quantity": 1, "destination_station_id": "station.local", "recipient_id": "npc.local.clerk"}
	for key in overrides: record[key] = overrides[key]
	var key := LedgerType.key_for("system.local", "faction.a", "desire.a")
	return {"version": 1, "entries": {key: {"system_id": "system.local", "faction_id": "faction.a",
		"desire_id": "desire.a", "cause_id": "cause.a", "state": "progressed",
		"satisfied_by_predicate": "", "records": [record],
		"achieved_effect_ids": [str(record["effect_id"])],
		"source_outcome_ids": [str(record["outcome_id"]), "m.unrelated:completed"],
		"last_outcome_id": str(record["outcome_id"]), "last_terminal_state": "completed", "revision": 1}}}


func _v2_context() -> Dictionary:
	return {"desires": [{"system_id": "system.local", "faction_id": "faction.a", "desire_id": "desire.a"}],
		"system_ids": ["system.local"], "station_ids": ["station.local"],
		"known_fact_ids": [], "effect_ids": [], "collection_ids": ["collection.abc"]}


## A v2 plan binds only against a collection the campaign really owns, and only
## when that collection is one of the plan's own interests.
func _test_v2_binding() -> void:
	var plan := _v2_plan()
	var bound := Plan.bind(plan, _v2_context())
	_expect(bool(bound.get("ok", false)) and str(bound["plan"]["status"]) == "active",
		"A fully bound v2 plan did not activate: %s" % str(bound.get("reason", "")))
	var unknown := _v2_context()
	unknown["collection_ids"] = []
	_expect(str(Plan.bind(_v2_plan(), unknown).get("reason", "")) == "unknown_collection_reference",
		"A plan referencing a collection the campaign does not own was activated.")
	# A collection predicate that matches no interest is refused.
	var stray := _v2_plan()
	stray["alternatives"][0]["all_of"][0]["collection_id"] = "collection.other"
	var stray_context := _v2_context()
	stray_context["collection_ids"] = ["collection.abc", "collection.other"]
	_expect(str(Plan.bind(stray, stray_context).get("reason", "")) == "collection_not_an_interest",
		"A collection predicate not tied to an interest was accepted.")
	# A v2 interest missing its collection binding is structurally invalid.
	for field: String in ["collection_id", "station_id", "recipient_id"]:
		var broken := _v2_plan(_v2_interest({field: ""}))
		_expect(not Plan.validate(broken).is_valid(),
			"A v2 interest without %s passed validation." % field)
	var wrong_kind := _v2_plan(_v2_interest({"completion_kind": "ownership_cleared"}))
	_expect(not Plan.validate(wrong_kind).is_valid(),
		"A v2 interest citing an unimplemented completion kind passed validation.")
	# v1 never gains the v2 predicate by reinterpretation.
	var v1 := _v2_plan()
	v1["version"] = 1
	_expect(not Plan.validate(v1).is_valid(),
		"A v1 plan accepted a collection_satisfied predicate.")


## Delivering resolves the COLLECTION, not the faction's legal goal, and a
## receipt that differs on any identifying axis does not count.
func _test_v2_evaluation() -> void:
	var plan: Dictionary = Plan.bind(_v2_plan(), _v2_context())["plan"]
	var progress := _delivery_progress()
	var resolved := Plan.evaluate(plan, {"desire_progress": progress,
		"committed_effect_ids": ["effect.delivered.1"], "activity_step": 3,
		"source_outcome_ids": ["m.delivery:completed", "m.unrelated:completed"]})
	_expect(bool(resolved.get("resolved", false)),
		"A matching delivery receipt did not resolve its collection milestone.")
	if bool(resolved.get("resolved", false)):
		var record: Dictionary = resolved["record"]
		_expect("m.delivery:completed" in (record["source_outcome_ids"] as Array),
			"Ending provenance lost the outcome that actually decided it.")
		_expect("m.unrelated:completed" not in (record["source_outcome_ids"] as Array),
			"Ending provenance included an unrelated mission.")
		_expect((record["known_fact_ids"] as Array).is_empty(),
			"A summary cited a fact the knowledge ledger does not know.")
	# The faction's broad goal is untouched: the desire stays progressed.
	_expect(not LedgerType.is_satisfied(progress, "system.local", "faction.a", "desire.a"),
		"A delivery satisfied the faction's broad legal goal.")
	# Wrong recipient, wrong station and wrong collection all fail closed.
	var mismatches := {
		"recipient_id": "npc.someone_else",
		"destination_station_id": "station.elsewhere",
		"collection_id": "collection.other",
	}
	for field: String in mismatches:
		var wrong := _delivery_progress({field: mismatches[field]})
		_expect(not bool(Plan.evaluate(plan, {"desire_progress": wrong,
			"committed_effect_ids": ["effect.delivered.1"]}).get("resolved", true)),
			"A receipt with the wrong %s satisfied the milestone." % field)
	# A survey filed with the wrong certification does not satisfy a
	# verified-evidence milestone.
	var survey_plan: Dictionary = Plan.bind(_v2_plan(_v2_interest({
		"completion_kind": Outcome.EFFECT_VERIFIED_SURVEY})), _v2_context())["plan"]
	_expect(not bool(Plan.evaluate(survey_plan, {"desire_progress": _delivery_progress(),
		"committed_effect_ids": ["effect.delivered.1"]}).get("resolved", true)),
		"A delivery receipt satisfied a verified-survey milestone.")
	# Cumulative receipts from separate jobs survive canonical JSON conversion.
	var canonical: Dictionary = JSON.parse_string(JSON.stringify(_delivery_progress()))
	_expect(LedgerType.fulfilled_collection_receipts(canonical).size() == 1,
		"A delivery receipt did not survive canonical conversion.")


## A v1 plan keeps its original predicates and is marked for diagnostics.
func _test_v1_stays_v1() -> void:
	var legacy := _plan()
	var bound := Plan.bind(legacy, _context())
	_expect(bool(bound.get("ok", false)), "A v1 plan stopped loading: %s" % str(bound.get("reason", "")))
	if bool(bound.get("ok", false)):
		_expect(bool(bound["plan"].get("legacy_resolution", false)),
			"A v1 plan was not marked legacy_resolution for diagnostics.")
		_expect(int(bound["plan"]["version"]) == 1,
			"A v1 plan was silently upgraded to v2.")
		_expect(JSON.stringify(bound["plan"]["alternatives"]) == JSON.stringify(legacy["alternatives"]),
			"A v1 plan had its predicates reinterpreted.")
	_expect(Plan.is_legacy_plan(legacy), "is_legacy_plan did not recognise a v1 plan.")
	_expect(not Plan.is_legacy_plan(_v2_plan()), "is_legacy_plan mislabelled a v2 plan.")
	# item_delivered may never close a desire on its own.
	_expect(not LedgerType.SATISFYING_EFFECTS.has(Outcome.EFFECT_ITEM_DELIVERED),
		"A delivery was listed as an effect that can satisfy a faction's goal.")
