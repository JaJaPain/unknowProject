import random, sys, json
from qm import gen, parse_json_field, copied, has_any
from prompts import v0_baseline, REFS

N = int(sys.argv[1]) if len(sys.argv) > 1 else 8
rng = random.Random(1234)
rows = []
for i in range(N):
    for ch in ("kaelen", "nova"):
        p, picks = v0_baseline(ch, rng)
        raw, dt = gen(p)
        line = parse_json_field(raw)
        rows.append({"ch": ch, "line": line, "picks": picks, "dt": round(dt, 1)})
        print(f"{ch:7s} {dt:5.1f}s  {line}")
        cp = copied(line or "", REFS[ch]) if line else None
        if cp:
            print(f"         ^ COPIED: {cp}")
json.dump(rows, open("v0.json", "w"), indent=1)
