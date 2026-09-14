class_name GeneratedFactionDesire
extends RefCounted

## Builds a local faction's INTERESTS: what it wants, what is stopping it, what
## it can offer, what it will not do, and what would change its mind.
##
## Goals have multiple compatible needs. Obstacles/events and holdings/payment
## are paired so random variation cannot supply contradictory facts to a writer.
## This affects new generation only; persisted desires are never rebuilt here.
##
## This is still generation from vocabularies -- it does not claim unlimited
## variety. It claims that the REASON differs, which is what the end goal asks
## for, and `QuestCausalContract.semantic_signature()` is what measures whether
## that is actually true rather than merely more words.

const Constraints := preload("res://scripts/persistence/GeneratedDesireConstraints.gd")

## What the faction is trying to bring about.
const GOALS := [
	"reopen the freight lane it lost",
	"clear its name on a salvage claim",
	"buy out the lease on its own dock",
	"get its impounded hulls released",
	"finish a survey before the filing deadline",
	"replace the crew it lost in one bad season",
	"prove a rival's manifest is fiction",
	"keep its people fed through a thin quarter",
	"secure a second supplier before the first one folds",
	"recover records that would settle an old debt",
	"win back a contract it was underbid on",
	"stop paying a toll it does not believe is legal",
]

## How anyone could TELL the goal was achieved. A desire with no observable
## success condition cannot produce a completion effect.
const SUCCESS_CONDITIONS := [
	"the lane reopens to its traffic",
	"the claim is struck from the register",
	"the lease transfers into its own name",
	"the hulls are released from impound",
	"the survey is filed before the cutoff",
	"its roster is crewed to minimum again",
	"the manifest is withdrawn",
	"its stores last the quarter",
	"a second supply line is signed",
	"the records are produced in full",
	"the contract comes back to it",
	"the toll stops being collected",
]

## The concrete thing it needs to get there.
const NEEDS := [
	"route permits",
	"replacement assemblies",
	"filed claim evidence",
	"convoy escort guarantees",
	"a reactor coupling nobody will sell it",
	"survey data from a drift it cannot reach",
	"sealed manifests from the last shipment",
	"medical stock for its own crew",
	"a clean ore assay",
	"a witness who will go on record",
	"fuel it can afford",
	"salvage rights to one specific wreck",
]

## Why it does not simply get the thing itself. This is the OBSTACLE, and it is
## generated separately from the rival, because plenty of problems are nobody's
## fault.
const OBSTACLES := [
	"its own hulls are all committed elsewhere",
	"the only supplier stopped answering",
	"the paperwork is held up behind an older dispute",
	"nobody local will take the run at the price it can pay",
	"the site sits outside its licensed operating radius",
	"the last two crews it sent did not come back",
	"its credit is frozen pending an audit",
	"the records burned with the ship that carried them",
	"the berth it needs is booked out for the season",
	"the assay equipment it owns is not certified",
]

## What actually happened to cause the obstacle. A problem with no triggering
## event is scenery; a problem with one is a story.
const TRIGGERING_EVENTS := [
	"a decompression in the number four bay",
	"a supplier folding mid-contract",
	"an impound order served without warning",
	"a convoy that never reported in",
	"an audit opened on an anonymous complaint",
	"a berth fire that took the filing office with it",
	"a licence lapsing during a handover",
	"a surveyor quitting on the spot",
	"a shipment arriving with the wrong seals",
	"a lane closure announced with three days' notice",
]

## What it holds that gives it something to trade with, and what it can pay from.
const CONTROLS := [
	"a repair bay nobody else can certify",
	"the only bonded warehouse on the ring",
	"two long-haul hulls in working order",
	"the assay records going back nine years",
	"a berth lease with four years left on it",
	"the fuel depot on the approach lane",
	"the medical bay the whole station uses",
	"a surveyor's licence that still checks out",
]

const PAYMENT_SOURCES := [
	"a salvage account it is paid into per hull stripped",
	"the escort bond it holds against the lane",
	"an advance it has already drawn against next quarter",
	"the berth fees it collects from three smaller outfits",
	"a settlement it won and has not yet spent",
	"the standing retainer its warehouse contract pays",
]

## The line it will not cross. Gives a refusal a reason and makes a branch that
## asks for it legible rather than arbitrary.
const LIMITS := [
	"it will not move anything sealed it has not logged",
	"it will not put its own name on another outfit's filing",
	"it will not hire anyone the station has flagged",
	"it will not let a job run through the medical bay",
	"it will not pay before delivery, for anyone",
	"it will not testify against a crew it used to employ",
]

## What would make it change its position. This is what lets a completed job
## actually move something instead of only paying out.
const CHANGE_CONDITIONS := [
	"the impound order being lifted",
	"a second supplier signing",
	"the audit closing without a finding",
	"the records turning up intact",
	"the lane reopening to anyone at all",
	"the rival withdrawing its own claim",
]

## Kept SEPARATE from the public explanation and never placed in a prompt. The
## contract records who knows it; the fact packet withholds it entirely.
const PRIVATE_MOTIVES := [
	"the shortfall is its own accounting error and it knows it",
	"it has already promised the same cargo to two buyers",
	"the crew it lost was sent out under-equipped on its own order",
	"it is buying time before an inspection it cannot pass",
	"the claim it is defending was filed on a guess",
	"it needs the job done before a partner finds out it was needed",
]

## The concrete cargo that actually IS each need.
##
## Exists so the contract compiler can say "this crate is the thing they are
## short of" and have it be TRUE BY CONSTRUCTION, rather than asserting a link
## between a need and whatever item a package-name list happened to produce.
## An unbound item is the failure the integration review named: the compiler
## supplies an invented reason as authoritative truth, and no critic downstream
## can catch it, because by then it IS the record.
const ITEMS_BY_NEED := {
	"route permits": ["Sealed Transit Permit Case", "Stamped Lane Authorisation"],
	"replacement assemblies": ["Transfer Coupling", "Pump Actuator Assembly", "Coolant Bypass Cap"],
	"filed claim evidence": ["Sealed Evidence Tube", "Certified Claim Packet"],
	"convoy escort guarantees": ["Escort Bond Certificate", "Countersigned Convoy Warrant"],
	"a reactor coupling nobody will sell it": ["Reactor Coupling", "Shielded Coupling Core"],
	"survey data from a drift it cannot reach": ["Survey Data Core", "Drift Telemetry Brick"],
	"sealed manifests from the last shipment": ["Sealed Manifest Bundle", "Bonded Cargo Ledger"],
	"medical stock for its own crew": ["Sealed Medical Case", "Trauma Resupply Crate"],
	"a clean ore assay": ["Certified Assay Sample", "Sealed Ore Reference Core"],
	"a witness who will go on record": ["Sworn Deposition Case", "Recorded Testimony Drive"],
	"fuel it can afford": ["Bonded Fuel Cell", "Surplus Reaction Mass Canister"],
	"salvage rights to one specific wreck": ["Salvage Title Deed", "Notarised Wreck Claim"],
}


## The cargo that satisfies a need, or "" when we have no binding for it.
## Returning empty is CORRECT and load-bearing: the compiler then declines to
## claim a link it cannot support, rather than inventing one.
static func item_for_need(need: String, salt: String = "") -> String:
	var options: Variant = ITEMS_BY_NEED.get(need.strip_edges(), Constraints.EXTRA_ITEMS.get(need.strip_edges(), []))
	if not (options is Array) or (options as Array).is_empty():
		return ""
	var list: Array = options
	var index := _digest("%s|%s" % [need, salt], "item") % list.size()
	return str(list[index])


static func binds_item_to_need(need: String, item_name: String) -> bool:
	var options: Variant = ITEMS_BY_NEED.get(need.strip_edges(), Constraints.EXTRA_ITEMS.get(need.strip_edges(), []))
	if not (options is Array):
		return false
	return item_name.strip_edges() in (options as Array)


## Which gameplay verbs a NEED actually implies. Drawn from the need rather than
## from the goal, so the work the player is asked to do follows from the thing
## that is missing -- not from a template index the goal happened to share.
const INTENTS_BY_NEED := {
	"route permits": ["delivery", "pickup"],
	"replacement assemblies": ["purchase", "delivery"],
	"filed claim evidence": ["recovery", "pickup"],
	"convoy escort guarantees": ["combat", "delivery"],
	"a reactor coupling nobody will sell it": ["purchase", "recovery"],
	"survey data from a drift it cannot reach": ["recovery", "pickup"],
	"sealed manifests from the last shipment": ["pickup", "recovery"],
	"medical stock for its own crew": ["purchase", "delivery"],
	"a clean ore assay": ["ore", "pickup"],
	"a witness who will go on record": ["pickup", "delivery"],
	"fuel it can afford": ["ore", "purchase"],
	"salvage rights to one specific wreck": ["recovery", "combat"],
}


## Draw within compatible sets. The IDs/version identify generation provenance;
## they do not migrate or re-author an existing world's facts.
static func build(scope: String, scope_id: String, index: int) -> Dictionary:
	var goal_index := _pick(scope, index, "goal", GOALS.size())
	var options: Dictionary = Constraints.GOAL_NEEDS[goal_index]
	var need := str(_draw(scope, index, "need", options.keys()))
	var blocker: Dictionary = _draw(scope, index, "obstacle", Constraints.BLOCKERS)
	var resources: Dictionary = _draw(scope, index, "controls", Constraints.RESOURCES)
	return {
		"id": "desire.%s.f%d" % [scope_id, index],
		"generation_version": Constraints.VERSION,
		"obstacle_binding_id": str(blocker["id"]),
		"resource_binding_id": str(resources["id"]),
		"goal": str(GOALS[goal_index]),
		# The success condition is paired with the goal on purpose: it is the
		# same statement seen from outside, not an independent choice.
		"success_condition": str(SUCCESS_CONDITIONS[goal_index]),
		"need": need,
		"need_reason": Constraints.need_reason(goal_index, need),
		"obstacle": str(blocker["obstacle"]),
		"triggering_event": str(blocker["triggering_event"]),
		"triggering_event_id": "event.%s.f%d" % [scope_id, index],
		"controls": str(resources["controls"]),
		"payment_source": str(resources["payment_source"]),
		"limit": str(_draw(scope, index, "limit", [LIMITS[0], LIMITS[2], LIMITS[4]])),
		"change_condition": str(blocker["change_condition"]),
		"private_motive": PRIVATE_MOTIVES[5],
		"mission_intents": _intents_for_need(need),
		"stake": "%s; resolving it would allow progress toward the goal" % str(blocker["obstacle"]),
	}


static func _intents_for_need(need: String) -> Array:
	var intents: Variant = INTENTS_BY_NEED.get(need, Constraints.EXTRA_INTENTS.get(need, ["delivery", "pickup"]))
	return (intents as Array).duplicate()


## Used by publication and diagnostics; legacy records are explicitly unchecked.
## It never edits a saved record to make today's generation rules fit it.
static func check_coherence(desire: Dictionary) -> Dictionary:
	if not desire.has("generation_version"):
		return {"checked": false, "ok": false, "errors": ["legacy_generator"]}
	if int(desire.get("generation_version", 0)) != Constraints.VERSION:
		return {"checked": true, "ok": false, "errors": ["unknown_generator_version"]}
	var errors: Array[String] = []
	var goal_index := GOALS.find(str(desire.get("goal", "")))
	var need := str(desire.get("need", ""))
	var reason := Constraints.need_reason(goal_index, need)
	if reason.is_empty() or reason != str(desire.get("need_reason", "")):
		errors.append("unsupported_goal_need")
	if goal_index < 0 or str(desire.get("success_condition", "")) != str(SUCCESS_CONDITIONS[goal_index]):
		errors.append("unsupported_success_condition")
	if not _matches_binding(desire, Constraints.BLOCKERS, "obstacle_binding_id", ["obstacle", "triggering_event", "change_condition"]):
		errors.append("unsupported_obstacle_event")
	if not _matches_binding(desire, Constraints.RESOURCES, "resource_binding_id", ["controls", "payment_source"]):
		errors.append("unsupported_resource_payment")
	if item_for_need(need).is_empty() or desire.get("mission_intents", []) != _intents_for_need(need):
		errors.append("unsupported_need_work")
	return {"checked": true, "ok": errors.is_empty(), "errors": errors}


static func _matches_binding(desire: Dictionary, bindings: Array, id_key: String, fields: Array) -> bool:
	for binding: Dictionary in bindings:
		if str(binding["id"]) != str(desire.get(id_key, "")):
			continue
		for field in fields:
			if str(desire.get(field, "")) != str(binding[field]):
				return false
		return true
	return false


## Deterministic per-dimension draw. The dimension name is part of the seed, so
## two dimensions of the same faction never move together.
##
## sha256 rather than String.hash(): Godot's string hash is linear, so two seeds
## of the same length differing only in a short suffix ("...|goal" vs "...|need")
## keep a CONSTANT difference modulo the option count. That made need perfectly
## predict goal -- the exact locked-template failure this class replaces, just
## hidden one layer down. Caught by the cross-seed variety test, not by review.
static func _pick(scope: String, index: int, dimension: String, size: int) -> int:
	if size <= 0:
		return 0
	var digest := ("%s|%d|%s" % [scope, index, dimension]).sha256_text()
	return absi(digest.substr(0, 8).hex_to_int()) % size


## Same reasoning as _pick: a cryptographic digest so short seed suffixes do not
## stay correlated after the modulo.
static func _digest(seed_text: String, dimension: String) -> int:
	return absi(("%s|%s" % [seed_text, dimension]).sha256_text().substr(0, 8).hex_to_int())


static func _draw(scope: String, index: int, dimension: String, options: Array) -> Variant:
	if options.is_empty():
		return ""
	return options[_pick(scope, index, dimension, options.size())]


## Relationship kinds, with the standing band each implies. Deliberately not all
## hostile: the plan is explicit that cooperation, dependency and indifference
## are legitimate, and that two factions can need each other while disagreeing
## over one specific matter.
const RELATIONSHIP_KINDS := {
	"dependency": {"low": 30, "high": 60},
	"cooperation": {"low": 20, "high": 55},
	"indifference": {"low": -10, "high": 10},
	"friction": {"low": -40, "high": -15},
	"rivalry": {"low": -75, "high": -45},
}

## Weighted draw. Friction and rivalry together are a minority, so a system does
## not default to everyone hating everyone.
const RELATIONSHIP_WEIGHTS := [
	"dependency", "dependency",
	"cooperation", "cooperation",
	"indifference", "indifference",
	"friction", "friction",
	"rivalry",
]


## Directed relationships for one system's factions. ASYMMETRIC on purpose: how
## A sees B is drawn separately from how B sees A, so one side can depend on a
## party that is indifferent to it.
##
## `factions` must already carry id, display_name and desire.
static func build_relationships(scope: String, factions: Array) -> void:
	if factions.size() < 2:
		for faction in factions:
			(faction as Dictionary)["relationships"] = []
		return
	for index in range(factions.size()):
		var relationships: Array = []
		for other in range(factions.size()):
			if other == index:
				continue
			relationships.append(_relationship(scope, factions, index, other))
		(factions[index] as Dictionary)["relationships"] = relationships
	# Deliberately NO forced adversarial pair. An earlier version guaranteed one
	# rivalry per system on the theory that a system without enemies has no story
	# to hang a mission on. That theory is wrong: a faction's obstacle, triggering
	# event and unmet need are what generate work, and those exist whether or not
	# anyone is hostile. Scarcity, an accident and a dependency are all reasons to
	# hire someone. Forcing hostility made every system read the same way.


static func _relationship(
	scope: String,
	factions: Array,
	index: int,
	other: int
) -> Dictionary:
	var subject: Dictionary = factions[index]
	var object: Dictionary = factions[other]
	var pair_seed := "%s|%d->%d" % [scope, index, other]
	var kind := str(RELATIONSHIP_WEIGHTS[_digest(pair_seed, "kind") % RELATIONSHIP_WEIGHTS.size()])
	var band: Dictionary = RELATIONSHIP_KINDS[kind]
	var span: int = maxi(1, int(band["high"]) - int(band["low"]))
	var standing: int = int(band["low"]) + (_digest(pair_seed, "standing") % (span + 1))
	return {
		"faction_id": str(object.get("id", "")),
		"kind": kind,
		"standing": standing,
		# The reason cites an ACTUAL local fact -- the other party's desire,
		# obstacle or holdings -- rather than asserting a mood.
		"reason": _relationship_reason(kind, subject, object),
	}


static func _relationship_reason(
	kind: String,
	subject: Dictionary,
	object: Dictionary
) -> String:
	var subject_name := str(subject.get("display_name", "They"))
	var object_name := str(object.get("display_name", "the other outfit"))
	var subject_desire: Dictionary = subject.get("desire", {}) \
		if subject.get("desire", {}) is Dictionary else {}
	var object_desire: Dictionary = object.get("desire", {}) \
		if object.get("desire", {}) is Dictionary else {}
	var object_controls := str(object_desire.get("controls", "")).strip_edges()
	var object_goal := str(object_desire.get("goal", "")).strip_edges()
	var subject_need := str(subject_desire.get("need", "")).strip_edges()
	match kind:
		"dependency":
			if object_controls.is_empty():
				return "%s cannot work without %s." % [subject_name, object_name]
			return "%s depends on %s, who holds %s." % [subject_name, object_name, object_controls]
		"cooperation":
			return "%s and %s have been splitting the same shortage since it started." % [
				subject_name, object_name
			]
		"indifference":
			return "%s has no business with %s either way." % [subject_name, object_name]
		"friction":
			if subject_need.is_empty():
				return "%s blames %s for the delay." % [subject_name, object_name]
			return "%s blames %s for the hold-up on %s." % [subject_name, object_name, subject_need]
		_:
			if object_goal.is_empty():
				return "%s is competing directly with %s." % [subject_name, object_name]
			return "%s is trying to %s, which costs %s the same thing." % [
				object_name, object_goal, subject_name
			]
