class_name MissionTemplateRegistry
extends RefCounted

const TEMPLATE_DELIVER_ORE_PUBLIC := "DELIVER_ORE_PUBLIC"
const TEMPLATE_PICKUP_SPECIAL_PUBLIC := "PICKUP_SPECIAL_PUBLIC"
const TEMPLATE_RECOVER_COMBAT_DROP := "RECOVER_COMBAT_DROP"
const TEMPLATE_DELIVER_ORE_AGENT := "DELIVER_ORE_AGENT"
const TEMPLATE_KILL_SHIPS_AGENT := "KILL_SHIPS_AGENT"
const TEMPLATE_PICKUP_SPECIAL_AGENT := "PICKUP_SPECIAL_AGENT"

const BOARD_WRITE_FIELDS: Array[String] = [
	"title", "poster", "body", "briefing", "kaelen_turn_in",
]

const BOARD_FIELD_LIMITS: Dictionary = {
	"title": 96,
	"poster": 48,
	"body": 280,
	"briefing": 220,
	"kaelen_turn_in": 220,
}

const AGENT_WRITE_FIELDS: Array[String] = [
	"title", "dialogue",
]

const AGENT_FIELD_LIMITS: Dictionary = {
	"title": 96,
	"dialogue": 400,
}

const FORBIDDEN_MECHANIC_WORDS: Array[String] = [
	"land on",
	"planet surface",
	"boarding party",
	"crew combat",
	"stealth",
	"hack the gate",
]

const BOARD_TONE: String = (
	"You write public contract-board flavor for SpaceGame.\n"
	+ "Tone: dark interstellar Craigslist. Deadpan absurdity. The job is real and the stakes matter, but the story around it should be weird, specific, and funny. "
	+ "Think: mundane workplace disasters in space, shady cover stories told badly, bureaucratic spite, passive-aggressive anonymous posting, things that went wrong in oddly specific ways.\n"
	+ "Good example titles: 'Need 40m3 Ore Before The Coolant Learns New Physics', 'Sealed Pickup, No Sniffing', 'Courier Exploded, Data Survived, Probably'.\n"
	+ "Bad: generic sci-fi ('Critical Supply Run', 'Urgent Delivery Needed'). Bad: purple prose. Bad: action-movie one-liners.\n"
	+ "The poster is always an anonymous account with a funny handle — never a named NPC, never 'Anonymous'. They are a specific person hiding badly.\n"
	+ "Kaelen (the broker) processes the payout but hates public-board work. She thinks it is beneath the pilot. She is sarcastic, disgusted, and specific about what grosses her out.\n"
	+ "The game code owns all mechanics. Do not invent destinations, rewards, "
	+ "factions, cargo, enemies, deadlines, or objectives.\n"
	+ "Return only valid JSON with these string keys: title, poster, body, briefing, kaelen_turn_in.\n"
	+ "Use the exact placeholders listed below. Do not replace them with real values.\n"
)

const BOARD_SPICE: Array[String] = [
	"The poster is clearly lying about why they need this done.",
	"The posting has been edited three times. The revision history is worse than the current version.",
	"There is a passive-aggressive reply chain in the comments that the poster deleted but everyone saw.",
	"The poster is obviously posting from a work terminal and hoping nobody notices.",
	"This job was previously posted at double the reward. The poster lowered it and hoped nobody would notice.",
	"The poster signs off with an oddly personal detail that raises more questions than it answers.",
	"The posting mentions an incident that is clearly under investigation.",
	"The poster uses corporate jargon so thick you can tell they were recently fired.",
	"The urgency in this posting suggests the poster has already been caught once.",
	"The posting contains a very specific instruction about what NOT to look at.",
	"The poster is trying to sound professional but the typos tell a different story.",
	"This job exists because someone lost a bet.",
	"The posting reads like it was written by someone who has been awake for 40 hours.",
]

const KAELEN_DISGUST_RULE := "kaelen_disgust"
const NO_DROP_PERCENT_RULE := "no_drop_percent"

static var _cache: Dictionary = {}


static func get_template(template_id: String) -> MissionTemplate:
	if _cache.has(template_id):
		return _cache[template_id]
	_ensure_loaded()
	return _cache.get(template_id)


static func has_template(template_id: String) -> bool:
	_ensure_loaded()
	return _cache.has(template_id)


static func _ensure_loaded() -> void:
	if not _cache.is_empty():
		return
	_register_board_templates()
	_register_agent_templates()


static func _register_board_templates() -> void:
	_cache[TEMPLATE_DELIVER_ORE_PUBLIC] = MissionTemplate.create({
		"template_id": TEMPLATE_DELIVER_ORE_PUBLIC,
		"objective_type": "DELIVER_ORE",
		"source_lane": "BOARD",
		"tone_card": BOARD_TONE,
		"write_fields": BOARD_WRITE_FIELDS,
		"field_limits": BOARD_FIELD_LIMITS,
		"required_placeholders": ["{ORE_AMOUNT}", "{TURN_IN_LOCATION}"],
		"forbidden_words": FORBIDDEN_MECHANIC_WORDS,
		"custom_rules": [KAELEN_DISGUST_RULE],
		"fallback_variants": [
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
		],
	})

	_cache[TEMPLATE_PICKUP_SPECIAL_PUBLIC] = MissionTemplate.create({
		"template_id": TEMPLATE_PICKUP_SPECIAL_PUBLIC,
		"objective_type": "PICKUP_SPECIAL",
		"source_lane": "BOARD",
		"tone_card": BOARD_TONE,
		"write_fields": BOARD_WRITE_FIELDS,
		"field_limits": BOARD_FIELD_LIMITS,
		"required_placeholders": ["{ITEM_NAME}", "{TARGET_NPC}", "{PICKUP_LOCATION}"],
		"forbidden_words": FORBIDDEN_MECHANIC_WORDS,
		"custom_rules": [KAELEN_DISGUST_RULE],
		"fallback_variants": [
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
		],
	})

	_cache[TEMPLATE_RECOVER_COMBAT_DROP] = MissionTemplate.create({
		"template_id": TEMPLATE_RECOVER_COMBAT_DROP,
		"objective_type": "RECOVER_COMBAT_DROP",
		"source_lane": "BOARD",
		"tone_card": BOARD_TONE,
		"write_fields": BOARD_WRITE_FIELDS,
		"field_limits": BOARD_FIELD_LIMITS,
		"required_placeholders": ["{TARGET_FACTION}", "{ITEM_NAME}", "{TURN_IN_LOCATION}"],
		"forbidden_words": FORBIDDEN_MECHANIC_WORDS,
		"custom_rules": [KAELEN_DISGUST_RULE, NO_DROP_PERCENT_RULE],
		"fallback_variants": [
			{
				"title": "Missing {ITEM_NAME}; Check The {TARGET_FACTION} Wrecks",
				"poster": "Dock 3 Claims Adjuster",
				"body": "Search {TARGET_FACTION} wreckage until {ITEM_NAME} turns up, then return it to {TURN_IN_LOCATION}. The courier is unavailable for comment due to explosion.",
				"briefing": "Keep hitting eligible {TARGET_FACTION} ships and checking the wreckage until {ITEM_NAME} turns up in the ship log, then return to {TURN_IN_LOCATION}.",
				"kaelen_turn_in": "{ITEM_NAME} is logged and the public-board payout cleared. I can smell the grime on this one, Shiny. Try not to make slumming it a lifestyle.",
			},
		],
	})


static func _register_agent_templates() -> void:
	_cache[TEMPLATE_DELIVER_ORE_AGENT] = MissionTemplate.create({
		"template_id": TEMPLATE_DELIVER_ORE_AGENT,
		"objective_type": "DELIVER_ORE",
		"source_lane": "AGENT",
		"tone_card": "",
		"write_fields": AGENT_WRITE_FIELDS,
		"field_limits": AGENT_FIELD_LIMITS,
		"required_placeholders": [],
		"forbidden_words": FORBIDDEN_MECHANIC_WORDS,
		"custom_rules": [],
		"fallback_variants": [],
	})

	_cache[TEMPLATE_KILL_SHIPS_AGENT] = MissionTemplate.create({
		"template_id": TEMPLATE_KILL_SHIPS_AGENT,
		"objective_type": "KILL_SHIPS",
		"source_lane": "AGENT",
		"tone_card": "",
		"write_fields": AGENT_WRITE_FIELDS,
		"field_limits": AGENT_FIELD_LIMITS,
		"required_placeholders": [],
		"forbidden_words": FORBIDDEN_MECHANIC_WORDS,
		"custom_rules": [],
		"fallback_variants": [],
	})

	_cache[TEMPLATE_PICKUP_SPECIAL_AGENT] = MissionTemplate.create({
		"template_id": TEMPLATE_PICKUP_SPECIAL_AGENT,
		"objective_type": "PICKUP_SPECIAL",
		"source_lane": "AGENT",
		"tone_card": "",
		"write_fields": AGENT_WRITE_FIELDS,
		"field_limits": AGENT_FIELD_LIMITS,
		"required_placeholders": [],
		"forbidden_words": FORBIDDEN_MECHANIC_WORDS,
		"custom_rules": [],
		"fallback_variants": [],
	})
