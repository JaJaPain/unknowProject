"""Deterministic anatomy-slip correction for N.O.V.A.

Author's idea, and a better one than asking the model to do it: if she reaches
for a human body word, CODE appends the machine correction. The model only has
to be natural about her body; the joke's payoff is guaranteed rather than
hoped for.

This is the same principle that fixed opener collapse and detail choice —
anything code can own reliably, code should own. Left to the model the slip
came out machine-to-machine ("stuffed to the bulkheads, or at least the cargo
hold"), which isn't the joke at all.

Author's canon:
  "that load has me filled up to my larynx, or at least my vocal processor"
"""
import collections
import random
import re

# human part -> the machine part she corrects herself to
ANATOMY = {
    # Only mappings where the machine term is a SURPRISINGLY precise substitute.
    # Author calibration: "larynx -> vocal processor" lands; "belly -> cargo
    # hold" falls flat, because a hold already IS a belly. Flat pairs were
    # removed rather than kept for coverage.
    "larynx": "vocal processor",
    "throat": "intake trunk",
    "lungs": "air scrubbers",
    "ribs": "frame spars",
    "ribcage": "frame spars",
    "spine": "keel",
    "backbone": "keel",
    "sternum": "keel plate",
    "waist": "midsection coupling",
    "hips": "gimbal mounts",
    "knees": "landing gear",
    "ankles": "landing struts",
    "jaw": "docking clamp",
    "teeth": "grapple hooks",
    "veins": "coolant lines",
    "nerves": "sensor net",
    "eyes": "optical array",
    "ears": "audio pickups",
    "hair": "antenna array",
    "fingers": "manipulators",
    "elbows": "articulation joints",
    "wrists": "articulation joints",
    "neck": "dorsal spine housing",
    "shoulders": "dorsal mounts",
}

_PARTS = "|".join(sorted(ANATOMY, key=len, reverse=True))
# Only correct HER body. "you could feel it in your bones" is the Captain's
# body and correcting that would be nonsense, so require a first-person
# possessive (or a bare "the X" immediately after "I'm/I've").
_WORD = re.compile(r"\bmy\s+(" + _PARTS + r")\b", re.I)
# she already corrected herself; don't stack a second one
_ALREADY = re.compile(r"\bor at least\b|\bwell,? not\b|\bi mean\b|\bfigure of speech\b", re.I)

CORRECTIONS = [
    "Or at least my {machine}.",
    "My {machine}, technically.",
    "Well. My {machine}.",
]


def find_part(line: str):
    m = _WORD.search(line or "")
    return m.group(1).lower() if m else None


_recent = collections.deque(maxlen=4)


def apply(line: str, rng: random.Random = None, track: bool = True) -> str:
    """Append her self-correction if she used a body word and hasn't corrected.

    Skips if the same machine part was corrected to recently — "My frame
    spars, technically" twice in thirty lines is exactly the repetition the
    rest of the system works to avoid.
    """
    if not line:
        return line
    part = find_part(line)
    if not part or _ALREADY.search(line):
        return line
    machine = ANATOMY[part]
    # she already named the machine part; correcting to it reads as a stutter
    # ("My cargo hold's stuffed. That is - my cargo hold.")
    if re.search(r"\b" + re.escape(machine) + r"\b", line, re.I):
        return line
    if machine in _recent:
        return line
    rng = rng or random
    template = rng.choice(CORRECTIONS)
    if track:
        _recent.append(machine)
    tail = template.format(machine=machine, machine_cap=machine[0].upper() + machine[1:])
    sep = " " if line.rstrip()[-1:] in ".!?" else ". "
    return line.rstrip() + sep + tail


if __name__ == "__main__":
    r = random.Random(1)
    for t in [
        "That load has me filled up to my larynx",
        "I'm stuffed to my ribs.",
        "You'd think I had a spine to carry this.",
        "Stuffed to the bulkheads. Or at least the cargo hold.",   # already corrected
        "Every bay's packed and the doors are shut.",              # no body word
    ]:
        print(f"  in : {t}\n  out: {apply(t, r)}\n")
