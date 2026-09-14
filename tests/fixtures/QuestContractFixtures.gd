class_name QuestContractFixtures
extends RefCounted

## The three vertical examples the plan asks phases A-C to prove end to end:
##
##   1. courier_one_path   -- a straightforward job with ONE completion path.
##                            It must pass every gate WITHOUT growing a branch.
##   2. investigation_one_choice
##                         -- one genuinely justified decision, both options
##                            supported, motivated and distinct.
##   3. investigation_unjustified_option
##                         -- the same investigation with a second option that
##                            has no grounded motive. The extra option must be
##                            removed and the quest must survive as one path.
##
## These are hand-written development fixtures, not generated output, and not
## evidence about real model prose.

const SYSTEM_ID := "system.tallow_reach"
const CAMPAIGN_ID := "campaign.fixture.a1"


## A shared world snapshot that makes the valid fixtures valid. Tests mutate a
## copy of this to prove each individual check actually bites.
static func world() -> Dictionary:
	return {
		"system_id": SYSTEM_ID,
		"reachable_system_ids": [SYSTEM_ID, "system.corvid_gap"],
		"station_ids": ["station.tallow_primary", "outpost.blacklist_yard"],
		"residents": [
			{
				"id": "npc.marn_dable",
				"name": "Marn Dable",
				"role": "quartermaster",
				"station_id": "outpost.blacklist_yard",
			},
			{
				"id": "npc.ysolde_kerr",
				"name": "Ysolde Kerr",
				"role": "clerk",
				"station_id": "station.tallow_primary",
			},
		],
		"capabilities": [
			"capability.cargo_transport",
			"capability.site_scan",
		],
		"requester_funds": 4000,
		"player_credits": 900,
		"current_time_minutes": 120,
	}


## 1. Courier. One path. No branches, no risk facts, no deadline. This is a
## CORRECT quest, and every gate has to agree that it is.
static func courier_one_path() -> Dictionary:
	return {
		"id": "quest.fixture.courier_one_path",
		"revision": 1,
		"campaign_id": CAMPAIGN_ID,
		"system_id": SYSTEM_ID,
		"requester_id": "faction.generated.a1.f0",
		"beneficiary_id": "faction.generated.a1.f0",
		"desire_id": "desire.a1.f0",
		"triggering_event_id": "event.a1.pump_seizure",
		"facts": {
			"fact.pump_seized": {
				"text": "The yard's number two transfer pump seized four days ago.",
				"visibility": "public",
				"kind": "problem",
			},
			"fact.part_on_station": {
				"text": "The only spare coupling in the system is sitting in primary station bond.",
				"visibility": "public",
				"kind": "problem",
			},
			"fact.marn_receives": {
				"text": "Marn Dable signs for yard parts and can fit the coupling himself.",
				"visibility": "public",
				"kind": "recipient",
			},
			"fact.no_hauler": {
				"text": "The yard's own hauler is down to one working thruster and will not make the run.",
				"visibility": "public",
				"kind": "delegation",
			},
			"fact.salvage_income": {
				"text": "The yard is paid per hull it strips, and pays out of that account.",
				"visibility": "public",
				"kind": "reward_source",
			},
		},
		"problem_fact_ids": ["fact.pump_seized", "fact.part_on_station"],
		"public_fact_ids": [
			"fact.pump_seized",
			"fact.part_on_station",
			"fact.marn_receives",
			"fact.no_hauler",
			"fact.salvage_income",
		],
		"private_fact_ids": [],
		"why_this_action_fact_ids": ["fact.part_on_station", "fact.marn_receives"],
		"why_player_fact_ids": ["fact.no_hauler"],
		"urgency_fact_ids": [],
		"reward_source_fact_ids": ["fact.salvage_income"],
		"objective_binding": {
			"type": "DELIVERY_COURIER",
			"capability_id": "capability.cargo_transport",
			"item_id": "item.transfer_coupling",
			"item_name": "Transfer Coupling",
			"quantity": 1,
			"location_system_id": SYSTEM_ID,
			"destination_station_id": "outpost.blacklist_yard",
			"reward_credits": 280,
			"deadline_minutes": 0,
		},
		"recipient_binding": {
			"id": "npc.marn_dable",
			"name": "Marn Dable",
			"role": "quartermaster",
			"station_id": "outpost.blacklist_yard",
			"protected": false,
		},
		"completion_effect_ids": ["desire_progress.desire.a1.f0"],
		"failure_effect_ids": [],
		"branch_contracts": [],
	}


## 2. Investigation with ONE justified decision. Both options do something the
## game supports, both have a motive a reasonable player can see, and they end
## in different recorded results -- handing the log to the claims office or
## keeping it. That is what earns a second button.
static func investigation_one_choice() -> Dictionary:
	return {
		"id": "quest.fixture.investigation_one_choice",
		"revision": 1,
		"campaign_id": CAMPAIGN_ID,
		"system_id": SYSTEM_ID,
		"requester_id": "faction.generated.a1.f1",
		"beneficiary_id": "faction.generated.a1.f1",
		"desire_id": "desire.a1.f1",
		"triggering_event_id": "event.a1.convoy_loss",
		"facts": {
			"fact.convoy_lost": {
				"text": "A four-hull convoy stopped transmitting inside the Corvid drift two weeks ago.",
				"visibility": "public",
				"kind": "problem",
			},
			"fact.claim_denied": {
				"text": "The claims office will not pay out without a recovered flight log.",
				"visibility": "public",
				"kind": "problem",
			},
			"fact.log_survives": {
				"text": "Flight logs sit in a shielded block that survives most hull losses.",
				"visibility": "public",
				"kind": "method",
			},
			"fact.no_scanner": {
				"text": "Nobody local still owns a survey rig that can read a drifting block.",
				"visibility": "public",
				"kind": "delegation",
			},
			"fact.escort_bond": {
				"text": "The escort bond pays the fee whether or not the claim clears.",
				"visibility": "public",
				"kind": "reward_source",
			},
			"fact.log_names_them": {
				"text": "If the log shows their own routing error, the claim dies and the bond is called.",
				"visibility": "private",
				"kind": "motive",
			},
			"fact.office_pays_finders": {
				"text": "The claims office pays finders directly for an original log.",
				"visibility": "public",
				"kind": "branch_motive",
			},
		},
		"problem_fact_ids": ["fact.convoy_lost", "fact.claim_denied"],
		"public_fact_ids": [
			"fact.convoy_lost",
			"fact.claim_denied",
			"fact.log_survives",
			"fact.no_scanner",
			"fact.escort_bond",
			"fact.office_pays_finders",
		],
		"private_fact_ids": ["fact.log_names_them"],
		"why_this_action_fact_ids": ["fact.claim_denied", "fact.log_survives"],
		"why_player_fact_ids": ["fact.no_scanner"],
		"urgency_fact_ids": [],
		"reward_source_fact_ids": ["fact.escort_bond"],
		"objective_binding": {
			"type": "INVESTIGATE_SIGNAL",
			"capability_id": "capability.site_scan",
			"site_id": "site.corvid_drift_wreck",
			"quantity": 1,
			"location_system_id": SYSTEM_ID,
			"reward_credits": 520,
			"deadline_minutes": 0,
		},
		"recipient_binding": {},
		"completion_effect_ids": [
			"evidence.flight_log_recovered",
			"desire_progress.desire.a1.f1",
		],
		"failure_effect_ids": ["desire_setback.desire.a1.f1"],
		"branch_contracts": [
			{
				"id": "branch.return_log",
				"action_id": "action.deliver_evidence.requester",
				"eligibility_predicates": ["evidence.flight_log_recovered"],
				"motivation_fact_ids": ["fact.escort_bond"],
				"public_information_fact_ids": ["fact.claim_denied"],
				"costs": {},
				"effect_ids": ["desire_progress.desire.a1.f1", "relationship.requester.up"],
				"outcome_id": "outcome.log_returned",
				"distinct_from_branch_ids": ["branch.sell_log"],
			},
			{
				"id": "branch.sell_log",
				"action_id": "action.deliver_evidence.claims_office",
				"eligibility_predicates": ["evidence.flight_log_recovered"],
				"motivation_fact_ids": ["fact.office_pays_finders"],
				"public_information_fact_ids": ["fact.office_pays_finders"],
				"costs": {"relationship_requester": -2},
				"effect_ids": ["desire_setback.desire.a1.f1", "reward.finder_fee"],
				"outcome_id": "outcome.log_sold",
				"distinct_from_branch_ids": ["branch.return_log"],
			},
		],
	}


## 3. The same investigation plus a third option that should NOT exist. It is
## the shape the plan warns about: a menu filler. It names no motive the player
## could act on, and its recorded result is identical to branch.return_log.
## Correct behavior is to drop it -- not to invent a danger that justifies it.
static func investigation_unjustified_option() -> Dictionary:
	var contract := investigation_one_choice()
	contract["id"] = "quest.fixture.investigation_unjustified_option"
	var branches: Array = contract["branch_contracts"]
	branches.append({
		"id": "branch.hand_over_quietly",
		"action_id": "action.deliver_evidence.requester",
		"eligibility_predicates": ["evidence.flight_log_recovered"],
		"motivation_fact_ids": [],
		"public_information_fact_ids": [],
		"costs": {},
		"effect_ids": ["desire_progress.desire.a1.f1", "relationship.requester.up"],
		"outcome_id": "outcome.log_returned",
		"distinct_from_branch_ids": [],
	})
	contract["branch_contracts"] = branches
	return contract


## An objective the game cannot execute, promising an effect it cannot enact,
## with a deadline nobody explains. Used to prove the gate actually rejects.
static func unsupported_contract() -> Dictionary:
	var contract := courier_one_path()
	contract["id"] = "quest.fixture.unsupported"
	contract["objective_binding"]["type"] = "SABOTAGE_STATION"
	contract["objective_binding"]["deadline_minutes"] = 90
	contract["completion_effect_ids"] = ["station_destroyed.blacklist_yard"]
	return contract


## A delivery aimed at someone who cannot receive cargo, in a system the player
## cannot reach, paid from nowhere.
static func impossible_delivery_contract() -> Dictionary:
	var contract := courier_one_path()
	contract["id"] = "quest.fixture.impossible_delivery"
	contract["objective_binding"]["location_system_id"] = "system.never_generated"
	contract["reward_source_fact_ids"] = []
	contract["recipient_binding"] = {
		"id": "npc.lounge_drinker",
		"name": "A Drinker",
		"role": "lounge_regular",
		"station_id": "station.does_not_exist",
		"protected": false,
	}
	return contract


## A contract that tries to route cargo to a protected fixed-cast character.
static func protected_recipient_contract() -> Dictionary:
	var contract := courier_one_path()
	contract["id"] = "quest.fixture.protected_recipient"
	contract["recipient_binding"] = {
		"id": "npc.kaelen",
		"name": "Kaelen",
		"role": "agent",
		"station_id": "outpost.blacklist_yard",
		"protected": true,
	}
	return contract


## A contract that lists its own secret as public disclosure.
static func leaking_contract() -> Dictionary:
	var contract := investigation_one_choice()
	contract["id"] = "quest.fixture.leaking"
	var public_ids: Array = contract["public_fact_ids"]
	public_ids.append("fact.log_names_them")
	contract["public_fact_ids"] = public_ids
	return contract
