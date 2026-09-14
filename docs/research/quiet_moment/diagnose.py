"""Local prompt diagnoser. No LLM calls, no cloud, no API cost.

Encodes the rules discovered by hand in ITERATIONS.md. Every one of them is
the same shape: the output mirrors a measurable property of its inputs, so
measure that property in BOTH and report the divergence.

Run this after any sample batch to get the diagnosis and the suggested fix,
instead of paying a reasoning model to notice it.

    from diagnose import diagnose
    diagnose(outputs, demos=[...], packets=[...], cap=25)
"""
import collections
import re

WORD = re.compile(r"[a-z0-9']+")
CONTRACTION = re.compile(r"n't|'ll|'re|'ve|'d\b|'s\b|'m\b", re.I)


def words(s):
    return WORD.findall(s.lower())


def ngrams(s, n):
    w = words(s)
    return [" ".join(w[i:i + n]) for i in range(len(w) - n + 1)]


def _pct(a, b):
    return 0.0 if not b else a / b


class Finding:
    def __init__(self, rule, severity, detail, fix):
        self.rule, self.severity, self.detail, self.fix = rule, severity, detail, fix

    def __str__(self):
        mark = {"high": "!!", "med": " !", "low": "  "}[self.severity]
        return f"{mark} [{self.rule}] {self.detail}\n     fix: {self.fix}"


# --------------------------------------------------------------- rules
def rule_length(outputs, demos, cap, out):
    over = [o for o in outputs if len(words(o)) > cap]
    if not over:
        return
    dm = sum(len(words(d)) for d in demos) / max(1, len(demos))
    out.append(Finding(
        "demo_length_sets_output_length", "high",
        f"{len(over)}/{len(outputs)} outputs exceed the {cap}-word cap; "
        f"demos average {dm:.0f} words",
        f"trim demos to <= {max(12, cap - 5)} words. Demo length, not the stated "
        f"cap, is what the model actually copies."))


def rule_register(outputs, demos, out):
    dc = _pct(sum(1 for d in demos if CONTRACTION.search(d)), len(demos))
    oc = _pct(sum(1 for o in outputs if CONTRACTION.search(o)), len(outputs))
    if dc < 0.5:
        out.append(Finding(
            "demo_register_sets_output_register", "high",
            f"only {dc:.0%} of demos use contractions (outputs: {oc:.0%})",
            "rewrite demos in spoken register with contractions. Formal demos "
            "produce written-sounding output regardless of any instruction."))


def rule_demo_leak(outputs, demos, out):
    """A phrase in one demo showing up across many outputs = templating."""
    for d in demos:
        dg = set(ngrams(d, 3))
        if not dg:
            continue
        hits = [o for o in outputs if dg & set(ngrams(o, 3))]
        if len(hits) >= max(2, 0.15 * len(outputs)):
            shared = sorted(dg & set(ngrams(hits[0], 3)))[:3]
            out.append(Finding(
                "demo_phrase_leak", "high",
                f"{len(hits)}/{len(outputs)} outputs share a phrase with one demo "
                f"{shared} -- demo: \"{d[:60]}...\"",
                "rewrite or drop that demo. A demo whose facts resemble the "
                "current moment gets templated instead of transferred."))


# Function words only: strips content, leaves grammatical skeleton. Catches a
# demo whose STRUCTURE is copied even when none of its words survive -- e.g.
# demo "X, which I like. Y, which I do not." -> outputs "X, which is good.
# Y, which is not." Literal n-grams miss this entirely.
FUNCTION = set("""a an the and or but so of to in on at for with from as by if
    then than that this these those it its is are was were be been am i my me
    you your we our us they them he she his her not no nor do does did done
    have has had will would can could should may might must let s t re ve ll d
    which who what when where why how there here just still only even yet again
    now too very much more most less least all any both each every some such
    one two first next last own same other another about after before between
    during without within up down out off away back through over under""".split())


def skeleton(s, keep=4):
    w = [x if x in FUNCTION else "_" for x in words(s)]
    return [" ".join(w[i:i + keep]) for i in range(len(w) - keep + 1)]


def rule_pattern_leak(outputs, demos, out, keep=3, min_share=0.25):
    """Structural monotony across outputs, attributed to a demo when possible.

    Looks for grammatical skeletons (content words blanked) shared by many
    outputs. Catches "X, which is good. Y, which is not." repeating even though
    no two such lines share a literal 3-gram.
    """
    counts = collections.Counter()
    for o in outputs:
        for g in set(skeleton(o, keep)):
            # keep only informative skeletons: >=2 real function words, so
            # generic frames like "_ the _" don't drown out "_ which is"
            if (keep - g.count("_")) >= 2:
                counts[g] += 1
    for gram, c in counts.most_common(8):
        if c < max(3, min_share * len(outputs)):
            continue
        source = next((d for d in demos if gram in set(skeleton(d, keep))), None)
        if source:
            out.append(Finding(
                "demo_pattern_leak", "high",
                f"{c}/{len(outputs)} outputs repeat the pattern \"{gram}\", which also "
                f"appears in a demo: \"{source[:55]}...\"",
                "rewrite that demo's construction. The model copies structure even "
                "when it changes every content word, so literal phrase checks miss it."))
        else:
            out.append(Finding(
                "structural_monotony", "med",
                f"{c}/{len(outputs)} outputs share the sentence pattern \"{gram}\" "
                f"(no demo source -- this is the model's own default)",
                "add a demo that uses a different construction, or gate on the "
                "skeleton at runtime the way openers are gated."))


def rule_auto_tics(outputs, packets, out, min_share=0.20):
    """Discover repeated phrasing without knowing it in advance."""
    packet_grams = set()
    for p in packets:
        packet_grams |= set(ngrams(p, 3))
    counts = collections.Counter()
    for o in outputs:
        for g in set(ngrams(o, 3)):
            if g not in packet_grams:
                counts[g] += 1
    for gram, c in counts.most_common(6):
        if c >= max(3, min_share * len(outputs)):
            out.append(Finding(
                "emergent_tic", "med",
                f"\"{gram}\" appears in {c}/{len(outputs)} outputs",
                "add to the runtime closer/phrase recency gate. Do NOT ban it "
                "in the prompt -- naming it raises its probability."))


def rule_opener_mirroring(outputs, packets, out):
    oo = collections.Counter(" ".join(words(o)[:2]) for o in outputs)
    distinct = _pct(len(oo), len(outputs))
    if distinct >= 0.75:
        return
    po = collections.Counter(words(p)[0] for p in packets if words(p))
    top_p, top_pc = (po.most_common(1) or [("", 0)])[0]
    detail = (f"only {len(oo)}/{len(outputs)} distinct output openers "
              f"(top: {oo.most_common(2)})")
    if _pct(top_pc, len(packets)) >= 0.4:
        out.append(Finding(
            "opener_mirroring", "high",
            detail + f"; {top_pc}/{len(packets)} packets also start with \"{top_p}\"",
            "vary packet GRAMMAR, not just vocabulary -- start packets with "
            "noun phrases, adverbs, fragments, passives. The model mirrors the "
            "packet's opening construction."))
    else:
        out.append(Finding(
            "opener_collapse", "med", detail,
            "packets are already varied, so fix this at runtime: reject "
            "candidates whose opening bigram is in the recency window. Prompt "
            "instructions have never fixed this."))


def rule_valence(outputs, valence, out):
    """valence: 'negative' | 'positive' | None"""
    if valence != "negative":
        return
    approve = re.compile(r"\b(more of (that|these|this)|do more|like to see more|"
                         r"that's a first|never seen|happy with)\b", re.I)
    hits = [o for o in outputs if approve.search(o)]
    if hits:
        out.append(Finding(
            "valence_inversion", "high",
            f"{len(hits)}/{len(outputs)} outputs approve of a negative-valence moment",
            "state the moment's valence in the prompt, and check no demo in the "
            "sampled set approves of a similar outcome. Demos carry valence."))


def diagnose(outputs, demos=(), packets=(), cap=25, valence=None, show=True):
    outputs = [o for o in outputs if o]
    found = []
    rule_length(outputs, list(demos), cap, found)
    if demos:
        rule_register(outputs, list(demos), found)
        rule_demo_leak(outputs, list(demos), found)
        rule_pattern_leak(outputs, list(demos), found)
    if packets:
        rule_auto_tics(outputs, list(packets), found)
        rule_opener_mirroring(outputs, list(packets), found)
    rule_valence(outputs, valence, found)
    if show:
        if not found:
            print("  no findings -- inputs and outputs agree on every measured property")
        for f in found:
            print(f)
    return found
