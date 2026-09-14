extends RefCounted

## Compatibility edges, not whole quest templates. A goal selects a supported
## need; transport obstacles and commercial resources vary independently within
## their compatible sets. These records are generated world facts, not proof of
## live inventory, bank balances or completed campaign effects.
const VERSION := 2

## Keys are stable goal indices in GeneratedFactionDesire.GOALS. The explanation
## records the missing causal link rather than asking a writer to invent it.
const GOAL_NEEDS := {
	0: {
		"route permits": "The lane authority requires those permits before its freight can use the route again.",
		"convoy escort guarantees": "Its freight insurer requires an escort guarantee before covering the reopened route.",
		"replacement assemblies": "The freight haulers need these assemblies before they can return to the lane.",
		"fuel it can afford": "Its next freight run cannot depart until it has fuel within the run's budget.",
	},
	1: {
		"filed claim evidence": "The claim register needs the original evidence to review the disputed entry.",
		"a witness who will go on record": "A recorded account of the salvage operation can challenge the disputed claim.",
		"sealed manifests from the last shipment": "The shipment manifests record where the disputed salvage came from.",
	},
	2: {
		"a countersigned dock purchase agreement": "The lease transfer requires the current holder's countersignature.",
		"a certified lease valuation": "The lender needs a certified valuation before financing the lease buyout.",
	},
	3: {
		"filed claim evidence": "The impound office needs the ownership evidence to review the detention.",
		"a witness who will go on record": "The impound appeal needs a recorded account of the seizure.",
		"route permits": "The impound office is holding the hulls until their transit permits are produced.",
	},
	4: {
		"survey data from a drift it cannot reach": "The filing is missing observations from that drift.",
		"a clean ore assay": "The survey filing needs a certified assay of the sampled ore.",
		"replacement assemblies": "Its survey instrument needs these assemblies before it can finish the observations.",
	},
	5: {
		"medical stock for its own crew": "The replacement crew needs medical supplies before it can sign on for active duty.",
		"signed recruitment papers": "The new crew's signed papers are needed to bring its roster back to minimum.",
	},
	6: {
		"sealed manifests from the last shipment": "The sealed originals can be compared with the rival's disputed manifest.",
		"a witness who will go on record": "A witness to the loading can challenge the rival's cargo account.",
		"filed claim evidence": "The filed cargo evidence can be checked against the rival's manifest.",
	},
	7: {
		"food stock for the quarter": "The missing rations cover the shortfall in its food stores.",
		"convoy escort guarantees": "Its food supplier requires an escort guarantee before dispatching the ration convoy.",
	},
	8: {
		"a countersigned supply agreement": "The replacement supplier needs a signed agreement before reserving stock.",
		"convoy escort guarantees": "The replacement supplier requires an escort guarantee before opening the supply route.",
	},
	9: {
		"sealed manifests from the last shipment": "The missing shipment records show which deliveries count against the debt.",
		"filed claim evidence": "The filed receipts establish which part of the old debt has been paid.",
	},
	10: {
		"replacement assemblies": "Its bid depends on restoring equipment needed to fulfil the contract.",
		"a clean ore assay": "The buyer needs an assay showing its ore meets the contract specification.",
		"convoy escort guarantees": "The buyer requires guaranteed transport protection before reconsidering its bid.",
	},
	11: {
		"route permits": "The permits record the toll exemption it is asking the authority to honour.",
		"filed claim evidence": "The filed toll receipts support its challenge to the charges.",
		"a witness who will go on record": "A recorded account of the collections supports its toll complaint.",
	},
}

## Each obstacle has its own event and a change that can address THAT obstacle.
## All are transport/document dispatch impediments, compatible with every need
## above. Avoid destroyed evidence, frozen payment accounts and invented enemies.
const BLOCKERS := [
	{
		"id": "carrier_cancelled",
		"obstacle": "its contracted carrier has cancelled the collection",
		"triggering_event": "the carrier entering liquidation before dispatch",
		"change_condition": "a replacement carrier taking the collection",
	},
	{
		"id": "cargo_cradle",
		"obstacle": "its transport cradle cannot safely secure the shipment",
		"triggering_event": "a failed load test on its transport cradle",
		"change_condition": "the cradle being recertified or a carrier providing suitable restraints",
	},
	{
		"id": "dispatch_backlog",
		"obstacle": "its dispatch team has no capacity for another collection",
		"triggering_event": "a dispatch contractor withdrawing from its booked runs",
		"change_condition": "another carrier taking the collection",
	},
	{
		"id": "handling_damage",
		"obstacle": "its own cargo handling equipment is awaiting repair",
		"triggering_event": "a loader failure during the previous unloading",
		"change_condition": "the loader repair or an outside carrier handling the cargo",
	},
	{
		"id": "collection_licence",
		"obstacle": "its collection licence is awaiting renewal",
		"triggering_event": "a licence renewal being returned for a missing signature",
		"change_condition": "the renewal clearing or a licensed carrier collecting for it",
	},
	{
		"id": "crew_reassigned",
		"obstacle": "its collection crew is covering an existing service commitment",
		"triggering_event": "a service contract extension keeping its collection crew occupied",
		"change_condition": "that commitment ending or another crew taking the collection",
	},
]

## Payment and holdings describe the same business. No asserted bank amount.
const RESOURCES := [
	{"id": "warehouse", "controls": "a bonded storage lease", "payment_source": "the retainer its storage contract pays"},
	{"id": "repair", "controls": "a licensed repair workshop", "payment_source": "receipts from completed repair work"},
	{"id": "berths", "controls": "a group of sublet cargo berths", "payment_source": "the berth fees its tenants pay"},
	{"id": "records", "controls": "a licensed shipping records service", "payment_source": "fees from completed records searches"},
]

const EXTRA_ITEMS := {
	"a countersigned dock purchase agreement": ["Countersigned Dock Agreement", "Sealed Lease Transfer"],
	"a certified lease valuation": ["Certified Lease Valuation", "Bonded Dock Appraisal"],
	"signed recruitment papers": ["Signed Crew Contracts", "Sealed Recruitment Packet"],
	"food stock for the quarter": ["Packed Ration Crate", "Preserved Food Shipment"],
	"a countersigned supply agreement": ["Countersigned Supply Agreement", "Sealed Supplier Contract"],
}

const EXTRA_INTENTS := {
	"a countersigned dock purchase agreement": ["pickup", "delivery"],
	"a certified lease valuation": ["pickup", "delivery"],
	"signed recruitment papers": ["pickup", "delivery"],
	"food stock for the quarter": ["purchase", "delivery"],
	"a countersigned supply agreement": ["pickup", "delivery"],
}

static func need_reason(goal_index: int, need: String) -> String:
	return str(GOAL_NEEDS.get(goal_index, {}).get(need, ""))
