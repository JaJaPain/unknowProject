extends RefCounted

## Written lines for every station mechanic (playtest 2026-10-10 findings 3
## and 4). Damaged ships get a line from their hull band, so nobody invents a
## crash the pilot never had; parts runs are a favour for somebody else's
## ship, paid back with a cheaper repair. All approved by Abe 2026-10-10
## except SPOTLESS, which awaits approval.

## Off the next repair at the shop whose parts run you finished, once.
const FAVOUR_DISCOUNT := 0.25

## Hull share (0-1) upper bounds and their lines, worst first.
const HULL_BANDS: Array = [
	[0.25, [
		"I've seen less damage on a ship that flew into a sun on purpose. Sit down before something falls off. Payment up front, in case you don't make it.",
		"Last month a hauler came in here as three pieces and a rumour. You're about two and a half. I can work with that. My rates can't.",
		"Is that a hull or a strongly worded suggestion of one? I'll patch it. You'll pay. At least one of us will cry.",
		"I once rebuilt a tug a Reaver used as a chew toy. It looked better than this. Don't worry, I like a challenge. I bill like one too.",
		"Your ship's held together by habit and my good opinion of you. Only one of those is free.",
		"Did you fly here, or did the debris just arrive together? I'll weld it back into a ship. Weld rates apply.",
		"A miner crashed into his own drill rig last week and still came in prettier. Breathe. I fix worse all the time. Just 'cause I can doesn't make it cheap, though.",
	]],
	[0.50, [
		"Had a freighter last week that skipped off an asteroid twice, like a stone on a pond. You're about one and a half skips. I'll patch you up. Standard fees, standard sighing.",
		"That's a lot of new holes for one trip. I've seen cheese with better hull integrity. Give me an hour and a fistful of credits.",
		"Somebody really didn't like you out there. Good news: I like you fine, at my usual rate.",
		"This looks like the courier that tried to dock with the wrong end of the station. She lived. So will you. So will my invoice.",
		"Half your plating's on the inside now. Don't panic, I've got a crate of the outside kind.",
		"Scorch marks in a pattern. Did you let them paint you? I'll fix it, but the art's extra.",
	]],
	[0.75, [
		"You're dented about as bad as a hauler I dug off an asteroid last week. She flies fine now, and so will you. The fees are regular, the sympathy's free.",
		"Took a few, didn't you? I've seen worse on ships that only went out for groceries. Let's get you closed up.",
		"That's a respectable amount of dents. Not 'call your mother' dents. 'Call your mechanic' dents. Hi.",
		"A tug came in last week looking like this after losing an argument with a docking arm. I'll tell you what I told its pilot: hold still, this costs money.",
		"Your hull's got character now. I'm going to remove most of it. Character's expensive to keep.",
		"Some scorching, some scraping, one dent I'm going to name. Nothing a few hours and your wallet can't fix.",
	]],
	[0.85, [
		"A few dings. I've seen worse from pilots who park with their eyes shut. Quick patch, quick bill.",
		"You call that damage? I had a racer in here who clipped a buoy at full burn. This is a bad hair day. I'll comb it out.",
		"Light work. Leave it with me, go get a drink, come back poorer.",
		"Couple of dents along the flank. Somebody's buying me lunch today, and it's you, indirectly.",
		"A love tap from a Reaver, by the look of it. I'll smooth it out before it turns into a story.",
		"Nothing structural. Just enough damage to justify my fee. My favourite kind.",
	]],
	[0.995, [
		"Scratched the paint? That's all? I'll buff it out. You'll barely feel the charge.",
		"One scuff. You flew through a fight and came back with one scuff. Show-off. Buffing's still billable.",
		"I've seen bigger marks from a careless coffee cup. Two minutes with a polisher.",
		"That's not damage, that's a fingerprint. I'll wipe it off and charge you like it was damage.",
		"A freighter came in yesterday with a dent shaped like a Reaver's face. Yours is shaped like nothing. Easy money. Mine.",
		"Barely a mark. You could fly like that forever, but then I'd starve. Let me fix it.",
		"Tiny scrape on the nose. I'll have it gone before you finish complaining about the price.",
	]],
]

## Full hull: the model's examples and its fallback. Awaiting Abe's approval.
const SPOTLESS: Array = [
	"Not a scratch on that {ship}. You know you're bad for business, right? Go dent something and come back.",
	"Your ship's in better shape than my bench. Come back when you've broken something; I've got bills.",
	"Clean hull, every plate where it belongs. Either you're good or you've been hiding. Nothing for me to bill.",
	"Nothing to fix on that {ship}. If you're saving up for something, my shop's got opinions on how to spend it.",
	"Pristine {ship}, empty bay. Sit down before I charge you for standing in my workspace.",
]

## Parts-run offers: {part}, {npc}, {outpost}.
const OFFERS: Array = [
	"I need a favour. I've got a ship on my stand I can't finish without a {part}, and {npc} over at {outpost} has one. Bring it back and your next repair comes in cheaper. The run pays, too.",
	"Somebody's freighter is stuck in my bay waiting on a {part}. {npc} at {outpost} is holding it. Fetch it for me and I'll knock a bit off your next repair bill. Plus credits for the trip.",
	"Do me a solid? {npc} at {outpost} has a {part} I need for a customer's wreck. Bring it here and you get paid now and patched cheaper later.",
	"I've got a job half done and a hole where a {part} should be. {npc}'s got one at {outpost}. You run it, I owe you: something off your next repair, and pay for the run.",
	"Favour time. Go to {outpost}, ask for {npc}, pick up a {part}. It's for a hauler I'm putting back together. Do it and your next repair's on me. Well, some of it.",
	"Somebody else's ship is hogging my whole bay until a {part} shows up. {npc} at {outpost} has it. Get it here and I'll remember it on your next bill. In a good way.",
	"Need a runner. {npc} at {outpost} is sitting on a {part} I need for a repair. Bring it back, earn a few credits, and I'll shave something off your next fix.",
]

## Parts-run hand-ins.
const HANDINS: Array = [
	"You're a lifesaver. The guy who owns that wreck has asked me 'is it done yet' nine times today. Number ten was going to end with a wrench.",
	"Finally. That bay's been full for three days and I've been turning paying customers away like a fool. Your discount's on file. Don't tell anyone how grateful I am.",
	"Oh, thank the stars. Its owner has been sleeping in my waiting room. He snores. He snores in two different keys.",
	"Perfect. Now I can finish his ship, take his money, and lose it at cards like a professional. Your next repair's cheaper. You earned it.",
	"You have no idea. He brought me a cake to hurry me up yesterday. A cake. I can't be bribed with cake twice, I have standards.",
	"There it is. One more day of that bay sitting full and I'd have started charging rent to the ship. Thanks. I mean it, and I'll mean it on your bill too.",
	"My hero. Well, my courier. Close enough. His ship's out by tonight and so is he, which is the real gift here.",
]

## Things a generated greeting may not bring up: none of them are in its
## fact packet, so the model would be making them up.
const INVENTED := [
	"crash", "last week", "last month", "last night", "last cycle", "yesterday",
	"since last", "saw you", "heard you", "heard about", "word is", "rumou",
	"sector", "ore field", "reaver", "pirate", "dogfight", "watchlist",
	"registry", "sputter", "screaming",
]
## A spotless hull has none of these.
const DAMAGE := ["dent", "scorch", "scratch", "scuff", "hole", "damage", "busted", "broken", "limp", "smok", "leak"]


static func hull_line(hull_share: float, rng: RandomNumberGenerator = null) -> String:
	for band in HULL_BANDS:
		if hull_share <= float(band[0]):
			return _pick(band[1], rng)
	return ""


static func spotless_line(ship: String, rng: RandomNumberGenerator = null) -> String:
	return _pick(SPOTLESS, rng).replace("{ship}", ship)


static func offer_line(part: String, npc: String, outpost: String, rng: RandomNumberGenerator = null) -> String:
	return _pick(OFFERS, rng).replace("{part}", part).replace("{npc}", npc).replace("{outpost}", outpost)


static func handin_line(rng: RandomNumberGenerator = null) -> String:
	return _pick(HANDINS, rng)


## Why a generated greeting for a full hull is made up, or "".
static func invented_detail(line: String, spotless: bool) -> String:
	var lower := line.to_lower()
	for word in INVENTED:
		if lower.contains(word):
			return "Mentions '%s', which is not in the fact packet. Only use the facts given." % word
	if spotless:
		for word in DAMAGE:
			if lower.contains(word):
				return "Mentions '%s', but the hull is at 100%%: there is no damage." % word
	return ""


static func _pick(pool: Array, rng: RandomNumberGenerator) -> String:
	if pool.is_empty():
		return ""
	var i := rng.randi_range(0, pool.size() - 1) if rng != null else randi() % pool.size()
	return str(pool[i])
