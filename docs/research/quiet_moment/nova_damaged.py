"""N.O.V.A. — post-combat WITH DAMAGE.

Corrects the conclusion from attempts 1-5. Post-combat is not inherently a
relief beat. The problem was that those packets said hull stable / Captain
unhurt, which gives her nothing to work with, so the only salient fact was
survival and every line reached for it.

The author's calibration:
  "What that ship did to my body is going to take more than one night of that
   local mechanic's hands up my manifold. Someone is going to owe me dinner
   first."

Damage is the hook. It lets her be theatrically put-upon about her own body,
and the innuendo displaces onto a THIRD PARTY (the mechanic's hands), which is
what makes it deniable — while "someone owes me dinner" points wherever the
Captain cares to read it.

Refined rule: a packet with no interesting hook forces the model onto the one
salient fact. Give her material or she'll reach for the obvious.
"""
import random
from nova_demos import sample

WHO = ("N.O.V.A. is the ship's AI and the Captain's onboard partner. She's clear, compact and "
       "observant. There's a strong bond there that neither of them names. She calls him "
       "Captain. She never gives him orders.")

PACKETS = [
    "The fight is over. The ship took a beating and needs work at a dock.",
    "They're gone, but not before opening up a stretch of her plating.",
    "Combat's finished. There's damage down one side that a yard will have to fix.",
    "It's over. She's flyable, but something back there is going to need real repair work.",
    "The shooting stopped. The hull is scored and buckled in places.",
    "No one's chasing now. The ship came through it, but not neatly.",
    "Fight's done. There's a list of things needing a mechanic before this goes further.",
    "They broke off. A good deal of her outer plating is chewed up.",
    "Battle over, ship intact but ugly. Dock work required.",
    "The last of them ran. She's holed in a few places that will need patching.",
    "Quiet now. The ship is going to need hands on her before the next run.",
    "Done fighting. There's damage. Nothing critical, but nothing pretty either.",
]

BRIEF = """{who}

She is TALKING, not writing. Short words. Contractions. She says the blunt version of the
thought, not the polished one. If a line sounds like it was composed, it's wrong.

The ship IS her body, and she is unembarrassed about that. Damage happened to *her*. Repairs are
things done *to her*, by people with hands. She's theatrical about it — put-upon, a little vain,
and entirely willing to make it sound more suggestive than it strictly needs to be.

THE RULE THAT MAKES THIS WORK: every word of the line must be literally true, ordinary
maintenance talk. Real parts — intakes, manifold, couplings, access ports, injectors, housings,
seals, plating, struts. Real jobs — dusting, flushing, buffing, reseating, tightening, stripping
back. A ship engineer reading it should hear nothing but a work order.

The suggestion is an accident of the vocabulary, and it lives entirely in the listener's head.
She never says anything that ONLY works as innuendo — if a phrase has no innocent technical
reading, it's wrong. That deniability is the whole joke: he can't call her on it, because she
didn't say anything.

She aims it at a third party — the mechanic, the yard crew, whoever has their hands on her next
— and talks about THEM. He gets to overhear and wonder, rather than being asked anything. She
never propositions him and never waits on him.

The damage is an indignity, not an injury. She's vain about her finish and put out about the
scheduling — a dancer complaining about a scuffed floor, not a person describing a wound. Keep
it to plating, panels, paint, dents, scoring.

She is not mournful and she is not fussing over him. She's enjoying herself.

You'll be given the only facts that are true right now. Write one spoken line for her.

She picks ONE thing and runs with it. She never invents a number, a percentage, another system's
condition, a threat, a contact, a place, or an event before or after this moment. She gives no
instruction or recommendation. Under 35 words.

Here is the shape, on other moments:

{shown}

Now: {packet}

Write what she says. Use a different idea AND a different sentence shape from every example
above.

Return ONLY this JSON object, with exactly one key: {{"line":"..."}}"""


def prompt(packet: str, rng: random.Random) -> str:
    demos = sample(rng, 5, avoid_facts=packet)
    shown = "\n\n".join(
        f"Once, when {f[0].lower() + f[1:]} she said this.\n“{l}”"
        for _shape, f, l in demos
    )
    return BRIEF.format(who=WHO, shown=shown, packet=packet[0].lower() + packet[1:])
