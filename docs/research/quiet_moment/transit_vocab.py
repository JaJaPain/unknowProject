"""Loaded-but-accurate vocabulary for N.O.V.A.'s transit flirting.

Author, 2026-08-02:
  "it never figured out that the maintenance job needs to imply something to
   do with sex. not just a random job that could be done."

That was a CODE fault, not a model fault. The detail pool was rotating in
jobs like "a film on the forward viewport" and "a cable run behind the galley
bulkhead" — real maintenance with no second reading whatsoever. The model was
then asked to be suggestive about wiping a window, which cannot work.

RULE FOR ADDING ENTRIES HERE: every job must satisfy BOTH readings.
  1. A ship engineer reads an ordinary work order. Real part, real procedure,
     nothing odd about it.
  2. The part is body-analogous (an opening, a shaft, a socket, a seal, a
     line that carries fluid) and the action maps to an act (easing open,
     seating, stroking, working in deep, greasing, flushing, bleeding off).

If only reading 1 holds, the flirt has nothing to stand on.
If only reading 2 holds, deniability is gone and it stops being her joke.
"""

# Jobs she dangles in front of him (the DANGLE device).
DETAILS = [
    "her intakes, which want a soft brush worked right down inside",
    "her secondary manifold, which is overdue a slow flush",
    "a coupling that needs seating properly by hand until it's snug",
    "her aft access port, which sticks and wants easing open",
    "her main drive shaft, which needs greasing along its whole length",
    "an injector that has to be stroked clean before it'll seat again",
    "a valve that's stiff and wants working open slowly",
    "her coolant line, which needs the pressure bled off by hand",
    "a socket that wants something seated firmly in it",
    "her lower ports, which want swabbing out properly",
    "a fitting deep in her housing that needs a hand worked in to reach",
    "her plating, which wants oiling and rubbing down by hand",
]

# Parts other people have had their hands on (the JEALOUSY device).
PARTS = [
    "my manifold",
    "my intakes",
    "my coupling housings",
    "my access ports",
    "my injector rail",
    "my main shaft",
    "my coolant lines",
    "my valve seats",
    "my lower ports",
    "my inlet housing",
]

# Loaded because they are ACCURATE, never because they are euphemisms.
TOOLS = [
    "a nano vibration gun",
    "a warm solvent bath",
    "an ultrasonic probe",
    "a slow pressure flush",
    "a long handled brush",
    "a heated seal iron",
    "a fine magnetic pick",
    "a lubricant gun",
    "nothing but his hands",
    "a soft bristle swab",
]

MISHAPS = [
    "I thought I was going to leak coolant",
    "I very nearly vented",
    "I thought a seal was going to give",
    "I came close to losing pressure entirely",
    "I thought something was going to pop loose",
    "I had to run a diagnostic afterwards to settle down",
    "I could not hold pressure the whole way through",
]


def audit():
    """Every entry must read as maintenance AND as something else."""
    body = ("intake", "manifold", "coupling", "port", "shaft", "socket",
            "injector", "valve", "seal", "housing", "inlet", "line", "plating")
    act = ("inside", "flush", "seat", "easing", "greas", "strok", "open",
           "bled", "swab", "worked in", "rubbing", "oiling", "snug", "hand")
    problems = []
    for d in DETAILS:
        low = d.lower()
        if not any(b in low for b in body):
            problems.append(f"no body-analogous part: {d}")
        elif not any(a in low for a in act):
            problems.append(f"no act reading: {d}")
    for p in PARTS:
        if not any(b in p.lower() for b in body):
            problems.append(f"part has no second reading: {p}")
    return problems


if __name__ == "__main__":
    issues = audit()
    for i in issues:
        print("  ", i)
    print(f"  {len(issues)} issue(s) across "
          f"{len(DETAILS)} details and {len(PARTS)} parts")
