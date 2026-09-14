"""Resumable batch runner: 30 per character on qwen3.6:35b-a3b, banked to JSON.

Usage:  python batch.py <character> <n_more>
Then:   python batch.py show <character> <start> <count>
"""
import json, os, sys
from qm import gen, parse_json_field, words
from fewshot import prompt
from run_fewshot import evaluate

STORE = "batch_35b.json"
MODEL = "qwen3.6:35b-a3b"


def load():
    return json.load(open(STORE)) if os.path.exists(STORE) else {"kaelen": [], "nova": []}


def add(ch, n):
    data = load()
    for i in range(n):
        raw, dt = gen(prompt(ch), model=MODEL, num_predict=200,
                      temperature=0.9, top_p=0.95)
        line = parse_json_field(raw)
        data[ch].append({"line": line, "flags": evaluate(ch, line) if line else ["no_parse"],
                         "secs": round(dt, 1)})
        json.dump(data, open(STORE, "w"), indent=1)
        print(f"  {len(data[ch]):2d}/{n} banked ({dt:.1f}s)", flush=True)


def show(ch, start, count):
    data = load()[ch]
    rows = data[start:start + count]
    seen = set()
    for i, r in enumerate(rows, start + 1):
        mark = "  " if not r["flags"] else "!!"
        print(f"{mark} {i:2d}. {r['line']}")
        if r["flags"]:
            print(f"        flags: {r['flags']}")
        seen.add(" ".join(words(r["line"] or "")))
    clean = sum(1 for r in rows if not r["flags"])
    print(f"\n  batch: {clean}/{len(rows)} clean, {len(seen)}/{len(rows)} distinct, "
          f"mean {sum(r['secs'] for r in rows)/len(rows):.1f}s")
    tot = sum(1 for r in data if not r["flags"])
    print(f"  running total for {ch}: {tot}/{len(data)} clean")


if __name__ == "__main__":
    if sys.argv[1] == "show":
        show(sys.argv[2], int(sys.argv[3]), int(sys.argv[4]))
    else:
        add(sys.argv[1], int(sys.argv[2]))
