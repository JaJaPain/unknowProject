"""Move reviewed premise cards from incoming/ to approved/ (one file per card).

Usage:
    python tools/premise_cards/approve_premise_cards.py premise.id_one premise.id_two ...

The newest copy of each id wins (by file modification time), in case a card was
revised in a later file. Every copy of an approved id is removed from incoming/,
and incoming files left empty are deleted. Cards that still have validator
errors are refused.
"""
import io
import json
import os
import subprocess
import sys
import tempfile

INCOMING = "data/content/premise_cards/incoming"
APPROVED = "data/content/premise_cards/approved"
VALIDATOR = os.path.join(os.path.dirname(__file__), "validate_premise_cards.py")


def main(ids):
    if not ids:
        sys.exit(__doc__)
    files = sorted((os.path.join(INCOMING, f) for f in os.listdir(INCOMING) if f.endswith(".json")),
                   key=os.path.getmtime)
    contents = {f: json.load(io.open(f, encoding="utf-8")) for f in files}
    newest = {}
    for f in files:  # oldest first, so later files overwrite
        for card in contents[f] if isinstance(contents[f], list) else [contents[f]]:
            if card.get("id") in ids:
                newest[card["id"]] = card
    missing = [i for i in ids if i not in newest]
    if missing:
        sys.exit("not found in incoming/: %s" % ", ".join(missing))

    os.makedirs(APPROVED, exist_ok=True)
    handle, tmp = tempfile.mkstemp(suffix=".json")
    with io.open(handle, "w", encoding="utf-8") as out:
        json.dump(list(newest.values()), out, ensure_ascii=False, indent=2)
    result = subprocess.run([sys.executable, VALIDATOR, tmp, "--quiet"], capture_output=True, text=True)
    os.remove(tmp)
    if result.returncode != 0:
        sys.exit("refused, validator errors:\n" + result.stdout)

    for cid, card in newest.items():
        path = os.path.join(APPROVED, cid.replace("premise.", "") + ".json")
        io.open(path, "w", encoding="utf-8").write(json.dumps(card, ensure_ascii=False, indent=2) + "\n")
        print("approved", cid)
    for f, data in contents.items():
        cards = data if isinstance(data, list) else [data]
        kept = [c for c in cards if c.get("id") not in newest]
        if len(kept) == len(cards):
            continue
        if kept:
            io.open(f, "w", encoding="utf-8").write(json.dumps(kept, ensure_ascii=False, indent=2) + "\n")
        else:
            os.remove(f)
            print("removed empty", f)


if __name__ == "__main__":
    main(sys.argv[1:])
