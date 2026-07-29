"""Corpus-derived allow-list validator.

Lexicon = content words of the character's own curated lines
        + closed-class function words
        + the approved fact words for THIS moment.
Anything else is, by construction, a word the character has no licence to say.
"""
import json, re
from qm import words, QUIET

STOP = set("""a an the and or but so of to in on at for with from as by into onto over under
is are was were be been being am s re ve ll d t
it its it's this that that's these those there there's here here's
we us our ours you your yours i my me mine they them their theirs he she his her
not no nor nothing none nobody nowhere never
one two three first second next last
just still only even yet again now then than too very much more most less least
what which who whom whose when where why how whether
if while because since although though unless until when
has have had do does did done will would can could shall should may might must
don't doesn't didn't won't can't cannot couldn't wouldn't shouldn't isn't aren't
wasn't weren't haven't hasn't hadn't i'm i'll i've i'd you're you'll you've
we're we'll we've they're it'll let's that'd who's
all any both each every few many some such other another same own
up down out off away back through about after before between during without within
own get got gets getting go goes going gone come comes coming came
make makes making made take takes taking took keep keeps keeping kept
put puts putting say says saying said
and/or""".split())

CURATED = {}
for ch in ("kaelen", "nova"):
    vocab = set()
    for e in QUIET:
        if e["character_id"] == ch:
            vocab.update(words(e["line"]))
    CURATED[ch] = vocab

FACTS = {
    "kaelen": set("""job payout paid pay payment modest safe safely small
                     completed complete finished done shiny captain""".split()),
    "nova": set("""hull stable stability fight fought combat over ended
                   sensor sensors pursuit pursued captain""".split()),
}


def lexicon(ch):
    return CURATED[ch] | FACTS[ch] | STOP


def outside(ch, line):
    lex = lexicon(ch)
    return sorted({w for w in words(line) if w not in lex and not w.isdigit()})


if __name__ == "__main__":
    for ch in ("kaelen", "nova"):
        print(f"{ch}: curated vocab {len(CURATED[ch])}, total lexicon {len(lexicon(ch))}")

    print("\n--- must REJECT (real failures from the research log) ---")
    bad = [
        ("kaelen", "Shiny, this job hit the modest payout sweet spot-no extra fees, no extra risk. Just honest numbers."),
        ("kaelen", "Shiny, that little bit's all the profit we get from the public board-just enough to keep the ship afloat."),
        ("kaelen", "Modest payout. Good work. You earned the coffee break."),
        ("kaelen", "Shiny's pay stub looks clean. The margin's tight-just enough to keep the coffee warm."),
        ("kaelen", "Shiny, this job's payout's just enough to cover my coffee. No extra."),
        ("nova", "Hull integrity at 98%. No pursuit detected. Ship's calm."),
        ("nova", "Hull stable. Sensors show no pursuit. Ship is breathing."),
        ("nova", "Hull integrity confirmed. Sensors show no threat vectors. Ship's stable."),
        ("nova", "Hull stable. Sensors clear. Let's reset the comms band to avoid false positives."),
        ("nova", "Hull stable. No pursuit. Systems nominal. You're safe."),
        ("nova", "Hull integrity holds. Sensors show no threat. Let's reset the navigation."),
    ]
    miss = 0
    for ch, l in bad:
        o = outside(ch, l)
        ok = "REJECT" if o else "*** MISSED ***"
        if not o:
            miss += 1
        print(f" {ok:14s} {ch:7s} {o}")
    print(f" missed: {miss}/{len(bad)}")

    print("\n--- must ACCEPT (held-out curated lines, leave-one-out) ---")
    fails = 0
    tot = 0
    for e in QUIET:
        ch = e["character_id"]
        held = set(words(e["line"]))
        others = set()
        for f in QUIET:
            if f["character_id"] == ch and f["line"] != e["line"]:
                others.update(words(f["line"]))
        lex = others | FACTS[ch] | STOP
        o = sorted({w for w in words(e["line"]) if w not in lex})
        tot += 1
        if o:
            fails += 1
            print(f"  {ch:7s} {o}  <- {e['line'][:70]}")
    print(f" leave-one-out false rejects: {fails}/{tot}")
