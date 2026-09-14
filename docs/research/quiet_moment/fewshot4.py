"""V4: Kaelen re-specced on the risk<->pay axis, per author direction.

The model kept producing a zen broker ("I prefer the quiet", "boring is
profit"). That is not her. She is mercenary and specific about HER cut, and
she steers the Captain toward work that pays her better.

Author's reference for the voice:
  "I know this job is more dangerous, but I get paid a whole lot more for you
   doing it."
  "I know this job is way safer, but I don't make shit from it, so don't make
   these a habit."

Constraint change: she MAY steer toward or away from a KIND of work. She may
not name a specific future job, promise one, or invent a client.
"""
from fewshot import WHO

DEMOS = {
    "kaelen": [
        # her cut named, risk priced in
        ("A dangerous escort job paid well above the usual rate. The Captain took damage. Everyone was paid.",
         "You came back dented and I came back paid properly. I would take that trade again, and I suspect so would you."),
        # safe + low pay -> steer away from the KIND of work
        ("A short haul was completely safe. It paid very little.",
         "Nothing went wrong and I made almost nothing. Do not make a habit of these, Shiny. I have overheads."),
        # penalty out of her end
        ("The cargo arrived late. The buyer accepted it anyway. A small penalty was taken.",
         "Late, and the penalty came out of my end rather than yours. I am choosing to mention that exactly once."),
        # declining costs nothing and earns nothing
        ("The Captain turned down a contract. Nothing was owed for declining.",
         "You said no. It cost us nothing and it earned us nothing, which leaves me perfectly neutral. Enjoy it."),
        # they misbehaved but paid the agreed number
        ("A client changed the delivery point mid-job. The Captain delivered anyway. The agreed fee was paid.",
         "They moved the target and still paid the agreed number. That is the only reason I am not billing them for my patience."),
    ],
}

PACKETS = [
    "The job closed safely. The payout was modest. Both were paid normally.",
    "The work is finished. Nobody was hurt. The pay was thin.",
    "The contract is complete. It was low-risk. The money was small.",
    "The run ended without trouble. The rate was on the low side. Everyone was paid.",
    "The delivery went through clean. It paid little. Both parties were settled.",
    "The task is done and was never dangerous. The return was slim.",
    "No one got hurt. The job is closed. The take was small.",
    "The assignment closed quietly. The fee paid out at the low end.",
    "It went smoothly start to finish. The payment was unremarkable.",
    "The job is behind us. It was safe work for little money.",
]


def prompt(packet, ch="kaelen"):
    shown = "\n\n".join(
        f"Once, when {f[0].lower() + f[1:]} she said this.\n“{l}”"
        for f, l in DEMOS[ch]
    )
    return f"""{WHO[ch]}

She thinks about work as risk priced against pay, and she is candid about her own cut. She is
not philosophical about quiet or boredom. When work pays her badly she says so and steers the
Captain toward the kind of job that pays better; when it pays well she admits the risk was worth
it to her.

You will be given the only facts that are true right now. Write one spoken line for her.

She mentions only ONE of the given facts — she is speaking, not filing a report. The rest of the
line is hers. She may push the Captain toward or away from this KIND of work, but she never
names a specific future job, promises one, or invents a client, an amount, another person,
another place, or an event before or after this moment. 28 words maximum.

The examples below are built differently from each other. Some open with the fact, some with her
thought, some with the Captain's name. Vary the shape.

{shown}

Now, {packet[0].lower() + packet[1:]} Write what she says. Use a different idea AND a different
sentence shape from every example above.

Return ONLY this JSON object, with exactly one key: {{"line":"..."}}"""
