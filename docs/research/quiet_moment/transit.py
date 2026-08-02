"""N.O.V.A. long transit — reworked to the author's spec (2026-08-02).

Author:
  "a lead in would help a lot. such as 'This is a very long flight. Since you
   got time you could (insert provocative maintenance suggestion here)' Then
   pull it back. There should be a pause between those too so insert a
   '. . .' into the TTS between the lines. try to make them sound sexy and
   playful not bitter or angry. like she just wants his attention not to
   complain for real."

Design consequences:
  - the beat has THREE parts, and code owns two of them:
      lead-in (authored, rotated) + offer (model) + " . . . " + pullback (model)
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
DEVICES = [
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

She has already said this out loud: "{lead}"
You are writing what comes next, in two parts.

The OFFER: she raises {detail} and dangles it in front of him. Provocative, unhurried, and
entirely ordinary maintenance talk on its face.

The PULLBACK: she takes it away again, and she enjoys doing it. She can change her mind, claim
she was only testing him, admit she wanted him to look up, or airily decide it can wait. It
should land like a wink — she is letting him off a hook she never meant to set, and both of them
know it.

The pullback is never sad, never self-pitying, and never tells him he has better things to do.
She is not releasing him because she doesn't matter; she's releasing him because she's enjoying
having the upper hand.

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


_detail_bag = []


def _next_detail(rng: random.Random) -> str:
    """Without replacement: rng.choice repeated 'collar' 4/10 in one run."""
    global _detail_bag
    if not _detail_bag:
        _detail_bag = DETAILS[:]
        rng.shuffle(_detail_bag)
    return _detail_bag.pop()


def compose(rng: random.Random, packet: str):
    demos = sample(rng, 4, avoid_facts=packet)
    shown = "\n\n".join(f'"{l}"' for _s, _f, l in demos)
    lead = rng.choice(LEAD_INS)
    prompt = BRIEF.format(
        who=NOVA_WHO, register=NOVA_REGISTER, device=rng.choice(DEVICES),
        lead=lead, detail=_next_detail(rng), shown=shown)
    return prompt, lead


def join(lead: str, offer: str, pullback: str) -> str:
    """lead-in + offer + authored pause + pullback."""
    parts = [lead.rstrip(), offer.strip()]
    head = " ".join(p for p in parts if p)
    return head.rstrip() + PAUSE + pullback.strip()


DEMO_LINES = [l for _s, _f, l in _NOVA_DEMOS]
