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
