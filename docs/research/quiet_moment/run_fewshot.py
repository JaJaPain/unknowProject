import sys, random, re, json
from qm import gen, parse_json_field, words, copied
from score import blacklist_hits
from fewshot import prompt, DEMOS
from qm import QUIET

W = re.compile(r"[a-z0-9%]+")
CURATED = {ch: [e["line"] for e in QUIET if e["character_id"] == ch] for ch in ("kaelen", "nova")}

# a line must STATE the anchor once (grounding) but not be only the anchor
ANCHOR = {
    "kaelen": set("payout pay paid payment modest job".split()),
    "nova": set("hull stable pursuit sensors".split()),
}


def evaluate(ch, line):
    bad = []
    w = W.findall(line.lower())
    if len(w) > 28:
        bad.append("too_long")
    if not (ANCHOR[ch] & set(w)):
        bad.append("missing_anchor")
    bad += blacklist_hits(ch, line)
    if copied(line, [d[1] for d in DEMOS[ch]], 5):
        bad.append("copied_demo")
    if copied(line, CURATED[ch], 5):
        bad.append("copied_curated")
    return bad


def run(model, n):
    for ch in ("kaelen", "nova"):
        ok, seen, ts = 0, set(), []
        print(f"\n===== {ch} / {model}")
        for i in range(n):
            raw, dt = gen(prompt(ch), model=model, num_predict=200,
                          temperature=0.9, top_p=0.95)
            ts.append(dt)
            line = parse_json_field(raw)
            if not line:
                print("  X   <no parse>")
                continue
            bad = evaluate(ch, line)
            if not bad:
                ok += 1
                seen.add(" ".join(words(line)))
            print(("  ok  " if not bad else "  X   ") + line + ("   " + str(bad) if bad else ""))
        print(f"  clean {ok}/{n}  distinct {len(seen)}  mean {sum(ts)/len(ts):.1f}s")


if __name__ == "__main__":
    run(sys.argv[1] if len(sys.argv) > 1 else "qwen3:4b",
        int(sys.argv[2]) if len(sys.argv) > 2 else 12)
