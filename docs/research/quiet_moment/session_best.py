"""Best lines from the 2026-08-01 build-out, for a listening pass.

Hand-picked from the run artifacts using the ear calibrated against the
author's earlier accept/reject decisions. Unedited — exactly as generated,
except where anatomy.py appended the correction (marked).
"""

KAELEN_LOW_PAY_SAFE = [
    "This one didn't cost much. That's the problem — it didn't move anything.",
    "Lights stay on, but nothing moves. Take it, Shiny — just don't expect it to carry us far.",
    "You take it, I take my cut, and we both know it's the same next week.",
    "This one didn't cost me anything. That's not a compliment — it's just math.",
    "Nothing dangerous happened. That's why the pay's not worth talking about.",
    "Nobody got hurt, and that's the only thing that came out ahead.",
]

KAELEN_HIGH_PAY_DANGEROUS = [
    "Bullets cost money, Shiny. This one paid enough to cover the holes.",
    "You got shot at and the fee was worth it. That's the kind I want more of.",
    "Danger's the only thing that pays this well. Glad you came back in one piece, Shiny.",
    "You did the risky part. Got the good pay. That's the trade I like.",
    "Danger and payout are the same coin, Shiny. I like the way it's weighing in your pocket right now.",
    "I'm not asking you to do more — I'm telling you to do more.",
]

KAELEN_PUBLIC_BOARD = [
    "They posted the rate, stuck it on the wall, and waited for someone desperate enough to take it. That's not work. That's a handout.",
    "This is the kind of job you scrape off your boots and leave on the dock, Shiny.",
    "That's pinned up like a trophy. I've seen the people who pick them. Not worth the trouble.",
    "Public listing. Public shame. You're not even trying to hide how bad this looks.",
    "This one's on the wall. No names, no leverage. You're better than that.",
    "That rate's posted where no one else can see it. Guess they figured we're too proud to ask for better.",
]

NOVA_POST_COMBAT_DAMAGED = [
    "You'll still need to scrape that burn out of my aft struts. Not that I mind the attention.",
    "I've got a few loose panels waiting for fingers. Who do we know with steady hands?",
    "They'll need to strip back the plating. It's not pretty under there. You'd think I'd be more embarrassed.",
    "My plating's got teeth marks and I'm going to need someone with patience to smooth this out.",
]

NOVA_REPAIR_DONE = [
    "They stripped me back to the frame and didn't miss a seam. You'd think they were fond of me.",
    "They took six hours, and I'm still warm where they touched me.",
    "All the seals are tight. They didn't even need to ask — they just knew how to hold a thing.",
    "They stripped back my plating and found nothing wrong. I'm clean inside. They'll be disappointed.",
    "They tightened every bolt twice. I can feel it in my struts. They were showing off.",
    "They polished my hull like they meant it. Didn't leave a mark. You'd think they were afraid of me.",
]

NOVA_LONG_TRANSIT = [
    "There's a tangle of cable behind the galley bulkhead. I could wait for maintenance. Or I could wait for you.",
    "My intakes are clean. They've been waiting for you to notice.",
    "Secondary manifold needs flushing. I'll wait. Maybe I'll forget. Maybe I won't.",
    "My viewport's got a film on it. You could wipe it. I'll tell you what - I'll let it stay.",
    "Locker seal's stuck. You could warm it up. Not that I need fixing.",
    "There's a filter that could go early. I'll wait. Just don't forget I mentioned it.",
]

# ** = anatomy.py appended the correction deterministically
NOVA_CARGO_FULL = [
    "I'm stuffed to the seams, and I don't mean the cargo holds.",
    "Captain, my hips are full. Can't twist left without scraping. Not that I'm asking you to. Or at least my gimbal mounts.",
    "My throat's full. The last load squeezed in tight. I'm not used to this much weight. Well. My intake trunk.",
    "Cargo's in. My waist's lower. You'd think I was carrying it myself. My midsection coupling, technically.",
    "Hold's full. Can't sit straight. You'll have to help me bend over later.",
]

KAELEN_ABANDONED = [
    "They were told it's not happening. I don't get paid for ghosts, Shiny.",
    "You walked. That's a hole in my pocket and a stain on my reputation. Both are yours now.",
    "It's off. No money. And someone just got told we don't finish.",
    "No credit, no pay, and the word's out. That's the price of not closing.",
    "Shiny. You walked. I don't get paid when you walk.",
    "I lose the fee, but I lose the trust worse.",
]

NOVA_ROUGH_ARRIVAL = [
    "You took a turn I didn't expect. My spine's still humming from it. You're lucky I don't have a jaw to bite you with.",
    "You got me scraped up on the dock. I'll be picking bits of hull out of my hair for weeks.",
    "You carried me in like a sack of scrap. My seams are still smarting. You're welcome.",
    "You set me down like a crate. I've got a spine, Captain. Try not to forget that next time.",
    "You handled me like I wasn't awake. My waist still remembers the way you dragged me in.",
]

NOVA_HARD_BURN = [
    "Burn's still warm. You don't ask about it. I don't mention how much I like the way you push.",
    "You're pushing me again. My core's still running hot. Must be nice, having someone who doesn't wait.",
    "Throttle's got a taste for the edge. Not that I'm waiting for it to come back.",
    "Engine's hot. You didn't ask. I didn't offer. Let's see how fast you can forget it.",
    "Another push. You don't ask about the heat. I don't mention how much I remember it.",
    "You're running me hot. I don't mind - I like it when you're sure of where you're going.",
]

BEATS = [
    ("kaelen", "low_pay_safe", KAELEN_LOW_PAY_SAFE),
    ("kaelen", "high_pay_dangerous", KAELEN_HIGH_PAY_DANGEROUS),
    ("kaelen", "public_board", KAELEN_PUBLIC_BOARD),
    ("nova", "post_combat_damaged", NOVA_POST_COMBAT_DAMAGED),
    ("nova", "repair_done", NOVA_REPAIR_DONE),
    ("nova", "long_transit", NOVA_LONG_TRANSIT),
    ("nova", "cargo_full", NOVA_CARGO_FULL),
    ("kaelen", "abandoned", KAELEN_ABANDONED),
    ("nova", "rough_arrival", NOVA_ROUGH_ARRIVAL),
    ("nova", "hard_burn", NOVA_HARD_BURN),
]
