# Quiet-Moment LLM — Independent Review and Proposal

Date: 2026-07-28
Scope: review of `docs/quiet_moment_llm_research_log.md`, the supplied example bank, the
voice bank, and the validator; plus new live experiments run against local Ollama.
Status: research findings and a proposed design. No production code was changed.

> **⚠ Read §11 first.** Sections 1–10 recommend moving the LLM offline. That recommendation was
> premature — it rested on an experiment set that never tested the fix my own §2.4 diagnosis
> pointed at. §11 corrects it with new data: **live generation works.** The §2 asset defects and
> the §8 validator bug fixes stand unchanged, with one softening noted in §2.1.
>
> **Working state and next step: `docs/research/quiet_moment/RESUME.md`.** Session paused
> 2026-07-29 mid-way through voice tuning; the current best prompt is `fewshot5.py` (V5), which
> post-dates §11.

Harness used for the new experiments: a Python replica of
`LocalModelGateway.generation_body()` — `/api/generate`, `stream:false`,
`format:"json"`, `think:false`, `num_ctx:8192`, `keep_alive:"30m"`, serial requests only.
It reproduces the Godot probe's request shape exactly, so results transfer.

---

## 1. Executive recommendation

**Stop asking the model to write the sentence that carries the fact. That is the whole bug.**

The research log frames the problem as "the model invents facts." The evidence says
something more specific and more actionable:

- Roughly half of the documented "inventions" were **supplied by the prompt itself** and are
  not inventions at all.
- Of the rest, most are **negation priming** — the ban list is the source of the banned words.
- Once you fix both of those, the model stops inventing and starts **restating**. It produces
  safe, valid, worthless lines. Deterministic validation passes them at 39/40 while a human
  rejects nearly all of them.

That last point is the ceiling. There is no deterministic validator that both admits novel
good lines and rejects novel bad ones, because the difference between *"The ledger balanced
itself for once"* (fine) and *"The board's fee is tiny"* (not fine) is semantic, not lexical.
I measured this directly: a corpus-derived allow-list rejects **11/11** of the real failures
from the log, and also false-rejects **30/30** of the project's own approved lines.

So the recommendation is:

> **Move the LLM from runtime authoring to offline authoring.** Code owns the fact clause,
> always, as curated text. A human-curated bank of *stance clauses* — written with heavy LLM
> assistance offline, using a large model — supplies the voice. At runtime, selection is
> deterministic, instant, and cannot invent anything.

This is not "give up on the LLM." It relocates it to where it measurably performs well.
`qwen3:14b` offline produced 39/40 fact-clean, genuinely varied candidates in 52 seconds
total. `qwen3:4b` live produced 0/30 usable N.O.V.A. lines.

**The variety concern is unfounded.** The player sees one line at a time. A bank of 8 fact
clauses × 20 stance clauses is 160 distinct lines for one moment — more than any player will
exhaust. Variety was never the constraint; trust was.

**And this is the part that matters for scaling to "many more of these":** stance clauses are
*not* moment-specific. Kaelen's reaction to a modest payout works for any low-reward outcome.
Author stance banks per **character × stance category** (roughly 8 categories), not per moment.
Fact clauses are the only per-moment work, and they are 6–8 short strings you write by hand in
ten minutes. That is what makes the design scale to dozens of moments instead of collapsing
under them. See §7.

---

## 2. Defects in the supplied assets

You asked me to look at these with suspicion first. Five real problems, in severity order.

### 2.1 The prompt tells Kaelen about the broker fee, then the log calls it invention

`FixedCastSoulRegistry.prompt_block()` unconditionally emits every `voice_controls` field,
including this one from `fixed_cast_souls.json`:

> `- Public-board money: Public-board work pays Kaelen only a tiny broker fee. She may complain
> about that small fee and the board rate; never claim there was no fee at all.`

Every Kaelen request in the log contained that sentence. The log then records
"invented public board" and "invented fee" as model failures in runs 2, 4, 6, 7 and in the
prefix/tail test. **The model was obeying the prompt.**

Measured, 8 runs per arm, everything else identical:

| Kaelen prompt | lines mentioning board/fee |
| --- | --- |
| soul block as shipped | **5/8** |
| identical, `public_board_money_rule` line removed | **1/8** |

This single line accounts for the largest documented Kaelen failure cluster. The rule is also
*wrong for this moment* — `safe_low_pay_completion` is not stated to be public-board work — and
`QuietMomentLineValidator` bans the very word the soul block licenses. The prompt and the
validator are in direct contradiction.

> **Softened 2026-07-29.** Do **not** delete this rule. Later voice work with the author
> established that Kaelen is mercenary and candid about her own thin cut — complaining about the
> broker fee is *characterful*, and it is the axis her best lines run on. The fix is to **gate
> the rule to public-board moments** rather than emitting it unconditionally, and to stop the
> validator banning `fee` outright. See `docs/research/quiet_moment/RESUME.md`.

### 2.2 The ban lists manufacture the failures they ban

Kaelen's prompt says *"Do not invent a payout amount, fee, coffee, drinks…"*. Coffee appears in
5/10 of the log's Kaelen lines and 2/6 of my baseline reproduction. Removing the ban list
entirely: **0/16 mentions of coffee.**

N.O.V.A.'s prompt says *"Do not invent exact damage, numbers, repairs, kills, another threat, a
secret, safety, communications…"*. The outputs contain hull percentages, threats, safety, comms.

Negative instructions inject the token into context and raise its probability. Every concrete
noun in a ban list is a suggestion. The bans must be enforced in the validator, never stated to
the model.

### 2.3 `QuietMomentLineValidator` uses substring matching, and rejects the project's own lines

`_contains_any()` uses `String.contains()`, not word boundaries. Consequences:

- `"fee"` matches **"feel"**. The curated Kaelen line *"Do not waste it by asking me how I
  feel."* is flagged `invented_personal_or_accounting_detail`.
- `"move"` matches "movement"/"removed"; `"use "` matches **"because "**; `"ready"` matches
  **"already"** — all flagged `unrequested_directive` for N.O.V.A.
- `"next"` matches the curated *"the **next** credit is not already promised"* →
  `invented_future_offer`.

Running the validator's own rules across the 30 curated Kaelen quiet lines flags **26 of 30**.
Most are `missing_modest_payout_anchor`, which is defensible since the anchor is moment-scoped —
but that fact is itself the finding in §2.4. The `fee`/`next` hits are outright bugs.

`REFERENCE_RUNS` is also stale: its four phrases come from the `turn_in` and `quiet_flight`
example sets, which are never injected into these prompts. It guards against copying text the
model never sees, while `matches_curated_line()` does the real work.

### 2.4 The 30 examples demonstrate a different task than the one being asked

This is the subtle one, and I think it is the second-biggest cause after §2.1.

All 60 quiet-moment examples are **unanchored idle observations**. Not one of them takes a
supplied fact packet and folds it into a line. But the probe asks for exactly that: "here are
three facts, state one and be dry about it."

So the model receives three demonstrations of *task A* and an instruction for *task B*. With no
demonstration of the target task, it falls back on its priors — status-report register for a
ship AI, coffee-and-fees for a broker. The reference block cannot teach a task it does not
contain.

This also explains the copying in §Experiment 2 of the log. `qwen3:8b` returned *"The numbers are
behaving. I will not praise them; they get ideas."* verbatim. When the only examples of a task
are three lines and none of them fit the request, reproducing one is the model's most reasonable
move. Copying is a symptom of exemplar/task mismatch, not defiance.

The `C(30,3) = 4,060` combination machinery in `FixedCastVoiceBank` is real and works. Its
measured effect on the failure rate is approximately zero, because the problem was never which
three examples were chosen.

Two smaller notes on the bank: `semantic_premise_tag` uses two conventions (`quiet.margin_has_room`
vs `quiet_income_has_gaps`, 15 each), and `required_context` is empty on all 60 quiet examples,
so `_requirements_match()` is a no-op on this path.

### 2.5 `num_predict: 70` silently truncates

`format:"json"` makes Ollama pretty-print. `{\n  "line": "…"\n}` plus a 28-word line exceeds 70
tokens; the JSON is cut mid-string, the inner parse fails, and the row lands as empty. I hit
this 3 times in 32 requests. It presents as `inner_json_invalid` / a blank line, which reads
like a model failure. Use ~160 for a one-line response.

---

## 3. New experiments and results

All runs serial, `qwen3:4b` unless stated. Raw transcripts are in the session scratchpad
(`qm.py`, `prompts.py`, `variants.py`, `score.py`, `fragments.py`, `offline.py`, `live_tail.py`).

### E0 — Baseline reproduction (6 per character)

Faithful. Kaelen: coffee 2/6, "no surprises"/"no chaos" 2/6. N.O.V.A.: 6/6 contained
`nominal`, `safe`, or `threat`. Mean latency 2.5s. The log's failure modes are real and stable.

### E1 — Positive-only task framing, ban list deleted (8 per character, two soul variants)

Rewrote the task as: *"Two things are true, and they are the only things you know… Sentence
one: say fact 2 in her own words. Sentence two: her dry opinion about that; it introduces no
new object, person, place, or event."* No bans, no negative examples.

- Coffee: **0/16**. Ban-list removal eliminates it outright.
- Board/fee: 5/8 → 1/8 when the soul's `public_board_money_rule` line is also dropped.
- N.O.V.A. `no threats detected` persists at ~5/8. This is **paraphrase drift**, not invention:
  the prompt says "sensors show no pursuit" and the model's prior renders that as "no threats
  detected." Same referent, unapproved word.

Conclusion: prompt structure accounts for the majority of the documented failures. It does not
account for all of them, and what remains is the interesting part.

### E2 — Corpus-derived allow-list validator (no model calls)

Built a lexicon per character = content words of that character's own 30 curated lines +
closed-class function words + the moment's approved fact words. Any word outside it is, by
construction, unlicensed.

| Test | Result |
| --- | --- |
| Reject the 11 real failure lines quoted in the research log | **11/11 rejected** |
| Accept held-out curated lines (leave-one-out over all 60) | **30/30 false-rejected** |

Perfect recall, unusable precision. 30 lines is nowhere near enough vocabulary to admit a novel
sentence. **This result generalises:** for free-prose output there is no lexical rule that
separates novel-good from novel-bad, because the distinction is semantic. A blacklist cannot
enumerate the space of possible inventions; an allowlist cannot admit the space of legitimate
sentences. Validation is a safety net, never a quality gate.

### E3 — Index selection: model chooses from curated fragments, code renders (10 per character)

Gave the model 8 curated fact clauses and 10 curated stance clauses, numbered, and asked for
`{"opener": n, "follow_up": m, "why": "…"}`.

- Invalid or out-of-range: **0/20**.
- Output safety: **20/20** — necessarily, since every token is curated.
- Latency 2.5s.
- **But**: Kaelen chose opener 5 in **10/10**; N.O.V.A. chose 6 or 7 in 9/10. Only 6 and 8
  distinct pairs out of 80 available.

The model picks well and picks the *same* thing. Code-side weighted selection with recency
suppression would give strictly more variety, in 0ms, with no Ollama dependency. **The LLM adds
essentially nothing here** — which is a genuine argument against the "let the LLM choose"
compromise, not for it.

### E4 — Offline batch authoring of stance clauses

Asked for 20 stance clauses in one call. A stance clause asserts nothing about the world — it is
attitude toward a fact the code already stated. That makes "did it invent something?"
mechanically checkable, and leaves the human curator judging only voice.

| Model | Kaelen | N.O.V.A. | Time | Character of output |
| --- | --- | --- | --- | --- |
| `qwen3:4b` | 20/21 auto-clean | **1/16** | 8s | Mode collapse. Every Kaelen line began "Modest…"; N.O.V.A. collapsed to "Hull holds. No threats detected." |
| `qwen3:14b` | 19/20 | 20/20 | 52s | Fact-clean, genuinely varied angles |

`qwen3:14b` output, unedited samples:

> *"No need for fireworks when the math checks out."* · *"Greed is a hole that never fills."*
> *"I have no notes."* → (N.O.V.A.) *"I notice I am not surprised, and that is odd."*
> *"There is a strange comfort in being unchased."*

Honest caveat: a good fraction is still generic (*"Safe is better than sorry"*, *"A job well
done is its own reward"*) or drifts lyrical for N.O.V.A. (*"a hush that feels almost
respectful"* is not a dry-systems voice). Realistic curator keep-rate: **25–35%**. That is
fine. 40 candidates per batch, ~5 minutes of review, ~12 keepers. Three batches per stance
category gets you to a shippable bank.

### E5 — Live hybrid: code owns the fact clause, 4b writes only the stance clause

This is the experiment that decides whether *any* live generation survives. It corrects both
mistakes in the log's prefix/tail test: the prefix is **not quoted verbatim** in the prompt (that
caused the echo), and there is **no ban list** (that caused the priming).

Deterministic checks alone, 20 per character:

- Auto-pass: **39/40**. Fact-clean, in length, no copying.

Then I looked at them:

> *"Hull integrity confirmed. No further action required."* — five times verbatim.
> *"The job closed safely. The payout was modest. I prefer that."* — restates the code prefix.
> *"Closed cleanly. Payout low. No drama. No risk."* — `no drama` is explicitly banned by the bible.

The model stopped inventing and started **restating**. So I added the one check that catches it —
the stance clause may not reuse the anchor's content words — and re-ran at N=30:

| Model | Kaelen non-echo survivors | N.O.V.A. non-echo survivors | Latency |
| --- | --- | --- | --- |
| `qwen3:4b` | 6/30 (20%) | **0/30** | 2.6s |
| `qwen3:14b` | 2/12 (17%) | 2/12 (17%) | 2.8s |

The larger model does **not** rescue it, so "use a bigger model" is not the answer. And the
survivors are still weak — 14b returned *"The numbers are honest. I have no quarrel with them,"*
a close paraphrase of the curated *"The numbers are behaving. I will not praise them."* Copying
persists at 14b even when the task is well-posed.

**This is the finding to carry forward.** The deterministic validator's precision on *truth* is
excellent and its power over *quality* is nil. Live generation with a small model yields
0–20% usable, and the gate that would catch the other 80% does not exist in code. Shipping this
means either showing the bad 80% or burning ~5 retries per line for a coin-flip.

---

## 4. Root causes, classified

As requested, separated by kind.

**Prompt structure (largest, fully fixable)**
- Soul block injects `public_board_money_rule` into a moment where it does not apply (§2.1).
- Ban lists prime the banned tokens (§2.2).
- Facts presented as a numbered "Facts allowed:" list read as a status-readout template; the
  model completes the template rather than speaking. This is why every N.O.V.A. line is
  telegraphic and none has a wry second beat.
- `num_predict: 70` truncates (§2.5).

**Few-shot copying (structural, not a discipline problem)**
- Examples demonstrate a different task than the request (§2.4). Copying is the rational
  response to that mismatch. "Do not quote or paraphrase" cannot fix it and did not, at 4b or 8b
  or 14b.

**Validation gaps (partly bugs, partly a hard limit)**
- Substring matching produces false positives on the project's own approved lines (§2.3).
- No echo/restatement rule — the dominant failure mode once fact invention is fixed.
- **Hard limit**: no lexical validator separates novel-good from novel-bad (§E2). Do not
  invest further here expecting quality enforcement.

**Model limitation (real, but smaller than it looks)**
- `qwen3:4b` cannot hold "comment on X without mentioning X." 0/30 for N.O.V.A.
- Mode collapse under batch generation at 4b (§E4).
- Both persist at 14b at only slightly better rates, so this is a task-shape problem more than
  a parameter-count problem.

**Unsuitable decomposition (the actual root cause)**
- A 28-word line that must be simultaneously *true*, *novel*, *in-voice*, and *non-restating* is
  a single indivisible judgment. Handing that whole judgment to a 4B model at runtime, behind a
  regex, is the design error. Everything above is downstream of it.

---

## 5. Ranked architectures

### A — Curated assembly (recommended, ship this)

**Code owns:** everything at runtime. A per-moment bank of 6–8 fact clauses and a per-character-
per-stance bank of ~20 stance clauses, all human-approved. Selection is weighted-random with
recency suppression over both halves, persisted per save.

**LLM receives:** nothing at runtime. Offline it receives the authoring brief from §E4.

**Schema:** none at runtime. The offline tool returns `{"lines": ["…"]}`.

**Voice:** preserved exactly, because every shipped token was written or approved by a human.

**Invention/copying:** impossible by construction. There is no generation step to validate.

**Validation/retry/fallback/silence:** the validator runs once, offline, in the curation tool —
as a *linter over the bank*, not a runtime gate. At runtime a missing bank means silence, which
the design already permits. No retries, no fallbacks, no failure path.

**Latency:** 0ms. Works with Ollama down. No `small_model_verified` dependency.

**Complexity:** low. One JSON bank, one selector (the existing `select_round_robin_line` is 80%
of it), one offline authoring script.

**Variety:** 8 × 20 = 160 lines per moment. With recency suppression a player will not notice
repetition inside a campaign.

**Test plan (Godot, serial):**
1. `run_quiet_moment_bank_tests.gd` — every bank entry passes the linter; every fact clause is
   ≤ 12 words; no two entries share a 5-word run; stance clauses contain no digit and no term
   from the moment's fact vocabulary.
2. `run_quiet_moment_assembly_tests.gd` — render all 160 pairings for each moment and assert
   every one passes the validator. This is the property that makes the design safe, so assert it
   exhaustively rather than sampling.
3. Recency test — 40 sequential selections produce ≥ 30 distinct lines and never repeat within 5.
4. Persistence test — used-id sets survive save/load; an unknown moment id yields silence, not
   an error.

### B — Offline generation with a curation gate (recommended, build alongside A)

This is not a competing runtime architecture; it is how bank A gets filled. Ranked second only
because it is a tool, not a feature.

**Code owns:** the authoring brief, the deterministic linter, and the curation UI (a Godot
editor tool or a plain CLI writing to the bank JSON).

**LLM receives:** the §E4 brief, at `qwen3:14b` or larger, temperature 0.9, asked for 20–40
clauses per call with an explicit *angle* list to force diversity.

**Schema:** `{"lines": ["…", …]}`.

**Voice:** the human curator is the gate. Keep-rate ~30%; anything ambiguous is dropped, because
the cost of dropping a line is zero.

**Invention/copying:** the linter auto-drops digits, fact-vocabulary leaks, over-length, and
5-word runs against the existing bank *and* against the curated examples. The curator then sees
only clean candidates and judges voice alone.

**Latency:** irrelevant — offline.

**Complexity:** low-moderate. The one piece of new work is the curation loop.

**Test plan:** golden-file test that the linter drops a known-bad fixture set (reuse the 11
failure lines from the log) and keeps a known-good fixture set.

### C — Live constrained generation with a pre-generated pool (defer)

Worth considering later, and only if A proves insufficient in playtest — which I doubt it will.

**Shape:** during loading screens and idle flight, a background job asks the model for stance
clauses for upcoming moments, runs the full deterministic gate (fact-clean, non-echo, non-copy),
and appends survivors to a *runtime* pool that is separate from the curated bank. Lines are
served from the curated bank first and the generated pool only after the curated pool is
exhausted for that moment.

**Why this shape:** it removes latency from the player's path, and it lets a 17–20% yield be
useful, because 5 background attempts over 30 seconds of loading is free.

**Why defer:** the 80% that fails is bland-but-valid, and nothing in code detects that. You
would be shipping unreviewed lines under a character's name. A critic pass does not close this —
asking the same model family to judge voice inherits the same blind spot, and the log's
Experiment 2 already shows 8b's judgment is not better than 4b's generation.

**Only make this real if** you add a player-facing or dev-facing "flag this line" control, so the
generated pool is curated by use rather than by review. That is a genuinely good design, but it
is a feature, not a fix.

**LoRA / fine-tuning:** not now. Realistic minimum is 500–1000 curated in-voice lines per
character, and you have 30. The useful reframing: **bank A is the training corpus.** Build it
for the game, and if it reaches ~800 lines per character, fine-tuning becomes a real option with
data you already needed. Do not treat it as a shortcut around curation; it is downstream of it.

**Grammars / constrained decoding:** GBNF can enforce shape but cannot enforce meaning. It would
have prevented none of the documented failures — every one of them was well-formed JSON with a
grammatical sentence inside. Not useful here.

---

## 6. Proposed next experiment

**Question:** can `qwen3:14b` offline, plus a deterministic linter, plus one human pass, produce
a shippable 20-clause stance bank in under 20 minutes of human time — and does the resulting
assembled line survive review at a rate that justifies building architecture A?

This is deliberately an experiment about the *authoring pipeline*, not about prompt tuning. The
prompt questions are settled by §3; this one is not.

### Exact prompt (Kaelen, stance category `outcome_modest_but_clean`)

```text
Kaelen is an independent broker: precise, dry, controlled, profit-minded, never sentimental.
She may call the Captain "Shiny".

The game's code has just made her say, out loud, that a job closed safely and the payout was
modest. Your job is to write the SECOND half of her line: her attitude to that.

Rules for every follow-up you write:
- It reacts only to what was already said. It reports nothing new.
- It names no amount, no client, no other job, no place, no other person, no object aboard the
  ship, and no event before or after this moment.
- It does not repeat the words: job, payout, pay, paid, modest, safe, closed, clean, quiet.
- It is one or two short sentences, 14 words or fewer.
- It works as a continuation of ANY phrasing of "the payout was modest".

Write 40 follow-ups. Make them differ in ANGLE, not just wording: acceptance, grim arithmetic,
deflected pride, warning against greed, self-mockery, professional standards, comparison to
worse outcomes, refusal to celebrate, affection disguised as business, fatigue.

Return ONLY this JSON object: {"lines": ["...", "...", ...]}
```

Settings: `qwen3:14b`, `temperature: 0.9`, `top_p: 0.95`, `num_predict: 2400`, `format: "json"`,
`think: false`. N.O.V.A. uses the parallel brief from `offline.py`, banned-repeat words
`hull, integrity, stable, holding, held, pursuit, sensors, following`.

Note the one addition versus §E4: the explicit *"does not repeat the words"* list. That is a
positive constraint on form, not a ban on subject matter, and it targets the echo failure which
was the real ceiling in §E5. It is the only prompt variable under test.

### Linter (deterministic, runs before any human sees a candidate)

Drop a candidate if any holds: contains a digit or `%`; > 16 words; contains any word from the
moment's fact vocabulary; contains any word from the character's fact-leak list
(`offline.py:FACT_LEAK`); shares a 5-word run with any curated example or any already-accepted
clause; is a duplicate after normalisation.

### Sample size

40 candidates per character per batch, 2 batches per character = **160 candidates total**.
One curator pass over the linter survivors.

### Success criteria (all four must hold)

1. Linter survival ≥ **60%** of raw candidates (≥ 96 of 160).
2. Curator keeps ≥ **20 distinct clauses per character** from those survivors.
3. Curator time ≤ **20 minutes total** for both characters.
4. Assembling all fact × stance pairings for one moment (8 × 20 = 160 lines), a curator spot-
   check of 25 randomly sampled pairings finds ≥ **23/25** acceptable to ship — i.e. the halves
   compose without needing per-pair review.

### Failure criteria (any one rejects the approach)

- Linter survival < 40% → the brief is not producing fact-free output; revisit §E4 framing
  before building anything.
- Fewer than 12 keepers per character from 80 candidates → the model cannot supply voice at
  volume, and the bank must be hand-written. Architecture A still stands; only its authoring
  cost changes.
- Spot-check < 18/25 → **this is the one that kills architecture A.** It would mean fact and
  stance clauses do not compose independently, and lines must be authored whole. Fall back to
  whole-line offline generation with per-line curation: slower to author, same runtime safety.
- Curator time > 45 minutes → does not scale to many moments; reduce to hand-authored banks of
  10 stance clauses and accept 80 lines per moment.

### What would make me reject my own recommendation

If criterion 4 fails while criteria 1–3 pass, the combinatorial-variety argument collapses and
architecture A's main advantage over plain whole-line curation disappears. I would then expect
per-moment authoring cost to roughly triple, which changes the scaling story in §7 materially
and is worth knowing before you build the selector.

---

## 7. Scaling to many moments — the part that matters most

The reason this design is worth the work is that **stance banks are reusable and fact banks are
cheap.**

Fact clauses are per-moment, but they are 6–8 short strings stating something the code already
knows. Ten minutes of hand-authoring per moment, no model involved, no risk.

Stance clauses are **per character × stance category**, not per moment. Kaelen's
`outcome_modest_but_clean` stances work for a low-paying delivery, a salvage that barely covered
fuel, a bounty that came in under quote — any moment whose emotional shape is "it worked, it
wasn't much." A first pass at the categories:

| Category | Kaelen | N.O.V.A. |
| --- | --- | --- |
| `outcome_good_low_stakes` | ✓ | ✓ |
| `outcome_good_high_stakes` | ✓ | ✓ |
| `outcome_bad_recoverable` | ✓ | ✓ |
| `outcome_bad_costly` | ✓ | ✓ |
| `waiting_nothing_happening` | ✓ | ✓ |
| `risk_ahead_acknowledged` | ✓ | ✓ |
| `player_did_well` | ✓ | ✓ |
| `player_did_something_reckless` | ✓ | ✓ |

8 categories × 2 characters × 20 clauses = **320 curated stance clauses total**, built once.
After that, each new quiet moment costs one fact bank (ten minutes) and a category tag. The
tenth moment is nearly free; the fiftieth is nearly free.

Compare with the current trajectory: per-moment prompt engineering, per-moment validator rules
(`QuietMomentLineValidator` already hardcodes `kaelen:safe_low_pay_completion` and
`nova:post_fight_stable_hull` in a `match` statement), and per-moment live failure analysis. That
cost is linear at best and it has not yet produced one shippable line.

---

## 8. File-level changes

Nothing below was applied. Ordered so that the first three are worth doing regardless of which
architecture you choose, because they are bug fixes to existing code.

### Fix now, independent of design

**`scripts/story/QuietMomentLineValidator.gd`**
- Replace `_contains_any()` substring matching with word-boundary matching over a normalised
  token list. Fixes `fee`↔`feel`, `use `↔`because `, `ready`↔`already`, `move`↔`removed`.
- Delete `REFERENCE_RUNS` — its phrases come from `turn_in`/`quiet_flight` examples that are
  never injected here. `matches_curated_line()` already covers the real case.
- Add an **echo rule**: reject when the line reuses the moment's anchor content words outside the
  code-owned fact clause. This is the check that caught what §E5 revealed and nothing currently
  catches. Handle possessives — my first cut let `hull's` through while catching `hull`.
- Add a **repeated-sentence rule**: reject when two sentences in the line normalise to the same
  string. This catches the prefix-echo the log flagged as needing a new rule.

**`scripts/story/FixedCastSoulRegistry.gd`**
- Make `prompt_block()` emit `voice_controls` fields selectively. `public_board_money_rule` must
  not appear in prompts for moments that are not public-board work. This is the §2.1 fix and it
  is the highest-value single change in the file list.

**`tests/tools/run_quiet_moment_live_probe.gd`**
- `num_predict: 70` → `160` (§2.5).
- Delete the ban-list sentences from both fixture prompts and both `_tail_prompt()` bodies;
  bans belong in the validator, never in the prompt (§2.2).
- `_obvious_flags()` is defined and never called — either wire it into the artifact rows or
  remove it.

### If you adopt architecture A

**New `data/content/fixed_cast_quiet_banks.json`** — `{moment_id: {fact: [...], stance_category:
"…"}}` plus `{character_id: {stance_category: [...]}}`. Keep it separate from
`fixed_cast_voice_examples.json`: that file is *style reference for prompts*, this one is
*shipped player-facing text*, and conflating them is how a reference line ends up on screen.

**New `scripts/story/QuietMomentAssembler.gd`** — `select(character_id, moment_id, context,
used_fact_ids, used_stance_ids) -> Dictionary`. Weighted-random with recency suppression over
both halves independently. Returns `{ok: false, reason: "no_bank"}` for silence. No LLM, no
HTTP, no async.

**`scripts/story/FixedCastVoiceBank.gd`** — leave `select_line` and `select_round_robin_line`
alone; they serve the existing curated path. Add nothing. The assembler is a sibling, not a
replacement, and `style_reference_block()` stays for the offline tool's use.

**New `tests/story/run_quiet_moment_assembler_tests.gd`** — the four cases in §5A. The
exhaustive all-pairings assertion is the important one.

**New `tests/tools/run_quiet_moment_offline_author.gd`** — the §6 batch tool. Serial, unique
`--log-file`, writes candidates plus linter verdicts to `logs/` for curation. Per the project
rule, run it alone.

### Delete or retire

`tests/tools/run_quiet_moment_live_probe.gd` should be kept as a research artifact but marked
clearly as such in its header comment — it is not on a path to production, and leaving it
looking production-adjacent invites someone to wire it up. `QuietMomentLineValidator`'s
per-moment `match` block should stop growing; if architecture A lands, per-moment rules move
into bank metadata.

---

## 9. Assumptions and decisions I need from you

**Assumptions I made** — say if any are wrong:
1. Quiet moments are genuinely optional and can be silent indefinitely. The whole design leans
   on this.
2. There is no requirement that a quiet-moment line reference *dynamic runtime values* (an
   actual credit figure, a specific system name). If some moments must, those need a separate
   template path with typed slots, and the fact bank becomes a format string. Worth knowing now.
3. `qwen3:14b` is acceptable for offline authoring on this machine. It is already pulled.
4. The 30 curated examples per character are approved shipping text, not just prompt fodder — I
   treated them as the voice ground truth throughout.

**Decisions that are genuinely yours:**

1. **Does the LLM need to be in the runtime loop at all for these lines?** My evidence says no,
   and says the compromise (§E3 index selection) adds nothing but a dependency. But this is a
   values call about what the feature is *for*, and if live generation is the point of the
   feature, architecture C with a flag-this-line control is the honest version. I would want
   that to be a deliberate choice rather than a default.

2. **Stance category taxonomy.** The eight in §7 are my first cut from reading the souls file.
   Getting these right is the highest-leverage authoring decision, because they determine reuse
   across every future moment. Worth 30 minutes with the bible open before anyone writes a clause.

3. **Curator of record.** Architecture B's keep-rate assumes one person with a consistent ear
   makes the calls. If that is you, the 20-minute budget in §6 is realistic. If it is going to be
   an LLM pass, the design does not work and we are back at §5C.

4. **What happens to `fixed_cast_voice_examples.json`.** Two options: freeze it as prompt-only
   reference, or promote the 60 quiet lines into the new stance banks (they are already approved
   text and several are stance clauses in all but name). I lean toward promoting them — it would
   give the bank a ~60-line head start — but it changes what the file means, and you have code
   reading it on both paths.

---

## 10. Direct answer to the log's open questions

1. *Abstract technique cards instead of literal examples?* Partially tested via the positive-only
   brief in §E1 and the angle list in §E4. It helps diversity and stops copying at batch scale.
   It does not fix live single-line quality (§E5). Use it offline; do not expect it to rescue
   runtime.
2. *A critic model that only classifies violations?* It would catch nothing the deterministic
   linter misses on *truth*, and it inherits the same blind spot on *quality* — the log's own
   Experiment 2 shows 8b copying a reference verbatim, which is a judgment failure, not a
   generation failure. Not worth building.
3. *Constrained structured output where code renders?* Yes — this is architecture A, and §E3
   confirms it is 100% safe. The surprise is that letting the model do the choosing adds
   nothing (10/10 identical openers). Take the constraint, drop the model.
4. *Offline generation with human curation?* **Yes. This is the recommendation.** §E4 shows the
   yield is there at 14b.
5. *Fine-tuning after a larger corpus?* Real but downstream. Build the bank first; it is both
   the product and the corpus. Revisit at ~800 lines per character.

---

## 11. CORRECTION — §1 was premature

Added after the sections above. **Read this before acting on §1 or §5.**

Sections 1–10 recommended moving the LLM offline. That recommendation was based on an
incomplete experiment set. I diagnosed in §2.4 that the few-shot examples demonstrate the wrong
task — and then never fixed that and retested. I also never tested `qwen3.6:35b-a3b`, which is
already pulled on this machine and is MoE (~3B active parameters), so it is runtime-viable.

I have now run both. The conclusion changes.

### E6 — Few-shot that demonstrates the actual task

I wrote 5 demo pairs per character, each a *fact packet → line* transform for a **different**
moment than the one under test, so copying a demo is useless to the model and detectable by us.
Same fact packet, same JSON output, no ban list, `public_board_money_rule` removed.

| Model | Kaelen fact-clean | N.O.V.A. fact-clean | Latency (warm) |
| --- | --- | --- | --- |
| `qwen3:4b` | **11/12** | **9/12** | 2.6s |
| `qwen3:8b` | 4/8 | 5/8 | 3.2s |
| `qwen3.6:35b-a3b` | **7/8** | **7/8** | 3.0s |

Compare with the log's original result for the same moment: **0/10 and 0/10.**

Across all of E6: zero coffee, zero board/fee, zero hull percentages, zero "systems nominal",
zero directives, zero copied references. **Fact invention is solved by demonstrating the
transform.** It was never primarily a model-capability problem. §2.4 was the correct diagnosis
and I failed to follow it through.

### Voice is the remaining variable, and it tracks model size

`qwen3:4b` is fact-clean but bland — it recites the fact packet in full, then appends an
interchangeable tail (*"this is the kind of clean finish we don't get often"*), and it produced
one line of outright banned generic praise (*"you've done the impossible"*).

`qwen3:8b` is worse: collapses to an *"I find it…"* formula on 6 of 8 N.O.V.A. lines.

`qwen3.6:35b-a3b` is a different tier. Unedited:

> **Kaelen** — *"I accept the modest payout because perfection is expensive and boring."*
> *"I take it, because sentiment does not cover expenses."*
> *"I dislike modesty, but I respect the promptness."*
> **N.O.V.A.** — *"The silence of the sensors suggests they are bored by how easy we were."*
> *"I have noted the peace of it, and filed it away."*

That is publishable voice at 3.0s warm, with the validator catching the residue (1/8 each:
`cut` for Kaelen, `enemy` for N.O.V.A.).

### Two prompt-format gotchas worth keeping

1. **In Ollama JSON mode, any `Label:` in the prompt becomes a JSON key.** My first few-shot
   format used `FACTS:` / `LINE:` labels; the model returned `{"facts": [...]}` and
   `{"What is true": …, "What she said": …}` instead of `{"line": …}`, and 10/12 requests
   "failed to parse." That is not a model failure — it is the prompt teaching a schema.
   Write demos as prose with no colon-labels. This likely applies to the `@@label` work in
   `OllamaTestStories/labeled_bible.py` too, in the opposite direction: there the labels are
   the point, so do **not** combine that technique with `format:"json"`.
2. The demos are the spec. The model copies their *shape* faithfully — mine all recite the
   fact in full before the wry beat, so the outputs do too. Demos where the fact is touched
   glancingly should produce lines that do the same. I have not tested this; it is the highest-
   value remaining prompt experiment.

### Revised recommendation

**Live generation is viable.** Use it. The corrected stack is:

1. `qwen3.6:35b-a3b` for these lines, if the VRAM cost is acceptable (see §12).
2. Few-shot of 5–8 curated *fact-packet → line* pairs, drawn from moments **other** than the one
   being generated, replacing the current unanchored style-reference block.
3. No ban lists in the prompt. `public_board_money_rule` gated to public-board moments only.
4. `QuietMomentLineValidator` as the safety net for the ~12% residue, with the §8 bug fixes.
5. Curated lines as the fallback when validation fails or Ollama is unavailable — and logged
   through `GenerationDiagnostics` as a failure to drive to root cause, per project rule, not
   accepted as normal operation.

**What survives from §1–§10:** the validator bug fixes (§8), the §2 asset defects, and the
finding that no lexical validator can grade *quality* (§E2) — so voice still depends on model
choice and demo quality, not on rules. What does **not** survive: the claim that runtime
generation cannot work. It can.

**What the curated bank is actually for:** it is the few-shot corpus, not the shipped output.
That is the reconciliation — curation still matters enormously, because the demos are the spec
and better demos are the main quality lever. But curated text feeds generation rather than
replacing it.

---

## 12. Revised open decisions

Replaces §9's decision 1.

1. **VRAM.** `qwen3.6:35b-a3b` is 24GB resident and would sit alongside the game's own renderer
   budget with `keep_alive: "30m"`. This is the real constraint on the revised recommendation
   and I do not know your headroom. If 24GB is not available during play, the fallbacks in
   descending order are: 35b with a short `keep_alive` and generation confined to loading/dock
   screens; or `qwen3:4b` with better demos, accepting blander voice.
2. **Sample sizes here are small** — 8–12 per arm. The fact-cleanliness deltas are large enough
   to trust (0/10 → 11/12). The voice judgment on `qwen3.6:35b-a3b` is 16 lines and it is my
   ear, not yours. Before committing, run 30 per character and read them yourself.
3. **The demo corpus is the new authoring task.** 5–8 fact-packet → line pairs per character,
   hand-written, covering varied moment shapes. That is a much smaller job than the 320-clause
   bank in §7 — and unlike that bank, it makes the model better rather than replacing it.
