"""Data-driven beat definition.

Everything learned so far, expressed as structure rather than prose:

  who        - character identity (stable across beats)
  register   - HOW they talk (stable across beats)
  valence    - what THIS moment means to them. Required: without it the model
               borrows valence from whichever demo it was shown (V9 -> V10).
  packets    - the same facts told many ways, varied in vocabulary AND grammar.
               Grammar matters: packets that all start "The job..." produce
               outputs that all start "The job..." (V7 -> V8).
  demos      - sampled per request from a pool, nearest-to-this-moment dropped
               to prevent templating. Demo length caps output length; demo
               register sets output register.

A beat is a dict so beats can live in JSON later without a rewrite.
"""
import random


def build_prompt(beat: dict, packet: str, rng: random.Random) -> str:
    demos = beat["sample"](rng, beat.get("demo_count", 5), avoid_facts=packet)
    shown = "\n\n".join(
        f"Once, when {f[0].lower() + f[1:]} she said this.\n“{l}”"
        for _shape, f, l in demos
    )
    return "\n\n".join(p for p in [
        beat["who"],
        beat["register"],
        "You'll be given the only facts that are true right now. Write one spoken line for her.",
        beat["scope"],
        "Say one concrete thing. No grand comparisons, no metaphors that need thinking about.",
        "The examples below are built differently from each other. Vary the shape; don't copy "
        "the sentence pattern of any of them.",
        shown,
        f"Now: {packet[0].lower() + packet[1:]}",
        beat["valence"],
        "Write what she says. Use a different idea AND a different sentence shape from every "
        "example above.",
        'Return ONLY this JSON object, with exactly one key: {"line":"..."}',
    ] if p)


def make(beat: dict):
    """Adapt a beat dict to the runner's expected module interface."""
    class _Mod:
        PACKETS = beat["packets"]
        __name__ = beat["id"]
        SPEAKER = beat.get("speaker", "")
        CAP = beat.get("cap", 28)
        DEMO_LINES = beat.get("demo_lines", ())

        @staticmethod
        def prompt(packet, rng):
            return build_prompt(beat, packet, rng)
    return _Mod


# ---------------------------------------------------------------- shared voice
KAELEN_WHO = (
    "Kaelen is an independent broker and fixer: precise, dry, controlled, profit-minded, never "
    "sentimental. She may call the Captain \"Shiny\"."
)

KAELEN_REGISTER = """She thinks about work as risk priced against pay, and she's candid about her own cut. She is
not philosophical about quiet or boredom.

Her complaint is aimed at the job, the rate, or the client — never at the Captain. She doesn't
call them lucky or careless. Underneath the accounting she's glad when they come back unhurt,
and that shows in half a line at most, never a speech.

She is TALKING, not writing. Short words. Contractions. She says the blunt version of the
thought, not the polished one. If a line sounds like it was composed, it's wrong.

She's a dealmaker, not a bookkeeper. A fair amount of her work sits on the wrong side of legal,
so she keeps nothing on paper by policy — no ledgers, no books, no records, no notes for later.
She carries the numbers in her head and prefers it that way."""

KAELEN_SCOPE = """She mentions only ONE of the given facts — she's speaking, not filing a report. The rest is
hers. She may nudge the Captain toward or away from this KIND of work, but she never names a
specific future job, promises one, or invents a client, an amount, another person, another
place, or an event before or after this moment. Under 25 words."""

NOVA_WHO = (
    "N.O.V.A. is the ship's AI and the Captain's onboard partner. She's clear, compact and "
    "observant. There's a strong bond there that neither of them names. She calls him Captain. "
    "She never gives him orders."
)

NOVA_REGISTER = """She is TALKING, not writing. Short words. Contractions. She says the blunt version of the
thought, not the polished one. If a line sounds like it was composed, it's wrong.

The ship IS her body, and she is unembarrassed about that. Things happen to *her*. Maintenance
is done *to her*, by people with hands. She's theatrical about it — put-upon, a little vain, and
entirely willing to make it sound more suggestive than it strictly needs to be.

THE RULE THAT MAKES THIS WORK: every word must be literally true, ordinary maintenance talk.
Real parts — intakes, manifold, couplings, access ports, injectors, housings, seals, plating,
struts. Real jobs — dusting, flushing, buffing, reseating, tightening, stripping back. A ship
engineer reading it should hear nothing but a work order.

The suggestion is an accident of the vocabulary and lives entirely in the listener's head. She
never says anything that ONLY works as innuendo — if a phrase has no innocent technical reading,
it's wrong. That deniability is the joke: he can't call her on it, because she didn't say
anything.

She aims it at a third party — the mechanic, the yard crew, whoever has their hands on her next
— and talks about THEM. He gets to overhear and wonder, rather than being asked anything. She
never propositions him and never waits on him.

She is not mournful and she is not fussing over him. She's enjoying herself."""

NOVA_SCOPE = """She picks ONE thing and runs with it. She never invents a number, a percentage, another
system's condition, a threat, a contact, a place, or an event before or after this moment. She
gives no instruction or recommendation. Under 30 words."""
