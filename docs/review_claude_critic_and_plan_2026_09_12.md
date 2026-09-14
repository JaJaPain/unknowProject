# Review: critic failure and Claude's implementation

2026-09-12, Codex. Review and isolated experiments only; no production gameplay
changes. Read alongside `problem_critic_always_passes.md` and
`plan_campaign_uniqueness_and_dialogue_quality.md`.

## Conclusion

The constant-pass critic is reproducible. The prompt tells the model to return
an already completed pass answer. However, removing that example alone did not
solve the problem in my experiment. A smaller, evidence-oriented task produces
discrimination on the SAME qwen3:4b model with thinking disabled. That disproves
the narrow claim that this model cannot discriminate at all; it does not establish
that it is accurate enough to enforce publication.

Keep the critic out of the enforcing runtime path for now. Repair the facts and
integration boundaries first, then calibrate separate factual-support and relevance
checks. Naturalness should remain a measured editorial concern, not an uncalibrated
word-overlap veto on plain speech.

Claude made useful progress and correctly stopped to measure the critic. His
implementation is broadly in the intended direction, but A-C are only partially
integrated, D is a broader deterministic foundation, and the work labeled “E first
slice” is still causal-description work rather than playable P2/P3 consequences.

## What I measured

Local Ollama reported version 0.34.0. Tests used qwen3:4b, think=false,
temperature=0.15, num_ctx=8192, seed=12345. No larger model or cloud inference.
Standalone requests isolate prompt/format behavior; they are not measurements of
the live worker or game frame performance. Experiments were sequential.

| Experiment | Result |
|---|---|
| Original prompt, supplied good/bad repro pair, 90-token budget | Both return the same completed pass JSON |
| Remove completed example, explicitly map failures to repair, same pair | Both still pass |
| Evidence-first JSON, same pair, 220-token budget | Invented survivors caught, but the good line falsely rejected |
| Same evidence prompt with a real JSON schema in `format` | Same classifications as generic JSON mode |
| Plain-text evidence then final label, same pair, 220-token budget | Both hit length limit before final classification; unusable, not passes |
| Claim-list schema plus relevance, 20 tuning cases, 450-token budget | 11/11 repair-labeled cases rejected, but 5/9 pass-labeled cases falsely rejected |
| Code-split sentence support checks plus separate relevance, same 20 tuning cases, 120 tokens/call | 8/11 repair-labeled cases rejected; 2/9 pass-labeled cases falsely rejected; all four awkward-but-true tuning cases pass |

The last method intentionally excludes style. Its three misses are two robotic
but factually supported recitations and an invented deadline. Factual support
alone correctly cannot distinguish the two recitations from truthful speech.
The two false rejections come from the relevance subcheck. Sentence-level factual
classification alone passed all nine good-labeled cases, but this is a tiny,
reused tuning set and is not a release claim. Aggregate accuracy would conceal
these important distinctions.

The claim-list version sometimes classified SOURCE facts rather than the target
line, fabricated claims, and contradicted its own evidence. Valid JSON did not
mean valid review. Splitting the target outside the model reduced that error.
The simple regex splitter in this experiment is NOT production-ready (abbreviations,
multiple clauses, quoted dialogue and compound claims need proper handling).

No held-out cases were submitted in my experiments. The original run already
reported holdout results; keep those separate and add a fresh holdout before final
qualification after future tuning. Do not describe the tuning results above as
independent evaluation.

Local reproducible artifacts:

- `.tmp_godot_user/critic_ablation.py` and `critic_ablation_results.json`
- `.tmp_godot_user/critic_claim_probe.py` and `critic_claim_probe_results.json`
- `.tmp_godot_user/critic_sentence_probe.py` and `critic_sentence_probe_results.json`
- `.tmp_godot_user/critic_audit.gd` and `critic_tuning_cases.json`

These workspace scratch artifacts retain exact requests and responses, independently
of Claude's existing baseline at `logs/quality_eval/critic_eval.json`. Preserve that
baseline. Move useful experiment code into the maintained harness before relying on
it in ongoing development.

## Answers to the problem brief

1. **Recoverable on 4B?** Nonconstant discrimination is demonstrated above. A
   production-quality all-purpose critic is not. Use narrow tasks with code-selected
   targets, then qualify each subcheck independently. Do not replace pass-everything
   with repair-everything.
2. **Is JSON mode the cause?** It is not established as the cause. Generic JSON
   mode guarantees structure, not semantic correctness or a mandated first key.
   Evidence-json and schema-json behaved similarly on the pair; free text exhausted
   its budget. Keep structured output while improving the actual task.
3. **Does evidence before verdict help?** It can, and changed behavior here, but
   evidence can itself be copied or fabricated. The model processes the prompt
   before producing output; verdict-first does not literally stop it from seeing
   the criteria. Evidence-first gives intermediate generated context, not proof.
4. **Separate criteria?** Yes as the next measured direction. Separate factual
   support from relevance; invoke relevance only for an actual question. Do not
   conflate an awkward sentence with a false statement. Budget calls by target
   count, not an assumption that all quests need four reviews.
5. **Few-shot?** An untested next experiment, not a demonstrated fix. If attempted,
   use balanced examples on the tuning split, counterbalance order, and detect
   copied example spans. Do not add another completed pass object as an instruction.

Official references: [Ollama structured outputs](https://docs.ollama.com/capabilities/structured-outputs)
documents schema enforcement through `format`; [generate API](https://docs.ollama.com/api/generate)
accepts generic JSON or a schema. [Qwen3 documentation](https://qwenlm.github.io/blog/qwen3/)
describes its non-thinking mode. These describe supported interfaces, not critic
accuracy, and do not support the conclusion that a 4B model necessarily copies all
concrete prompt text.

## Recommended solution architecture

1. Validate causal facts BEFORE using them as reviewer evidence. A critic cannot
   detect that the compiler invented an unsupported causal link if that very link
   is supplied as authoritative truth.
2. Give writer and reviewer the same versioned public fact packet, including exact
   objective terms. Select facts for the actual question; do not truncate away the
   relevant answer simply because six earlier facts were inserted first.
3. Have code choose the target sentence/clause. Ask for support relation and source
   fact IDs. No default verdict object and no full-dialogue multi-purpose grade.
   Keep knowledge of the actual question outside the model: no question means no
   relevance call, regardless of a model's tendency to answer that field anyway.
4. Validate the review: known source IDs, valid relation, completion not truncated,
   and any quoted target span must really occur in that target. Reject inconsistent
   pass-plus-error output. Missing coverage, malformed evidence or contradictions
   within the review become UNKNOWN, not proof of a fault or permission to approve.
   These checks cannot prove entailment; they prevent obvious reviewer failures.
5. Keep factual-support, relevance and style results separate. Initially run semantic
   results in diagnostic mode. Qualify each with false-pass and false-rejection rates;
   the current relevance subcheck is not good enough to enforce.
6. Fix high-value numeric checks with normalized numeric VALUES AND ROLES: hours,
   price, quantity, people. “Two hulls” cannot justify “two hours.” Include spelled-out
   quantities. Avoid broad bans on any number absent from a context substring.
7. Retry only unpublished failed writing, using the grounded issue and existing
   shared budget. Do not change quest facts to make a line pass. Keep accepted
   missions completable, diagnostic unknown distinct from passed, and optional
   publication enforcement behind explicit rollout policy.
8. Add a critic qualification regression with known-positive and known-negative
   sentinels, verdict distribution, unique raw-response count, malformed/unknown
   rate and per-category errors. Constant results on a balanced labeled set disable
   trust in that critic configuration. Uniform verdicts on a naturally all-good
   production sample are not, by themselves, proof of failure.

This needs no larger runtime model. Real writer-output evaluation can proceed in
parallel with critic development; it should not be blocked waiting for an ideal judge.

## Fast implementation review: actionable findings

The Git HEAD is still f09a1915, before both our last work and Claude's work. There
is no clean committed session boundary. I reviewed the combined diff and Claude's
new files against the previous handoff, rather than attributing every modified
line to him. No unrelated edits were reverted. This is a fast integration review,
not an exhaustive audit of all historical changes.

### P1 — Writer does not consume the fact packet the gate validates against

`MissionConversationGeneration.gd:54` still calls the old compiler prompt.
`DialogueFactPacket.prompt_block()` has a test caller but no production caller.
The packet is constructed after generation in `_quality_check_slice()`. Therefore
its richer public facts and question-specific grounding are not actually provided
to the writer through this route. Connect packet construction to dispatch and
persist its fingerprint with the slice; validate against that exact snapshot.
Keep the protected soul projection. This is an unfinished C integration, not a
reason to retune the model against mismatched inputs.

### P1 — Plausibility failures lose their contract and still publish

`PublicBoardOfferBuilder.gd:484` logs validation failure and returns from attachment;
the offer remains publishable without a contract. That is defensible as an explicit
diagnostic rollout, but it is not an enforcing plausibility gate. Only this publication
seam calls the new validator; acceptance/docking/turn-in are not wired to it.
Additionally `QuestPlausibilityValidator.gd:309` treats an explicitly empty resident
list as success, just like a missing snapshot. Zero residents must fail delivery
presence; unknown snapshot must remain unknown. Preserve old missions with a legacy
policy, while making new validated-offer requirements explicit. Existing delivery
guards remain useful but do not establish the new contract checks are complete.

### P1 — Compiler can manufacture the very facts used to approve dialogue

`PublicBoardOfferBuilder.gd:646` supplies stock delegation claims by objective type
(no free hull/no armed hull) without consulting faction holdings or availability.
`QuestCausalContractCompiler.gd:234` claims the selected courier item is what the
requester lacks without proving it matches the recorded need. Purchase jobs claim
the selected purchase is the ONLY way to satisfy the need; ore jobs assert sale
proceeds will pay for it. These are templates promoted to truth, not verified
causal links. Generate/bind a compatible objective from the need, or reject the
unbound cause. Hiding a requester-as-target name does not fix a self-targeting job.

Independent draws in `GeneratedFactionDesire` also need compatibility constraints:
random goal/need/obstacle/holdings/event combinations increase variety but can produce
contradictions. A large count of distinct combinations does not measure plausibility.

### P1 — “Hard” language checks have both known gaps and false rejection risks

`DialogueQualityGate.gd:155` checks digits only. I ran the exact “eleven hours” line
from the brief through `hard_checks()` with the convoy facts: it returns `ok:true`.
The brief's statement that this example is already caught is incorrect for the
current code. Word-overlap relevance at line 244 rejects “Patrols fire on ships
entering the restricted lane” as an answer to “Ask about the risk,” despite the
same sentence being supplied as a supporting fact. These checks are heuristics,
not authoritative semantic failures. Move overlap/style results to diagnostic
signals until calibrated; retain truly authoritative checks.

### P2 — Branch filtering is reported but does not remove executable options

`MissionConversationPlan.gd:140–163` computes surviving branches, but keeps every
non-question intent unchanged and stores the branch result as `policy_branches`.
No production consumer of that result was found beyond the plan builder. The policy
helper is useful; claims that it enforces all gameplay branches are premature.
Wire eligible branch IDs into actual action rendering AND command execution. The
fixtures' `INVESTIGATE_SITE` is also different from the existing capability's
`INVESTIGATE_SIGNAL`; align with the real capability before claiming runtime coverage.

### P2 — Quality provenance and review parsing are incomplete

`accept_response()` returns a quality state, but `promote()` and `copy_generation()`
do not retain that state with the offer. Missing-contract `quality_pending` can also
describe an offer with no scheduled review. Persist field-level state/version and
use an explicit missing-grounding reason. `parse_review()` accepts a `pass` with
nonempty issue codes; spans are ignored. Strict inconsistency checks belong in the
parser before any review is permitted to affect publication.

### P2 — Mandatory hostility contradicts the agreed direction

`GeneratedFactionDesire.gd:281,347` still guarantees an adversarial pair in EVERY
system, and a test enforces it. The new plan explicitly allows a system's problems
to come from scarcity, dependency or accidents. Remove that universal requirement;
use a real obstacle, not mandatory enemies, to support missions.

### P2 — Effect/capability validation is a vocabulary check, not execution proof

`QuestPlausibilityValidator` allows effect prefixes including pressure, relationship
and ending_predicate without resolving an executable handler. The compiler always
attaches desire_progress, but the planned outcome reducer is not implemented.
Distinguish planned narrative interests from supported executable effects, and derive
capability validation from the real registry instead of a parallel allowlist.

## Where Claude left off

| Plan phase | Assessed status |
|---|---|
| A: contracts | Schemas, compiler, validators and fixtures built; runtime enforcement and lifecycle checks incomplete |
| B: meaningful options | Question filtering wired; branch policy exists but action/UI enforcement incomplete |
| C: natural dialogue | Hard checks wired after generation; packet writer path, review scheduling/budget integration and persisted quality provenance incomplete; first real critic run failed |
| D: rich factions | Expanded deterministic desires, relationship kinds and compiler inputs built; coherent joint generation and no-forced-hostility rule unfinished |
| E: playable consequences | Specific-object causal text improved; real investigation integration and pressure reducer still outstanding |
| F: direction/endings | Not started in this work |
| G: qualification/freshness | 28-case critic corpus and first real run exist; full corpus, writer measurement, novelty history/batch and memory qualification unfinished |

Recommended restart order: fix shared writer/gate packet and false hard checks;
make causal publication state explicit; integrate real choices/capabilities; evaluate
actual writer output; qualify narrow critic subchecks; then finish D coherence and
the actual E runtime work. Do not wait on a perfect critic to continue deterministic
integration, and do not mark A–C complete solely because unit fixtures pass.

Five targeted suites rerun here passed with exit 0 and no SCRIPT ERROR: dialogue
quality gate, choice policy, causal contract, generated faction desire and public
board validation. Normal certificate/stat-write warnings remain. These green suites
do not cover the integration gaps above. No changes to protected soul/voice files
were found in the inspected diff. No new player approval or 8GB qualification is claimed.
