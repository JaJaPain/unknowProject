"""Full-playthrough simulation across all beats.

Every earlier sim ran one beat in isolation. In the real game a character's
beats interleave, and recency has to be tracked PER CHARACTER, not per beat —
otherwise Kaelen opens three different beats the same way and the player
hears the repetition even though each beat looked fine alone.

  python playthrough.py [moments]
"""
import collections, json, random, sys

import anatomy
import beat as beatlib
import beats_kaelen
import beats_nova
from selector import QuietMomentSelector

import beat_transit

BEATS = []
for src in (beats_kaelen.BEATS, beats_nova.BEATS):
    for bid, b in src.items():
        if bid == "nova_long_transit":
            continue           # superseded by beat_transit (two rotating devices)
        BEATS.append((b.get("speaker", ""), bid, beatlib.make(b)))
BEATS.append(("nova", "nova_long_transit", beat_transit.Module))


def run(moments=40, model="qwen3:14b", seed=99):
    rng = random.Random(seed)
    # one selector per character: the player hears the CHARACTER, not the beat
    sel = {"kaelen": QuietMomentSelector(opener_window=6, line_window=30),
           "nova": QuietMomentSelector(opener_window=6, line_window=30)}
    packets = {bid: list(mod.PACKETS) for _s, bid, mod in BEATS}
    served, silent, calls = [], 0, 0
    rejects = collections.Counter()
    for i in range(moments):
        who, bid, mod = BEATS[rng.randrange(len(BEATS))]
        pk = packets[bid]
        if not pk:
            pk = packets[bid] = list(mod.PACKETS)
        p = pk.pop(rng.randrange(len(pk)))
        line, c, rej = sel[who].request(mod, p, rng, model=model, max_calls=5)
        if line and getattr(mod, "LEAD_INS", None) is None and hasattr(mod, "lead_in"):
            pass  # lead-in already joined inside the selector
        calls += c
        for _l, why in rej:
            rejects.update(why)
        if line is None:
            silent += 1
            print(f"  {i+1:2d}. [{bid}] (silence)")
            continue
        if who == "nova":
            fixed = anatomy.apply(line, rng)
            if fixed != line:
                sel[who].recent_lines[-1] = fixed
            line = fixed
        served.append((who, bid, line))
        print(f"  {i+1:2d}. [{bid}] {line}")
    return served, silent, calls, rejects


if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 40
    served, silent, calls, rejects = run(n)
    from qm import words
    per = collections.defaultdict(list)
    for who, _b, l in served:
        per[who].append(" ".join(words(l)[:2]))
    print(f"\n  served {len(served)}/{n}, silent {silent} ({silent/n:.0%}), "
          f"{calls/n:.1f} calls/moment")
    print(f"  exact duplicates: {len(served) - len({l for _w,_b,l in served})}")
    for who, ops in per.items():
        print(f"  {who}: {len(set(ops))}/{len(ops)} distinct openers across beats")
    print(f"  rejections: {dict(rejects)}")
    json.dump([{"speaker": w, "beat": b, "line": l} for w, b, l in served],
              open("playthrough_mixed.json", "w", encoding="utf-8"),
              indent=1, ensure_ascii=False)
