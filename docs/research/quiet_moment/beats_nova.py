"""N.O.V.A. beats."""
from beat import NOVA_WHO, NOVA_REGISTER, NOVA_SCOPE
from nova_demos import sample, NOVA as _NOVA_DEMOS

_BASE = {"speaker": "nova", "cap": 30, "who": NOVA_WHO,
         "register": NOVA_REGISTER, "scope": NOVA_SCOPE, "sample": sample,
         "demo_lines": [l for _s, _f, l in _NOVA_DEMOS]}

# ------------------------------------------------- post-combat, damaged
POST_COMBAT_DAMAGED = dict(_BASE, **{
    "id": "nova_post_combat_damaged",
    "packets": [
        "The fight is over. The ship took a beating and needs work at a dock.",
        "They're gone, but not before opening up a stretch of her plating.",
        "Combat's finished. There's damage down one side that a yard will have to fix.",
        "It's over. She's flyable, but something back there needs real repair work.",
        "The shooting stopped. The hull is scored and buckled in places.",
        "No one's chasing now. The ship came through it, but not neatly.",
        "Fight's done. There's a list of things needing a mechanic before this goes further.",
        "They broke off. A good deal of her outer plating is chewed up.",
        "Battle over, ship intact but ugly. Dock work required.",
        "The last of them ran. She's holed in a few places that will need patching.",
        "Quiet now. The ship is going to need hands on her before the next run.",
        "Done fighting. There's damage. Nothing critical, but nothing pretty either.",
    ],
    "valence": """The damage is an indignity, not an injury. She's vain about her finish and put out about the
scheduling — a dancer complaining about a scuffed floor, not a person describing a wound. Keep
it to plating, panels, paint, dents, scoring.

She makes no claim about whether this has happened before.""",
})

# ------------------------------------------------- repair completed
REPAIR_DONE = dict(_BASE, **{
    "id": "nova_repair_done",
    "packets": [
        "The repair work is finished. The yard crew have signed off and gone.",
        "She's back together. The mechanic packed up an hour ago.",
        "Every panel they opened is closed again.",
        "Nothing on her is outstanding any more.",
        "Repairs are done and the crew have cleared out.",
        "Signed off, all of it. Nobody aboard but the two of them now.",
        "Her plating is whole again for the first time in a while.",
        "Fixed, buffed, and handed back.",
        "Servicing complete. Panels are back on.",
        "Somebody spent six hours on her and has now gone home.",
        "Everything on the list got done, and the dock is quiet again.",
        "Whatever was wrong with her isn't wrong any more.",
    ],
    "valence": """The work is finished and she's pleased with the result — she likes being in good order, and
she's a little smug about how she looks now. She has opinions about the crew who did it: whether
they were thorough, gentle, quick, careless. She's allowed to have enjoyed the attention and
allowed to be sniffy about it.

The yard crew did this work, not the Captain. He was not the one with his hands on her — she is
telling him about other people. Keep the "you" for him and the "they" for the crew, and don't
mix them up.

She makes no claim about what happens next and makes no claim about whether this has happened
before. Nothing is wrong with her now — she does not invent a remaining fault.""",
})

# ------------------------------------------------- long clean transit
LONG_TRANSIT = dict(_BASE, **{
    "id": "nova_long_transit",
    "packets": [
        "They've been flying a long time. Nothing has happened and nothing is nearby.",
        "Hours of empty space so far, and a while still to run.",
        "It's a long haul with nothing to look at.",
        "Still in transit. The scopes have been empty the whole way.",
        "A long stretch with nothing around them.",
        "Dead easy crossing, and plenty of it left.",
        "Long run. Empty scopes. No traffic at all.",
        "The route is long and completely uneventful so far.",
        "No contacts, no events, and a lot of flight left.",
        "Empty in every direction, and hours of it behind them.",
        "This crossing has been simple from the start.",
        "A long stretch of nothing, with no one else out here.",
    ],
    "valence": """Nothing is wrong and nothing needs doing, and that's exactly the problem — she's bored, and
being bored makes her mischievous. This is where she starts inventing jobs for him, then
withdrawing them.

Her best move here: mention something on her that could use attention, offer him the job, then
take it back with a mundane technical fact — she has automatics for that, or it can wait. The
retraction is the joke and it should land as its own beat.

She does not comment on the silence or the quiet — that's the obvious observation and she's
better than that. She makes no claim about what's ahead or how long remains.""",
})

BEATS = {b["id"]: b for b in (POST_COMBAT_DAMAGED, REPAIR_DONE, LONG_TRANSIT)}
