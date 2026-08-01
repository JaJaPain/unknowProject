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
