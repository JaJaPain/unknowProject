"""V2: demos where the fact is GLANCING and the turn carries the line,
plus two positive constraints replacing nothing (no bans added).

Changes vs fewshot.py, both targeting the recitation failure:
  - every Kaelen demo now names the fact in <=7 words;
  - explicit "name one fact, briefly" instruction;
  - "never list more than one of the given facts".
"""
from fewshot import TEST, WHO

DEMOS = {
    "kaelen": [
        ("The cargo arrived late. The buyer accepted it anyway. A small penalty was taken.",
         "Late, and they took it anyway. I am not asking why. Curiosity has a way of becoming a second penalty."),
        ("The Captain turned down a contract. Nothing was owed for declining.",
         "You said no. Do you understand how rare it is for that to cost us nothing, Shiny?"),
        ("A repair bill was paid in full. The ship is fixed.",
         "Bill settled. I would like a moment to enjoy owing absolutely nobody anything."),
        ("The ore sold at the standard market rate. The buyer paid on time.",
         "Standard rate, paid on time. I keep waiting for the part where somebody disappoints me."),
        ("A client changed the delivery point mid-job. The Captain delivered anyway. The agreed fee was paid.",
         "They moved the target and still paid. Filing that under miracles, Shiny, not precedent."),
    ],
    "nova": [
        ("The gate transit completed. The ship is on the far side.",
         "Transit complete. I dislike that stretch of the process, and I dislike having no reason to."),
        ("Docking is complete. The ship is secured to the station clamps.",
         "We are secured. The clamps are holding us more firmly than I hold most opinions."),
        ("Refuelling finished. The tanks are full.",
         "Tanks are full. I intend to enjoy the brief interval before that stops being true."),
        ("A minor scrape on the plating was repaired at dock.",
         "The plating is mended. The ship has stopped mentioning it, which I take as forgiveness."),
        ("The cargo hold was emptied at the station. Nothing remains aboard.",
         "The hold is empty. Tidiest I have seen it. I give it an hour."),
    ],
}


def prompt(ch):
    shown = "\n\n".join(
        f"Once, when {f[0].lower() + f[1:]} she said this.\n“{l}”"
        for f, l in DEMOS[ch]
    )
    return f"""{WHO[ch]}

You will be given the only facts that are true right now. Write one spoken line for her.

She names ONE of the given facts, in seven words or fewer. She never lists the others — she is
speaking, not filing a report. The rest of the line is hers: her angle on what she just named.
That part introduces nothing outside the facts — no amount, no other person, no other place, no
object, no event before or after this moment. 28 words maximum.

Here is the transform, on other moments:

{shown}

Now, {TEST[ch][0].lower() + TEST[ch][1:]} Write what she says. Use a different idea from every
example above.

Return ONLY this JSON object, with exactly one key: {{"line":"..."}}"""
