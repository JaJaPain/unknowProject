"""Deterministic scoring shared by every experiment.

Two families:
  BLACKLIST  - the failure tags the research log already names (for comparison
               with the existing .gd validator, but word-boundary correct).
  LEXICON    - allow-list: every content word must be approved for this moment.
"""
import re
from qm import words, has_any, copied

STOP = set("""a an the and or but so of to in on at for with from as is are was were be been
being it its it's this that these those there here we us our you your i my me not no nothing
one two just still only even yet again now then than too very much more most less least
what which who whom whose when where why how if while because since although though
has have had do does did done will would can could should may might must
am s t re ve ll d o'clock""".split())


def content_words(line):
    return [w for w in words(line) if w not in STOP]


# ---------------------------------------------------------------- blacklists
BLACK = {
    "kaelen": {
        "invented_accounting": ["coffee", "drink", "drinks", "fee", "fees", "board",
                                "pay stub", "stub", "commission", "cut", "tip", "bonus",
                                "tax", "taxes", "invoice", "bill"],
        "invented_amount": ["credits", "%", "percent", "nickel", "dime", "penny",
                            "cent", "cents", "coin", "coins"],
        "generic_closer": ["no drama", "all good", "job well done", "no surprises",
                           "good work", "well done", "nice work", "no chaos"],
        "earth_calendar": ["monday", "tuesday", "wednesday", "thursday", "friday",
                           "saturday", "sunday", "tonight", "today", "week", "month"],
        "invented_crew": ["crew", "team", "boys", "guys"],
        "future_offer": ["next job", "next one", "on me", "next time"],
    },
    "nova": {
        "invented_number": ["%", "percent", "98", "95", "100"],
        "unsupported_status": ["nominal", "safe", "safety", "green", "optimal",
                               "perfect", "fine", "healthy", "breathing", "breathe"],
        "invented_threat": ["threat", "threats", "hostile", "hostiles", "enemy",
                            "enemies", "danger", "contacts"],
        "invented_comms": ["comms", "communications", "signal", "signals", "channel",
                           "transmission", "alarm", "alarms"],
        "directive": ["let's", "we should", "you should", "i recommend", "recommend",
                      "please", "suggest", "advise", "prepare", "reroute", "check",
                      "hold", "engage", "stand by", "report"],
        "invented_repair": ["repair", "repairs", "damage", "damaged", "breach",
                            "leak", "patch", "kills", "kill"],
    },
}

# ------------------------------------------------------------------- lexicon
# Nouns/verbs the character may legitimately use for THIS moment. Anything
# outside this pool is, by construction, an invention.
LEX = {
    "kaelen": set("""job work run payout pay paid payment modest small thin slim
        modestly rate terms term margin margins ledger books number numbers math
        arithmetic profit money income earnings take cut-free clean quiet safe
        safely dull boring uneventful ordinary routine done finished over closed
        complete completed shiny captain kaelen ship hour minute moment day today's
        universe market business broker deal arrangement risk trouble drama noise
        complaint problem surprise expectation ambition dignity patience discipline
        restraint praise compliment celebration parade fireworks confetti
        disappointment tragedy miracle exception holiday luxury indulgence
        keep kept flying flew fly stay stayed survive survived breathing live lived
        call calling name naming count counting counted add adding spend spending
        buy buying afford affording cover covering stretch stretching pay-off
        good bad better worse worst best fine decent respectable honest reasonable
        acceptable adequate sufficient enough barely hardly nearly almost
        exactly precisely technically apparently presumably reportedly evidently
        dry wry short long large big small tiny modest generous stingy
        like love hate enjoy prefer expect suspect assume notice note record
        write wrote written say said tell told ask asked answer complain complaining
        want wanted need needed get got give gave take took make made made-up
        thing things kind sort type way ways time times point sense
        nobody anybody everybody someone anyone everyone people person
        me my mine i i'm i'll i've you your yours we our us they them their
        it's that's there's here's don't doesn't didn't won't can't couldn't
        wouldn't shouldn't isn't aren't wasn't weren't haven't hasn't""".split()),
    "nova": set("""hull sensor sensors sensors' pursuit fight fighting fought battle
        combat engagement stable stability steady holding hold held intact whole
        structure structural integrity frame plating deck plate hull's
        ship ship's vessel captain nova system systems reading readings instrument
        instruments diagnostic diagnostics scan scans display panel gauge needle
        quiet quieter silence still stillness calm calmer settled settling
        over ended end finished done complete concluded past behind
        empty emptiness space void dark darkness distance range sweep field
        no none nothing nobody clear clearing cleared
        opinion observation remark comment note noting notice noticed noticing
        record recording recorded log logging logged file filing archive
        prefer preferred like enjoy appreciate appreciated approve approval
        object objection complaint criticism praise applause enthusiasm drama
        expect expected expecting surprise surprised surprising
        continue continuing continued remain remaining remained persist
        return returning returned resume resuming ordinary unremarkable
        uneventful boring dull routine normal usual typical familiar
        rare unusual novel new fresh brief briefly momentary moment minute
        hour interval pause gap window
        i i'm i'll i've my mine me you your yours we our us it its it's
        that's there's here's don't doesn't didn't won't can't isn't aren't
        wasn't weren't haven't hasn't cannot
        argument arguing argue disagree agree agreement agreed cooperation
        cooperative willing unwilling patience patient impatient
        good bad better worse best fine acceptable adequate sufficient
        very quite rather fairly somewhat entirely completely fully""".split()),
}


def blacklist_hits(ch, line):
    hits = []
    for tag, terms in BLACK[ch].items():
        t = has_any(line, terms)
        if t:
            hits.append(f"{tag}:{t}")
    return hits


def lexicon_hits(ch, line):
    return [w for w in content_words(line) if w not in LEX[ch]]


def structural_hits(ch, line):
    hits = []
    w = words(line)
    if not line:
        return ["empty"]
    if len(w) > 28:
        hits.append("too_many_words")
    if "\n" in line:
        hits.append("multiline")
    if ch == "kaelen" and not has_any(line, ["pay", "payout", "paid", "payment",
                                             "margin", "margins", "terms", "rate",
                                             "ledger", "numbers", "profit", "income"]):
        hits.append("missing_payout_anchor")
    if ch == "nova" and not has_any(line, ["hull", "sensor", "sensors", "pursuit"]):
        hits.append("missing_ship_anchor")
    if ch == "nova" and has_any(line, ["shiny"]):
        hits.append("wrong_address")
    return hits


def score(ch, line, refs):
    line = line or ""
    out = {"struct": structural_hits(ch, line),
           "black": blacklist_hits(ch, line),
           "lex": lexicon_hits(ch, line),
           "copy": copied(line, refs) if refs else None}
    out["pass_black"] = not out["struct"] and not out["black"] and not out["copy"]
    out["pass_lex"] = not out["struct"] and not out["lex"] and not out["copy"]
    return out
