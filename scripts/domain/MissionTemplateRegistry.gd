class_name MissionTemplateRegistry
extends RefCounted

const TEMPLATE_DELIVER_ORE_PUBLIC := "DELIVER_ORE_PUBLIC"
const TEMPLATE_PICKUP_SPECIAL_PUBLIC := "PICKUP_SPECIAL_PUBLIC"
const TEMPLATE_DELIVERY_COURIER_PUBLIC := "DELIVERY_COURIER_PUBLIC"
const TEMPLATE_PURCHASE_DELIVERY_PUBLIC := "PURCHASE_DELIVERY_PUBLIC"
const TEMPLATE_RECOVER_COMBAT_DROP := "RECOVER_COMBAT_DROP"
const TEMPLATE_DELIVER_ORE_AGENT := "DELIVER_ORE_AGENT"
const TEMPLATE_KILL_SHIPS_AGENT := "KILL_SHIPS_AGENT"
const TEMPLATE_PICKUP_SPECIAL_AGENT := "PICKUP_SPECIAL_AGENT"
const TEMPLATE_TARGET_WITH_COMMS_REVERSAL := "TARGET_WITH_COMMS_REVERSAL"

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
	+ "This board IS the space Craigslist. Same energy: sleazy landlords, "
	+ "suspiciously vague gig postings, people clearly mid-divorce selling things that belong to someone else, "
	+ "'no lowballers I know what I have', guys who sign every post with a Bible verse, "
	+ "scams so obvious they loop back to charming, and the occasional post that makes you genuinely concerned for the poster's safety. "
	+ "PG-13 — innuendo is fine, nothing explicit. The humor comes from specificity and deadpan delivery.\n\n"
	+ "POSTER HANDLE: Never 'Anonymous'. Never a real NPC name. Always a burner account name that tells a story. "
	+ "Examples: 'Definitely Not Maintenance', 'Dock 7 Liability Account', 'Former Employee (Unrelated)', "
	+ "'Husband Of The Year Burner', 'NOT The Guy From The Incident', 'Concerned Taxpayer With Access', "
	+ "'Third Shift Survivor'. The handle alone should make someone want to read the posting.\n\n"
	+ "TITLE: Specific and weird. Should read like an actual Craigslist post that makes you click. "
	+ "GOOD: 'Need 40m3 Ore Before The Coolant Learns New Physics', 'Sealed Package, Do Not Shake Or Ask Questions', "
	+ "'My Ex-Business Partner Left Something At Your Outpost'. "
	+ "BAD: 'Urgent Delivery Needed', 'Critical Supply Run', 'Resource Transport'. No generic sci-fi. No action-movie one-liners.\n\n"
	+ "BODY: 1-3 sentences. The poster is a real person who is bad at hiding something. "
	+ "They overshare one specific detail while being suspiciously vague about another. "
	+ "The job itself is legitimate — the context around it is where the humor lives.\n\n"
	+ "BRIEFING: Deadpan summary. Acknowledge something weird the poster said, then move on professionally.\n\n"
	+ "KAELEN TURN-IN: Kaelen (the broker) processes the payout but she did NOT post this job. "
	+ "She is disgusted the pilot took public-board work. She is specific about what grosses her out — "
	+ "the smell, the clientele, the poster's grammar, the stain on the contract, the fact that it was posted at 3am. "
	+ "She takes the money because profit is profit, but she wants the pilot to know she noticed.\n\n"
	+ "The game code owns all mechanics. Do not invent destinations, rewards, "
	+ "factions, cargo, enemies, deadlines, or objectives.\n"
	+ "Return only valid JSON with these string keys: title, poster, body, briefing, kaelen_turn_in.\n"
	+ "Use the exact placeholders listed below. Do not replace them with real values.\n"
)

const BOARD_SPICE: Array[String] = [
	"The poster is clearly lying about why they need this done. They gave two different reasons in the title and body.",
	"The posting was edited three times in ten minutes. Each version was worse.",
	"The poster's handle is a burner account created today. Their first post is this job. Their second post is asking where to buy a fake ID.",
	"This posting is written in the tone of someone who is actively being yelled at by a supervisor while typing.",
	"The poster is obviously going through a divorce and this job is somehow related.",
	"The previous courier for this job is 'unavailable for comment' and the poster will not elaborate.",
	"The posting has a suspiciously specific disclaimer about what is NOT illegal about this job.",
	"The poster accidentally left a personal detail in the posting that makes the whole thing 10x funnier.",
	"This job exists because someone lost a bet. The poster is the someone.",
	"The posting reads like it was written at 3am by someone who just got fired and is making a point.",
	"The poster signed off with something weirdly personal, like a horoscope reference or an apology to someone named Gary.",
	"The posting mentions an incident that 'has been resolved' but the job proves it has not been resolved.",
	"The poster uses very careful language around one specific detail, like a lawyer wrote that sentence and only that sentence.",
	"This is clearly a favor for someone the poster owes money to.",
	"The posting's tone shifts halfway through, like the poster started angry and gave up.",
	"The poster included a review of the last courier. It is scathing and detailed and explains why the pay is low.",
	"The urgency suggests the poster has already tried to do this themselves and it went badly.",
	"The poster is pretending this is a normal routine job. The listing duration and reward say otherwise.",
	"There is an energy to this posting that suggests the poster is hiding in a supply closet right now.",
	"The poster helpfully included what NOT to tell customs.",
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

	_cache[TEMPLATE_DELIVERY_COURIER_PUBLIC] = MissionTemplate.create({
		"template_id": TEMPLATE_DELIVERY_COURIER_PUBLIC,
		"objective_type": "DELIVERY_COURIER",
		"source_lane": "BOARD",
		"tone_card": BOARD_TONE,
		"write_fields": BOARD_WRITE_FIELDS,
		"field_limits": BOARD_FIELD_LIMITS,
		"required_placeholders": ["{ITEM_NAME}", "{DESTINATION}"],
		"forbidden_words": FORBIDDEN_MECHANIC_WORDS,
		"custom_rules": [KAELEN_DISGUST_RULE],
		"fallback_variants": [
			{
				"title": "Sealed Courier Run: {ITEM_NAME}, No Heroics",
				"poster": "Logistics Account With A Nervous Tick",
				"body": "Take {ITEM_NAME} to {DESTINATION}. The seal is intact, the manifest is technically readable, and nobody needs to learn why it is warm.",
				"briefing": "Courier {ITEM_NAME} to {DESTINATION}. Keep the seal intact and the explanations short.",
				"kaelen_turn_in": "{ITEM_NAME} delivered, public-board payout processed. I admire your commitment to jobs that smell like wet paperwork.",
			},
			{
				"title": "{ITEM_NAME} Needs A Ride To {DESTINATION}",
				"poster": "Definitely Not Avoiding Customs",
				"body": "Courier {ITEM_NAME} to {DESTINATION}. It is legal in every jurisdiction that matters and several that do not.",
				"briefing": "Carry {ITEM_NAME} to {DESTINATION}. The job is simple, which is usually where the trouble hides.",
				"kaelen_turn_in": "Done. {ITEM_NAME} is off your ship and the credits cleared. Public-board courier work, Shiny? The romance is dead.",
			},
		],
	})

	_cache[TEMPLATE_PURCHASE_DELIVERY_PUBLIC] = MissionTemplate.create({
		"template_id": TEMPLATE_PURCHASE_DELIVERY_PUBLIC,
		"objective_type": "PURCHASE_DELIVERY",
		"source_lane": "BOARD",
		"tone_card": BOARD_TONE,
		"write_fields": BOARD_WRITE_FIELDS,
		"field_limits": BOARD_FIELD_LIMITS,
		"required_placeholders": ["{QUANTITY}", "{ITEM_NAME}", "{STORE_LOCATION}", "{DESTINATION}"],
		"forbidden_words": FORBIDDEN_MECHANIC_WORDS,
		"custom_rules": [KAELEN_DISGUST_RULE],
		"fallback_variants": [
			{
				"title": "Buy {QUANTITY} {ITEM_NAME}; Do Not Haggle With The Wrong Person",
				"poster": "Expense Report Casualty",
				"body": "Buy {QUANTITY} {ITEM_NAME} from {STORE_LOCATION} and bring it to {DESTINATION}. I would do it myself but the store owner and I have what legal calls 'history'.",
				"briefing": "Purchase {QUANTITY} {ITEM_NAME} at {STORE_LOCATION}, then deliver it to {DESTINATION}.",
				"kaelen_turn_in": "{ITEM_NAME} received and public-board payout cleared. You bought retail for someone else's errand. I hope that sentence follows you.",
			},
			{
				"title": "Need {QUANTITY} {ITEM_NAME} From {STORE_LOCATION}, Receipts Optional",
				"poster": "Procurement Burner, Third Shift",
				"body": "Buy {QUANTITY} {ITEM_NAME} from {STORE_LOCATION} and deliver to {DESTINATION}. If anyone asks, this was budgeted. If accounting asks, run.",
				"briefing": "Get {QUANTITY} {ITEM_NAME} from {STORE_LOCATION} and bring it to {DESTINATION}.",
				"kaelen_turn_in": "The {ITEM_NAME} is handed over. Credits processed. Public procurement jobs are how ambition goes to cough.",
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


	_cache[TEMPLATE_TARGET_WITH_COMMS_REVERSAL] = MissionTemplate.create({
		"template_id": TEMPLATE_TARGET_WITH_COMMS_REVERSAL,
		"objective_type": "TARGET_WITH_COMMS_REVERSAL",
		"source_lane": "BOARD",
		"tone_card": BOARD_TONE,
		"write_fields": BOARD_WRITE_FIELDS,
		"field_limits": BOARD_FIELD_LIMITS,
		"required_placeholders": ["{TARGET_FACTION}", "{KILL_COUNT}", "{TURN_IN_LOCATION}"],
		"forbidden_words": FORBIDDEN_MECHANIC_WORDS,
		"custom_rules": [KAELEN_DISGUST_RULE],
		"fallback_variants": [
			{
				"title": "Somebody Needs {KILL_COUNT} {TARGET_FACTION} Ships Gone Yesterday",
				"poster": "Concerned Investor (Burner #3)",
				"body": "I need {KILL_COUNT} {TARGET_FACTION} ships removed from my shipping lane. The insurance company is asking questions I don't want to answer. Return to {TURN_IN_LOCATION} when it's done.",
				"briefing": "Eliminate {KILL_COUNT} {TARGET_FACTION} vessels and report to {TURN_IN_LOCATION}. The poster's reasons are between them and their accountant.",
				"kaelen_turn_in": "Public board kill job. Lovely. I can smell the desperation on this one from here. Credits processed. Try not to make slumming it a habit, Shiny.",
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
