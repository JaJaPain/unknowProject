"""Merge private-fact rewrites and investigation culprits into approved cards.

Usage:
    python tools/premise_cards/apply_private_fact_rewrites.py [--check | --dry-run]

Reads data/content/premise_cards/private_fact_rewrites.json, a JSON array
written by Gemini (who never edits approved/ directly). Each entry names a
mission by card id, beat number and mission index, and carries either a new
"private_fact" (a hidden truth about a person, present tense, never narrating
the pilot) or a "culprit" (the person or faction role an investigate_signal
mission's evidence exposes), or both.

--check    validate only and list problems (Gemini runs this until 0).
--dry-run  validate and report what would change, without writing.
"""
import io
import json
import os
import re
import sys

APPROVED = "data/content/premise_cards/approved"
REWRITES = "data/content/premise_cards/private_fact_rewrites.json"
# Same rule as validate_premise_cards.NARRATED_FACT.
NARRATED_FACT = re.compile(r"^\s*the (pilot|player)\b|\bthe pilot (must|discovers?|realizes?|realises?|finds|learns|chooses|sees|notices|will)\b|\b(you|your)\b", re.I)
MIN_FACT = 45


def load_cards():
    cards = {}
    for name in os.listdir(APPROVED):
        if name.endswith(".json"):
            path = os.path.join(APPROVED, name)
            card = json.load(io.open(path, encoding="utf-8"))
            cards[card["id"]] = (path, card)
    return cards


def find_mission(card, beat_n, index):
    for beat in card.get("beats", []):
        if beat.get("n") == beat_n:
            missions = beat.get("missions", [])
            if 0 <= index < len(missions):
                return missions[index]
    return None


def main(argv):
    check = "--check" in argv
    dry = "--dry-run" in argv or check
    entries = json.load(io.open(REWRITES, encoding="utf-8"))
    if not isinstance(entries, list):
        sys.exit("refused: the file must be a JSON array")
    cards = load_cards()
    problems = []
    changes = []
    for i, e in enumerate(entries):
        where = "entry %d (%s beat %s mission %s)" % (i, e.get("card"), e.get("beat"), e.get("mission"))
        if e.get("card") not in cards:
            problems.append("%s: not an approved card" % where)
            continue
        path, card = cards[e["card"]]
        mission = find_mission(card, e.get("beat"), e.get("mission", -1))
        if mission is None:
            problems.append("%s: no such mission" % where)
            continue
        if "private_fact" not in e and "culprit" not in e:
            problems.append("%s: needs private_fact or culprit" % where)
        if "private_fact" in e:
            fact = str(e["private_fact"]).strip()
            if len(fact) < MIN_FACT:
                problems.append("%s: private_fact under %d characters" % (where, MIN_FACT))
            elif mission.get("verb") != "comms_reversal" and NARRATED_FACT.search(fact):
                problems.append("%s: private_fact still narrates the pilot: %r" % (where, fact[:80]))
            else:
                changes.append((path, card, mission, "private_fact", fact))
        if "culprit" in e:
            kinds = {r.get("id"): r.get("kind") for r in card.get("roles", [])}
            culprit = e["culprit"]
            if mission.get("verb") != "investigate_signal":
                problems.append("%s: culprit only on investigate_signal missions" % where)
            elif kinds.get(culprit) not in ("person", "faction"):
                problems.append("%s: culprit %r is not a person or faction role" % (where, culprit))
            else:
                changes.append((path, card, mission, "culprit", culprit))
    if problems:
        print("%d problem(s):" % len(problems))
        for p in problems:
            print("  " + p)
        if not check:
            sys.exit("refused")
        return
    if check:
        print("0 problems; %d change(s) ready" % len(changes))
        return
    touched = {}
    for path, card, mission, field, value in changes:
        mission[field] = value
        touched[path] = card
    if not dry:
        for path, card in touched.items():
            io.open(path, "w", encoding="utf-8").write(json.dumps(card, ensure_ascii=False, indent=2) + "\n")
    print("%s %d change(s) in %d card(s)" % ("would write" if dry else "wrote", len(changes), len(touched)))


if __name__ == "__main__":
    main(sys.argv[1:])
