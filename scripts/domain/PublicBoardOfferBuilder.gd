class_name PublicBoardOfferBuilder
extends RefCounted

const TEMPLATE_DELIVER_ORE := MissionTemplateRegistry.TEMPLATE_DELIVER_ORE_PUBLIC
const TEMPLATE_PICKUP_SPECIAL := MissionTemplateRegistry.TEMPLATE_PICKUP_SPECIAL_PUBLIC
const TEMPLATE_RECOVER_COMBAT_DROP := MissionTemplateRegistry.TEMPLATE_RECOVER_COMBAT_DROP

const PART_NAMES: Array[String] = [
	"Sealed Actuator",
	"Nav Cache Brick",
	"Coolant Bypass Cap",
	"Audit-Proof Relay",
	"Unlabeled Heat Sink",
]


static func build_offers(current_time_minutes: int) -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	offers.append(_build_ore_offer(current_time_minutes))
	offers.append(_build_pickup_offer(current_time_minutes))
	offers.append(_build_recovery_preview())
	_apply_cooldowns(offers)
	return offers


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


static func _build_ore_offer(current_time_minutes: int) -> Dictionary:
	var amount := 35.0 + float((current_time_minutes / 60) % 3) * 5.0
	var base_reward := int(amount * 3.0)
	var duration_minutes := 180
	var urgent_multiplier := 1.5
	var objective := {
		"type": "DELIVER_ORE",
		"amount_required": amount,
		"reward_credits": base_reward,
	}
	var quest_data := _quest_data(
		"Coolant Needed. Do Not Ask Why It Is Warm.",
		"neutral",
		"Public Board",
		"Bring %d m3 of ore to the main station. The posting says the coolant is not supposed to steam. Nobody asked you to verify that." % int(amount),
		objective,
		{
			"timed": true,
			"urgent": true,
			"duration_minutes": duration_minutes,
			"expiration_policy": "expire",
			"urgent_reward_multiplier": urgent_multiplier,
		}
	)
	return _offer(
		TEMPLATE_DELIVER_ORE,
		true,
		"[URGENT] Coolant Needed. Do Not Ask Why It Is Warm.",
		"Definitely Licensed Dockhand",
		"Bring ore before a supervisor learns thermodynamics.",
		"%d m3 Ore" % int(amount),
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


static func _build_pickup_offer(current_time_minutes: int) -> Dictionary:
	var outpost_ids: Array = GlobalState.PICKUP_OUTPOST_IDS
	var outpost_index := int(current_time_minutes / 45) % maxi(1, outpost_ids.size())
	var outpost_id := str(outpost_ids[outpost_index])
	var outpost_display := str(
		GlobalState.PICKUP_OUTPOST_DISPLAY.get(outpost_id, outpost_id)
	)
	var npcs := GlobalState.get_minor_npcs_at_outpost(outpost_id)
	var npc_name := "Local Contact"
	if not npcs.is_empty():
		npc_name = str(npcs[int(current_time_minutes / 30) % npcs.size()])
	var part_name := PART_NAMES[int(current_time_minutes / 15) % PART_NAMES.size()]
	var base_reward := 130
	var objective := {
		"type": "PICKUP_SPECIAL",
		"target_outpost": outpost_id,
		"target_outpost_display": outpost_display,
		"target_npc": npc_name,
		"part_name": part_name,
		"destination": "Grease Monkeys",
		"reward_credits": base_reward,
	}
	var quest_data := _quest_data(
		"Sealed Part Pickup, No Smelling The Package",
		"neutral",
		"Public Board",
		"Pick up %s from %s at %s. If anyone asks why it has a warranty sticker over a bite mark, you did not see that." % [
			part_name,
			npc_name,
			outpost_display,
		],
		objective,
		{}
	)
	return _offer(
		TEMPLATE_PICKUP_SPECIAL,
		true,
		"[LOCAL] Sealed Part Pickup, No Smelling The Package",
		"Outpost Maintenance Account",
		"Pickup job with a local contact and a suspicious return handoff.",
		"Pick up %s from %s at %s" % [
			part_name,
			npc_name,
			outpost_display,
		],
		base_reward,
		0,
		1.0,
		quest_data,
		["{ITEM_NAME}", "{TARGET_NPC}", "{PICKUP_LOCATION}"],
		{
			"{ITEM_NAME}": part_name,
			"{TARGET_NPC}": npc_name,
			"{PICKUP_LOCATION}": outpost_display,
		}
	)


static func _build_recovery_preview() -> Dictionary:
	var base_reward := 840
	var objective := {
		"type": TEMPLATE_RECOVER_COMBAT_DROP,
		"target_faction": "reavers",
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
		"Search Reaver wreckage for the missing data pack. It gets logged automatically if you find it.",
		objective,
		{}
	)
	return _offer(
		TEMPLATE_RECOVER_COMBAT_DROP,
		true,
		"[RECOVERY] Courier Exploded. Data Survived. Probably.",
		"Dock 3 Claims Adjuster",
		"Recover a missing data pack from hostile wreckage. Legal says the courier is now a rounding error.",
		"Search Reaver wreckage until the data pack turns up in the ship log.",
		base_reward,
		0,
		1.0,
		quest_data,
		["{TARGET_FACTION}", "{ITEM_NAME}", "{TURN_IN_LOCATION}"],
		{
			"{TARGET_FACTION}": "Reaver",
			"{ITEM_NAME}": "data pack",
			"{TURN_IN_LOCATION}": "the main station",
		}
	)


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
		"placeholder_values": placeholder_values,
	}


static func _objective_summary(objective: Dictionary) -> String:
	match str(objective.get("type", "")):
		"DELIVER_ORE":
			return "%d m3 Ore" % int(round(float(
				objective.get("amount_required", 0.0)
			)))
		"PICKUP_SPECIAL":
			return "Pick up %s from %s at %s" % [
				str(objective.get("part_name", "the package")),
				str(objective.get("target_npc", "the contact")),
				str(objective.get("target_outpost_display", "the outpost")),
			]
		TEMPLATE_RECOVER_COMBAT_DROP:
			return "Recover %s from %s wreckage" % [
				str(objective.get("item_name", "the data pack")),
				str(objective.get("target_faction", "hostile")).to_upper(),
			]
	return "Review posting details"
