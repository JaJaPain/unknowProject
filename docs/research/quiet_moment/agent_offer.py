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
# Briefing NOTES, not dialogue. This matters more than it looks: the first
# version phrased these as things a person would say ("It's dangerous, and I'm
# telling you that up front"), and four of five personalities simply recited
# all three bullets in order with no voice at all. If the packet sounds like a
# line, the model hands it straight back.
OBJECTIVES = {
    "DELIVERY_COURIER": [
        "job: courier run. sealed package, destination {destination}. not to be opened.",
        "job: carry one sealed parcel to {destination}. seal intact on arrival.",
        "job: small sealed item, moved to {destination}, unopened.",
    ],
    "DELIVER_ORE": [
        "job: haul refined ore to {destination}.",
        "job: ore shipment, destination {destination}.",
        "job: move a load of ore out to {destination}.",
    ],
    "KILL_SHIPS": [
        "job: destroy hostile ships operating on the lanes.",
        "job: several armed ships to be removed from the routes.",
        "job: engage and destroy hostiles working the shipping lanes.",
    ],
    "PICKUP_SPECIAL": [
        "job: collect one item, return it here intact.",
        "job: retrieve a package and bring it back to this station.",
        "job: pickup, returned in person, undamaged.",
    ],
    "PURCHASE_DELIVERY": [
        "job: purchase an item on the agent's behalf, deliver to {destination}.",
        "job: acquire goods, then transport to {destination}.",
        "job: buy, then run it out to {destination}.",
    ],
    "RECOVER_COMBAT_DROP": [
        "job: recover cargo lost during an engagement.",
        "job: salvage a drop left at the site of a firefight.",
        "job: locate and retrieve materiel lost in combat.",
    ],
    "TARGET_WITH_COMMS_REVERSAL": [
        "job: intercept a target vessel. its transmissions are unreliable.",
        "job: stop a broadcasting ship. comms cannot be trusted.",
    ],
}

RISK = {
    True: ["risk: high. expect hostiles.", "risk: high. injuries likely.",
           "risk: high."],
    False: ["risk: low.", "risk: low. no known hostiles.",
            "risk: routine."],
}

PAY = {
    "high": ["fee: above the usual rate.", "fee: high.", "fee: well above normal."],
    "low": ["fee: below the usual rate.", "fee: low.", "fee: modest."],
}

BRIEF = """{who}

{register}

{axis}

Kaelen has already introduced you to the Captain, so you are not strangers and there is no need
to establish who you are.

Your briefing notes. These are the only facts you have, and they are notes — nobody talks like
this. Do not read them out, do not work through them in order, and do not repeat their wording.
Say the job the way YOU would say it.

{packet}

Say what you'd say to open. Two or three sentences.

You do NOT cover all three notes. Nobody pitching a job recites risk and fee and objective in
order — that's a form, not a person. Lead with whatever YOU care about most, mention at most one
other thing, and let the rest come up later or not at all. What you dwell on, skip or soften is
the whole of your character.

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
# Fixations must SUIT THE JOB. A crate-related prohibition on a kill contract
# is incoherent — "don't let it go through the scanner twice" when there is no
# crate reads as a malfunction, not a character.
FIXATIONS = {
    # things that only make sense when something is being carried
    "cargo": [
        "the maintenance crew must not see inside the crate",
        "the manifest must not be read where anyone can see over your shoulder",
        "nobody photographs the seal",
        "it does not sit in the hold overnight at a station",
        "you don't accept help loading it",
        "you don't let it go through the scanner twice",
        "the crate stays upright the entire way",
        "tell whoever takes it that I was careful with it",
    ],
    # things that only make sense when there is a person on the other end
    "target": [
        "if he apologises, tell him I'm sorry too — then finish it",
        "he should know I sent you, but not why",
        "nobody out there gets spoken to unkindly",
        "pass on my regards, whatever else happens",
        "if it goes badly, I don't want the details afterwards",
        "he doesn't get told where I am",
    ],
    # true regardless of the job
    "any": [
        "you should use the service berth, not the main arm",
        "the destination must not be said out loud on an open channel",
        "my name doesn't come up at the far end",
        "you come back and tell me in person, not over comms",
    ],
}

# Which fixation groups a job can draw from.
FIXATION_GROUPS = {
    "KILL_SHIPS": ["target", "any"],
    "TARGET_WITH_COMMS_REVERSAL": ["target", "any"],
    "DELIVERY_COURIER": ["cargo", "any"],
    "DELIVER_ORE": ["cargo", "any"],
    "PICKUP_SPECIAL": ["cargo", "any"],
    "PURCHASE_DELIVERY": ["cargo", "any"],
    "RECOVER_COMBAT_DROP": ["cargo", "any"],
}


def _pick_fixation(rng, objective_type):
    groups = FIXATION_GROUPS.get(objective_type, ["any"])
    pool = []
    for g in groups:
        pool += FIXATIONS[g]
    return _draw("fixation.%s" % objective_type, pool, rng)


PARANOID_FIXATION_RULE = """
One more thing matters enormously to you: {fixation}.

That is written the way you would say it. Say it in your own words, in the first
person — never refer to yourself as "the agent".

You raise it, then you insist on it again — plainly, not cleverly. "I'm serious." "For real."
Ordinary words, repeated. The insisting is the point.

Then you go straight back to the job as if nothing odd just happened, and you do not soften or
withdraw any of it. If the fixation sits strangely against the job — a kindness attached to
something unkind, a courtesy attached to violence — that is exactly right. Leave it sitting
there.

You never explain why it matters. You never name what you're afraid of. You never suggest the
Captain is the risk."""

_bags = {}


def _draw(key, pool, rng):
    bag = _bags.get(key) or []
    if not bag:
        bag = list(pool)
        rng.shuffle(bag)
    _bags[key] = bag
    return bag.pop()


# Which facts each personality is GIVEN. Code decides, not the model: asking
# it to be selective helps, but it cannot recite a note it never received.
# The objective is always included; the rest is chosen to suit who's talking.
#   desperate  the stakes are why they're asking, so risk goes in
#   old_hand   the practical warning is their whole contribution
#   chancer    gets the fee and NOT the risk - he'd have skated over it anyway
#   believer   gets neither by default; the cause is his pitch, not the terms
#   paranoid   gets one at random; his fixation is doing the work
FACTS_BY_PERSONALITY = {
    "desperate": ["risk"],
    "old_hand": ["risk"],
    "chancer": ["pay"],
    "believer": [],
    "paranoid": ["risk", "pay"],   # one of, picked per request
}


def _facts_for(personality_id, rng):
    wanted = FACTS_BY_PERSONALITY.get(personality_id, ["risk", "pay"])
    if personality_id == "paranoid" and wanted:
        return [wanted[rng.randrange(len(wanted))]]
    return list(wanted)


def build_packet(rng, objective_type=None, known_tough=None, high_pay=None,
                 destination=None, include=None):
    objective_type = objective_type or _draw("obj", list(OBJECTIVES), rng)
    known_tough = rng.random() < 0.4 if known_tough is None else known_tough
    high_pay = known_tough if high_pay is None else high_pay
    destination = destination or _draw("dest", DESTINATIONS, rng)
    include = ["risk", "pay"] if include is None else include
    lines = [
        _draw(f"o.{objective_type}", OBJECTIVES[objective_type], rng)
        .format(destination=destination)
    ]
    if "risk" in include:
        lines.append(_draw(f"r.{known_tough}", RISK[known_tough], rng))
    if "pay" in include:
        lines.append(_draw("p.high" if high_pay else "p.low",
                           PAY["high" if high_pay else "low"], rng))
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
    packet_kwargs.setdefault("include", _facts_for(personality_id, rng))
    packet, meta = build_packet(rng, **packet_kwargs)
    if demos is None:
        # drop the demo whose job resembles this one; a near match gets
        # templated rather than transferred
        demos = demos_for(personality_id, meta["objective_type"])
    shown = "\n\n".join(f'"{d}"' for d in demos)
    axis = p["axis"]
    if personality_id == "paranoid":
        axis += PARANOID_FIXATION_RULE.format(
            fixation=_pick_fixation(rng, meta["objective_type"]))
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
