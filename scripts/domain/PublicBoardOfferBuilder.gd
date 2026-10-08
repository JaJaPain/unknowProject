class_name PublicBoardOfferBuilder
extends RefCounted

const OreJobsType := preload("res://scripts/economy/OreJobs.gd")
const TEMPLATE_DELIVER_ORE := MissionTemplateRegistry.TEMPLATE_DELIVER_ORE_PUBLIC
const TEMPLATE_PICKUP_SPECIAL := MissionTemplateRegistry.TEMPLATE_PICKUP_SPECIAL_PUBLIC
const TEMPLATE_DELIVERY_COURIER := MissionTemplateRegistry.TEMPLATE_DELIVERY_COURIER_PUBLIC
const TEMPLATE_PURCHASE_DELIVERY := MissionTemplateRegistry.TEMPLATE_PURCHASE_DELIVERY_PUBLIC
const TEMPLATE_RECOVER_COMBAT_DROP := MissionTemplateRegistry.TEMPLATE_RECOVER_COMBAT_DROP
const StoreRegistryScript = preload("res://scripts/economy/StoreRegistry.gd")
const CausalCompilerType := preload(
	"res://scripts/domain/QuestCausalContractCompiler.gd"
)
const CausalContractType := preload("res://scripts/domain/QuestCausalContract.gd")
const GeneratedFactionDesireType := preload(
	"res://scripts/persistence/GeneratedFactionDesire.gd"
)
const PlausibilityType := preload(
	"res://scripts/domain/QuestPlausibilityValidator.gd"
)

const PART_NAMES: Array[String] = [
	"Sealed Actuator",
	"Nav Cache Brick",
	"Coolant Bypass Cap",
	"Audit-Proof Relay",
	"Unlabeled Heat Sink",
]
const COURIER_PACKAGE_NAMES: Array[String] = [
	"Sealed Evidence Tube",
	"Red-Tagged Med Case",
	"Uninsured Firmware Brick",
	"Quiet Little Black Box",
	"Customs-Adjacent Envelope",
]

static var story_config_override_for_tests: SystemConfig = null


## The board window being built; picks which faction's cause a job carries.
static var _board_time := 0


static func build_offers(current_time_minutes: int) -> Array[Dictionary]:
	_board_time = current_time_minutes
	var offers: Array[Dictionary] = []
	offers.append(_build_ore_offer(current_time_minutes))
	var fuel_offer := _build_fuel_offer(current_time_minutes)
	if not fuel_offer.is_empty():
		offers.append(fuel_offer)
	var block_offer := _build_fuel_block_offer(current_time_minutes)
	if not block_offer.is_empty():
		offers.append(block_offer)
	var o2_offer := _build_o2_offer(current_time_minutes)
	if not o2_offer.is_empty():
		offers.append(o2_offer)
	var fetch_offer := _build_fetch_offer(current_time_minutes)
	if not fetch_offer.is_empty():
		offers.append(fetch_offer)
	var pickup_offer := _build_pickup_offer(current_time_minutes)
	if not pickup_offer.is_empty():
		offers.append(pickup_offer)
	var courier_offer := _build_courier_offer(current_time_minutes)
	if not courier_offer.is_empty():
		offers.append(courier_offer)
	var purchase_offer := _build_purchase_offer(current_time_minutes)
	if not purchase_offer.is_empty():
		offers.append(purchase_offer)
	offers.append(_build_recovery_preview())
	_scale_pay_by_depth(offers)
	# Each card carries N.O.V.A.'s remark from the start (finding 7).
	for offer in offers:
		if offer.get("quest_data", {}) is Dictionary and not (offer["quest_data"] as Dictionary).is_empty():
			preload("res://scripts/story/MissionRemarks.gd").attach(offer["quest_data"])
	_withhold_invalid_offers(offers)
	_apply_story_intent_priority(offers)
	_apply_cooldowns(offers)
	return offers


## Deeper systems pay more (core loop step 6): the board's figure and the
## contract's reward together, so what's posted is what's paid.
static func _scale_pay_by_depth(offers: Array[Dictionary]) -> void:
	var factor: float = preload("res://scripts/domain/DepthScaling.gd").pay_factor(
		preload("res://scripts/domain/DepthScaling.gd").current_depth())
	if is_equal_approx(factor, 1.0):
		return
	for offer in offers:
		if offer.has("base_reward"):
			offer["base_reward"] = int(round(float(offer["base_reward"]) * factor))
		var quest: Dictionary = offer.get("quest_data", {}) if offer.get("quest_data", {}) is Dictionary else {}
		var objective: Dictionary = quest.get("objective", {}) if quest.get("objective", {}) is Dictionary else {}
		if objective.has("reward_credits"):
			objective["reward_credits"] = int(round(float(objective["reward_credits"]) * factor))


static func _apply_cooldowns(offers: Array[Dictionary]) -> void:
	var qm = Engine.get_singleton("QuestManager") if Engine.has_singleton("QuestManager") else null
	if qm == null:
		var tree := Engine.get_main_loop()
		if tree and tree.has_method("get_root") and tree.get_root():
			qm = tree.get_root().get_node_or_null("QuestManager")
	if qm == null:
		return
	for i in range(offers.size()):
		var tid: String = str(offers[i].get("template_id", ""))
		if tid.is_empty():
			continue
		if qm.is_board_template_on_cooldown(tid):
			offers[i]["enabled"] = false
			var remaining: int = qm.get_board_cooldown_remaining(tid)
			offers[i]["cooldown_remaining"] = remaining


static func _apply_story_intent_priority(offers: Array[Dictionary]) -> void:
	var intents: Array[String] = _story_mission_intents()
	if intents.is_empty() or offers.size() <= 1:
		return
	var prioritized: Array[Dictionary] = []
	var used_indexes: Array[int] = []
	for intent in intents:
		for index in range(offers.size()):
			if index in used_indexes:
				continue
			var offer: Dictionary = offers[index]
			if _offer_matches_intent(offer, intent):
				prioritized.append(offer)
				used_indexes.append(index)
				break
	for index in range(offers.size()):
		if index not in used_indexes:
			prioritized.append(offers[index])
	offers.clear()
	for offer in prioritized:
		offers.append(offer)


static func _offer_matches_intent(offer: Dictionary, intent: String) -> bool:
	var clean_intent := intent.strip_edges().to_lower()
	var template_id := str(offer.get("template_id", ""))
	match clean_intent:
		"ore", "mining", "resource":
			return template_id == TEMPLATE_DELIVER_ORE
		"pickup", "fetch", "handoff":
			return template_id == TEMPLATE_PICKUP_SPECIAL
		"delivery", "courier", "cargo":
			return template_id == TEMPLATE_DELIVERY_COURIER
		"purchase", "procurement", "store":
			return template_id == TEMPLATE_PURCHASE_DELIVERY
		"combat", "bounty", "recovery", "salvage":
			return template_id == TEMPLATE_RECOVER_COMBAT_DROP
	return false


static func _build_ore_offer(current_time_minutes: int) -> Dictionary:
	var amount := 35.0 + float((current_time_minutes / 60) % 3) * 5.0
	var base_reward := int(amount * 3.0)
	var duration_minutes := 180
	var urgent_multiplier := 1.5
	var story_note := _story_board_context("ore")
	# The ore, picked in code from this system's belts (playtest 2026-10-08
	# finding 5); the posting's own text says which (the story note is left
	# as written).
	var gs_for_ore: Node = _global_state()
	var local_mix: Dictionary = gs_for_ore.get("system_ore_mix") if gs_for_ore != null and gs_for_ore.get("system_ore_mix") is Dictionary else {"silicate": 1.0}
	var ore := OreJobsType.pick_local(local_mix, "board_ore|%d" % int(current_time_minutes / 60))
	var dialogue := OreJobsType.rewrite("Bring %d m3 of ore to the main station. The posting says the coolant is not supposed to steam. Nobody asked you to verify that." % int(amount), ore)
	var board_body := OreJobsType.rewrite("Bring ore before a supervisor learns thermodynamics.", ore)
	if not story_note.is_empty():
		dialogue += " Local note: %s" % story_note
		board_body += " Local note: %s" % story_note
	var objective := {
		"type": "DELIVER_ORE",
		"amount_required": amount,
		"reward_credits": base_reward,
		"ore_type": ore,
	}
	var quest_data := _quest_data(
		"Coolant Needed. Do Not Ask Why It Is Warm.",
		"neutral",
		"Public Board",
		dialogue,
		objective,
		{
			"timed": true,
			"urgent": true,
			"duration_minutes": duration_minutes,
			"expiration_policy": "expire",
			"urgent_reward_multiplier": urgent_multiplier,
		}
	)
	_attach_story_cause_metadata(quest_data, "ore")
	return _offer(
		TEMPLATE_DELIVER_ORE,
		true,
		"[URGENT] Coolant Needed. Do Not Ask Why It Is Warm.",
		"Definitely Licensed Dockhand",
		board_body,
		"%d m3 %s" % [int(amount), preload("res://scripts/economy/OreTypes.gd").display(ore)],
		base_reward,
		duration_minutes,
		urgent_multiplier,
		quest_data,
		["{ORE_AMOUNT}", "{TURN_IN_LOCATION}"],
		{
			"{ORE_AMOUNT}": "%d m3" % int(amount),
			"{TURN_IN_LOCATION}": "the main station",
		}
	)


## A fuel run (Abe): someone is short on fuel for a reason, and something
## happens if it does not arrive. The fuel comes out of the captain's tank
## (DELIVER_ORE with ore_type "fuel"); drawn from data/content/fuel_runs.json.
static func _build_fuel_offer(current_time_minutes: int) -> Dictionary:
	var deck := _fuel_run_deck()
	var groups: Array = deck.get("groups", [])
	var reasons: Array = deck.get("reasons", [])
	if groups.is_empty() or reasons.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("fuel_run|%d" % int(current_time_minutes / 120))
	var group: Dictionary = groups[rng.randi() % groups.size()]
	var reason := str(reasons[rng.randi() % reasons.size()])
	var stakes: Array = []
	for s in deck.get("stakes", []):
		var fits: Array = (s as Dictionary).get("for", [])
		if str(group.get("id", "")) in fits or "*" in fits:
			stakes.append(str(s.get("text", "")))
	var stake: String = str(stakes[rng.randi() % stakes.size()]) if not stakes.is_empty() else "they are in real trouble"
	var span: Array = deck.get("amount_range", [15, 35])
	var amount := float(rng.randi_range(int(span[0]), int(span[1])))
	var base_reward := int(round(amount * float(deck.get("pay_per_unit", 5.5))))
	var who := str(group.get("who", "someone here"))
	var title := str(group.get("title", "Fuel Run"))
	var dialogue := "%s is short on fuel: %s. If it doesn't arrive, %s. Bring %d units of fuel from your own tank." % [
		who.substr(0, 1).to_upper() + who.substr(1), reason, stake, int(amount)]
	var objective := {
		"type": "DELIVER_ORE",
		"amount_required": amount,
		"ore_type": "fuel",
		"reward_credits": base_reward,
	}
	var quest_data := _quest_data(title, "neutral", "Public Board", dialogue, objective, {
		"timed": true,
		"urgent": true,
		"duration_minutes": int(deck.get("duration_minutes", 240)),
		"expiration_policy": "expire",
		"urgent_reward_multiplier": float(deck.get("urgent_reward_multiplier", 1.4)),
	})
	var authored := _offer(
		TEMPLATE_DELIVER_ORE,
		true,
		"[URGENT] " + title,
		"Public Board",
		dialogue,
		"%d Fuel" % int(amount),
		base_reward,
		int(deck.get("duration_minutes", 240)),
		float(deck.get("urgent_reward_multiplier", 1.4)),
		quest_data,
		["{ORE_AMOUNT}", "{TURN_IN_LOCATION}"],
		{
			"{ORE_AMOUNT}": "%d fuel" % int(amount),
			"{TURN_IN_LOCATION}": "the main station",
		}
	)
	# Its own title and brief say fuel; the ore template text would call it
	# "16 fuel Ore" (Abe, 2026-09-28), so the text generator leaves it alone.
	authored["keep_authored_text"] = true
	return authored


## Fuel Blocks for a station's generators (item fuel_booster): fabricated here
## from water ice, never jumped in. The hand-in is the main station.
static func _build_fuel_block_offer(current_time_minutes: int) -> Dictionary:
	var deck: Dictionary = _fuel_run_deck().get("block_runs", {})
	var groups: Array = deck.get("groups", [])
	var reasons: Array = deck.get("reasons", [])
	if groups.is_empty() or reasons.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("fuel_blocks|%d" % int(current_time_minutes / 180))
	var group: Dictionary = groups[rng.randi() % groups.size()]
	var reason := str(reasons[rng.randi() % reasons.size()])
	var stakes: Array = []
	for s in deck.get("stakes", []):
		var fits: Array = (s as Dictionary).get("for", [])
		if str(group.get("id", "")) in fits or "*" in fits:
			stakes.append(str(s.get("text", "")))
	var stake: String = str(stakes[rng.randi() % stakes.size()]) if not stakes.is_empty() else "people here go without"
	var span: Array = deck.get("quantity_range", [4, 8])
	var quantity := rng.randi_range(int(span[0]), int(span[1]))
	var base_reward := quantity * int(deck.get("pay_per_block", 34))
	var station_id := _main_station_id()
	var station_display := _main_station_display()
	var who := str(group.get("who", "the station"))
	var title := str(group.get("title", "Fuel Blocks Needed"))
	var dialogue := "Fuel Blocks are running out for %s: %s. If they don't get more, %s. Bring %d Fuel Blocks to %s. They can't come through a gate, so they have to be fabricated here, from water ice." % [
		who, reason, stake, quantity, station_display]
	var gs = Engine.get_main_loop().root.get_node_or_null("GlobalState")
	if gs != null and float((gs.get("system_ore_mix") as Dictionary).get("water_ice", 0.0)) <= 0.0:
		dialogue += " There's no ice in this system's belts; it'll have to be hauled in."
	else:
		dialogue += " Ice is scarce in the belts: fly out to one and scan (C) to find it."
	var objective := {
		"type": "PURCHASE_DELIVERY",
		"item_id": "fuel_booster",
		"item_name": "Fuel Block",
		"quantity_required": quantity,
		"store_station_id": station_id,
		"store_display": station_display,
		"destination_station_id": station_id,
		"destination_display": station_display,
		"reward_credits": base_reward,
	}
	var quest_data := _quest_data(title, "neutral", "Public Board", dialogue, objective, {})
	var authored := _offer(
		TEMPLATE_PURCHASE_DELIVERY,
		true,
		"[POWER] " + title,
		"Public Board",
		dialogue,
		"%d Fuel Blocks to %s" % [quantity, station_display],
		base_reward,
		0,
		1.0,
		quest_data,
		["{QUANTITY}", "{ITEM_NAME}", "{STORE_LOCATION}", "{DESTINATION}"],
		{
			"{QUANTITY}": str(quantity),
			"{ITEM_NAME}": "Fuel Block",
			"{STORE_LOCATION}": station_display,
			"{DESTINATION}": station_display,
		}
	)
	# Its own title and brief say fuel; the ore template text would call it
	# "16 fuel Ore" (Abe, 2026-09-28), so the text generator leaves it alone.
	authored["keep_authored_text"] = true
	return authored


static var _fuel_deck_cache: Dictionary = {}


## O2 relief (Abe): an outpost's air is running short. Compress canisters from
## water ice at a station (Compress O2) and deliver them; data/content/o2_runs.json.
static func _build_o2_offer(current_time_minutes: int) -> Dictionary:
	var f := FileAccess.open("res://data/content/o2_runs.json", FileAccess.READ)
	if f == null:
		return {}
	var deck: Variant = JSON.parse_string(f.get_as_text())
	if not deck is Dictionary:
		return {}
	var groups: Array = deck.get("groups", [])
	var reasons: Array = deck.get("reasons", [])
	var gs = _global_state()
	if groups.is_empty() or reasons.is_empty() or gs == null or not gs.has_method("get_current_pickup_outposts"):
		return {}
	var outposts: Array = gs.get_current_pickup_outposts()
	if outposts.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("o2_run|%d" % int(current_time_minutes / 200))
	var group: Dictionary = groups[rng.randi() % groups.size()]
	var reason := str(reasons[rng.randi() % reasons.size()])
	var stakes: Array = []
	for st in deck.get("stakes", []):
		var fits: Array = (st as Dictionary).get("for", [])
		if str(group.get("id", "")) in fits or "*" in fits:
			stakes.append(str(st.get("text", "")))
	var stake: String = str(stakes[rng.randi() % stakes.size()]) if not stakes.is_empty() else "people there go without"
	var outpost: Dictionary = outposts[rng.randi() % outposts.size()]
	var dest_id := str(outpost.get("id", ""))
	var dest_display := str(outpost.get("display", dest_id))
	var span: Array = deck.get("quantity_range", [4, 10])
	var quantity := rng.randi_range(int(span[0]), int(span[1]))
	var base_reward := quantity * int(deck.get("pay_per_canister", 38))
	var station_display := _main_station_display()
	var title := str(group.get("title", "Outpost Needs Oxygen"))
	var dialogue := "Air is running short for %s at %s: %s. If it doesn't arrive, %s. Bring %d O2 canisters (%d L). Compress them from water ice at a station refinery (Compress O2); they are safe to carry through a gate." % [
		str(group.get("who", "the outpost")), dest_display, reason, stake, quantity, quantity * 10]
	var objective := {
		"type": "PURCHASE_DELIVERY",
		"item_id": "o2_canister",
		"item_name": "Compressed O2 Canister",
		"quantity_required": quantity,
		"store_station_id": _main_station_id(),
		"store_display": station_display,
		"destination_station_id": dest_id,
		"destination_display": dest_display,
		"reward_credits": base_reward,
	}
	var extra := {"timed": true, "urgent": true, "duration_minutes": int(deck.get("duration_minutes", 300)),
		"expiration_policy": "expire", "urgent_reward_multiplier": float(deck.get("urgent_reward_multiplier", 1.35))}
	var quest_data := _quest_data(title, "neutral", "Public Board", dialogue, objective, extra)
	var offer := _offer(
		TEMPLATE_PURCHASE_DELIVERY,
		true,
		"[LIFE SUPPORT] " + title,
		"Public Board",
		dialogue,
		"%d O2 canisters to %s" % [quantity, dest_display],
		base_reward,
		int(deck.get("duration_minutes", 300)),
		float(deck.get("urgent_reward_multiplier", 1.35)),
		quest_data,
		["{QUANTITY}", "{ITEM_NAME}", "{STORE_LOCATION}", "{DESTINATION}"],
		{"{QUANTITY}": str(quantity), "{ITEM_NAME}": "Compressed O2 Canister", "{STORE_LOCATION}": station_display, "{DESTINATION}": dest_display}
	)
	offer["keep_authored_text"] = true
	return offer


## Rare items a store actually sells, so a fetch job can be finished. Props
## join once the rarity / "where to find it" work places them (todo).
const FETCH_STOCKED_ITEMS := ["survey_drone", "thermal_lattice", "rad_quartz", "cryo_ferrite", "resonant_crystal", "antimatter_pod"]
static var _fetch_cards_cache: Array = []


## A fetch job from Gemini's approved cards (data/content/fetch_cards/approved):
## someone needs a rare item, for a reason, or something happens. Buy it at the
## main station and bring it to the requester at an outpost (or the station).
static func _build_fetch_offer(current_time_minutes: int) -> Dictionary:
	var cards := _fetch_cards()
	if cards.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("fetch|%d" % int(current_time_minutes / 240))
	var card: Dictionary = cards[rng.randi() % cards.size()]
	var item_id := str(card.get("item_id", ""))
	var item := _store_item(item_id)
	if item.is_empty() or not item_id in FETCH_STOCKED_ITEMS:
		# Props aren't sold: someone at an outpost has one (the hint is the
		# job itself: who and where), and it comes back to the station.
		return _build_fetch_pickup_offer(card, rng)
	var item_name := str(item.get("display_name", item_id))
	var station_id := _main_station_id()
	var station_display := _main_station_display()
	var dest_id := station_id
	var dest_display := station_display
	var gs = Engine.get_main_loop().root.get_node_or_null("GlobalState")
	if gs != null and gs.has_method("get_current_pickup_outposts"):
		var outposts: Array = gs.get_current_pickup_outposts()
		if not outposts.is_empty():
			var outpost: Dictionary = outposts[rng.randi() % outposts.size()]
			dest_id = str(outpost.get("id", station_id))
			dest_display = str(outpost.get("display", dest_id))
	var urgent := str(card.get("urgency", "days")) == "hours"
	var base_reward := int(round(float(item.get("base_price", 100)) * 1.35)) + 120
	var requester := str(card.get("requester", "a local"))
	var title := "%s Needed" % item_name
	var dialogue := "%s

Buy a %s at %s and bring it to %s." % [str(card.get("board_text", "")), item_name, station_display, dest_display]
	var objective := {
		"type": "PURCHASE_DELIVERY",
		"item_id": item_id,
		"item_name": item_name,
		"quantity_required": 1,
		"store_station_id": station_id,
		"store_display": station_display,
		"destination_station_id": dest_id,
		"destination_display": dest_display,
		"reward_credits": base_reward,
	}
	var extra := {}
	if urgent:
		extra = {"timed": true, "urgent": true, "duration_minutes": 360, "expiration_policy": "expire", "urgent_reward_multiplier": 1.3}
	var quest_data := _quest_data(title, "neutral", "Public Board", dialogue, objective, extra)
	var offer := _offer(
		TEMPLATE_PURCHASE_DELIVERY,
		true,
		("[URGENT] " if urgent else "") + title,
		requester.substr(0, 1).to_upper() + requester.substr(1),
		dialogue,
		"%s to %s" % [item_name, dest_display],
		base_reward,
		360 if urgent else 0,
		1.3 if urgent else 1.0,
		quest_data,
		["{QUANTITY}", "{ITEM_NAME}", "{STORE_LOCATION}", "{DESTINATION}"],
		{
			"{QUANTITY}": "1",
			"{ITEM_NAME}": item_name,
			"{STORE_LOCATION}": station_display,
			"{DESTINATION}": dest_display,
		}
	)
	offer["keep_authored_text"] = true
	offer["fetch_variant"] = str(card.get("variant", ""))
	offer["fetch_card_id"] = str(card.get("card_id", ""))
	return offer


## A prop fetch card as a pickup: "<npc> at <outpost> has one". Pay grows
## with the item's rarity (data/content/item_rarity.json).
static func _build_fetch_pickup_offer(card: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var gs = _global_state()
	if gs == null or not gs.has_method("get_current_pickup_outposts"):
		return {}
	var outposts: Array = gs.get_current_pickup_outposts()
	if outposts.is_empty():
		return {}
	var outpost: Dictionary = outposts[rng.randi() % outposts.size()]
	var outpost_id := str(outpost.get("id", ""))
	var outpost_display := str(outpost.get("display", outpost_id))
	var npcs: Array = gs.get_minor_npcs_at_outpost(outpost_id)
	if npcs.is_empty():
		return {}
	var holder := str(npcs[rng.randi() % npcs.size()])
	var item_id := str(card.get("item_id", ""))
	var item_name := _prop_name(item_id)
	if item_name.is_empty():
		return {}
	var rarity := float(_item_rarity().get(item_id, 3.5))
	var base_reward := int(round(120.0 + rarity * 70.0))
	var requester := str(card.get("requester", "a local"))
	var title := "%s Needed" % item_name
	var dialogue := "%s

Word is someone in the lounge at %s has one. Work out who, talk it out of them, and bring it back here." % [str(card.get("board_text", "")), outpost_display]
	var objective := {
		"type": "PICKUP_SPECIAL",
		"target_outpost": outpost_id,
		"target_outpost_display": outpost_display,
		"target_npc": holder,
		"lounge_hunt": true,
		"part_name": item_name,
		# The real hand-in: this system's main station (finding 14).
		"destination": preload("res://scripts/domain/QuestNextStep.gd").hand_in_name(),
		"reward_credits": base_reward,
	}
	var quest_data := _quest_data(title, "neutral", "Public Board", dialogue, objective, {})
	var offer := _offer(
		TEMPLATE_PICKUP_SPECIAL,
		true,
		title,
		requester.substr(0, 1).to_upper() + requester.substr(1),
		dialogue,
		"Find who has %s in the lounge at %s" % [item_name, outpost_display],
		base_reward,
		0,
		1.0,
		quest_data,
		["{ITEM_NAME}", "{PICKUP_LOCATION}"],
		{"{ITEM_NAME}": item_name, "{PICKUP_LOCATION}": outpost_display}
	)
	offer["keep_authored_text"] = true
	offer["fetch_variant"] = str(card.get("variant", ""))
	offer["fetch_card_id"] = str(card.get("card_id", ""))
	return offer


static var _rarity_cache: Dictionary = {}


static func _item_rarity() -> Dictionary:
	if _rarity_cache.is_empty():
		var f := FileAccess.open("res://data/content/item_rarity.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_rarity_cache = (parsed as Dictionary).get("rarity", {})
	return _rarity_cache


static func _prop_name(item_id: String) -> String:
	var f := FileAccess.open("res://data/content/prop_items.json", FileAccess.READ)
	if f == null:
		return ""
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for item in (parsed as Dictionary).get("items", []):
			if item is Dictionary and str(item.get("id", "")) == item_id:
				return str(item.get("name", item_id))
	return ""


static func _fetch_cards() -> Array:
	if _fetch_cards_cache.is_empty():
		var dir := DirAccess.open("res://data/content/fetch_cards/approved")
		if dir != null:
			for file_name in dir.get_files():
				if not file_name.ends_with(".json"):
					continue
				var f := FileAccess.open("res://data/content/fetch_cards/approved/" + file_name, FileAccess.READ)
				if f == null:
					continue
				var parsed: Variant = JSON.parse_string(f.get_as_text())
				if parsed is Dictionary:
					for card in (parsed as Dictionary).get("cards", []):
						if card is Dictionary:
							_fetch_cards_cache.append(card)
	return _fetch_cards_cache


static func _store_item(item_id: String) -> Dictionary:
	var f := FileAccess.open("res://data/content/store_items.json", FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for item in (parsed as Dictionary).get("items", []):
			if item is Dictionary and str(item.get("item_id", "")) == item_id:
				return item
	return {}


static func _fuel_run_deck() -> Dictionary:
	if _fuel_deck_cache.is_empty():
		var f := FileAccess.open("res://data/content/fuel_runs.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_fuel_deck_cache = parsed
	return _fuel_deck_cache


static func _build_pickup_offer(current_time_minutes: int) -> Dictionary:
	var gs = Engine.get_main_loop().root.get_node("GlobalState")
	var outposts: Array = gs.get_current_pickup_outposts()
	if outposts.is_empty():
		return {}
	var outpost_index := int(current_time_minutes / 45) % maxi(1, outposts.size())
	var outpost: Dictionary = outposts[outpost_index]
	var outpost_id := str(outpost.get("id", ""))
	var outpost_display := str(outpost.get("display", outpost_id))
	var npcs: Array = gs.get_minor_npcs_at_outpost(outpost_id)
	if npcs.is_empty():
		return {}
	var npc_name := str(npcs[int(current_time_minutes / 30) % npcs.size()])
	var part_name := PART_NAMES[int(current_time_minutes / 15) % PART_NAMES.size()]
	var base_reward := 130
	var story_note := _story_board_context("pickup")
	# A lounge hunt (Abe, 2026-10-03): the job never says who has it.
	var dialogue := "Someone in the lounge at %s is sitting on %s. Work out who and talk it out of them. If anyone asks why it has a warranty sticker over a bite mark, you did not see that." % [
		outpost_display,
		part_name,
	]
	var board_body := "Pickup job: find which lounge regular has it, then a suspicious return handoff."
	if not story_note.is_empty():
		dialogue += " Local note: %s" % story_note
		board_body += " Local note: %s" % story_note
	var objective := {
		"type": "PICKUP_SPECIAL",
		"target_outpost": outpost_id,
		"target_outpost_display": outpost_display,
		"target_npc": npc_name,
		"lounge_hunt": true,
		"part_name": part_name,
		# The real hand-in: this system's main station (finding 14).
		"destination": preload("res://scripts/domain/QuestNextStep.gd").hand_in_name(),
		"reward_credits": base_reward,
	}
	var quest_data := _quest_data(
		"Sealed Part Pickup, No Smelling The Package",
		"neutral",
		"Public Board",
		dialogue,
		objective,
		{}
	)
	_attach_story_cause_metadata(quest_data, "pickup")
	return _offer(
		TEMPLATE_PICKUP_SPECIAL,
		true,
		"[LOCAL] Sealed Part Pickup, No Smelling The Package",
		"Outpost Maintenance Account",
		board_body,
		"Find who has %s in the lounge at %s" % [
			part_name,
			outpost_display,
		],
		base_reward,
		0,
		1.0,
		quest_data,
		["{ITEM_NAME}", "{PICKUP_LOCATION}"],
		{
			"{ITEM_NAME}": part_name,
			"{PICKUP_LOCATION}": outpost_display,
		}
	)


static func _build_courier_offer(current_time_minutes: int) -> Dictionary:
	var gs = _global_state()
	if gs == null:
		return {}
	var outposts: Array = gs.get_current_pickup_outposts()
	if outposts.is_empty():
		return {}
	var outpost_index := int(current_time_minutes / 35) % maxi(1, outposts.size())
	var outpost: Dictionary = outposts[outpost_index]
	var destination_id := str(outpost.get("id", ""))
	var destination_display := str(outpost.get("display", destination_id))
	if destination_id.is_empty():
		return {}
	# Prefer cargo that IS the thing the local cause actually needs, so the
	# contract can state the link truthfully instead of asserting it. Falls back
	# to the generic package list when no local desire caused this posting -- and
	# the compiler then makes only the weaker claim it can support.
	var package_name := _need_bound_package("delivery")
	if package_name.is_empty():
		package_name = COURIER_PACKAGE_NAMES[
			int(current_time_minutes / 20) % COURIER_PACKAGE_NAMES.size()
		]
	var origin_id := _main_station_id()
	var origin_display := _main_station_display()
	var base_reward := 160
	var story_note := _story_board_context("delivery")
	var dialogue := "Carry %s from %s to %s. The seal is legally more important than your comfort." % [
		package_name,
		origin_display,
		destination_display,
	]
	var board_body := "Sealed courier job to %s. The package has opinions." % destination_display
	if not story_note.is_empty():
		dialogue += " Local note: %s" % story_note
		board_body += " Local note: %s" % story_note
	var objective := {
		"type": "DELIVERY_COURIER",
		"item_name": package_name,
		"origin_station_id": origin_id,
		"origin_display": origin_display,
		"destination_station_id": destination_id,
		"destination_display": destination_display,
		"reward_credits": base_reward,
	}
	var quest_data := _quest_data(
		"Sealed Courier Run, No Heroics",
		"neutral",
		"Public Board",
		dialogue,
		objective,
		{}
	)
	_attach_story_cause_metadata(quest_data, "delivery")
	return _offer(
		TEMPLATE_DELIVERY_COURIER,
		true,
		"[COURIER] Sealed Courier Run, No Heroics",
		"Logistics Account With A Nervous Tick",
		board_body,
		"Deliver %s to %s" % [package_name, destination_display],
		base_reward,
		0,
		1.0,
		quest_data,
		["{ITEM_NAME}", "{DESTINATION}"],
		{
			"{ITEM_NAME}": package_name,
			"{DESTINATION}": destination_display,
		}
	)


static func _build_purchase_offer(current_time_minutes: int) -> Dictionary:
	var item_info := _store_purchase_item(current_time_minutes)
	if item_info.is_empty():
		return {}
	var item_id := str(item_info.get("item_id", ""))
	var item_name := str(item_info.get("display_name", item_id))
	var quantity := int(item_info.get("quantity", 1))
	var store_station_id := str(item_info.get("station_id", _main_station_id()))
	var store_display := str(item_info.get("store_display", _main_station_display()))
	var destination_id := _main_station_id()
	var destination_display := _main_station_display()
	var base_reward := int(item_info.get("base_price", 20)) * quantity + 90
	var story_note := _story_board_context("purchase")
	var dialogue := "Buy %d %s from %s and bring it to %s. Yes, this is procurement with extra steps. That is most jobs if you squint." % [
		quantity,
		item_name,
		store_display,
		destination_display,
	]
	var board_body := "Purchase request for %s. Someone made enemies in retail." % item_name
	if not story_note.is_empty():
		dialogue += " Local note: %s" % story_note
		board_body += " Local note: %s" % story_note
	var objective := {
		"type": "PURCHASE_DELIVERY",
		"item_id": item_id,
		"item_name": item_name,
		"quantity_required": quantity,
		"store_station_id": store_station_id,
		"store_display": store_display,
		"destination_station_id": destination_id,
		"destination_display": destination_display,
		"reward_credits": base_reward,
	}
	var quest_data := _quest_data(
		"Purchase Request With Suspicious Receipts",
		"neutral",
		"Public Board",
		dialogue,
		objective,
		{}
	)
	_attach_story_cause_metadata(quest_data, "purchase")
	return _offer(
		TEMPLATE_PURCHASE_DELIVERY,
		true,
		"[PROCUREMENT] Purchase Request With Suspicious Receipts",
		"Expense Report Casualty",
		board_body,
		"Buy %d %s from %s" % [quantity, item_name, store_display],
		base_reward,
		0,
		1.0,
		quest_data,
		["{QUANTITY}", "{ITEM_NAME}", "{STORE_LOCATION}", "{DESTINATION}"],
		{
			"{QUANTITY}": str(quantity),
			"{ITEM_NAME}": item_name,
			"{STORE_LOCATION}": store_display,
			"{DESTINATION}": destination_display,
		}
	)


static func _build_recovery_preview() -> Dictionary:
	var base_reward := 840
	var target_faction := _story_recovery_target_faction()
	var target_faction_label := _story_faction_display(target_faction)
	var story_note := _story_board_context("recovery")
	var dialogue := "Search %s wreckage for the missing data pack. It gets logged automatically if you find it." % target_faction_label
	var board_body := "Recover a missing data pack from hostile wreckage. Legal says the courier is now a rounding error."
	if not story_note.is_empty():
		dialogue += " Local note: %s" % story_note
		board_body += " Local note: %s" % story_note
	var objective := {
		"type": TEMPLATE_RECOVER_COMBAT_DROP,
		"target_faction": target_faction,
		"count_required": 3,
		"drop_chance": 0.33,
		"item_name": "data pack",
		"turn_in_location": "main station",
		"reward_credits": base_reward,
	}
	var quest_data := _quest_data(
		"Courier Exploded. Data Survived. Probably.",
		"neutral",
		"Public Board",
		dialogue,
		objective,
		{}
	)
	_attach_story_cause_metadata(quest_data, "recovery")
	return _offer(
		TEMPLATE_RECOVER_COMBAT_DROP,
		true,
		"[RECOVERY] Courier Exploded. Data Survived. Probably.",
		"Dock 3 Claims Adjuster",
		board_body,
		"Search %s wreckage until the data pack turns up in the ship log." % target_faction_label,
		base_reward,
		0,
		1.0,
		quest_data,
		["{TARGET_FACTION}", "{ITEM_NAME}", "{TURN_IN_LOCATION}"],
		{
			"{TARGET_FACTION}": target_faction_label,
			"{ITEM_NAME}": "data pack",
			"{TURN_IN_LOCATION}": "the main station",
		}
	)


## Which faction's cause a job of this kind carries in this board window:
## every faction that wants it takes turns as the board refreshes (before,
## the first faction owned every job of that kind). {} when none.
static func _cause_for(offer_kind: String) -> Dictionary:
	var story_pack := _current_system_story_pack()
	var all: Array = story_pack.get("mission_causes_all", {}).get(offer_kind, [])
	if not all.is_empty():
		var window := int(_board_time / 240)
		return all[absi(hash("%s|%s|%d" % [str(story_pack.get("system_id", "")), offer_kind, window])) % all.size()]
	var causes: Dictionary = story_pack.get("mission_causes", {})
	return causes.get(offer_kind, {})


static func _story_board_context(_offer_kind: String) -> String:
	var story_pack := _current_system_story_pack()
	var picked := _cause_for(_offer_kind)
	if not picked.is_empty():
		return str(picked.get("public_because", ""))
	if story_pack.is_empty():
		return ""
	var seeds: Array = story_pack.get("mission_seeds", [])
	var seed_text := ""
	if not seeds.is_empty():
		var seed_index: int = abs(hash(str(story_pack.get("system_id", "")) + _offer_kind)) % seeds.size()
		seed_text = str(seeds[seed_index])
	var problem := str(story_pack.get("station_economy_problem", ""))
	var tension := str(story_pack.get("active_tension", ""))
	var resource := str(story_pack.get("resource_hook", ""))
	var parts: Array[String] = []
	if not seed_text.is_empty():
		parts.append(seed_text)
	if not problem.is_empty():
		parts.append(problem)
	if _offer_kind == "ore" and not resource.is_empty():
		parts.append(resource)
	elif not tension.is_empty():
		parts.append(tension)
	if parts.is_empty():
		return ""
	return "; ".join(parts).capitalize() + "."


static func _attach_story_cause_metadata(
	quest_data: Dictionary,
	offer_kind: String
) -> void:
	var metadata := _story_cause_metadata(offer_kind)
	if metadata.is_empty():
		return
	quest_data["narrative_metadata"] = metadata
	var hook := str(metadata.get("story_hook_ref", "")).strip_edges()
	if not hook.is_empty():
		quest_data["story_hook_ref"] = hook
	_attach_causal_contract(quest_data, metadata)


## Compile the causal contract for a board offer from the local faction data the
## system already holds. New invalid offers are withheld; accepted jobs use
## their persisted terms and never pass through this publication builder again.
static func _attach_causal_contract(
	quest_data: Dictionary,
	metadata: Dictionary
) -> void:
	var objective: Dictionary = quest_data.get("objective", {}) if quest_data.get("objective", {}) is Dictionary else {}
	if objective.is_empty():
		return
	var requester_id := str(metadata.get("cause_faction_id", "")).strip_edges()
	var agenda := _faction_agenda(requester_id)
	if _withhold_incoherent_desire(quest_data, agenda.get("desire", {})):
		return
	var contract := CausalCompilerType.compile({
		"campaign_id": _campaign_id(),
		"system_id": _current_system_id(),
		"objective": objective,
		"cause": metadata,
		"agenda": agenda,
		"requester_display": _faction_display_for_id(requester_id),
		"rival_display": _faction_display_for_id(
			str(metadata.get("cause_rival_faction_id", "")).strip_edges()
		),
		"recipient": _contract_recipient(objective),
		# Resolve the objective's raw faction KEY to a display name before it can
		# reach a player-visible fact.
		"target_faction_display": _local_faction_display(
			str(objective.get("target_faction", ""))
		),
		"delegation": _delegation_text(objective, requester_id),
		"reward_source": _reward_source_text(requester_id),
	})
	if not CausalContractType.is_present(contract):
		# Nothing local caused this job. That is a legitimate state -- the board
		# has always posted work nobody in particular wants done -- so it
		# publishes as an UNCAUSED offer rather than being withheld.
		quest_data["causal_publication_state"] = PUBLICATION_UNCAUSED
		return
	var report: Dictionary = PlausibilityType.check(contract, _plausibility_world())
	if not bool(report.get("ok", false)):
		# A contract that FAILS its checks is different: the mechanics or the
		# cause are wrong, and publishing it anyway is how an impossible job
		# reaches the player. New discretionary offers are withheld.
		_report_contract_rejection(quest_data, report)
		quest_data["causal_publication_state"] = PUBLICATION_WITHHELD
		quest_data["causal_withheld_issue_codes"] = report.get("issue_codes", [])
		return
	quest_data["narrative_metadata"]["causal_contract"] = contract
	quest_data["causal_contract"] = contract
	quest_data["causal_publication_state"] = PUBLICATION_VALIDATED


static func _withhold_incoherent_desire(quest_data: Dictionary, desire: Dictionary) -> bool:
	var coherence := GeneratedFactionDesireType.check_coherence(desire)
	if not bool(coherence.get("checked", false)) or bool(coherence.get("ok", false)):
		return false
	quest_data["causal_publication_state"] = PUBLICATION_WITHHELD
	quest_data["causal_withheld_issue_codes"] = coherence.get("errors", [])
	_report_contract_rejection(quest_data, {"issue_codes": coherence.get("errors", [])})
	return true


## How a built offer stands with respect to its causal contract.
##
## The distinction the integration review asked for: an offer with no local cause
## at all is fine and publishes; an offer whose contract FAILED validation has
## broken mechanics or an unbound cause and must not become a new discretionary
## job. Neither state touches missions the player has already accepted -- those
## are governed by their saved terms, not by today's generation rules.
const PUBLICATION_VALIDATED := "validated"
const PUBLICATION_UNCAUSED := "uncaused_legacy_compatible"
const PUBLICATION_WITHHELD := "withheld_invalid_contract"


## Remove offers whose causal contract failed validation.
##
## Deliberately applied to NEWLY BUILT board offers only. It never inspects or
## withdraws an accepted mission: an accepted job keeps its saved objective,
## recipient and terms and stays completable even if today's rules would no
## longer generate it.
static func _withhold_invalid_offers(offers: Array[Dictionary]) -> void:
	var kept: Array[Dictionary] = []
	for offer in offers:
		var quest_data: Dictionary = offer.get("quest_data", {}) \
			if offer.get("quest_data", {}) is Dictionary else {}
		if str(quest_data.get("causal_publication_state", "")) == PUBLICATION_WITHHELD:
			continue
		kept.append(offer)
	if kept.size() == offers.size():
		return
	offers.clear()
	for offer in kept:
		offers.append(offer)


## A rejected contract is a development signal AND a publication decision. The
## reason is recorded so a shortage of offers is visible rather than silent.
static func _report_contract_rejection(
	quest_data: Dictionary,
	report: Dictionary
) -> void:
	var diagnostics = _causal_generation_diagnostics()
	if diagnostics == null or not diagnostics.has_method("record_event"):
		return
	var codes: Array = report.get("issue_codes", [])
	diagnostics.call(
		"record_event",
		"mission_causal_contract",
		"contract_rejected",
		"public_board",
		{
			"title": str(quest_data.get("title", "")),
			"issue_codes": codes,
		}
	)


static func _causal_generation_diagnostics() -> Node:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("GenerationDiagnostics")


## The world snapshot the plausibility validator checks against. Keys that
## cannot be resolved are LEFT OUT rather than guessed, because a missing key
## means "unknown" to the validator and a wrong one means a false rejection.
static func _plausibility_world() -> Dictionary:
	var world := {
		"system_id": _current_system_id(),
	}
	var gs := _global_state()
	if gs == null:
		return world
	var station_ids: Array[String] = []
	var main_station := _main_station_id()
	if not main_station.is_empty():
		station_ids.append(main_station)
	if gs.has_method("get_current_pickup_outposts"):
		for raw_outpost in gs.call("get_current_pickup_outposts"):
			if not (raw_outpost is Dictionary):
				continue
			var outpost_id := str((raw_outpost as Dictionary).get("id", "")).strip_edges()
			if not outpost_id.is_empty() and outpost_id not in station_ids:
				station_ids.append(outpost_id)
	if not station_ids.is_empty():
		world["station_ids"] = station_ids
	return world


static func _campaign_id() -> String:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return ""
	var game_root := (loop as SceneTree).root.get_node_or_null("GameRoot")
	if game_root != null and "active_campaign_slot_id" in game_root:
		return str(game_root.get("active_campaign_slot_id"))
	return ""


## GlobalState is an autoload, so it may be absent in a headless fixture. A
## missing system id means "unknown" to the validator, which is correct.
static func _current_system_id() -> String:
	var gs := _global_state()
	if gs == null or not ("current_system_id" in gs):
		return ""
	return str(gs.get("current_system_id"))


static func _faction_agenda(faction_id: String) -> Dictionary:
	if faction_id.is_empty():
		return {}
	for raw_agenda in (_current_system_story_pack().get("faction_agendas", []) as Array):
		if not (raw_agenda is Dictionary):
			continue
		if str((raw_agenda as Dictionary).get("faction_id", "")) == faction_id:
			return (raw_agenda as Dictionary).duplicate(true)
	return {}


static func _faction_display_for_id(faction_id: String) -> String:
	if faction_id.is_empty():
		return ""
	return str(_faction_agenda(faction_id).get("faction_name", ""))


## Resolve a faction KEY to the name a person would actually say. Generated keys
## look like "gen_3753748b9ca0_f1"; `_story_faction_display` would title-case the
## hash and produce "3753748b9ca0 F1", which reached player-visible text before
## the compiled facts were printed and read. Returns empty rather than a
## prettified hash, and the compiler then omits the name entirely.
static func _local_faction_display(faction_key: String) -> String:
	var clean := faction_key.strip_edges()
	if clean.is_empty():
		return ""
	var config := _current_system_config()
	if config != null:
		var identities: Dictionary = config.faction_identities
		if identities.has(clean):
			var identity: Variant = identities[clean]
			if identity is Dictionary:
				var display := str((identity as Dictionary).get("display_name", "")).strip_edges()
				if not display.is_empty():
					return display
		for key in identities.keys():
			var record: Variant = identities[key]
			if not (record is Dictionary):
				continue
			var entry: Dictionary = record
			if str(entry.get("id", "")) != clean and str(entry.get("legacy_id", "")) != clean:
				continue
			var name := str(entry.get("display_name", "")).strip_edges()
			if not name.is_empty():
				return name
	# Tutorial factions have authored names; generated keys that got this far are
	# an unresolved hash and must not be shown.
	if clean in ["reavers", "obsidian", "dustborn", "wraiths", "ironclad", "zenith", "aurelia", "vanguard"]:
		return _story_faction_display(clean)
	return ""


## Only deliveries need one, and only a resident who is actually there counts.
static func _contract_recipient(objective: Dictionary) -> Dictionary:
	var objective_type := str(objective.get("type", "")).to_upper()
	if objective_type not in CausalCompilerType.DELIVERY_TYPES:
		return {}
	var destination := str(objective.get("destination_station_id", "")).strip_edges()
	if destination.is_empty():
		return {}
	var gs := _global_state()
	if gs == null or not gs.has_method("get_delivery_recipient"):
		return {}
	var recipient: Dictionary = gs.call("get_delivery_recipient", destination)
	if recipient.is_empty():
		return {}
	var resident_name := str(recipient.get("name", "")).strip_edges()
	return {
		"id": "npc.%s" % resident_name.to_lower().replace(" ", "_"),
		"name": resident_name,
		"role": str(recipient.get("delivery_role", "station_contact")),
		"station_id": destination,
		# Protected fixed cast are never reassigned as cargo recipients.
		"protected": resident_name in ["Kaelen", "N.O.V.A."],
	}


## Cargo that satisfies the recorded need behind this offer kind, or "" when no
## local desire caused it. The binding lives with the desire vocabulary so the
## generator and the compiler cannot disagree about what satisfies what.
static func _need_bound_package(offer_kind: String) -> String:
	var metadata := _story_cause_metadata(offer_kind)
	if metadata.is_empty():
		return ""
	var agenda := _faction_agenda(str(metadata.get("cause_faction_id", "")).strip_edges())
	var desire: Dictionary = agenda.get("desire", {}) 		if agenda.get("desire", {}) is Dictionary else {}
	var need := str(desire.get("need", "")).strip_edges()
	if need.is_empty():
		return ""
	return GeneratedFactionDesireType.item_for_need(need, str(desire.get("id", "")))


## Why this job is being handed to an outsider.
##
## The previous version invented a reason from the objective TYPE alone -- "no
## free hull", "no armed hull" -- without consulting what the faction actually
## holds or has available. That is a fabricated fact, and once it enters the
## contract it is indistinguishable from a verified one.
##
## Now it uses the faction's own recorded obstacle, which IS the reason. When no
## obstacle is recorded it returns empty, and the contract simply carries no
## delegation fact rather than a plausible-sounding invention.
static func _delegation_text(objective: Dictionary, requester_id: String) -> String:
	if objective.is_empty():
		return ""
	var agenda := _faction_agenda(requester_id)
	var desire: Dictionary = agenda.get("desire", {}) \
		if agenda.get("desire", {}) is Dictionary else {}
	var obstacle := str(desire.get("obstacle", "")).strip_edges()
	if obstacle.is_empty():
		return ""
	return "They are hiring it out because %s." % _lower_first_word(obstacle.trim_suffix("."))


static func _lower_first_word(text: String) -> String:
	if text.is_empty():
		return text
	var first := text.substr(0, 1)
	if first != first.to_upper():
		return text
	# Leave a proper noun alone.
	var words := text.split(" ", false)
	if words.size() > 1 and str(words[1]).length() > 0 \
			and str(words[1])[0] == str(words[1])[0].to_upper():
		return text
	return first.to_lower() + text.substr(1)


static func _reward_source_text(faction_id: String) -> String:
	var display := _faction_display_for_id(faction_id).strip_edges()
	if display.is_empty():
		return "The board escrows the fee before the job is posted."
	return "%s posts the fee against its own account before the job goes up." % display


static func _story_cause_metadata(offer_kind: String) -> Dictionary:
	var picked := _cause_for(offer_kind)
	if not picked.is_empty():
		return picked.duplicate(true)
	var because := ""
	var hook := ""
	var main_loop := Engine.get_main_loop()
	if main_loop != null and main_loop.has_method("get_root"):
		var manager = main_loop.root.get_node_or_null("StoryManager")
		if manager != null:
			if manager.has_method("get_current_because"):
				because = str(manager.call("get_current_because")).strip_edges()
			if manager.has_method("current_hook_ref"):
				hook = str(manager.call("current_hook_ref")).strip_edges()
	if because.is_empty():
		because = _story_board_context(offer_kind).strip_edges()
	if because.is_empty() and hook.is_empty():
		return {}
	var source_text := because if not because.is_empty() else hook
	return {
		"cause_id": "cause.public_board.%s" % source_text.sha256_text().substr(0, 12),
		"story_hook_ref": hook,
		"public_because": because,
	}


static func _story_mission_intents() -> Array[String]:
	var story_pack: Dictionary = _current_system_story_pack()
	if story_pack.is_empty():
		return []
	var raw_intents: Variant = story_pack.get("mission_intents", [])
	var result: Array[String] = []
	if raw_intents is Array:
		for item in raw_intents:
			var intent := str(item).strip_edges().to_lower()
			if not intent.is_empty() and intent not in result:
				result.append(intent)
	if not result.is_empty():
		return result
	var mission_seeds: Array = story_pack.get("mission_seeds", [])
	var seed_parts: Array[String] = []
	for seed in mission_seeds:
		seed_parts.append(str(seed))
	var seed_text: String = " ".join(seed_parts).to_lower()
	if seed_text.contains("supplies") or seed_text.contains("cargo"):
		result.append("delivery")
	if seed_text.contains("store") or seed_text.contains("buy"):
		result.append("purchase")
	if seed_text.contains("wreck") or seed_text.contains("recover"):
		result.append("recovery")
	if seed_text.contains("raider") or seed_text.contains("thin out"):
		result.append("combat")
	return result


static func _story_recovery_target_faction() -> String:
	var config := _current_system_config()
	if config == null or config.faction_weights.is_empty():
		return "reavers"
	var faction_keys: Array = config.faction_weights.keys()
	if faction_keys.is_empty():
		return "reavers"
	for faction_name in faction_keys:
		var clean_name := str(faction_name)
		if clean_name not in ["zenith", "aurelia", "vanguard"]:
			return clean_name
	return str(faction_keys[0])


static func _current_system_story_pack() -> Dictionary:
	var config := _current_system_config()
	if config == null:
		return {}
	return config.story_pack.duplicate(true)


static func _store_purchase_item(current_time_minutes: int) -> Dictionary:
	var registry = StoreRegistryScript.shared()
	var station_id := _main_station_id()
	var stores: Array = registry.get_stores_for_station(station_id)
	if stores.is_empty() and station_id != "haven":
		station_id = "haven"
		stores = registry.get_stores_for_station(station_id)
	if stores.is_empty():
		return {}
	var store = stores[0]
	var ids: Array = store.get_catalog_ids()
	var candidates: Array[String] = []
	for raw_id in ids:
		var item_id := str(raw_id)
		var item_def = registry.get_item(item_id)
		if item_def == null:
			continue
		if str(item_def.category) in ["trade_good", "ship_part", "novelty"]:
			candidates.append(item_id)
	if candidates.is_empty():
		return {}
	var selected_id := candidates[int(current_time_minutes / 25) % candidates.size()]
	var selected_def = registry.get_item(selected_id)
	return {
		"item_id": selected_id,
		"display_name": str(selected_def.display_name),
		"base_price": int(selected_def.base_price),
		"quantity": 1,
		"station_id": station_id,
		"store_display": _main_station_display(),
	}


static func _main_station_id() -> String:
	var gs = _global_state()
	if gs == null:
		return "haven"
	var current_system_id := str(gs.get("current_system_id"))
	return current_system_id if not current_system_id.is_empty() else "haven"


static func _main_station_display() -> String:
	var story_pack := _current_system_story_pack()
	var station_name := str(story_pack.get("station_name", ""))
	if not station_name.is_empty():
		return station_name
	var gs: Node = _global_state()
	if gs != null and str(gs.get("current_system_id")) != "start_system":
		var local_name := str(story_pack.get("local_nickname", ""))
		if not local_name.is_empty():
			return "%s Station" % local_name
	return "the main station"


static func _current_system_config() -> SystemConfig:
	if story_config_override_for_tests != null:
		return story_config_override_for_tests
	var main_loop := Engine.get_main_loop()
	if main_loop == null or not main_loop is SceneTree:
		return null
	var tree := main_loop as SceneTree
	var game_root = tree.current_scene
	if game_root == null:
		return null
	var registry = game_root.get("system_registry")
	if registry == null or not registry.has_method("get_generated_config"):
		return null
	var gs: Node = _global_state()
	if gs == null:
		return null
	return registry.get_generated_config(str(gs.current_system_id))


static func _global_state() -> Node:
	var main_loop := Engine.get_main_loop()
	if main_loop == null or not main_loop.has_method("get_root"):
		return null
	var root = main_loop.root
	if root == null:
		return null
	return root.get_node_or_null("GlobalState")


static func _story_faction_display(faction_name: String) -> String:
	var clean := faction_name.strip_edges()
	if clean == "reavers":
		return "Reaver"
	if clean == "obsidian":
		return "Obsidian"
	if clean == "dustborn":
		return "Dustborn"
	if clean == "wraiths":
		return "Wraith"
	if clean == "ironclad":
		return "Ironclad"
	if clean.begins_with("faction.generated."):
		clean = clean.trim_prefix("faction.generated.")
	elif clean.begins_with("faction."):
		clean = clean.trim_prefix("faction.")
	if clean.begins_with("gen_"):
		clean = clean.trim_prefix("gen_")
	var parts := clean.replace(".", "_").replace("-", "_").replace("_", " ").split(" ", false)
	var titled: Array[String] = []
	for part in parts:
		var lower := str(part).to_lower()
		if lower.length() <= 2 and lower.is_valid_int():
			continue
		titled.append(lower.substr(0, 1).to_upper() + lower.substr(1))
	if titled.is_empty():
		return "Local"
	return " ".join(titled)


static func _quest_data(
	title: String,
	faction: String,
	agent_name: String,
	dialogue: String,
	objective: Dictionary,
	timing: Dictionary
) -> Dictionary:
	var data := {
		"title": title,
		"faction": faction,
		"agent_name": agent_name,
		"dialogue": dialogue,
		"objective": objective,
		"objective_summary": _objective_summary(objective),
		"choices": [
			{
				"text": "Accept posting.",
				"consequence": {
					"credits_immediate": 0,
					"reputation_change": {},
					"combat_multiplier": 1.0,
					"reward_credits_multiplier": 1.0,
					"dialogue_response": "Posting accepted. Try not to make the paperwork interesting.",
				},
			},
		],
		"public_board": true,
	}
	if not timing.is_empty():
		data["timing"] = timing
	return data


static func _offer(
	template_id: String,
	enabled: bool,
	title: String,
	poster: String,
	body: String,
	objective_summary: String,
	base_reward: int,
	duration_minutes: int,
	urgent_multiplier: float,
	quest_data: Dictionary,
	required_placeholders: Array[String],
	placeholder_values: Dictionary
) -> Dictionary:
	var values := placeholder_values.duplicate(true)
	values["{POSTER_HANDLE}"] = poster
	var quest_metadata: Dictionary = quest_data.get("narrative_metadata", {}) \
		if quest_data.get("narrative_metadata", {}) is Dictionary else {}
	var story_pressure := str(quest_metadata.get("public_because", "")).strip_edges()
	if story_pressure.is_empty():
		story_pressure = str(quest_metadata.get("story_hook_ref", "")).strip_edges()
	values["{STORY_PRESSURE}"] = story_pressure
	return {
		"template_id": template_id,
		"enabled": enabled,
		"title": title,
		"poster": poster,
		"body": body,
		"objective": objective_summary,
		"base_reward": base_reward,
		"duration_minutes": duration_minutes,
		"urgent_multiplier": urgent_multiplier,
		"quest_data": quest_data,
		"required_placeholders": required_placeholders,
		"placeholder_values": values,
	}


static func _objective_summary(objective: Dictionary) -> String:
	match str(objective.get("type", "")):
		"DELIVER_ORE":
			var ore_name := "Ore"
			if str(objective.get("ore_type", "")) == "fuel":
				ore_name = "Fuel"
			elif not str(objective.get("ore_type", "")).is_empty():
				ore_name = preload("res://scripts/economy/OreTypes.gd").display(str(objective["ore_type"]))
			return "%d m3 %s" % [int(round(float(
				objective.get("amount_required", 0.0)
			))), ore_name]
		"PICKUP_SPECIAL":
			return "Pick up %s from %s at %s" % [
				str(objective.get("part_name", "the package")),
				str(objective.get("target_npc", "the contact")),
				str(objective.get("target_outpost_display", "the outpost")),
			]
		"DELIVERY_COURIER":
			return "Deliver %s to %s" % [
				str(objective.get("item_name", "the package")),
				str(objective.get("destination_display", "the destination")),
			]
		"PURCHASE_DELIVERY":
			return "Buy %d %s from %s" % [
				int(objective.get("quantity_required", 1)),
				str(objective.get("item_name", "the item")),
				str(objective.get("store_display", "the store")),
			]
		TEMPLATE_RECOVER_COMBAT_DROP:
			var target_display := _story_faction_display(
				str(objective.get("target_faction", "hostile"))
			)
			objective["target_faction_display"] = target_display
			return "Recover %s from %s wreckage" % [
				str(objective.get("item_name", "the data pack")),
				target_display,
			]
	return "Review posting details"
