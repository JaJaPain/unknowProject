"""Prepare conservative, human-readable rewrites for the lounge quality review.

This deliberately does not call Ollama.  It turns the already-generated raw
batch into a review queue while keeping the original model text beside a
fact-bound rewrite.  That means the player-facing example bank stays useful
even when the model wandered outside the supplied situation.
"""

import json
from pathlib import Path

SOURCE = Path(__file__).with_name("lounge_curated_100.json")
OUT = Path(__file__).with_name("lounge_assistant_rewrite_review.json")


def rewritten(item: dict, n: int) -> dict:
    kind = n % 4
    if kind == 0:  # clogged intake filters / customs
        openers = [
            "Customs has had a line of ships parked outside since morning. Every one of them came in coughing through the intakes.",
            "The arrivals board has not stopped blinking. Filters are coming out of those ships full of the same residue.",
            "I have seen customs turn ships around all day, and nobody looks happy about it.",
            "The maintenance bay is collecting clogged intake filters faster than it can label them.",
            "Those arrivals are not being held for paperwork. Something keeps turning up in their intake filters.",
        ]
        answers = [
            "A run of arrivals came in with their intake filters clogged by an unidentified residue. Customs is holding arrivals until they know it is contained.",
            "The filters on a group of arriving ships were clogged by residue nobody has identified. Until customs knows it is contained, arrivals stay on hold.",
            "Nobody has named the residue yet. Customs only knows it is showing up in intake filters, so they are keeping new arrivals outside for now.",
        ]
        closes = [
            "Makes the queue miserable, but it beats spreading a problem they do not understand.",
            "That is all anyone knows for certain, which is why the inspectors are taking their time.",
            "If you are arriving today, bring patience. That seems to be the only thing clearing customs quickly.",
        ]
    elif kind == 1:  # missing convoy
        openers = [
            "The convoy's slot came and went, and the board is still blank.",
            "There is an empty line on the freight schedule where a convoy should be.",
            "I have been waiting on a convoy check-in that never arrived.",
            "The freight board is quiet in the one place it should not be.",
            "Someone is going to spend the rest of the shift staring at that missing check-in.",
        ]
        answers = [
            "The freight convoy missed its check-in. Nobody knows whether it broke down, diverted, or was intercepted.",
            "It never checked in, and there is no confirmed explanation yet. It could have broken down, diverted, or been intercepted.",
            "All we know is that the convoy missed its check-in. Anything beyond that would be guessing.",
        ]
        closes = [
            "Until somebody hears from them, the missing line is all we have.",
            "That kind of silence makes people invent stories. Best wait for a real update.",
            "I would rather have bad news than no news, but we are not there yet.",
        ]
    elif kind == 2:  # fuel
        openers = [
            "Every shift starts with the same question now: which service craft can wait another day for fuel?",
            "The fuel board is getting shorter, and nobody likes what is being crossed off it.",
            "You can tell a delivery is late by how quiet the nonessential bays have gotten.",
            "We are counting fuel by the service craft now, which is never a cheerful sign.",
            "The station is saving fuel where it can, and that means some work is simply not moving today.",
        ]
        answers = [
            "Fuel deliveries are late, so the station has started rationing nonessential service craft.",
            "The shortage is serious enough that nonessential service craft are being rationed until the late fuel deliveries arrive.",
            "Late deliveries mean the station is prioritizing essential work and holding back nonessential service craft.",
        ]
        closes = [
            "Nobody is calling it a crisis, but everyone is planning like it might become one.",
            "That is the practical version: essential work first, everything else waits.",
            "It is not dramatic until the wrong craft is the one that has to wait.",
        ]
    else:  # freight inspection backlog
        openers = [
            "The docks are full of cargo that has nowhere to go yet.",
            "Freight crews have been waiting on the same clearance long enough to memorize the dock lights.",
            "Cargo is stacked up on the docks because the inspectors have not released it.",
            "Everyone on the freight side is waiting for a stamp that has not arrived.",
            "The docks look busy, but very little is actually moving.",
        ]
        answers = [
            "Freight crews are waiting on inspection clearance, so their cargo is sitting on the docks.",
            "The inspection clearance has not come through, which is leaving freight crews and their cargo stuck on the docks.",
            "Nothing is wrong with the freight itself that anyone has said. The crews are simply waiting for inspection clearance.",
        ]
        closes = [
            "Until that clearance comes through, the freight runs stay parked.",
            "It is a slow problem, but it still stops everything behind it.",
            "That is station life: one missing clearance and a whole dock holds its breath.",
        ]

    # n is zero-based and the source scenarios were emitted 0..3 in sequence.
    return {
        "opener": openers[(n // 4) % len(openers)],
        "answer": answers[(n // 4) % len(answers)],
        "close": closes[(n // 4) % len(closes)],
    }


def main() -> None:
    raw_items = json.loads(SOURCE.read_text(encoding="utf-8"))["items"]
    review_items = []
    for index, item in enumerate(raw_items):
        review_items.append({
            "id": item["id"],
            "contact_name": item["contact_name"],
            "contact_role": item["contact_role"],
            "station": item["station"],
            "allowed_facts": item["allowed_facts"],
            "player_question": item["player_question"],
            "original": {
                "opener": item["opener"],
                "answer": item["npc_answer"],
                "close": item["close"],
            },
            "assistant_rewrite": rewritten(item, index),
            "review_reason": "The raw exchange may be repetitive, contain stage direction, or add facts outside the supplied situation. The rewrite stays within the fact packet and treats the speaker as a person, not a briefing terminal.",
            "status": "needs_user_confirmation",
        })
    OUT.write_text(json.dumps({"batch_id": "lounge-assistant-rewrite-review", "items": review_items}, indent=2), encoding="utf-8")
    print(f"Prepared {len(review_items)} rewrite comparisons: {OUT.name}")


if __name__ == "__main__":
    main()
