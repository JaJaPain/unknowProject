"""Curated fragment banks for the assembly architecture.

Every string here is human-authored/approved. The LLM never writes text; it
only chooses indices. Worst case output = a slightly odd but safe pairing.
"""

KAELEN_SAFE_LOW_PAY = {
    # fact clause: states the approved outcome. code-owned, always true.
    "fact": [
        "Payout's modest.",
        "The payout came in on the low side.",
        "Modest pay, clean job.",
        "It paid what it said it would pay, which was not much.",
        "Small payout, no complications.",
        "The number's small and the job was quiet.",
        "We got paid. Modestly.",
        "Terms held. The payout was thin.",
    ],
    # opinion clause: attitude only, asserts nothing new about the world.
    "opinion": [
        "I have decided to be pleased about the quiet part.",
        "I will take boring and solvent over interesting and not.",
        "Nobody bled, nobody argued. I am counting that as the real payment.",
        "Do not look so betrayed. This is what most of the work looks like.",
        "I have stopped expecting the numbers to flatter us.",
        "It is not a story. It is a Tuesday that paid.",
        "Small and certain beats large and theoretical.",
        "I would celebrate, but celebrating has overheads.",
        "The margin is thin enough to read through. I still prefer it to a loss.",
        "Put it in the good column and stop squinting at it.",
    ],
}

NOVA_POST_FIGHT = {
    "fact": [
        "Hull's holding.",
        "The hull is stable.",
        "Hull integrity is holding, Captain.",
        "Structure is intact.",
        "Nothing is pursuing us.",
        "Sensors have nothing following us.",
        "The hull held, and nothing is behind us.",
        "Hull stable. Sensors are empty behind us.",
    ],
    "opinion": [
        "I am going to sit with that for a moment before I trust it.",
        "I have no notes. That is unusual enough to mention.",
        "I would like the record to show the ship did most of the work.",
        "Quiet is not the same as finished, but I will accept it for now.",
        "I have nothing to escalate. I find that agreeable.",
        "The instruments have stopped arguing with each other.",
        "You may exhale, Captain. I already have.",
        "I have logged the moment. I do not expect a matching one soon.",
        "For once I am not composing a warning.",
        "That is the outcome I would have chosen, had anyone asked me.",
    ],
}

BANK = {"kaelen": KAELEN_SAFE_LOW_PAY, "nova": NOVA_POST_FIGHT}

CONTEXT = {
    "kaelen": "The job just closed. It was safe. The payout was modest. Kaelen and the Captain both got paid normally.",
    "nova": "A hard fight just ended. The hull is stable. Sensors show no pursuit.",
}

WHO = {
    "kaelen": 'Kaelen, an independent broker: precise, dry, controlled, profit-minded. She may call the Captain "Shiny".',
    "nova": 'N.O.V.A., the ship\'s AI: clear, compact, observant, humour lands as a systems remark. She calls the Captain "Captain".',
}


def select_prompt(ch):
    b = BANK[ch]
    facts = "\n".join(f"{i}. {s}" for i, s in enumerate(b["fact"]))
    ops = "\n".join(f"{i}. {s}" for i, s in enumerate(b["opinion"]))
    return f"""You are casting one spoken line for {WHO[ch]}

Situation: {CONTEXT[ch]}

Choose the OPENER that best fits the situation:
{facts}

Choose the FOLLOW-UP that best continues that opener in her voice:
{ops}

Pick the pair that sounds most like one person speaking one thought.
Return ONLY this JSON object: {{"opener": <number>, "follow_up": <number>, "why": "<six words or fewer>"}}"""


def render(ch, opener, follow_up):
    b = BANK[ch]
    return f"{b['fact'][opener]} {b['opinion'][follow_up]}"
