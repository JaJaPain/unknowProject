extends RefCounted

## A delivery-shaped faction need, bound to work the game can actually perform.
##
## Version 1. Compiled from REAL generated world data, never from a desire
## vocabulary alone: an item label in a need is not an inventory source, and a
## destination name is not a registered station. Every binding below must be
## supplied by the caller from the actual world, and a missing one WITHHOLDS the
## edge with a diagnostic naming which binding is absent.
##
## What a fulfilled contract proves is exactly one thing: that this item, in
## this quantity, reached this recipient at this station. It does NOT prove
## ownership clearance, lease transfer, appeal success, survey filing, an assay,
## a route opening, or a faction capacity to pay. The desire moves to
## progressed; only an independently implemented predicate could close it.

const Validation := preload("res://scripts/domain/ValidationResult.gd")

const CONTRACT_VERSION := 1

## The three delivery verbs the game implements today.
const ACTION_PICKUP := "pickup"
const ACTION_COURIER := "courier"
const ACTION_PURCHASE_DELIVERY := "purchase_delivery"
const ACTIONS := [ACTION_PICKUP, ACTION_COURIER, ACTION_PURCHASE_DELIVERY]

## One completion kind, closed. A delivery proves a delivery.
const COMPLETION_ITEM_DELIVERED := "item_delivered"

const OBJECTIVE_BY_ACTION := {
	ACTION_PICKUP: "PICKUP_SPECIAL",
	ACTION_COURIER: "DELIVERY_COURIER",
	ACTION_PURCHASE_DELIVERY: "PURCHASE_DELIVERY",
}

## The eight delivery-shaped edges from docs/cause_coverage_audit_2026_09_14.md.
## Nothing outside this table is a supported delivery edge, and no verb here is
## new. A purchase_delivery edge additionally requires a store catalogue entry.
const SUPPORTED_NEEDS := {
	"a countersigned dock purchase agreement": {"actions": [ACTION_PICKUP, ACTION_COURIER], "quantity": 1},
	"a certified lease valuation": {"actions": [ACTION_PICKUP, ACTION_COURIER], "quantity": 1},
	"signed recruitment papers": {"actions": [ACTION_PICKUP, ACTION_COURIER], "quantity": 1},
	"a countersigned supply agreement": {"actions": [ACTION_PICKUP, ACTION_COURIER], "quantity": 1},
	"sealed manifests from the last shipment": {"actions": [ACTION_PICKUP, ACTION_COURIER], "quantity": 1},
	"food stock for the quarter": {"actions": [ACTION_PICKUP, ACTION_COURIER], "quantity": 1},
	"medical stock for its own crew": {"actions": [ACTION_PICKUP, ACTION_COURIER], "quantity": 1},
	"replacement assemblies": {"actions": [ACTION_PICKUP, ACTION_COURIER, ACTION_PURCHASE_DELIVERY], "quantity": 1},
}

## Needs the audit REJECTED, with the capability that is missing. Kept here so a
## withheld edge reports the real reason rather than a bare "unsupported".
const REJECTED_NEEDS := {
	"a clean ore assay": "no_assay_mechanic",
	"route permits": "no_permit_issuance_or_route_reopening",
	"convoy escort guarantees": "no_escort_capability",
	"a witness who will go on record": "no_testimony_or_recruitment_mechanic",
	"fuel it can afford": "no_bulk_fuel_commodity",
}


static func is_supported_need(need: String) -> bool:
	return SUPPORTED_NEEDS.has(need)


## Why a need cannot become a collection contract, or "" when it can.
static func unsupported_reason(need: String) -> String:
	if SUPPORTED_NEEDS.has(need):
		return ""
	return str(REJECTED_NEEDS.get(need, "need_not_in_supported_catalogue"))


## Build a contract, or report the exact missing binding.
##
## `bindings` carries what the world actually provides: source_station_id,
## source_supplies (the station really stocks or issues this item through its
## existing pickup/store path), destination_station_id, destination_registered,
## recipient_id, recipient_is_generated_local, item_id_or_special_name,
## store_catalogue and action.
static func compile(source: Dictionary, bindings: Dictionary) -> Dictionary:
	var need := str(source.get("need", ""))
	var reason := unsupported_reason(need)
	if not reason.is_empty():
		return _withheld(reason, "need")
	var rule: Dictionary = SUPPORTED_NEEDS[need]
	var action := str(bindings.get("action", ""))
	if action not in ACTIONS:
		return _withheld("unsupported_action", "action")
	if action not in (rule["actions"] as Array):
		return _withheld("action_not_supported_for_need", "action")
	for field in ["campaign_id", "system_id", "faction_id", "desire_id", "cause_id"]:
		if str(source.get(field, "")).strip_edges().is_empty():
			return _withheld("missing_scope", field)
	var item := str(bindings.get("item_id_or_special_name", "")).strip_edges()
	if item.is_empty():
		return _withheld("no_bound_item", "item_id_or_special_name")
	var source_station := str(bindings.get("source_station_id", "")).strip_edges()
	if source_station.is_empty():
		return _withheld("no_source_station", "source_station_id")
	if not bool(bindings.get("source_supplies", false)):
		return _withheld("source_does_not_supply_item", "source_supplies")
	if action == ACTION_PURCHASE_DELIVERY and not bool(bindings.get("store_catalogue", false)):
		return _withheld("item_not_in_store_catalogue", "store_catalogue")
	var destination := str(bindings.get("destination_station_id", "")).strip_edges()
	if destination.is_empty():
		return _withheld("no_destination_station", "destination_station_id")
	if not bool(bindings.get("destination_registered", false)):
		return _withheld("destination_not_registered", "destination_registered")
	var recipient := str(bindings.get("recipient_id", "")).strip_edges()
	if recipient.is_empty():
		return _withheld("no_local_recipient", "recipient_id")
	if not bool(bindings.get("recipient_is_generated_local", false)):
		# A tutorial resident is never substituted for a generated local contact.
		return _withheld("recipient_is_not_a_generated_local_contact", "recipient_is_generated_local")
	if action == ACTION_PICKUP and str(bindings.get("source_contact_id", "")).strip_edges().is_empty():
		return _withheld("no_source_contact", "source_contact_id")
	var quantity := maxi(1, int(bindings.get("quantity", rule["quantity"])))
	var contract := {
		"version": CONTRACT_VERSION,
		"id": _contract_id(source, action, item),
		"campaign_id": str(source["campaign_id"]),
		"system_id": str(source["system_id"]),
		"faction_id": str(source["faction_id"]),
		"desire_id": str(source["desire_id"]),
		"cause_id": str(source["cause_id"]),
		"need_binding_id": str(source.get("obstacle_binding_id", "")),
		"item_id_or_special_name": item,
		"quantity": quantity,
		"source_station_id": source_station,
		# Only a pickup collects from a NAMED person at the origin; the other two
		# verbs leave this empty rather than inventing a contact.
		"source_contact_id": str(bindings.get("source_contact_id", "")) if action == ACTION_PICKUP else "",
		"destination_station_id": destination,
		"recipient_id": recipient,
		"action": action,
		"completion_kind": COMPLETION_ITEM_DELIVERED,
	}
	var result := validate(contract)
	if not result.is_valid():
		return _withheld(str(result.errors[0].get("code", "invalid_collection_contract")),
			str(result.errors[0].get("field", "")))
	return {"ok": true, "contract": contract}


static func objective_type_for(contract: Dictionary) -> String:
	return str(OBJECTIVE_BY_ACTION.get(str(contract.get("action", "")), ""))


static func validate(value: Dictionary) -> ValidationResult:
	var result := Validation.new()
	if value.is_empty():
		result.add_error("empty_collection_contract", "Collection contract is empty.")
		return result
	if int(value.get("version", 0)) != CONTRACT_VERSION:
		result.add_error("unsupported_collection_contract_version",
			"Collection contract version is not supported.", "version")
	for field in ["id", "campaign_id", "system_id", "faction_id", "desire_id", "cause_id",
			"item_id_or_special_name", "source_station_id", "destination_station_id", "recipient_id"]:
		if str(value.get(field, "")).strip_edges().is_empty():
			result.add_error("missing_collection_binding",
				"Collection contract field is required: %s" % field, field)
	if str(value.get("action", "")) not in ACTIONS:
		result.add_error("unsupported_collection_action", "Unsupported collection action.", "action")
	if str(value.get("completion_kind", "")) != COMPLETION_ITEM_DELIVERED:
		result.add_error("unsupported_collection_completion",
			"A collection contract proves only that its item was delivered.", "completion_kind")
	var quantity: Variant = value.get("quantity", 0)
	if not (quantity is int or quantity is float) or int(quantity) < 1:
		result.add_error("invalid_collection_quantity",
			"Collection quantity must be a positive integer.", "quantity")
	return result


## Stable and independent of list order or wall clock, so reopening a posting
## resolves to the same collection.
static func _contract_id(source: Dictionary, action: String, item: String) -> String:
	var key := "%s|%s|%s|%s|%s|%s" % [source.get("campaign_id", ""), source.get("system_id", ""),
		source.get("faction_id", ""), source.get("desire_id", ""), action, item]
	return "collection.%s" % key.sha256_text().substr(0, 24)


static func _withheld(reason: String, missing_binding: String) -> Dictionary:
	return {"ok": false, "reason": reason, "missing_binding": missing_binding}
