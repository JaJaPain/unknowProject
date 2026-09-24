"""Coverage report for the approved premise deck: what is thin, what is overused.

Usage:
    python tools/premise_cards/deck_report.py

Gemini reads this before each batch and writes toward the gaps, so variety is
steered by counts rather than by a reviewer's memory.
"""
import io
import json
import os
from collections import Counter

APPROVED = "data/content/premise_cards/approved"
TARGET = 300

VOCAB_THEMES = (
    "debt_and_obligation safety_vs_freedom truth_vs_comfort loyalty_vs_survival progress_vs_tradition "
    "price_of_profit who_owns_the_past chosen_family justice_vs_mercy helpers_corrupted reinvention "
    "scarcity_breeds_cruelty faith_and_doubt cost_of_neutrality legacy labour_and_exploitation").split()
VOCAB_TONES = "noir heist tragic farce paranoid political survival melancholy tense hopeful bleak absurd".split()
VERBS = ("kill_ships comms_reversal recover_combat_drop deliver_ore delivery_courier purchase_delivery "
         "pickup_special investigate_signal").split()
ORES = "silicate ferrite water_ice cuprite thorium".split()
QUIRKS = ("pulsar nebula ion_storm dense_debris dying_star black_hole_proximity dead_system gravity_tides "
          "relay_dark_zone").split()
COMBAT = {"kill_ships", "comms_reversal", "recover_combat_drop"}


def load():
    cards = []
    if os.path.isdir(APPROVED):
        for name in sorted(os.listdir(APPROVED)):
            if name.endswith(".json"):
                data = json.load(io.open(os.path.join(APPROVED, name), encoding="utf-8"))
                cards += data if isinstance(data, list) else [data]
    return cards


def line(title, counter, vocab=None):
    keys = vocab or sorted(counter)
    items = sorted(((counter.get(k, 0), k) for k in keys))
    return "%-18s %s" % (title, "  ".join("%s:%d" % (k, n) for n, k in items))


def main():
    cards = load()
    n = len(cards)
    print("APPROVED DECK: %d cards (target %d)\n" % (n, TARGET))
    if not n:
        return
    scales = Counter(c["scale"] for c in cards)
    themes = Counter(t for c in cards for t in c["themes"])
    tones = Counter(t for c in cards for t in c["tone"])
    verbs = Counter(m["verb"] for c in cards for b in c["beats"] for m in b["missions"])
    ores = Counter(m["ore"] for c in cards for b in c["beats"] for m in b["missions"] if "ore" in m)
    quirks = Counter(q for c in cards for key in ("quirks_required", "quirks_preferred") for q in c["requirements"].get(key, []))
    shapes = Counter(" > ".join(b["function"] for b in c["beats"]) for c in cards)
    requesters = Counter(r.get("archetype") for c in cards for r in c["roles"] if r["kind"] == "person")
    combat_free = sum(1 for c in cards if not COMBAT & {m["verb"] for b in c["beats"] for m in b["missions"]})
    deadly = sum(1 for c in cards for r in c["resolutions"] if r["id"] == c["default_resolution"]
                 and any(q.get("fate") == "dead" for q in r["consequences"]))

    print("Sizes (aim ~40/40/20%%): personal %d, local %d, regional %d"
          % (scales["personal"], scales["local"], scales["regional"]))
    print("No combat: %d (%d%%)   Default ending kills someone: %d (%d%%)\n"
          % (combat_free, 100 * combat_free // n, deadly, 100 * deadly // n))
    print(line("Themes", themes, VOCAB_THEMES))
    print(line("Tones", tones, VOCAB_TONES))
    print(line("Mission verbs", verbs, VERBS))
    print(line("Ore types", ores, ORES))
    print(line("Quirks used", quirks, QUIRKS))
    whys = [c.get("core_why") or {} for c in cards]
    motives = Counter(w.get("motive") for w in whys if w.get("motive"))
    secrets = sorted({w.get("secret") for w in whys if w.get("secret")})
    print(line("core_why motives", motives))
    print("core_why coverage: %d of %d cards" % (sum(1 for w in whys if w.get("secret")), n))
    if secrets:
        print("Secrets already used (don't reuse; a similar shape is fine):")
        print("  " + ", ".join(secrets))
    print("\nMost common beat shapes:")
    for shape, count in shapes.most_common(5):
        print("  %3d  %s" % (count, shape))
    print("\nPerson archetypes used least (reference only; invent the story first, never build a card from this list):")
    all_types = ("broker dockmaster pilot official inspector mechanic preacher heir smuggler scientist soldier "
                 "merchant refugee journalist doctor labourer crime_boss union_organiser bureaucrat veteran "
                 "child_of_someone_important retired_legend con_artist bounty_hunter engineer archivist negotiator "
                 "gambler debt_collector station_manager").split()
    print("  " + ", ".join(sorted(all_types, key=lambda a: requesters.get(a, 0))[:10]))
    print("\nWRITE TOWARD: themes %s; tones %s; verbs %s."
          % (", ".join(sorted(VOCAB_THEMES, key=lambda t: themes.get(t, 0))[:4]),
             ", ".join(sorted(VOCAB_TONES, key=lambda t: tones.get(t, 0))[:3]),
             ", ".join(sorted(VERBS, key=lambda v: verbs.get(v, 0))[:2])))


if __name__ == "__main__":
    main()
