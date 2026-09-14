"""V9 demo pool: PLAIN and SPOKEN.

Author calibration (2026-08-01) on the V8 batch: rejected the two most
writerly lines ("I'll note that in the ledger, under 'lessons'", "leaves the
ledger flat... work that leaves it slightly richer") and passed the plainer
ones as "not terrible".

Two faults in the V6-V8 pool, both mine:
  1. Literary register -- "There is a particular satisfaction in a job that
     pays what it promised and then has the decency to end."
  2. ZERO contractions across all 12 demos ("I am", "I will", "It is").
     That alone makes every output sound written rather than spoken.

Author's own reference for her, which is the target register:
  "I know this job is way safer, but I don't make shit from it, so don't make
   these a habit."
Plain words, contractions, direct, a clear point instead of a flourish.

Rule for adding demos here: if it sounds like something you'd WRITE, cut it.
She's talking, not composing.
"""
import random

# (shape, facts, line)  -- plain, spoken, contracted, <= 20 words
KAELEN = [
    ("fact_first",
     "A dangerous escort job paid well above the usual rate. The Captain took damage. Everyone was paid.",
     "You came back dented. You also came back paid. I'll take that trade."),
    ("thought_first",
     "A short haul was completely safe. It paid very little.",
     "Nothing went wrong. I also made almost nothing. Don't make these a habit, Shiny."),
    ("fact_first",
     "The cargo arrived late. The buyer accepted it anyway. A small penalty was taken.",
     "It was late, so the penalty came out of my end. Not yours. I'm mentioning it once."),
    ("address_first",
     "The Captain turned down a contract. Nothing was owed for declining.",
     "Shiny. You said no. Cost us nothing, earned us nothing. I'd still rather you say no than take a bad one."),
    ("fact_first",
     "A client changed the delivery point mid-job. The Captain delivered anyway. The agreed fee was paid.",
     "They moved the drop and you still made it. They paid what they said. Fine."),
    ("question",
     "A salvage job paid barely enough to cover the fuel spent reaching it.",
     "You know what we cleared on that after fuel? Nothing. Ask me again when I'm less annoyed."),
    ("single_sentence",
     "A long haul finished without incident. The rate was standard.",
     "It paid what it said it would pay, and you'd be amazed how rare that is."),
    ("thought_first",
     "A buyer paid immediately on delivery. The goods were ordinary.",
     "They paid the second it landed. I wish more of them worked that way."),
    ("fact_first",
     "A mining run was uneventful. The ore sold at the going rate.",
     "Ore went at the going rate. The going rate's an insult, but it showed up on time."),
    ("address_first",
     "A rush job was completed on time. The client paid a premium for the speed.",
     "Shiny. They paid extra for speed and you were fast. Do more of that."),
    ("question",
     "A contract ended early because the client's situation resolved itself. A partial fee was paid.",
     "They fixed their own problem and still paid part of it. Who am I to argue?"),
    ("single_sentence",
     "A delivery was completed. Nothing unusual happened. The pay was average.",
     "Average pay for average trouble is the deal, and I only complain when it's worse."),
]

SHAPES = sorted({s for s, _f, _l in KAELEN})


def sample(rng: random.Random, k: int = 5, avoid_facts: str = ""):
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
