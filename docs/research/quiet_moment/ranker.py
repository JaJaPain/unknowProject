"""Best-of-N with an LLM ranker.

Generation is a hard task; DISCRIMINATION between finished candidates is an
easier one. The quality failures at V8 are muddled metaphors and vagueness,
which no lexical rule catches -- so the question is whether the same model
can spot them when shown side by side.

No colon-labels in the prompt (they become JSON keys under format:"json").
"""
import json, random
from qm import gen, parse_json_field

CRITERIA = """You are choosing which take to use for a line of game dialogue.

The speaker is Kaelen, an independent broker: precise, dry, controlled, profit-minded but never
cruel to the Captain. She has just been told a job closed safely and paid badly.

Prefer the take that:
- sounds like a person speaking, not a status report;
- carries one concrete, specific image rather than a general sentiment;
- grumbles about the money without insulting the Captain;
- would still be worth hearing the third time a player heard it.

Reject any take whose comparison or metaphor does not quite make sense, and any take that could
have been said by any character in any game."""


def pick(candidates, model="qwen3:14b"):
    listed = "\n".join(f"{i}. {c}" for i, c in enumerate(candidates))
    p = f"""{CRITERIA}

The takes:
{listed}

Return ONLY this JSON object, with exactly two keys:
{{"best": <the number of the best take>, "worst": <the number of the weakest take>}}"""
    raw, dt = gen(p, model=model, num_predict=120, temperature=0.3)
    try:
        d = json.loads(raw)
        b, w = int(d["best"]), int(d["worst"])
        if 0 <= b < len(candidates) and 0 <= w < len(candidates):
            return b, w, dt
    except Exception:
        pass
    return None, None, dt
