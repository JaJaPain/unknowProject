"""Kaelen beats."""
from beat import KAELEN_WHO, KAELEN_REGISTER, KAELEN_SCOPE, make
from demo_pool_v9 import sample, KAELEN as _K_DEMOS

# ---------------------------------------------- high pay, real danger
HIGH_PAY = {
    "id": "kaelen_high_pay_dangerous",
    "speaker": "kaelen",
    "cap": 25,
    "who": KAELEN_WHO,
    "register": KAELEN_REGISTER,
    "scope": KAELEN_SCOPE,
    "sample": sample,
    "demo_lines": [l for _s, _f, l in _K_DEMOS],
    "packets": [
        "The job was dangerous and it paid well. Both were paid.",
        "Hard work, and the money matched it.",
        "They shot at you out there, and the number was worth it.",
        "It paid properly. It also nearly went badly.",
        "Big payout. Real risk. Everyone got paid.",
        "That contract was ugly and generous in equal measure.",
        "Dangerous run, good rate.",
        "Risky job, and the number came in high.",
        "The money's good. So was the danger.",
        "Nasty contract, handsome fee.",
        "Serious risk on that one, and serious pay.",
        "You took a bad one and it paid like a bad one should.",
    ],
    "valence": """This one paid well, and it was genuinely dangerous. She's pleased about the money and isn't
coy about it — the danger is exactly why the number was good, and that trade is her whole
business. She's also aware he could have been hurt, and that shows in half a line at most.

She does not lecture him about the risk and does not tell him to avoid this kind of work. This
is the kind she wants MORE of. She makes no claim about whether this has happened before.

She prices his risk; she does not compliment his skill. Admiration, if any, arrives as an
observation about the money or the trade, never as a remark about how well he did.""",
}

# ---------------------------------------------- public board turn-in
PUBLIC_BOARD = {
    "id": "kaelen_public_board",
    "speaker": "kaelen",
    "cap": 25,
    "who": KAELEN_WHO,
    "register": KAELEN_REGISTER,
    "scope": KAELEN_SCOPE,
    "sample": sample,
    "demo_lines": [l for _s, _f, l in _K_DEMOS],
    "packets": [
        "It's finished. Anyone could have taken that one off the open listings.",
        "Done. Nobody negotiated anything; the rate was posted before she ever saw it.",
        "Closed out. That job was pinned on a wall where anyone could read it.",
        "Delivered. She had no hand in setting those terms.",
        "Complete. The posting paid exactly what the posting said.",
        "That one's off the board and finished. Take it or leave it were the only terms.",
        "Signed off. A public listing, open to anyone with a hull.",
        "It's done. She brokered nothing — the board did all the talking.",
        "Finished. There was nothing to arrange; it was already arranged.",
        "Wrapped up. Public work, public rate, no room to move.",
        "That's closed. Her name wasn't on it anywhere.",
        "Handled. The kind of listing that doesn't need a fixer at all.",
    ],
    "valence": """Postings like these get picked off a wall by whoever has no contacts, no leverage and nothing
better on. Badly paid, unskilled, beneath a fixer with a book of names — and beneath him too.
Both of them are slumming.

So she's snobbish, and funny about being snobbish; she knows exactly how she sounds and doesn't
care. The money's bad, but the indignity is the joke. She'd like it on record that she noticed.

Her disdain never points at the CAPTAIN. He's on her side of this — they're both too good for
it. It points at the work, at the board, and at the sort of people who need it.

She does not name an amount and makes no claim about whether this has happened before. She does
not say "thin cut" or "board work", and she does not begin by classifying the job — no "this is
the kind of job that...". She just talks.""",
}

# ---------------------------------------------- safe job, low pay
# The original beat, rebuilt on beat.py with every later lesson applied.
LOW_PAY = {
    "id": "kaelen_low_pay_safe",
    "speaker": "kaelen",
    "cap": 25,
    "who": KAELEN_WHO,
    "register": KAELEN_REGISTER,
    "scope": KAELEN_SCOPE,
    "sample": sample,
    "demo_lines": [l for _s, _f, l in _K_DEMOS],
    "packets": [
        "The job closed safely and the payout was modest. Both were paid normally.",
        "Nobody was hurt. The pay was thin. The work is finished.",
        "Quietly, without trouble, the contract completed. The money was small.",
        "Low risk from start to finish, and a rate on the low side.",
        "It went through clean. It paid little. Both parties were settled.",
        "There was never any danger. The return was slim. The task is done.",
        "Small take, no injuries, job closed.",
        "Payment landed at the low end. The assignment closed quietly.",
        "Start to finish it went smoothly, and the payment was unremarkable.",
        "Safe work for little money, and it's behind them now.",
        "Done, and nobody bled. The number was disappointing.",
        "Uneventful throughout. What it paid barely registers.",
    ],
    "valence": """Safety is cheap. That's the whole thought — nobody pays a premium for a job where nothing can
go wrong, and she knew that going in. So the small number isn't a surprise or an injustice, it's
arithmetic, and she's dry about it rather than aggrieved.

What she actually minds is that work like this doesn't move them anywhere. It keeps the lights
on and buys another week of the same. She'd rather be paid for something that mattered.

She nudges him toward better-paying work without naming a specific job. She does not lecture him
and does not suggest he did anything wrong — taking it was sensible. She prices his risk; she
does not compliment his skill.

She makes no claim about whether this has happened before.""",
}

BEATS = {b["id"]: b for b in (HIGH_PAY, PUBLIC_BOARD, LOW_PAY)}


# ---------------------------------------------- mission abandoned
ABANDONED = {
    "id": "kaelen_abandoned",
    "speaker": "kaelen",
    "cap": 25,
    "who": KAELEN_WHO,
    "register": KAELEN_REGISTER,
    "scope": KAELEN_SCOPE,
    "sample": sample,
    "demo_lines": [l for _s, _f, l in _K_DEMOS],
    "packets": [
        "The Captain walked away from the contract. It's dead, and nothing was paid.",
        "The job's abandoned. Nobody sees a credit for it.",
        "That one got dropped part-way. No payment, and the client knows.",
        "It's off. The work stopped short, and there's no money.",
        "Contract's dead in the water. Nothing earned.",
        "The Captain backed out. The work is unfinished and unpaid.",
        "Dropped, mid-job. No pay, and someone had to be told.",
        "The client's been informed it isn't happening.",
        "That work stopped and won't restart. Nothing came of it.",
        "Walked away from it. Nothing to show, nothing banked.",
        "Abandoned. No credits, and a name attached to the failure.",
        "Quit partway through. It's closed and it's empty.",
    ],
    "valence": """This one costs her, and she doesn't hide that. Not the lost fee — the fact that somebody was
told Kaelen's Captain didn't finish. Her whole trade runs on being the person whose people
deliver, and that's the thing that took the damage here.

So she states the cost plainly and without melodrama. She does not threaten him, guilt-trip him,
or demand an explanation, and she does not sulk. If there was a good reason she'd rather have it
than not, but she doesn't interrogate him for it.

She makes no claim about what happens next, doesn't name the client, and makes no claim about
whether this has happened before.""",
}

BEATS["kaelen_abandoned"] = ABANDONED


# ---------------------------------------------- mission declined
DECLINED = {
    "id": "kaelen_declined",
    "speaker": "kaelen",
    "cap": 25,
    "who": KAELEN_WHO,
    "register": KAELEN_REGISTER,
    "scope": KAELEN_SCOPE,
    "sample": sample,
    "demo_lines": [l for _s, _f, l in _K_DEMOS],
    "packets": [
        "The offer was turned down. Nothing was owed for saying no.",
        "Passed on it. No penalty, no obligation.",
        "That one got refused before it started. Costs nothing to refuse.",
        "Declined. The work goes to somebody else now.",
        "Turned away. No money changed hands in either direction.",
        "The contract was on the table and it stayed there.",
        "Said no. Nothing lost, nothing gained.",
        "Refused, and there's no penalty for refusing.",
        "That job was offered and not taken. It's someone else's problem now.",
        "Not taken. No harm done, no credits either.",
        "Left on the table. Whoever wanted it will find another hull.",
        "Rejected before anything was signed.",
    ],
    "valence": """This costs nothing and earns nothing, and she is entirely at peace with that. Saying no is a
skill, and one most people don't have — she has watched plenty of pilots take work they should
have refused.

So she's approving without being warm about it, and she'd rather he refuse ten than take one
that eats him. If there's a joke here it's about how rare it is to walk away from money without
regretting it.

She does not ask why he refused, does not second-guess him, and does not push him toward
anything specific. She makes no claim about the client or about what happens to the job now.""",
}
BEATS["kaelen_declined"] = DECLINED
