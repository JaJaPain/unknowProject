"""Remove a taunt line by its audio clip stem, keeping data and audio in sync.

Usage: python tools/cut_taunt_line.py contract_hit_06

Deletes the line from data/content/taunt_lines.json, removes the rendered clip,
and drops it from both index files so a cut line is never auditioned twice.
Other clips keep their numbers: filenames are stable references, so renumbering
would invalidate every note already made about them.
"""
import glob
import io
import json
import os
import sys

DATA = "data/content/taunt_lines.json"
ROOT = os.path.join("logs", "taunt_pool_audio")


def main():
    stem = sys.argv[1]
    cause, _, num = stem.rpartition("_")
    matches = glob.glob(os.path.join(ROOT, cause, "%s_*.wav" % stem))
    if not matches:
        sys.exit("no clip found for %s" % stem)
    clip = matches[0]

    index_path = os.path.join(ROOT, cause, "index.txt")
    rows = io.open(index_path, encoding="utf-8").read().splitlines()
    row = next((r for r in rows if r.startswith(os.path.basename(clip))), None)
    if row is None:
        sys.exit("no index row for %s" % stem)
    text = row.split("s  ", 1)[1]

    data = json.load(io.open(DATA, encoding="utf-8"))
    lines = data["causes"][cause]["lines"]
    if text not in lines:
        sys.exit("line not in data (already cut?): %s" % text)
    lines.remove(text)
    io.open(DATA, "w", encoding="utf-8").write(json.dumps(data, indent="\t") + "\n")

    os.remove(clip)
    io.open(index_path, "w", encoding="utf-8").write(
        "\n".join(r for r in rows if not r.startswith(os.path.basename(clip))) + "\n")
    master = os.path.join(ROOT, "INDEX.txt")
    m = io.open(master, encoding="utf-8").read().splitlines()
    io.open(master, "w", encoding="utf-8").write(
        "\n".join(r for r in m if not r.startswith(os.path.basename(clip))) + "\n")

    print("cut [%s] %s" % (cause, text))
    print("%s now has %d lines" % (cause, len(lines)))


if __name__ == "__main__":
    main()
