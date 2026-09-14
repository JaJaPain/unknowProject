extends RefCounted

## Persisted offer ownership. Callers commit returned state before displaying it.
## No model text, wall clock or scene iteration order can redraw a published job.
const Selector := preload("res://scripts/domain/InvestigationSelector.gd")
const Builder := preload("res://scripts/domain/InvestigationOfferBuilder.gd")
const Planner := preload("res://scripts/domain/InvestigationSitePlanner.gd")
const Placement := preload("res://scripts/domain/InvestigationWorldPlacement.gd")
const Shapes := preload("res://scripts/domain/MissionShapeRegistry.gd")
const Desire := preload("res://scripts/persistence/GeneratedFactionDesire.gd")
const StateValidator := preload("res://scripts/domain/InvestigationStateValidator.gd")
const Validation := preload("res://scripts/domain/ValidationResult.gd")
const Compiler := preload("res://scripts/domain/QuestCausalContractCompiler.gd")
const Plausibility := preload("res://scripts/domain/QuestPlausibilityValidator.gd")
const Definition := preload("res://scripts/domain/MissionDefinition.gd")

static func empty_state(seed_value: int) -> Dictionary:
	return {"version": 1, "selection": Selector.empty_state(seed_value), "entries": {}}

## Preparing is speculative. Failed placement or unsupported causes consume nothing.
static func prepare(saved: Dictionary, context: Dictionary) -> Dictionary:
	if not bool(context.get("post_tutorial_unlocked", false)):
		return _failure("tutorial_locked")
	if str(context.get("campaign_id", "")).is_empty() or str(context.get("system_id", "")).is_empty():
		return _failure("missing_scope")
	var state := saved.duplicate(true) if not saved.is_empty() else empty_state(int(context.get("campaign_seed", 0)))
	if not validate(state).is_valid():
		return _failure("invalid_saved_board")
	var entries: Dictionary = state["entries"]
	var owner := _owner(context)
	for entry: Dictionary in entries.values():
		# Ordinary postings share this dictionary but are not investigations.
		if posting_kind(entry) != POSTING_KIND_INVESTIGATION:
			continue
		if str(entry["owner"]) == owner and str(entry["status"]) != "retired":
			return _persistable({"ok": true, "state": state, "offer_id": entry["offer_id"], "posting": entry["posting"].duplicate(true)})
	var candidates := _candidates(context)
	# A retired fulfilled cause is never a fresh reason, under any new ID.
	var retired: Array = context.get("retired_cause_ids", [])
	if not retired.is_empty():
		var fresh: Array = []
		for candidate: Dictionary in candidates:
			if _offer_id(context, candidate) not in retired and str(candidate["agenda"]["desire"]["id"]) not in retired:
				fresh.append(candidate)
		candidates = fresh
	if candidates.is_empty():
		return _failure("no_supported_local_cause")
	# Discretionary family pacing. The caller decides; this only refuses to post
	# what the pacing window already said it would withhold.
	var pacing: Dictionary = context.get("family_pacing", {}) if context.get("family_pacing", {}) is Dictionary else {}
	if not pacing.is_empty() and not bool(pacing.get("allowed", true)):
		return _failure("withheld_family_pacing")
	# Shape-bag eligibility remains authoritative; within each shape prefer the
	# least-repeated real cause before constructing any site truth or posting.
	var scored: Array = []
	for candidate: Dictionary in candidates:
		var objective := {"type": "INVESTIGATE_SIGNAL", "recipe": candidate["recipe"], "reward_credits": context.get("reward_budget", 0)}
		var preview := _posting(_offer_id(context, candidate), candidate, objective, context)
		var signature := preload("res://scripts/domain/QuestCausalContract.gd").semantic_signature_v2(preview["quest_data"]["causal_contract"])
		scored.append({"id": _offer_id(context, candidate), "signature": signature, "candidate": candidate})
	var ranked := preload("res://scripts/persistence/NoveltyHistoryStore.gd").rank_candidates(context.get("novelty_history", {}), scored, int(context.get("campaign_seed", 0)), str(context.get("campaign_history_id", "")))
	candidates = []
	for entry: Dictionary in ranked:
		candidates.append(entry["candidate"])
	var registry := Shapes.new()
	if not registry.load_from_path().is_valid():
		return _failure("invalid_shape_catalog")
	var by_shape: Dictionary = {}
	for candidate: Dictionary in candidates:
		var id := _offer_id(context, candidate)
		if entries.has(id):
			continue # A retired cause is not a fresh reason for the same work.
		var shape = registry.shape_for_recipe(str(candidate["recipe"]))
		if shape != null and not by_shape.has(str(shape.id)):
			by_shape[str(shape.id)] = candidate
	if by_shape.is_empty():
		return _failure("causes_already_used")
	# Only one draft globally: two simultaneous peeks cannot commit the same bag.
	for entry: Dictionary in entries.values():
		if posting_kind(entry) == POSTING_KIND_INVESTIGATION and str(entry["status"]) == "prepared":
			return _failure("another_offer_preparing")
	var reservation_key := "pending.%s" % owner
	var reservation := Selector.reserve(state["selection"], by_shape.keys(), reservation_key)
	if reservation.is_empty():
		return _failure("no_shape")
	var selected: Dictionary = by_shape[str(reservation["shape_id"])]
	var offer_id := _offer_id(context, selected)
	var world: Dictionary = context.get("world", {})
	var local_stations: Array = []
	for station: Dictionary in world.get("stations", []):
		if str(context.get("station_id", "")) in station.get("ids", [station.get("id", "")]):
			local_stations.append(station)
	var placement := Planner.plan_sites(int(reservation["seed"]), local_stations,
		world.get("hazards", []), world.get("gates", []))
	# Anchor at the posting station, but clear every other station too.
	if bool(placement.get("ok", false)):
		for site: Dictionary in placement["sites"]:
			var p: Array = site["position"]
			if not Planner.is_position_safe(Vector3(p[0], p[1], p[2]), world.get("hazards", []), world.get("stations", []), world.get("gates", [])):
				return _failure("no_safe_sites")
	var shape = registry.get_shape(reservation["shape_id"])
	var branches: Array = shape.branch_ids.duplicate()
	# A client seeking evidence has not funded its destruction. No invented buyer.
	branches.erase("liquidate")
	var budget := int(context.get("reward_budget", 0))
	if budget <= 0:
		return _failure("missing_reward_budget")
	var pressure := _pressure_for(context, selected)
	var branch_payouts := _branch_payouts(str(shape.recipe), branches, budget, pressure)
	var built := Builder.build_objective(offer_id, {"id": str(shape.id), "recipe": str(shape.recipe), "branch_ids": branches},
		int(reservation["seed"]), placement, budget, str(context.get("station_id", "")), selected["claimants"], str(context["system_id"]),
		branch_payouts)
	if not bool(built.get("ok", false)):
		return built
	var objective: Dictionary = built["objective"]
	objective["system_id"] = str(context["system_id"])
	if not StateValidator.validate(objective).is_valid():
		return _failure("invalid_objective")
	var checked := Placement.check_saved_sites(objective, world)
	if not bool(checked.get("ok", false)):
		return checked
	var posting := _posting(offer_id, selected, objective, context, pressure)
	if not Plausibility.validate(posting["quest_data"]["causal_contract"], {"system_id": context["system_id"]}).is_valid():
		return _failure("invalid_causal_contract")
	entries[offer_id] = {"offer_id": offer_id, "owner": owner, "status": "prepared", "reservation_key": reservation_key,
		"eligible_shapes": by_shape.keys(), "cause": selected.duplicate(true), "posting": posting}
	return _persistable({"ok": true, "state": state, "offer_id": offer_id, "posting": posting.duplicate(true)})

## ---------------------------------------------------------------------------
## Ordinary (non-investigation) postings.
##
## Same ownership machinery, same entries dictionary, same save. The only
## differences are the `posting_kind` discriminator and which validators run:
## an ordinary objective has no investigation sites, so site validation must not
## be applied to it.
## ---------------------------------------------------------------------------

const POSTING_KIND_INVESTIGATION := "investigation"
const POSTING_KIND_ORDINARY := "ordinary"


## A missing discriminator means a posting written before ordinary jobs owned
## their identity, and those were all investigations.
static func posting_kind(entry: Dictionary) -> String:
	var kind := str(entry.get("posting_kind", ""))
	return kind if kind in [POSTING_KIND_INVESTIGATION, POSTING_KIND_ORDINARY] else POSTING_KIND_INVESTIGATION


## Reuse or create the persisted identity for ONE ordinary posting.
##
## `candidate` is an already-validated, already-ranked offer whose objective and
## terms are final. Reopening the board returns the same publication ID and the
## same frozen posting: an ordinary publication ID is allocated exactly once.
## The caller commits the returned state; a failed save means no exposure was
## recorded, because nothing was written.
static func claim_ordinary(saved: Dictionary, context: Dictionary, candidate: Dictionary) -> Dictionary:
	if str(context.get("campaign_id", "")).is_empty() or str(context.get("system_id", "")).is_empty():
		return _failure("missing_scope")
	var template_id := str(candidate.get("template_id", "")).strip_edges()
	if template_id.is_empty():
		return _failure("missing_template_id")
	var quest: Variant = candidate.get("quest_data", {})
	if not quest is Dictionary or (quest as Dictionary).is_empty():
		return _failure("missing_quest_data")
	var objective: Variant = (quest as Dictionary).get("objective", {})
	if not objective is Dictionary or (objective as Dictionary).is_empty():
		return _failure("missing_objective")
	var state := saved.duplicate(true) if not saved.is_empty() else empty_state(int(context.get("campaign_seed", 0)))
	if not validate(state).is_valid():
		return _failure("invalid_saved_board")
	var entries: Dictionary = state["entries"]
	var owner := _owner(context)
	var key := _ordinary_key(owner, template_id)
	var existing: Dictionary = entries.get(key, {}) if entries.get(key, {}) is Dictionary else {}
	if not existing.is_empty() and str(existing.get("status", "")) != "retired":
		# Reopening never allocates another ID and never rewrites frozen terms.
		return _persistable({"ok": true, "state": state, "offer_id": key,
			"publication_id": str(existing.get("publication_id", "")),
			"reused": true, "posting": (existing["posting"] as Dictionary).duplicate(true)})
	var checks := _validate_ordinary(quest, context)
	if not bool(checks.get("ok", false)):
		return checks
	var next_id := maxi(0, int(state.get("next_ordinary_publication_id", 0)))
	state["next_ordinary_publication_id"] = next_id + 1
	var publication_id := "publication.ordinary.%d" % next_id
	var frozen: Dictionary = candidate.duplicate(true)
	frozen["offer_id"] = key
	frozen["publication_id"] = publication_id
	frozen["posting_kind"] = POSTING_KIND_ORDINARY
	entries[key] = {
		"offer_id": key,
		"owner": owner,
		"posting_kind": POSTING_KIND_ORDINARY,
		"publication_id": publication_id,
		# Semantic, and deliberately separate from identity: two postings may
		# share a signature and still be two different published jobs.
		"signature": str(candidate.get("signature", "")),
		"status": "published",
		"reservation_key": "",
		"eligible_shapes": [],
		"cause": (quest as Dictionary).get("narrative_metadata", {}) if (quest as Dictionary).get("narrative_metadata", {}) is Dictionary else {},
		"posting": frozen,
	}
	return _persistable({"ok": true, "state": state, "offer_id": key,
		"publication_id": publication_id, "reused": false, "posting": frozen.duplicate(true)})


## The real runtime mission ID is recorded on ACCEPTANCE, so a published job and
## the mission it became can be reconciled after a reload.
static func record_ordinary_acceptance(saved: Dictionary, offer_id: String, runtime_mission_id: String) -> Dictionary:
	var state := saved.duplicate(true)
	var entries: Dictionary = state.get("entries", {}) if state.get("entries", {}) is Dictionary else {}
	var entry: Dictionary = entries.get(offer_id, {}) if entries.get(offer_id, {}) is Dictionary else {}
	if entry.is_empty() or posting_kind(entry) != POSTING_KIND_ORDINARY:
		return _failure("offer_unavailable")
	if runtime_mission_id.is_empty():
		return _failure("missing_runtime_mission_id")
	entry["runtime_mission_id"] = runtime_mission_id
	entry["status"] = "retired"
	entries[offer_id] = entry
	state["entries"] = entries
	return _persistable({"ok": true, "state": state, "offer_id": offer_id})


static func _ordinary_key(owner: String, template_id: String) -> String:
	return "mission.ordinary.%s" % ("%s|%s" % [owner, template_id]).sha256_text().substr(0, 24)


## Ordinary objectives get the ordinary validators: mission definition, causal
## contract and (for a delivery) its recipient. Investigation site planning and
## state validation are NOT applicable and are never run here.
static func _validate_ordinary(quest: Dictionary, context: Dictionary) -> Dictionary:
	var definition := Definition.new().load_from_offer(quest)
	if not definition.is_valid():
		# Name the actual defect: a withheld posting must say what is missing.
		return _failure("invalid_ordinary_objective:%s" % str(definition.errors[0].get("code", "unknown")))
	var contract: Variant = quest.get("causal_contract", {})
	if contract is Dictionary and not (contract as Dictionary).is_empty():
		if not Plausibility.validate(contract, {"system_id": context.get("system_id", "")}).is_valid():
			return _failure("invalid_causal_contract")
	var objective: Dictionary = quest["objective"]
	if str(objective.get("type", "")) in ["DELIVERY_COURIER", "PURCHASE_DELIVERY"]:
		var destination := str(objective.get("destination_station_id", "")).strip_edges()
		if destination.is_empty():
			return _failure("missing_delivery_destination")
		var recipients: Dictionary = context.get("delivery_recipients", {}) if context.get("delivery_recipients", {}) is Dictionary else {}
		if not recipients.is_empty() and str(recipients.get(destination, "")).is_empty():
			return _failure("missing_delivery_recipient")
	return {"ok": true}


static func publish(saved: Dictionary, offer_id: String, context: Dictionary) -> Dictionary:
	if not validate(saved).is_valid():
		return _failure("invalid_saved_board")
	var state := saved.duplicate(true)
	var entry: Dictionary = state["entries"].get(offer_id, {})
	if entry.is_empty() or posting_kind(entry) != POSTING_KIND_INVESTIGATION 			or str(entry["owner"]) != _owner(context) or str(entry["status"]) == "retired":
		return _failure("offer_unavailable")
	if not bool(context.get("post_tutorial_unlocked", false)):
		return _failure("tutorial_locked")
	var cause_current := false
	for candidate: Dictionary in _candidates(context):
		if _persistable(candidate) == _persistable(entry["cause"]):
			cause_current = true
	if not cause_current:
		return _failure("cause_changed")
	var objective: Dictionary = entry["posting"]["quest_data"]["objective"]
	var checked := Placement.check_saved_sites(objective, context.get("world", {}))
	if not bool(checked.get("ok", false)):
		return checked
	Selector.publish(state["selection"], entry["eligible_shapes"], str(entry["reservation_key"]))
	entry["status"] = "published"
	return _persistable({"ok": true, "state": state, "offer_id": offer_id, "posting": entry["posting"].duplicate(true)})

## Retiring a published offer preserves its exposure and cause history. Cancelling
## a speculative draft returns the reservation without retiring anything.
static func release(saved: Dictionary, offer_id: String) -> Dictionary:
	var state := saved.duplicate(true)
	if not validate(state).is_valid():
		return state
	var entry: Dictionary = state.get("entries", {}).get(offer_id, {})
	if entry.is_empty():
		return state
	Selector.release(state["selection"], str(entry["reservation_key"]))
	if str(entry["status"]) == "prepared":
		state["entries"].erase(offer_id)
	else:
		entry["status"] = "retired"
	return state

static func _candidates(context: Dictionary) -> Array:
	var result: Array = []
	var agendas: Array = context.get("agendas", [])
	var ids: Array = []
	for agenda: Dictionary in agendas:
		var id := str(agenda.get("faction_id", ""))
		if not id.is_empty() and id not in ids:
			ids.append(id)
	ids.sort()
	for agenda: Dictionary in agendas:
		var desire: Dictionary = agenda.get("desire", {})
		var check := Desire.check_coherence(desire)
		if not bool(check.get("checked", false)) or not bool(check.get("ok", false)):
			continue
		# Other existing blockers describe moving cargo, not collecting new scans.
		if str(desire.get("obstacle_binding_id", "")) != "dispatch_backlog":
			continue
		var recipe := ""
		if str(desire.get("need", "")) == "survey data from a drift it cannot reach":
			recipe = "survey_discrepancy"
		elif str(desire.get("need", "")) == "filed claim evidence" and str(desire.get("goal", "")) == "clear its name on a salvage claim" and ids.size() >= 2:
			recipe = "competing_claims"
		if recipe.is_empty() or str(agenda.get("faction_name", "")).is_empty() or str(agenda.get("faction_id", "")).is_empty():
			continue
		result.append({"recipe": recipe, "agenda": {"faction_id": str(agenda["faction_id"]), "faction_name": str(agenda["faction_name"]), "desire": desire.duplicate(true)}, "claimants": ids.duplicate()})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return str(a["agenda"]["faction_id"]) < str(b["agenda"]["faction_id"]))
	return result

## The active pressure constraint this cause serves, or empty. Matched on the
## exact bound desire/faction/system, never on a display name.
static func _pressure_for(context: Dictionary, candidate: Dictionary) -> Dictionary:
	var desire_id := str(candidate["agenda"]["desire"]["id"])
	var faction_id := str(candidate["agenda"]["faction_id"])
	for raw: Variant in context.get("pressure_constraints", []):
		if not raw is Dictionary:
			continue
		var constraint: Dictionary = raw
		if str(constraint.get("desire_id", "")) != desire_id or str(constraint.get("faction_id", "")) != faction_id:
			continue
		if str(constraint.get("system_id", "")) != str(context.get("system_id", "")):
			continue
		var shapes: Array = constraint.get("preferred_shape_ids", [])
		if shapes.is_empty():
			continue # A track with no implemented shape publishes no posting.
		return constraint.duplicate(true)
	return {}


## Integer floor of each ordinary branch payout times the applicable MAXIMUM
## modifier. Modifiers never multiply, and this is the only place they apply.
static func _branch_payouts(recipe: String, branches: Array, budget: int, pressure: Dictionary) -> Dictionary:
	if pressure.is_empty():
		return {}
	var Pressure = preload("res://scripts/story/LocalPressureDirector.gd")
	var fractions := {
		"report": [1, 2], "certify_match": [1, 1], "certify_mismatch": [1, 1],
		"preserve": [1, 1], "liquidate": [3, 2],
	}
	var modifiers: Dictionary = pressure.get("branch_modifiers", {})
	var default_num := int(pressure.get("payout_numerator", 1))
	var default_den := int(pressure.get("payout_denominator", 1))
	var out: Dictionary = {}
	for branch: Variant in branches:
		var key := str(branch)
		if not fractions.has(key):
			continue
		var fraction: Array = fractions[key]
		var ordinary := int(floor(float(budget) * float(fraction[0]) / float(fraction[1])))
		var modifier: Dictionary = modifiers.get(key, {"numerator": default_num, "denominator": default_den})
		out[key] = Pressure.snapshot_payout(ordinary, int(modifier["numerator"]), int(modifier["denominator"]))
	return out


static func _posting(id: String, candidate: Dictionary, objective: Dictionary, context: Dictionary, pressure: Dictionary = {}) -> Dictionary:
	var agenda: Dictionary = candidate["agenda"]
	var desire: Dictionary = agenda["desire"]
	var survey := str(candidate["recipe"]) == "survey_discrepancy"
	var task := "Compare the route codes at both survey beacons, then file your finding. An unverified report pays half; an incorrect certification pays a quarter." if survey else "Scan the recorder and its ownership record, then preserve the evidence. An unverified report pays half."
	var body := "%s needs %s to %s. %s Its dispatch team has no capacity for another collection. %s Payment comes from %s; return to %s to settle." % [agenda["faction_name"], desire["need"], desire["goal"], desire["need_reason"], task, desire["payment_source"], context.get("station_display", "the posting station")]
	var title := "Survey readings for %s" % agenda["faction_name"] if survey else "Claim records for %s" % agenda["faction_name"]
	var quest := {"id": id, "title": title, "agent_name": str(agenda["faction_name"]), "faction": "neutral", "dialogue": body,
		"objective_summary": task, "objective": objective, "public_board": true,
		"choices": [{"id": "choice.accept", "text": "Accept posting", "consequence": {}}],
		"investigation_cause": candidate.duplicate(true)}
	var contract := Compiler.compile({"campaign_id": context["campaign_id"], "system_id": context["system_id"],
		"agenda": agenda, "objective": objective, "cause": {"cause_id": id, "cause_faction_id": agenda["faction_id"], "desire_id": desire["id"]},
		"requester_display": agenda["faction_name"], "action_helps": task,
		"delegation": "Its dispatch team has no capacity for another collection, so it is commissioning an independent pilot."})
	# Pressure reduction is not implemented yet; do not promise that effect.
	contract["completion_effect_ids"] = []
	quest["causal_contract"] = contract
	quest["narrative_metadata"] = {"cause_faction_id": agenda["faction_id"], "cause_id": id,
		"desire_id": desire["id"], "public_because": desire["need_reason"], "causal_contract": contract.duplicate(true)}
	var posting := {"offer_id": id, "investigation_posting": true, "template_id": "investigation.%s" % candidate["recipe"], "enabled": true,
		"title": title, "poster": str(agenda["faction_name"]), "body": body, "objective": task,
		"base_reward": int(objective["reward_credits"]), "duration_minutes": 0, "urgent_multiplier": 1.0, "quest_data": quest}
	if pressure.is_empty():
		return posting
	# Frozen pressure terms travel with the posting: publication, adapter, active
	# mission, save and terminal record all read the SAME snapshot. A level change
	# may replace an unaccepted offer, but never rewrites accepted terms.
	for field: Array in [["pressure_id", "pressure_id"], ["pressure_revision", "pressure_revision"],
			["level_at_offer", "level_at_offer"]]:
		quest[field[0]] = pressure.get(field[1], 0 if field[0] != "pressure_id" else "")
		posting[field[0]] = quest[field[0]]
	quest["pressure_relief"] = true
	posting["pressure_relief"] = true
	posting["pressure_kind"] = str(pressure.get("kind", ""))
	posting["pressure_label"] = str(pressure.get("public_label", ""))
	posting["pressure_display_name"] = str(pressure.get("display_name", ""))
	posting["escalates_after"] = int(pressure.get("escalates_after", 0))
	quest["narrative_metadata"]["pressure_id"] = str(pressure.get("pressure_id", ""))
	return posting

static func _owner(context: Dictionary) -> String:
	return "%s|%s|%s" % [context.get("campaign_id", ""), context.get("system_id", ""), context.get("station_id", "")]

static func _offer_id(context: Dictionary, candidate: Dictionary) -> String:
	# Independent of time and list order; moving stations cannot duplicate a cause.
	return "mission.investigation.%s" % ("%s|%s|%s|%s" % [context.get("campaign_id", ""), context.get("system_id", ""), candidate["agenda"]["desire"]["id"], candidate["recipe"]]).sha256_text().substr(0, 24)

static func validate(value: Dictionary) -> ValidationResult:
	var result := Validation.new()
	if value.is_empty():
		return result # Additive: old campaigns have no investigation board.
	if int(value.get("version", 0)) != 1 or not value.get("entries") is Dictionary or not value.get("selection") is Dictionary:
		result.add_error("invalid_investigation_board", "Invalid investigation board envelope.")
		return result
	var selection: Dictionary = value["selection"]
	if not selection.get("bags") is Dictionary or not selection.get("outstanding_offers") is Array:
		result.add_error("invalid_investigation_selection", "Invalid investigation selection state.")
		return result
	var reservations := {}
	for raw: Variant in selection["outstanding_offers"]:
		if not raw is Dictionary or str(raw.get("offer_id", "")).is_empty() or not raw.get("pending_bag") is Dictionary:
			result.add_error("invalid_investigation_reservation", "Invalid shape reservation.")
			continue
		if reservations.has(str(raw["offer_id"])):
			result.add_error("duplicate_investigation_reservation", "Duplicate shape reservation.")
		reservations[str(raw["offer_id"])] = raw
	for record: Variant in selection["bags"].values():
		if not record is Dictionary or not record.get("bag") is Dictionary:
			result.add_error("invalid_investigation_bag", "Invalid saved shape bag.")
			continue
		# Explicit cycle fields are optional: a pre-migration bag has neither.
		var saved_record: Dictionary = record
		if saved_record.has("remaining_shape_ids") and not saved_record["remaining_shape_ids"] is Array:
			result.add_error("invalid_investigation_cycle", "Remaining shape IDs must be an array.")
		if saved_record.has("cycle_index") and int(saved_record.get("cycle_index", 0)) < 0:
			result.add_error("invalid_investigation_cycle", "Cycle index must not be negative.")
	for key in value["entries"]:
		var raw: Variant = value["entries"][key]
		if not raw is Dictionary:
			result.add_error("invalid_investigation_entry", "Offer entry must be an object.")
			continue
		var entry: Dictionary = raw
		var kind := posting_kind(entry)
		if str(entry.get("offer_id", "")) != str(key) or str(entry.get("owner", "")).is_empty() 				or str(entry.get("status", "")) not in ["prepared", "published", "retired"] 				or not entry.get("eligible_shapes") is Array or not entry.get("cause") is Dictionary 				or not entry.get("posting") is Dictionary:
			result.add_error("invalid_investigation_entry", "Invalid investigation offer identity or state.")
			continue
		if kind == POSTING_KIND_ORDINARY:
			# An ordinary posting owns a monotonic publication ID instead of a
			# shape reservation, and has no investigation sites to validate.
			if str(entry.get("publication_id", "")).is_empty():
				result.add_error("missing_ordinary_publication_id", "An ordinary posting must own a publication ID.")
			var ordinary_quest: Variant = entry["posting"].get("quest_data")
			if not ordinary_quest is Dictionary or not (ordinary_quest as Dictionary).get("objective") is Dictionary:
				result.add_error("invalid_ordinary_posting", "Missing ordinary objective.")
				continue
			result.merge(Definition.new().load_from_offer(ordinary_quest), str(key))
			var ordinary_contract: Variant = (ordinary_quest as Dictionary).get("causal_contract", {})
			if ordinary_contract is Dictionary and not (ordinary_contract as Dictionary).is_empty():
				result.merge(Plausibility.validate(ordinary_contract), str(key))
			continue
		if str(entry.get("reservation_key", "")).is_empty():
			result.add_error("invalid_investigation_entry", "An investigation offer must own a shape reservation.")
			continue
		if str(entry["status"]) != "retired":
			var reservation: Dictionary = reservations.get(str(entry["reservation_key"]), {})
			if reservation.is_empty() or bool(reservation.get("published", false)) != (str(entry["status"]) == "published"):
				result.add_error("missing_investigation_reservation", "Offer and shape publication disagree.")
		var quest: Variant = entry["posting"].get("quest_data")
		if not quest is Dictionary or not quest.get("objective") is Dictionary:
			result.add_error("invalid_investigation_posting", "Missing investigation objective.")
			continue
		var objective_check := StateValidator.validate(quest["objective"])
		result.merge(objective_check, str(key))
		if not objective_check.is_valid():
			continue
		result.merge(Definition.new().load_from_offer(quest), str(key))
		result.merge(Plausibility.validate(quest.get("causal_contract", {})), str(key))
		if str(quest.get("id", "")) != str(key) or str(quest["objective"].get("investigation", {}).get("mission_id", "")) != str(key):
			result.add_error("investigation_owner_mismatch", "Posting and objective identities disagree.")
		if str(quest["objective"].get("investigation", {}).get("phase", "")) != "search":
			result.add_error("resolved_board_offer", "A posting cannot already be resolved.")
	return result

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _persistable(value: Dictionary) -> Dictionary:
	# Freeze JSON's numeric representation before first display, not on reload.
	return JSON.parse_string(JSON.stringify(value))
