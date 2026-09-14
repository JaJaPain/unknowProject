extends RefCounted

## Turns a VERIFIED collection opportunity into an ordinary board posting.
##
## Pure. Every world fact arrives in `context`, so the same builder runs in a
## test and in the game. It invents nothing: the item, source, destination and
## recipient all come from the already-compiled collection contract, and if the
## caller cannot supply a real recipient record the posting is WITHHELD rather
## than addressed to nobody.
##
## The prose is deliberately narrow. A delivery posting says the item is being
## carried to a named person at a named station, and stops. It does not say the
## lease transfers, the claim clears, the debt settles or the roster is restored
## -- none of those is an effect the game can record, and a sentence claiming one
## would be the reskin this whole package exists to prevent.

const Contract := preload("res://scripts/domain/CollectionContract.gd")
const CausalCompiler := preload("res://scripts/domain/QuestCausalContractCompiler.gd")
const CausalContract := preload("res://scripts/domain/QuestCausalContract.gd")
const Plausibility := preload("res://scripts/domain/QuestPlausibilityValidator.gd")
const Definition := preload("res://scripts/domain/MissionDefinition.gd")

## Template IDs are per COLLECTION, not per verb, so two collections never share
## a board cooldown and the ordinary posting-ownership key stays distinct.
const TEMPLATE_PREFIX := "board.collection"


## Build one posting, or report why it cannot be built.
##
## `context` supplies: reward_credits, station_display, origin_display,
## destination_display and `recipient` {id, name, role, station_id, protected}.
static func build(opportunity: Dictionary, context: Dictionary) -> Dictionary:
	var contract: Variant = opportunity.get("contract", {})
	if not contract is Dictionary or not Contract.validate(contract as Dictionary).is_valid():
		return _withheld("invalid_collection_contract", "contract")
	var bound: Dictionary = contract
	var objective_type := Contract.objective_type_for(bound)
	if objective_type.is_empty():
		return _withheld("unsupported_collection_action", "action")
	var reward := int(context.get("reward_credits", 0))
	if reward <= 0:
		return _withheld("missing_reward_budget", "reward_credits")
	var recipient: Variant = context.get("recipient", {})
	if not recipient is Dictionary or (recipient as Dictionary).is_empty():
		return _withheld("no_local_recipient", "recipient")
	var person: Dictionary = recipient
	if str(person.get("id", "")) != str(bound["recipient_id"]):
		# The posting must address the SAME contact the contract bound, not
		# whoever happens to be standing at the destination now.
		return _withheld("recipient_does_not_match_contract", "recipient.id")
	if bool(person.get("protected", false)):
		return _withheld("protected_character_recipient", "recipient.protected")
	var agenda: Variant = opportunity.get("agenda", {})
	if not agenda is Dictionary or (agenda as Dictionary).is_empty():
		return _withheld("missing_agenda", "agenda")
	var requester: Dictionary = agenda
	var desire: Dictionary = requester.get("desire", {}) if requester.get("desire", {}) is Dictionary else {}
	var objective := _objective(bound, objective_type, context, reward)
	if objective.is_empty():
		return _withheld("unsupported_collection_action", "action")
	var quest := _quest_data(bound, requester, desire, objective, context, person)
	var causal: Dictionary = quest.get("causal_contract", {})
	if causal.is_empty():
		return _withheld("uncompilable_causal_contract", "causal_contract")
	var plausible := Plausibility.validate(causal, {"system_id": str(bound["system_id"])})
	if not plausible.is_valid():
		return _withheld("implausible_causal_contract:%s"
			% str(plausible.errors[0].get("code", "unknown")), "causal_contract")
	var definition := Definition.new().load_from_offer(quest)
	if not definition.is_valid():
		return _withheld("invalid_collection_objective:%s"
			% str(definition.errors[0].get("code", "unknown")), "objective")
	return {"ok": true, "posting": _offer(bound, quest, objective, context, person, reward)}


static func template_id(contract: Dictionary) -> String:
	return "%s.%s" % [TEMPLATE_PREFIX, str(contract.get("id", "")).replace("collection.", "")]


## The runtime objective for this collection's action. Field names are the ones
## the existing capabilities already read; no new objective shape is introduced.
static func _objective(contract: Dictionary, objective_type: String, context: Dictionary,
		reward: int) -> Dictionary:
	var item := str(contract["item_id_or_special_name"])
	var origin_display := str(context.get("origin_display", contract["source_station_id"]))
	var destination_display := str(context.get("destination_display", contract["destination_station_id"]))
	match objective_type:
		"DELIVERY_COURIER":
			return {"type": "DELIVERY_COURIER", "item_name": item,
				"item_id": _item_id(item), "quantity_required": int(contract["quantity"]),
				"origin_station_id": str(contract["source_station_id"]),
				"origin_display": origin_display,
				"destination_station_id": str(contract["destination_station_id"]),
				"destination_display": destination_display,
				"reward_credits": reward}
		"PURCHASE_DELIVERY":
			return {"type": "PURCHASE_DELIVERY", "item_name": item,
				"item_id": _item_id(item), "quantity_required": int(contract["quantity"]),
				"store_station_id": str(contract["source_station_id"]),
				"destination_station_id": str(contract["destination_station_id"]),
				"destination_display": destination_display,
				"reward_credits": reward}
		"PICKUP_SPECIAL":
			return {"type": "PICKUP_SPECIAL",
				"target_outpost": str(contract["source_station_id"]),
				"target_outpost_display": origin_display,
				"target_npc": str(context.get("source_contact_name", "")),
				"part_name": item,
				"destination": str(contract["destination_station_id"]),
				"destination_station_id": str(contract["destination_station_id"]),
				"destination_display": destination_display,
				"reward_credits": reward}
	return {}


static func _item_id(item_name: String) -> String:
	return "item.%s" % item_name.to_lower().replace(" ", "_").replace("-", "_")


## What the posting SAYS. One sentence of cause, one of task, one of payment.
## The task sentence is the whole promise: this item, to this person, here.
static func _body(contract: Dictionary, requester: Dictionary, desire: Dictionary,
		context: Dictionary, person: Dictionary) -> String:
	var faction_name := str(requester.get("faction_name", "the requester"))
	var need := str(desire.get("need", "the consignment"))
	var goal := str(desire.get("goal", "")).strip_edges()
	var reason := str(desire.get("need_reason", "")).strip_edges()
	var obstacle := str(desire.get("obstacle", "")).strip_edges()
	var origin_display := str(context.get("origin_display", contract["source_station_id"]))
	var destination_display := str(context.get("destination_display", contract["destination_station_id"]))
	var lines: Array = []
	if goal.is_empty():
		lines.append("%s needs %s." % [faction_name, need])
	else:
		lines.append("%s needs %s to %s." % [faction_name, need, goal])
	if not reason.is_empty():
		lines.append(reason)
	if not obstacle.is_empty():
		lines.append("It cannot collect this itself: %s." % obstacle)
	# The only promise made anywhere in this posting.
	lines.append("Collect %s at %s and hand it to %s at %s. Payment is for the delivery itself." % [
		str(contract["item_id_or_special_name"]), origin_display,
		str(person.get("name", "the named contact")), destination_display])
	var payment := str(desire.get("payment_source", "")).strip_edges()
	if not payment.is_empty():
		lines.append("Payment comes from %s." % payment)
	return " ".join(lines)


static func _title(contract: Dictionary, requester: Dictionary) -> String:
	return "%s for %s" % [str(contract["item_id_or_special_name"]),
		str(requester.get("faction_name", "a local account"))]


static func _quest_data(contract: Dictionary, requester: Dictionary, desire: Dictionary,
		objective: Dictionary, context: Dictionary, person: Dictionary) -> Dictionary:
	var body := _body(contract, requester, desire, context, person)
	var task := "Deliver %s to %s at %s." % [str(contract["item_id_or_special_name"]),
		str(person.get("name", "the named contact")),
		str(context.get("destination_display", contract["destination_station_id"]))]
	var quest := {
		"id": "mission.collection.%s" % str(contract["id"]).replace("collection.", ""),
		"title": _title(contract, requester),
		"agent_name": str(requester.get("faction_name", "Public Board")),
		"faction": "neutral",
		"dialogue": body,
		"objective_summary": task,
		"objective": objective,
		"public_board": true,
		"choices": [{"id": "choice.accept", "text": "Accept posting",
			"consequence": {"credits_immediate": 0, "reputation_change": {},
				"combat_multiplier": 1.0, "reward_credits_multiplier": 1.0,
				"dialogue_response": "Posting accepted."}}],
		# The frozen bindings travel with the posting from here on: adapter,
		# active mission, save and terminal record all read THIS dictionary.
		"collection_contract": contract.duplicate(true),
		"delivery_recipient_name": str(person.get("name", "")),
	}
	var causal: Dictionary = CausalCompiler.compile({
		"campaign_id": str(contract["campaign_id"]),
		"system_id": str(contract["system_id"]),
		"agenda": requester,
		"objective": objective,
		"cause": {"cause_id": str(contract["cause_id"]),
			"cause_faction_id": str(contract["faction_id"]),
			"desire_id": str(contract["desire_id"])},
		"requester_display": str(requester.get("faction_name", "")),
		"action_helps": task,
		"delegation": str(context.get("delegation", "")),
		"recipient": person,
	})
	if causal.is_empty():
		return quest
	quest["causal_contract"] = causal
	quest["narrative_metadata"] = {
		"cause_faction_id": str(contract["faction_id"]),
		"cause_id": str(contract["cause_id"]),
		"desire_id": str(contract["desire_id"]),
		"public_because": str(desire.get("need_reason", "")),
		"collection_id": str(contract["id"]),
		"causal_contract": causal.duplicate(true),
	}
	return quest


static func _offer(contract: Dictionary, quest: Dictionary, objective: Dictionary,
		context: Dictionary, person: Dictionary, reward: int) -> Dictionary:
	var causal: Dictionary = quest.get("causal_contract", {}) if quest.get("causal_contract", {}) is Dictionary else {}
	return {
		"template_id": template_id(contract),
		"enabled": true,
		"title": str(quest["title"]),
		"poster": str(quest["agent_name"]),
		"body": str(quest["dialogue"]),
		"objective": str(quest["objective_summary"]),
		"base_reward": reward,
		"duration_minutes": 0,
		"urgent_multiplier": 1.0,
		"collection_posting": true,
		"collection_id": str(contract["id"]),
		# Semantic, and deliberately separate from the posting's identity.
		"signature": CausalContract.semantic_signature_v2(causal) if not causal.is_empty() else "",
		"quest_data": quest,
		"required_placeholders": [],
		"placeholder_values": {
			"{ITEM_NAME}": str(contract["item_id_or_special_name"]),
			"{DESTINATION}": str(context.get("destination_display", contract["destination_station_id"])),
			"{RECIPIENT}": str(person.get("name", "")),
			"{POSTER_HANDLE}": str(quest["agent_name"]),
		},
	}


static func _withheld(reason: String, missing_binding: String) -> Dictionary:
	return {"ok": false, "reason": reason, "missing_binding": missing_binding}
