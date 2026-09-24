"""Fast triage for a large incoming batch: one line per card, red-flag hits, and the most
similar pairs against the approved deck.

Usage:
    python tools/premise_cards/triage.py

Used for lighter reviews once the deck is past calibration: read this first, then open
full review sheets (review_sheet.py --ids=...) only for flagged or doubtful cards. Flags
are prompts for a human look, not verdicts; the validator is the source of hard rules.
"""
import io, json, os, re, itertools

INC = "data/content/premise_cards/incoming"
APP = "data/content/premise_cards/approved"


def load(d):
    out = []
    for f in sorted(os.listdir(d)):
        if f.endswith(".json"):
            data = json.load(io.open(os.path.join(d, f), encoding="utf-8"))
            out += data if isinstance(data, list) else [data]
    return out


incoming, approved = load(INC), load(APP)

FLAGS = {
    "reserved?": r"\b(clone\w*|hologram\w*|ghost\w*|haunt\w*|spirit\w*|faked? (their |his |her )?death|not really dead|back from|revive\w*|resurrect\w*|possess\w*|madness|hallucinat\w*|voices?)\b",
    "carry-person": r"\b(passenger\w*|transport (the|a) (prisoner|refugee|bride|child|informant|defector|body|patient)|smuggle (her|him|them|the \w+) (out|off|through)|extract (her|him|them)|rescue (her|him|them)|escape with)\b",
    "walk/board": r"\b(lobby|corridor|hallway|office door|walk\w*|on foot|board(s|ing)? (the|a|her|his)|climb\w*|sneak\w*|infiltrat\w*)\b",
    "dock-moving": r"\bdock (with|alongside) (the|a) (\w+ )?(ship|yacht|freighter|cruiser|transport|convoy)\b",
    "body-cargo": r"\b(casket|coffin|corpse|body|bodies|remains)\b",
}


def text(c):
    return json.dumps(c, ensure_ascii=False)


print("=== TRIAGE ===")
for c in incoming:
    t = text(c)
    hits = []
    for name, pat in FLAGS.items():
        found = sorted({m.group(0).lower() for m in re.finditer(pat, t, re.I)})
        if found:
            hits.append("%s:%s" % (name, ",".join(found[:4])))
    print("%-34s %-8s %s" % (c["id"].replace("premise.", ""), c["scale"], c["logline"][:150]))
    if hits:
        print("   FLAGS " + " | ".join(hits))

STOP = set("""a an the and or of to in on for with by at from is are was were be been their they them his her its it this that
as into over under than then who whom whose which what when while before after only just all any some one two three
pilot player system station ship sector local must needs need hires hire wants want while but not no so if""".split())


def words(c):
    s = " ".join([c["logline"], c["public_situation"], c["private_truth"]]).lower()
    return {w for w in re.findall(r"[a-z]{4,}", s) if w not in STOP}


print("\n=== MOST SIMILAR PAIRS (incoming vs incoming+approved) ===")
pairs = []
pool = [(c, "I") for c in incoming] + [(c, "A") for c in approved]
wsets = {id(c): words(c) for c, _ in pool}
for (a, ta), (b, tb) in itertools.combinations(pool, 2):
    if ta == "A" and tb == "A":
        continue
    wa, wb = wsets[id(a)], wsets[id(b)]
    j = len(wa & wb) / max(1, len(wa | wb))
    tags = set(a["novelty_tags"]) & set(b["novelty_tags"])
    pairs.append((j + 0.05 * len(tags), a["id"], ta, b["id"], tb, sorted(wa & wb)[:8], sorted(tags)))
for s, a, ta, b, tb, common, tags in sorted(pairs, reverse=True)[:18]:
    print("%.2f %s(%s) ~ %s(%s) words=%s tags=%s" % (s, a.replace("premise.", ""), ta, b.replace("premise.", ""), tb, common, tags))
