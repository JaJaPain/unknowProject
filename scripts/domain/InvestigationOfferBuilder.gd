class_name InvestigationOfferBuilder
extends RefCounted

## Builds an INVESTIGATE_SIGNAL objective (plan P2).
##
## TRUTH IS GENERATED HERE, IN CODE, FROM THE SEED -- never by a model, and never
## rerolled once the offer is accepted. Route codes, forged status and recorder
## ownership are mission facts the player is asked to determine; if a generated
## label could overwrite them, the evidence the player gathers would stop
## agreeing with the answer they are graded against.
##
## Pure: no scene access, no globals. The caller supplies the placed sites, the
## approved reward budget and the candidate claimant factions.

const PlannerType := preload("res://scripts/domain/InvestigationSitePlanner.gd")

const CODE_A := "A"
const CODE_B := "B"


## `sites` comes from InvestigationSitePlanner.plan_sites().
## `budget` is the already-approved offer reward; it is mirrored, never invented.
static func build_objective(
	mission_id: String,
	shape: Dictionary,
	seed_value: int,
	placement: Dictionary,
	budget: int,
	turn_in_station_id: String,
	claimant_faction_ids: Array = []
) -> Dictionary:
	if not bool(placement.get("ok", false)):
		return {"ok": false, "reason": str(placement.get("reason", "no_safe_sites"))}
	var recipe := str(shape.get("recipe", ""))
	var rng := RandomNumberGenerator.new()
	# Offset the stream so truth does not correlate with placement, which drew
	# from the same seed.
	rng.seed = seed_value ^ 0x5F37
	var sites := _build_sites(mission_id, recipe, rng, placement, claimant_faction_ids)
	var site_ids: Array[String] = []
	for site in sites:
		site_ids.append(str(site["id"]))

	var investigation := {
		"version": 1,
		"mission_id": mission_id,
		"recipe": recipe,
		"seed": seed_value,
		"phase": "search",
		"scanned_site_ids": [],
		"evidence": [],
		"branch_id": "",
		"outcome_tag": "",
		"payout_numerator": 1,
		"payout_denominator": 1,
		"consumable_spent": false,
		"hostile_spawned": false,
		"hostile_id": "",
		"outcome_event_id": "",
		"investigation_revision": 0,
		"applied_commands": {},
		"sites": sites,
		"search_center": placement.get("search_center", [0.0, 0.0, 0.0]),
		"search_radius": float(placement.get("search_radius", PlannerType.SEARCH_RADIUS)),
		# Derived once, here, so nothing downstream has to re-derive it from the
		# codes and risk disagreeing about what "forged" meant.
		"forged": _is_forged(recipe, sites),
	}
	return {
		"ok": true,
		"objective": {
			"type": "INVESTIGATE_SIGNAL",
			"shape_id": str(shape.get("id", "")),
			"recipe": recipe,
			"branch_ids": shape.get("branch_ids", []),
			"mission_site_ids": site_ids,
			"turn_in_station_id": turn_in_station_id,
			"reward_credits": budget,
			"investigation": investigation,
		},
	}


## The primary always reports A. The verification site is the coin flip, and its
## meaning depends on the recipe: equality means "codes match" for a survey and
## "beacon genuine" for a lure.
static func _build_sites(
	mission_id: String,
	recipe: String,
	rng: RandomNumberGenerator,
	placement: Dictionary,
	claimant_faction_ids: Array
) -> Array:
	var placed: Array = placement.get("sites", [])
	var out: Array = []
	var uses_codes := recipe in ["survey_discrepancy", "transmitter_lure"]
	var second_code := CODE_A if rng.randi() % 2 == 0 else CODE_B
	var owner := ""
	if recipe == "competing_claims" and claimant_faction_ids.size() >= 2:
		owner = str(claimant_faction_ids[rng.randi() % claimant_faction_ids.size()])

	for entry in placed:
		if not entry is Dictionary:
			continue
		var site: Dictionary = (entry as Dictionary).duplicate(true)
		var role := str(site.get("role", ""))
		site["id"] = "%s.site.%s" % [mission_id, role]
		site["code"] = ""
		site["owner_faction_id"] = ""
		if uses_codes:
			site["code"] = CODE_A if role == "primary" else second_code
		# Only the verification site names an owner; the primary deliberately
		# leaves it empty so the player must travel to learn it.
		if recipe == "competing_claims" and role == "verification":
			site["owner_faction_id"] = owner
		out.append(site)
	return out


static func _is_forged(recipe: String, sites: Array) -> bool:
	if recipe != "transmitter_lure":
		return false
	var primary := ""
	var verification := ""
	for raw in sites:
		if not raw is Dictionary:
			continue
		var site: Dictionary = raw
		if str(site.get("role", "")) == "primary":
			primary = str(site.get("code", ""))
		elif str(site.get("role", "")) == "verification":
			verification = str(site.get("code", ""))
	return primary != verification
