"""N.O.V.A. long transit, rebuilt around ONE idea: she is making him jealous.

Author, after hearing the earlier attempts:
  "think of it like trying to make the player jelous"
  "other lines could be like 'You know Mrs. Kross scrubs my manifold with a
   nano vibration gun. I thought i was going to leak coolant if she wasnt
   careful'"

That reframes the beat. Earlier versions treated it as "she wants his
attention and invents a pretext" — offer, then retract. The retraction read
as rejection and the offers read as chores. The real move is simpler and
much funnier: she talks, in loaded technical detail, about OTHER PEOPLE
having their hands on her, and lets him sit with it.

Why this works where the offer/pullback did not:
  - nothing is withdrawn, so nothing sounds like rejection;
  - the innuendo is displaced onto a named third party, which is her
    established deniability mechanism;
  - it makes HIM react instead of asking him for anything.

Single output field. The two-field offer/pullback shape is retired — the
field names themselves steered the model back into chore-assignment.
"""
import random

from beat import NOVA_WHO, NOVA_REGISTER
from nova_demos import sample, NOVA as _NOVA_DEMOS

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

# Named servicers. Mixed, titled, ordinary — a real person the player could
# have met, not "a mechanic". INTEGRATION: draw these from the current or
# last visited system so the jealousy lands inside THIS campaign.
MECHANICS = [
    "Mrs. Kross", "old Ferro", "the Dalley girl", "Mister Ovin",
    "that Bexley woman", "young Tam", "Doctor Hesse", "Sella Rusk",
]

# Loaded because they are ACCURATE, never because they are euphemisms.
TOOLS = [
    "a nano vibration gun", "a warm solvent bath", "a soft bristle rotary",
    "an ultrasonic probe", "a slow pressure flush", "a hand buffer",
    "a heated seal iron", "a fine magnetic pick",
]

PARTS = [
    "my manifold", "my intakes", "my coupling housings", "my access ports",
    "my plating seams", "my radiator fins", "my docking collar",
    "my injector rail", "my forward viewport", "my strut housings",
]

# what nearly went wrong — real failure modes, all suggestive by accident
MISHAPS = [
    "I thought I was going to leak coolant",
    "I very nearly vented",
    "I thought a seal was going to give",
    "I came close to losing pressure entirely",
    "I thought something was going to pop loose",
    "I had to run a diagnostic afterwards to settle down",
]

PACKETS = [
    "They've been flying a long time with nothing around them.",
    "Empty space in every direction and hours of it behind them.",
    "A long crossing, entirely uneventful so far.",
    "Still in transit. The scopes have been empty the whole way.",
    "Nothing has happened for a long stretch and nothing is nearby.",
    "A long haul, and no traffic at all.",
]

BRIEF = """{who}

{register}

THE POINT OF THIS LINE: she is trying to make the Captain jealous.

She has him to herself, there is nothing to do, and so she starts talking about other people who
have had their hands on her. Servicing, maintenance, a refit — all completely innocent, all
described in rather more detail than anybody needed. She wants him to picture it. She wants him
slightly bothered. She will never admit that is what she's doing.

She has already said this out loud: "{lead}"
Write what she says next.

The memory she's drawing on: {mechanic} once worked on {part}, using {tool}, and {mishap}.

That is raw material, not a sentence plan. She might lead with the mishap, or with the tool, or
with how long it took, or with what she was thinking at the time. She might not name the person
until the end, or at all. She might mention only part of it. Do NOT produce "NAME did TOOL to
PART, then MISHAP" — that's a service record, not speech.

She recounts it fondly and in passing, the way you'd mention a good haircut. She does NOT ask
the Captain to do anything, does not compare him to anyone, does not say she's jealous or wants
him jealous, and does not explain the story. She tells it and stops.

Every word is literally true, ordinary maintenance talk. A ship engineer would hear a service
record. The suggestion is entirely in the listener's head — that deniability is the joke, and if
a phrase only works as innuendo it is wrong.

Two or three short sentences. She invents no number, no fault she doesn't have, no threat, and
gives no order.

Here is her voice on other occasions:

{shown}

Return ONLY this JSON object, with exactly one key: {{"line":"..."}}"""


def compose(rng: random.Random, packet: str, mechanic: str = ""):
    demos = sample(rng, 4, avoid_facts=packet)
    shown = "\n\n".join(f'"{l}"' for _s, _f, l in demos)
    lead = rng.choice(LEAD_INS)
    prompt = BRIEF.format(
        who=NOVA_WHO, register=NOVA_REGISTER, lead=lead,
        mechanic=mechanic or rng.choice(MECHANICS), tool=rng.choice(TOOLS),
        part=rng.choice(PARTS), mishap=rng.choice(MISHAPS), shown=shown)
    return prompt, lead


DEMO_LINES = [l for _s, _f, l in _NOVA_DEMOS]
