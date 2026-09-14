"""Turn completed lounge-review choices into a small, non-repetitive example bank."""
import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).parent
REVIEWS = ROOT / "lounge_diverse_review_decisions.json"
BATCH = ROOT / "lounge_diverse_rewrite_review.json"
OUT = ROOT / "lounge_curated_selected_examples.json"

def words(text):
    return set(re.findall(r"[a-z0-9']+", text.lower()))

def similarity(left, right):
    a, b = words(left), words(right)
    return len(a & b) / max(1, len(a | b))

def main():
    saved = json.loads(REVIEWS.read_text(encoding="utf-8"))["reviews"]
    choices = saved["lounge-rewrite:lounge-diverse-rewrite-review"]["decisions"]
    source = json.loads(BATCH.read_text(encoding="utf-8"))["items"]
    candidates = []
    for item in source:
        choice = choices.get(item["id"], {})
        decision = choice.get("decision")
        if decision == "user_rewrite": text = {key: choice.get(key, "") for key in ("opener", "answer", "close")}
        elif decision == "original": text = item["original"]
        elif decision == "assistant_rewrite": text = item["assistant_rewrite"]
        else: continue
        candidates.append({"id": item["id"], "contact_name": item["contact_name"], "contact_role": item["contact_role"], "station": item["station"], "allowed_facts": item["allowed_facts"], "player_question": item["player_question"], "decision": decision, **text})

    priority = {"user_rewrite": 3, "original": 2, "assistant_rewrite": 1}
    grouped = defaultdict(list)
    for entry in candidates: grouped[entry["allowed_facts"]].append(entry)
    kept, removed = [], []
    for fact, entries in grouped.items():
        unique = []
        for entry in sorted(entries, key=lambda x: (-priority[x["decision"]], x["id"])):
            combined = " ".join((entry["opener"], entry["answer"], entry["close"]))
            duplicate = next((old for old in unique if similarity(combined, " ".join((old["opener"], old["answer"], old["close"]))) >= 0.82), None)
            if duplicate:
                removed.append({"removed_id": entry["id"], "kept_id": duplicate["id"], "reason": "near-duplicate within the same story"})
            elif len(unique) >= 4:
                removed.append({"removed_id": entry["id"], "kept_id": unique[0]["id"], "reason": "story already has four distinct retained examples"})
            else:
                unique.append(entry)
        kept.extend(unique)
    OUT.write_text(json.dumps({"summary": {"reviewed": len(candidates), "kept": len(kept), "removed_as_duplicate": len(removed)}, "items": kept, "removed": removed}, indent=2), encoding="utf-8")
    print(json.dumps({"reviewed": len(candidates), "kept": len(kept), "removed": len(removed), "by_decision": {key: sum(x["decision"] == key for x in kept) for key in priority}}, indent=2))

if __name__ == "__main__": main()
