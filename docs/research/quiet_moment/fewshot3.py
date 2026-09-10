"""V3: fix V2's opener collapse.

V2 put the fact first in all five demos and capped it at seven words, so the
model opened all ten lines with "Modest pay". V3 keeps "mention only one fact"
but demonstrates five DIFFERENT structures:
  1. turn first, fact second
  2. direct address first
  3. single sentence, fact embedded mid-line
  4. fact first (the V2 shape, kept so it stays available)
  5. question form
"""
from fewshot import TEST, WHO

DEMOS = {
    "kaelen": [
        # turn first, fact arrives second
        ("The cargo arrived late. The buyer accepted it anyway. A small penalty was taken.",
         "I am not going to ask why they accepted it late. Curiosity has a way of becoming a second penalty."),
        # direct address first
        ("The Captain turned down a contract. Nothing was owed for declining.",
         "Shiny. You said no, and it cost us nothing. Do you understand how rare that sentence is?"),
        # one sentence, fact embedded
        ("A repair bill was paid in full. The ship is fixed.",
         "There is a particular kind of quiet that comes from owing absolutely nobody anything, and the settled bill just bought us some."),
        # fact first
        ("The ore sold at the standard market rate. The buyer paid on time.",
         "Standard rate, paid on time. I keep waiting for the part where somebody disappoints me."),
        # question
        ("A client changed the delivery point mid-job. The Captain delivered anyway. The agreed fee was paid.",
         "They moved the target and still paid us. Do I file that under miracles or under precedent?"),
    ],
    "nova": [
        ("The gate transit completed. The ship is on the far side.",
         "I dislike that stretch of the process. Now that the transit is done, I dislike having no reason to."),
        ("Docking is complete. The ship is secured to the station clamps.",
         "Captain. The clamps are holding us more firmly than I hold most opinions."),
        ("Refuelling finished. The tanks are full.",
         "There is a brief and specific interval between the tanks being full and that no longer being true, and we are inside it."),
        ("A minor scrape on the plating was repaired at dock.",
         "The plating is mended. The ship has stopped mentioning it, which I take as forgiveness."),
        ("The cargo hold was emptied at the station. Nothing remains aboard.",
         "The hold is empty. How long do you estimate before that stops being the case?"),
    ],
}


def prompt(ch):
    shown = "\n\n".join(
        f"Once, when {f[0].lower() + f[1:]} she said this.\n“{l}”"
        for f, l in DEMOS[ch]
    )
    return f"""{WHO[ch]}

You will be given the only facts that are true right now. Write one spoken line for her.

She mentions only ONE of the given facts — she is speaking, not filing a report. The rest of the
line is hers: her angle on it. That part introduces nothing outside the facts: no amount, no
other person, no other place, no object, no event before or after this moment. 28 words maximum.

Notice that the examples below are built differently from each other. Some open with the fact,
some open with her thought, some with the Captain's name, some ask a question. Vary the shape.

{shown}

Now, {TEST[ch][0].lower() + TEST[ch][1:]} Write what she says. Use a different idea AND a
different sentence shape from every example above.

Return ONLY this JSON object, with exactly one key: {{"line":"..."}}"""
