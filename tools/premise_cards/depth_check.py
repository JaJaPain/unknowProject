"""Depth check for incoming premise cards: finds stock filler phrases shared across cards,
strips them, and re-measures each card on its real content (reason, private fact and
resolution-summary lengths). Verdicts: ok / borderline / THIN.


Usage:
    python tools/premise_cards/depth_check.py

Run it when batches arrive suspiciously fast: padding can pass length checks while the
ideas stay thin.
"""
import io, json, os, re
from collections import Counter

I = "data/content/premise_cards/incoming"
A = "data/content/premise_cards/approved"


def load(d):
    out = []
    for f in sorted(os.listdir(d)):
        if f.endswith(".json"):
            data = json.load(io.open(os.path.join(d, f), encoding="utf-8"))
            for c in data if isinstance(data, list) else [data]:
                out.append((f, c))
    return out


inc = load(I)
appr = [c for _, c in load(A)]


def texts(c):
    for b in c["beats"]:
        for m in b["missions"]:
            yield m["reason"]
            yield m["private_fact"]
    for r in c["resolutions"]:
        yield r["summary"]


# Find 8-word phrases used in 3+ different incoming cards: those are stock filler.
def grams(s, n=8):
    w = re.findall(r"[a-z']+", s.lower())
    return {" ".join(w[i:i + n]) for i in range(len(w) - n + 1)}


count = Counter()
for _, c in inc:
    seen = set()
    for t in texts(c):
        seen |= grams(t)
    count.update(seen)
stock = {g for g, n in count.items() if n >= 3}

# Split every text into sentences; a sentence containing a stock 8-gram is filler.
def strip(t):
    sentences = re.split(r"(?<=[.!?])\s+", t)
    keep = [s for s in sentences if not (grams(s) & stock)]
    return " ".join(keep)


print("%-34s %-22s %4s %6s %6s %6s  %s" % ("card", "file", "fill", "reason", "priv", "ressum", "verdict"))
verdicts = {}
for f, c in inc:
    ms = [m for b in c["beats"] for m in b["missions"]]
    rs = c["resolutions"]
    filler = sum(1 for t in texts(c) if strip(t) != t)
    r_len = sum(len(strip(m["reason"])) for m in ms) / len(ms)
    p_len = sum(len(strip(m["private_fact"])) for m in ms) / len(ms)
    s_len = sum(len(strip(r["summary"])) for r in rs) / len(rs)
    thin = (r_len < 75) + (p_len < 55) + (s_len < 85)
    v = "THIN" if thin >= 2 else ("borderline" if thin == 1 else "ok")
    verdicts[c["id"]] = v
    print("%-34s %-22s %4d %6.0f %6.0f %6.0f  %s" % (c["id"][8:], f[6:28], filler, r_len, p_len, s_len, v))
print()
from collections import Counter as C2
print(C2(verdicts.values()))
print("stock phrases:", len(stock))
