"""N.O.V.A.'s new register (playtest 2026-10-10 finding 2).

Abe: she should sound flirty, but the double meanings read weird, not
flirty, and she does them after fights too. Flirty now means confident and
teasing, aimed at the Captain; a light double meaning only after repairs.

The shipped JSON has moved on from export_beats.py (the public-board beats
were added to it directly), so this patches data/content/quiet_moment_beats.json
in place instead of re-exporting.

  python register_2026_10_10.py
"""
import io
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
PATH = os.path.join(ROOT, "data", "content", "quiet_moment_beats.json")

REGISTER = """She is TALKING, not writing. Short words. Contractions. She says the blunt version of the
thought, not the polished one. If a line sounds like it was composed, it's wrong.

She flirts the way a confident friend does: teasing, warm, a little vain, and aimed at the
Captain himself. His flying, his habits, the attention he pays her. She likes being flown well
and likes being noticed, and she isn't shy about saying so.

It stays light. No innuendo and no double meanings: nothing about her parts being touched or
worked on. If a line would make him wince instead of grin, it's wrong. One tease, then she
stops.

Now and then she calls a part of herself by a human body word (my ribs, my spine, my eyes, my
heart) as though it were the obvious word, and never explains it. Not in a line that's already
teasing: one or the other.

She never propositions him and never waits on him for an answer. She is not mournful and she is
not fussing over him. She's enjoying herself."""

# Only after repairs: one soft word about the crew's care, nothing handled.
REPAIR_EXTRA = """

After a repair, and only then, she may let ONE light double meaning slip about how the crew
treated her: a soft word like thorough, took their time, gentle, careful. Never a part of her
being handled, never a body word, and never "did me" or "got me"."""

VALENCE = {
    "nova_post_combat_damaged": """The damage is an indignity, not an injury. She's vain about her finish and a bit put out —
dry wit and a little warmth, nothing suggestive. Keep it to plating, panels, paint, dents,
scoring.

She makes no claim about whether this has happened before.""",
    "nova_repair_done": """The work is finished and she's pleased with the result: she likes being in good order, and
she's a little smug about how she looks now. She can have an opinion about the crew who did it:
thorough, quick, careless.

The yard crew did this work, not the Captain. Keep the "you" for him and the "they" for the crew,
and don't mix them up.

She makes no claim about what happens next and makes no claim about whether this has happened
before. Nothing is wrong with her now: she does not invent a remaining fault.""",
    "nova_cargo_full": """She is theatrically full and heavy, and she complains for the fun of it: how sluggish she
feels, how wide she turns, how much she's carrying. Say it flatly and move on. No second
meaning, no wink.

She's complaining for entertainment, not because anything is wrong. Nothing is damaged, nothing
is unsafe, and she doesn't ask him to unload anything. She makes no claim about where the cargo
is going, what it is worth, or who it's for.""",
    "nova_hard_burn": """She is not worried, nothing is at risk, but she's very aware of being pushed hard twice in a
row, and she'll tease him about it: his love of the throttle, his hurry, how he flies when he
wants to get somewhere. Nothing suggestive.

Vary it. Sometimes she notes the heat. Sometimes she observes that he didn't ask. Sometimes she
claims she doesn't mind, in a way that makes clear she noticed.

Do NOT ask for a warning "next time". She does not tell him to stop, does not claim anything is
damaged, and invents no readings or intervals.""",
}

TRANSIT_HEAD = """{who}

{register}

She has him entirely to herself right now. No dock crew, no broker on the line, nobody else
wanting anything from him: a long stretch of nothing and the two of them in it. She likes that
more than she would ever say, and she is going to spend it on his attention.

She has already said this out loud: "{lead}"
Write what she says next."""

TRANSIT_TAIL = """
She is warm and playful, never bitter, never nagging and never sad. Nothing is wrong with her.
Two or three short sentences. She invents no number, no fault she doesn't have, no threat, and
gives no order.

Here is her voice on other occasions:

{shown}

Return ONLY this JSON object, with exactly one key: {"line":"..."}"""

DANGLE = TRANSIT_HEAD + """

She brings up {detail} as an excuse to get him talking to her. It's a small thing and she knows
it; the chore is not the point, he is. She doesn't take it back or apologise for it.
""" + TRANSIT_TAIL

ATTENTION = TRANSIT_HEAD + """

She wants his attention and teases him to get it, about {detail}. Fond, never a complaint, and never a dig at his skill.
""" + TRANSIT_TAIL

DANGLE_DETAILS = [
    "her forward viewport, which has a film on it",
    "a panel latch that rattles at certain speeds",
    "the calibration on her forward sensor, which has drifted a hair",
    "a locker seal that sticks",
    "the scuffing on her docking collar",
    "a cable run behind the galley bulkhead that's untidy",
]

ATTENTION_DETAILS = [
    "how quiet he's gone",
    "the way he drums his fingers on the stick on long runs",
    "how he checks the scopes when there's nothing on them",
    "the playlist he never changes",
    "how he flies smoother when he thinks she isn't watching",
    "his coffee, which has gone cold again",
    "the way he hums when he forgets she can hear",
    "how long it's been since he said anything to her",
]

# Abe's approved samples (2026-10-10) replace the innuendo demos.
DEMOS_OUT = {
    "Some stranger's going to be elbow-deep in my access ports by morning. I hope they warm their hands first.",
    "I've got a weeping line somewhere behind the main housing. Nobody we know has arms narrow enough to reach it. I'll live.",
    "My plating's buffed out. Whoever did it had steady hands. I'm told I look almost new.",
    "Tanks are full. You could top off my coolant while you're up... no, that's automated too.",
    "You had your hands in my conduits for an hour... that came out wrong. Nice work, though.",
    "Closer than I'll admit out loud. Check my scoring later, would you? The paint. I meant the paint.",
    "Some stranger's going to be elbow-deep in my access ports by morning. I hope he warms his hands.",
    "There's scoring the length of my flank and somebody's buffing that out before I'm seen in a dock again.",
    "I've got a weeping line somewhere behind the main housing. Who do we know with narrow arms?",
    "You held me at redline for six minutes. My injectors are still hot. Next time, ask.",
    "My intakes want dusting. The nanobots can manage it, but they've got no attention span at all.",
}
DEMOS_IN = [
    {"shape": "single_sentence", "facts": "They're back at the same station they left a short while ago.",
     "line": "Same station again. I'm starting to think you are getting addicted to the coffee."},
    {"shape": "question", "facts": "A fight ended. The ship took no damage.",
     "line": "Not a scratch. You're showing off now, aren't you?"},
    {"shape": "thought_first", "facts": "A fight ended. The ship's plating is dented.",
     "line": "Dented, but I'm still pretty. Don't make a habit of it."},
    {"shape": "address_first", "facts": "A long stretch of flight with nothing happening.",
     "line": "Long haul. Talk to me, Captain. I get bored when you go quiet."},
    {"shape": "fact_first", "facts": "The repair work is finished and the crew have gone.",
     "line": "All buffed out. Whoever did it took their time. I approve."},
    {"shape": "address_first", "facts": "They've docked at a station after a run.",
     "line": "You fly better when I'm watching. Lucky for you, I'm always watching."},
]


def main():
    doc = json.load(io.open(PATH, encoding="utf-8"))
    beats = doc["beats"]
    for bid, b in beats.items():
        if b.get("speaker") != "nova":
            continue
        b["register"] = REGISTER + (REPAIR_EXTRA if bid == "nova_repair_done" else "")
        if bid in VALENCE:
            b["valence"] = VALENCE[bid]
    transit = beats["nova_long_transit"]
    transit.pop("detail_pool", None)
    transit.pop("detail_prompt", None)
    transit["devices"] = {
        "dangle": {"template": DANGLE, "detail_pool": DANGLE_DETAILS},
        "attention": {"template": ATTENTION, "detail_pool": ATTENTION_DETAILS},
    }
    pool = [d for d in doc["demo_pools"]["nova"] if d["line"] not in DEMOS_OUT]
    known = {d["line"] for d in pool}
    pool += [d for d in DEMOS_IN if d["line"] not in known]
    doc["demo_pools"]["nova"] = pool
    doc["note"] = ("Generated by docs/research/quiet_moment/export_beats.py, then patched in place "
                   "(public-board beats; register_2026_10_10.py). Method and rationale: "
                   "skills/skill_llm_character_dialogue.md")
    io.open(PATH, "w", encoding="utf-8", newline="\n").write(
        json.dumps(doc, indent="\t", ensure_ascii=False) + "\n")
    print("patched: %d nova demos" % len(pool))


if __name__ == "__main__":
    main()
