class_name PublicBoardTextGenerator
extends RefCounted

const OfferBuilderType := preload(
	"res://scripts/domain/PublicBoardOfferBuilder.gd"
)

const OUTPUT_FIELDS: Array[String] = [
	"title",
	"poster",
	"body",
	"briefing",
	"kaelen_turn_in",
]

const FORBIDDEN_MECHANIC_WORDS: Array[String] = [
	"land on",
	"planet surface",
	"boarding party",
	"crew combat",
	"stealth",
	"hack the gate",
]

const KAELEN_AUTHORSHIP_BLOCKLIST: Array[String] = [
	"i posted",
	"my posting",
	"my job",
	"i arranged",
	"i set this up",
	"my contract",
]

const KAELEN_DISGUST_CUES: Array[String] = [
	"slumming",
	"public board",
	"public-board",
	"stain",
	"stains",
	"smell",
	"grime",
	"scrape",
	"desperate",
	"standards",
	"dumpster",
	"gutter",
]


static func build_generation_request(
	offer: Dictionary,
	critique: String = ""
) -> Dictionary:
	var facts := _facts_for_prompt(offer)
	var required := _required_placeholders(offer)
	var prompt := (
		"You write public contract-board flavor for SpaceGame.\n"
		+ "Tone: dark interstellar Craigslist. The job is real; the story can be strange.\n"
		+ "The game code owns all mechanics. Do not invent destinations, rewards, factions, cargo, enemies, deadlines, or objectives.\n"
		+ "Return only valid JSON with these string keys: title, poster, body, briefing, kaelen_turn_in.\n"
		+ "Use the exact placeholders listed below. Do not replace them with real values.\n"
		+ "Required placeholders: " + ", ".join(required) + "\n"
		+ "Facts you must obey:\n" + facts + "\n"
		+ "Kaelen turn-in rule: Kaelen may process payout, but she did not post this job. "
		+ "She should sound visibly grossed out that the player is slumming it on public-board work.\n"
	)
	if not critique.strip_edges().is_empty():
		prompt += "\nSELF-CRITIQUE: previous output failed because " + critique
	return {
		"template_id": str(offer.get("template_id", "")),
		"prompt": prompt,
		"format": "json",
		"required_placeholders": required,
		"fields": OUTPUT_FIELDS.duplicate(),
	}


static func fallback_payload(offer: Dictionary, salt: int = 0) -> Dictionary:
	match str(offer.get("template_id", "")):
		OfferBuilderType.TEMPLATE_DELIVER_ORE:
			return _ore_fallback(salt)
		OfferBuilderType.TEMPLATE_PICKUP_SPECIAL:
			return _pickup_fallback(salt)
		OfferBuilderType.TEMPLATE_RECOVER_COMBAT_DROP:
			return _recovery_fallback(salt)
	return {
		"title": "Odd Job With Missing Details",
		"poster": "Anonymous Account",
		"body": "The posting is half corrupted, which is already a review.",
		"briefing": "Verify the objective summary before accepting.",
		"kaelen_turn_in": "I processed the public board payout. Don't make me ask where you found that one; I can smell the standards dropping from here.",
	}


static func apply_payload_to_offer(
	offer: Dictionary,
	payload: Dictionary,
	is_fallback: bool
) -> Dictionary:
	var result := validate_payload(offer, payload)
	if not bool(result.get("ok", false)):
		return {
			"ok": false,
			"reason": str(result.get("reason", "invalid generated text")),
			"offer": offer.duplicate(true),
		}
	var rendered := offer.duplicate(true)
	rendered["title"] = _render(str(payload.get("title", "")), offer)
	rendered["poster"] = _render(str(payload.get("poster", "")), offer)
	rendered["body"] = _render(str(payload.get("body", "")), offer)
	rendered["generated_briefing"] = _render(
		str(payload.get("briefing", "")),
		offer
	)
	rendered["generated_text_is_fallback"] = is_fallback
	rendered["generated_text_payload"] = payload.duplicate(true)

	var quest_data: Dictionary = rendered.get("quest_data", {})
	if not quest_data.is_empty():
		quest_data = quest_data.duplicate(true)
		quest_data["title"] = str(rendered["title"])
		quest_data["dialogue"] = str(rendered["generated_briefing"])
		quest_data["public_board"] = true
		quest_data["public_board_template_id"] = str(
			rendered.get("template_id", "")
		)
		quest_data["public_board_turn_in_line"] = _render(
			str(payload.get("kaelen_turn_in", "")),
			offer
		)
		quest_data["public_board_text_is_fallback"] = is_fallback
		rendered["quest_data"] = quest_data
	return {
		"ok": true,
		"offer": rendered,
		"reason": "",
	}


static func fallback_offer(offer: Dictionary, salt: int = 0) -> Dictionary:
	var payload := fallback_payload(offer, salt)
	var applied := apply_payload_to_offer(offer, payload, true)
	if bool(applied.get("ok", false)):
		return applied["offer"]
	push_warning(
		"[PublicBoardTextGenerator] Fallback failed validation: %s" %
		str(applied.get("reason", "unknown"))
	)
	return offer


static func validate_payload(offer: Dictionary, payload: Dictionary) -> Dictionary:
	if not payload is Dictionary:
		return _invalid("payload is not a dictionary")
	for field in OUTPUT_FIELDS:
		var value := str(payload.get(field, "")).strip_edges()
		if value.is_empty():
			return _invalid("missing field '%s'" % field)
		if value.length() > _field_limit(field):
			return _invalid("field '%s' is too long" % field)
	var combined := ""
	for field in OUTPUT_FIELDS:
		combined += "\n" + str(payload.get(field, ""))
	for placeholder in _required_placeholders(offer):
		if not combined.contains(placeholder):
			return _invalid("missing placeholder %s" % placeholder)
	var lower := combined.to_lower()
	for word in FORBIDDEN_MECHANIC_WORDS:
		if lower.contains(word):
			return _invalid("invented unsupported mechanic '%s'" % word)
	if str(offer.get("template_id", "")) == OfferBuilderType.TEMPLATE_RECOVER_COMBAT_DROP \
			and combined.contains("%"):
		return _invalid("recovery posting exposed hidden drop percentage")
	var kaelen := str(payload.get("kaelen_turn_in", "")).to_lower()
	for blocked in KAELEN_AUTHORSHIP_BLOCKLIST:
		if kaelen.contains(blocked):
			return _invalid("Kaelen line implies she authored the posting")
	var has_disgust := false
	for cue in KAELEN_DISGUST_CUES:
		if kaelen.contains(cue):
			has_disgust = true
			break
	if not has_disgust:
		return _invalid("Kaelen line is not disgusted enough about public-board work")
	return {"ok": true, "reason": ""}


static func _facts_for_prompt(offer: Dictionary) -> String:
	var quest_data: Dictionary = offer.get("quest_data", {})
	var objective: Dictionary = quest_data.get("objective", {})
	var lines: Array[String] = [
		"- template_id: " + str(offer.get("template_id", "")),
		"- objective_summary: " + str(offer.get("objective", "")),
		"- base_reward: " + str(offer.get("base_reward", 0)) + " SC",
	]
	if int(offer.get("duration_minutes", 0)) > 0:
		lines.append(
			"- deadline_minutes: " + str(offer.get("duration_minutes", 0))
		)
		lines.append(
			"- urgent_multiplier: " + str(offer.get("urgent_multiplier", 1.0))
		)
	if not objective.is_empty():
		lines.append("- objective_type: " + str(objective.get("type", "")))
		for key in objective.keys():
			if key == "type":
				continue
			if str(key) == "drop_chance":
				continue
			lines.append("- " + str(key) + ": " + str(objective[key]))
	return "\n".join(lines)


static func _ore_fallback(salt: int) -> Dictionary:
	var variants := [
		{
			"title": "[URGENT] {ORE_AMOUNT} Ore Needed Before The Coolant Learns New Physics",
			"poster": "Definitely Licensed Dockhand",
			"body": "Need {ORE_AMOUNT} ore delivered to {TURN_IN_LOCATION}. The coolant is steaming, the supervisor is blinking too slowly, and nobody wants an audit.",
			"briefing": "Bring {ORE_AMOUNT} ore to {TURN_IN_LOCATION}. Ignore any bucket labeled 'evidence'.",
			"kaelen_turn_in": "Fine, the {ORE_AMOUNT} ore is logged and the public-board credits cleared. I take their money because I am alive; you, apparently, are auditioning for dockside charity work.",
		},
		{
			"title": "[URGENT] {ORE_AMOUNT} Ore For A Totally Normal Heat Problem",
			"poster": "Maintenance Account With No Last Name",
			"body": "{TURN_IN_LOCATION} needs {ORE_AMOUNT} ore before someone notices the heat sinks are making soup noises.",
			"briefing": "Deliver {ORE_AMOUNT} ore to {TURN_IN_LOCATION}. Do not taste the steam.",
			"kaelen_turn_in": "Payout processed for that {ORE_AMOUNT} ore job. Public board work, Shiny? Really? I suppose standards are expensive.",
		},
	]
	return variants[abs(salt) % variants.size()]


static func _pickup_fallback(salt: int) -> Dictionary:
	var variants := [
		{
			"title": "Sealed Pickup: {ITEM_NAME}, No Sniffing",
			"poster": "Outpost Maintenance Account",
			"body": "Collect {ITEM_NAME} from {TARGET_NPC} at {PICKUP_LOCATION}. The package is sealed because trust is cheaper than insurance.",
			"briefing": "Go to {PICKUP_LOCATION}, get {ITEM_NAME} from {TARGET_NPC}, and bring it back intact.",
			"kaelen_turn_in": "There. {ITEM_NAME} is handed over and the public board money cleared. I did not broker this little errand, but apparently I now launder dignity and grime too.",
		},
		{
			"title": "{ITEM_NAME} Pickup From {PICKUP_LOCATION}, Please Stop Asking Why",
			"poster": "Concerned Owner, Burner Account",
			"body": "{TARGET_NPC} has {ITEM_NAME} waiting at {PICKUP_LOCATION}. If it hums, pretend it always did that.",
			"briefing": "Pick up {ITEM_NAME} from {TARGET_NPC} at {PICKUP_LOCATION}. Bring it to the listed destination.",
			"kaelen_turn_in": "{ITEM_NAME} received. Credits routed. Next time you feel like slumming it on the public board, at least pick one with fewer stains.",
		},
	]
	return variants[abs(salt) % variants.size()]


static func _recovery_fallback(salt: int) -> Dictionary:
	var variants := [
		{
			"title": "Missing {ITEM_NAME}; Check The {TARGET_FACTION} Wrecks",
			"poster": "Dock 3 Claims Adjuster",
			"body": "Search {TARGET_FACTION} wreckage until {ITEM_NAME} turns up, then return it to {TURN_IN_LOCATION}. The courier is unavailable for comment due to explosion.",
			"briefing": "Keep hitting eligible {TARGET_FACTION} ships and checking the wreckage until {ITEM_NAME} turns up in the ship log, then return to {TURN_IN_LOCATION}.",
			"kaelen_turn_in": "{ITEM_NAME} is logged and the public-board payout cleared. I can smell the grime on this one, Shiny. Try not to make slumming it a lifestyle.",
		},
	]
	return variants[abs(salt) % variants.size()]


static func _render(text: String, offer: Dictionary) -> String:
	var rendered := text
	var values: Dictionary = offer.get("placeholder_values", {})
	for key in values.keys():
		rendered = rendered.replace(str(key), str(values[key]))
	return rendered


static func _required_placeholders(offer: Dictionary) -> Array[String]:
	var output: Array[String] = []
	var source: Array = offer.get("required_placeholders", [])
	for item in source:
		output.append(str(item))
	return output


static func _field_limit(field: String) -> int:
	match field:
		"title":
			return 96
		"poster":
			return 48
		"body":
			return 280
		"briefing":
			return 220
		"kaelen_turn_in":
			return 220
	return 220


static func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
