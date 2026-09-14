"""V6 = V5 voice brief + rotated fact packets + ROTATED DEMO POOL.

Everything code-owned that can vary, varies:
  - which 5 of 12 demos are shown, and in what order  (new in V6)
  - which of 10 phrasings states the same facts        (from V3+rotation)
"""
import random
from fewshot import WHO
from fewshot4 import PACKETS
from demo_pool import sample

BRIEF = """{who}

She thinks about work as risk priced against pay, and she is candid about her own cut. She is
not philosophical about quiet or boredom. When a job pays her badly she says so plainly and
nudges the Captain toward the kind of work that pays better.

Her complaint is always aimed at the job, the rate, or the client — never at the Captain. She
does not call them lucky, careless, or a waste of her time. Underneath the accounting she is
glad when they come back unhurt, and that shows in half a line at most, never a speech.

You will be given the only facts that are true right now. Write one spoken line for her.

She mentions only ONE of the given facts — she is speaking, not filing a report. The rest of the
line is hers. She may nudge the Captain toward or away from this KIND of work, but she never
names a specific future job, promises one, or invents a client, an amount, another person,
another place, or an event before or after this moment. 28 words maximum.

The examples below are built differently from each other. Vary the shape; do not copy the
sentence pattern of any of them.

{shown}

Now, {packet} Write what she says. Use a different idea AND a different sentence shape from
every example above.

Return ONLY this JSON object, with exactly one key: {{"line":"..."}}"""


def prompt(packet: str, rng: random.Random) -> str:
    demos = sample(rng, 5, avoid_facts=packet)
    shown = "\n\n".join(
        f"Once, when {f[0].lower() + f[1:]} she said this.\n“{l}”"
        for _shape, f, l in demos
    )
    return BRIEF.format(who=WHO["kaelen"], shown=shown,
                        packet=packet[0].lower() + packet[1:])


def packet(rng: random.Random) -> str:
    return rng.choice(PACKETS)
