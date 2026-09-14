"""Code-owned fact packets: same facts, rotated wording AND rotated grammar.

Two separate levers, learned the hard way:
  1. WORDING rotation killed the "Modest pay" opener attractor (1/10 -> 10/10).
  2. GRAMMAR rotation is needed too. V7's packets began "The job/work/run..."
     in 7 of 10 cases and the model mirrored that: "The job..." opened 9/20.

So every packet below starts differently: noun phrase, adverb, "nobody",
a fragment, a passive, a "there was" construction. The FACTS are identical
in all of them -- only the telling changes.
"""

# moment: kaelen / safe_low_pay_completion
SAFE_LOW_PAY = [
    "The job closed safely and the payout was modest. Both were paid normally.",
    "Nobody was hurt. The pay was thin. The work is finished.",
    "Quietly, without trouble, the contract completed. The money was small.",
    "Low risk from start to finish, and a rate on the low side. Everyone was paid.",
    "It went through clean. It paid little. Both parties were settled.",
    "There was never any danger. The return was slim. The task is done.",
    "Small take, no injuries, job closed.",
    "Payment landed at the low end. The assignment closed quietly.",
    "Start to finish it went smoothly, and the payment was unremarkable.",
    "Safe work for little money, and it is behind us now.",
    "Done, and nobody bled. The number was disappointing.",
    "Uneventful throughout. What it paid barely registers.",
]

PACKETS = SAFE_LOW_PAY
