# Prompt for Claude: resume the campaign uniqueness plan

You are implementing SpaceGame in `C:\CodingProjects\SpaceGame`. This is a fresh
session. Read the context below, inspect current source, and start the next unfinished
implementation slice. Do not stop at another plan or ask whether to continue.

## My instructions

Make each campaign feel different after the tutorial system through specific
faction interests, believable mission reasons, supported consequences, travel
dependencies and campaign endings. Renamed factions or reshuffled text are not
enough. Familiar gameplay verbs can repeat; identical underlying stories should not.

Kaelen and N.O.V.A.'s personalities, canon, soul definitions, approved voice guidance,
reviewed line banks and voice identities must remain unchanged. Use their existing
protections. Do not weaken them to improve a generic dialogue score.

Quests may have ONE completion path. Additional options require a credible motive,
supported action and meaningful difference. Do not create dilemmas or danger to fill
menus. Questions should add useful information; there is no mandatory why/risk/
connection trio. Ordinary direct speech is valid even when it is not elegant.

Player testing is deferred. Continue automated implementation and evaluation. Record
human review and hardware qualification as pending; do not invent approval or use
their absence to stop ordinary development. No larger model, hosted API or paid
service may become a player requirement. The combined memory target remains 8GB.

## Read first

1. Root AGENTS.md, CLAUDE.md and applicable directory instructions.
2. PROJECT_MAP.md or PROJECT_MAP.json before broad exploration.
3. docs/design_end_goal.md — the product goal.
4. docs/whileYouWasSleeping.md — latest handoff.
5. docs/plan_campaign_uniqueness_and_dialogue_quality.md — primary implementation plan.
6. docs/review_claude_critic_and_plan_2026_09_12.md — integration findings.
7. docs/critic_fix_2026_09_12.md — exact critic correction and measured limits.
8. Relevant parts of docs/plan_mission_conversation_llm_path.md and
   docs/plan_replayability_local_inference.md, especially P2/P3/P4.

docs/problem_critic_always_passes.md is the historical failure brief. It is not an
instruction to reinstall the old prompt. Earlier status entries are chronological;
later corrections supersede claims that phases are complete.

## What Codex just changed

- Added scripts/story/DialogueCritic.gd: code-selected sentence coverage, separate
  factual-support/relevance jobs, strict schema and evidence parsing, bounded job
  counts, coverage checks and calibration logic.
- Removed the completed pass example. DialogueQualityGate.parse_review() deliberately
  refuses the old unbound pass/repair protocol. Use DialogueCritic jobs/prompt/parse/
  aggregate for the replacement; do not “fix” compatibility by accepting old JSON.
- DialogueQualityGate.decide() requires independently supplied, matching qualification
  before semantic reviews can approve OR reject. No current critic is qualified.
- Added written-number and duration-role checks. Moved lexical relevance and
  briefing-restatement checks to advisory status to avoid rejecting plain speech.
- Added mission_dialogue_quality persistence through promotion/copy/MissionAdapter.
- Gateway accepts real JSON schemas. The maintained evaluator now uses the shared
  protocol and stores request settings, model identity, raw output and qualifications.
- Added tests/story/run_dialogue_critic_tests.gd and a balanced CriticSentinels corpus.
- Preserved the original baseline at logs/quality_eval/critic_eval.json.

Seven relevant suites passed; 357 scripts compiled. Inspect and rerun the appropriate
tests for your changes rather than relying on historical results.

## The critic decision is settled for this implementation stage

The silent constant-pass approval path is blocked and regression-tested. The 4B
model now discriminates, but its accuracy is still insufficient to enforce.

The full original corpus produced 4 false passes among 9 factual negative cases,
with 0 false rejections among 12 good cases. The separate relevance check falsely
rejected 2 of 6 relevant answers. Two seeds of the independent 16-case sentinels
each missed 4 of 8 bad claims. These runs correctly failed qualification.

Therefore keep semantic judging DIAGNOSTIC, never fake quality_passed, never turn
uncertain into approval, and never impose an unqualified critic's rejection on
plain dialogue. Measure actual writer outputs instead of waiting for a perfect
critic. Deterministic quest mechanics/knowledge checks still enforce their contracts.
This follows the original plan's instruction to keep a costly or ineffective
critic offline until evidence supports using it.

Do not weaken thresholds, relabel difficult cases or add a blanket pass fallback
to produce a green score. All eight original holdout cases have now been evaluated;
future tuning needs a fresh independent holdout before final qualification. Never
present tuning results as human review. Keep factual, relevance and style dimensions
separate. A truthful robotic line is not a factual lie; a fluent lie is not good output.

## Next work, in order

### 1. Finish A–C integration before expanding the feature set

Connect DialogueFactPacket to the real writer dispatch in
MissionConversationGeneration.prompt_for_job(). Currently it is constructed only
after generation for validation; its prompt_block has no production writer caller.
Writer and validator must share the same immutable public packet and fingerprint.
Select facts by the actual question, not just generic purpose and dictionary order.
Do not omit the relevant answer because six unrelated facts reached the cap first.
Keep fixed-cast soul projection and existing stale-response/retry protections.

Make causal publication states explicit. PublicBoardOfferBuilder currently logs a
rejected contract and publishes the offer without it. Distinguish old compatible
missions from newly generated discretionary offers that fail required checks.
New optional offers with invalid mechanics or unbound causes should be withheld;
old accepted jobs must remain completable. A missing world snapshot is unknown;
an explicitly empty resident list means nobody is there and must fail a delivery
presence check. Integrate validation at acceptance, docking and turn-in, using
real authoritative world snapshots rather than invented capability/funding data.

Connect QuestChoicePolicy's surviving branch IDs to actual UI actions and command
execution. Currently policy_branches is stored but has no gameplay consumer, and
non-question intents are retained independently of it. Revalidate eligibility on
click. Preserve already accepted terms and explain temporary unavailability.
Use the existing `INVESTIGATE_SIGNAL` capability,
not the fixtures' unsupported `INVESTIGATE_SITE` alias. Resolve capabilities/effects
against executable handlers; an approved string prefix is not execution proof.

Ensure quality provenance survives the full offer→active mission→checkpoint path.
Codex added the aggregate quality record, but future per-field asynchronous review
needs exact packet/model/version association and preserved attempt accounting.
Never overwrite a line already displayed or spoken. Do not schedule model calls
inside acceptance, scanning, inventory spending or delivery commits.

Prove the three vertical examples through real entry points:
- A straightforward courier with one completion path.
- An investigation with one justified decision.
- An investigation whose gratuitous extra option is removed without breaking it.

### 2. Finish D's causal coherence

GeneratedFactionDesire now independently draws richer dimensions, but independent
random choices can contradict each other. Add compatibility constraints and real
bindings between goal, need, obstacle, holdings, triggering event and payment.
Do not count distinct combinations as proof they make sense.

PublicBoardOfferBuilder._delegation_text() currently invents “no free hull” or
“no armed hull” from mission type alone. QuestCausalContractCompiler can claim an
arbitrary courier item fulfills a need, a purchase is the ONLY solution, or ore
will be sold to fund a need. Those claims need actual support before entering the
fact packet. Generate compatible objectives from the need, or reject the draft.
A critic cannot catch an invented reason when the compiler supplies it as truth.

Remove GeneratedFactionDesire's universal adversarial-pair requirement and update
its regression test. A system can have work because of shortages, accidents or
dependencies without mandatory enemies. Preserve genuine disagreements when the
generated situation supports them. Hiding a self-targeting faction's name does not
repair an invalid mission that still targets its own requester.

### 3. Implement E: playable consequences

The previous “E first slice” improved specific-item descriptions; it did not finish
investigation gameplay or pressures. Integrate P2's first two investigation shapes
with actual offers, safe site placement, discovery/scans, evidence, branch commands,
cleanup and saves. Use the plan's navigation bounds and real obstacle data. Honor
the current instruction that branch count follows the situation, not a quota.

Then implement P3's code-owned pressure reducer using committed, deduplicated
mission outcomes. Preserve the distinction between pressure activity steps and
callback delivery steps. Inventory, rewards, mission state and consequences must
commit/restore together. Double clicks, retry, restart and checkpoint rollback
must never duplicate a payment, item spend or effect.

Only narrate effects the code actually applied. Do not promise station closures,
deaths, market collapse or recovered trade lanes when no implemented effect exists.

### 4. Implement F and G

Build campaign-specific resolution conditions from the premise and supported
effects. Bind travel leads to reachable destinations with their own persisted
local factions and real services. Let recorded choices and outcomes determine
the ending; do not require a final choice menu if events already resolved it.

Add semantic-signature and sequence repetition checks, normalizing away names.
Persist a bounded cross-campaign exposure history separately from cast memories.
Count shown offers separately from speculative prefetch and accepted work. Prefer
fewer credible offers over novelty created by nonsense. Preserve saved identities
and facts; new generation rules must not reroll already visited systems.

Implement the remaining corpus, writer evaluation and performance harnesses.
Measure the real configured model, complete request pipeline and combined memory;
do not claim that model size alone proves the 8GB target. Keep model absence,
timeouts and unavailable hardware as honest unmeasured results, not invented passes.

## Questions answered in advance

**Should I retry critic prompts until every existing case passes?** No. That would
overfit exposed examples. The approval bug is guarded. Continue the real integration
work with semantic judging diagnostic. Any later critic improvement needs a fresh
evaluation, exact configuration fingerprint and acceptable per-dimension results.

**Can I require qwen3:8b?** No. It may be development equipment only. Do not change
player requirements or globally enable model thinking as an unmeasured workaround.

**What if there are no good choices or no danger?** One path is valid. Omit the
extra choice or risk question. Acceptance, decline and leaving remain normal UI
controls; they are not proof of a branching quest.

**Can the model invent missing world facts?** It may propose draft facts during
world generation. Code must validate and bind them before publication. A line writer
or reviewer cannot retroactively change an accepted quest's truth to make prose fit.

**What happens to reputation?** Preserve local standing keyed by stable faction IDs
across revisits. Show the current system's relevant standings. Defer portable
notoriety until it has its own explicit contract; do not propagate tutorial opinions
automatically or reset standing on every jump.

**Do player testing, voice audition or an ideal critic block coding?** No. They
remain deferred qualification items. Do not mark them passed, but keep implementing
authorized deterministic and integration work.

**Can existing saves change?** Add versioned migrations and preserve accepted
missions, known facts, rosters, recipient bindings and completion gates. Do not
silently discard a mission, reroll truth or change rewards to repair bad prose.

## Workspace and verification rules

Start with git status and read the relevant source/diffs. The workspace contains
uncommitted work from both assistants; HEAD is not a clean handoff boundary. Preserve
it. Do not reset, clean, revert, commit or push unless explicitly requested.
Do not manually overwrite data/content/taunt_lines.json as incidental cleanup.

Regression requirements include tutorial decline-and-return, delivery route and
recipient checks, destination-local lounge/docking identities, generated-system
roster persistence, fixed-cast protections and stale outcome callbacks.

Run Godot headless tests sequentially with unique absolute workspace log files.
Inspect SCRIPT ERROR output even when a suite prints PASS. Use deferred runtime
loads where early preloads otherwise run before autoload registration.

Example deterministic regression:

```powershell
.\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/story/run_dialogue_critic_tests.gd --log-file C:/CodingProjects/SpaceGame/.tmp_godot_user/test_logs/claude_critic_regression_01.log -- --baseline-offline --llm-live-fire
```

Example real local critic measurement:

```powershell
.\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tools/quality_eval/run_critic_eval.gd --log-file C:/CodingProjects/SpaceGame/.tmp_godot_user/test_logs/claude_critic_measure_01.log -- --baseline-offline --llm-live-fire --tuning-only
```

Both flags disable unrelated startup generation/refill; the probe still calls
Ollama directly. Use --sentinels for the balanced sentinel set and --seed=67890 for
another seed. A nonzero qualification result is an honest failed qualification,
not a reason to remove the guard. Inspect the saved report for the reason.

Use tests/parse_check_scene_scripts.gd for whole-project compilation and run
git diff --check. Refresh PROJECT_MAP after significant new systems or file moves.
Python may not be on PATH; the bundled interpreter previously available was:
`C:\Users\abejh\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe`.

Keep progress updates concise. Update docs/whileYouWasSleeping.md and implementation
status after substantial slices. Separate implemented, automatically tested,
real-model measured and human-reviewed. At session end, leave the exact next step,
tests/results and remaining risks. Start with the first unfinished integration
step above, not another rewrite of the entire architecture.
