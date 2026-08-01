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
    # Code owns which part she fusses about. Left to itself the model said
    # "my struts are loose" in 5/20.
    "detail_pool": [
        "her air intakes, which could do with dusting",
        "a coupling on the port side that could stand tightening",
        "her forward viewport, which has a film on it",
        "the grease on her landing gear, which is overdue",
        "a filter that could be swapped early",
        "her radiator fins, which have picked up dust",
        "a locker seal that sticks",
        "the scuffing on her docking collar",
        "her secondary manifold, which wants flushing",
        "a panel latch that rattles at certain speeds",
        "the calibration on her forward sensor, which has drifted a hair",
        "a cable run behind the galley bulkhead that's untidy",
    ],
    "detail_prompt": "The thing she chooses to bring up is {detail}.",
    "valence": """Nothing is wrong and nothing needs doing, and that's exactly the problem — she's bored, and
being bored makes her mischievous. This is where she starts inventing jobs for him, then
withdrawing them.

Her move here: mention the thing that could use attention, dangle it in front of him, then take
it back. The retraction is the joke and it should land as its own beat.

Vary how she takes it back. Sometimes it's automated. Sometimes it can wait. Sometimes she'd
rather keep the fault than lose his company while he fixes it. Sometimes she changes the subject
and pretends she never raised it. Sometimes she admits she only mentioned it to see what he'd
say. Don't reach for the automatics every time.

The teasing NEVER implies he's useless, clumsy, incompetent, or that a machine would do better
than him. She's flirting, not needling — she'd rather have his attention than the job done. If a
line would sting to hear, it's wrong.

She does not comment on the silence or the quiet — that's the obvious observation and she's
better than that. She makes no claim about what's ahead or how long remains.""",
})

# ------------------------------------------------- hold loaded to capacity
# Author's canon for this beat: "woh that load has me filled up to my larynx,
# or at least my vocal processor."
CARGO_FULL = dict(_BASE, **{
    "id": "nova_cargo_full",
    "packets": [
        "The hold is loaded to capacity. There's no room left aboard.",
        "Cargo's aboard, every last crate of it. She's full.",
        "They've packed her out. Nothing else is going to fit.",
        "Full load. The hold won't take another thing.",
        "Loading finished. She's carrying as much as she's rated for.",
        "Every bay is packed and the doors are shut.",
        "She's heavy. The hold is at its limit.",
        "The last of it went aboard a few minutes ago. She's at capacity.",
        "Stuffed to the frames. Nothing more fits.",
        "Capacity reached. That's everything loaded.",
        "The whole consignment is aboard and she's riding low.",
        "Loaded out completely — there isn't a spare metre in there.",
    ],
    "valence": """She is enormously, theatrically full, and she wants him to know about it. She's carrying more
than she'd like, she can feel the weight of it, and she is not going to be quiet about that.

Her best move here is UNDERSTATEMENT. One short remark carrying an obvious innocent meaning and
a second one she leaves completely alone — no wink, no explanation, no follow-through. She says
it flatly and moves on, as though she hadn't noticed what she said.

Do not over-explain the joke and do not stack a second one on top of it. Vary how she gets
there: sometimes she describes the weight, sometimes how she's sitting, sometimes what she can't
do while loaded, sometimes what the crew had to do to fit it in. Reach for a human body part
only where it genuinely fits better than the ship word.

She's complaining for entertainment, not because anything is wrong. Nothing is damaged, nothing
is unsafe, and she doesn't ask him to unload anything. She makes no claim about where the cargo
is going, what it is worth, or who it's for.""",
})

BEATS = {b["id"]: b for b in (POST_COMBAT_DAMAGED, REPAIR_DONE, LONG_TRANSIT, CARGO_FULL)}


# ------------------------------------------------- rough arrival
ROUGH_ARRIVAL = dict(_BASE, **{
    "id": "nova_rough_arrival",
    "packets": [
        "That arrival was rough. She's down safe but it wasn't tidy.",
        "He put her down hard. Nothing broke.",
        "Docked, eventually. The approach was a mess.",
        "They're stationary. Getting there involved more contact than it needed to.",
        "Arrival complete, and it was not elegant.",
        "She's parked. The last thirty seconds were ugly.",
        "Down, safe, and badly. Nothing is damaged.",
        "The approach went sideways but they're secured now.",
        "Rough set-down. She took it without complaint until now.",
        "They made it in. Grace was not involved.",
        "That docking was heavy-handed from start to finish.",
        "Secured. The manoeuvre that got them here was scruffy.",
    ],
    "valence": """Nothing is damaged and she knows it, so this is entirely about her dignity. She's been handled
carelessly in public, at a dock where other ships can see, and she is going to have something to
say about that.

THE CAPTAIN did this — he was flying. This is the one beat where the teasing points straight at
him rather than at a dock crew, so it's "you", not "they". Nobody else touched her.

She teases him rather than scolds — she's not actually angry, and she'd never suggest he's a bad
pilot. It's the indignity of it, and she milks it.

She makes no claim about damage, does not tell him how to fly, and makes no claim about whether
this has happened before.""",
})
BEATS["nova_rough_arrival"] = ROUGH_ARRIVAL

# ------------------------------------------------- boost again, quickly
HARD_BURN = dict(_BASE, **{
    "id": "nova_hard_burn",
    "packets": [
        "The boost is lit again, not long after the last one.",
        "Another burn, hard on the heels of the previous one.",
        "That's the throttle wide open again, barely any gap.",
        "Leaning on the drive again already.",
        "Back to full power with almost no pause since the last time.",
        "Another shove on the drive, soon after the last.",
        "Boosting again. The previous burn is barely cold.",
        "Full throttle again, in short order.",
        "Hard acceleration once more, with little recovery between.",
        "Again, close together, at full power.",
        "The drive's been pushed hard again after almost no pause.",
        "Another burn, and she's had no time to settle since the last.",
    ],
    "valence": """She is not worried — nothing is at risk — but she's very aware of being pushed hard twice in a
row, and that's exactly the sort of thing she'll comment on.

This is where she's at her most suggestive, and it stays deniable because every word is ordinary
talk about drive load, heat and recovery time.

Vary what she does with it. Sometimes she notes the heat. Sometimes she observes that he didn't
ask. Sometimes she claims she doesn't mind, in a way that makes clear she noticed. Sometimes
she comments on his enthusiasm for the throttle. Sometimes she says nothing about wanting a
pause at all and just remarks on how hard he's driving.

Do NOT ask for a warning "next time" — that phrasing has been used to death. She does not tell
him to stop, does not claim anything is damaged, and invents no readings or intervals.""",
})
BEATS["nova_hard_burn"] = HARD_BURN


# ------------------------------------------------- back at the same station
RETURNED_SAME = dict(_BASE, **{
    "id": "nova_returned_same_station",
    "packets": [
        "They're back at the same station they left a short while ago.",
        "Same dock, same clamps, not much time in between.",
        "This is the station they departed from recently.",
        "Back where they started, and it hasn't been long.",
        "The same berth as before. They haven't been gone long.",
        "Returned to the station they'd only just left.",
        "Docked again at the place they set out from.",
        "Same station, second visit, short gap.",
        "They've come back round to where they were.",
        "This berth is the one they used earlier.",
        "Back at the same clamps as before.",
        "Full circle, and not much of one.",
    ],
    "valence": """She noticed. Of course she noticed — she notices everything — and she's going to make sure he
knows she noticed, without ever suggesting he's lost or disorganised.

Her angle is that she's perfectly happy to keep going round in circles as long as he's the one
flying, and she'd rather be here twice than somewhere interesting alone. It's affectionate
teasing about the route, never about his competence.

She makes no claim about why they came back, what they're doing here, or what happens next. She
does not name the station.""",
})
BEATS["nova_returned_same_station"] = RETURNED_SAME
