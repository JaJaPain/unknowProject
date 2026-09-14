"""N.O.V.A. long transit — reworked to the author's spec (2026-08-02).

Author:
  "a lead in would help a lot. such as 'This is a very long flight. Since you
   got time you could (insert provocative maintenance suggestion here)' Then
   pull it back. There should be a pause between those too so insert a
   '. . .' into the TTS between the lines. try to make them sound sexy and
   playful not bitter or angry. like she just wants his attention not to
   complain for real."

Design consequences:
  - UPDATE 2026-08-02, after listening: the author dropped the pullback.
    "the pullbacks dont hit well. The starting line does though. so we can
     just drop the pause and pullback... the lines sounded like she was sad
     or rejected not playful."
    Also: "there was no noticeable pause between lines" — Kokoro does NOT
    honour a spaced ". . ." as silence. A real pause needs separate TTS calls
    with inserted silence, so the pause idea is parked.
  - MODE_OFFER_ONLY is now the default: lead-in (authored) + offer (model).
  - MODE_WITH_PULLBACK is kept for comparison. Its retraction is reframed:
    the canon pullback ("I forgot I can have my nanobots do that") is her
    CATCHING HERSELF WITH A FACT, not letting him off. Mine were all "never
    mind, you're busy", which reads as rejection — hence "sad".
  - asking for two named fields guarantees both halves exist and puts the
    pause exactly where the author wants it. Left to prose the model merged
    them or dropped the retraction.
  - hook: this is rare time alone with him. She isn't bored and she isn't
    complaining — she wants his attention and the job is a pretext.
  - devices rotate (code-side), because one named move becomes formulaic
    within a run (the automations retraction hit 20/20 that way).
  - longer and meandering: dead air means she has time.
  - the memory gap may surface as vague unease only, never named or explained.
"""
import random

from beat import NOVA_WHO, NOVA_REGISTER
from nova_demos import sample, NOVA as _NOVA_DEMOS

PAUSE = " . . . "

LEAD_INS = [
    "This is a very long flight.",
    "Nothing out here for hours yet.",
    "Long way still to run.",
    "We've a great deal of nothing ahead of us.",
    "Hours of this left, Captain.",
    "Long crossing, and no one else in it.",
    "Plenty of time before anything happens.",
    "It's a long way to the other side of this.",
]

# code picks what she brings up; left to itself the model repeats one part
DETAILS = [
    "her air intakes, which could do with dusting",
    "her secondary manifold, which wants flushing",
    "a coupling on the port side that could stand tightening",
    "the grease on her landing gear",
    "her radiator fins, which have picked up dust",
    "a locker seal that sticks",
    "the scuffing on her docking collar",
    "a filter that could be swapped early",
    "her forward viewport, which has a film on it",
    "a panel latch that rattles",
    "the calibration on her forward sensor",
    "a cable run behind the galley bulkhead",
]

# rotate the MOVE as well as the detail
# Rotated in code: naming one rival in the brief made the model reproduce
# that exact sentence in 6/10 outputs. Same failure as putting a target line
# in a brief, which is documented and which I did anyway.
RIVALS = [
    "the mechanic back at {place}, the one with the nice hands",
    "the yard crew at {place}, who never say no",
    "whoever's on the docking arm when they next put in at {place}",
    "that engineer at {place} who did the last refit and took his time about it",
    "the service hands at {place}",
    "the one at {place} who did her plating, who was very thorough",
    "any of the dock crew at {place}, who'd be glad of the work",
    "the next pair of hands aboard at {place}",
]

# INTEGRATION: fill from the real playthrough. ShipBehaviorObserver already
# carries `last_dock_station` and `station_name` in its event context, and
# GameRoot has the current system id. Naming a place the player actually
# visited is what makes the jealousy land as part of THIS campaign rather
# than as generic flavour.
PLACES_FOR_TESTING = [
    "Kova Station", "Iron Reach", "the Latch", "Bellhaven",
    "Ordos Yard", "Trell's Landing",
]

# Author example of the reminiscence device (2026-08-02):
#   "You know Mrs. Kross scrubs my manifold with a nano vibration gun. I
#    thought I was going to leak coolant if she wasn't careful."
# Note: a NAMED servicer, a real tool, a real failure mode, and she is
# recounting rather than asking. It makes HIM jealous instead of the reverse.
MECHANICS = [
    "Mrs. Kross", "old Ferro", "the Dalley girl", "Mister Ovin",
    "that Bexley woman", "young Tam", "Doctor Hesse", "the Rusk brothers",
]

# Loaded because they are ACCURATE, not because they are euphemisms.
TOOLS = [
    "a nano vibration gun", "a warm solvent bath", "a soft-bristle rotary",
    "an ultrasonic probe", "a pressure flush", "a hand-buffer",
    "a heated seal iron", "a magnetic pick",
]

DEVICES = [
    "She reminisces about a past servicing in far more detail than the moment "
    "requires — who did it, what they used on her, and how close it came to "
    "going wrong. She is not asking him for anything; she is telling him about "
    "somebody else's hands, and letting that sit.",
    "She offers him the job outright, then takes it back.",
    "She wonders aloud whether he'd be any good at it, then decides not to find out.",
    "She points out he has nothing better to do, then withdraws the invitation.",
    "She describes what the job would involve in more detail than strictly necessary, "
    "then drops it.",
    "She says she wasn't going to mention it, mentions it, then says forget it.",
    "She asks whether he's ever done it before, then tells him not to answer.",
]

PACKETS = [
    "They've been flying a long time with nothing around them.",
    "Empty space in every direction and hours of it behind them.",
    "A long crossing, entirely uneventful so far.",
    "Still in transit. The scopes have been empty the whole way.",
    "Nothing has happened for a long stretch and nothing is nearby.",
    "A long haul, and no traffic at all.",
    "Dead easy crossing with plenty of it left.",
    "No contacts, no events, and a lot of flight still to go.",
]

BRIEF = """{who}

{register}

Right now she has him entirely to herself. No dock crew, no broker on the line, no one else
wanting anything from him — just a long stretch of nothing and the two of them in it. She likes
this more than she would ever say, and she is going to spend it getting his attention.

So she invents a reason to have him touch something of hers. The job is a pretext and she barely
pretends otherwise. She is warm, playful and a little suggestive — never bitter, never nagging,
never actually complaining. Nothing is wrong with her and she doesn't want anything fixed; she
wants him over here.

{device}

If it helps, {mechanic} has serviced her before and is the sort to use {tool} on her. Use that
only if the device above calls for it.

She has already said this out loud: "{lead}"
You are writing what comes next, in two parts.

The OFFER: she raises {detail} and dangles it in front of him. Provocative, unhurried, and
entirely ordinary maintenance talk on its face.

The PULLBACK: she does NOT let him off. She mentions, lightly, that {rival} would be glad to do
it instead. Say it as pure convenience — people service ships, that's all she means — and put
her own spin on it in her own words. Do not use the phrasing given here; find another way to
land the same idea.

This keeps the pressure on him rather than releasing it. She is not withdrawing, not resigned,
not giving up and not sad — she is making it clear the offer has other takers. She never says
she's jealous and never asks him to choose. She just mentions the alternative and lets it sit.

Never "never mind". Never "you've got better things to do". Never "it's automated" — the point
is that a person would do it, not a machine.

Every word stays literally true, ordinary maintenance talk — real parts, real jobs. The
suggestion lives in the listener's head, never in what she actually says. She invents no number,
no fault, no threat, and gives no order.

She may, rarely, let slip that something about her own memory feels incomplete — never named,
never explained, never dwelt on, and never in the same line as the offer.

She has time here, so let her meander. Each part can run to a couple of short sentences.

Here is her voice on other occasions:

{shown}

Return ONLY this JSON object, with exactly two keys:
{{"offer":"...","pullback":"..."}}"""


# Offer-only: the author's preferred shape after listening. No pause, no
# retraction — the provocative opener is the whole line.
BRIEF_OFFER_ONLY = BRIEF.split("The PULLBACK:")[0].rstrip() + """

Every word stays literally true, ordinary maintenance talk — real parts, real jobs. The
suggestion lives in the listener's head, never in what she actually says. She invents no number,
no fault, no threat, and gives no order.

She has time here, so let her meander a little. Two or three short sentences.

Here is her voice on other occasions:

{shown}

Return ONLY this JSON object, with exactly one key: {{"offer":"..."}}"""


_detail_bag = []


def _next_detail(rng: random.Random) -> str:
    """Without replacement: rng.choice repeated 'collar' 4/10 in one run."""
    global _detail_bag
    if not _detail_bag:
        _detail_bag = DETAILS[:]
        rng.shuffle(_detail_bag)
    return _detail_bag.pop()


def compose(rng: random.Random, packet: str, with_pullback: bool = False,
            place: str = ""):
    demos = sample(rng, 4, avoid_facts=packet)
    shown = "\n\n".join(f'"{l}"' for _s, _f, l in demos)
    lead = rng.choice(LEAD_INS)
    template = BRIEF if with_pullback else BRIEF_OFFER_ONLY
    prompt = template.format(
        who=NOVA_WHO, register=NOVA_REGISTER, device=rng.choice(DEVICES),
        lead=lead, detail=_next_detail(rng), shown=shown,
        mechanic=rng.choice(MECHANICS), tool=rng.choice(TOOLS),
        rival=rng.choice(RIVALS).format(place=place or rng.choice(PLACES_FOR_TESTING)))
    return prompt, lead


def join(lead: str, offer: str, pullback: str) -> str:
    """lead-in + offer + authored pause + pullback."""
    parts = [lead.rstrip(), offer.strip()]
    head = " ".join(p for p in parts if p)
    return head.rstrip() + PAUSE + pullback.strip()


DEMO_LINES = [l for _s, _f, l in _NOVA_DEMOS]
