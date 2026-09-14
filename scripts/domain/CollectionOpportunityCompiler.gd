extends RefCounted

## Turns generated faction desires into VERIFIED collection opportunities.
##
## Pure: every fact about the world arrives in `context`, so this is testable
## without a scene and cannot accidentally consult a live node. The caller is
## responsible for capturing the world honestly; this module is responsible for
## refusing anything the capture does not actually support.
##
## Never invents a source, a destination, a recipient or a route. An edge whose
## bindings are incomplete is WITHHELD with the exact binding named, and the
## caller is expected to log that rather than substitute something plausible.

const Contract := preload("res://scripts/domain/CollectionContract.gd")
const DesireType := preload("res://scripts/persistence/GeneratedFactionDesire.gd")
const ConstraintsType := preload("res://scripts/persistence/GeneratedDesireConstraints.gd")

## Cap from the director packet contract in the handoff. Compiling more than
## this is allowed; SUPPLYING more than this to a writer is not.
const MAX_DIRECTOR_CANDIDATES := 8


## Compile every supported edge the world can actually back.
##
## `context` supplies:
##   campaign_id, system_id,
##   agendas: [{faction_id, faction_name, desire}],
##   stations: {station_id: {registered: bool, supplies: [item names],
##              store_catalogue: [item names], recipients: [npc ids],
##              tutorial_only: bool}},
##   posting_station_id: where the job would be posted,
##   retired_cause_ids: causes already fulfilled.
##
## Returns {opportunities: [...], withheld: [{desire_id, need, reason,
## missing_binding}]}. Both halves matter: the withheld list is the diagnostic
## the handoff asks for.
static func compile_opportunities(context: Dictionary) -> Dictionary:
	var opportunities: Array = []
	var withheld: Array = []
	var campaign_id := str(context.get("campaign_id", ""))
	var system_id := str(context.get("system_id", ""))
	var stations: Dictionary = context.get("stations", {}) if context.get("stations", {}) is Dictionary else {}
	var retired: Array = context.get("retired_cause_ids", []) if context.get("retired_cause_ids", []) is Array else []
	for raw: Variant in (context.get("agendas", []) as Array if context.get("agendas", []) is Array else []):
		if not raw is Dictionary:
			continue
		var agenda: Dictionary = raw
		var desire: Dictionary = agenda.get("desire", {}) if agenda.get("desire", {}) is Dictionary else {}
		var need := str(desire.get("need", ""))
		var desire_id := str(desire.get("id", ""))
		var faction_id := str(agenda.get("faction_id", ""))
		if desire_id.is_empty() or faction_id.is_empty():
			continue
		var unsupported := Contract.unsupported_reason(need)
		if not unsupported.is_empty():
			withheld.append(_withheld(desire_id, need, unsupported, "need"))
			continue
		var cause_id := _cause_id(campaign_id, system_id, desire_id)
		if cause_id in retired or desire_id in retired:
			withheld.append(_withheld(desire_id, need, "cause_already_fulfilled", "cause_id"))
			continue
		var source := {"campaign_id": campaign_id, "system_id": system_id,
			"faction_id": faction_id, "desire_id": desire_id, "cause_id": cause_id,
			"obstacle_binding_id": str(desire.get("obstacle_binding_id", "")), "need": need}
		var bound := _bind(source, need, stations, context)
		if not bool(bound.get("ok", false)):
			withheld.append(_withheld(desire_id, need, str(bound.get("reason", "")),
				str(bound.get("missing_binding", ""))))
			continue
		var built := Contract.compile(source, bound["bindings"])
		if not bool(built.get("ok", false)):
			withheld.append(_withheld(desire_id, need, str(built.get("reason", "")),
				str(built.get("missing_binding", ""))))
			continue
		opportunities.append({"contract": built["contract"], "agenda": agenda.duplicate(true),
			"need": need, "faction_name": str(agenda.get("faction_name", ""))})
	opportunities.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["contract"]["id"]) < str(b["contract"]["id"]))
	withheld.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["desire_id"]) < str(b["desire_id"]))
	return {"opportunities": opportunities, "withheld": withheld}


## Find a real source, destination, recipient and item for one need.
##
## Order matters: the ITEM has to exist somewhere before a station can be called
## its source, and the destination has to be registered before anyone standing
## there counts as a recipient.
static func _bind(source: Dictionary, need: String, stations: Dictionary, context: Dictionary) -> Dictionary:
	var destination_id := str(context.get("posting_station_id", ""))
	if destination_id.is_empty():
		return _missing("no_destination_station", "destination_station_id")
	var destination: Dictionary = stations.get(destination_id, {}) if stations.get(destination_id, {}) is Dictionary else {}
	if destination.is_empty() or not bool(destination.get("registered", false)):
		return _missing("destination_not_registered", "destination_registered")
	var recipient := _local_recipient(destination)
	if recipient.is_empty():
		return _missing("no_local_recipient", "recipient_id")
	if bool(destination.get("tutorial_only", false)):
		# A tutorial resident is never substituted for a generated contact.
		return _missing("recipient_is_not_a_generated_local_contact", "recipient_is_generated_local")
	# The item vocabulary is the one the desires already draw from; this adds no
	# new item names, it only asks whether the world stocks any of them.
	var raw_items: Variant = DesireType.ITEMS_BY_NEED.get(need,
		ConstraintsType.EXTRA_ITEMS.get(need, []))
	var item_names: Array = raw_items if raw_items is Array else []
	var overrides: Variant = context.get("items_for_need", {})
	var candidates: Array = item_names
	if overrides is Dictionary and (overrides as Dictionary).has(need) 			and (overrides as Dictionary)[need] is Array:
		candidates = (overrides as Dictionary)[need]
	var rule: Dictionary = Contract.SUPPORTED_NEEDS[need]
	# What "this station can supply it" MEANS depends on the verb, because each
	# verb has a different implemented handover:
	#
	#   purchase_delivery -- the player buys it, so the item must really be in
	#       that station's store catalogue. No stock, no purchase.
	#   courier           -- the origin issues a sealed consignment at
	#       acceptance. `GlobalState.accept_special` IS that handover, so a
	#       registered origin distinct from the destination is the whole
	#       requirement; demanding a store entry would model a mechanic the
	#       courier path does not have.
	#   pickup            -- the player collects from a NAMED contact at the
	#       origin, which the pickup capability checks, so the origin must
	#       actually have a contact standing there.
	#
	# None of this loosens the rule that the world must back the job. It makes
	# each action ask for the thing its own capability enforces.
	var station_ids: Array = stations.keys()
	station_ids.sort()
	for action: Variant in (rule["actions"] as Array):
		for station_id: Variant in station_ids:
			if str(station_id) == destination_id:
				continue
			var station: Dictionary = stations[station_id] if stations[station_id] is Dictionary else {}
			if not bool(station.get("registered", false)):
				continue
			var catalogue: Array = station.get("store_catalogue", []) if station.get("store_catalogue", []) is Array else []
			var contacts: Array = station.get("recipients", []) if station.get("recipients", []) is Array else []
			for raw_item: Variant in candidates:
				var item := str(raw_item)
				if item.is_empty():
					continue
				var in_store := item in catalogue
				if str(action) == Contract.ACTION_PURCHASE_DELIVERY and not in_store:
					continue
				if str(action) == Contract.ACTION_PICKUP and contacts.is_empty():
					continue
				return {"ok": true, "bindings": {
					"action": str(action),
					"item_id_or_special_name": item,
					"quantity": int(rule.get("quantity", 1)),
					"source_station_id": str(station_id),
					"source_supplies": true,
					"store_catalogue": in_store,
					"source_contact_id": str(contacts[0]) if not contacts.is_empty() else "",
					"destination_station_id": destination_id,
					"destination_registered": true,
					"recipient_id": recipient,
					"recipient_is_generated_local": true,
				}}
	return _missing("source_does_not_supply_item", "source_supplies")


## The first generated local contact at this station, by stable sorted ID, so
## two visits bind the same person.
static func _local_recipient(station: Dictionary) -> String:
	var recipients: Array = station.get("recipients", []) if station.get("recipients", []) is Array else []
	var ids: Array = []
	for raw: Variant in recipients:
		var id := str(raw).strip_edges()
		if not id.is_empty():
			ids.append(id)
	if ids.is_empty():
		return ""
	ids.sort()
	return str(ids[0])


static func _cause_id(campaign_id: String, system_id: String, desire_id: String) -> String:
	return "cause.collection.%s" % ("%s|%s|%s" % [campaign_id, system_id, desire_id]).sha256_text().substr(0, 24)


static func _missing(reason: String, binding: String) -> Dictionary:
	return {"ok": false, "reason": reason, "missing_binding": binding}


static func _withheld(desire_id: String, need: String, reason: String, binding: String) -> Dictionary:
	return {"desire_id": desire_id, "need": need, "reason": reason, "missing_binding": binding}
