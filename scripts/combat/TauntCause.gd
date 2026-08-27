class_name TauntCause
extends RefCounted

# WHY this fight is happening, derived from real game state at start_combat and
# carried into every taunt the enemy speaks.
#
# Before this existed there were two buckets, rage and reason, and the per-fight
# prompt hardcoded "a furious stranger trash-talking whoever just attacked
# them" -- which is wrong every single time the NPC started the fight. A pirate
# who ambushed the player, a patrol collecting a mining fine, and a contract
# target who just worked out they were sold all said the same generic thing.
#
# Every id here MUST be derivable from state the game already tracks. If we
# cannot prove a reason, the speaker does not claim one (see OPPORTUNIST).

# ── Player swung first ────────────────────────────────────────────────────────
const CONTRACT_HIT := "contract_hit"
const PREEMPTIVE_STRIKE := "preemptive_strike"
const UNPROVOKED := "unprovoked"

# ── They swung first ──────────────────────────────────────────────────────────
const CODE_ENFORCEMENT := "code_enforcement"
const REINFORCEMENT := "reinforcement"
const PIRATE_PREDATION := "pirate_predation"
const REPUTATION_GRUDGE := "reputation_grudge"
const OPPORTUNIST := "opportunist"

const ALL: Array[String] = [
	CONTRACT_HIT,
	PREEMPTIVE_STRIKE,
	UNPROVOKED,
	CODE_ENFORCEMENT,
	REINFORCEMENT,
	PIRATE_PREDATION,
	REPUTATION_GRUDGE,
	OPPORTUNIST,
]

const PLAYER_INITIATED: Array[String] = [
	CONTRACT_HIT,
	PREEMPTIVE_STRIKE,
	UNPROVOKED,
]


static func is_valid(cause: String) -> bool:
	return cause.strip_edges() in ALL


static func is_player_initiated(cause: String) -> bool:
	return cause.strip_edges() in PLAYER_INITIATED


# What the speaker WANTS, what they KNOW about the player, and the register to
# hit. Written as prompt guidance: this text goes straight into the generation
# brief, so it is phrased for a model, not for a human reader.
#
# The house register is dark and dry -- gallows humour, understatement, people
# being casually awful about violence because it is Tuesday. It is NOT zany,
# and it is NOT the yo-mama material this system used to ship.
const _BRIEFS: Dictionary = {
	CONTRACT_HIT: {
		"situation": "there is a BOUNTY ON THE SPEAKER'S HEAD, and the pilot has just attacked them to collect it. The speaker is the hunted one, and every line comes from the hunted",
		# Say the thing plainly. An earlier brief described them as having
		# "worked out they were SOLD", and the model wrote from inside that
		# realisation -- "You were sold. Not me." -- which is a riddle to a
		# player who only knows they took a job. Name the transaction.
		# Positive framing only. Spelling out what NOT to say ("the pilot was not
		# sold") got it read straight back as "You were never sold. You were
		# hired." A 4b treats a prohibition as vocabulary. Describing the one
		# thing they DO talk about is what keeps the roles straight.
		"knows": "A stranger has come to cash in the bounty on them. They have no idea who posted it, and that is the part that stings.",
		"wants": "To needle the stranger for killing a person for money, and to wonder aloud what the bounty on them was worth.",
		"register": "Bitter and wounded, darkly funny about their own price tag. Every line is about the speaker's head or the pilot's fee, in plain words the pilot can tie to the job they took.",
	},
	PREEMPTIVE_STRIKE: {
		"situation": "the player shot first at a ship that was already coming for them",
		"knows": "They were going to attack anyway. The player just moved the schedule up.",
		"wants": "To take credit for the inevitable and act unbothered about losing the first shot.",
		"register": "Dry, almost approving. Professional respect delivered as an insult.",
	},
	UNPROVOKED: {
		"situation": "the pilot opened fire on them with no warning and no reason. They were flying along doing something completely ordinary",
		"knows": "Nothing about the pilot at all. One moment they were working, the next a stranger was shooting at them.",
		# "Wants an explanation" produced argumentative lines that read like a
		# comeback to an insult rather than a reaction to being shot -- "You
		# don't get to decide who's an idiot". Naming the ordinary activity
		# gives the model something concrete to be outraged about.
		"wants": "To know what they did to deserve this, while naming the dull thing they were in the middle of -- a delivery, a survey run, a shift that ends in an hour.",
		"register": "Outraged and genuinely baffled, and SPECIFIC about the ordinary business the pilot just interrupted. The mundane detail is the joke, not an insult contest.",
	},
	CODE_ENFORCEMENT: {
		"situation": "they were dispatched because the player was mining a belt they had no permit for",
		"knows": "The exact violation and the exact fine. This is paperwork that happens to involve guns.",
		"wants": "The fine paid. Destroying the ship is simply the escalation path on the form.",
		"register": "Bored, procedural, faintly menacing. Bureaucracy is the joke -- they are quoting policy while shooting.",
	},
	REINFORCEMENT: {
		"situation": "they were called in as backup after the player fought their people earlier",
		"knows": "That the player already hurt someone on their side. They arrived to a mess.",
		"wants": "To finish what the first group could not, and to be smug about being the competent wave.",
		"register": "Grimly amused, unhurried. The confidence of arriving second with better odds.",
	},
	PIRATE_PREDATION: {
		"situation": "they attacked because robbing ships is simply what they do",
		"knows": "Nothing about the player, and they do not care to. This is a cargo transaction with extra steps.",
		"wants": "The hold emptied. The pilot is an obstacle attached to the cargo.",
		"register": "Transactional and cheerful. Talks about the player as inventory, never as a person.",
	},
	REPUTATION_GRUDGE: {
		"situation": "they attacked because their faction's standing with the player has gone bad",
		"knows": "The player's REPUTATION with them -- a record of past offences, not a name.",
		"wants": "To settle the account on behalf of the flag they fly.",
		"register": "Cold and institutional. This is policy being enforced, and they are enjoying it slightly too much.",
	},
	OPPORTUNIST: {
		"situation": "they attacked and the reason is not worth explaining",
		"knows": "Nothing in particular about the player.",
		"wants": "The fight, or whatever falls out of it.",
		"register": "Curt and unbothered. They do not justify themselves -- never invent a specific grievance here.",
	},
}


static func brief(cause: String) -> Dictionary:
	var key := cause.strip_edges()
	if not _BRIEFS.has(key):
		return _BRIEFS[OPPORTUNIST].duplicate(true)
	return (_BRIEFS[key] as Dictionary).duplicate(true)


# One-line summary, used in logs and diagnostics so a bad taunt can be traced
# back to the cause that produced it.
static func describe(cause: String) -> String:
	return str(brief(cause).get("situation", ""))


# The generation brief as prompt text. `extra` carries cause-specific facts the
# speaker is allowed to know -- the reputation tier for REPUTATION_GRUDGE, the
# outstanding fine for CODE_ENFORCEMENT -- so lines can cite something true
# instead of inventing a grievance.
static func prompt_block(cause: String, extra: Dictionary = {}) -> String:
	var data := brief(cause)
	var parts: Array[String] = [
		"WHY THIS FIGHT IS HAPPENING: %s." % str(data.get("situation", "")),
		"What the speaker knows: %s" % str(data.get("knows", "")),
		"What the speaker wants: %s" % str(data.get("wants", "")),
		"Register: %s" % str(data.get("register", "")),
	]
	var facts: Array = extra.get("facts", []) if extra.get("facts", []) is Array else []
	if not facts.is_empty():
		parts.append("True details the speaker may reference:")
		for fact in facts.slice(0, 4):
			parts.append("- %s" % str(fact).strip_edges())
	return "\n".join(parts)


# Reputation at or below this is a standing grudge rather than mere dislike.
# Matches the threshold NPCShip uses to decide the player is an enemy at all,
# so a ship that engaged over reputation always classifies as one.
const HOSTILE_REPUTATION := -10.0


# Works out why this fight started, from state the game already tracks.
#
# `enemy_flags` is a plain dictionary rather than the ship node so this stays
# pure and testable: {is_quest_target, is_code_enforcement, is_reinforcement,
# is_minor_faction, reputation}.
#
# Order matters. The most specific provable reason wins, because a code
# enforcement ship is also technically a faction ship, and a contract target is
# also technically a stranger who just got shot.
static func derive(player_initiated: bool, enemy_flags: Dictionary) -> String:
	var reputation := float(enemy_flags.get("reputation", 0.0))
	var minor := bool(enemy_flags.get("is_minor_faction", false))
	if player_initiated:
		# They were marked for a contract and the player took the job.
		if bool(enemy_flags.get("is_quest_target", false)):
			return CONTRACT_HIT
		# Already hostile when the player pulled the trigger, so "unprovoked"
		# would be a lie the player can see through.
		if minor or reputation <= HOSTILE_REPUTATION:
			return PREEMPTIVE_STRIKE
		return UNPROVOKED
	if bool(enemy_flags.get("is_code_enforcement", false)):
		return CODE_ENFORCEMENT
	if bool(enemy_flags.get("is_reinforcement", false)):
		return REINFORCEMENT
	if minor:
		return PIRATE_PREDATION
	if reputation <= HOSTILE_REPUTATION:
		return REPUTATION_GRUDGE
	# They started it and we cannot prove why. Say nothing specific.
	return OPPORTUNIST


# Authored floor, used before the model has banked anything for a cause and
# whenever generation fails. Small on purpose -- these exist so the first fight
# of a fresh install is not silent, not to carry the game. Written in the house
# voice, with a mix of situation-carrying lines and plain flat threats.
const _AUTHORED: Dictionary = {
	# Larger than the other floors on purpose. This cause asks a 4b to hold two
	# roles at once -- the speaker is the hunted, the pilot is the hired gun --
	# and it reliably collapses them ("you were sold", "how much did you pay").
	# Four rounds of prompt work got it to roughly half usable, so the authored
	# set carries this one and generation supplements it under a role guard.
	CONTRACT_HIT: [
		"Somebody put a price on me. I hope it was embarrassing.",
		"You're not angry. You're just employed.",
		"I'm going to make this one hurt.",
		"Whatever they paid you, it wasn't enough for this part.",
		"So that's what I'm worth this season.",
		"You came a long way for someone else's grudge.",
		"Bounty work. Very honest, very brave.",
		"I'd ask who wants me dead, but you wouldn't know either.",
		"Collect carefully. I'm told I'm difficult.",
		"Hope the fee clears before the funeral.",
		"You don't even know my name. Just my number.",
		"Somebody's paying you to be here. Nobody's paying me.",
	],
	PREEMPTIVE_STRIKE: [
		"You moved first. Doesn't change where this ends.",
		"Saved me the trouble of the approach.",
		"Eager. I like that in a wreck.",
		"That was my line, and my minute.",
	],
	UNPROVOKED: [
		"I don't even know you. That's the insulting part.",
		"Was it something I flew?",
		"You picked the wrong quiet afternoon.",
		"No warning, no reason. Fine. Same to you.",
	],
	CODE_ENFORCEMENT: [
		"You mined a belt you don't have a permit for. This is the escalation step.",
		"The fine was cheaper an hour ago.",
		"I'd rather be doing paperwork. You've made it this instead.",
		"Nothing personal. It's a form with guns attached.",
	],
	REINFORCEMENT: [
		"You made a mess. We're the cleanup.",
		"The first crew underestimated you. We read their file.",
		"Second wave. Better funded.",
		"They called it in before they stopped transmitting.",
	],
	PIRATE_PREDATION: [
		"Open the hold and we can both be somewhere else in ten minutes.",
		"You're cargo with opinions.",
		"Nothing personal. You're just carrying.",
		"I'm going to make this quick. For me.",
	],
	REPUTATION_GRUDGE: [
		"Your record with us reads like a confession.",
		"We keep accounts. Yours came due.",
		"This isn't about today. Today's just when we found you.",
		"You earned this one slowly.",
	],
	OPPORTUNIST: [
		"I'm going to make this one hurt.",
		"Wrong place. That's all it ever is.",
		"Don't take it personally. Don't take it any way at all.",
		"Let's get this over with.",
	],
}


static func authored_lines(cause: String) -> Array[String]:
	var out: Array[String] = []
	var key := cause.strip_edges()
	if not _AUTHORED.has(key):
		key = OPPORTUNIST
	for line in (_AUTHORED[key] as Array):
		out.append(str(line))
	return out
