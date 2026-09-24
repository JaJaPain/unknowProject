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
## INVESTIGATE_SIGNAL needs live site placement, so it comes back marked
## `premise_needs_completion: true`; the live adapter completes it with
## InvestigationOfferBuilder. Everything else is complete here.
##
## `world` is the same snapshot PremiseCasting uses, plus optionally:
##   store_items: Array[{item_id, display_name, quantity, station_id, store_display, base_price}]

const LibraryType := preload("res://scripts/story/premise/PremiseCardLibrary.gd")
const CastingType := preload("res://scripts/story/premise/PremiseCasting.gd")

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
			var faction_key := str(target.get("faction_key", target.get("entity_id", "")))
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
		"premise_private_fact": CastingType.fill_text(str(mission.get("private_fact", "")), cast, world),
		"premise_competing": bool(offer_ref.get("competing", false)),
	}
	if needs_completion:
		offer["premise_needs_completion"] = true
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
