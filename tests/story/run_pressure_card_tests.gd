extends SceneTree

## Pressure postings through the REAL board lifecycle: frozen terms, retired
## causes, prototype exclusion and immutable accepted terms.

const Board := preload("res://scripts/domain/InvestigationBoardLifecycle.gd")
const Desire := preload("res://scripts/persistence/GeneratedFactionDesire.gd")
const Director := preload("res://scripts/story/LocalPressureDirector.gd")
const Adapter := preload("res://scripts/domain/MissionAdapter.gd")
const Validator := preload("res://scripts/domain/InvestigationStateValidator.gd")

var failures: Array[String] = []
var base: Dictionary = {}

func _initialize():
	call_deferred("_run")

func _run():
	base = _context()
	if base.get("agendas", []).size() != 2:
		_expect(false, "Could not build coherent fixture agendas.")
	else:
		_test_unpressured_baseline()
		_test_frozen_terms()
		_test_retired_cause()
		_test_terms_survive_acceptance()
	if failures.is_empty():
		print("[PASS] Pressure cards: frozen terms, maximum modifier, retired causes, immutable accepted terms")
	else:
		for message in failures: push_error("[FAIL] " + message)
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _context() -> Dictionary:
	var agendas: Array = []
	var found := {}
	for i in range(6000):
		var desire: Dictionary = Desire.build("pressure_fixture_%d" % i, "local", i)
		if desire["obstacle_binding_id"] != "dispatch_backlog": continue
		var key := ""
		if desire["need"] == "survey data from a drift it cannot reach": key = "survey"
		if desire["need"] == "filed claim evidence" and desire["goal"] == "clear its name on a salvage claim": key = "claims"
		if key.is_empty() or found.has(key): continue
		found[key] = true
		agendas.append({"faction_id": "faction.local." + key, "faction_name": "Local " + key.capitalize(), "desire": desire})
		if found.size() == 2: break
	return {"campaign_id": "campaign.test", "campaign_seed": 89, "system_id": "system.local",
		"station_id": "station.local", "station_display": "Local Station", "post_tutorial_unlocked": true,
		"reward_budget": 400, "agendas": agendas,
		"world": {"ok": true, "system_id": "system.local", "stations": [{"id": "station.local", "position": Vector3.ZERO}],
			"hazards": [], "gates": []}}

## The claims agenda, and a level-3 claims constraint bound to it.
func _claims_agenda() -> Dictionary:
	for agenda: Dictionary in base["agendas"]:
		if str(agenda["desire"]["need"]) == "filed claim evidence": return agenda
	return {}

func _constraint(level: int) -> Dictionary:
	var agenda := _claims_agenda()
	var modifiers: Dictionary = {}
	if level == 3:
		modifiers["preserve"] = {"numerator": 5, "denominator": 4}
	return {"pressure_id": "pressure.claims.fixture", "pressure_revision": 2, "kind": "claims",
		"system_id": "system.local", "station_id": "station.local",
		"faction_id": str(agenda["faction_id"]), "desire_id": str(agenda["desire"]["id"]),
		"cause_id": str(agenda["desire"]["id"]), "level_at_offer": level,
		"preferred_shape_ids": ["mission_shape.competing_claims"], "ore_relief": false, "forced_forged": false,
		"payout_numerator": 1, "payout_denominator": 1, "branch_modifiers": modifiers,
		"public_label": "Ownership of local salvage is disputed.", "display_name": "Contested salvage claims",
		"escalates_after": 2}

## Only the claims agenda, so the claims constraint MUST bind. Without this the
## shape draw can pick the survey cause and the frozen-terms assertions below
## would never execute.
func _claims_only_context() -> Dictionary:
	var context := base.duplicate(true)
	var agendas: Array = []
	for agenda: Dictionary in context["agendas"]:
		var copy: Dictionary = agenda.duplicate(true)
		if str(copy["desire"]["need"]) != "filed claim evidence":
			# Still a local claimant faction (competing_claims needs two), but no
			# longer an eligible cause, so the claims draw is deterministic.
			copy["desire"]["obstacle_binding_id"] = "handling_damage"
		agendas.append(copy)
	context["agendas"] = agendas
	return context


func _prepare(context: Dictionary) -> Dictionary:
	return Board.prepare(Board.empty_state(89), context)

func _test_unpressured_baseline() -> void:
	# With no constraints nothing is stamped and ordinary fractions still apply.
	var prepared := _prepare(base)
	_expect(prepared.get("ok", false), "Baseline preparation failed: %s" % prepared)
	if not prepared.get("ok", false): return
	var posting: Dictionary = prepared["posting"]
	_expect(str(posting.get("pressure_id", "")).is_empty(), "An unpressured posting carried a pressure ID.")
	var investigation: Dictionary = posting["quest_data"]["objective"]["investigation"]
	_expect((investigation.get("branch_payouts", {}) as Dictionary).is_empty(),
		"An unpressured posting froze branch payouts.")

func _test_frozen_terms() -> void:
	var context := _claims_only_context()
	context["pressure_constraints"] = [_constraint(3)]
	var prepared := _prepare(context)
	_expect(prepared.get("ok", false), "Pressured preparation failed: %s" % prepared)
	if not prepared.get("ok", false): return
	var posting: Dictionary = prepared["posting"]
	_expect(not str(posting.get("pressure_id", "")).is_empty(),
		"A claims constraint failed to stamp its own claims posting.")
	if str(posting.get("pressure_id", "")).is_empty(): return
	_expect(str(posting["pressure_id"]) == "pressure.claims.fixture", "Posting carried the wrong pressure ID.")
	_expect(int(posting["pressure_revision"]) == 2, "Posting lost its pressure revision.")
	_expect(int(posting["level_at_offer"]) == 3, "Posting lost the level it was offered at.")
	_expect(bool(posting["pressure_relief"]), "A pressure posting was not marked as relief.")
	_expect(int(posting["escalates_after"]) == 2, "Card did not state escalation in resolved jobs.")
	# Claims base 400: preserve pays 500 at level 3, report stays 200.
	var frozen: Dictionary = posting["quest_data"]["objective"]["investigation"]["branch_payouts"]
	_expect(int(frozen.get("preserve", 0)) == 500, "Level-3 preserve did not freeze at 500, got %d." % int(frozen.get("preserve", 0)))
	_expect(int(frozen.get("report", 0)) == 200, "Report was modified; it must stay 200, got %d." % int(frozen.get("report", 0)))
	_expect(not frozen.has("liquidate"), "An unfunded liquidation branch was priced.")
	# Level 1 applies no modifier at all.
	var low := _claims_only_context()
	low["pressure_constraints"] = [_constraint(1)]
	var cheap := _prepare(low)
	_expect(bool(cheap.get("ok", false)) and not str(cheap["posting"].get("pressure_id", "")).is_empty(),
		"Level 1 claims posting did not build.")
	if bool(cheap.get("ok", false)) and not str(cheap["posting"].get("pressure_id", "")).is_empty():
		var terms: Dictionary = cheap["posting"]["quest_data"]["objective"]["investigation"]["branch_payouts"]
		_expect(int(terms.get("preserve", 0)) == 400, "Level 1 changed the preserve payout.")
		_expect(int(terms.get("report", 0)) == 200, "Level 1 changed the report payout.")
	# The frozen snapshot must pass real investigation validation.
	_expect(Validator.validate(posting["quest_data"]["objective"]).is_valid(),
		"A frozen-terms objective failed real investigation validation.")

func _test_retired_cause() -> void:
	# A fulfilled cause is not a fresh reason, under any new ID or station.
	var context := base.duplicate(true)
	var prepared := _prepare(context)
	if not prepared.get("ok", false): return
	var used := str(prepared["posting"]["quest_data"]["investigation_cause"]["agenda"]["desire"]["id"])
	context["retired_cause_ids"] = [used]
	var again := _prepare(context)
	if bool(again.get("ok", false)):
		var next := str(again["posting"]["quest_data"]["investigation_cause"]["agenda"]["desire"]["id"])
		_expect(next != used, "A retired fulfilled cause was resurrected as a new posting.")
	# Retiring every cause leaves the track without an actionable posting rather
	# than minting a reskin.
	var all_causes: Array = []
	for agenda: Dictionary in base["agendas"]:
		all_causes.append(str(agenda["desire"]["id"]))
	context["retired_cause_ids"] = all_causes
	var exhausted := _prepare(context)
	_expect(not bool(exhausted.get("ok", false)), "Exhausted causes still produced a posting.")
	_expect(str(exhausted.get("reason", "")) == "no_supported_local_cause",
		"Exhausted causes reported '%s'." % exhausted.get("reason", ""))

func _test_terms_survive_acceptance() -> void:
	var context := _claims_only_context()
	context["pressure_constraints"] = [_constraint(3)]
	var prepared := _prepare(context)
	_expect(prepared.get("ok", false) and not str(prepared["posting"].get("pressure_id", "")).is_empty(),
		"Acceptance fixture did not produce a pressured posting.")
	if not prepared.get("ok", false) or str(prepared["posting"].get("pressure_id", "")).is_empty():
		return
	var quest: Dictionary = prepared["posting"]["quest_data"]
	var adapted := Adapter.build_active_state(quest, quest["choices"][0], "mission.runtime.pressure", "system.local", 0)
	_expect(adapted["validation"].is_valid(), "A pressured posting failed the real mission adapter.")
	if not adapted["validation"].is_valid(): return
	var state: Dictionary = adapted["state"]
	# Accepted terms are immutable and must reach the terminal record intact.
	_expect(str(state.get("pressure_id", "")) == "pressure.claims.fixture", "Acceptance dropped the pressure ID.")
	_expect(int(state.get("pressure_revision", 0)) == 2, "Acceptance dropped the pressure revision.")
	_expect(int(state.get("level_at_offer", 0)) == 3, "Acceptance dropped the offered level.")
	_expect(bool(state.get("pressure_relief", false)), "Acceptance dropped the relief designation.")
	var frozen: Dictionary = state["investigation"]["branch_payouts"]
	_expect(int(frozen.get("preserve", 0)) == 500, "Acceptance rewrote the frozen preserve payout.")
	# A save roundtrip preserves the agreed terms exactly.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state))
	_expect(int(saved["investigation"]["branch_payouts"]["preserve"]) == 500, "A save roundtrip changed accepted terms.")
	_expect(str(saved.get("pressure_id", "")) == "pressure.claims.fixture", "A save roundtrip dropped the pressure ID.")
