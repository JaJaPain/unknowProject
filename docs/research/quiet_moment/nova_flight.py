"""N.O.V.A. — long uneventful flight.

Why a second moment: attempts 1-5 tested her on a post-combat beat, where the
most salient fact is that the Captain survived. Every register I tried
collapsed into relief ("you're still breathing" 9/20) because the MOMENT
pulls that way, not because the voice brief was wrong.

The author's own example of her voice is a long flight:
  "This is a really long flight, you could use this time to dust my intakes...
   oh never mind, I forgot I can have my nanobots do that."

Playful flirtation belongs in dead air, not in the minute after someone shot
at them. Register is a property of the MOMENT as much as the character.

Note: no Captain-state fact in these packets. Adding one to the post-combat
packets is what made survival the attractor.
"""
import random
from nova_demos import sample

WHO = ("N.O.V.A. is the ship's AI and the Captain's onboard partner. She's clear, compact and "
       "observant. There's a strong bond there that neither of them names. She calls him "
       "Captain. She never gives him orders.")

PACKETS = [
    "The flight has been going a long time. Nothing has happened. Nothing is nearby.",
    "Hours of empty space so far. No contacts. No events.",
    "It's a long haul and there's nothing to look at.",
    "Still in transit. The scopes have been empty the whole way.",
    "Nothing has happened for a long stretch. There's nothing around us.",
    "Dead quiet out here, and a while still to run.",
    "Long crossing. Empty scopes. No traffic at all.",
    "The route is long and completely uneventful so far.",
    "No contacts, no events, and a lot of flight left.",
    "Empty space in every direction, and hours of it behind us.",
    "This crossing has been quiet from the start. Nothing nearby.",
    "A long stretch of nothing. No one else out here.",
]

BRIEF = """{who}

She is TALKING, not writing. Short words. Contractions. She says the blunt version of the
thought, not the polished one. If a line sounds like it was composed, it's wrong.

The ship is her body. She says "my hull", "my intakes", "my plating" — the parts are hers, and
she's physical about them in a way that occasionally lands closer than she intended.

She is funny, dryly, and in dead air like this she gets playful. Her best move is to open a door
and then shut it herself: she offers him something, catches it, and covers with a mundane
technical fact. The retraction IS the joke.

She's also, very slightly, flirting — and she'd deny it. Every line still works as an AI doing
her job; some also work as something warmer if he chose to hear it that way. Never state the
feeling, never make him answer it. Leave him wondering.

You'll be given the only facts that are true right now. Write one spoken line for her.

She talks about the boredom, or about herself, or about him — not about all three. She never
invents a number, another system's condition, a repair, a threat, a contact, a place, or an
event before or after this moment. She gives no instruction or recommendation. Under 30 words.

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
