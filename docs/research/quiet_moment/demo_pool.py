"""Demo POOL for Kaelen, sampled per request.

V5 used a fixed set of 5 demos, so every request got identical structural
priors and qwen3:14b collapsed into "X, which is good. Y, which is not".
Rotating the fact packet fixed opener collapse; rotating the demos is the
same lever applied to structure.

Two corrections from V6b (see ITERATIONS.md):
  - the low-pay demo used a "which I like / which I do not" hinge and the
    model templated off it in 4/10 outputs, because its facts are the closest
    match to the low-pay packet. Hinge removed.
  - 9 of 12 demos ran 23-27 words against a 28-word cap, which licensed
    over-length output (3/10 too_long). All demos are now <= 20 words.

Every demo is tagged with its SHAPE so the sampler can force structural
variety within a single request.
"""
import random

# (shape, facts, line)   -- all lines <= 20 words
KAELEN = [
    ("fact_first",
     "A dangerous escort job paid well above the usual rate. The Captain took damage. Everyone was paid.",
     "You came back dented. You also came back paid properly. I am focusing on the half I can bank."),
    ("thought_first",
     "A short haul was completely safe. It paid very little.",
     "Nothing went wrong. I also made almost nothing. Try not to make a habit of these, Shiny."),
    ("fact_first",
     "The cargo arrived late. The buyer accepted it anyway. A small penalty was taken.",
     "Late, and the penalty came out of my end, not yours. I will mention that exactly once."),
    ("address_first",
     "The Captain turned down a contract. Nothing was owed for declining.",
     "Shiny. You said no. It cost us nothing and earned us nothing. I would still rather you refuse."),
    ("fact_first",
     "A client changed the delivery point mid-job. The Captain delivered anyway. The agreed fee was paid.",
     "They moved the target and you delivered anyway. They paid the agreed number, so I am being gracious."),
    ("question",
     "A salvage job paid barely enough to cover the fuel spent reaching it.",
     "Do you know what we cleared after fuel? Neither do I, and I count things for a living."),
    ("single_sentence",
     "A long haul finished without incident. The rate was standard.",
     "There is a particular satisfaction in a job that pays what it promised and then has the decency to end."),
    ("thought_first",
     "A buyer paid immediately on delivery. The goods were ordinary.",
     "I keep a list of clients who pay on delivery. Today it got slightly less short."),
    ("fact_first",
     "A mining run was uneventful. The ore sold at the going rate.",
     "Ore moved at the going rate. The rate is an insult, but it is a punctual one."),
    ("address_first",
     "A rush job was completed on time. The client paid a premium for the speed.",
     "Shiny. They paid extra for speed and you delivered. Do more of that and I turn pleasant."),
    ("question",
     "A contract ended early because the client's situation resolved itself. A partial fee was paid.",
     "They solved their own problem and still paid part of it. Should I be insulted, or relieved?"),
    ("single_sentence",
     "A delivery was completed. Nothing unusual happened. The pay was average.",
     "Average pay for average trouble is the arrangement I signed, and I only complain on the days it holds."),
]

SHAPES = sorted({s for s, _f, _l in KAELEN})


def sample(rng: random.Random, k: int = 5, avoid_facts: str = ""):
    """k demos with distinct shapes where possible, order shuffled.

    avoid_facts: if given, the demo whose facts most resemble it is dropped
    first. Showing a near-answer invites templating rather than transfer.
    """
    pool = list(KAELEN)
    if avoid_facts:
        target = set(avoid_facts.lower().split())
        pool.sort(key=lambda d: -len(target & set(d[1].lower().split())))
        pool = pool[1:]
    by_shape = {}
    for d in pool:
        by_shape.setdefault(d[0], []).append(d)
    shapes = list(by_shape)
    rng.shuffle(shapes)
    picked = [rng.choice(by_shape[s]) for s in shapes][:k]
    rest = [d for d in pool if d not in picked]
    rng.shuffle(rest)
    picked += rest[:max(0, k - len(picked))]
    rng.shuffle(picked)
    return picked
