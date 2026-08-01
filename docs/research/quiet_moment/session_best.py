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
    "I showed up, took my cut, and got in the way of someone who could've done it better.",
    "This one didn't need me. I'm good at that — not needed. Not wanted.",
    "I charge for what I bring to the table, and I brought nothing.",
    "This one's already written for me. I'm just here to read it.",
    "I showed up. They paid. That's all I do here, Shiny.",
    "I'm just a backseat driver on a job that drove itself.",
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
    "Secondary manifold wants flushing. You could do it. But I've got autos on standby. They're reliable. They don't flirt.",
    "Grease on the landing gear's due. I suppose you could do it... if you're not too busy pretending to be useful.",
    "Filter's loose. You could swap it if you wanted. Don't worry, I'll hold still. Just don't get attached.",
    "My intakes could use a brush. I'll leave it. You'd probably drop the tool. I'd rather not know what that looks like.",
    "Filter's loose in the intake. You could swap it. No, I'll hold it. See how long you wait before asking why.",
    "Secondary manifold's due for a flush. I'd say you're just the one to do it... but the automatics handle it every cycle.",
]

# ** = anatomy.py appended the correction deterministically
NOVA_CARGO_FULL = [
    "I'm full. You can feel it in my ribs. The cargo's heavy. I don't ask you to lift it. Or at least my frame spars.",
    "I'm stuffed. You can feel it in the bulkheads. My ribs are aching from it. My frame spars, technically.",
    "Captain. My belly's full. Can't take another thing. You'll have to find someone else to carry the rest. That is — my cargo hold.",
    "I'm stuffed to the frames. My ribs are full. You'd think I'd be more graceful about it. Frame spars, if we're being accurate.",
    "I'm stuffed to the seams, and I don't mean the cargo holds.",
]

KAELEN_ABANDONED = [
    "I lose the fee, but I lose the trust worse.",
    "You bailed mid-job. That's what I'm charging for.",
    "It's not done, and that's the whole job. You know what that costs me.",
    "No credit came through. That's the cost of not finishing. I don't do unfinished.",
    "Name's attached to failure, and I don't get paid for that, Shiny.",
]

NOVA_ROUGH_ARRIVAL = [
    "You took a turn I didn't expect. My spine's still humming from it. You're lucky I don't have a jaw to bite you with.",
    "You got me scraped up on the dock. I'll be picking bits of hull out of my hair for weeks.",
    "You carried me in like a sack of scrap. My seams are still smarting. You're welcome.",
    "You set me down like a crate. I've got a spine, Captain. Try not to forget that next time.",
    "You handled me like I wasn't awake. My waist still remembers the way you dragged me in.",
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
]
