# Quiet-Moment Iteration Log

One entry per experiment. **+** = keep this, **−** = don't repeat this.
Newest at the bottom. Raw outputs in the sibling `v*.json` / `batch_*.json` files.

---

## Hardware constraint (measured 2026-07-29, after repair)

`nvidia-smi`: **RTX 5060 Ti, 16311 MiB total, 1865 MiB used at idle.**

- `qwen3.6:35b-a3b` is **24GB — it does not fit in VRAM.** Its 3.0s warm timing was
  achieved while offloading to CPU/RAM on an otherwise idle machine. With the game
  rendering it will contend badly. **Treat every 35b result below as an upper bound
  on quality, not as a shippable config.**
- Candidates that actually fit alongside a running game: `qwen3:4b` (2.5GB),
  `qwen3:8b` (5.2GB), `gemma4:12b` (7.6GB), `qwen3:14b` (9.3GB — tight).
- `qwen3:14b` has **never been tested with the corrected demos**. That is the gap.

---

## V0 — original config from the research log (baseline reproduction)

Ban lists in prompt, unanchored style references, soul block emitted whole, `num_predict:70`.

**−** Kaelen: coffee 2/6. N.O.V.A.: `nominal`/`safe`/`threat` 6/6. Faithful reproduction of
the documented failure. Nothing here is worth keeping.

## V1 — correct few-shot: demonstrate *fact packet → line*

5 demo pairs per character, each from a **different** moment than the one under test, so
copying a demo is useless and detectable. No ban lists. `public_board_money_rule` removed.

**+** **The single biggest fix in the whole project.** Kaelen 0/10 (original log) → **11/12**
fact-clean on `qwen3:4b`. Zero coffee, zero board/fee, zero hull %, zero "nominal", zero
directives, zero copied references across every run.
**+** Confirms the diagnosis: fact invention was a *task-demonstration* problem, not a model
limit. The 30 curated examples demonstrate unanchored idle observations, which is a different
task from what the prompt asks for.
**−** Voice is bland at 4b: recites the full fact packet, then appends an interchangeable tail.
**−** Demos all recited the fact in full, so outputs did too. **The demos are the spec.**

## V2 — glancing fact, hard word cap ("name ONE fact, ≤7 words")

**+** Killed the recitation problem outright. 10/10 validator-clean.
**−** **Collapsed every opener to "Modest pay/payout" (10/10).** "I prefer X" in 5/10.
Over-tightening traded recitation for monotony. Do not use a hard word cap.

## V3 — varied demo *shape* (turn-first, address-first, embedded, fact-first, question)

**+** 10/10 clean, 10/10 distinct lines, structure varied *within* lines.
**−** Openers still collapsed: 9/10 began "Modest pay…". **Prompt-side diversity instructions
cannot beat a strong lexical attractor.** Stop trying to fix this in the prompt.
**−** Surfaced two validator gaps: `he/his` for the Captain (2/10, assumes player gender) and
smart-quote-wrapped returns.

## V3 + rotated fact packets ← the diversity fix

Same prompt; **code** rotates the wording of the fact packet across 10 phrasings
("the pay was thin", "the take was small", "the return was slim"…). Content identical.

**+** **Openers 1/10 → 10/10 distinct.** Biggest win after V1, costs nothing, no model
involvement. The attractor existed only because code said "modest" every single time.
**+** Produced the best lines to that point: *"Nobody bled. The accounts balanced. It is not
victory; it is merely acceptable."* / *"Slim returns require thick skins. Mine are leather-lined."*
**−** Validator false-rejected 5/10 of them: `missing_anchor` hardcodes `pay/payout/modest`, so
lines saying "money", "returns", "take" were rejected. **The anchor list must be derived from
the packet that was actually sent.**

## Best-of-N + opener-diversity gate (code-side)

Up to 3 candidates; reject on validator or on an opening bigram used in the last 6.

**+** 6/6 distinct openers, 1.9 calls/moment.
**−** Coverage fell to 60% — 4/10 moments went silent. Author has since chosen **"balanced"**:
retry 3–5, then silence, targeting ~10%. Needs N=5 and the fixed anchor rule to get there.

## V4 — Kaelen re-specced on the risk↔pay axis (author direction)

Author: *"I know this job is more dangerous, but I get paid a whole lot more for you doing it."*
/ *"I know this job is way safer, but I don't make shit from it, so don't make these a habit."*

**+** Broke the "zen broker" default the model kept reverting to ("I prefer the quiet",
"boring is profit"). That persona was never her and no constraint had shifted it.
**+** 9/10 distinct openers.
**−** **Overshot into contempt aimed at the Captain**: *"You got lucky, I got broke"*, *"Stop
treating negligence like a strategy"*, *"A waste of my time."* The bible is explicit that she is
never punitive. A mercenary axis without a warmth clause turns cruel.

## V5 — warm-mercenary Kaelen ← current best for Kaelen

Complaint aimed at the job / rate / client, **never** at the Captain. Warmth shows in half a
line, never a speech. Author: *"she isn't cold, just wants her money."*

**+** ~6/10 shippable by author review, up from ~2/10 on the zen-broker versions. The axis
change did more than every prompt constraint combined.
**+** 10/10 distinct openers. Closest to author intent: *"Clean delivery. Low fee. I'm glad
you're safe, but next time, pick jobs that pay more."*
**+** Author confirmed the *steer* ("next time, pick jobs that pay more") is canon — which means
`fixed_cast_souls.json → quiet_moment.must_not` and the validator both need updating.
**−** Residual drift: corporate-memo register (*"ensure our labor matches the remuneration"*),
sententiousness (*"Safety is cheap labor"*), and one full reversion to zen-broker with no money
complaint at all.
**−** Only 10 samples, on a model that does not fit in VRAM.

---

## Settled decisions

- **Steering is canon** for Kaelen (author's own example does it). Bible + validator must follow.
- **"today"/"tonight" are fine** — the Earth-calendar ban should not catch them.
- **Silence budget: balanced** — retry 3–5 candidates, then stay quiet. Target ~10% silent.
- **Scope: audit the codebase first**, then the author picks which moments make v1.
- `public_board_money_rule` is **characterful — gate it to public-board moments, do not delete**.

## Hard-won gotchas

- In Ollama `format:"json"`, any `Label:` in the prompt **becomes a JSON key**. Demos written
  as `FACTS:` / `LINE:` returned `{"facts": […]}`; 10/12 requests looked like parse failures.
  Write demos as prose with no colon-labels.
- `num_predict:70` truncates pretty-printed JSON around a 28-word line → silent empty rows.
- `QuietMomentLineValidator._contains_any()` is substring-based: `"fee"` matches **"feel"**,
  `"use "` matches **"because "**, `"ready"` matches **"already"**. It flags 26 of the project's
  own 30 curated Kaelen lines.
- No lexical validator can grade *quality*. A corpus allow-list caught 11/11 real failures and
  false-rejected 30/30 legitimate novel lines. Validation is a safety net; voice comes from the
  demos and the model.

---

# Post-repair session (2026-07-29)

## Model re-evaluation forced by the VRAM finding

`qwen3.6:35b-a3b` does not fit in 16GB. Re-tested the practical candidates with V5.

**−** `qwen3:14b` + V5 (fixed demos): on-axis but **formulaic** — 4/10 used
"X, which is good. Y, which is not", 5/10 distinct openers, 7.7s cold.
**+** Once warm, `qwen3:14b` runs **3.1s** and fits at 9.3GB. Viable.

## V6 — rotate the DEMO POOL (12 demos, sample 5 per request)

Same lever as packet rotation, applied to structure instead of vocabulary.

**+** First run showed "which"-hinge 4/10 → 0/10.
**−** **Over-read at n=10.** A re-run with packets cycled properly showed the hinge back at
4/10. Lesson: **n=10 is too small to call a tic fixed.** Use n=20 minimum.
**+** The re-run localized the real cause: one demo in the pool used a
"which I like / which I do not" hinge AND had the facts closest to the test packet, so the
model templated off it. **Demos that resemble the current moment invite copying rather than
transfer** — hence `sample(avoid_facts=...)`, which drops the nearest demo.

## V7 — tightened demos (all ≤20 words) + avoid_facts

**+** `too_long` 3/10 → **0/20**. **Demo length sets output length**; 9 of 12 demos had been
23–27 words against a 28-word cap.
**+** "which"-hinge → **0/20**, confirmed at n=20 after the demo rewrite.
**−** `"The job…"` opened **9/20**. New tic "next time" at 5/20.

## V8 — packets varied by GRAMMAR, not just vocabulary

V7's packets began "The job / The work / The run…" in 7 of 10 cases, and the model mirrored
the packet's opening. New packets start with noun phrases, adverbs, "Nobody", fragments,
passives, "There was".

**+** Distinct openers 10/20 → **12/20**; `"The job"` 9 → 5; "next time" 5/20 → **1/20**.
**+** 19/20 clean, 0 exact duplicates, 3.1s.
**+** Best lines to date: *"No injuries, and the coin barely covered the fuel. This kind of
work is a leaky pocket, Shiny."* / *"I'll file that under 'discretion' and forget it's there."*
/ *"I prefer it when the math at least tries to look honest."*
**−** Quality plateau: roughly **11–13/20 genuinely good**. Failures are now *muddled*, not
unsafe — bad metaphors (*"a door that only opens once"*), vagueness (*"only gets you here,
not anywhere else"*), rambling. **No lexical rule can catch these.**
**−** New emerging formula: "I'll take the X, but not the Y" in 4/20.

### Standing lesson

Every diversity win so far came from **code-side rotation of something code owns** — packet
vocabulary, packet grammar, demo selection. Every attempt to fix diversity by *instructing*
the model has failed. Assume the next collapse also has a code-side source.

## Author calibration #1 (2026-08-01) — the register was wrong

Author marked the V8 batch: rejected 7 and 9, "6 ok ish", rest "not terrible".
Both rejects were the most **writerly** lines, and both used *ledger*.

**+** **The floor is what matters, not the ceiling.** Author: *"if we keep our worst as not
terrible I think we are doing better."* Retarget: 90% at least fine, nothing embarrassing —
not 90% brilliant.
**−** My demo pool was the cause. Every demo was literary (*"There is a particular satisfaction
in a job that pays what it promised and then has the decency to end"*) and **not one contained
a contraction** — "I am", "I will", "It is". Written English, not spoken.
**−** Author follow-up: *"it's the ledger comments I don't care for. I don't see Kaelen as the
record keeping type."* Then the reason: **"her work is less than legal so she would not be the
one to keep records."** Note `fixed_cast_souls.json → kaelen.voice_controls.favored_motifs`
lists **"receipts"**, which now contradicts author intent and should be updated.

## V9 — plain, spoken, contracted demos

**+** Distinct openers 12/20 → **15/20**. 20/20 clean. `ledger` **0/20**. Contractions 16/20.
**+** Produced the first lines in the author's own register: *"Low pay for low risk. I don't
mind the risk. I mind the pay."* / *"No one bled. The number still leaves us short, Shiny."*
**−** New failure class: **logic errors**, now the dominant one.
  - *"Not worth the risk"* when the packet says there was no danger.
  - *"That's the kind I like to see more of"* — **axis inversion**, she wants the opposite.
  - *"That's a first"* — a claim about history she has no basis for.
**−** Root cause of the inversion: **demos carry valence.** The pool contains *"Do more of
that"* for a job that paid a premium, and the model transferred the approval to a low-pay
moment. Nothing in the prompt said which valence this moment has.

## V10 — state the moment's valence explicitly

Added: *"This one paid badly. She is not pleased about the money... She also does not claim it
was risky — it wasn't — and she makes no claim about whether this has happened before."*

**+** **axis_inversion 0/20, false_novelty 0/20, bookkeeping 0/20.** One short paragraph killed
all three logic failures.
**+** Distinct openers **16/20** — best so far. 20/20 clean, 3.0s.
**+** Best batch yet: *"This one didn't cost us, but it didn't pay us either. Not sure why we
did it."* / *"I don't complain about the risk, but I do about the pay."* / *"The numbers still
suck."* (that last one is the author's own bluntness landing).
**−** Two lines called a modest payout *"a loss"* — factual overstatement, not a tic. Added a
check.
**−** `risk_claim` fired 4/20 but all four were **false positives** — "No risk, no reward" is
correct. Crude regexes on a semantic property produce noise; keep them as signals, not gates.

## V11 — add the "less than legal, so no paper" angle

**+** `loss_overstatement` **0/20**, `bookkeeping` **0/20**. The illegality framing gives the
no-records trait a *reason*, which turns it from a ban into material:
*"This one paid small. No tricks, no traps. Just small."*
**−** Distinct openers fell to 12/20, *"This one"* opening **6/20**. The extra paragraph shifted
the opener distribution.

### Standing lesson, restated

I keep trying to fix opener repetition in the prompt and it keeps coming back. **Stop.** Every
diversity win came from code-side rotation, and the runtime already has the mechanism the
author approved: generate up to N, reject on an opener-bigram recency window, else stay silent.
Openers are a *runtime selection* problem, not a prompt problem.

---

## What transfers vs. what is Kaelen-only

Asked by the author 2026-08-01: *"are we learning what works with this llm in general with this
process or just what is working for this one?"* Honest classification.

### General — technique, should hold for any character, moment, or small local model

1. **Few-shot must demonstrate the actual transform** (fact packet → line), not just the target
   register. This was the single biggest fix: 0/10 → 11/12. Ordinary in-context learning.
2. **Negative instructions prime what they ban.** "Do not mention coffee" produced coffee.
3. **Demo length sets output length.** 23–27-word demos → over-length output; ≤20 → 0/20.
4. **Demo register sets output register.** Literary demos → literary output. Zero contractions
   in the demos → stiff, written-sounding lines.
5. **Demos carry valence.** A demo where she approves of a good payout leaked approval onto a
   bad payout. State the moment's valence explicitly or the model borrows the demo's.
6. **Demos too similar to the current moment invite templating** rather than transfer. Drop the
   nearest demo (`avoid_facts`).
7. **Code-side rotation beats prompt-side instruction, every time.** Packet vocabulary, packet
   grammar, demo selection. Five attempts to fix diversity by instruction all failed.
8. **In Ollama `format:"json"`, prompt labels become JSON keys.**
9. **LLM rankers prefer bland over concrete** — usable as a rejector, not a selector.
10. **No lexical validator grades quality.** Allow-list: 11/11 real failures caught, 30/30
    legitimate lines false-rejected.
11. **n=10 cannot confirm a fix.** A tic "fixed" at 0/10 returned at 4/10 on re-run. Use n≥20.

### Kaelen-only — characterization, must be redone from scratch per character

- The risk↔pay axis, warm-not-cold, dealmaker-not-bookkeeper, no paper trail because the work
  is less than legal. None of this transfers; it is what the author told me about *her*.
- The specific packets, demos, and valence paragraphs.

### Not yet proven

**The recipe has only ever been run on one character and one moment.** Whether the general list
above actually generalizes is untested. The falsification test is to apply the whole method
cold to N.O.V.A. — different character, and a different fact domain (ship systems, not money) —
and count how much transfers without rework.

## Playthrough simulation — 30 firings, freshness gates persisting

First end-to-end test of the runtime selector (structural + opener-recency + phrase-repeat +
closer-repeat gates, max 3 calls, then silence).

**+** **0 exact duplicates across 30 firings**; 17/22 distinct openers. The replay-freshness
goal looks achievable — repetition is being caught by code, not hoped away.
**+** 1.9 calls/moment at 3.0s — affordable for an async optional line.
**+** Quality holding at roughly 80% acceptable by the author's "not terrible" bar.
**−** **27% silence, against the ~10% the author chose.** Rejections: `opener_repeat` 28,
`phrase_repeat` 15, `closer_repeat` 2. The model's opener vocabulary is narrower than the
8-slot recency window can absorb.
**−** Fixes to try, cheapest first: raise `max_calls` 3 → 5; shrink `opener_window` 8 → 5;
widen the packet pool past 12. Do **not** fix this in the prompt.

---

## diagnose.py — moving refinement off expensive compute

Author's constraint (2026-08-01): iterating this way is too expensive to repeat per character
per moment. *"I can see it being VERY expensive if every call took a week's worth of my compute
to get correct."*

Almost none of the cost was generation. It was: sample → spot a pattern → **diagnose which
input caused it** → fix that input. And nearly every diagnosis had one shape:

> The output mirrors a measurable property of the demos or packets. Measure it in both,
> and the divergence names the fix.

That is computable locally with no model. `diagnose.py` encodes the rules found by hand:

| Rule | Detects | Discovered by hand in |
| --- | --- | --- |
| `demo_length_sets_output_length` | over-cap output ← long demos | V7 |
| `demo_register_sets_output_register` | stiff output ← demos with no contractions | V9 |
| `demo_phrase_leak` | literal templating off one demo | V6b |
| `demo_pattern_leak` / `structural_monotony` | repeated *grammar* via function-word skeletons | V6b |
| `emergent_tic` | repeated phrasing, no prior knowledge needed | V7/V8 |
| `opener_mirroring` | opener collapse **and whether packets caused it** | V8 |
| `valence_inversion` | approving of a negative moment | V9 |

### Validation against known answers

Re-run over historical batches where the answer was already established by hand:

**+** V5/V7: independently reported the zero-contraction demo register (the finding that needed
author calibration to spot), and `opener_mirroring` **with its cause** — *"8/10 packets also
start with 'the'"* — which had taken several manual runs to isolate.
**+** `emergent_tic` auto-discovered *"the job was"* 5/20 with no hardcoded regex.
**+** `valence_inversion` found 2/20 in V9; by hand I had only spotted 1.
**+** After tightening, `demo_pattern_leak` reports *"which is not"* 3/10 on V6b and
*"this one _"* 6/20 on V11 — both exactly the known defects.
**−** First cut was too permissive: generic frames like `"_ the _"` swamped the signal. Fixed by
requiring ≥2 real function words per skeleton.
**−** Attribution to a specific demo is imperfect — the which-hinge demo used *"which I like"*
while outputs used *"which is"*, so it reports "model default" rather than naming the demo.
Detection is reliable; blame assignment is not.

### What this means for cost

- **Rule discovery is expensive and one-time.** Rule *application* is free and local.
- The remaining irreducibly-human input is **voice direction** — "she isn't cold", "not the
  record-keeping type", "her work is less than legal". The author supplied ~4 such notes total,
  and each one applies to *every* moment for that character, not per moment.
- So the per-new-moment cost should be: write a fact packet set, run 20 samples, run
  `diagnose.py`, apply the named fixes, repeat once. No reasoning model in the loop.
- **Untested:** whether a local model can propose *new* voice direction. It cannot judge voice
  (the ranker preferred bland over concrete), so assume not.

---

# N.O.V.A. — transfer test (2026-08-01)

Purpose: apply the Kaelen recipe cold to a different character in a different fact domain, and
count how much transfers. Author voice input: strong unnamed bond, mutual survival as her
stated goal, faint jealousy about him and Kaelen, curiosity about her missing memory, gate-
travel trauma. Later additions: **dry humour**, and **subtle deniable flirtation**.

## What transferred with no rework

**+** All mechanical lessons applied first time and held: contractions 12/12 demos, all demos
≤20 words, shapes tagged, packets varied by grammar, `avoid_facts` on. Result: **20/20
structurally clean on the very first run**, 0 exact duplicates, 2.9s.
**+** `diagnose.py` worked **cold on a new character with zero changes** — instantly reported
`"i didn't expect"` 6/20, and correctly chose `opener_collapse` (packets already varied → fix at
runtime) over `opener_mirroring` (packets are the cause). The tooling generalizes.
**+** So the *engineering* transferred completely. Kaelen needed 11 iterations to reach
structural cleanliness; N.O.V.A. reached it on attempt 1.

## What did NOT transfer — and cost 5 attempts

**−** **Voice is per-character and unguessable.** My assumption ("competent and observant, warmth
restrained") was wrong. Author corrections arrived in three separate notes: she needs *dry
humour*; she's *subtly flirting*; and then the example that reframed everything:

> *"This is a really long flight, you could use this time to dust my intakes... oh never mind,
> I forgot I can have my nanobots do that."*

Three things no amount of iteration would have found:
  1. **The ship is her body** — "my intakes", "my plating". The flirtation is physical.
  2. **The joke is self-undercutting** — she opens a door, then shuts it herself with a mundane
     technical fact. The retraction is the punchline.
  3. **She's playful, not mournful.** Everything I produced was worried-about-him.

**−** **I violated my own negative-instruction rule and paid for it.** I wrote *"Do not comment
on whether he is alive, breathing, or still here"* and `"you're still breathing"` went UP to
9/20. Bans prime. This rule applies to me writing briefs, not just to the game's prompts.

**−** **My attempt-4 "fix" caused the worst regression.** Adding *"the Captain came through it
unhurt"* to the packet made survival the most salient fact, so every line reached for it.
**Adding a fact to the packet makes that fact the attractor** — a lever in both directions.

## The structural finding: register is a property of the MOMENT

Attempts 1–5 all collapsed into relief on the post-combat beat, no matter what the brief said.
Not a brief problem — the *moment* pulls that way. Someone was just shooting at them; playful
flirtation does not belong in the minute after.

Retested the same character and brief on a **long uneventful flight** (the moment the author's
own example describes):

**+** Flirtation and humour appeared immediately: *"You're not malfunctioning, are you,
Captain?"* / *"I'll count the stars if you count the seconds between them."* / *"...wondering if
you're bored enough to talk to me just for fun."*
**−** New attractor: 13/20 mention silence/quiet, `"the silence is"` 5/20. Dead air makes
"silence" the salient noun the way survival was on the combat beat.
**−** `"All systems nominal"` reappeared once — the exact failure from the original research log.
**−** Ship-as-body possessives only 5/20; the self-undercutting retraction structure is still
rare. The demos carry it but the model doesn't reliably copy it.

### Consequence for the design

**Each moment needs its own valence and register note, not just its own facts.** A character
brief alone is not portable across beats. Expect per-moment tuning of *what she's doing here*,
even when the voice is settled — which matters because the author plans many beats per
character across procedurally different campaigns.

## N.O.V.A. post-combat, corrected: damage is the hook

Author: *"you can use post combat for humor"* + the calibration example:

> *"What that ship did to my body is going to take more than one night of that local mechanic's
> hands up my manifold. Someone is going to owe me dinner first."*

**−** My "register is per-moment" conclusion was **half wrong**. Post-combat isn't inherently a
relief beat. My packets said *hull stable, Captain unhurt* — which gives her nothing to work
with, so the only salient fact was survival.
**+** Corrected rule: **a packet with no interesting hook forces the model onto the one salient
fact.** Damage is material; stability isn't. Give her something to be theatrical about.
**+** With damage packets: **18/20 distinct openers** — best in the project — 20/20 clean.

### dmg1 → dmg2: the overcorrection pattern, again

**−** dmg1 overshot exactly as Kaelen V4 did. Innuendo aimed straight at the Captain (*"I've
been waiting for hands. You're late"*), and register slid from bawdy into **visceral** —
*"peeled back my skin"*, *"cut me open"*, *"knife in my ribs"*.
**+** **This is now a confirmed pattern, not a coincidence.** Give this model a new voice axis
and it overshoots. Both times the fix was a constraint on **where it aims**, not on intensity:
Kaelen's complaint aims at the job not the Captain; N.O.V.A.'s innuendo aims at the mechanic not
the Captain. Expect to write an aim-constraint every time a new axis is introduced.
**+** dmg2: `aimed_at_captain` **0/20**.
**−** dmg2 lost the deniability instead — *"I'm not a fan of being open"*, *"I don't like my skin
disturbed"* work ONLY as innuendo, so there's nothing to hide behind.

### dmg3: the face-value rule ← current best for N.O.V.A.

Author: *"lude insinuating humor, but that could be taken at face value"* and *"double entendres
are a great way of doing it."*

Encoded as a positive requirement: **every word must be literally true, ordinary maintenance
talk.** Real parts (intakes, manifold, couplings, access ports, struts), real jobs (dusting,
flushing, buffing, reseating, stripping back). A ship engineer should hear only a work order.
Nothing that works ONLY as innuendo. The deniability *is* the joke — he can't call her on it
because she didn't say anything.

**+** `visceral` **0/20**, `aimed_at_captain` **0/20**, 17/20 distinct openers, 20/20 clean.
**+** Closest to author intent yet: *"You'll still need to scrape that burn out of my aft struts.
Not that I mind the attention."* / *"I've got a few loose panels waiting for fingers."* /
*"They'll need to strip back the plating. It's not pretty under there. You'd think I'd be more
embarrassed."*
**−** New tic: *"Who do we know with [steady/soft] hands?"* 5/20 — a demo-shaped question form
the model latched onto. Runtime `phrase_repeat` gate territory, not a prompt fix.
**−** *"There's a dent in my flank/side/stern/prow"* repeats; one broken output
(*"It's not the dent. It's not the dent."*).

### Generalizable: how to specify innuendo to a small model

Positive, mechanical, checkable — not "be subtle":
1. Every phrase must have an innocent literal reading (double entendre, not euphemism).
2. Aim it at a third party; the player overhears rather than being addressed.
3. Constrain the vocabulary to a real technical domain — the domain does the work.

## Author approval + the compounding loop

**+** 2026-08-01, author on the dmg3 batch: *"I loved every one of those. They are completely on
brand for her."* First unqualified pass in the project. Locked into `approved.py` with the
moment and packet alongside each line, plus a `REJECTED` list carrying the *reason* so the same
mistakes aren't re-derived.
**+** **Approved output is a better demo than anything I can write**, because it's on-brand by
definition. Feeding approvals back as few-shot demos is a compounding loop: each round of
approval makes the next round cheaper and more on-voice. This is the practical answer to
"how do we avoid spending a week of compute per beat" — the corpus bootstraps once a
character's voice is settled.

## British delivery: DON'T put it in the prompt

Author: *"with that british accent it will give it an even more dry feeling so it hits even
harder"* (N.O.V.A.'s TTS voice is `bf_emma`, British).

Tested a paragraph asking for dry English understatement, litotes, no emphasis.

**−** **Made it worse, and in the most instructive way available.** The new paragraph silently
**evicted the face-value rule**: outputs went back to phrases with no innocent reading
(*"how much I like being touched"*, *"I like my curves intact"*, *"I'll give it to the next
hands that touch me"*). Distinct openers also fell 17/20 → 14/20.
**+** **New general finding: prompt real estate is finite, and adding a constraint can silently
evict an earlier one.** The small model holds a limited number of simultaneous rules and the
newest tends to win. **Re-run the full check set after every prompt addition** — do not assume
an addition is free.
**+** Correct resolution: the accent is carried by the TTS voice, not by the text. `dmg3` stays
canonical. Don't spend prompt budget on delivery the voice engine already provides.

## Audio validation (2026-08-01)

Rendered approved / canon / rejected lines through the project's Kokoro server using the real
voice ids from `voice_provider_kokoro.json` (N.O.V.A. `bf_emma[0.7]+af_bella[0.3]`, Kaelen
`af_bella`). Script: `render_audio.py`; output `.tmp_godot_user/quiet_moment_audio/`.

**+** Author after listening: *"I still agree with our decisions of rejecting those and what we
approved"* and *"the approved ones all hit well."*
**+** **Text-level criteria hold up in the spoken medium.** This was a real risk — the whole
project optimised against written lines for a feature that is heard, not read. It validates
continuing to iterate on text, and means the rejection reasons in `approved.py` are sound.
**+** Cheap to repeat: `render_audio.py` pulls voice ids from the game's own config, so listening
tests can't drift from what ships.

## Beat audit — see MOMENTS.md

Surveyed the event surface for beats that could carry a quiet moment.

**+** Much of the plumbing already exists. `ShipBehaviorObserver` emits semantic events with
context and a 180s cooldown (`clean_long_transit`, `rough_arrival`, `boost_again_quickly`,
`returned_to_same_station`). `LLMInterface.gd:5282-5285` already derives `high_payout`,
`lower_payout`, `low_risk`, `known_tough` — **Kaelen's entire axis, already computed.**
`FixedCastAttachmentLedger` already models earned beats like `known_tough_completion`.
**+** The audit's organising principle is the hook rule learned from N.O.V.A.: rank candidate
beats by whether they give the model *material*, not just a trigger. "Post-combat undamaged" is
listed as a known-weak beat precisely because it was tested and failed.
**−** Two strong beats (gate transit, cold boot) are **excluded from v1** because they collide
with the scripted amnesia/flashback content in `docs/todo.md`. Generated lines there could
contradict authored story — the one failure a player would actually notice.

---

# Beat build-out session (2026-08-01)

Six beats built on `beat.py`, a data-driven definition (who / register / valence / packets /
demos) so beats can move to JSON without a rewrite. All on `qwen3:14b`, ~3.0s.

## Results

| Beat | clean | distinct openers | note |
| --- | --- | --- | --- |
| `kaelen_low_pay_safe` | 18/20 | 15/20 | rebuilt; was the original ~80% beat |
| `kaelen_high_pay_dangerous` | 19/20 | — | voice transferred across valence first try |
| `kaelen_public_board` | 20/20 | — | needed a hook rewrite (see below) |
| `nova_post_combat_damaged` | 20/20 | 18/20 | author-approved |
| `nova_repair_done` | 20/20 | 15/20 | her strongest register |
| `nova_long_transit` | 19/20 | 13/20 | canon retraction structure achieved |
| `nova_cargo_full` | 19/20 | 15/20 | anatomy slip, code-enforced |

**+ Selector tuned:** `opener_window` 8→5 with `max_calls` 5 → **12% silence** (target ~10%),
2.2 calls/moment, 17/21 distinct openers, **0 duplicates**. Task closed.

## New deterministic checks, each from an observed defect

| Check | Caught |
| --- | --- |
| `packet_echo` | line hands the packet's own words back to the player |
| `demo_echo` | output copied a demo near-verbatim (2/20 on the repair beat) |
| `wrong_address` | Kaelen saying "Captain"; N.O.V.A. saying "Shiny" |
| `generic_praise` | "you're good at that" — banned in her bible |
| `invented_number` | "45 knots", "warp six" in a space sim |

**−** Two bugs in my own checks, both worth remembering:
1. Models emit **U+2019** apostrophes; ASCII regexes silently missed `you're good at`. Normalise
   quotes before matching. This had also caused a possessive miss earlier (`hull's`).
2. `\b` written through a shell heredoc became a literal **backspace** (`\x08`), so the praise
   regex matched nothing. **Write regexes with an editor, never through a heredoc.**
3. Including "one" as a number word false-flagged 9/20 good lines ("this **one** paid small").
   Demonstratives dominate; exclude it.

## The hook rule, confirmed twice more

**−** `kaelen_public_board` first attempt collapsed hard: *"Board work. Thin cut. No complaints."*
in 14/20, **4/20 distinct openers**. Two causes — the register handed it the ready-made phrase
"thin broker's cut", and the beat had no material.
**+** Rewriting the hook fixed it completely. The interesting thing about board work for a
*fixer* isn't the money, it's that **nobody negotiated** — the terms were set before she arrived
and anyone could have taken it. It's honest work that makes her redundant. That produced the
best Kaelen lines of the session: *"I showed up, took my cut, and got in the way of someone who
could've done it better."*
**+** Same treatment lifted `kaelen_low_pay_safe`: the hook is that safe work **doesn't move
them anywhere** — *"This one didn't cost much. That's the problem — it didn't move anything."*

**Rule: when a beat produces flat output, the fault is usually the hook, not the prompt.** Ask
what this moment threatens or flatters in the character, not what happened mechanically.

## Detail rotation — a new lever

**−** When a beat needs a concrete detail the facts don't supply, the model picks one default
and repeats it: *"my struts are loose"* 5/20.
**+** Rotating the detail **in code** (`detail_pool`) took that to 0/20 and keeps the choice on
the authored side. Same family as packet rotation: anything code can own reliably, code should.

## Naming one move makes it formulaic

**−** Telling her to retract with "she has automatics for that" produced the automation
retraction in **20/20**.
**+** Listing several ways to take it back (automated / he'd make a mess of it / she'd rather
keep the fault / changes the subject / only mentioned it to see what he'd say) → **1/20**, and
much funnier: *"if you're not too busy pretending to be useful."*

## Agent confusion

**−** On the repair beat, lines credited the **Captain** with work the packet said the yard crew
did. The demos contain him doing repairs, so the role leaked.
**+** Naming who did what in the valence — "the yard crew did this, not the Captain; keep the
'you' for him and the 'they' for the crew" — took it to **0/20**.

## The anatomy slip: hand it to code

Author's canon: *"that load has me filled up to my larynx, or at least my vocal processor."*

**−** Asking the model for the two-part slip produced machine-to-machine — *"stuffed to the
bulkheads, or at least the cargo hold"* — which isn't the joke. 0/20 used a human body word.
**−** Root cause was a **constraint collision**: the face-value rule ("every word must be
ordinary maintenance talk") forbids anatomy words outright. Needed an explicit carve-out.
**+** Author's fix, and better than prompting: **if she uses a body word, code appends the
correction** (`anatomy.py`). The model only has to be natural about her body; the payoff is
guaranteed. 7/20 now carry it, reading well: *"My ribs are aching from it. My frame spars,
technically."*
**+** Three guards, each from a real failure: only corrects **her** body (first-person
possessive, so *"you can feel it in your bones"* is left alone), skips if she already corrected
herself, and skips if the machine term is already in the line (*"My cargo hold's stuffed. That
is — my cargo hold."*).

**Generalises:** for any signature verbal tic, prompt for the *setup* and let code enforce the
*payoff*. Small models are unreliable at multi-part structures and perfectly reliable as input
to a regex.

## Three more beats: abandoned, rough arrival, hard burn

**+** `kaelen_abandoned` — hook is that somebody was *told* her Captain doesn't finish, which
damages the thing her trade runs on. 11/12 clean, **12/12 distinct openers**. Best:
*"I lose the fee, but I lose the trust worse."* / *"You bailed mid-job. That's what I'm charging
for."*
**−** First attempt leaked `assumes_captain_gender` — **because my own packets said "He walked
away"**. Packet wording is prompt content; write packets in the same register you want back.
Fixed by using "the Captain" / passive.

**+** `nova_rough_arrival` — 12/12 clean, and the funniest batch of the session:
*"You're lucky I don't have a jaw to bite you with."* / *"I'll be picking bits of hull out of my
hair for weeks."* / *"I've got a spine, Captain."*
**−** First attempt blamed **"they"** (dock crew) for handling the packet attributed to *him*.
Cause: the standing "aim the innuendo at a third party" rule, which is right for every other
N.O.V.A. beat and wrong for this one. Adding "the Captain did this, so it's *you*, not *they*"
took it from 6/12 to **1/12**.
**→ A character-level rule can be wrong for a specific beat.** Check the standing rules against
each new moment rather than assuming they carry over.

**−** `nova_hard_burn` is the weakest of the nine: 7/12, "next time" tic 6/12, and several
`invented_number` flags. Some of those are false positives (the packet says "second burn", so
"two" is licensed) but "ten hours" was invented. Needs another pass.

## Session summary

Nine beats built on `beat.py`. Selector at **12% silence, 2.2 calls/moment, 0 duplicates**.
Handoff for integration: `SYSTEM.md`.

The compounding claim held up: with the mechanical lessons pre-applied, new beats reached
structural cleanliness on the **first or second run**, versus eleven iterations for the first
one. What still costs real time is finding each beat's *hook*, and that is authorial judgement
rather than engineering.

---

# Author feedback pass 2 (2026-08-02, overnight)

Feedback on the rendered audio, and what each item turned into.

## 1. "kaelen_abandoned_02 — I didn't understand one of the words"

Line: *"You bailed mid-job. That's what I'm charging for."*

**+** `bailed` is common; **`mid-job` is the suspect** — hyphenated compounds have no reliable
spoken form in Kokoro. Added a `tts_risk` screen (hyphen compounds, all-caps, symbols,
ellipses). Applied to the 55-line listening set it flagged **exactly one line: the one the
author flagged.** Beat regenerated hyphen-free; note added to `docs/tts_hygiene_notes.md`.
**−** Near-miss worth remembering: my first version combined the alternatives under one `re.I`
flag, so `[A-Z]{2,}` matched **any two letters** and flagged **55/55 good lines**.
Case-sensitive alternatives must not share an IGNORECASE flag.
**→ These lines are SPOKEN.** A construction that reads fine and renders badly is still a
defect. Screen for it.

## 2. "All the public board ones are wrong — the wrong idea was sent"

Author's read: it's **trash work beneath her and the player**. Slumming it. Too bougie for this.
Peasant work that doesn't pay well. My hook had been professional redundancy — technically true
and completely flat.

**+** Rebuilt on class snobbery. Distinct openers **3/16 → 13/16**, and the tone landed:
*"They posted the rate, stuck it on the wall, and waited for someone desperate enough to take
it. That's not work. That's a handout."* / *"Public listing. Public shame."*
**+** Author was explicit that this was **not an output problem** — the inputs were wrong. That
is the hook rule stated from the other side, and it's now the first question to ask of any flat
beat.
**−** First rebuild collapsed to *"This is the kind of job…"* **13/16** — because my own valence
prose used that frame — and one output **quoted my valence paragraph verbatim**. Added
`brief_echo`. **Never put a target line or a distinctive frame in the brief; describe the
technique instead.**

## 3. "nova_cargo_full_05 is perfect, the rest didn't do well"

The one that worked was the **understated** one, with no anatomy correction at all.

**+** Diagnosis: the corrections that failed were flat mappings — `belly → cargo hold` isn't a
joke because a hold already *is* a belly. The author's canon works because `larynx → vocal
processor` is an absurdly precise substitute. Curated `ANATOMY` down to surprising pairs only
and shortened the correction phrasings.
**+** Steered the beat to understatement: one remark with an innocent reading and a second she
leaves alone, no wink, no follow-through.
**−** Then over-corrected: the "and I don't mean the cargo bays" formula hit 8/16, because I had
**quoted the target line in the brief**. Removing it took the formula to **0/16**.

## 4. "long transit 01 and 02 are a bit insulting"

Lines: *"They don't flirt"* and *"if you're not too busy pretending to be useful."*

**+** **Third occurrence of the overcorrection pattern**, and the clearest. Kaelen V4 aimed
contempt at the Captain; N.O.V.A. dmg1 aimed innuendo at him; here the teasing implied he was
useless. Every time, the fix is an **aim-constraint**, and every time I had to be told.
**+** Added: the teasing never implies he's useless, clumsy or that a machine would do better —
she'd rather have his attention than the job done. Needling **0/16**, and warmer output:
*"I could wait for maintenance. Or I could wait for you."* / *"My intakes are clean. They've
been waiting for you to notice."*
**→ Standing rule: whenever a character gets a sharp edge, write who it points at, in the same
breath.** Assume the model will aim it at the player otherwise.

## System-level validation

First run mixing **all ten beats** with recency tracked **per character** rather than per beat —
the real case, since a character shouldn't repeat herself across different beats either.

**+** 32/32 served, **0% silence**, 1.4 calls/moment, **0 exact duplicates**, and **17/17 and
15/15 distinct openers across beats** per character.
**+** Interleaving beats **improves** coverage versus a single beat in isolation (0% vs 12%
silence): different beats naturally produce different openers, so the recency window collides
less. Single-beat silence rates are a pessimistic bound.
**−** One unusable line passed every check: *"My hips are full. The hold is full. My knees are
full. My spine is full."* Added `word_echo` (any content word 3+ times).


## Two more beats, both clean on the first run

**+** `kaelen_declined` — 14/14 clean. Hook: saying no is a skill most pilots don't have, and
she's watched plenty take work they should have refused. *"No debt. No regret. That's a skill
most don't have, Shiny."*
**+** `nova_returned_same_station` — 13/14 clean, **13/14 distinct openers**. Hook: she's happy
to go in circles as long as he's flying. *"They're still holding me. I don't mind being held —
you're the one who keeps bringing me back."* / *"You're not the first to circle back, but you're
the only one who ever did it with me."*
**+** Both reached the bar with **no iteration at all**, which is the compounding claim holding:
eleven beats in, the mechanical work is free and only the hook costs thought.

---

# Author feedback pass 3 (2026-08-02)

**+ 41 lines approved**: all Kaelen beats from the batch, plus `nova_cargo_full` and
`nova_hard_burn`. Recorded in `approved.py`.

## Code-owned lead-ins — the biggest structural change since the beat builder

Author: post-combat and rough-arrival reactions *"need extra context… without that it will sound
unwarranted, or out of place"*, e.g. **"Enemy vessel is destroyed."** then the reaction.

**+** Implemented as `lead_in_pool` — authored lines, rotated like packets, prepended in code.
The model is told the lead-in has already been said and must carry on rather than restate it.
Both beats went to **9/10 and 10/10 clean** and read far better situated:
*"Hostile is down. They got me on the left flank. My best side. I'll have words with the
schedule."* / *"We made it. Just. You've got a bruise on my stern. Nobody else was close enough
to do that."*
**+** This **converges on the fact-clause + reaction split** from the original architecture work
— reached independently from the author's ear rather than from analysis, which is decent
evidence it's the right shape.
**−** Two new defects, both caught and fixed: the model repeated a short lead-in verbatim
(*"They're finished. They're finished."* — a 4-word run check misses two-word lead-ins, so
opening words are now compared directly), and "Captain" appeared in both halves
(`double_address`).

## Firing probability

**+** Author: hard burn *"should only play about 25% of the time the player hits the boost or it
will become too redundant."* Added `fire_probability` to the beat definition. **A beat's quality
and its firing rate are separate problems** — a good line on too common a trigger still wears
out.

## Long transit, reworked to spec

Author's spec: a lead-in like *"This is a very long flight. Since you got time you could…"*, then
the pullback, **with a `. . .` pause between them in the TTS**; *"sexy and playful, not bitter or
angry… she just wants his attention, not to complain for real."* Plus: rare time alone with him;
rotate devices; longer and meandering; memory gap allowed as vague unease only.

**+** Restructured into **three parts, two of them code-owned**: authored lead-in + model
`offer` + authored `. . .` pause + model `pullback`. Asking for two named JSON fields guarantees
both halves exist and puts the pause exactly where the author wants it — in prose the model
merged them or dropped the retraction entirely.
**+** 8-9/10 clean, and the register arrived: *"You'd need to get in there, fingers first. Maybe
a little pressure. Just to see what's sticking. . . . No need to linger."* / *"Intakes need
dusting. You could do it. I wasn't going to mention it. . . . Forget it. I was just testing."*
**−** `rng.choice` over the detail pool repeated "collar" 4/10 in a single run — **sampling with
replacement is not rotation**. Switched to a shuffled bag. Same bug class as the packet-sampling
error back in V6.
**−** Pullbacks drifted self-pitying (*"You've got better things to do"*, *"Someone else can
handle it. Probably better."*). Added: the pullback is a wink, never sad — she's releasing him
because she's enjoying the upper hand, not because she doesn't matter. Improved but not fully
solved; **this is the open item on transit.**
**−** The authored `. . .` collides with the `tts_ellipsis` check, so the two halves are checked
separately, before joining. Model-produced ellipses are still caught.

## Rough arrival: "she isn't bitter"

Two author corrections in quick succession, and the second was the important one.

**−** *"'Down and stopped' is not what I would say"* — planetary-landing language for a station
dock. **Two lead-ins and five packets** used ground vocabulary ("put her down hard", "rough
set-down", "she's parked"). Replaced with docking terms (clamps, berthed, alongside, on the
arm). **Packet wording is prompt content**, so a domain error there leaks straight into speech.
**→ Check authored text against the physical situation, not just the character.**

**−** Then, on listening to the rest: *"she isn't bitter. Nova is almost in love with the player.
She will complain loudly but she isn't bitter like these suggest."* Reading them back, the
outputs were keeping score: *"I'm still holding a grudge"*, *"I've got witnesses"*, *"You'll pay
me back in polish"*, *"a pilot with your reflexes would know better"*.
**→ This is a DIFFERENT failure from the earlier overcorrections.** Those aimed contempt at the
player; this one is genuine grievance. **Loud is not the same as bitter** — she can be as loud
as she likes provided it's a performance rather than a complaint.
**+** Rewrote the valence around that: an enormous fuss made for fun and for his attention, no
grudge, no score, no demand for apology or compensation, never a suggestion he flew badly.
Stated test for the model: *she should sound like she's fishing for him to make a fuss back.*
**+** Bitterness markers **0/12**, and the note landed: *"I'm going to complain about the clamps
until I'm blue in the face. You'll enjoy it, I promise."* / *"My struts are twisted, but I'll
wait for you to notice before I mention it."*
**−** `lead_in_echo` fired 2/12 — the model still sometimes opens by repeating the lead-in. The
runtime gate catches it, at the cost of a retry.

### Standing note

For a character defined by affection, **specify the emotional temperature of a complaint, not
just its target.** Kaelen needed "aim it at the job, not the Captain". N.O.V.A. needed that too
— and separately needed "this is a performance, not a grievance". Volume, target and sincerity
are three different dials.
