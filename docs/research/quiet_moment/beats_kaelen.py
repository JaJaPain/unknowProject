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
        "That one's off the board and finished. Take it or leave it, and he took it.",
        "Signed off. A public listing, open to anyone with a hull.",
        "It's done. She brokered nothing — the board did all the talking.",
        "Finished. There was nothing to arrange; it was already arranged.",
        "Wrapped up. Public work, public rate, no room to move.",
        "That's closed. Her name wasn't on it anywhere.",
        "Handled. The kind of listing that doesn't need a fixer at all.",
    ],
    "valence": """The money is small, but the money isn't really the point. Kaelen's whole trade is knowing who to
call and what a job is actually worth. On board work none of that matters — the terms were set
by somebody else before she arrived, anyone with a hull could have taken it, and she added
nothing but her presence. It's honest work that makes her redundant, and that stings more than
the rate does.

So she's dry about it rather than angry, and the joke is usually at her own expense. She is
never bitter at the Captain — taking the job was sensible and she'd have told him to.

She does not name an amount and makes no claim about whether this has happened before. She does
not say the words "thin cut" or "board work" — find her own way to say it.""",
}

BEATS = {b["id"]: b for b in (HIGH_PAY, PUBLIC_BOARD)}
