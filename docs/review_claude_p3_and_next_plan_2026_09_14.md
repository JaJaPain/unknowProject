# P3 review and next implementation plan — 2026-09-14

## Verdict and scope

Claude made useful progress: the pressure reducer, typed outcome/progress records,
settlement checkpoint path, frozen pressure rewards, resolution compiler and
novelty stores exist. The two prototype recipes remain disabled, and supply is
correctly withheld rather than pretending raw ore is an assay.

However, **the handoff is not fully implemented end to end**, and there are
confirmed correctness problems. Fix these before expanding content. Claude's
latest `docs/todo.md` correctly acknowledges several integration gaps, whereas
the newest changelog's “all five ... implemented, tested and wired” overstates
completion. This review supersedes that broad status claim.

Reviewed current source at HEAD `75e284e4`, the P3 commits through `29ff002c`,
the handoff, changelog and current backlog. The first P3 commit also includes
previously uncommitted earlier work, so its entire diff must not be attributed
to Claude's new P3 implementation. This was a targeted high-level review, not
an exhaustive audit or player playthrough. No gameplay source was changed.

## Findings, in priority order

### 1. P1 — Failed delivery settlement can consume cargo without paying

`scripts/QuestManager.gd:939` applies completion hints before the rollback
snapshot at line 943. Those hints remove ore, inventory items or special cargo.
If the new settlement checkpoint fails, restoration uses the already-depleted
inventory. The mission is restored but cannot simply be retried.

Reproduced using the actual QuestManager with a 10-unit ore delivery and an
injected checkpoint failure:

```text
accepted=true before=10.0 after_failed_save=0.0 active=true retry_ready=false
```

The existing transaction test uses KILL_SHIPS, which consumes no delivery cargo
and therefore misses this ordering defect. Capture before all completion effects,
stage under the reentrancy guard, and defer externally observable reward/cargo
notifications until commitment. Test ore, inventory and special-cargo deliveries.

### 2. P1 — Automatically composed campaign goals need not be achievable or tied to the premise

`StoryManager._resolution_interest_candidates()` at line 1436 accepts interests
by need text alone. It does not use the board's stricter coherence, blocker,
salvage-goal and two-claimant eligibility checks. A filed-evidence interest for
another goal or a transport-only blocker can become a required campaign goal
without an available investigation capable of satisfying it.

A direct composer probe activated a plan for `filed claim evidence` with a
`carrier_cancelled` blocker and no second claimant. The real investigation board
rejects such a candidate. This is a binding gap, not a model quality question.

Further, `_compose_resolution_plan()` at line 1475 takes the first one or two
sorted local interests and writes empty `premise_fact_ids`. `_proven_desire_predicates()`
then treats their supported effect kinds as proof of desire satisfaction. That
can conflate collecting evidence with the broader generated goal being achieved.
There is no existing-campaign opt-in guard: opening a board can introduce this
replacement campaign goal into a legacy campaign too.

Do not ship this composer as the final campaign ending mechanism. Bind a precise
collection subgoal separately from a faction's legal/economic goal, and validate
the actual executable route before activation. Preserve old campaign direction.

### 3. P2 — Traveling can downgrade an active campaign plan to pending

`StoryManager.ensure_resolution_plan()` at line 1406 only short-circuits a
resolved plan, not an active one. It rebinds against the CURRENT system's agendas
and a one-element system list. On another eligible system's board, the original
references are missing and `bind()` changes the existing plan to pending.

Reproduced:

```text
initial plan=active
previously active plan after visiting another system=pending_bindings
```

Freeze active plans. Pending proposals must bind against persistent campaign
references, not only whichever local scene is loaded. A system visit must not
invalidate a previously proved campaign goal.

### 4. P2 — Resolution evaluation and presentation remain partially disconnected

`StoryManager._evaluate_resolution()` at line 1637 supplies only the current
outcome's effect KINDS to `committed_effect_ids`. MissionOutcome actually generates
unique effect IDs, and the desire ledger retains them. Typed `effect_committed`
predicates therefore do not receive the durable cumulative ID ledger promised by
the schema; conditions spanning separate jobs cannot work correctly through this
path. The auto-composed desire-only plan masks this gap.

Repository call-site search also found no consumer for
`is_primary_arc_resolved()` beyond the summary helper, and no consumer for
`campaign_resolution_summary()`. `_check_chapter_advance_after_hook_resolution()`
still refills chapters without that guard. The compiler's comments promise free
play with the resolved primary arc stopped, but the actual chapter and UI paths
are not wired to that behavior. Knowledge-only transactions also need a real
evaluation trigger, after their facts commit.

Use cumulative, correctly scoped effect IDs and public provenance; add real
chapter/UI consumers without stopping unrelated accepted work. Test this through
the StoryManager lifecycle, not only the pure compiler.

### 5. P2 — Novelty is recorded but does not yet change play

Call-site search finds definitions but no production callers for
`NoveltyHistoryStore.rank_candidates()`, `variety_exhausted()`,
`RunOpeningHistoryStore.preferred_pairs()`, or the pressure accepted-family
recording/pacing helpers. History writes are wired for investigations; ordinary
quest publication/acceptance and the settings reset are not fully connected.
Consequently the stores do not yet prevent repeated opening pairs or steer live
offers away from repeated reasons. Claude's current todo already acknowledges
ranking and reset gaps.

Additional history hardening before activation: opening upserts never trim the
stored list; acceptance currently records distinct shapes rather than the first
two accepted occurrences; save failure leaves the in-memory entry deduplicated,
so the same-entry retry returns before another disk write. Both file writers
remove the original before rename, leaving a failure window rather than a fully
safe replacement. These are bounded history defects, not campaign-save corruption
claims. Fix them as part of connecting selection.

## Other integration checks for the corrective pass

- SaveMigrator maps pressure track systems but has no equivalent mapping for new
  desire-progress keys/records or resolution interests/predicates. Add complete
  canonical/runtime roundtrips and unknown-reference rejection before relying on
  these structures across system aliases. This review did not reproduce a current
  player save failure from that omission.
- Resolution validation needs stronger malformed-record and overlapping-alternative
  checks. Current overlap detection only catches subset predicate sets; disjoint
  compatible sets can both hold, and any effect predicate is treated as proof of
  loss. Require a proven loss kind and an unambiguous result before enabling
  director-authored partial/failure alternatives.
- Pressure-slot candidates use looser checks than the investigation builder too;
  unify eligibility so a track does not promise work that has no supported cause.
- Several status/prose paths still occur after the authoritative settlement
  checkpoint. Include hook/knowledge/memory consistency in failure-injection
  coverage rather than assuming the new pressure snapshot covers all story state.

## Verification performed

Eight regression suites passed: local pressure, terminal transaction, pressure
cards, campaign resolution, novelty history, save migration, checkpoint storage
and fixed-cast souls. Whole-project parse: **383 scripts, zero failures**. No
SCRIPT ERROR appeared in those results. Passing these suites does not negate the
separately reproduced failures above.

Logs: `.tmp_godot_user/test_logs/review_0914_*.log` and console companions.
Targeted reproduction: `.tmp_godot_user/review_0914_probe.gd`, log
`.tmp_godot_user/test_logs/review_0914_probe.log`. It uses workspace fixtures and
does not change game source. Existing environment/shutdown warnings remain.
No player testing, visual approval, model-quality or hardware qualification was
performed. The fixed-cast soul regression passed; this review made no cast edits.

## Next work, ordered toward the end goal

### Step 1 — Correctness and honest completion status

Fix findings 1–4 before adding new content. Keep the current automatic ending
composer from replacing a campaign's premise until it passes executable-interest
and legacy-compatibility guards. Preserve legitimate pending/active/resolved saves;
do not silently erase saved promises.

Acceptance: failed ore/item/courier settlement restores resources and mission;
retry pays exactly once; the entire staged state survives real checkpoint reload;
an active plan survives A→B→A; a goal cannot activate without its supported route;
two effects from separate outcomes satisfy their intended bound condition; known
facts trigger evaluation once; resolved primary arc stops refilling and a factual
summary is visible while unrelated accepted work remains playable.

Add the new-system mappings, malformed state tests, cumulative provenance and
overlap/loss validation during this pass. Replace optimistic A–E checkmarks with
the verified subset. No new recipe or player testing is required to begin.

### Step 2 — Make remembered variety affect actual offers

Connect ranker, opening-pair preference, accepted-family pacing and reset to real
production paths. Keep eligibility before ranking and freeze published terms.
Cover ordinary board jobs as well as investigations; preserve accepted and
required work. Harden bounded history, campaign identity, repeated-shape recording
and retry/replacement behavior first.

Acceptance: with the same eligible candidates and seed, changing only prior
exposure changes the next offered reason/opening when a genuine alternative
exists. Panel reopen, prefetch, failed save and duplicate acceptance do not add
exposure. Sparse catalogs report exhaustion rather than fabricating variety.

### Step 3 — Expand reasons using existing executable delivery verbs

Use `docs/cause_coverage_audit_2026_09_14.md` as a candidate list, not automatic
authorization that every edge is already valid. Connect its supported delivery
edges to real items, origins, destinations and local recipients. Record only what
delivery actually proves. Carry exact causal bindings through settlement and
future offer selection; completed collection causes stay retired.

Acceptance: generated systems/outposts all provide a real recipient, cargo is
available through an implemented path, docking and turn-in agree, save/load does
not orphan it, and different needs/dependencies produce different reasons before
the model writes prose. This broadens meaningful variety without adding verbs.

### Step 4 — Generate campaign direction from the premise and local interests

Use the existing director/bible lifecycle to propose a small set of bound interests
that genuinely serve the campaign's premise. Code provides only executable
candidate effects and reachable destinations; the director selects/explains them.
Validate before freezing. Keep collection subgoals distinct from unimplemented
legal, economic or political outcomes. Do not label “first two local jobs” as the
campaign's unique end goal.

Connect supported dependencies to existing frontier leads and knowledge/navigation
paths. Persist a coherent direction across systems. Allow one justified ending;
partial/failure outcomes require actual committed loss or unresolved limitation,
not arbitrary branch counts or pressure levels. Legacy campaigns retain their
accepted story unless an explicit compatible migration is implemented.

Acceptance: automated multi-system traces show how different recorded actions
change eligible leads, future work and a factual outcome. Every ending claim has
an effect/fact source, and neither unknown secrets nor model-invented effects can
become game truth.

### Step 5 — Dialogue quality and combined automated campaign traces

Once causes/effects are reliable, feed their public facts into the existing narrow
writer/quality pipeline. Re-evaluate reasons, delegation, risk and actual options
on live-produced examples. Keep the critic diagnostic until evidence qualifies it;
parser success is not natural speech. No new model family, fallback speech bank,
or Kaelen/N.O.V.A. characterization changes are part of this step.

Run reproducible multi-seed traces covering tutorial exit, several generated
systems, recurring interests, deliveries, investigations, history and resolution.
Report semantic repetition, unsupported causes, dead ends and actual state
divergence—not just different names. Keep subjective player evaluation pending.

### Still deferred

`transmitter_lure`, `unstable_archive`, supply/assay expansion and further activity
types remain outside this implementation sequence. The first two investigation
recipes still need eventual human evaluation, and the complete project still
needs prose and hardware qualification. We can complete the above automated work
without requesting player testing now.
