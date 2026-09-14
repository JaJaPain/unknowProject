"""Generate a listening set through the REAL runtime path.

Every earlier listening set was hand-picked from raw batches. This one runs
the actual pipeline — selector gates, retries, lead-in joining, anatomy
corrections, per-character recency — so what the author hears is what the
game would actually say, including the effect of the gates.

  python build_showcase.py [per_beat]
"""
import json
import random
import sys

import anatomy
import beat as beatlib
import beat_transit
import beats_kaelen
import beats_nova
from selector import QuietMomentSelector

BEATS = []
for src in (beats_kaelen.BEATS, beats_nova.BEATS):
    for bid, b in src.items():
        if bid == "nova_long_transit":
            continue
        BEATS.append((b.get("speaker", ""), bid, beatlib.make(b)))
BEATS.append(("nova", "nova_long_transit", beat_transit.Module))


def build(per_beat=5, model="qwen3:14b", seed=20260802):
    rng = random.Random(seed)
    sel = {"kaelen": QuietMomentSelector(opener_window=6, line_window=40),
           "nova": QuietMomentSelector(opener_window=6, line_window=40)}
    out, silent, calls = [], 0, 0
    for who, bid, mod in BEATS:
        pk = list(mod.PACKETS)
        rng.shuffle(pk)
        got = 0
        attempts = 0
        while got < per_beat and attempts < per_beat * 3:
            attempts += 1
            if not pk:
                pk = list(mod.PACKETS)
                rng.shuffle(pk)
            line, c, _rej = sel[who].request(mod, pk.pop(), rng, model=model,
                                             max_calls=5)
            calls += c
            if line is None:
                silent += 1
                continue
            if who == "nova":
                fixed = anatomy.apply(line, rng)
                if fixed != line and sel[who].recent_lines:
                    sel[who].recent_lines[-1] = fixed
                line = fixed
            got += 1
            out.append({"speaker": who, "beat": bid, "line": line})
            print(f"  [{bid}] {line}")
    print(f"\n  {len(out)} lines, {silent} silences, {calls} calls")
    json.dump(out, open("showcase.json", "w", encoding="utf-8"),
              indent=1, ensure_ascii=False)
    return out


if __name__ == "__main__":
    build(int(sys.argv[1]) if len(sys.argv) > 1 else 5)
