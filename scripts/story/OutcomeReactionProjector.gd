class_name OutcomeReactionProjector
extends RefCounted

## Projects a TYPED P2/P3 outcome into the few facts dialogue is allowed to use
## (plan P4).
##
## PURE: an outcome dictionary in, facts out. No nodes, no autoloads, no model.
##
## Two problems this exists to solve.
##
## 1. Today world effects are inferred from KEYWORDS in generated text, which
##    means the world reacts to what a model happened to say rather than to what
##    actually occurred. Here the outcome tag is the truth and the text is
##    derived from it, never the reverse.
##
## 2. Not every outcome is PUBLIC. Some of what the player does is known only to
##    the player -- and in one case, not even to them. Projecting a private
##    outcome into dialogue would have an NPC casually reveal something nobody
##    should know, which is a spoiler delivered by accident.
##
## The plan allows ONE public local consequence per interaction. That cap is the
## point: the old packet builder copied every tension, hook and history entry
## into each bark, and that is most of the wasted inference.

const VERSION := 1

## Terminal outcome tags from InvestigateSignalCapability.
##
## `public` decides whether an NPC may reference this at all.
## `certainty` is what the SPEAKER can claim: "known" for things that visibly
## happened, "rumoured" for things that would travel as talk rather than fact.
const OUTCOME_PROJECTIONS: Dictionary = {
	"verified": {
		"public": true,
		"certainty": "known",
		"summary": "The find was verified and the paperwork holds up.",
	},
	"unverified": {
		"public": true,
		"certainty": "rumoured",
		"summary": "A find was reported without verification.",
	},
	"preserved": {
		"public": true,
		"certainty": "known",
		"summary": "The site was left intact rather than stripped.",
	},
	"liquidated": {
		"public": true,
		"certainty": "known",
		"summary": "The site was stripped and sold off.",
	},
	"copied": {
		"public": true,
		"certainty": "rumoured",
		"summary": "A reconstruction was made from the site's remains.",
	},
	"extracted": {
		"public": true,
		"certainty": "known",
		"summary": "The cache was pulled out whole.",
	},
	# PRIVATE, and deliberately so. A mistaken certification is one the player
	# got PAID for and was never corrected on -- they may not know they were
	# wrong. An NPC referencing it would tell them, and would tell them by
	# accident, in a bark, instead of through the story beat that should. This
	# is the single most important entry in this table.
	"mistaken": {
		"public": false,
		"certainty": "unknown",
		"summary": "",
	},
}

## The plan's cap: one public local consequence per interaction.
const MAX_CONSEQUENCES := 1
## Facts stay few on purpose; this is the whole point of narrowing.
const MAX_FACTS := 3


## Project one typed outcome. Returns:
##   {ok: bool, reason: String, facts: Array, consequence: Dictionary}
##
## `ok` false is NORMAL, not an error: a private or unknown outcome simply has
## nothing dialogue may say about it, and the caller should proceed without
## facts rather than substituting something.
static func project(outcome: Dictionary) -> Dictionary:
	if int(outcome.get("version", VERSION)) != VERSION:
		return _empty("unsupported_version")
	var tag := str(outcome.get("outcome_tag", "")).strip_edges()
	if tag.is_empty():
		return _empty("no_outcome_tag")
	if not OUTCOME_PROJECTIONS.has(tag):
		# An unrecognised tag is refused rather than guessed at. A new outcome
		# type must be classified public or private by a person, because getting
		# that wrong leaks story.
		return _empty("unclassified_outcome:%s" % tag)
	var projection: Dictionary = OUTCOME_PROJECTIONS[tag]
	if not bool(projection.get("public", false)):
		return _empty("private_outcome:%s" % tag)

	var owner := str(outcome.get("owner_id", "")).strip_edges()
	var facts: Array = []
	facts.append({
		"id": "outcome.%s" % tag,
		"text": str(projection.get("summary", "")),
		"revision": int(outcome.get("revision", 1)),
	})
	# The location, when the outcome had one. NPCs talk about places.
	var place := str(outcome.get("system_name", "")).strip_edges()
	if not place.is_empty():
		facts.append({
			"id": "outcome.place",
			"text": "It happened around %s." % place,
			"revision": int(outcome.get("revision", 1)),
		})
	# The payout band, never the exact figure. A specific number invites a model
	# to do arithmetic it cannot check, and an NPC who quotes the player's exact
	# credits reads as omniscient rather than informed.
	var band := payout_band(int(outcome.get("payout_credits", 0)))
	if not band.is_empty():
		facts.append({
			"id": "outcome.payout_band",
			"text": "The job paid %s." % band,
			"revision": int(outcome.get("revision", 1)),
		})
	if facts.size() > MAX_FACTS:
		facts = facts.slice(0, MAX_FACTS)

	return {
		"ok": true,
		"reason": "",
		"facts": facts,
		"consequence": {
			"owner_id": owner,
			"outcome_tag": tag,
			"certainty": str(projection.get("certainty", "rumoured")),
			"summary": str(projection.get("summary", "")),
		},
	}


## Coarse payout description. Bands rather than figures, so a speaker can be
## right without being precise.
static func payout_band(credits: int) -> String:
	if credits <= 0:
		return ""
	if credits < 100:
		return "badly"
	if credits < 300:
		return "the going rate"
	return "well"


## True when this outcome may be referenced in dialogue at all.
static func is_public(outcome_tag: String) -> bool:
	var projection: Dictionary = OUTCOME_PROJECTIONS.get(outcome_tag, {})
	return bool(projection.get("public", false))


static func _empty(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "facts": [], "consequence": {}}
