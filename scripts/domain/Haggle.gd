extends RefCounted

## Pushing an agent for more money is a gamble (playtest 2026-10-06 finding
## 5, Abe). An offer's "push" answer (a big payout raise, no advance) works
## about 60% of the time, better with good standing, worse with bad; the rest
## of the time the agent cuts the pay instead and says so, cockily. The
## reputation hit still lands; the extra danger doesn't (nobody's escalating
## for a pilot they just short-changed).
##
## Lines are hand-written (for Abe's review), never the model.

const BASE_ODDS := 0.6
## Odds per point of standing (-100..100): +/-0.25 at the extremes.
const ODDS_PER_STANDING := 0.0025
const MIN_ODDS := 0.3
const MAX_ODDS := 0.85
## A push: the answer raises the pay at least this much and pays nothing up front.
const PUSH_MULTIPLIER := 1.35
const CUT_MULTIPLIER := 0.8

const AGENT_LINES := [
	"The pay's less now. Take the job or don't. Don't waste my time.",
	"You wanted more. Now it's less. Still interested?",
	"Pushing me was a mistake. The rate just went down.",
	"I've got ten pilots who'd take the old rate. You get the new one.",
	"Wrong day to haggle. Pay's cut. Take it or leave it.",
]
const KAELEN_LINES := [
	"Cute, Shiny. The pay just went down. Want it or not?",
	"You haggle like you fly, Shiny. Less money now. Take it or walk.",
	"Nice try, Shiny. The new number's lower. Don't make me lower it again.",
	"I don't haggle with my own pilots, Shiny. Pay's cut. Clock's ticking.",
]


static func is_push(choice: Dictionary) -> bool:
	var c: Dictionary = choice.get("consequence", {}) if choice.get("consequence", {}) is Dictionary else {}
	return float(c.get("reward_credits_multiplier", 1.0)) >= PUSH_MULTIPLIER and int(c.get("credits_immediate", 0)) <= 0


static func odds(standing: float) -> float:
	return clampf(BASE_ODDS + standing * ODDS_PER_STANDING, MIN_ODDS, MAX_ODDS)


## The choice as it really plays out. `roll` in [0, 1): below the odds the
## push works (the choice is returned as is); otherwise the pay is cut and the
## reply replaced. `kaelen` picks her lines. Not a push: returned unchanged.
static func resolve(choice: Dictionary, standing: float, roll: float, kaelen: bool) -> Dictionary:
	if not is_push(choice) or roll < odds(standing):
		return choice
	var out := choice.duplicate(true)
	var c: Dictionary = out["consequence"]
	c["reward_credits_multiplier"] = CUT_MULTIPLIER
	c["combat_multiplier"] = 1.0
	var lines: Array = KAELEN_LINES if kaelen else AGENT_LINES
	c["dialogue_response"] = str(lines[int(roll * 1000.0) % lines.size()])
	out["haggle_backfired"] = true
	return out
