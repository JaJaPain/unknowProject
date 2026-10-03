extends RefCounted

## The gate Kaelen can't buy open (core loop step 11c, Abe 2026-10-02).
##
## DIRECTOR-ONLY (never in a prompt, never in player-visible text): Kaelen is
## desperate for money to get these gates opened for the Captain. This one
## gate her credits can't open, so she needs leverage, a big bargaining chip.
## She never says so.
##
## What the player sees: once per campaign, a few jumps out, Kaelen has one
## job and only that job (a sealed ledger to recover) until it's done. She
## never says what it's for. Afterwards the gate's route is for sale from her
## as usual, at her usual price, and when she sells it she half-hints the
## Captain had a hand in it.
##
## State in StoryManager.story_state["kaelen_locked_gate"]:
##   {gate_id, stage: "needed" | "done" | "sold"}

const STATE_KEY := "kaelen_locked_gate"
## Not before the player is this many jumps out.
const MIN_DEPTH := 3
const QUEST_FLAG := "kaelen_locked_gate"

## Her handoff when the job is first offered, and when it's offered again.
const FIRST_HANDOFF := "I've only got the one job right now, Shiny. Hear me out."
## When she has to offer it again (Abe, 2026-10-02: she may offer it several
## times). Rotated, never the same twice running.
const REPEAT_HANDOFFS := [
	"Same job's still open. It's the only one I've got.",
	"Still the ledger, Shiny. Nothing else on my books until it's done.",
	"Back again? Good. The ledger's still out there.",
	"I'm not holding out on you. That ledger's the only work I've got.",
	"Every other client can wait. This one can't.",
	"You know what I'm going to say. The ledger.",
]
## Her repeat briefing: shorter than the first, the same job.
const REPEAT_BRIEFINGS := [
	"Two Reaver raiders, one sealed ledger. Bring it to me, not to its owners. Don't open it. Pays fair.",
	"The Reavers still have that courier's ledger. I still want it, sealed. The pay hasn't changed.",
	"It hasn't gone anywhere, Shiny. Two Reaver ships, a sealed ledger, my hands, not theirs. Same pay.",
]
const FIRST_BRIEFING := "Got something quiet for you, Shiny. A pair of Reaver raiders picked off a courier out here and kept what he was carrying: a sealed ledger. The people it belongs to would be very grateful to whoever brings it home. Bring it to me, not to them. Don't open it. Pays fair."
const HINTS := [
	"Funny thing. That lane's been shut tight for months, and it opened right after you brought me that ledger. Coincidence, I'm sure. Price is the same.",
	"Don't look at me like that. Some doors only open for the right favour. Anyway. Usual rate.",
	"You'd be surprised what a little ledger can open. Not that I'd know. That'll be the usual fee.",
]


static func state(story_state: Dictionary) -> Dictionary:
	var s = story_state.get(STATE_KEY)
	return s if s is Dictionary else {}


static func stage(story_state: Dictionary) -> String:
	return str(state(story_state).get("stage", ""))


## Once per campaign: lock `gate_id` if nothing is locked yet, the tutorial is
## done and the ship is deep enough. True if it locked.
static func maybe_lock(story_state: Dictionary, gate_id: String, depth: int) -> bool:
	if gate_id.is_empty() or not stage(story_state).is_empty() or depth < MIN_DEPTH:
		return false
	if not bool(story_state.get("first_contract_handed_in", false)):
		return false
	story_state[STATE_KEY] = {"gate_id": gate_id, "stage": "needed", "times_offered": 0}
	return true


## While her job is waiting, she has no other work to offer.
static func blocks_other_offers(story_state: Dictionary) -> bool:
	return stage(story_state) == "needed"


## The gate she can't sell yet.
static func is_withheld(story_state: Dictionary, gate_id: String) -> bool:
	return stage(story_state) == "needed" and str(state(story_state).get("gate_id", "")) == gate_id


## The job (authored; a Reaver recovery, like the board's). `handoff` comes
## back so the caller can use it as her intro.
static func offer(story_state: Dictionary) -> Dictionary:
	var s := state(story_state)
	var times := int(s.get("times_offered", 0))
	var handoff := FIRST_HANDOFF
	var dialogue := FIRST_BRIEFING
	if times > 0:
		handoff = str(REPEAT_HANDOFFS[(times - 1) % REPEAT_HANDOFFS.size()])
		dialogue = str(REPEAT_BRIEFINGS[(times - 1) % REPEAT_BRIEFINGS.size()])
	s["times_offered"] = times + 1
	story_state[STATE_KEY] = s
	return {
		"title": "A Ledger Worth Owning",
		"faction": "neutral",
		"agent_name": "Broker Kaelen",
		"agent_role": "Neutral Fixer & Profit Broker",
		"handoff": handoff,
		QUEST_FLAG: true,
		"dialogue": dialogue,
		"objective": {
			"type": "RECOVER_COMBAT_DROP",
			"target_faction": "reavers",
			"count_required": 2,
			"drop_chance": 1.0,
			"item_name": "sealed ledger",
			"turn_in_location": "main station",
			"reward_credits": 260,
		},
		"choices": [
			{
				"text": "A ledger. Sure, I'll get it.",
				"consequence": {"credits_immediate": 0, "reputation_change": {}, "combat_multiplier": 1.0, "reward_credits_multiplier": 1.0,
					"dialogue_response": "Good. Quietly, Shiny. And it stays sealed."},
			},
			{
				"text": "Who does it belong to?",
				"consequence": {"credits_immediate": 0, "reputation_change": {}, "combat_multiplier": 1.0, "reward_credits_multiplier": 1.0,
					"dialogue_response": "Someone who'll owe me. That's all you need to know, Shiny. Pay's the same either way."},
			},
		],
	}


## Her job handed in: the gate's route can be sold now.
static func on_quest_completed(story_state: Dictionary, quest_data: Dictionary) -> bool:
	if not bool(quest_data.get(QUEST_FLAG, false)) or stage(story_state) != "needed":
		return false
	var s := state(story_state)
	s["stage"] = "done"
	story_state[STATE_KEY] = s
	return true


## Selling the once-withheld gate: her half-hint, once. "" for any other gate.
static func on_gate_sold(story_state: Dictionary, gate_id: String, roll: int) -> String:
	var s := state(story_state)
	if str(s.get("stage", "")) != "done" or str(s.get("gate_id", "")) != gate_id:
		return ""
	s["stage"] = "sold"
	story_state[STATE_KEY] = s
	return str(HINTS[posmod(roll, HINTS.size())])
