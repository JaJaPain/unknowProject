"""Check Gemini's fetch-mission card batches and print a compact review sheet.

    python tools/fetch_cards/check_fetch_cards.py [batch_01.json ...]

With no arguments it checks every file in data/content/fetch_cards/incoming/.
Structural errors are listed first; then each card on a few short lines.
Brief: docs/gemini_prompts/fetch_card_prompt.md.
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INCOMING = ROOT / "data/content/fetch_cards/incoming"
APPROVED = ROOT / "data/content/fetch_cards/approved"
VARIANTS = {"life_or_death", "funny", "personal"}
URGENCY = {"hours", "days"}
FIELDS = ["card_id", "item_id", "variant", "requester", "need", "stakes", "board_text", "urgency"]
# Reserved topics and outside settings (see the brief); a hit is a flag to read, not an auto-fail.
FLAG_WORDS = [
    "android", "robot", "synthetic", "sentient", "self-aware", "conscious", "upload", "clone",
    "ghost", "haunt", "spirit", "time travel", "time loop", "parallel", "dimension", "hologram",
    "puppet", "remote control", "remote-control", "resurrect", "back to life", "undead",
    "eve", "capsuleer", "concord", "jedi", "starfleet", "protomolecule", "firefly",
    "credits", " sc ", "reward",
]


def load_items() -> dict:
    items = {}
    store = json.loads((ROOT / "data/content/store_items.json").read_text(encoding="utf-8"))
    for i in store["items"]:
        items[i["item_id"]] = i["display_name"]
    props = json.loads((ROOT / "data/content/prop_items.json").read_text(encoding="utf-8"))
    for i in props["items"]:
        items[i["id"]] = i["name"]
    return items


def main(paths: list) -> int:
    items = load_items()
    errors = []
    seen_ids = set()
    for old in APPROVED.glob("*.json") if APPROVED.exists() else []:
        for c in json.loads(old.read_text(encoding="utf-8")).get("cards", []):
            seen_ids.add(c.get("card_id"))
    all_cards = []
    for path in paths:
        try:
            data = json.loads(Path(path).read_text(encoding="utf-8"))
        except Exception as e:
            errors.append(f"{Path(path).name}: not valid JSON ({e})")
            continue
        cards = data.get("cards", [])
        per_item = Counter()
        for c in cards:
            cid = c.get("card_id", "?")
            for f in FIELDS:
                if not str(c.get(f, "")).strip():
                    errors.append(f"{cid}: missing {f}")
            if c.get("item_id") not in items:
                errors.append(f"{cid}: unknown item_id {c.get('item_id')}")
            if c.get("variant") not in VARIANTS:
                errors.append(f"{cid}: bad variant {c.get('variant')}")
            if c.get("urgency") not in URGENCY:
                errors.append(f"{cid}: bad urgency {c.get('urgency')}")
            if cid != f"fetch_{c.get('item_id')}_{c.get('variant')}":
                errors.append(f"{cid}: card_id should be fetch_<item_id>_<variant>")
            if cid in seen_ids:
                errors.append(f"{cid}: duplicate card_id")
            seen_ids.add(cid)
            per_item[(c.get("item_id"), c.get("variant"))] += 1
            text = " ".join(str(c.get(f, "")) for f in FIELDS[3:]).lower()
            for w in FLAG_WORDS:
                if re.search(r"\b" + re.escape(w.strip()) + r"\b", text):
                    errors.append(f"{cid}: FLAG word '{w.strip()}' (read it)")
            if len(str(c.get("board_text", ""))) < 80:
                errors.append(f"{cid}: board_text very short")
            all_cards.append((Path(path).name, c))
        for key, n in per_item.items():
            if n > 1:
                errors.append(f"{Path(path).name}: {key} appears {n} times")
    # Repeated phrasing across cards: any 6-word run shared by two cards.
    grams = {}
    for _, c in all_cards:
        words = re.findall(r"[a-z']+", str(c.get("board_text", "")).lower())
        for i in range(len(words) - 5):
            grams.setdefault(" ".join(words[i:i + 6]), set()).add(c.get("card_id"))
    for g, ids in grams.items():
        if len(ids) > 1:
            errors.append(f"shared phrase '{g}' in {sorted(ids)}")
    requesters = Counter(str(c.get("requester", "")).lower() for _, c in all_cards)
    for r, n in requesters.items():
        if n > 1:
            errors.append(f"requester '{r}' used {n} times")

    print(f"== {len(all_cards)} cards, {len(errors)} issues")
    for e in errors:
        print("  !", e)
    for name, c in all_cards:
        print(f"\n[{c.get('card_id')}] {c.get('urgency')} | {c.get('requester')}")
        print(f"  NEED: {c.get('need')}")
        print(f"  STAKES: {c.get('stakes')}")
        print(f"  BOARD: {c.get('board_text')}")
    return 1 if any("FLAG" not in e and "shared phrase" not in e for e in errors) else 0


if __name__ == "__main__":
    args = sys.argv[1:] or sorted(str(p) for p in INCOMING.glob("*.json"))
    sys.exit(main(args))
