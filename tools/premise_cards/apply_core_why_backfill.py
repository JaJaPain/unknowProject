"""Merge a core_why backfill file into the approved premise cards.

Usage:
    python tools/premise_cards/apply_core_why_backfill.py [--dry-run]

Reads data/content/premise_cards/core_why_backfill.json, a JSON object mapping
card id -> {"motive": ..., "secret": ...}, written by Gemini (who never edits
approved/ directly). Checks every entry, then writes core_why into each approved
card that doesn't have one yet. Prints repeated secrets so a reviewer can decide
whether those cards really share a reason.
"""
import io
import json
import os
import re
import sys
from collections import defaultdict

APPROVED = "data/content/premise_cards/approved"
BACKFILL = "data/content/premise_cards/core_why_backfill.json"
MOTIVES = set("revenge fear faith control greed protecting_someone ideology survival legacy guilt".split())
SECRET = re.compile(r"[a-z0-9]+(_[a-z0-9]+){1,6}")


def main(argv):
    dry = "--dry-run" in argv
    backfill = json.load(io.open(BACKFILL, encoding="utf-8"))
    cards = {}
    for name in os.listdir(APPROVED):
        if name.endswith(".json"):
            path = os.path.join(APPROVED, name)
            card = json.load(io.open(path, encoding="utf-8"))
            cards[card["id"]] = (path, card)

    problems = []
    for cid, why in backfill.items():
        if cid not in cards:
            problems.append("%s: not an approved card" % cid)
        elif not isinstance(why, dict) or why.get("motive") not in MOTIVES:
            problems.append("%s: motive %r is not in the vocabulary" % (cid, (why or {}).get("motive")))
        elif not SECRET.fullmatch(str(why.get("secret", ""))):
            problems.append("%s: secret %r is not a 2-7 word snake_case label" % (cid, why.get("secret")))
    missing = [cid for cid, (_, c) in cards.items() if "core_why" not in c and cid not in backfill]
    if problems:
        sys.exit("refused:\n  " + "\n  ".join(problems))

    by_secret = defaultdict(list)
    for cid, (_, c) in cards.items():
        why = c.get("core_why") or backfill.get(cid)
        if why:
            by_secret[why["secret"]].append(cid)
    repeats = {s: ids for s, ids in by_secret.items() if len(ids) > 1}

    written = 0
    for cid, why in backfill.items():
        path, card = cards[cid]
        if "core_why" in card:
            continue
        card["core_why"] = {"motive": why["motive"], "secret": why["secret"]}
        written += 1
        if not dry:
            io.open(path, "w", encoding="utf-8").write(json.dumps(card, ensure_ascii=False, indent=2) + "\n")

    print("%s %d cards; %d approved cards still without core_why" % ("would write" if dry else "wrote", written, len(missing)))
    if missing:
        shown = sorted(missing)[:10]
        print("  missing: " + ", ".join(shown) + (" ... and %d more" % (len(missing) - 10) if len(missing) > 10 else ""))
    if repeats:
        print("repeated secrets (review whether these cards really share a reason):")
        for s, ids in sorted(repeats.items()):
            print("  %s: %s" % (s, ", ".join(sorted(ids))))


if __name__ == "__main__":
    main(sys.argv[1:])
