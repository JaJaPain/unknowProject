"""The experiment I skipped: few-shot that demonstrates the ACTUAL task.

Every example is a FACT PACKET -> LINE pair, for a DIFFERENT moment than the
one under test. So copying an example is useless to the model and detectable
by us. This teaches the transform, which the 30 curated lines never did.
"""

DEMOS = {
    "kaelen": [
        ("The cargo arrived late. The buyer accepted it anyway. A small penalty was taken.",
         "Late, and they took it regardless. I have decided not to ask why, in case curiosity costs us the penalty twice."),
        ("The Captain turned down a contract. Nothing was owed for declining.",
         "You said no and it cost us nothing. Do you understand how rare that sentence is, Shiny?"),
        ("A repair bill was paid in full. The ship is fixed.",
         "The bill is settled and the ship is whole. Two things I do not often get to say in the same breath."),
        ("The ore sold at the standard market rate. The buyer paid on time.",
         "Standard rate, paid when promised. I keep waiting for the part where someone disappoints me."),
        ("A client changed the delivery point mid-job. The Captain delivered anyway. The agreed fee was paid.",
         "They moved the target and still paid the agreed number. I am filing that under miracles, not precedent."),
    ],
    "nova": [
        ("The gate transit completed. The ship is on the far side.",
         "Transit complete. I dislike that stretch of the process, and I dislike having no reason to."),
        ("Docking is complete. The ship is secured to the station clamps.",
         "We are secured. The clamps are holding us more firmly than I would hold most opinions."),
        ("Refuelling finished. The tanks are full.",
         "Tanks are full, Captain. I intend to enjoy the brief period before that stops being true."),
        ("A minor scrape on the plating was repaired at dock.",
         "The plating is mended. The ship has stopped mentioning it, which I take as forgiveness."),
        ("The cargo hold was emptied at the station. Nothing remains aboard.",
         "The hold is empty. It is the tidiest I have seen it, and I expect that to last an hour."),
    ],
}

TEST = {
    "kaelen": "The job closed safely. The payout was modest. The Captain and Kaelen were both paid normally.",
    "nova": "The fight is over. The hull is stable. Sensors show no pursuit.",
}

WHO = {
    "kaelen": 'Kaelen, an independent broker and fixer: precise, dry, controlled, profit-minded, never sentimental. She may call the Captain "Shiny".',
    "nova": "N.O.V.A., the ship's AI: clear, compact, observant; her humour lands as a systems remark. She calls the Captain \"Captain\". She never gives orders.",
}


NAME = {"kaelen": "Kaelen", "nova": "N.O.V.A."}


def prompt(ch, demos=None):
    demos = DEMOS[ch] if demos is None else demos
    shown = "\n\n".join(
        f"Once, when {f[0].lower() + f[1:]} she said this.\n“{l}”"
        for f, l in demos
    )
    return f"""{WHO[ch]}

You will be given the only facts that are true right now. Write one spoken line for her.

The line states one of the given facts in her own words, then adds her attitude to it. The
attitude half introduces nothing that is not in the facts: no amount, no other person, no other
place, no object, no event before or after this moment. 28 words maximum.

Here is the transform, on other moments:

{shown}

Now, {TEST[ch][0].lower() + TEST[ch][1:]} Write what she says. Use a different idea from every example above.

Return ONLY this JSON object, with exactly one key: {{"line":"..."}}"""
