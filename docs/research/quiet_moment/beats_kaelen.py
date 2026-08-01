"""Kaelen beats."""
from beat import KAELEN_WHO, KAELEN_REGISTER, KAELEN_SCOPE, make
from demo_pool_v9 import sample

# ---------------------------------------------- high pay, real danger
HIGH_PAY = {
    "id": "kaelen_high_pay_dangerous",
    "speaker": "kaelen",
    "cap": 25,
    "who": KAELEN_WHO,
    "register": KAELEN_REGISTER,
    "scope": KAELEN_SCOPE,
    "sample": sample,
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
    "register": KAELEN_REGISTER + """

This job came off the public board. Board work pays her only a thin broker's cut — she may
complain about that cut and about the board's rates, and she never pretends she took nothing.""",
    "scope": KAELEN_SCOPE,
    "sample": sample,
    "packets": [
        "The job came off the public board and it's done. The board sets the rate.",
        "Board work, finished. The posted rate is the posted rate.",
        "That one was public-board. It's closed out.",
        "Off the boards, done, and paid at whatever the board felt like paying.",
        "Public posting, completed. Standard board terms.",
        "Done. It was board work, so the rate wasn't negotiable.",
        "The board's job is finished and the board's rate applied.",
        "Closed out a posting. Board rules, board money.",
        "That was one of the open postings. Complete now.",
        "Board contract, delivered. They pay what they advertise.",
        "Finished a public listing. No negotiation on those.",
        "It's done — public board, posted terms, nothing unusual.",
    ],
    "valence": """Board work pays her a thin cut and she's dry about that; it's a standing gripe, not an outrage.
She took the cut and says so. The job itself went fine — she has no complaint about the work or
about him.

She does not name an amount. She makes no claim about whether this has happened before.""",
}

BEATS = {b["id"]: b for b in (HIGH_PAY, PUBLIC_BOARD)}
