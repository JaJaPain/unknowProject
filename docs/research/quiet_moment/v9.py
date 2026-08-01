"""V9 = V8 machinery + plain/spoken demos + a register instruction.

Changed from V8:
  - demo pool rewritten plain and contracted (demo_pool_v9)
  - brief now says explicitly that she is TALKING, and warns off the two
    things the author rejected: polished phrasing and the ledger flourish
  - "one concrete thing" replaces the vaguer "her angle on it"
"""
import random
from fewshot import WHO
from packets import PACKETS
from demo_pool_v9 import sample

BRIEF = """{who}

She thinks about work as risk priced against pay, and she's candid about her own cut. When a job
pays her badly she says so plainly and nudges the Captain toward work that pays better.

Her complaint is aimed at the job, the rate, or the client — never at the Captain. She doesn't
call them lucky or careless. Underneath the accounting she's glad when they come back unhurt,
and that shows in half a line at most, never a speech.

She is TALKING, not writing. Short words. Contractions. She says the blunt version of the
thought, not the polished one. If a line sounds like it was composed, it's wrong.

She's a dealmaker, not a bookkeeper. A fair amount of her work sits on the wrong side of legal,
so she keeps nothing on paper by policy — no ledgers, no books, no records, no notes for later.
She carries the numbers in her head and prefers it that way, and she's dry about the reason.

You'll be given the only facts that are true right now. Write one spoken line for her.

She mentions only ONE of the given facts — she's speaking, not filing a report. The rest is
hers. She may nudge the Captain toward or away from this KIND of work, but she never names a
specific future job, promises one, or invents a client, an amount, another person, another
place, or an event before or after this moment. Under 25 words.

Say one concrete thing. No grand comparisons, no metaphors that need thinking about.

The examples below are built differently from each other. Vary the shape; don't copy the
sentence pattern of any of them.

{shown}

Now, {packet}

This one paid badly. She is not pleased about the money, and she does not pretend the job was
worth more than it was. She also does not claim it was risky — it wasn't — and she makes no
claim about whether this has happened before.

Write what she says. Use a different idea AND a different sentence shape from every example
above.

Return ONLY this JSON object, with exactly one key: {{"line":"..."}}"""


def prompt(packet: str, rng: random.Random) -> str:
    demos = sample(rng, 5, avoid_facts=packet)
    shown = "\n\n".join(
        f"Once, when {f[0].lower() + f[1:]} she said this.\n“{l}”"
        for _shape, f, l in demos
    )
    return BRIEF.format(who=WHO["kaelen"], shown=shown,
                        packet=packet[0].lower() + packet[1:])
