"""N.O.V.A. long transit — one beat, two devices, rotated in code.

Author settled this over several passes:
  - the offer/pullback shape is dead. The retraction always read as
    rejection, and the ". . ." pause is inaudible in Kokoro anyway.
  - DANGLE survives, without a pullback: she offers him the job and stops.
  - JEALOUSY is the better device: she recounts somebody ELSE having their
    hands on her, in loaded technical detail, and lets him sit with it.
    ("You know Mrs. Kross scrubs my manifold with a nano vibration gun. I
     thought i was going to leak coolant if she wasnt careful")
  - "it can be both" — so code rotates, and neither wears out.

Both devices share the lead-in, the register and the deniability rule; they
differ only in what she does with the moment.
"""
import random

from beat import NOVA_WHO, NOVA_REGISTER
from nova_demos import sample, NOVA as _NOVA_DEMOS
import transit_jealous as TJ
import transit_vocab as VOCAB

SPEAKER = "nova"
CAP = 45
DEMO_LINES = [l for _s, _f, l in _NOVA_DEMOS]

LEAD_INS = TJ.LEAD_INS
PACKETS = TJ.PACKETS
MECHANICS = TJ.MECHANICS
# Loaded-but-accurate: see transit_vocab for the two-readings rule.
TOOLS = VOCAB.TOOLS
PARTS = VOCAB.PARTS
MISHAPS = VOCAB.MISHAPS

DETAILS = VOCAB.DETAILS


_HEAD = """{who}

{register}

She has him entirely to herself right now. No dock crew, no broker on the line, nobody else
wanting anything from him — a long stretch of nothing and the two of them in it. She likes that
more than she would ever say, and she is going to spend it on his attention.

She has already said this out loud: "{lead}"
Write what she says next."""

_TAIL = """
Every word is literally true, ordinary maintenance talk — real parts, real jobs. A ship engineer
would hear nothing unusual. The suggestion lives entirely in the listener's head, and if a phrase
only works as innuendo it is wrong.

She is warm and playful, never bitter, never nagging and never sad. Nothing is wrong with her.
Two or three short sentences. She invents no number, no fault she doesn't have, no threat, and
gives no order.

Here is her voice on other occasions:

{shown}

Return ONLY this JSON object, with exactly one key: {{"line":"..."}}"""

DANGLE = _HEAD + """

She raises {detail} and dangles it in front of him — unhurried, and rather more inviting than
the job deserves. She does NOT then take it back, apologise for mentioning it, or tell him it's
automated. She offers, and leaves the offer standing.
""" + _TAIL

JEALOUSY = _HEAD + """

She is trying to make him jealous, and she will never admit it. She talks about somebody else
who has had their hands on her — a servicing, a refit, entirely innocent, described in rather
more detail than anybody needed. She wants him to picture it and be faintly bothered.

The memory she's drawing on: {mechanic} once worked on {part}, using {tool}, and {mishap}.

That is raw material, not a sentence plan. She might lead with the mishap, with the tool, with
how long it took, or with what she was thinking at the time. She might not name the person until
the end. Do NOT produce "NAME did TOOL to PART, then MISHAP" — that's a service record, not
speech.

She tells it fondly and in passing, the way you'd mention a good haircut, and then stops. She
does not ask him for anything, does not compare him to anyone, and never says she's jealous.
""" + _TAIL

DEVICES = ("dangle", "jealousy")

_bags = {}


def _draw(rng, key, pool):
    """Without replacement. rng.choice repeated one detail 4/10 in a run."""
    bag = _bags.get(key) or []
    if not bag:
        bag = pool[:]
        rng.shuffle(bag)
    _bags[key] = bag
    return bag.pop()


def compose(rng: random.Random, packet: str, device: str = "", mechanic: str = ""):
    device = device or _draw(rng, "device", list(DEVICES))
    demos = sample(rng, 4, avoid_facts=packet)
    shown = "\n\n".join(f'"{l}"' for _s, _f, l in demos)
    lead = _draw(rng, "lead", LEAD_INS)
    common = dict(who=NOVA_WHO, register=NOVA_REGISTER, lead=lead, shown=shown)
    if device == "jealousy":
        prompt = JEALOUSY.format(
            mechanic=mechanic or _draw(rng, "mech", MECHANICS),
            tool=_draw(rng, "tool", TOOLS), part=_draw(rng, "part", PARTS),
            mishap=rng.choice(MISHAPS), **common)
    else:
        prompt = DANGLE.format(detail=_draw(rng, "detail", DETAILS), **common)
    return prompt, lead, device


# ---- adapter so the selector/playthrough can treat this like any other beat
class Module:
    """compose() returns three values; the runtime wants prompt(packet, rng)."""
    PACKETS = PACKETS
    SPEAKER = SPEAKER
    CAP = CAP
    DEMO_LINES = DEMO_LINES
    THIRD_PARTIES = MECHANICS
    __name__ = "nova_long_transit"
    _last = {"lead": "", "device": ""}

    @staticmethod
    def prompt(packet, rng):
        p, lead, device = compose(rng, packet)
        Module._last = {"lead": lead, "device": device}
        return p

    @staticmethod
    def lead_in():
        return Module._last["lead"]
