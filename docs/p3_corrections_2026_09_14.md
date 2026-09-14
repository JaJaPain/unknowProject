# P3 corrective implementation — 2026-09-14

## Completed in this turn

- Fixed delivery rollback snapshot ordering. Ore, purchased inventory and courier
  cargo survive failed settlement and can be retried; successful retry consumes
  once and duplicate completion does not repay. Completion-stage GlobalState
  signals are suppressed until the checkpoint decision.
- Stopped automatic campaign-ending composition on board visits. Campaigns without
  a persisted proposal remain on their existing story path. Active/resolved plans
  remain frozen when another system is visited. Candidate pressure/resolution
  interests now use the actual coherent investigation cause filter.
- Resolution evaluation reads cumulative effect IDs rather than only the latest
  outcome's effect kinds. Safe checkpoints evaluate knowledge-supported endings
  before capture and roll back the projection on failure. Resolved primary arcs
  stop hook-driven refill; the board shows a factual resolution summary.
- Added save-system mapping for desire-progress records and composite keys,
  resolution interests and predicates. Unknown systems fail. Hardened missing-list,
  overlapping-alternative and unjustified-loss validation.
- Novelty ranking is consulted for investigation causes within the existing shape
  selection. Opening history influences initial pressure pairs. Cooldown occupies
  its slot until the four-job boundary. Investigation acceptance records its family
  inside the acceptance checkpoint.
- Histories retain monotonic sequences at capacity, current plus two previous
  openings, repeated accepted shapes, and a dirty investigation-history retry.
  Replacement no longer deletes the old file before attempting rename. Added a
  narrow pause-menu history reset; no campaign or character memory is cleared.

## Verification

16 distinct affected regression suites passed, plus the whole-project parse check:
**383 scripts, zero failures**. Logs are under `.tmp_godot_user/test_logs/` with
`fix_0914_*` and `handoff_fix_0914_*` prefixes. The final runs contain no SCRIPT
ERROR. Existing environment/shutdown warnings remain.

New tests cover ore/item/courier rollback and retry, preserved active plans across
systems, refusal to author a campaign ending from a board visit, cumulative
effect evaluation, consequence system/key conversion and unknown IDs, history
replacement/caps/sequence order. Existing investigation, pressure, persistence,
tutorial, delivery recipient/route and fixed-cast soul regressions pass.

## Limits and exact continuation

This is a corrective slice, not completion of every original handoff item.
The complete terminal callback/expiry/failure audit, ordinary-posting ownership
and novelty pacing, shape-level novelty integration, delivery-edge expansion and
director-authored campaign direction still need work. Existing v1 saved resolution
semantics were preserved, not silently reinterpreted. The new handoff separates
collection milestones from broader generated faction goals for future v2 plans.

Within-shape ranking alone often ties in the current narrow cause vocabulary.
No claim of broad new variety, fully generated endings, subjective dialogue
quality, player approval or hardware qualification is made. Player testing remains
deferred. Neither fixed cast nor prototype recipe availability changed.

Fresh-session instructions:
`docs/handoff_claude_gemini_campaign_completion_2026_09_14.md`.
That document defines implementation packages, schemas, rules, tests and failure
behavior for either Claude or Gemini; it supersedes stale completion claims.
