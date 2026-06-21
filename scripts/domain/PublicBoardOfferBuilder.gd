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

static var story_config_override_for_tests: SystemConfig = null


static func build_offers(current_time_minutes: int) -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	offers.append(_build_ore_offer(current_time_minutes))
	var pickup_offer := _build_pickup_offer(current_time_minutes)
	if not pickup_offer.is_empty():
		offers.append(pickup_offer)
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
	var story_note := _story_board_context("ore")
	var dialogue := "Bring %d m3 of ore to the main station. The posting says the coolant is not supposed to steam. Nobody asked you to verify that." % int(amount)
	var board_body := "Bring ore before a supervisor learns thermodynamics."
	if not story_note.is_empty():
		dialogue += " Local note: %s" % story_note
		board_body += " Local note: %s" % story_note
	var objective := {
		"type": "DELIVER_ORE",
		"amount_required": amount,
		"reward_credits": base_reward,
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
	return _offer(
		TEMPLATE_DELIVER_ORE,
		true,
		"[URGENT] Coolant Needed. Do Not Ask Why It Is Warm.",
		"Definitely Licensed Dockhand",
		board_body,
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
	var dialogue := "Pick up %s from %s at %s. If anyone asks why it has a warranty sticker over a bite mark, you did not see that." % [
		part_name,
		npc_name,
		outpost_display,
	]
	var board_body := "Pickup job with a local contact and a suspicious return handoff."
	if not story_note.is_empty():
		dialogue += " Local note: %s" % story_note
		board_body += " Local note: %s" % story_note
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
		dialogue,
		objective,
		{}
	)
	return _offer(
		TEMPLATE_PICKUP_SPECIAL,
		true,
		"[LOCAL] Sealed Part Pickup, No Smelling The Package",
		"Outpost Maintenance Account",
		board_body,
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


static func _story_board_context(_offer_kind: String) -> String:
	var story_pack := _current_system_story_pack()
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
	if clean.begins_with("gen_"):
		clean = clean.trim_prefix("gen_")
	var parts := clean.replace("_", " ").split(" ", false)
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
