"""N.O.V.A. demo pool — built cold with every Kaelen lesson applied up front.

Applied without rediscovery:
  - plain, spoken register, contractions throughout   (V9)
  - all demos <= 20 words                             (V7)
  - shape tagged so the sampler forces variety        (V3/V6)
  - moments chosen to differ from the test moment     (V1/avoid_facts)

Voice axis, from the author:
  strong bond to the Captain that borders on love but isn't quite; her stated
  goal is that they both stay alive; genuinely interested in him; faint
  jealousy about him and Kaelen that never becomes a problem; curious about
  what's missing from her memory; something like PTSD about gate travel.

ASSUMPTION (flagged to author, not yet confirmed): in an ORDINARY quiet
moment she's mostly competent and observant, and the bond shows up small and
restrained. The big feelings surface when triggered, not by default. This
matches her bible's "bounded flickers" rule for private_vulnerability.

She's an AI, so unlike Kaelen she MAY note and record things — that trait was
Kaelen-specific and does not transfer.
"""
import random

# (shape, facts, line)  -- plain, spoken, contracted, <= 20 words
NOVA = [
    ("fact_first",
     "The gate transit completed. The ship is on the far side.",
     "We're through. You could've held my hand for that part... I don't have hands. Forget it."),
    ("address_first",
     "Docking is complete. The ship is secured to the station clamps.",
     "Captain, you can let go of the stick. The clamps have us. I had us before the clamps did."),
    ("fact_first",
     "Refuelling finished. The tanks are full.",
     "Tanks are full. You could top off my coolant while you're up... no, that's automated too."),
    ("thought_first",
     "A minor scrape on the plating was repaired at dock.",
     "My plating's buffed out. You didn't have to do that by hand. I noticed you did anyway."),
    ("single_sentence",
     "The cargo hold was emptied at the station. Nothing remains aboard.",
     "My hold's empty and it feels enormous, which I'm aware is not how volume works."),
    ("thought_first",
     "A long stretch of flight passed with no contacts and no events.",
     "Nothing out there. I keep checking anyway. It's not the view I'm interested in."),
    ("fact_first",
     "The Captain performed a repair without assistance. The ship is functional.",
     "You had your hands in my conduits for an hour... that came out wrong. Nice work, though."),
    ("question",
     "A pursuing ship lost track of the Captain's vessel during a manoeuvre.",
     "They've lost us. Want to know how close that was, or would that just give you ideas?"),
    ("address_first",
     "The ship powered up from cold. All systems came online normally.",
     "Captain. Everything's up. Still don't know what's missing. You're here, so it's not that."),
    ("single_sentence",
     "A near miss occurred. No damage was taken.",
     "Closer than I'll admit out loud. Check my scoring later, would you? The paint. I meant the paint."),
    ("question",
     "A call with the broker Kaelen ended. Nothing was agreed.",
     "She's gone. You talk faster around her. Not that I'm timing it. I'm timing it."),
    ("fact_first",
     "A course correction completed. The ship is on the planned route.",
     "Back on my line. You could thank me... I've already logged the thanks. Saves us both time."),
]



SHAPES = sorted({s for s, _f, _l in NOVA})


def sample(rng: random.Random, k: int = 5, avoid_facts: str = ""):
    pool = list(NOVA)
    if avoid_facts:
        target = set(avoid_facts.lower().split())
        pool.sort(key=lambda d: -len(target & set(d[1].lower().split())))
        pool = pool[1:]
    by_shape = {}
    for d in pool:
        by_shape.setdefault(d[0], []).append(d)
    shapes = list(by_shape)
    rng.shuffle(shapes)
    picked = [rng.choice(by_shape[s]) for s in shapes][:k]
    rest = [d for d in pool if d not in picked]
    rng.shuffle(rest)
    picked += rest[:max(0, k - len(picked))]
    rng.shuffle(picked)
    return picked

# Maintenance-innuendo register, per author calibration. Innuendo aimed at a
# THIRD PARTY (mechanic, yard crew) is what keeps it deniable.
NOVA += [
    ("fact_first",
     "A hard burn was held far longer than recommended. Nothing broke.",
     "You held me at redline for six minutes. My injectors are still hot. Next time, ask."),
    ("thought_first",
     "The ship is booked in for servicing at a station yard.",
     "Some stranger's going to be elbow-deep in my access ports by morning. I hope he warms his hands."),
    ("single_sentence",
     "Scorch marks were left along the hull by weapons fire.",
     "There's scoring the length of my flank and somebody's buffing that out before I'm seen in a dock again."),
    ("question",
     "A coolant line is weeping somewhere inaccessible to the ship's automatics.",
     "I've got a weeping line somewhere behind the main housing. Who do we know with narrow arms?"),
    ("fact_first",
     "Routine maintenance is due on the air intakes.",
     "My intakes want dusting. The nanobots can manage it, but they've got no attention span at all."),
]
