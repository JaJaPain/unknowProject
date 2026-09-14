import random, sys, json, importlib
from qm import gen, parse_json_field
from prompts import REFS
from score import score
import variants

names = sys.argv[1].split(",")
N = int(sys.argv[2]) if len(sys.argv) > 2 else 8
model = sys.argv[3] if len(sys.argv) > 3 else "qwen3:4b"

allrows = []
for name in names:
    fn = getattr(variants, name)
    rng = random.Random(4242)
    tally = {"kaelen": [0, 0], "nova": [0, 0]}
    print(f"\n===== {name} ({model}) =====")
    for i in range(N):
        for ch in ("kaelen", "nova"):
            p, picks = fn(ch, rng)
            raw, dt = gen(p, model=model)
            line = parse_json_field(raw)
            s = score(ch, line or "", REFS[ch])
            tally[ch][0] += 1 if s["pass_black"] else 0
            tally[ch][1] += 1 if s["pass_lex"] else 0
            flag = ("B" if s["pass_black"] else ".") + ("L" if s["pass_lex"] else ".")
            print(f" {flag} {ch:7s} {line}")
            bad = s["struct"] + s["black"] + (["copy"] if s["copy"] else [])
            if bad:
                print(f"      -> {bad}")
            if s["lex"] and not s["black"]:
                print(f"      -> lex-only: {s['lex']}")
            allrows.append({"variant": name, "ch": ch, "line": line,
                            "score": {k: v for k, v in s.items() if k != "copy"},
                            "copy": s["copy"], "picks": picks})
    for ch in ("kaelen", "nova"):
        print(f" {name} {ch}: blacklist {tally[ch][0]}/{N}  lexicon {tally[ch][1]}/{N}")
json.dump(allrows, open(f"ab_{'_'.join(names)}.json", "w"), indent=1)
