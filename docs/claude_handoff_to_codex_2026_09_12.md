# Handoff: what I did NOT finish, and why

**From:** Claude, 2026-09-12, end of the A–C/D integration session.
**To:** Codex (or whoever picks this up next).
**Read with:** `plan_campaign_uniqueness_and_dialogue_quality.md` (implementation
status sections, newest last) and `whileYouWasSleeping.md` (top entry).

This document is deliberately about the GAPS. What landed is recorded in the plan
doc and the changelog; repeating it here would bury the part that matters.

---

## Ground rules I worked under, so you can tell deliberate from unfinished

Three things below are **unfinished**. Several others are **deliberately not
done**, and I want that distinction to survive the handoff, because a future
session that "fixes" a deliberate refusal would be undoing the work.

**Deliberately NOT done — do not treat these as todo items:**

- **I did not tune the critic prompt.** Your review's answer stands: the 4B
  discriminates but is not accurate enough to enforce, all eight original
  holdout cases are now burned, and further tuning against an exposed corpus
  overfits it. Semantic judging stayed diagnostic the whole session.
- **I did not loosen `missing_answer_anchor`.** It is the single largest cause
  of writer rejection (3 of 10 in the real run) and the plan already flags it as
  hostile to natural paraphrase. Loosening it would have raised my acceptance
  number from 12/24 to roughly 15/24. That is trading truth for a green figure,
  which section 11 forbids. It is recorded as measured evidence instead.
- **I did not weaken any threshold, relabel any case, or add a pass fallback.**
- **I did not touch Kaelen or N.O.V.A.** — soul, canon, voice, line banks, or
  their validators.

---

## 1. Phase E is not started. This is the biggest gap.

**Status: untouched.** My previous session labelled something "E first slice";
your review correctly called that causal-description work, not E. I did not
improve on that framing — I left E alone entirely and worked your P1/P2 list
first, because integrating what already existed seemed more valuable than
starting a new subsystem on top of unwired foundations.

Concretely, what is missing:

- **`scripts/domain/InvestigationOfferBuilder.gd` has no production caller.**
  I grepped: the only reference to it in `scripts/` is its own definition. It
  builds an `INVESTIGATE_SIGNAL` objective and nothing asks it to. `GameRoot.gd:1291`
  branches on that objective type, so there is a consumer for the *objective*,
  but nothing generates the offer.
- **No safe site placement, no discovery/scan step, no evidence commit, no
  cleanup, no save integration.** The P2 prototype is domain-shaped only.
- **No P3 pressure reducer exists.** I grepped `scripts/story` and
  `scripts/domain` for pressure handling; the hits are unrelated
  (`ChallengeBudget`, `FixedCastAttachmentLedger`). There is no reducer, no
  activity-step accounting separate from callback delivery steps, and no
  commit/restore pairing for inventory + rewards + mission state + consequences.

**Why not done:** ran out of session, not blocked. It is the correct next large
piece after item 2 below.

**One thing I did do that E depends on:** branch options now carry
`action_id`, `effect_ids` and `outcome_id` through to a committed terminal
choice (`MissionConversationController`), and eligibility is rechecked on click.
So when the reducer exists, there is a real selection to feed it. There is
still **no executor** that takes those effect IDs and applies anything.

---

## 2. Phase D joint coherence is only half done — and I have the evidence now

**Status: partially done, and the remainder is the highest-value next step.**

What I fixed: the compiler no longer *asserts* links it cannot prove. Cargo that
genuinely satisfies the recorded need earns "this is what they are short of";
arbitrary cargo gets a weaker claim that is actually supported. Delegation cites
the faction's own recorded obstacle instead of inventing "no free hull" from the
objective type. Unchecked superlatives ("the only way", "the only record") are
gone. The universal adversarial-pair rule is removed.

**What is still broken: the dimensions are still drawn independently and can
contradict each other.** You predicted this. The writer run confirmed it with a
worked example I did not have to hunt for:

> Contract paired need **"fuel it can afford"** with goal **"prove a rival's
> manifest is fiction"**. qwen3:4b dutifully produced:
> *"We need this fuel to prove the rival's manifest is fake."*

That is a compiler-supplied falsehood. Every downstream layer — the hard checks,
the packet, the critic if it were ever qualified — treats it as ground truth,
because by then it **is** the record. This is exactly your point that a critic
cannot catch an invented reason the compiler handed it.

**Why not done:** I found it at the end of the session, in the writer
measurement rather than by reasoning, and a joint-draw constraint is a real
design decision rather than a patch. I did not want to invent a compatibility
matrix at the end of a long session and leave you something half-considered.

**Suggested shape, for you to accept or replace:** constrain the draw so
`goal`, `need`, `obstacle`, `controls` and `payment_source` are chosen as a
compatible tuple rather than five independent picks — either an explicit
compatibility table, or draw `need` from the goal and `obstacle` from the need.
The variety test in `tests/persistence/run_generated_faction_desire_tests.gd`
counts distinct combinations; **it will need a companion test that counts
*coherent* ones**, because as you wrote, a large count of distinct combinations
does not measure plausibility. My current test measures exactly the wrong thing
for this property and I did not change it.

---

## 3. Writer prose is measured but not good, and I made no claim otherwise

**Status: measured once, honestly, and that is all.**

`tools/quality_eval/run_writer_eval.gd` drives the real dispatch path. Latest
run: **24 slices, 12 accepted**, latency p50 633 ms / p95 962 ms, provenance
`quality_unknown` ×12. Raw data in `logs/quality_eval/writer_eval_*.json`.

**12/24 accepted is not a quality result and must not be quoted as one.** I read
the accepted lines. They include:

- an accept-path line opening *"We don't need your help right now."*
- *"deliver to Blacklist Yard"* rendered as *"pick up the cargo from Blacklist
  Yard"*, and *"will reach Blacklist Yard before we need it"*
- the fuel/manifest incoherence above

Passing the hard checks means grounded and well-formed. It does not mean good.

**What I did NOT build:**

- **No held-out writer corpus.** The 8 contracts are 2 fixtures + 6 generated;
  there is no train/holdout split on the writer side at all. If you tune writer
  prompts, build one first — I did not, so there is nothing to overfit yet, but
  there is also nothing to validate against.
- **No blind human review structure.** Deferred per instruction; not attempted.
- **No memory measurement.** I measured latency and token counts only. The 8 GB
  target is **unmeasured** — I did not sample process RSS or combined footprint,
  and `OllamaProbe.model_footprint()` exists but is unused and only reports
  Ollama's own model accounting, which is not the combined figure anyway. Do not
  let that helper mislead you into a compliance claim.
- **No second seed.** One seed (12345). The critic runs have two; the writer run
  has one. Treat the 12/24 as a single sample.

---

## 4. Smaller gaps in the A–C work I did land

These are real, known, and small. Listing them so they are not discovered as
surprises.

- **Docking stage is not separately wired.** `QuestWorldSnapshot.check_mission()`
  supports `STAGE_DOCKING`, and acceptance + turn-in call it. Nothing calls it at
  the *docking* moment specifically — turn-in covers the delivery case, but a
  dedicated docking check (for a mission that should re-evaluate on arrival
  without a delivery) does not exist.
- **`capabilities` and `requester_funds` are never populated.** Deliberate:
  nothing live owns either as authoritative data, and faking them manufactures
  both false passes and false rejections. So the validator's capability and
  affordability checks are effectively dormant in production. A test asserts the
  keys stay absent. **When a real registry exists, this is a one-place fix** in
  `QuestWorldSnapshot.build()` and every stage gets it at once.
- **Effect IDs are still validated by prefix, not by handler.** I moved
  *objective type* validation onto the real `MissionCapabilityRegistry`
  (`has_type()`), which was your P2 point, and verified the old
  `INVESTIGATE_SITE` alias is now correctly rejected. I did **not** do the same
  for effects — `completion_effect_ids` are still checked against a prefix list
  with no executable handler behind them. That is the same class of problem, one
  layer over, and it matters more once the reducer exists.
- **`_report_contract_rejection` fires per built offer.** Withheld offers are
  logged to `GenerationDiagnostics` and removed from the board. I did not add a
  rate limit or dedupe, so a systematically broken cause will log on every board
  rebuild.
- **Fixture `capability_id` values are decorative.** They say things like
  `capability.site_scan`, which no registry knows. They pass only because the
  world snapshot never supplies a `capabilities` list, so the check abstains.
  When capabilities become real, these fixtures will need real IDs.

---

## 5. Two process notes that cost me time, so they do not cost you any

- **`git checkout` does not restore an UNTRACKED file.** Most of the new work is
  untracked (HEAD is still `f09a1915`; there is no committed boundary). I used
  `git checkout --` to undo a mutation test, it silently did nothing, and a suite
  went green against mutated code for one run. I caught it by grepping for the
  mutation marker rather than trusting the restore. Use `cp` backups.
- **A mutation check that does not fail is not a pass.** My first attempt at
  proving question-aware fact selection disabled the ranking and *nothing
  failed* — the fixture's purpose order already happened to rank the answering
  fact first. I wrote `tests/story/run_dialogue_fact_packet_tests.gd` with a fact
  deliberately buried past `MAX_FACTS`; disabling ranking now fails two
  assertions with the filler facts named.

---

## 6. Verification state, so you know what "green" currently covers

- **31 suites**, run sequentially with unique workspace log files, all
  `pass fail=0 script_errors=0`.
- **361 scripts compile**, 0 failed (`tests/parse_check_scene_scripts.gd`).
- `git diff --check` clean. `PROJECT_MAP` refreshed.
- **Mutation-checked this session:** writer packet guidance, question ranking,
  empty-roster distinction, branch intent rendering, single-path guard, the
  need/item binding requirement.
- **Real inference run:** writer only, one seed. Critic runs are yours from the
  previous session and I did not re-run or invalidate them.

**What green does NOT cover**, restating your own warning because it still
applies: none of these suites exercise E, the reducer, memory, a second seed, or
whether any line reads well.

---

## 7. If you want one thing done next

**Constrain the joint desire draw (item 2).** It is the smallest change with the
largest correctness payoff, it has a worked failing example sitting in
`logs/quality_eval/writer_eval_12345_1789255066.json`, and every later phase
inherits the falsehood if it is left in. E is bigger and more visible, but
building consequences on top of incoherent causes means the consequences are
incoherent too.

Everything I deferred in section "Ground rules" above should stay deferred
unless you have new evidence — particularly the critic. Nothing in this session
changed the conclusion that it is diagnostic only.
