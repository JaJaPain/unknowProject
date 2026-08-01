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
import random
import re

# human part -> the machine part she corrects herself to
ANATOMY = {
    "larynx": "vocal processor",
    "throat": "intake trunk",
    "voice": "vocal processor",
    "lungs": "air scrubbers",
    "ribs": "frame spars",
    "ribcage": "frame spars",
    "spine": "keel",
    "backbone": "keel",
    "waist": "midsection coupling",
    "hips": "gimbal mounts",
    "belly": "cargo hold",
    "stomach": "cargo hold",
    "gut": "cargo hold",
    "guts": "internals",
    "chest": "forward bulkhead",
    "shoulders": "dorsal mounts",
    "knees": "landing gear",
    "ankles": "landing struts",
    "jaw": "docking clamp",
    "teeth": "grapple hooks",
    "skin": "plating",
    "bones": "frame",
    "veins": "coolant lines",
    "blood": "coolant",
    "nerves": "sensor net",
    "heart": "reactor",
    "eyes": "optical array",
    "ears": "audio pickups",
    "hair": "antenna array",
    "fingers": "manipulators",
    "hands": "manipulators",
    "lips": "hatch seals",
    "elbows": "articulation joints",
    "sternum": "keel plate",
    "shoulder": "dorsal mount",
    "knee": "landing gear",
    "rib": "frame spar",
    "lung": "air scrubber",
    "throat lining": "intake trunk",
    "belly button": "access port",
    "toes": "landing pads",
    "wrists": "articulation joints",
    "neck": "dorsal spine housing",
    "hip": "gimbal mount",
    "thigh": "strut housing",
    "back": "dorsal plating",
    "stomach lining": "hold liner",
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
    "{machine_cap}, if we're being accurate.",
    "That is — my {machine}.",
    "Or the {machine}, if you want the correct term.",
]


def find_part(line: str):
    m = _WORD.search(line or "")
    return m.group(1).lower() if m else None


def apply(line: str, rng: random.Random = None) -> str:
    """Append her self-correction if she used a body word and hasn't corrected."""
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
    rng = rng or random
    template = rng.choice(CORRECTIONS)
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
