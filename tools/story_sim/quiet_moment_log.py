"""Prints the quiet-moment log (QuietMomentDirector.log_path) for review:
every line the cast tried to say, the pattern-check failures, the small
model's word-salad verdict and what happened (spoken / retry / silent).

    python tools/story_sim/quiet_moment_log.py [--last=40] [--salad] [--path=<file>]

--salad shows only the lines the model called word salad, so its calls can
be double-checked. The default path is the game's user folder on Windows.
"""
import json
import os
import sys


def main(argv):
    path = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "SpaceGame", "quiet_moment_log.jsonl")
    last, salad_only = 40, False
    for a in argv:
        if a.startswith("--last="):
            last = int(a[7:])
        elif a == "--salad":
            salad_only = True
        elif a.startswith("--path="):
            path = a[7:]
    if not os.path.exists(path):
        sys.exit("no log yet at %s" % path)
    entries = []
    for raw in open(path, encoding="utf-8"):
        raw = raw.strip()
        if raw:
            try:
                entries.append(json.loads(raw))
            except ValueError:
                pass
    counts = {}
    for e in entries:
        key = e.get("sense") or ("pattern" if e.get("pattern_failures") else "?")
        counts[key] = counts.get(key, 0) + 1
    spoken = sum(1 for e in entries if e.get("outcome") == "spoken")
    silent = sum(1 for e in entries if e.get("outcome") == "silent")
    print("%d attempts: %d spoken, %d silent; verdicts %s" % (len(entries), spoken, silent, counts))
    shown = [e for e in entries if not salad_only or e.get("sense") == "word_salad"][-last:]
    for e in shown:
        mark = {"fine": "ok  ", "word_salad": "SALAD"}.get(e.get("sense", ""), "pat ")
        why = ", ".join(e.get("pattern_failures", []))
        print("%s %-6s %s %-22s #%d %-7s %s%s" % (e.get("time", "")[5:16], mark, e.get("speaker", "")[:5], e.get("beat", "")[:22],
            int(e.get("attempt", 0)), e.get("outcome", ""), e.get("line", ""), ("  [" + why + "]") if why else ""))


if __name__ == "__main__":
    main(sys.argv[1:])
