"""V5: keep the mercenary axis, remove the contempt.

V4 aimed the complaint at the Captain ("you got lucky, I got broke", "stop
treating negligence like a strategy", "a waste of my time"). That is cruel,
and the bible is explicit that she never becomes punitive.

Correction: the money complaint is aimed at the JOB, the RATE, and the MARKET
— never at the Captain. Underneath the accounting she is glad they came back
unhurt, and that shows in half a line, never a speech.
"""
from fewshot import WHO
from fewshot4 import PACKETS  # noqa: F401  (re-exported for the runner)

DEMOS = {
    "kaelen": [
        ("A dangerous escort job paid well above the usual rate. The Captain took damage. Everyone was paid.",
         "You came back dented. You also came back paid properly, and I have decided to concentrate on the half of that I can bank."),
        ("A short haul was completely safe. It paid very little.",
         "Nothing went wrong, which I like. I also made almost nothing, which I do not. Try not to make a habit of these, Shiny."),
        ("The cargo arrived late. The buyer accepted it anyway. A small penalty was taken.",
         "Late, and the penalty came out of my end rather than yours. I am not going to sulk about it. I am going to mention it once."),
        ("The Captain turned down a contract. Nothing was owed for declining.",
         "You said no. It cost us nothing and earned us nothing. I would still rather you refuse one than take one that eats you."),
        ("A client changed the delivery point mid-job. The Captain delivered anyway. The agreed fee was paid.",
         "They moved the target and you delivered anyway. They paid the agreed number, so I have decided to be gracious about it."),
    ],
}


def prompt(packet, ch="kaelen"):
    shown = "\n\n".join(
        f"Once, when {f[0].lower() + f[1:]} she said this.\n“{l}”"
        for f, l in DEMOS[ch]
    )
    return f"""{WHO[ch]}

She thinks about work as risk priced against pay, and she is candid about her own cut. She is
not philosophical about quiet or boredom. When a job pays her badly she says so plainly and
nudges the Captain toward the kind of work that pays better.

Her complaint is always aimed at the job, the rate, or the client — never at the Captain. She
does not call them lucky, careless, or a waste of her time. Underneath the accounting she is
glad when they come back unhurt, and that shows in half a line at most, never a speech.

You will be given the only facts that are true right now. Write one spoken line for her.

She mentions only ONE of the given facts — she is speaking, not filing a report. The rest of the
line is hers. She may nudge the Captain toward or away from this KIND of work, but she never
names a specific future job, promises one, or invents a client, an amount, another person,
another place, or an event before or after this moment. 28 words maximum.

The examples below are built differently from each other. Vary the shape.

{shown}

Now, {packet[0].lower() + packet[1:]} Write what she says. Use a different idea AND a different
sentence shape from every example above.

Return ONLY this JSON object, with exactly one key: {{"line":"..."}}"""
