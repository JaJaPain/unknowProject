"""Live hybrid: code owns the fact sentence, 4b writes ONLY the opinion clause.

Differences from the failed prefix/tail experiment in the research log:
  - the prefix is NOT quoted verbatim in the prompt (that caused the echo);
  - no ban list of concrete nouns (that caused the coffee/hull%/threat priming);
  - the brief describes what the clause must DO, positively;
  - three curated OPINION clauses are shown as shape, not as content.
"""
import json, random, sys
from qm import gen, parse_json_field, words, copied
from fragments import BANK, WHO
from offline import check

SHAPE = {
    "kaelen": [
        "I have decided to be pleased about the quiet part.",
        "Do not look so betrayed. This is what most of the work looks like.",
        "I would celebrate, but celebrating has overheads.",
    ],
    "nova": [
        "I have no notes. That is unusual enough to mention.",
        "Quiet is not the same as finished, but I will accept it for now.",
        "For once I am not composing a warning.",
    ],
}

BRIEF = {
    "kaelen": """{who}

She has just said out loud that the job closed safely and the payout was modest. Write the SECOND half of her line: her attitude to what she just said.

The follow-up:
- reacts only to what she already said, and reports nothing new;
- names no amount, no client, no other job, no place, no other person, no object, and no event before or after this moment;
- is one or two short sentences, 14 words or fewer.

These three show the SHAPE and restraint to aim for. Do not reuse their wording or their idea:
{shape}

Return ONLY this JSON object: {{"follow_up":"..."}}""",
    "nova": """{who}

She has just said out loud that the hull held and nothing is following the ship after a hard fight. Write the SECOND half of her line: her attitude to what she just said.

The follow-up:
- reacts only to what she already said, and reports nothing new;
- names no number, no other system, no repair, no threat, no communication, no place, no other person, and no event before or after this moment;
- contains no instruction or recommendation to the Captain;
- is one or two short sentences, 14 words or fewer.

These three show the SHAPE and restraint to aim for. Do not reuse their wording or their idea:
{shape}

Return ONLY this JSON object: {{"follow_up":"..."}}""",
}


def prompt(ch, rng):
    shape = "\n".join("- " + s for s in rng.sample(BANK[ch]["opinion"], 3))
    return BRIEF[ch].format(who=WHO[ch], shape=shape)


if __name__ == "__main__":
    N = int(sys.argv[1]) if len(sys.argv) > 1 else 20
    model = sys.argv[2] if len(sys.argv) > 2 else "qwen3:4b"
    rng = random.Random(7)
    for ch in ("kaelen", "nova"):
        ok = 0
        seen = set()
        ts = []
        print(f"\n===== {ch} / {model}")
        for i in range(N):
            raw, dt = gen(prompt(ch, rng), model=model, num_predict=160,
                          temperature=0.9, top_p=0.95)
            ts.append(dt)
            t = parse_json_field(raw, "follow_up")
            if not t:
                print("  X   <no parse>", repr(raw[:90]))
                continue
            bad = check(ch, t)
            cp = copied(t, BANK[ch]["opinion"], 4)
            if cp:
                bad.append("copied_shape")
            if not bad:
                ok += 1
                seen.add(" ".join(words(t)))
            print(("  ok  " if not bad else "  X   ") + t + ("   " + str(bad) if bad else ""))
        print(f"  auto-pass {ok}/{N}   distinct {len(seen)}   mean {sum(ts)/len(ts):.1f}s")
