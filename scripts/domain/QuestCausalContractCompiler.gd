class_name QuestCausalContractCompiler
extends RefCounted

## Turns the data the game ALREADY has -- a local faction's desire, its rival,
## the objective it produced -- into a causal contract, so the reason a job
## exists is recorded as structured facts instead of one prose sentence.
##
## This does not generate anything. It compiles. The model's job comes later,
## expressing these facts as speech; if the compiler cannot bind a fact, the
## contract is simply thinner, never invented.

const ContractType := preload("res://scripts/domain/QuestCausalContract.gd")
const DesireType := preload("res://scripts/persistence/GeneratedFactionDesire.gd")

## Objective types that hand an object to a person.
const DELIVERY_TYPES := ["DELIVERY_COURIER", "PURCHASE_DELIVERY"]

## Which capability each objective needs. Used so the plausibility validator can
## check the objective against what is actually active.
const CAPABILITY_BY_OBJECTIVE := {
	"DELIVER_ORE": "capability.cargo_transport",
	"DELIVERY_COURIER": "capability.cargo_transport",
	"PURCHASE_DELIVERY": "capability.cargo_transport",
	"PICKUP_SPECIAL": "capability.cargo_transport",
	"RECOVER_COMBAT_DROP": "capability.salvage",
	"KILL_SHIPS": "capability.combat",
	"TARGET_WITH_COMMS_REVERSAL": "capability.combat",
	"INVESTIGATE_SIGNAL": "capability.site_scan",
}


## `source` is the assembled offer data:
##   objective            -- the real objective dictionary
##   cause                -- story cause metadata (cause_id, desire_id, faction ids,
##                           public_because, stake)
##   agenda               -- the faction agenda record from the system story pack
##   recipient            -- {id, name, role, station_id, protected} for deliveries
##   campaign_id, system_id, requester_display, rival_display
##
## Returns a normalized contract. Callers must still run
## QuestPlausibilityValidator before publishing it.
static func compile(source: Dictionary) -> Dictionary:
	var cause: Dictionary = source.get("cause", {}) if source.get("cause", {}) is Dictionary else {}
	var objective: Dictionary = source.get("objective", {}) \
		if source.get("objective", {}) is Dictionary else {}
	var agenda: Dictionary = source.get("agenda", {}) \
		if source.get("agenda", {}) is Dictionary else {}
	var desire: Dictionary = agenda.get("desire", {}) \
		if agenda.get("desire", {}) is Dictionary else {}

	var requester_id := str(cause.get("cause_faction_id", "")).strip_edges()
	if requester_id.is_empty():
		requester_id = str(agenda.get("faction_id", "")).strip_edges()
	var desire_id := str(cause.get("desire_id", "")).strip_edges()
	if desire_id.is_empty():
		desire_id = str(desire.get("id", "")).strip_edges()
	var cause_id := str(cause.get("cause_id", "")).strip_edges()
	# Without a requester or a desire there is no causal story to record, and a
	# contract invented to fill the gap would be exactly the fake we are avoiding.
	if requester_id.is_empty() or desire_id.is_empty():
		return {}

	var facts := _build_facts(source, cause, desire, agenda)
	var objective_type := str(objective.get("type", "")).strip_edges().to_upper()
	var contract := {
		"id": _contract_id(source, cause_id, objective_type),
		"revision": maxi(1, int(source.get("revision", 1))),
		"campaign_id": str(source.get("campaign_id", "")).strip_edges(),
		"system_id": str(source.get("system_id", "")).strip_edges(),
		"requester_id": requester_id,
		"beneficiary_id": str(source.get("beneficiary_id", requester_id)).strip_edges(),
		"desire_id": desire_id,
		"triggering_event_id": _triggering_event_id(desire, cause_id),
		"facts": facts,
		"problem_fact_ids": _present(facts, ["fact.obstacle", "fact.need", "fact.triggering_event"]),
		"public_fact_ids": _public_ids(facts),
		"private_fact_ids": _private_ids(facts),
		"why_this_action_fact_ids": _present(facts, ["fact.need", "fact.action_helps"]),
		"why_player_fact_ids": _present(facts, ["fact.delegation"]),
		"urgency_fact_ids": _present(facts, ["fact.urgency"]),
		"reward_source_fact_ids": _present(facts, ["fact.reward_source"]),
		"objective_binding": _objective_binding(source, objective, objective_type),
		"recipient_binding": _recipient_binding(source, objective_type),
		"completion_effect_ids": ["desire_progress.%s" % desire_id],
		"failure_effect_ids": [],
		"branch_contracts": _string_keyed_branches(source.get("branch_contracts", [])),
		"semantic_tokens": _semantic_tokens(desire, objective, objective_type),
	}
	return ContractType.normalize(contract)


static func _contract_id(source: Dictionary, cause_id: String, objective_type: String) -> String:
	var explicit := str(source.get("contract_id", "")).strip_edges()
	if not explicit.is_empty():
		return explicit
	var basis := "%s|%s|%s|%s" % [
		str(source.get("campaign_id", "")),
		str(source.get("system_id", "")),
		cause_id,
		objective_type,
	]
	return "quest.%s" % basis.sha256_text().substr(0, 16)


## Facts are only recorded when the underlying data actually exists. A missing
## rival produces no rivalry fact -- it does NOT produce a generic one. That is
## the difference between a thin contract and a fabricated one.
static func _build_facts(
	source: Dictionary,
	cause: Dictionary,
	desire: Dictionary,
	agenda: Dictionary
) -> Dictionary:
	var facts := {}
	var requester := str(source.get("requester_display", "")).strip_edges()
	if requester.is_empty():
		requester = str(agenda.get("faction_name", "")).strip_edges()
	if requester.is_empty():
		requester = "The client"

	var need := str(desire.get("need", "")).strip_edges()
	var goal := str(desire.get("goal", "")).strip_edges()
	if not need.is_empty() and not goal.is_empty():
		var need_text := "%s needs %s in order to %s." % [requester, need, goal]
		var coherence := DesireType.check_coherence(desire)
		if bool(coherence.get("checked", false)) and not bool(coherence.get("ok", false)):
			# A corrupt new draft must not become an asserted causal explanation.
			# The publication builder withholds it; legacy records stay compatible.
			need_text = "%s wants to %s. It has recorded a need for %s." % [requester, goal, need]
		if bool(coherence.get("ok", false)):
			need_text = "%s wants to %s. It needs %s. %s" % [
				requester, goal, need, str(desire["need_reason"])
			]
		facts["fact.need"] = _fact(
			need_text,
			"public",
			"problem"
		)
	var stake := str(cause.get("stake", desire.get("stake", ""))).strip_edges()
	if not stake.is_empty():
		facts["fact.stake"] = _fact(
			"For %s, %s." % [requester, _lower_first(stake.trim_suffix("."))],
			"public",
			"stake"
		)
	# The faction's OWN obstacle comes first. A rival is only an obstacle when
	# there actually is one and the relationship is actually adversarial, so a
	# system full of cooperating outfits still produces real problems.
	var obstacle := str(source.get("obstacle", desire.get("obstacle", ""))).strip_edges()
	if obstacle.is_empty():
		obstacle = _obstacle_from_rivalry(source, cause, agenda, requester)
	elif not requester.is_empty():
		obstacle = "%s: %s." % [requester, obstacle.trim_suffix(".")]
	if not obstacle.is_empty():
		facts["fact.obstacle"] = _fact(obstacle, "public", "problem")
	# What actually happened. A problem with no cause is scenery.
	var event := str(source.get("triggering_event", desire.get("triggering_event", ""))).strip_edges()
	if not event.is_empty():
		facts["fact.triggering_event"] = _fact(
			"It started with %s." % event.trim_suffix("."),
			"public",
			"event"
		)
	# What it holds gives it something to trade with, and explains why it can
	# credibly pay at all.
	var controls := str(desire.get("controls", "")).strip_edges()
	if not controls.is_empty():
		facts["fact.controls"] = _fact(
			"%s holds %s." % [requester, controls.trim_suffix(".")],
			"public",
			"holdings"
		)
	# The line it will not cross. Makes a refusal legible instead of arbitrary.
	var limit := str(desire.get("limit", "")).strip_edges()
	if not limit.is_empty():
		facts["fact.limit"] = _fact(
			"%s." % _upper_first(limit.trim_suffix(".")),
			"public",
			"limit"
		)
	# How THIS objective -- this item, this target, this destination -- addresses
	# the need. Attaching a cause by mission verb alone was the gap: it justified
	# the category ("they need a delivery") and not the particular cargo.
	var action_helps := str(source.get("action_helps", "")).strip_edges()
	if action_helps.is_empty():
		action_helps = _action_helps_text(source, desire, requester)
	if not action_helps.is_empty():
		facts["fact.action_helps"] = _fact(action_helps, "public", "method")
	var delegation := str(source.get("delegation", "")).strip_edges()
	if not delegation.is_empty():
		facts["fact.delegation"] = _fact(delegation, "public", "delegation")
	var reward_source := str(source.get("reward_source", "")).strip_edges()
	if reward_source.is_empty():
		var payment := str(desire.get("payment_source", "")).strip_edges()
		if not payment.is_empty():
			reward_source = "%s pays out of %s." % [requester, payment.trim_suffix(".")]
	if not reward_source.is_empty():
		facts["fact.reward_source"] = _fact(reward_source, "public", "reward_source")
	# Urgency is recorded ONLY when the objective actually has a deadline. Never
	# manufacture a hurry to make a job feel more interesting.
	var urgency := str(source.get("urgency", "")).strip_edges()
	var objective: Dictionary = source.get("objective", {}) \
		if source.get("objective", {}) is Dictionary else {}
	if not urgency.is_empty() and int(objective.get("duration_minutes", 0)) > 0:
		facts["fact.urgency"] = _fact(urgency, "public", "urgency")
	var risk := str(source.get("risk", "")).strip_edges()
	if not risk.is_empty():
		facts["fact.risk"] = _fact(risk, "public", "risk")
	# Recorded, never disclosed. It stays out of every dialogue fact packet; the
	# contract holds it so a lie can be distinguished from broken quest logic.
	var private_motive := str(source.get("private_motive", desire.get("private_motive", ""))).strip_edges()
	if not private_motive.is_empty():
		facts["fact.private_motive"] = _fact(private_motive, "private", "motive")
	# A public explanation that adds nothing beyond the facts above is dropped
	# rather than duplicated, so the packet does not say the same thing twice.
	var because := str(cause.get("public_because", "")).strip_edges()
	if not because.is_empty() and not facts.has("fact.need"):
		facts["fact.need"] = _fact(because, "public", "problem")
	return facts


## Say what the specific objective does for the specific need. Returns empty
## when the objective does not carry enough detail to make a real claim -- a
## vague sentence that fits any cargo is worse than no fact at all, because the
## packet would then present it as grounding it does not provide.
static func _action_helps_text(
	source: Dictionary,
	desire: Dictionary,
	requester: String
) -> String:
	var objective: Dictionary = source.get("objective", {}) if source.get("objective", {}) is Dictionary else {}
	var need := str(desire.get("need", "")).strip_edges()
	if need.is_empty():
		return ""
	var who := requester if not requester.is_empty() else "They"
	var objective_type := str(objective.get("type", "")).strip_edges().to_upper()
	var item := _objective_item_name(objective)
	var destination := str(objective.get("destination_display", "")).strip_edges()
	if destination.is_empty():
		destination = str(objective.get("destination_station_id", "")).strip_edges()
	var origin := str(objective.get("store_display", objective.get("origin_display", ""))).strip_edges()
	var target_outpost := str(objective.get("target_outpost_display", "")).strip_edges()

	# Whether this objective's cargo is ACTUALLY the thing the need names. Only a
	# bound item earns the strong claim; an arbitrary crate gets the weaker one
	# that is still true. This is the review's point: the compiler must not hand
	# the fact packet an invented causal link as authoritative truth, because
	# nothing downstream can catch it once it IS the record.
	var item_is_the_need := not item.is_empty() and DesireType.binds_item_to_need(need, item)

	match objective_type:
		"DELIVERY_COURIER":
			if item.is_empty() or destination.is_empty():
				return ""
			if item_is_the_need:
				return "%s is what %s is short of, and it has to reach %s before the need is met." % [
					item, who, destination
				]
			# Unbound cargo: state only what is actually supported -- a paid run
			# to a place, for a party that is short-handed. Do NOT claim this
			# particular crate is the missing thing.
			return "%s is paying to get %s to %s while its own hulls are tied up." % [
				who, item, destination
			]
		"PURCHASE_DELIVERY":
			if item.is_empty() or origin.is_empty():
				return ""
			if item_is_the_need:
				return "%s stocks %s, which is what %s needs to move on %s." % [
					origin, item, who, need
				]
			# "the ONLY way" was never established; nothing checked alternatives.
			return "%s is paying for %s out of %s rather than sourcing it itself." % [
				who, item, origin
			]
		"DELIVER_ORE":
			var amount := int(float(objective.get("amount_required", 0)))
			if amount <= 0:
				return ""
			# Deliberately does NOT claim the ore satisfies the need directly --
			# it funds it. Asserting "ore is what covers survey data" was a
			# false causal claim the fact packet would have presented as truth.
			return "%d m3 of ore is what %s is selling to pay for %s." % [amount, who, need]
		"PICKUP_SPECIAL":
			if item.is_empty() or target_outpost.is_empty():
				return ""
			if item_is_the_need:
				return "%s is held at %s, and %s cannot proceed on %s without it." % [
					item, target_outpost, who, need
				]
			return "%s wants %s brought back from %s." % [who, item, target_outpost]
		"RECOVER_COMBAT_DROP", "KILL_SHIPS", "TARGET_WITH_COMMS_REVERSAL":
			# Only a display name may appear here. The objective carries a raw
			# faction KEY ("gen_3753748b9ca0_f1"), which reached player-visible
			# text in an earlier version. If the caller did not resolve it to a
			# name, describe the obstruction without naming anyone.
			var hostile_display := str(source.get("target_faction_display", "")).strip_edges()
			# A faction cannot be the thing standing between itself and what it
			# wants. The recovery target picker can land on the requester, and
			# naming it produced "What X is running stands between X and ...".
			if hostile_display == requester:
				hostile_display = ""
			if hostile_display.is_empty():
				return "Clearing that lane is what stands between %s and %s." % [who, need]
			return "What %s is running in that lane is what stands between %s and %s." % [
				hostile_display, who, need
			]
		"INVESTIGATE_SIGNAL":
			var site := str(objective.get("site_display", objective.get("site_id", ""))).strip_edges()
			if site.is_empty():
				return ""
			# "the only record" was an unchecked superlative. State what is
			# supported: the site is where the evidence would be.
			return "Whatever is still at %s is what would settle %s." % [site, need]
		_:
			return ""


static func _upper_first(text: String) -> String:
	if text.is_empty():
		return text
	return text.substr(0, 1).to_upper() + text.substr(1)


static func _lower_first(text: String) -> String:
	if text.is_empty():
		return text
	# Only lower an ordinary capitalised word; never touch a proper noun that is
	# already capitalised as part of a name.
	var first := text.substr(0, 1)
	if first != first.to_upper():
		return text
	var words := text.split(" ", false)
	if words.size() > 1 and str(words[1]).length() > 0 and str(words[1])[0] == str(words[1])[0].to_upper():
		return text
	return first.to_lower() + text.substr(1)


static func _objective_item_name(objective: Dictionary) -> String:
	for key in ["item_name", "part_name", "display_name"]:
		var value := str(objective.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return ""

## The rival only becomes an obstacle when there IS one and the relationship is
## actually adversarial. Cooperation and indifference are legitimate outcomes.
static func _obstacle_from_rivalry(
	source: Dictionary,
	cause: Dictionary,
	agenda: Dictionary,
	requester: String
) -> String:
	var rival_id := str(cause.get("cause_rival_faction_id", "")).strip_edges()
	if rival_id.is_empty():
		return ""
	var rival_display := str(source.get("rival_display", "")).strip_edges()
	if rival_display.is_empty():
		return ""
	for raw_relationship in (agenda.get("relationships", []) as Array):
		if not (raw_relationship is Dictionary):
			continue
		var relationship: Dictionary = raw_relationship
		if str(relationship.get("faction_id", "")).strip_edges() != rival_id:
			continue
		if int(relationship.get("standing", 0)) >= 0:
			# They get along. That is not an obstacle, and pretending otherwise
			# is how every faction ends up hating someone for no reason.
			return ""
		var reason := str(relationship.get("reason", "")).strip_edges()
		if not reason.is_empty():
			return "%s." % reason.trim_suffix(".")
		return "%s is competing with %s for the same access." % [rival_display, requester]
	return ""


## The desire records the event that caused its obstacle. Prefer that over the
## cause id, which identifies the mission slot rather than the thing that happened.
static func _triggering_event_id(desire: Dictionary, cause_id: String) -> String:
	var event_id := str(desire.get("triggering_event_id", "")).strip_edges()
	return event_id if not event_id.is_empty() else cause_id


static func _fact(text: String, visibility: String, kind: String) -> Dictionary:
	return {"text": text.strip_edges(), "visibility": visibility, "kind": kind}


static func _objective_binding(
	source: Dictionary,
	objective: Dictionary,
	objective_type: String
) -> Dictionary:
	var binding := {
		"type": objective_type,
		"capability_id": str(CAPABILITY_BY_OBJECTIVE.get(objective_type, "")),
		"reward_credits": int(objective.get("reward_credits", 0)),
		"location_system_id": str(source.get("system_id", "")).strip_edges(),
	}
	for key in ["amount_required", "quantity_required", "quantity", "count"]:
		if objective.has(key):
			binding["quantity"] = float(objective[key])
			break
	for key in ["item_id", "part_name", "item_name", "cargo_id"]:
		if objective.has(key):
			binding["item_name"] = str(objective[key])
			break
	for key in ["destination_id", "destination", "target_outpost", "turn_in_location"]:
		if objective.has(key) and not str(objective[key]).strip_edges().is_empty():
			binding["destination_station_id"] = str(objective[key]).strip_edges()
			break
	if objective.has("target_faction"):
		binding["target_faction"] = str(objective["target_faction"])
	var duration := int(objective.get("duration_minutes", 0))
	if duration > 0:
		binding["deadline_minutes"] = duration
	return binding


## Only deliveries carry a recipient. Attaching one to a mining job would be
## noise the plausibility validator would then have to warn about.
static func _recipient_binding(source: Dictionary, objective_type: String) -> Dictionary:
	if objective_type not in DELIVERY_TYPES:
		return {}
	var recipient: Variant = source.get("recipient", {})
	if not (recipient is Dictionary) or (recipient as Dictionary).is_empty():
		return {}
	var entry: Dictionary = recipient
	return {
		"id": str(entry.get("id", "")).strip_edges(),
		"name": str(entry.get("name", "")).strip_edges(),
		"role": str(entry.get("role", "")).strip_edges().to_lower(),
		"station_id": str(entry.get("station_id", "")).strip_edges(),
		"protected": bool(entry.get("protected", false)),
	}


static func _string_keyed_branches(value: Variant) -> Array:
	if not (value is Array):
		return []
	return (value as Array).duplicate(true)


## Fact IDs from `wanted` that were actually recorded. Keeps every list in the
## contract referentially honest without the caller checking each one.
static func _present(facts: Dictionary, wanted: Array) -> Array[String]:
	var present: Array[String] = []
	for fact_id in wanted:
		var key := str(fact_id)
		if facts.has(key) and key not in present:
			present.append(key)
	return present


static func _public_ids(facts: Dictionary) -> Array[String]:
	return _ids_with_visibility(facts, "public")


static func _private_ids(facts: Dictionary) -> Array[String]:
	return _ids_with_visibility(facts, "private")


static func _ids_with_visibility(facts: Dictionary, visibility: String) -> Array[String]:
	var ids: Array[String] = []
	for fact_id in facts.keys():
		var fact: Variant = facts[fact_id]
		if not (fact is Dictionary):
			continue
		if str((fact as Dictionary).get("visibility", "")) == visibility:
			ids.append(str(fact_id))
	return ids


## Structural tokens for novelty comparison (plan P3 deliverable E).
##
## Derived from validated STRUCTURED desire fields, never from prose, names,
## coordinates, quantities, random suffixes or private evidence values. A
## campaign-specific ID suffix must never make two identical reasons look
## different, and a shared suffix must never make two different motivations look
## the same.
static func _semantic_tokens(desire: Dictionary, objective: Dictionary, objective_type: String) -> Dictionary:
	var recipe := str(objective.get("recipe", "")).strip_edges().to_lower()
	return {
		"goal": _slug(desire.get("goal", "")),
		"need": _slug(desire.get("need", "")),
		"obstacle": _slug(desire.get("obstacle_binding_id", "")),
		"event": _slug(desire.get("triggering_event", "")),
		"verb": objective_type.to_lower(),
		"resolution": recipe,
		# The PATTERN, not the secret: "two-site comparison" never reveals which
		# of A or B is true, so a signature cannot leak the answer.
		"evidence_pattern": _evidence_pattern(recipe),
	}


static func _evidence_pattern(recipe: String) -> String:
	match recipe:
		"survey_discrepancy", "transmitter_lure":
			return "two_site_comparison"
		"competing_claims":
			return "ownership_record_comparison"
		"unstable_archive":
			return "single_source_recovery"
	return "none" if recipe.is_empty() else "other"


## Lowercase, punctuation-free, whitespace-joined. Stable across campaigns
## because it reads the meaning, not an instance ID.
static func _slug(value: Variant) -> String:
	var text := str(value).strip_edges().to_lower()
	if text.is_empty():
		return "none"
	var out := ""
	for index in range(text.length()):
		var ch := text[index]
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif not out.ends_with("_"):
			out += "_"
	return out.strip_edges().trim_suffix("_").trim_prefix("_")
