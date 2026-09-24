"""Print a compact, story-only review sheet for premise cards.

Usage:
    python tools/premise_cards/review_sheet.py [PATH ...] [--ids id1,id2]

Structure is the validator's job; this sheet shows only what a story review
needs (who wants what, what the pilot does and why, how it can end, the
threads), at roughly a quarter of the size of the JSON. With no PATH it reads
data/content/premise_cards/incoming/.
"""
import io
import json
import os
import sys

DEFAULT_PATH = "data/content/premise_cards/incoming"


def cards_in(paths):
    for path in paths:
        files = sorted(os.path.join(path, f) for f in os.listdir(path) if f.endswith(".json")) \
            if os.path.isdir(path) else [path]
        for name in files:
            data = json.load(io.open(name, encoding="utf-8"))
            for card in data if isinstance(data, list) else [data]:
                yield card


def sheet(c):
    roles = {r["id"]: r for r in c["roles"]}
    out = ["## %s  [%s | %s | %s]" % (c["id"], c["scale"], "/".join(c["tone"]), "/".join(c["themes"])),
           "LOG  " + c["logline"],
           "CAST " + "; ".join("%s(%s%s)" % (r["id"], r["kind"], "," + r["archetype"] if r.get("archetype") else "")
                               for r in c["roles"]),
           "PUB  " + c["public_situation"],
           "TRUE " + c["private_truth"]]
    for b in c["beats"]:
        loc = "" if b.get("location", "same_system") == "same_system" else " @" + b["location"]
        out.append("B%d %s%s: %s" % (b["n"], b["function"], loc, b["public_change"]))
        for m in b["missions"]:
            ore = "(%s)" % m["ore"] if "ore" in m else ""
            routes = ", ".join("%s>%s" % (k, v.replace("resolution:", "R:")) for k, v in m.get("routes", {}).items())
            out.append("  %s%s %s->%s | %s | PRIV %s | %s"
                       % (m["verb"], ore, m["requester"], m.get("target"), m["reason"], m["private_fact"], routes))
        if b.get("player_choice"):
            pc = b["player_choice"]
            out.append("  CHOICE %s :: %s" % (pc["prompt"], " / ".join(
                "%s>%s" % (o["label"], o["leads_to"].replace("resolution:", "R:")) for o in pc["options"])))
    for r in c["resolutions"]:
        mark = "*" if r["id"] == c["default_resolution"] else ""
        fates = ", ".join("%s %s" % (q["target"], q["fate"]) for q in r["consequences"] if q["type"] == "cast_fate")
        out.append("R:%s%s %s [%s]" % (r["id"], mark, r["summary"], fates))
    for t in c["loose_threads"]:
        out.append("T[%s] %s" % (t["surface"], t["detail"]))
    out.append("V " + " | ".join("%s: %s" % kv for kv in c["voice_direction"].items()))
    return "\n".join(out)


def main(argv):
    ids = None
    paths = []
    for arg in argv:
        if arg.startswith("--ids"):
            ids = set(arg.split("=", 1)[1].split(",")) if "=" in arg else None
        else:
            paths.append(arg)
    for card in cards_in(paths or [DEFAULT_PATH]):
        if ids is None or card.get("id") in ids:
            print(sheet(card) + "\n")


if __name__ == "__main__":
    main(sys.argv[1:])
