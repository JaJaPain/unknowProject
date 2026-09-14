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

const MEMORY_KINDS := {
	"verified": "verification_paid_off", "unverified": "verification_skipped",
	"preserved": "evidence_preserved", "liquidated": "value_taken",
	"copied": "evidence_preserved", "extracted": "risk_taken",
}


## Only committed, player-visible outcomes enter the persisted memory ledger.
static func remember_completed(ledger: Array, mission: Dictionary, activity_step: int = 0) -> Array:
	var result := normalize_memories(ledger)
	if str(mission.get("objective_type", "")) != "INVESTIGATE_SIGNAL" \
			or not mission.has("completed_time_minutes"):
		return result
	var investigation: Dictionary = mission.get("investigation", {}) if mission.get("investigation", {}) is Dictionary else {}
	var tag := str(investigation.get("outcome_tag", ""))
	var mission_id := str(mission.get("runtime_id", ""))
	var system_id := str(mission.get("system_id", ""))
	if not is_public(tag) or mission_id.is_empty() or system_id.is_empty() \
			or str(investigation.get("phase", "")) not in ["ready", "closed"]:
		return result
	for speaker in ["kaelen", "nova"]:
		var identity := "%s:%s" % [mission_id, speaker]
		var exists := false
		for entry in result:
			if str(entry.get("id", "")) == identity:
				exists = true
		if not exists:
			result.append({"id": identity, "outcome_id": mission_id, "mission_id": mission_id,
				"speaker_id": speaker, "system_id": system_id, "outcome_tag": tag,
				"public_fact_id": "outcome.%s" % tag, "kind": MEMORY_KINDS[tag],
				"at_minute": int(mission["completed_time_minutes"]), "at_step": activity_step,
				"callback_delivered": false})
	return normalize_memories(result)


static func normalize_memories(raw: Variant) -> Array:
	var result: Array = []
	if not raw is Array:
		return result
	for value in raw:
		if not value is Dictionary:
			continue
		var tag := str(value.get("outcome_tag", ""))
		var speaker := str(value.get("speaker_id", ""))
		var mission_id := str(value.get("mission_id", ""))
		if not is_public(tag) or speaker not in ["kaelen", "nova"] or mission_id.is_empty() or str(value.get("system_id", "")).is_empty():
			continue
		var identity := "%s:%s" % [mission_id, speaker]
		if result.any(func(entry: Dictionary) -> bool: return entry["id"] == identity):
			continue
		result.append({"id": identity, "outcome_id": mission_id, "mission_id": mission_id,
			"speaker_id": speaker, "system_id": str(value["system_id"]), "outcome_tag": tag,
			"public_fact_id": "outcome.%s" % tag, "kind": MEMORY_KINDS[tag],
			"at_minute": maxi(0, int(value.get("at_minute", 0))),
			"callback_delivered": bool(value.get("callback_delivered", false)),
			"immediate_delivered": bool(value.get("immediate_delivered", false)),
			"at_step": int(value.get("at_step", -100)),
			"delivered_step": int(value.get("delivered_step", -1)),
			"delivered_visit": int(value.get("delivered_visit", -1)),
			"attempted_step": int(value.get("attempted_step", -1))})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["at_minute"]) < int(b["at_minute"]))
	for speaker in ["kaelen", "nova"]:
		while result.filter(func(entry: Dictionary) -> bool: return entry["speaker_id"] == speaker).size() > 12:
			var victim := -1
			for index in result.size():
				if result[index]["speaker_id"] == speaker:
					if victim == -1:
						victim = index
					if bool(result[index]["callback_delivered"]):
						victim = index
						break
			result.remove_at(victim)
	return result


## Rebuild wording from the typed tag; persisted free text is never prompt input.
static func memory_context(raw: Variant, speaker: String, system_id: String) -> Array:
	var result: Array = []
	if system_id.is_empty():
		return result
	var memories := normalize_memories(raw)
	memories.reverse()
	for entry in memories:
		if entry["speaker_id"] != speaker or entry["system_id"] != system_id:
			continue
		var projection := project({"outcome_tag": entry["outcome_tag"], "owner_id": entry["mission_id"]})
		result.append({"id": entry["public_fact_id"], "mission_id": entry["mission_id"],
			"certainty": projection["consequence"]["certainty"], "text": projection["consequence"]["summary"]})
		if result.size() == 2:
			break
	return result


static func eligible_reaction(raw: Variant, speaker: String, system_id: String, step: int, visit: int) -> Dictionary:
	var memories := normalize_memories(raw)
	memories.reverse()
	# One outcome reference per speaker per visit, across all outcomes.
	for entry in memories:
		if entry["speaker_id"] == speaker and int(entry["delivered_visit"]) == visit:
			return {}
	for entry in memories:
		var age := step - int(entry["at_step"])
		if entry["speaker_id"] != speaker or entry["system_id"] != system_id \
				or age < 0 or age > 4 or int(entry["attempted_step"]) == step:
			continue
		if not bool(entry["immediate_delivered"]):
			entry["phase"] = "immediate"
			return entry
		if not bool(entry["callback_delivered"]) and age >= 1 and step > int(entry["delivered_step"]):
			entry["phase"] = "callback"
			return entry
	return {}


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
