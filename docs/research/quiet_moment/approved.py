"""Author-approved lines. The gold standard, and the seed corpus.

Why this file matters beyond record-keeping: an approved line is a better
demo than anything I can write, because it is by definition on-brand. Feeding
approved output back in as few-shot demos is a compounding loop — each round
of approval makes the next round cheaper and more on-voice.

This is the practical answer to "how do we not spend a week of compute per
beat": the corpus bootstraps itself once a character's voice is settled.

Rules for this file:
  - nothing goes in here without explicit author approval;
  - keep the moment and the packet alongside the line, since a line is only
    approved FOR a moment;
  - never delete on a whim — a rejected-later line should be moved to
    REJECTED with the reason, so the same mistake isn't re-derived.
"""

# ---------------------------------------------------------------- N.O.V.A.
# 2026-08-01, post-combat with damage. Author: "I loved every one of those.
# They are completely on brand for her."
NOVA_POST_COMBAT_DAMAGED = [
    "You'll still need to scrape that burn out of my aft struts. Not that I mind the attention.",
    "I've got a few loose panels waiting for fingers. Who do we know with steady hands?",
    "They'll need to strip back the plating. It's not pretty under there. You'd think I'd be more embarrassed.",
    "I'm whole but I'm not pretty. Someone's going to have to scrape me clean.",
    "My plating's got teeth marks and I'm going to need someone with patience to smooth this out.",
]

# Author's own reference lines. These define the voice; treat as canon.
NOVA_AUTHOR_CANON = [
    "This is a really long flight, you could use this time to dust my intakes... "
    "oh never mind, I forgot I can have my nanobots do that.",
    "What that ship did to my body is going to take more than one night of that local "
    "mechanic's hands up my manifold. Someone is going to owe me dinner first.",
]

# ----------------------------------------------------------------- Kaelen
# 2026-08-01. Author bar: "not terrible" is a pass; these cleared it.
KAELEN_SAFE_LOW_PAY = [
    "This one paid small. No tricks, no traps. Just small.",
    "This one didn't cost us, but it didn't pay us either. Not sure why we did it.",
    "Low risk, low pay. I don't complain about the risk, but I do about the pay.",
    "No one got hurt. The numbers still suck. Let's find something that doesn't.",
    "Nobody bled. The number's low. I don't pretend it was anything else.",
    "It paid like it was a favor. I'll take the favor, but I won't take the rate.",
]

KAELEN_AUTHOR_CANON = [
    "I know this job is more dangerous, but I get paid a whole lot more for you doing it.",
    "I know this job is way safer, but I don't make shit from it, so don't make these a habit.",
]

# Explicitly rejected, with the reason, so it is never re-derived.
REJECTED = [
    ("kaelen", "I'll note that in the ledger, under 'lessons'.",
     "record-keeping; her work is less than legal so she keeps nothing on paper"),
    ("kaelen", "This kind of job leaves the ledger flat. I prefer work that leaves it slightly richer.",
     "record-keeping, and too writerly"),
    ("kaelen", "Safe work pays poorly because it requires no skill.",
     "preachy; she doesn't moralise about skill, she prices risk against pay"),
    ("kaelen", "It closed clean. The money's clean too. Not worth the trouble, but trouble's trouble.",
     "muddled - 'trouble's trouble' means nothing"),
    ("kaelen", "No danger, no reward. This one's on the table, and it's not worth the trouble.",
     "muddled - 'on the table' means nothing here"),
    ("nova", "Hull's intact. You're still breathing. That's enough for now.",
     "maudlin; she is playful, not worried about him"),
    ("nova", "They peeled back my skin and looked inside.",
     "visceral; damage is an indignity to her finish, not an injury"),
    ("nova", "I've been waiting for hands. You're late, Captain.",
     "aimed directly at the Captain; loses deniability"),
]


# ============================================================
# Author approval 2026-08-02, MORNING_2026_08_02 listening set.
# "All of Kaelens are good from this batch. Nova full is also good.
#  The Nova hard burns are all good."
# ============================================================


APPROVED_KAELEN_LOW_PAY_SAFE = [
    "This one didn't cost much. That's the problem — it didn't move anything.",
    "Lights stay on, but nothing moves. Take it, Shiny — just don't expect it to carry us far.",
    "You take it, I take my cut, and we both know it's the same next week.",
    "This one didn't cost me anything. That's not a compliment — it's just math.",
    "Nothing dangerous happened. That's why the pay's not worth talking about.",
    "Nobody got hurt, and that's the only thing that came out ahead.",
]

APPROVED_KAELEN_HIGH_PAY_DANGEROUS = [
    'Bullets cost money, Shiny. This one paid enough to cover the holes.',
    "You got shot at and the fee was worth it. That's the kind I want more of.",
    "Danger's the only thing that pays this well. Glad you came back in one piece, Shiny.",
    "You did the risky part. Got the good pay. That's the trade I like.",
    "Danger and payout are the same coin, Shiny. I like the way it's weighing in your pocket right now.",
    "I'm not asking you to do more — I'm telling you to do more.",
]

APPROVED_KAELEN_PUBLIC_BOARD = [
    "They posted the rate, stuck it on the wall, and waited for someone desperate enough to take it. That's not work. That's a handout.",
    'This is the kind of job you scrape off your boots and leave on the dock, Shiny.',
    "That's pinned up like a trophy. I've seen the people who pick them. Not worth the trouble.",
    "Public listing. Public shame. You're not even trying to hide how bad this looks.",
    "This one's on the wall. No names, no leverage. You're better than that.",
    "That rate's posted where no one else can see it. Guess they figured we're too proud to ask for better.",
]

APPROVED_NOVA_CARGO_FULL = [
    "I'm stuffed to the seams, and I don't mean the cargo holds.",
    "My throat's full. The last load squeezed in tight. I'm not used to this much weight. Well. My intake trunk.",
    "Captain, my hips are full. Can't twist left without scraping. Not that I'm asking you to. Or at least my gimbal mounts.",
    "Cargo's in. My waist's lower. You'd think I was carrying it myself. My midsection coupling, technically.",
    "Hold's full. Can't sit straight. You'll have to help me bend over later.",
    "I'm carrying this like a second spine. You didn't have to stack it so high.",
]

APPROVED_KAELEN_ABANDONED = [
    "They were told it's not happening. I don't get paid for ghosts, Shiny.",
    "You walked. That's a hole in my pocket and a stain on my reputation. Both are yours now.",
    "It's off. No money. And someone just got told we don't finish.",
    "No credit, no pay, and the word's out. That's the price of not closing.",
    "Shiny. You walked. I don't get paid when you walk.",
    'I lose the fee, but I lose the trust worse.',
]

APPROVED_NOVA_HARD_BURN = [
    "Burn's still warm. You don't ask about it. I don't mention how much I like the way you push.",
    "You're pushing me again. My core's still running hot. Must be nice, having someone who doesn't wait.",
    "Throttle's got a taste for the edge. Not that I'm waiting for it to come back.",
    "Engine's hot. You didn't ask. I didn't offer. Let's see how fast you can forget it.",
    "Another push. You don't ask about the heat. I don't mention how much I remember it.",
    "You're running me hot. I don't mind - I like it when you're sure of where you're going.",
]

APPROVED_KAELEN_DECLINED = [
    "You said no. No debt. No regret. That's a skill most don't have, Shiny.",
    "They offered it, and you turned it down. I like that. Some people can't say no - you just did.",
    "Refused before it started. That's a luxury most don't get.",
    "Turned it down. That's your call. I'm not here to argue the price, Shiny.",
    "No money, no trouble. I'm not even going to pretend this was hard.",
]
