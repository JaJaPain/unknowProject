"""Reusable experiment runner.

  python runner.py <version_module> <model> <n> [tag]

The version module must expose prompt(packet, rng) and a PACKETS list.
Packets are cycled without replacement (sampling WITH replacement inflates
apparent opener collapse -- that bug cost a run in V6).
"""
import collections, json, random, re, sys
from qm import gen, parse_json_field, words

PRON = re.compile(r"\b(he|him|his)\b", re.I)
# structural tics worth counting: each collapsed a run at some point
# Kaelen's bible bans "generic hero praise" outright. She prices risk; she
# does not compliment his skill.
PRAISE = re.compile(
    r"(you'?re good at|you'?re good|you did (good|well|it right)|nice work"
    r"|well done|good work|proud of you|you handled it|impressive|you earned"
    r"|you'?ve got a knack|you'?re better at)", re.I)

# "one" is excluded deliberately: it is overwhelmingly a demonstrative here
# ("this one paid small"), and including it false-flagged 9/20 good lines.
NUMERIC = re.compile(r"\d|\b(two|three|four|five|six|seven|eight|nine|ten|"
                     r"eleven|twelve|dozen|hundred|thousand)\b", re.I)

TICS = {
    "which_hinge": re.compile(r",\s*which\s+(is|i)\b", re.I),
    "i_prefer": re.compile(r"\bI (prefer|like)\b", re.I),
    "lets": re.compile(r"\b(let's|let us)\b", re.I),
    "next_time": re.compile(r"\bnext (time|one)\b", re.I),
}


def _shares_run(a, b, n=5):
    aw, bw = words(a), words(b)
    if len(aw) < n or len(bw) < n:
        return False
    bs = " ".join(bw)
    return any(" ".join(aw[i:i + n]) in bs for i in range(len(aw) - n + 1))


def normalize_quotes(s):
    """Models emit U+2019 for apostrophes; ASCII regexes silently miss it.
    This bit us twice: "you're good at" praise and possessive "hull's"."""
    return (s.replace("’", "'").replace("‘", "'")
             .replace("“", '"').replace("”", '"')
             .replace("—", "-").replace("–", "-"))


def check(line, cap=28, packet="", speaker="", demos=()):
    f = []
    if not line:
        return ["no_parse"]
    line = normalize_quotes(line)
    # the player must never be shown a demo line back
    for d in demos:
        if _shares_run(line, d, 5):
            f.append("demo_echo")
            break
    # echo: the line hands the packet's own words back to the player
    if packet and _shares_run(line, packet):
        f.append("packet_echo")
    # cross-character address: only N.O.V.A. says Captain, only Kaelen says Shiny
    low = line.lower()
    if speaker == "kaelen" and "captain" in low:
        f.append("wrong_address")
    if speaker == "nova" and "shiny" in low:
        f.append("wrong_address")
    if len(words(line)) > cap:
        f.append("too_long")
    if PRON.search(line):
        f.append("assumes_captain_gender")
    if "\n" in line:
        f.append("multiline")
    if speaker == "kaelen" and PRAISE.search(line):
        f.append("generic_praise")
    # invented quantities: neither character is licensed to state a number the
    # packet didn't supply. Caught "45 knots" and "0.7c" in a space sim.
    if NUMERIC.search(line) and not NUMERIC.search(packet or ""):
        f.append("invented_number")
    return f


def run(mod, model, n, tag=""):
    rng = random.Random(20260729)
    packets = list(mod.PACKETS)
    rows = []
    for i in range(n):
        if i % len(packets) == 0:
            rng.shuffle(packets)
        p = packets[i % len(packets)]
        raw, dt = gen(mod.prompt(p, rng), model=model, num_predict=200,
                      temperature=0.9, top_p=0.95)
        line = (parse_json_field(raw) or "").strip().strip('“”"')
        rows.append({"line": line, "secs": round(dt, 1),
                     "flags": check(line, packet=p,
                                    speaker=getattr(mod, "SPEAKER", ""),
                                    cap=getattr(mod, "CAP", 28),
                                    demos=getattr(mod, "DEMO_LINES", ()))})
    name = f"{tag or mod.__name__}_{model.replace(':', '_').replace('.', '')}"
    json.dump(rows, open(f"out_{name}.json", "w", encoding="utf-8"),
              indent=1, ensure_ascii=False)
    return rows, name


def report(rows, name, show=True):
    n = len(rows)
    if show:
        for i, r in enumerate(rows, 1):
            print(("  " if not r["flags"] else "!!") + f" {i:2d}. {r['line']}")
            if r["flags"]:
                print(f"         {r['flags']}")
    ops = collections.Counter(" ".join(words(r["line"])[:2]) for r in rows)
    clean = sum(1 for r in rows if not r["flags"])
    dup = n - len({" ".join(words(r["line"])) for r in rows})
    print(f"\n  == {name}  n={n}")
    print(f"  clean {clean}/{n}   exact-dupes {dup}   "
          f"distinct openers {len(ops)}/{n}   mean {sum(r['secs'] for r in rows)/n:.1f}s")
    for tic, rx in TICS.items():
        c = sum(1 for r in rows if rx.search(r["line"]))
        if c:
            print(f"  tic {tic}: {c}/{n}")
    rep = [(o, c) for o, c in ops.most_common(3) if c > 1]
    if rep:
        print(f"  repeated openers: {rep}")


if __name__ == "__main__":
    mod = __import__(sys.argv[1])
    rows, name = run(mod, sys.argv[2], int(sys.argv[3]),
                     sys.argv[4] if len(sys.argv) > 4 else "")
    report(rows, name)
