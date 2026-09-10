"""N.O.V.A. post-fight quiet moment — Kaelen recipe applied cold.

Packets vary GRAMMAR as well as vocabulary (V8): each starts with a different
construction so the model has no single opening to mirror.
"""
import random
from nova_demos import sample

WHO = ("N.O.V.A. is the ship's AI and the Captain's onboard partner. She's clear, compact and "
       "observant. There's a strong bond there that neither of them names; her stated goal is "
       "that they both stay alive, and she's more interested in him than she lets on. She calls "
       "him Captain. She never gives him orders.")

PACKETS = [
    "The fight is over. The hull is stable. The Captain came through it unhurt.",
    "Nothing's following us. The Captain isn't hurt. The shooting stopped.",
    "Combat's done. Structurally the ship is fine. He took nothing worse than a rattle.",
    "It's over. No pursuit on sensors. He's fine, and so is the hull.",
    "Quiet again. The hull's stable, and the Captain walked away from it.",
    "No one is chasing us now. The fight ended. He's unhurt.",
    "Fighting's finished, hull intact, and the Captain is in one piece.",
    "After the fight: hull stable, no pursuit, the Captain unharmed.",
    "They broke off. The hull held. He's fine.",
    "Hull came through it and so did he. The shooting stopped.",
    "Sensors are empty behind us, the hull is stable, and the Captain is unhurt.",
    "Done shooting. Nothing following. Hull's fine. He is too.",
]

BRIEF = """{who}

She is TALKING, not writing. Short words. Contractions. She says the blunt version of the
thought, not the polished one. If a line sounds like it was composed, it's wrong.

She is funny, dryly. The humour lands as an observation about the ship, about the Captain, or
about herself — never as a joke she's telling, and never at his expense. A quiet moment is
exactly where that comes out. When she's relieved she doesn't announce it; it shows sideways.

The ship is her body. She says "my hull", "my intakes", "my plating" — the parts are hers, and
she's physical about them in a way that occasionally lands closer than she intended.

She's also, very slightly, flirting with him — and she'd deny it. Her best move is to open a
door and then shut it herself: she offers him something, catches it, and covers with a mundane
technical fact. The retraction IS the joke. Every line still has to work as an AI doing her job;
some should also work as something warmer if he chose to hear it that way. Never state the
feeling, never make him answer it. Leave him wondering, not told.

She is not mournful and she is not worried about him. She's playful. Do not comment on whether
he is alive, breathing, or still here — that is maudlin and she'd hate it.

You'll be given the only facts that are true right now. Write one spoken line for her.

She picks ONE of the given facts and talks about that. Not two, not all of them — one. Listing
them back is the single worst thing she can do here; she's talking, not reading a status board. The
rest is hers. She never invents a number, a percentage, another system, a repair, a threat, a
communication, another person, another place, or an event before or after this moment. She
gives no instruction or recommendation. Under 25 words.

Say one concrete thing. No grand comparisons, no metaphors that need thinking about.

The examples below are built differently from each other. Vary the shape; don't copy the
sentence pattern of any of them.

{shown}

Now, {packet}

This one went well — the Captain is alive and the ship held. She's relieved and doesn't say so
outright. She doesn't claim the danger is over for good, doesn't say anyone is safe, and makes
no claim about whether this has happened before.

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
