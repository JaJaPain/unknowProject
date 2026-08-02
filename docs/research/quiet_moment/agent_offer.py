"""The agent mission-offer beat.

Delivery only: mission generation is untouched. The briefing facts come from
the real quest data, and the personality decides only how they're said.

Fact packets are built from fields the game actually has — objective_type,
faction, known_tough, reward band — rather than invented. The agent's name and
system are code-supplied too, which is what makes an offer feel like it came
from a person in a place rather than from flavour text.
"""
import random

from agents import PERSONALITIES, SHARED_REGISTER, ORDER, demos_for

# What the job actually is, in plain terms. Rotated wording AND grammar, for
# the reason packet rotation exists at all: the model mirrors the packet's
# opening construction.
OBJECTIVES = {
    "DELIVERY_COURIER": [
        "A sealed package has to reach {destination}.",
        "Something small needs carrying to {destination}, unopened.",
        "There's a courier run out to {destination}.",
        "Take a sealed parcel to {destination}. Nobody opens it.",
    ],
    "DELIVER_ORE": [
        "A load of ore has to get to {destination}.",
        "Refined ore, bound for {destination}.",
        "There's ore sitting here that belongs at {destination}.",
        "Ore needs shifting out to {destination}.",
    ],
    "KILL_SHIPS": [
        "Some ships need removing from the lanes.",
        "There are hostiles working the routes who need to stop.",
        "A few ships out there have become a problem.",
        "Something armed needs dealing with, out past the lanes.",
    ],
    "PICKUP_SPECIAL": [
        "There's a package to collect and bring back here.",
        "Something needs picking up and returning intact.",
        "A pickup, and it comes back to me personally.",
        "Collect an item and bring it straight back.",
    ],
    "PURCHASE_DELIVERY": [
        "Buy something on my behalf and deliver it to {destination}.",
        "There's a purchase to make, then a run out to {destination}.",
        "You'd be buying, then carrying it to {destination}.",
        "Acquire it, then get it to {destination}.",
    ],
    "RECOVER_COMBAT_DROP": [
        "Something was lost in a fight out there and needs recovering.",
        "There's salvage sitting where a fight happened.",
        "A drop went missing during an engagement. It needs finding.",
        "Recover what was left behind after a shooting match.",
    ],
    "TARGET_WITH_COMMS_REVERSAL": [
        "There's a target out there, and the comms on it are not what they seem.",
        "A ship needs intercepting. Its transmissions are unreliable.",
        "Something out there is broadcasting, and it needs stopping.",
    ],
}

RISK = {
    True: [
        "It's dangerous, and I'm telling you that up front.",
        "People have got hurt doing this kind of thing.",
        "This one has teeth. I won't pretend otherwise.",
        "It's not safe work.",
    ],
    False: [
        "It's routine, as far as anyone can promise that.",
        "There's nothing about it that should bite.",
        "Low risk. Genuinely.",
        "Quiet run, if the last few are anything to go by.",
    ],
}

PAY = {
    "high": [
        "The fee is good, and it's good for a reason.",
        "It pays well.",
        "The money on it is better than usual.",
    ],
    "low": [
        "The fee is not going to impress you.",
        "It doesn't pay much.",
        "The money's modest and I know it.",
    ],
}

BRIEF = """{who}

{register}

{axis}

Kaelen has already introduced you to the Captain, so you are not strangers and there is no need
to establish who you are.

The briefing, which is everything you know:
{packet}

Say what you'd say to open. One short paragraph at most — two or three sentences. Give him the
job. What you choose to dwell on, skip, or soften is entirely down to who you are.

You never state a credit figure, a deadline, or any number the briefing didn't give you. You
never invent a client, a faction, a place, or a consequence that isn't above. You don't tell him
what he'll decide, and you don't thank him for a job he hasn't taken.

Here is how you've sounded on other occasions:

{shown}

Return ONLY this JSON object, with exactly one key: {{"line":"..."}}"""

DESTINATIONS = ["Kova Station", "Iron Reach", "the Latch", "Bellhaven",
                "Ordos Yard", "Trell's Landing", "Halgate", "the Bight"]

AGENT_NAMES = ["Vess Corrin", "Otto Balen", "Mira Sant", "Dax Hoyle",
               "Ines Reyk", "Palo Grieves", "Sura Vance", "Ren Mattis"]

SYSTEMS = ["Kova", "Iron Reach", "Halgate", "Ordos", "Bellhaven"]

# The paranoid one's signature: an oddly SPECIFIC prohibition, insisted on.
# Author's example: they're adamant you don't show the box to the maintenance
# person — "For real, don't show them. I'm serious."
#
# Same principle as N.O.V.A.'s detail pool: when a character trait depends on
# a specific detail, code picks the detail. Left to itself the model reaches
# for generic caution ("be careful out there"), which is not the joke. The
# fixation has to be narrow enough to be strange and mundane enough to be
# plausible.
FIXATIONS = [
    "the maintenance crew must not see inside the crate",
    "the manifest must not be read where anyone can see over your shoulder",
    "you should use the service berth, not the main arm",
    "the destination must not be said out loud on an open channel",
    "nobody photographs the seal",
    "it does not sit in the hold overnight at a station",
    "you don't accept help loading it",
    "their name is not mentioned at the far end",
    "you don't let it go through the scanner twice",
    "the crate stays upright the entire way",
]

PARANOID_FIXATION_RULE = """
One more thing matters enormously to you, and it is this: {fixation}.

You raise it, and then you insist on it again — plainly, not cleverly. "I'm serious." "For real."
Ordinary words. The insisting is the point.

You do not explain why. You do not name what you're afraid of. You never suggest the Captain is
the risk."""

_bags = {}


def _draw(key, pool, rng):
    bag = _bags.get(key) or []
    if not bag:
        bag = list(pool)
        rng.shuffle(bag)
    _bags[key] = bag
    return bag.pop()


def build_packet(rng, objective_type=None, known_tough=None, high_pay=None,
                 destination=None):
    objective_type = objective_type or _draw("obj", list(OBJECTIVES), rng)
    known_tough = rng.random() < 0.4 if known_tough is None else known_tough
    high_pay = known_tough if high_pay is None else high_pay
    destination = destination or _draw("dest", DESTINATIONS, rng)
    lines = [
        _draw(f"o.{objective_type}", OBJECTIVES[objective_type], rng)
        .format(destination=destination),
        _draw(f"r.{known_tough}", RISK[known_tough], rng),
        _draw("p.high" if high_pay else "p.low",
              PAY["high" if high_pay else "low"], rng),
    ]
    return "\n".join("- " + l for l in lines), {
        "objective_type": objective_type,
        "known_tough": known_tough,
        "high_pay": high_pay,
        "destination": destination,
    }


def compose(rng, personality_id, demos=None, name=None, system=None, **packet_kwargs):
    p = PERSONALITIES[personality_id]
    name = name or _draw("name", AGENT_NAMES, rng)
    system = system or _draw("sys", SYSTEMS, rng)
    packet, meta = build_packet(rng, **packet_kwargs)
    if demos is None:
        # drop the demo whose job resembles this one; a near match gets
        # templated rather than transferred
        demos = demos_for(personality_id, meta["objective_type"])
    shown = "\n\n".join(f'"{d}"' for d in demos)
    axis = p["axis"]
    if personality_id == "paranoid":
        axis += PARANOID_FIXATION_RULE.format(
            fixation=_draw("fixation", FIXATIONS, rng))
    prompt = BRIEF.format(
        who=p["who"].format(name=name, system=system),
        register=SHARED_REGISTER,
        axis=axis,
        packet=packet,
        shown=shown,
    )
    meta.update({"name": name, "system": system, "personality": personality_id,
                 "demos": demos})
    return prompt, meta
