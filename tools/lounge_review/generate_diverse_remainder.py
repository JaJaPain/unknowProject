"""Generate a varied second set of lounge exchanges, one Ollama call at a time."""

import json
import sys
from pathlib import Path

from generate_batch import generate, review

OUT = Path(__file__).with_name("lounge_diverse_remainder.json")

# The first ten fact packets are the ten stories used for the 10-by-10 batch.
# Each packet is deliberately narrow.  It gives the model something
# concrete to answer without inviting it to invent a new solar system, crisis,
# or named NPC just to make a scene feel busy.
SCENARIOS = [
    ("Rook Danner", "Dockhand", "A cargo lift has been reserved for emergency medical supplies, delaying ordinary loading.", "Why is nothing moving on Dock Three?"),
    ("Sana Rell", "Bartender", "A visiting survey crew has occupied the quiet end of the lounge and refuses to say what it found.", "What is with the survey crew?"),
    ("Jenna Kross", "Mechanic", "Several ships need replacement maneuvering thruster seals after a bad batch reached the station.", "Why is the maintenance bay packed?"),
    ("Ivet Marr", "Cargo Inspector", "Two cargo tags have been assigned to the same container, and inspectors are reconciling the records.", "Why are the inspectors arguing over that crate?"),
    ("Marek Vale", "Dockworker", "A tug pilot called in sick, leaving one scheduled ship without a docking escort.", "Why is that freighter waiting outside?"),
    ("Lio Sable", "Comms Tech", "The station's public comms relay is working, but private-channel traffic is delayed while a relay array is serviced.", "Why are private messages taking so long?"),
    ("Tamsin Roe", "Freight Runner", "A buyer rejected a delivery because the cargo seal did not match the manifest, so the crew must return it.", "Why is that crew unloading the same cargo again?"),
    ("Perrin Holt", "Cook", "The galley received no fresh produce shipment, so tonight's menu is limited to stored food.", "Why is everyone complaining about dinner?"),
    ("Vera Nix", "Salvager", "A salvager sold a useful part cheaply without checking its value, and the lounge is teasing her about it.", "What happened with that sale?"),
    ("Olan Pike", "Station Guard", "Visitors must use the marked corridor because a deckhand is repairing a damaged handrail nearby.", "Why is that corridor closed?"),
    ("Kess Marrow", "Hauler Captain", "A small asteroid shifted close to a common shipping lane, so freighters are taking a longer route around it.", "Why are arrivals taking the long way in?"),
    ("Dessa Vorn", "Miner", "The miners have stopped taking new claims because their claim registrar has not processed the last group.", "Why are the miners not taking new work?"),
    ("Bram Edd", "Repair Apprentice", "A repair crew is tracing an intermittent power flicker affecting only the station's laundry machines.", "What is with the lights flickering in the service hall?"),
    ("Nara Quill", "Courier", "A courier is waiting for a passenger who missed a connection, leaving a small package undelivered.", "Why is that courier still here?"),
    ("Sana Rell", "Bartender", "A regular lost a harmless wager and must wear a bright station-jacket for one shift.", "Why is that regular dressed like that?"),
    ("Jenna Kross", "Mechanic", "A ship's diagnostic system keeps reporting a fault that technicians cannot reproduce in the bay.", "Why is that ship still in diagnostics?"),
    ("Ivet Marr", "Cargo Inspector", "A passenger brought three different versions of the same travel permit, so inspection is verifying which is valid.", "Why is that passenger being held at the desk?"),
    ("Marek Vale", "Dockworker", "The station is hosting a routine fire drill, and crews are practicing a faster evacuation route.", "Why are all the alarms going off?"),
    ("Rook Danner", "Dockhand", "A crate of glassware arrived with a cracked outer case, so workers are moving it by hand.", "Why are they carrying that crate instead of using a loader?"),
    ("Lio Sable", "Comms Tech", "A local broadcast loop is repeating yesterday's weather bulletin until its scheduled reset.", "Why does the station announcement keep repeating?"),
    ("Tamsin Roe", "Freight Runner", "A crew is waiting for a replacement meal heater before beginning a long freight shift.", "Why has that crew not departed yet?"),
    ("Perrin Holt", "Cook", "A kitchen supply crate was delivered to the wrong deck, so the cook is waiting for it to be rerouted.", "Why is the galley closed this morning?"),
    ("Vera Nix", "Salvager", "A salvage crew found a perfectly intact chair in wreckage and cannot agree who gets to keep it.", "Why is everyone arguing over a chair?"),
    ("Olan Pike", "Station Guard", "The guard is redirecting visitors because an automated floor scrubber is stuck in the main entryway.", "Why is the entrance blocked?"),
]


def main() -> None:
    target = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    items = json.loads(OUT.read_text(encoding="utf-8")).get("items", []) if OUT.exists() else []
    for index in range(len(items), target):
        name, role, facts, question = SCENARIOS[index % 10]
        record = {
            "id": f"diverse-{index + 1:03d}", "contact_name": name,
            "contact_role": role, "station": "Greywake Station",
            "allowed_facts": facts, "player_question": question,
        }
        try:
            text = generate(name, role, facts, question, 20000 + index)
            verdict, reasons = review(text, question)
            record.update({"opener": text.get("opener", ""), "npc_answer": text.get("answer", ""), "close": text.get("close", ""), "screen_verdict": verdict, "screen_reasons": reasons})
        except Exception as error:
            record.update({"opener": "", "npc_answer": "", "close": "", "screen_verdict": "needs_human", "screen_reasons": [str(error)]})
        items.append(record)
        OUT.write_text(json.dumps({"batch_id": "lounge-diverse-remainder", "items": items}, indent=2), encoding="utf-8")
        print(f"checkpoint {len(items)}/{target}", flush=True)
    print(f"Done: {len(items)} varied exchanges", flush=True)


if __name__ == "__main__":
    main()
