"""Apply a batch of review decisions to the taunt pool.

Usage: python tools/apply_taunt_review.py "1N 2N 3Y 4Y 5Y" ["3=replacement text"]

Decisions apply to the NEXT n queued lines, in order. Rejected lines are removed
from data/content/taunt_lines.json; replacements overwrite in place. State lives
in logs/taunt_review_state.json so the pass can resume.
"""
import io
import json
import sys

STATE = "logs/taunt_review_state.json"
DATA = "data/content/taunt_lines.json"


def main():
    decisions = sys.argv[1].split()
    replacements = {}
    for arg in sys.argv[2:]:
        num, _, text = arg.partition("=")
        replacements[int(num.strip())] = text.strip()

    state = json.load(io.open(STATE, encoding="utf-8"))
    data = json.load(io.open(DATA, encoding="utf-8"))
    batch = state["queue"][:len(decisions)]
    if len(batch) != len(decisions):
        sys.exit("queue has %d left, got %d decisions" % (len(batch), len(decisions)))

    for index, (decision, item) in enumerate(zip(decisions, batch), start=1):
        cause, text = item["cause"], item["text"]
        lines = data["causes"][cause]["lines"]
        verdict = decision.upper().lstrip("0123456789")
        if verdict == "N":
            lines.remove(text)
            state["rejected"].append(item)
            print("  %d REJECT  [%s] %s" % (index, cause, text))
        else:
            if index in replacements:
                new = replacements[index]
                lines[lines.index(text)] = new
                item = {"cause": cause, "text": new, "was": text}
                print("  %d REVISE  [%s] %s" % (index, cause, new))
            else:
                print("  %d approve [%s] %s" % (index, cause, text))
            state["approved"].append(item)

    state["queue"] = state["queue"][len(decisions):]
    io.open(STATE, "w", encoding="utf-8").write(json.dumps(state, indent="\t") + "\n")
    io.open(DATA, "w", encoding="utf-8").write(json.dumps(data, indent="\t") + "\n")
    total = sum(len(v["lines"]) for v in data["causes"].values())
    print("\napproved %d / rejected %d / %d left to review / pool now %d" % (
        len(state["approved"]), len(state["rejected"]), len(state["queue"]), total))


if __name__ == "__main__":
    main()
