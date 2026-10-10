extends RefCounted

## Written lines for every station mechanic (playtest 2026-10-10 findings 3
## and 4). Damaged ships get a line from their hull band, so nobody invents a
## crash the pilot never had; parts runs are a favour for somebody else's
## ship, paid back with a cheaper repair. All approved by Abe 2026-10-10
## (SPOTLESS too).

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

## Full hull: the model's examples and its fallback. Approved by Abe 2026-10-10.
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

## Personalities for the generated mechanics (Abe, 2026-10-10: each one gets a
## bit of personality, with male-only and female-only sets). A station's
## mechanic keeps one for good, picked from its id and gender. Each has two
## lines per hull band (worst first, same bounds as HULL_BANDS) and two for a
## spotless hull. Only "approved" ones are used; until then a mechanic speaks
## Jenna's lines.
const PERSONALITIES := {
	"old_hand": {
		"gender": "m",
		"approved": true,
		"about": "a gruff old-timer: few words, has seen every kind of wreck, grumbles about young pilots, proud of his work, never hurries",
		"bands": [
			["Forty years on this deck, and I've seen worse exactly twice. Both times I said the same thing. Sit down, son. This'll take a while, and it won't be cheap.",
			"My old man used to say a ship tells you how it was flown. Yours is screaming. I'll shut it up. You'll pay for the quiet."],
			["Kids these days. Fly like the hull grows back on its own. It doesn't. I do it. For money.",
			"Seen this before. Fellow tried to outrun a Reaver in a tub like yours, back when I had hair. He paid me double. You'll pay standard. Be grateful."],
			["Dented. Not dead. I don't do sympathy, I do plating. Park it.",
			"Hmph. Could be worse. Could be better. Bill sits right in the middle, same as always."],
			["A few knocks. When I was your age I'd have flown on it. Then I'd have paid someone like me. So: pay someone like me.",
			"That'll buff. Don't stand behind me while I work. Don't talk either. Talking's extra."],
			["You came in for that? My wife's spoons have deeper scratches. Fine. Ten minutes, and you're buying.",
			"One mark. In my day we'd call that a clean run and keep the money. You're not in my day. Pay up."],
		],
		"spotless": [
			"Nothing wrong with that {ship}. Don't make me find something. I will.",
			"Clean hull. Huh. Come back when you've earned a visit.",
		],
	},
	"tinkerer": {
		"gender": "m",
		"approved": true,
		"about": "an excitable tinkerer who loves machines more than people: talks to the ship like a pet, gets carried away, a bit awkward with pilots",
		"bands": [
			["Oh, you poor thing. Not you, the ship. Look what he did to you. Don't worry, girl, I've got you. You, Captain, have got the bill.",
			"Oh, this is wonderful. I mean terrible! Terrible for you. For me it's a whole week of work. My kids are going to eat this month."],
			["You know what I love about a hull this busted? You get to see how she's put together. You don't love it. That's fine. That's what the invoice is for.",
			"Last month I rebuilt a hauler's whole spine with a spare from a mining rig. It still flies. Yours'll fly too, just with less of your money inside it."],
			["She's been through it, hasn't she? Hey there. Hey. We'll get those dents out. Captain, pay the nice man.",
			"Ooh, a fresh scorch pattern. I keep a scrapbook, you know. My brother thinks it's weird. He's not wrong. That'll be the usual."],
			["Couple of bumps. She's fine, she's just being dramatic. Ships are like that. So are pilots. Quick job.",
			"A little scuffed. I'll have her purring before you finish your coffee. The purring costs, sadly."],
			["That's barely a scratch! I'll fix it anyway. She deserves it. You can pay for it. You deserve that.",
			"Hardly a mark. Honestly, I'm a bit disappointed. Bring me something broken next time, I get bored."],
		],
		"spotless": [
			"Not a scratch on her! Can I just look at her for a bit? No charge. Well. Small charge.",
			"That {ship} is gleaming. Whoever's flying her is either very good or very lucky. Either way, she likes you.",
		],
	},
	"navy_engineer": {
		"gender": "f",
		"approved": true,
		"about": "a calm ex-navy engineer: clinical, precise, deadpan, talks in damage reports, quietly proud",
		"bands": [
			["Structural integrity is a strong word for what you have. I'll replace what's missing. My invoice is itemised. It's long.",
			"In the fleet we wrote ships like this off and kept the paint. I'm not in the fleet. Sit. I don't scrap things that still pay."],
			["Four impacts, three fires, one decision I'd have court-martialled. I'll fix the first seven.",
			"My mother flew haulers for thirty years and never came home like this. I'll charge you less than I charged her. Just don't tell her."],
			["Moderate damage. You'll live. The ship will live. Your credit balance will be wounded.",
			"I once patched a corvette mid-burn with a cutting torch and a prayer. This is easier. I'll still charge like it isn't."],
			["Cosmetic, mostly. I'll handle it. Don't touch anything on your way out.",
			"Minor dents along the port side. Fixable in an hour. Billable in a minute."],
			["A scratch. You docked to show me a scratch. All right. I respect thoroughness. And payment.",
			"A few percent off spec. I'll round it up for my trouble. I can round up your bill while I'm at it."],
		],
		"spotless": [
			"Hull at full. Systems nominal. You're wasting my bay, but you're doing it politely.",
			"That {ship} is clean. Go break something useful and come back.",
		],
	},
	"big_heart": {
		"gender": "f",
		"approved": true,
		"about": "a loud, big-hearted bruiser: laughs easily, calls the pilot Captain or sugar, teases kindly, bills firmly",
		"bands": [
			["Oh, Captain. Oh no. Come here, let me see. Mm-hm. Mm-hm. Yeah, you're paying me a lot today.",
			"Ha! Last time a ship came in this bad, the pilot cried on my shoulder. Go ahead, I've got two. Then pay me."],
			["Look at all those holes! You got into a fight and the fight won, didn't it? Aw. I'll fix you up, sugar. At full price, sugar.",
			"My sister wrecked a skiff just like this once and I never let her forget it. Don't worry, I'll only tease you a little. I'll make up for my loss with your bill."],
			["Bit banged up, huh? Happens to the best of us. Mostly happens to the rest of us. Park her, I'll sort it.",
			"Ha, look at that dent! That's a good one. I'm keeping a picture. You're keeping the receipt."],
			["Just a few dings, Captain. I'll have you shining before you can say 'how much'. Don't say it.",
			"Aw, a couple of bruises. Nothing a hammer and a hug can't fix. The hug's free."],
			["That's what you came in for? Sweetheart, I've got lipstick marks worse than that. Fine, I'll buff it.",
			"One little scuff! You're too careful. I like that in a pilot. Not in a customer. Pay up."],
		],
		"spotless": [
			"Not a mark on that {ship}! Did you just come by to see me? I'm flattered. Buy something.",
			"Clean as a whistle, Captain. Go on, get out there and give me some work.",
		],
	},
}

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


## A personality id for one station's mechanic, stable for that seed: only
## approved ones, matching gender (female 1, male 0, unknown -1 takes any).
## "" means Jenna's lines.
static func personality_for(key: String, female: int, include_unapproved: bool = false) -> String:
	var pool: Array = []
	for id in PERSONALITIES.keys():
		var p: Dictionary = PERSONALITIES[id]
		if not include_unapproved and not bool(p.get("approved", false)):
			continue
		if female == 1 and str(p["gender"]) != "f":
			continue
		if female == 0 and str(p["gender"]) != "m":
			continue
		pool.append(id)
	if pool.is_empty():
		return ""
	pool.sort()
	return str(pool[absi(key.hash()) % pool.size()])


static func about(personality: String) -> String:
	return str(PERSONALITIES.get(personality, {}).get("about", ""))


static func hull_line(hull_share: float, rng: RandomNumberGenerator = null, personality: String = "") -> String:
	for i in HULL_BANDS.size():
		if hull_share <= float(HULL_BANDS[i][0]):
			if PERSONALITIES.has(personality):
				return _pick(PERSONALITIES[personality]["bands"][i], rng)
			return _pick(HULL_BANDS[i][1], rng)
	return ""


static func spotless_pool(personality: String = "") -> Array:
	if PERSONALITIES.has(personality):
		return PERSONALITIES[personality]["spotless"]
	return SPOTLESS


static func spotless_line(ship: String, rng: RandomNumberGenerator = null, personality: String = "") -> String:
	return _pick(spotless_pool(personality), rng).replace("{ship}", ship)


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
