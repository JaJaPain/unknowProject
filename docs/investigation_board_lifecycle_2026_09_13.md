# Investigation board ownership and publication — 2026-09-13

**Later status:** the board, world sites, evidence controls, checkpointed
acceptance and payment are now connected. See
[board-to-payment integration](investigation_playable_loop_2026_09_13.md).
The implementation notes below describe the earlier backend-only slice.

## Completed in this continuation

`InvestigationBoardLifecycle` now prepares and publishes persisted investigation
postings. StoryManager supplies local entry points using the current campaign
seed, generated system agendas, registered station, live navigation snapshot,
tutorial completion flag and a code-owned 400-credit investigation budget.
The budget is a game reward policy, not a simulated faction bank balance.

Preparation never mutates the caller's state or retires a shape. Publication
rechecks the local cause and site clearance. StoryManager commits the entire
posting and selector state through StoryStateStore before returning success;
failed saves and stale preparations cannot overwrite the current state. The
first JSON representation is frozen before display, so reopening/reloading does
not change evidence, locations, reward or offered branches. Checkpoint capture
and restore preserve the additive `investigation_board` field. Invalid board
state is rejected before replacing the current story state.

The integration tests uncovered a real selector bug: a fresh TauntBag was
constructed with a global random seed before its campaign RNG was attached.
InvestigationSelector now supplies the initial seed explicitly. Existing saved
bags remain authoritative. Taunt behavior and content banks were not changed.

Eligibility is intentionally narrow. Survey-data needs support survey scans;
filed evidence for a salvage claim supports recorder preservation when another
local faction exists. Both currently require the coherent dispatch-backlog
blocker: the other generated blockers describe cargo transport and do not yet
justify commissioning new observations. Unsupported causes produce no offer.
This is a supported subset, not a claim that all generated needs are covered.

Postings retain their causal contract through the actual MissionAdapter.
There is one acceptance option. Resolution has the report escape and relevant
verification choices. Claims postings omit liquidation: a client commissioning
evidence has not supplied a funded alternative buyer for its destruction.
No timer is invented, and no P3 pressure effect is promised before it exists.

The lifecycle also provides release semantics: cancelling an unpublished draft
does not retire its shape; releasing a published posting preserves exposure and
cause history. The same cause cannot be relisted at another station in that
system. Different causes are sorted before selection, independent of list order.

## Verification

Six suites pass: new board lifecycle, selector, investigation runtime, story-state
migration, existing public-board validation and fixed-cast souls. Whole-project
parse check: 368 scripts, zero failures. Final test logs have no SCRIPT ERROR.
The migration suite's old user:// fixture was unwritable in this environment;
it now uses a guarded workspace fixture directory and passes.

New tests exercise actual StoryManager publication, real StoryStateStore disk
roundtrip, checkpoint restoration/rejection, local world/config preparation,
actual MissionAdapter acceptance, failed commits, stale requests, tutorial gate,
unsupported causes, missing budget, blocked sites, cause removal, retired causes,
unseen-draft cancellation and deterministic selection. Existing headless root
certificate/stats-write and shutdown-resource warnings remain.

## Next integration at the time — subsequently implemented

The UIManager board presenter is **not connected to these entry points yet**.
No new investigation jobs become available to the player from this change alone.
There are still no mission-owned discoverable sites or evidence/choice controls.
Connect those together so accepting a displayed posting provides a finishable
loop. The existing board's text fallback/HTTP rewrite path must not rewrite the
new posting or receive hidden site truth. Published cause/reward terms must remain
frozen, and unavailable published postings need an accurate status in the UI.

At that point wire release to acceptance/decline/terminal handling, coordinating
mission and board state with the campaign checkpoint; do not retire an offer on
a failed acceptance. Verify published system/station ownership through real
generated-system unload/reload and canonical alias conversion before exposing
the presenter. The current persistence tests use stable system IDs and do not
claim that alias integration is complete.

Then continue P3 pressure, campaign resolutions and novelty history. Player
testing remains deferred. Kaelen and N.O.V.A.'s personality, soul, voice and
reviewed banks are unchanged. The critic remains diagnostic/unqualified; these
mechanical checks are not approval of generated prose.
