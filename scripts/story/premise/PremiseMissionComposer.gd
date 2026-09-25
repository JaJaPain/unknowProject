class_name PremiseMissionComposer
extends RefCounted

## Turns one premise-card mission into an ordinary mission offer: the same
## dictionary shape StoryAgentOfferBuilder produces, so QuestManager,
## MissionAdapter, the board UI and saves all work unchanged.
##
## The offer carries its story identity in existing fields:
##   narrative_metadata.story_thread_id = arc id
##   narrative_metadata.story_beat_id   = "<card_id>:b<beat>:m<mission_index>"
##
## INVESTIGATE_SIGNAL becomes a real investigation (scan sites placed in
## space, evidence, branches) when the world carries `investigation_world`;
## the recipe follows the mission's wording. If no safe sites can be placed it
## falls back to collecting "Survey readings" at the site.
##
## `world` is the same snapshot PremiseCasting uses, plus optionally:
##   store_items: Array[{item_id, display_name, quantity, station_id, store_display, base_price}]
##   investigation_world: InvestigationWorldPlacement.capture() (stations, gates, hazards)

const LibraryType := preload("res://scripts/story/premise/PremiseCardLibrary.gd")
const CastingType := preload("res://scripts/story/premise/PremiseCasting.gd")
const SitePlannerType := preload("res://scripts/domain/InvestigationSitePlanner.gd")
const InvestigationBuilderType := preload("res://scripts/domain/InvestigationOfferBuilder.gd")
const InvestigationPlacementType := preload("res://scripts/domain/InvestigationWorldPlacement.gd")
const ComplicationsType := preload("res://scripts/story/premise/MissionComplications.gd")
const TwistsType := preload("res://scripts/story/premise/MissionTwists.gd")
const NameForgeType := preload("res://scripts/story/premise/NameForge.gd")
const InvestigationValidatorType := preload("res://scripts/domain/InvestigationStateValidator.gd")
const ShapesType := preload("res://scripts/domain/MissionShapeRegistry.gd")

## Which investigation a card mission becomes, from words in its reason.
const RECIPE_WORDS := {
	"transmitter_lure": ["signal", "beacon", "transmission", "transmitter", "frequency", "broadcast", "distress"],
	"unstable_archive": ["record", "records", "archive", "archives", "log", "logs", "recorder", "data", "files", "black box", "ledger"],
	"competing_claims": ["claim", "claims", "ownership", "salvage rights", "owner", "deed"],
}
static var _shapes = null

const BASE_REWARD := {
	"kill_ships": 420, "comms_reversal": 620, "recover_combat_drop": 520, "deliver_ore": 300,
	"delivery_courier": 220, "purchase_delivery": 140, "pickup_special": 260, "investigate_signal": 380,
}
const SCALE_REWARD := {"personal": 0.9, "local": 1.0, "regional": 1.3}
const SCALE_KILLS := {"personal": 2, "local": 3, "regional": 4}
const SCALE_ORE := {"personal": 15.0, "local": 20.0, "regional": 30.0}
const BEAT_REWARD_STEP := 0.1


## Returns the offer dictionary, or {} if the mission can't be composed here.
static func compose(offer_ref: Dictionary, card: Dictionary, cast: Dictionary, world: Dictionary, seed_value: int) -> Dictionary:
	var mission: Dictionary = offer_ref.get("mission", {})
	var verb := str(mission.get("verb", ""))
	var beat_n := int(offer_ref.get("beat", 1))
	var mission_index := int(offer_ref.get("mission_index", 0))
	var scale := str(card.get("scale", "local"))
	var reward := int(round(float(BASE_REWARD.get(verb, 300)) * float(SCALE_REWARD.get(scale, 1.0)) * (1.0 + BEAT_REWARD_STEP * float(beat_n - 1))))
	var target: Dictionary = cast.get(str(mission.get("target", "")), {})
	var requester: Dictionary = cast.get(str(mission.get("requester", "")), {})
	var main: Dictionary = world.get("main_station", {"id": str(world.get("system_id", "start_system")), "display": "the main station"})
	var item := _item_name(card, cast, mission)

	var objective := {}
	var needs_completion := false
	match verb:
		"kill_ships", "comms_reversal", "recover_combat_drop":
			# Only spawnable keys: a ship's faction_key, or a targeted faction's spawn_key.
			var faction_key := str(target.get("faction_key", target.get("spawn_key", "")))
			if faction_key.is_empty():
				faction_key = _first_hostile(world)
			objective = {"type": LibraryType.VERB_TO_OBJECTIVE[verb], "target_faction": faction_key,
				"count_required": int(SCALE_KILLS.get(scale, 3)), "reward_credits": reward}
			if verb == "recover_combat_drop":
				objective["drop_chance"] = 0.4
				objective["item_name"] = item
				objective["turn_in_location"] = str(main.get("display", "the main station"))
		"deliver_ore":
			objective = {"type": "DELIVER_ORE", "amount_required": float(SCALE_ORE.get(scale, 20.0)),
				"ore_type": str(mission.get("ore", "silicate")), "reward_credits": reward}
		"delivery_courier":
			objective = _courier(item, main, target, reward)
		"purchase_delivery":
			var stock: Array = world.get("store_items", [])
			if stock.is_empty():
				objective = _courier(item, main, target, reward)
			else:
				var pick: Dictionary = stock[abs(hash("%d|%s|%d" % [seed_value, card.get("id", ""), mission_index])) % stock.size()]
				objective = {"type": "PURCHASE_DELIVERY", "item_id": str(pick.get("item_id", "")),
					"item_name": str(pick.get("display_name", pick.get("item_id", ""))), "quantity_required": int(pick.get("quantity", 1)),
					"store_station_id": str(pick.get("station_id", main.get("id", ""))), "store_display": str(pick.get("store_display", main.get("display", ""))),
					"destination_station_id": str(target.get("entity_id", main.get("id", ""))),
					"destination_display": str(target.get("display_name", main.get("display", ""))),
					"reward_credits": int(pick.get("base_price", 20)) + reward}
		"pickup_special":
			objective = {"type": "PICKUP_SPECIAL", "target_outpost": str(target.get("entity_id", main.get("id", ""))),
				"target_outpost_display": str(target.get("display_name", main.get("display", ""))),
				"target_npc": str(requester.get("display_name", "a local contact")), "part_name": item,
				"destination": str(main.get("display", "the main station")), "reward_credits": reward}
		"investigate_signal":
			var real := _investigation_objective(offer_ref, card, cast, world, mission, target, main, reward, seed_value)
			if not real.is_empty():
				objective = real
			elif bool(world.get("investigation_fallback", false)) or world.has("investigation_world"):
				# No safe scan sites here (or no live world): collect the readings
				# at the site instead; the arc then asks for the finding.
				objective = {"type": "PICKUP_SPECIAL", "target_outpost": str(target.get("entity_id", main.get("id", ""))),
					"target_outpost_display": str(target.get("display_name", main.get("display", ""))),
					"target_npc": str(requester.get("display_name", "a local contact")), "part_name": "Survey readings",
					"destination": str(main.get("display", "the main station")), "reward_credits": reward}
			else:
				objective = {"type": "INVESTIGATE_SIGNAL", "reward_credits": reward, "site_target_id": str(target.get("entity_id", "")),
					"site_display": str(target.get("display_name", "")), "turn_in_station_id": str(main.get("id", ""))}
				needs_completion = true
		_:
			return {}

	var faction_entity := _requester_faction(card, cast)
	var arc_id := str(offer_ref.get("arc_id", ""))
	var beat_id := "%s:b%d:m%d" % [str(card.get("id", "")), beat_n, mission_index]
	var reason := CastingType.fill_text(str(mission.get("reason", "")), cast, world)
	var offer := {
		"title": _title(verb, target, item, mission),
		"faction": faction_entity,
		"agent_name": str(requester.get("display_name", "Local Contact")),
		"agent_role": str(requester.get("archetype", "contact")).replace("_", " "),
		"agent_id": str(requester.get("entity_id", "")),
		"dialogue": reason,
		"objective": objective,
		"choices": [_accept_choice()],
		"narrative_metadata": {"story_thread_id": arc_id, "story_beat_id": beat_id,
			"public_because": CastingType.fill_text(str(LibraryType.beat(card, beat_n).get("public_change", "")), cast, world)},
		"story_thread_id": arc_id,
		"story_beat_id": beat_id,
		"premise_card_id": str(card.get("id", "")),
		"premise_requester_role": str(mission.get("requester", "")),
		"premise_private_fact": CastingType.fill_text(str(mission.get("private_fact", "")), cast, world),
		"premise_competing": bool(offer_ref.get("competing", false)),
	}
	if needs_completion:
		offer["premise_needs_completion"] = true
	# Layer 4: some kill jobs turn mid-mission (a counter-offer or a
	# surrender). A card's own comms-reversal mission is a counter-offer by
	# design, so it always gets one (with a real bribe and hail line).
	var twist := {}
	if verb == "comms_reversal":
		for t in TwistsType.deck().get("twists", []):
			if str(t.get("id", "")) == "counter_offer":
				twist = (t as Dictionary).duplicate(true)
				var hails: Array = twist.get("hails", [])
				twist["hail"] = str(hails[abs(hash(beat_id)) % hails.size()]) if not hails.is_empty() else ""
	else:
		twist = TwistsType.roll(verb, "%d|%s" % [seed_value, beat_id], not str(offer.get("premise_private_fact", "")).strip_edges().is_empty())
	if not twist.is_empty():
		# A rival on the job is someone the captain may have met before (the
		# recurring cast), else a new name.
		var rivals: Array = world.get("rival_candidates", [])
		var rival_name := ""
		if not rivals.is_empty():
			rival_name = str((rivals[abs(hash(beat_id)) % rivals.size()] as Dictionary).get("display_name", ""))
		if rival_name.is_empty():
			var name_rng := RandomNumberGenerator.new()
			name_rng.seed = hash("rival|" + beat_id)
			rival_name = NameForgeType.person_name(name_rng)
		offer = TwistsType.apply(offer, twist, str(requester.get("display_name", "")), str(target.get("display_name", "")),
			{"private_fact": str(offer.get("premise_private_fact", "")), "rival_name": rival_name})
	# Layer 3: about half the jobs come with a complication that changes how
	# they play (seeded per mission, so a reload never rerolls it).
	var complication := ComplicationsType.roll(verb, world.get("quirks", []), "%d|%s" % [seed_value, beat_id])
	offer = ComplicationsType.apply(offer, complication, str(requester.get("display_name", "")))
	return offer


static func _courier(item: String, main: Dictionary, target: Dictionary, reward: int) -> Dictionary:
	var dest_id := str(target.get("entity_id", ""))
	var dest_display := str(target.get("display_name", ""))
	if dest_id.is_empty() or dest_id == str(main.get("id", "")):
		dest_display = dest_display if not dest_display.is_empty() else str(main.get("display", ""))
		dest_id = dest_id if not dest_id.is_empty() else str(main.get("id", ""))
	return {"type": "DELIVERY_COURIER", "item_name": item,
		"origin_station_id": str(main.get("id", "")), "origin_display": str(main.get("display", "")),
		"destination_station_id": dest_id, "destination_display": dest_display, "reward_credits": reward}


## The cargo a mission is about: an object role named in the reason, else the card's first object, else a generic.
static func _item_name(card: Dictionary, cast: Dictionary, mission: Dictionary) -> String:
	var reason := str(mission.get("reason", "")).to_lower()
	var first_object := ""
	for role in card.get("roles", []):
		if str(role.get("kind", "")) != "object":
			continue
		var name := str(cast.get(str(role["id"]), {}).get("display_name", ""))
		if first_object.is_empty():
			first_object = name
		if not name.is_empty() and reason.contains(name.to_lower()):
			return name.capitalize()
	return first_object.capitalize() if not first_object.is_empty() else "Sealed cargo"


static func _requester_faction(card: Dictionary, cast: Dictionary) -> String:
	for role in card.get("roles", []):
		if str(role.get("kind", "")) == "faction":
			var entity := str(cast.get(str(role["id"]), {}).get("entity_id", ""))
			if not entity.is_empty():
				return entity
	return "neutral"


static func _first_hostile(world: Dictionary) -> String:
	var hostile: Array = world.get("hostile_factions", [])
	return str(hostile[0]) if not hostile.is_empty() else "reavers"


static func _title(verb: String, target: Dictionary, item: String, mission: Dictionary) -> String:
	var who := str(target.get("display_name", "")).trim_prefix("the ").trim_prefix("The ")
	match verb:
		"kill_ships":
			return "Stop %s" % who if not who.is_empty() else "Clear the lane"
		"comms_reversal":
			return "Intercept %s" % who if not who.is_empty() else "Intercept"
		"recover_combat_drop":
			return "Recover %s" % item.to_lower()
		"deliver_ore":
			return "%s for %s" % [str(mission.get("ore", "silicate")).replace("_", " ").capitalize(), who]
		"delivery_courier":
			return "Courier to %s" % who
		"purchase_delivery":
			return "Supply run to %s" % who
		"pickup_special":
			return "Pickup at %s" % who
		"investigate_signal":
			return "Survey at %s" % who
	return "Contract"


static func _accept_choice() -> Dictionary:
	return {"text": "Accept contract.", "consequence": {"credits_immediate": 0, "reputation_change": {},
		"combat_multiplier": 1.0, "reward_credits_multiplier": 1.0, "dialogue_response": "Good. I'll send the details now."}}


## A real investigation for a card mission, or {} (no world data, or no safe
## sites): scan sites around the target (else the main station), turned in at
## the main station.
static func _investigation_objective(offer_ref: Dictionary, card: Dictionary, cast: Dictionary, world: Dictionary,
		mission: Dictionary, target: Dictionary, main: Dictionary, reward: int, seed_value: int) -> Dictionary:
	var inv_world: Dictionary = world.get("investigation_world", {})
	if not bool(inv_world.get("ok", false)):
		return {}
	var recipe := recipe_for(str(mission.get("reason", "")), cast)
	if _shapes == null:
		_shapes = ShapesType.new()
		if not _shapes.load_from_path().is_valid():
			_shapes = null
			return {}
	var shape = _shapes.shape_for_recipe(recipe)
	if shape == null:
		return {}
	# Anchor at the story's place if it is a station here, else the main station.
	var anchors: Array = []
	var main_station_id := str(main.get("station_id", main.get("id", "")))
	var wanted := [str(target.get("entity_id", "")), main_station_id, str(main.get("id", ""))]
	for want in wanted:
		for station: Dictionary in inv_world.get("stations", []):
			if want in station.get("ids", [station.get("id", "")]) and not anchors.has(station):
				anchors.append(station)
	if anchors.is_empty():
		return {}
	var beat_n := int(offer_ref.get("beat", 1))
	var mission_id := "premise.%s.b%d.m%d" % [str(offer_ref.get("arc_id", "arc")).replace(".", "_"), beat_n, int(offer_ref.get("mission_index", 0))]
	var inv_seed: int = abs(hash("%d|%s" % [seed_value, mission_id]))
	var placement := SitePlannerType.plan_sites(inv_seed, anchors, inv_world.get("hazards", []), inv_world.get("gates", []))
	if not bool(placement.get("ok", false)):
		return {}
	var branches: Array = (shape.branch_ids as Array).duplicate()
	branches.erase("liquidate")  # a client seeking evidence has not funded its destruction
	var claimants: Array = []
	for entity: Dictionary in cast.values():
		if str(entity.get("kind", "")) == "faction":
			claimants.append(str(entity.get("entity_id", "")))
	var built := InvestigationBuilderType.build_objective(mission_id, {"id": str(shape.id), "recipe": recipe, "branch_ids": branches},
		inv_seed, placement, reward, main_station_id, claimants, str(inv_world.get("system_id", "")))
	if not bool(built.get("ok", false)):
		return {}
	var objective: Dictionary = built["objective"]
	objective["system_id"] = str(inv_world.get("system_id", ""))
	objective["site_display"] = str(target.get("display_name", main.get("display", "")))
	if not InvestigationValidatorType.validate(objective).is_valid():
		return {}
	if not bool(InvestigationPlacementType.check_saved_sites(objective, inv_world).get("ok", false)):
		return {}
	return objective


## The investigation recipe a mission reason calls for, among the recipes the
## game can actually run (InvestigationStateValidator.BRANCHES: all four since
## 2026-09-24). Competing claims needs two factions to be claimants.
static func recipe_for(reason: String, cast: Dictionary) -> String:
	var text := reason.to_lower()
	var factions := cast.values().filter(func(e): return str(e.get("kind", "")) == "faction").size()
	for recipe in ["transmitter_lure", "unstable_archive", "competing_claims"]:
		if not InvestigationValidatorType.BRANCHES.has(recipe):
			continue
		if recipe == "competing_claims" and factions < 2:
			continue
		for word in RECIPE_WORDS[recipe]:
			if (" %s " % text.replace(".", " ").replace(",", " ")).contains(" %s " % word):
				return recipe
	return "survey_discrepancy"
