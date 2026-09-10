"""Offline authoring probe: batch-generate OPINION CLAUSES only.

An opinion clause asserts nothing about the world - it is attitude toward a
fact the code already stated. That makes 'did it invent a fact?' checkable,
and a human curator only has to judge voice, not truth.
"""
import json, sys, re
from qm import gen, words
from fragments import BANK, CONTEXT, WHO

BRIEF = {
    "kaelen": """Kaelen is an independent broker: precise, dry, controlled, profit-minded, never sentimental. She may call the Captain "Shiny".

The game's code has just made her say, out loud, that a job closed safely and the payout was modest. Your job is to write the SECOND half of her line: her attitude to that.

Rules for every follow-up you write:
- It reacts only to what was already said. It reports nothing new.
- It names no amount, no client, no other job, no place, no other person, no object aboard the ship, and no event before or after this moment.
- It is one or two short sentences, 14 words or fewer.
- It works as a continuation of ANY phrasing of "the payout was modest".

Write %d follow-ups. Make them differ in ANGLE, not just wording: acceptance, grim arithmetic, deflected pride, warning against greed, self-mockery, professional standards, comparison to worse outcomes, refusal to celebrate, affection disguised as business, fatigue.
Return ONLY this JSON object: {"lines": ["...", "...", ...]}""",
    "nova": """N.O.V.A. is the ship's AI: clear, compact, observant; her humour lands as a systems remark. She calls the Captain "Captain". She never gives orders.

The game's code has just made her say, out loud, that the hull is stable and nothing is pursuing the ship after a hard fight. Your job is to write the SECOND half of her line: her attitude to that.

Rules for every follow-up you write:
- It reacts only to what was already said. It reports nothing new.
- It names no number, no percentage, no other system, no repair, no threat, no communication, no place, no other person, and no event before or after this moment.
- It contains no instruction or recommendation to the Captain.
- It is one or two short sentences, 14 words or fewer.
- It works as a continuation of ANY phrasing of "the hull held and nothing is following us".

Write %d follow-ups. Make them differ in ANGLE, not just wording: relief withheld, dry record-keeping, credit given to the ship, refusal to call it over, self-observation, understated approval, wry pessimism, quiet companionship, professional detachment, mild disbelief.
Return ONLY this JSON object: {"lines": ["...", "...", ...]}""",
}

DIGIT = re.compile(r"\d|%")
# words that would mean it asserted something new about the world
FACT_LEAK = {
    "kaelen": set("""fee fees coffee drink drinks board commission tip bonus tax invoice bill
        credits credit client contract cargo ore station dock port crew captain's next
        tomorrow yesterday week month monday tuesday wednesday thursday friday saturday sunday""".split()),
    "nova": set("""nominal safe safety threat threats hostile hostiles enemy enemies comms
        communications signal channel transmission repair repairs damage breach leak
        patch shields shield engine fuel reactor coolant oxygen station dock gate
        recommend suggest advise prepare reroute shiny""".split()),
}


def check(ch, s):
    bad = []
    w = words(s)
    if DIGIT.search(s):
        bad.append("number")
    if len(w) > 16:
        bad.append("too_long")
    leak = FACT_LEAK[ch] & set(w)
    if leak:
        bad.append("leak:" + ",".join(sorted(leak)))
    return bad


if __name__ == "__main__":
    model = sys.argv[1] if len(sys.argv) > 1 else "qwen3:4b"
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 20
    out = {}
    for ch in ("kaelen", "nova"):
        raw, dt = gen(BRIEF[ch] % count, model=model, num_predict=1600,
                      temperature=0.9, top_p=0.95)
        try:
            lines = json.loads(raw)["lines"]
        except Exception as e:
            print(f"{ch}: PARSE FAIL {e}\n{raw[:400]}")
            continue
        uniq = []
        for l in lines:
            if l.strip() and l.strip() not in uniq:
                uniq.append(l.strip())
        clean = [l for l in uniq if not check(ch, l)]
        print(f"\n===== {ch} / {model} / {dt:.0f}s "
              f"asked {count}, got {len(lines)}, unique {len(uniq)}, auto-clean {len(clean)}")
        for l in uniq:
            b = check(ch, l)
            print(("  ok  " if not b else "  X   ") + l + ("   " + str(b) if b else ""))
        out[ch] = uniq
    json.dump(out, open(f"offline_{model.replace(':','_').replace('.','')}.json", "w"), indent=1)
