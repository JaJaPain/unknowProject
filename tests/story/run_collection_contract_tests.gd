extends SceneTree

## Package 3: the eight delivery-shaped edges, bound to real world data.
##
## The point of every case here is that a SENTENCE is not a binding. A need with
## an item name in it, a destination with a display label, or a recipient who
## happens to be standing somewhere are all refused unless the world actually
## supplies them.

const Contract := preload("res://scripts/domain/CollectionContract.gd")
const Outcome := preload("res://scripts/domain/MissionOutcome.gd")
const Ledger := preload("res://scripts/story/DesireProgressLedger.gd")
const Compiler := preload("res://scripts/domain/CollectionOpportunityCompiler.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_test_supported_catalogue()
	_test_missing_bindings_withhold()
	_test_compiled_contract()
	_test_item_delivered_effect()
	_test_ledger_records_the_delivery()
	_test_opportunity_compilation()
	_test_opportunity_withholding()
	_test_posting_generation()
	_test_posting_withholding()
	if failures.is_empty():
		print("[PASS] Collection contracts: supported edges, withheld bindings, item_delivered effect, delivery receipts, world-bound opportunities and generated board postings")
		quit(0)
		return
	for message in failures:
		push_error("[FAIL] " + message)
	quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _source(overrides: Dictionary = {}) -> Dictionary:
	var value := {"campaign_id": "campaign.test", "system_id": "system.local",
		"faction_id": "faction.local.records", "desire_id": "desire.local.records",
		"cause_id": "cause.local.records", "obstacle_binding_id": "carrier_cancelled",
		"need": "sealed manifests from the last shipment"}
	for key in overrides: value[key] = overrides[key]
	return value

func _bindings(overrides: Dictionary = {}) -> Dictionary:
	var value := {"action": "courier", "item_id_or_special_name": "Sealed Manifest Packet",
		"quantity": 1, "source_station_id": "station.origin", "source_supplies": true,
		"destination_station_id": "station.local", "destination_registered": true,
		"recipient_id": "npc.local.clerk", "recipient_is_generated_local": true,
		"store_catalogue": false}
	for key in overrides: value[key] = overrides[key]
	return value

## The catalogue is exactly the audit's eight supported edges, and every
## rejected need reports the capability that is actually missing.
func _test_supported_catalogue() -> void:
	_expect(Contract.SUPPORTED_NEEDS.size() == 8,
		"The supported delivery catalogue is not the audit's eight edges: %d" % Contract.SUPPORTED_NEEDS.size())
	_expect(Contract.unsupported_reason("a clean ore assay") == "no_assay_mechanic",
		"Raw ore was treated as an assay.")
	for need: String in ["route permits", "convoy escort guarantees",
			"a witness who will go on record", "fuel it can afford"]:
		_expect(not Contract.unsupported_reason(need).is_empty(),
			"A rejected need was reported as supported: %s" % need)
	_expect(Contract.unsupported_reason("something invented") == "need_not_in_supported_catalogue",
		"An unknown need was not refused.")
	# Only the ship-part edge may be a store purchase.
	_expect(not bool(Contract.compile(_source(), _bindings({"action": "purchase_delivery",
		"store_catalogue": true})).get("ok", true)),
		"A document need was allowed as a store purchase.")
	var part := Contract.compile(_source({"need": "replacement assemblies"}),
		_bindings({"action": "purchase_delivery", "store_catalogue": true}))
	_expect(bool(part.get("ok", false)),
		"The ship-part edge was refused as a store purchase: %s" % str(part.get("reason", "")))
	var uncatalogued := Contract.compile(_source({"need": "replacement assemblies"}),
		_bindings({"action": "purchase_delivery", "store_catalogue": false}))
	_expect(str(uncatalogued.get("reason", "")) == "item_not_in_store_catalogue",
		"A purchase delivery was allowed for an item no store carries.")


## Each missing binding withholds the edge and NAMES the binding, so an
## unavailable job is diagnosable instead of silently absent.
func _test_missing_bindings_withhold() -> void:
	var cases := {
		"no_source_station": {"source_station_id": ""},
		"source_does_not_supply_item": {"source_supplies": false},
		"no_destination_station": {"destination_station_id": ""},
		"destination_not_registered": {"destination_registered": false},
		"no_local_recipient": {"recipient_id": ""},
		"recipient_is_not_a_generated_local_contact": {"recipient_is_generated_local": false},
		"no_bound_item": {"item_id_or_special_name": ""},
		"unsupported_action": {"action": "teleport"},
	}
	for expected: String in cases:
		var result := Contract.compile(_source(), _bindings(cases[expected]))
		_expect(not bool(result.get("ok", true)),
			"A missing binding still produced a contract: %s" % expected)
		_expect(str(result.get("reason", "")) == expected,
			"Wrong withholding reason: expected %s, got %s" % [expected, str(result.get("reason", ""))])
		_expect(not str(result.get("missing_binding", "")).is_empty(),
			"A withheld edge did not name which binding is missing: %s" % expected)
	for field: String in ["campaign_id", "system_id", "faction_id", "desire_id", "cause_id"]:
		var scoped := Contract.compile(_source({field: ""}), _bindings())
		_expect(str(scoped.get("reason", "")) == "missing_scope",
			"A contract compiled without %s." % field)


func _test_compiled_contract() -> void:
	var built := Contract.compile(_source(), _bindings())
	if not bool(built.get("ok", false)):
		_expect(false, "A fully bound edge was refused: %s" % str(built.get("reason", "")))
		return
	var contract: Dictionary = built["contract"]
	_expect(Contract.validate(contract).is_valid(), "A compiled contract failed its own validation.")
	_expect(str(contract["completion_kind"]) == "item_delivered",
		"A collection contract claimed something other than a delivery.")
	_expect(Contract.objective_type_for(contract) == "DELIVERY_COURIER",
		"A courier contract did not map to the courier objective.")
	# Identity is stable: reopening the same edge resolves to the same collection.
	var again := Contract.compile(_source(), _bindings())
	_expect(str(again["contract"]["id"]) == str(contract["id"]),
		"Recompiling the same edge produced a different collection ID.")
	# A pickup collects from a NAMED person, so it is refused without one.
	_expect(str(Contract.compile(_source(), _bindings({"action": "pickup"})).get("reason", ""))
			== "no_source_contact",
		"A pickup was bound with nobody at the origin to collect from.")
	# A different action is a different collection.
	var pickup := Contract.compile(_source(), _bindings({"action": "pickup",
		"source_contact_id": "npc.origin.foreman"}))
	if not bool(pickup.get("ok", false)):
		_expect(false, "A bound pickup was refused: %s" % str(pickup.get("reason", "")))
		return
	_expect(str(pickup["contract"]["id"]) != str(contract["id"]),
		"Two different actions shared one collection ID.")
	_expect(Contract.objective_type_for(pickup["contract"]) == "PICKUP_SPECIAL",
		"A pickup contract did not map to the pickup objective.")
	_expect(str(pickup["contract"]["source_contact_id"]) == "npc.origin.foreman",
		"A pickup contract lost the contact it collects from.")
	_expect(str(contract["source_contact_id"]).is_empty(),
		"A courier contract invented a source contact it does not use.")
	# Validation refuses a contract whose completion claims more.
	var overreaching := contract.duplicate(true)
	overreaching["completion_kind"] = "ownership_cleared"
	_expect(not Contract.validate(overreaching).is_valid(),
		"A contract claiming a legal outcome passed validation.")


func _quest(contract: Dictionary, objective_type: String) -> Dictionary:
	return {
		"runtime_id": "mission.runtime.collection",
		"objective_type": objective_type,
		"system_id": str(contract.get("system_id", "")),
		"collection_contract": contract,
		"narrative_metadata": {"cause_faction_id": str(contract.get("faction_id", "")),
			"desire_id": str(contract.get("desire_id", "")), "cause_id": str(contract.get("cause_id", ""))},
	}


## The effect proves the delivery and nothing else, and it carries WHO actually
## received the item so a later milestone cannot credit the wrong recipient.
func _test_item_delivered_effect() -> void:
	var contract: Dictionary = Contract.compile(_source(), _bindings())["contract"]
	var built := Outcome.build(_quest(contract, "DELIVERY_COURIER"), "completed", 250, 100, "campaign.test")
	if not bool(built.get("ok", false)):
		_expect(false, "A bound delivery outcome was refused: %s" % str(built.get("reason", "")))
		return
	var effects: Array = built["outcome"]["effects"]
	_expect(effects.size() == 1, "A bound delivery recorded %d effects." % effects.size())
	var effect: Dictionary = effects[0]
	_expect(str(effect["kind"]) == "item_delivered", "The delivery effect was not item_delivered.")
	_expect(str(effect["collection_id"]) == str(contract["id"]), "The effect did not cite its collection.")
	_expect(str(effect["recipient_id"]) == "npc.local.clerk", "The effect did not record who received the item.")
	_expect(str(effect["destination_station_id"]) == "station.local", "The effect did not record where it arrived.")
	# The wrong verb for this contract records nothing.
	var mismatched := Outcome.build(_quest(contract, "PICKUP_SPECIAL"), "completed", 250, 100, "campaign.test")
	_expect((mismatched["outcome"]["effects"] as Array).is_empty(),
		"A mission completing a different objective claimed the contract's delivery.")
	# An unfinished mission proves nothing.
	var abandoned := Outcome.build(_quest(contract, "DELIVERY_COURIER"), "abandoned", 0, 100, "campaign.test")
	_expect((abandoned["outcome"]["effects"] as Array).is_empty(),
		"An abandoned delivery recorded an effect.")
	# An invalid contract on a mission records no effect rather than a vague one.
	var broken := contract.duplicate(true)
	broken["recipient_id"] = ""
	var unbound := Outcome.build(_quest(broken, "DELIVERY_COURIER"), "completed", 250, 100, "campaign.test")
	_expect((unbound["outcome"]["effects"] as Array).is_empty(),
		"An unbound collection still recorded a delivery.")


## The ledger records the exact item, quantity, destination, recipient, cause and
## outcome ID; the delivery retires its own cause but does NOT satisfy the
## faction's broad goal; and paying twice for one delivery is impossible.
func _test_ledger_records_the_delivery() -> void:
	var contract: Dictionary = Contract.compile(_source(), _bindings())["contract"]
	var outcome: Dictionary = Outcome.build(_quest(contract, "DELIVERY_COURIER"), "completed", 250, 100, "campaign.test")["outcome"]
	var applied := Ledger.apply_outcome(Ledger.empty_state(), outcome, {})
	if not bool(applied.get("ok", false)):
		_expect(false, "The ledger refused a bound delivery: %s" % str(applied.get("reason", "")))
		return
	var state: Dictionary = applied["state"]
	var receipts: Array = Ledger.fulfilled_collection_receipts(state)
	_expect(receipts.size() == 1, "The ledger recorded %d delivery receipts." % receipts.size())
	if receipts.size() == 1:
		var receipt: Dictionary = receipts[0]
		_expect(str(receipt["collection_id"]) == str(contract["id"]), "The receipt cited the wrong collection.")
		_expect(str(receipt["item_id_or_special_name"]) == "Sealed Manifest Packet", "The receipt lost the item.")
		_expect(int(receipt["quantity"]) == 1, "The receipt lost the quantity.")
		_expect(str(receipt["destination_station_id"]) == "station.local", "The receipt lost the destination.")
		_expect(str(receipt["recipient_id"]) == "npc.local.clerk", "The receipt lost the recipient.")
		_expect(str(receipt["cause_id"]) == "cause.local.records", "The receipt lost the cause.")
		_expect(str(receipt["outcome_id"]) == str(outcome["id"]), "The receipt lost its source outcome.")
	# The broad goal is NOT satisfied by a delivery.
	_expect(not Ledger.is_satisfied(state, "system.local", "faction.local.records", "desire.local.records"),
		"Delivering a document satisfied the faction's legal goal.")
	var entry: Dictionary = (state["entries"] as Dictionary).values()[0]
	_expect(str(entry["state"]) == "progressed", "A delivery left the desire at %s." % str(entry["state"]))
	# The exact fulfilled collection cause is retired.
	_expect("cause.local.records" in Ledger.retired_cause_ids(state),
		"A fulfilled collection did not retire its own cause.")
	# Repeating the same terminal outcome applies once.
	var repeated := Ledger.apply_outcome(state, outcome, {})
	_expect(str(repeated.get("reason", "")) == "duplicate_outcome",
		"A repeated delivery was applied twice.")
	_expect(Ledger.fulfilled_collection_receipts(repeated["state"]).size() == 1,
		"A repeated delivery produced a second receipt.")


func _opportunity_context(overrides: Dictionary = {}) -> Dictionary:
	var value := {
		"campaign_id": "campaign.test", "system_id": "system.local",
		"posting_station_id": "station.local",
		"stations": {
			"station.local": {"registered": true, "supplies": [], "store_catalogue": [],
				"recipients": ["npc.local.clerk", "npc.local.broker"], "tutorial_only": false},
			"station.origin": {"registered": true,
				"supplies": ["Sealed Manifest Bundle", "Transfer Coupling"],
				"store_catalogue": ["Transfer Coupling"], "recipients": [], "tutorial_only": false},
		},
		"agendas": [
			{"faction_id": "faction.records", "faction_name": "Local Records",
				"desire": {"id": "desire.records", "need": "sealed manifests from the last shipment",
					"obstacle_binding_id": "carrier_cancelled"}},
			{"faction_id": "faction.assay", "faction_name": "Local Assay",
				"desire": {"id": "desire.assay", "need": "a clean ore assay",
					"obstacle_binding_id": "carrier_cancelled"}},
		],
		"retired_cause_ids": [],
	}
	for key in overrides: value[key] = overrides[key]
	return value


## A real source, a registered destination and a generated local contact produce
## a bound opportunity; the assay need is withheld because no assay exists.
func _test_opportunity_compilation() -> void:
	var compiled := Compiler.compile_opportunities(_opportunity_context())
	var opportunities: Array = compiled["opportunities"]
	var withheld: Array = compiled["withheld"]
	_expect(opportunities.size() == 1, "Expected exactly one bound opportunity, got %d." % opportunities.size())
	if opportunities.size() == 1:
		var contract: Dictionary = opportunities[0]["contract"]
		_expect(str(contract["source_station_id"]) == "station.origin",
			"The opportunity did not bind a station that actually supplies the item.")
		_expect(str(contract["destination_station_id"]) == "station.local",
			"The opportunity did not deliver to the posting station.")
		_expect(str(contract["recipient_id"]) == "npc.local.broker",
			"The opportunity did not bind a stable generated local contact: %s" % str(contract["recipient_id"]))
		_expect(str(contract["item_id_or_special_name"]) == "Sealed Manifest Bundle",
			"The opportunity bound an item the source does not stock.")
	var assay_withheld := false
	for entry: Dictionary in withheld:
		if str(entry["desire_id"]) == "desire.assay":
			assay_withheld = true
			_expect(str(entry["reason"]) == "no_assay_mechanic",
				"The ore-assay need was withheld for the wrong reason: %s" % str(entry["reason"]))
	_expect(assay_withheld, "The ore-assay need was not withheld.")


## Every unbound world produces a NAMED missing binding rather than a job.
func _test_opportunity_withholding() -> void:
	var cases := {
		"no_local_recipient": {"stations": {
			"station.local": {"registered": true, "supplies": [], "store_catalogue": [], "recipients": []},
			"station.origin": {"registered": true, "supplies": ["Sealed Manifest Bundle"], "recipients": []}}},
		"destination_not_registered": {"stations": {
			"station.local": {"registered": false, "recipients": ["npc.local.clerk"]},
			"station.origin": {"registered": true, "supplies": ["Sealed Manifest Bundle"], "recipients": []}}},
		"source_does_not_supply_item": {"stations": {
			"station.local": {"registered": true, "supplies": [], "recipients": ["npc.local.clerk"]},
			"station.unregistered": {"registered": false, "supplies": [], "recipients": []}}},
		"recipient_is_not_a_generated_local_contact": {"stations": {
			"station.local": {"registered": true, "recipients": ["npc.jenna_kross"], "tutorial_only": true},
			"station.origin": {"registered": true, "supplies": ["Sealed Manifest Bundle"], "recipients": []}}},
	}
	for expected: String in cases:
		var compiled := Compiler.compile_opportunities(_opportunity_context(cases[expected]))
		_expect((compiled["opportunities"] as Array).is_empty(),
			"An unbound world still produced a job: %s" % expected)
		var found := false
		for entry: Dictionary in compiled["withheld"]:
			if str(entry["desire_id"]) == "desire.records" and str(entry["reason"]) == expected:
				found = true
				_expect(not str(entry["missing_binding"]).is_empty(),
					"A withheld edge did not name its binding: %s" % expected)
		_expect(found, "Expected withholding reason %s was not reported." % expected)
	# A source that is also the destination is not a delivery.
	var same_station := _opportunity_context({"stations": {
		"station.local": {"registered": true, "supplies": ["Sealed Manifest Bundle"],
			"recipients": ["npc.local.clerk"]}}})
	_expect((Compiler.compile_opportunities(same_station)["opportunities"] as Array).is_empty(),
		"A job was created to carry an item across the station it is already at.")
	# A courier origin issues its consignment at acceptance, so it does NOT need
	# a store entry -- but it must still be a real registered station.
	var courier_world := _opportunity_context({"stations": {
		"station.local": {"registered": true, "store_catalogue": [], "recipients": ["npc.local.clerk"]},
		"station.origin": {"registered": true, "store_catalogue": [], "recipients": []}}})
	var couriered: Array = Compiler.compile_opportunities(courier_world)["opportunities"]
	_expect(couriered.size() == 1,
		"A courier edge was withheld even though its origin is a real registered station.")
	if couriered.size() == 1:
		var contract: Dictionary = couriered[0]["contract"]
		_expect(str(contract["action"]) == "courier",
			"A stockless origin produced a %s rather than a courier." % str(contract["action"]))
		_expect(str(contract["source_station_id"]) == "station.origin",
			"The courier edge bound the wrong origin.")
	# A cause already fulfilled is never reposted under a new ID.
	var retired := _opportunity_context()
	var first := Compiler.compile_opportunities(retired)
	retired["retired_cause_ids"] = [str(first["opportunities"][0]["contract"]["cause_id"])]
	_expect((Compiler.compile_opportunities(retired)["opportunities"] as Array).is_empty(),
		"A fulfilled collection cause was reposted.")


## ---------------------------------------------------------------------------
## The board posting generated FROM a verified collection opportunity.
## ---------------------------------------------------------------------------

const Posting := preload("res://scripts/domain/CollectionPostingBuilder.gd")

func _opportunity_for_posting() -> Dictionary:
	var built := Contract.compile(_source(), _bindings())
	return {"contract": built["contract"], "need": str(_source()["need"]),
		"faction_name": "Local Records",
		"agenda": {"faction_id": "faction.local.records", "faction_name": "Local Records",
			"desire": {"id": "desire.local.records",
				"need": "sealed manifests from the last shipment",
				"goal": "settle a disputed salvage debt",
				"need_reason": "The sealed originals record which deliveries count against the debt.",
				"obstacle": "its contracted carrier has cancelled the collection",
				"triggering_event": "the carrier entering liquidation before dispatch",
				"payment_source": "the retainer its storage contract pays"}}}

func _posting_context(overrides: Dictionary = {}) -> Dictionary:
	var value := {"reward_credits": 280, "station_display": "Local Station",
		"origin_display": "Origin Depot", "destination_display": "Local Station",
		"delegation": "Its contracted carrier has cancelled the collection, so it is hiring an independent pilot.",
		"recipient": {"id": "npc.local.clerk", "name": "Mara Vance", "role": "clerk",
			"station_id": "station.local", "protected": false}}
	for key in overrides: value[key] = overrides[key]
	return value


func _test_posting_generation() -> void:
	var built := Posting.build(_opportunity_for_posting(), _posting_context())
	if not bool(built.get("ok", false)):
		_expect(false, "A verified opportunity produced no posting: %s" % str(built.get("reason", "")))
		return
	var posting: Dictionary = built["posting"]
	var quest: Dictionary = posting["quest_data"]
	var objective: Dictionary = quest["objective"]
	_expect(str(objective["type"]) == "DELIVERY_COURIER",
		"The posting used the wrong verb for a courier collection: %s" % str(objective["type"]))
	_expect(str(objective["origin_station_id"]) == "station.origin",
		"The posting did not send the player to the bound source.")
	_expect(str(objective["destination_station_id"]) == "station.local",
		"The posting did not deliver to the bound destination.")
	_expect(str(objective["item_name"]) == "Sealed Manifest Packet",
		"The posting carried an item the contract did not bind.")
	# The contract travels with the posting.
	_expect(quest.get("collection_contract", {}) is Dictionary 			and str((quest["collection_contract"] as Dictionary)["id"]) == str(_opportunity_for_posting()["contract"]["id"]),
		"The posting lost its collection contract.")
	_expect(str(quest["delivery_recipient_name"]) == "Mara Vance",
		"The posting did not name the bound recipient.")
	_expect(not str(posting.get("signature", "")).is_empty(),
		"The posting carries no semantic signature.")
	_expect(bool(posting.get("collection_posting", false)),
		"The posting did not declare itself a collection posting.")
	# No sentence claims a broader effect than the delivery.
	var prose := (str(posting["body"]) + " " + str(posting["objective"])).to_lower()
	for overreach: String in ["transfers the lease", "clears the claim", "settles the debt",
			"restores the roster", "reopens the route", "certifies", "wins the bid"]:
		_expect(not prose.contains(overreach),
			"A posting sentence claimed an effect the game cannot record: '%s'" % overreach)
	_expect(prose.contains("payment is for the delivery itself"),
		"The posting did not limit its promise to the delivery.")
	# Two different collections are two different templates.
	var other := _opportunity_for_posting()
	other["contract"]["id"] = "collection.other"
	_expect(Posting.template_id(other["contract"]) != Posting.template_id(_opportunity_for_posting()["contract"]),
		"Two collections shared one board template ID.")


## A posting is withheld rather than addressed to nobody, or to the wrong person.
func _test_posting_withholding() -> void:
	var cases := {
		"missing_reward_budget": {"reward_credits": 0},
		"no_local_recipient": {"recipient": {}},
		"recipient_does_not_match_contract": {"recipient": {"id": "npc.someone_else",
			"name": "Someone Else", "role": "clerk", "station_id": "station.local"}},
		"protected_character_recipient": {"recipient": {"id": "npc.local.clerk",
			"name": "Kaelen", "role": "clerk", "station_id": "station.local", "protected": true}},
	}
	for expected: String in cases:
		var result := Posting.build(_opportunity_for_posting(), _posting_context(cases[expected]))
		_expect(not bool(result.get("ok", true)), "A posting was built anyway: %s" % expected)
		_expect(str(result.get("reason", "")).begins_with(expected),
			"Wrong withholding reason: expected %s, got %s" % [expected, str(result.get("reason", ""))])
		_expect(not str(result.get("missing_binding", "")).is_empty(),
			"A withheld posting did not name its binding: %s" % expected)
	# An implausible recipient role is refused by the existing validator.
	var bad_role := _posting_context({"recipient": {"id": "npc.local.clerk", "name": "Mara Vance",
		"role": "poet", "station_id": "station.local", "protected": false}})
	_expect(str(Posting.build(_opportunity_for_posting(), bad_role).get("reason", "")).begins_with(
		"implausible_causal_contract"),
		"A recipient who cannot accept a delivery was accepted.")
	# An invalid contract never becomes a posting.
	var broken := _opportunity_for_posting()
	broken["contract"]["recipient_id"] = ""
	_expect(str(Posting.build(broken, _posting_context()).get("reason", "")) == "invalid_collection_contract",
		"An unbound contract produced a posting.")
