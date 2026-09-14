# Cause coverage audit — which generated desires can actually be played

**Scope.** A bounded compatibility audit of `GeneratedDesireConstraints`
(version 2) against the verbs, cargo items, recipients, sites and effects that
exist in code today. This adds no new needs, enemies, hazards, recipes or
dialogue branches. Its purpose is to say, per edge, whether a generated desire
can be turned into playable work **with existing capabilities**, and to record
the exact reason when it cannot.

A generated textual success condition is not proof of an implemented effect.
An edge is listed **supported** only when the action actually supplies the
stated need, and the location, resource and recipient checks pass.

## What the game can actually do

| Capability | What it establishes |
|---|---|
| `INVESTIGATE_SIGNAL` / `survey_discrepancy` | Two beacon readings compared; a certification or an unverified report |
| `INVESTIGATE_SIGNAL` / `competing_claims` | A recorder scanned and preserved, handed to its verified owner |
| `DELIVER_ORE` | A quantity of raw ore moved to a station |
| `DELIVERY_COURIER` / `PICKUP_SPECIAL` | One **named** item moved from an origin to an accepting recipient |
| `PURCHASE_DELIVERY` | A **store-catalogue** item bought and delivered |
| `KILL_SHIPS`, `RECOVER_COMBAT_DROP`, `COMMS_REVERSAL` | Combat outcomes; not a collection of documents or readings |

Store catalogue (29 items) contains consumables, ammo, ship parts, novelties and
two trade goods. It contains **no** medical stock, rations, permits, manifests,
assay certificates or recruitment papers. Named-item delivery does not require a
store entry; `PURCHASE_DELIVERY` does.

## Supported edges

| Need | Verb | Effect actually recorded | Runtime eligible now |
|---|---|---|---|
| `survey data from a drift it cannot reach` | `survey_discrepancy` | `verified_survey_evidence_submitted` (correct certification, both sites scanned) | **Yes** — with `dispatch_backlog` |
| `filed claim evidence` (goal: clear its name on a salvage claim, ≥2 local claimants) | `competing_claims` | `recorder_preserved_and_delivered` | **Yes** — with `dispatch_backlog` |
| `a countersigned dock purchase agreement` | courier / pickup | document delivered | Delivery-shaped; needs origin + accepting local contact bound |
| `a certified lease valuation` | courier / pickup | document delivered | Delivery-shaped; needs origin + accepting local contact bound |
| `signed recruitment papers` | courier / pickup | document delivered | Delivery-shaped; needs origin + accepting local contact bound |
| `a countersigned supply agreement` | courier / pickup | document delivered | Delivery-shaped; needs origin + accepting local contact bound |
| `food stock for the quarter` | courier / pickup (named crate) | crate delivered | Delivery-shaped; **not** `PURCHASE_DELIVERY` — no catalogue ration item |
| `sealed manifests from the last shipment` | courier / pickup | document delivered | Delivery-shaped; needs origin + accepting local contact bound |
| `medical stock for its own crew` | courier / pickup (named crate) | crate delivered | Delivery-shaped; **not** `PURCHASE_DELIVERY` — no catalogue medical item |
| `replacement assemblies` | courier / pickup, or `PURCHASE_DELIVERY` of a `ship_part` | part delivered | Delivery-shaped; the catalogue does carry ship parts |

**The delivery caveat, and it is the whole point.** Delivering a countersigned
agreement records *that the document arrived*. It does **not** complete a lease
transfer, clear an impound, settle a debt, win a contract bid, or restore a
roster. The desire moves to `progressed`, never to `satisfied`, because no typed
predicate proves the legal or commercial outcome. Anything that claims otherwise
is a reskin with a better sentence on it.

## Rejected edges, with the specific missing capability

| Need | Why it is not playable today |
|---|---|
| `a clean ore assay` | **No assay mechanic.** Delivering raw ore moves ore; it does not certify composition against a specification. This is the blocker keeping the `supply` pressure track runtime-ineligible. Do not add an assay to activate it. |
| `route permits` | No permit issuance, and nothing reopens a route. A permit *document* can be carried, but the need is the authority honouring it. |
| `convoy escort guarantees` | No escort capability. A guarantee is an underwriting commitment, not a deliverable object. |
| `a witness who will go on record` | No NPC testimony, recruitment or persuasion mechanic. A person is not cargo. |
| `fuel it can afford` | No fuel commodity the player can buy on a faction's behalf. `fuel_booster` is a player consumable, not bulk freight. |

## Obstacle bindings

Investigation eligibility remains restricted to `dispatch_backlog`. That blocker
says the faction cannot *collect* something — which is exactly what commissioning
an independent pilot to go and gather readings or evidence addresses.

The other five blockers (`carrier_cancelled`, `cargo_cradle`, `handling_damage`,
`collection_licence`, `crew_reassigned`) all describe **moving existing cargo**.
None of them establishes a need for fresh scans, so none of them justifies an
investigation. They are compatible with delivery-shaped work, where the change
condition ("another carrier taking the collection") is literally what the player
does. Preserve `dispatch_backlog`-only investigation eligibility until another
edge has that proof.

## Consequences for the pressure tracks

| Track | Status | Reason |
|---|---|---|
| `signals` | Runtime eligible | `survey_discrepancy` is implemented and causally bound |
| `claims` | Runtime eligible | `competing_claims` is implemented and causally bound |
| `supply` | **Runtime ineligible** (`no_validated_ore_consumption_cause`) | The only ore-shaped need is an assay, and no assay exists |

This restricted catalogue **cannot promise permanent unlimited relief work**. Two
recipes over two eligible kinds will exhaust their fresh causes in a given system;
when that happens the correct behaviour is to show the track without an actionable
posting and log it, not to mint a reskin of a cause already used.

## Rules this audit sets for implementation

1. Expand runtime eligibility only for an edge listed **supported**, and only
   after its location, resource and recipient checks pass at publication time.
2. Bind the real item, origin, destination and accepting local contact for any
   delivery edge, and record delivery of *that item* as the consequence.
3. Never claim a delivery completed a legal appeal, ownership transfer, assay or
   route reopening.
4. Keep the existing docking-recipient repair and destination checks for
   generated outposts.
5. When an edge cannot be implemented with existing capabilities, leave it
   unavailable with a diagnostic naming the missing capability.
