# Investigation board-to-payment integration — 2026-09-13

## Implemented

The visible station board now offers the first two investigation recipes when
the local generated agenda supplies a supported cause and the tutorial is
complete. The existing narrow eligibility and 400-credit base budget remain.
Unsupported needs do not create substitute investigations. Published facts,
sites, reward and branches stay frozen; these cards bypass the generic board
writer so hidden evidence is never sent to that rewriting path.

Acceptance rechecks the actual station, docking state, board slot, local cause
and navigation clearance. The active mission and retired posting are captured
together in a station checkpoint before acceptance events fire. Failed checkpoint
creation restores the previous mission focus and posting state. Declining a
published investigation persists its retirement before changing the visible
board. A published offer that becomes unavailable displays its reason.

Mission-owned transient world markers show the search area, reveal the first
site within sensor detection range, and reveal verification after the first scan.
Markers use detection hysteresis and are recreated from saved mission facts;
they are removed on system departure, resolution, abandonment or reset. They
are not ordinary anomalies, persistent world entities or general overview rows.
The mission card and investigation panel provide navigation to them.

The evidence panel uses QuestManager's real scan holds, pose/range/speed/combat
checks, revision checks and inventory authority. It displays only recovered
evidence, available actions and reasons an action is unavailable. Survey jobs
support reporting or certification; claims postings support reporting or recorder
preservation. No unfunded liquidation buyer is invented. Controls use code-owned
mission terms, without impersonating a character or generating fallback speech.

Resolved missions navigate to their assigned settlement station. Board turn-in
uses the investigation payout and a neutral Contract Settlement receipt, rather
than invoking Kaelen's agent-completion dialogue. Repeated turn-in cannot pay
twice. Kaelen and N.O.V.A.'s personalities, souls, voices and reviewed banks were
not changed by this slice.

## Persistence fixes

Canonical/runtime system conversion now includes persisted posting ownership,
reservation keys, site IDs and causal-contract system bindings, as well as active
investigations. Unknown ownership mappings fail validation.

Checkpoint sanitization previously removed every field called `position`, which
also erased permanent investigation sites. Both sanitization and schema checks
now recognize only the exact active-mission and published-posting site paths.
Ship positions, velocity and investigation-shaped dictionaries in unrelated
locations remain disposable. Search centers/radii and primary-site containment
are validated before acceptance or restore.

The acceptance checkpoint guarantees the mission/posting pair is durable. It
does not claim an atomic transaction covering all later chronicle events or all
unrelated checkpoint side effects.

## Automated evidence

Headless tests exercise actual UIManager board handlers, both published recipes,
failed/successful acceptance checkpoints, duplicate acceptance, timed scan
buttons, evidence actions, assigned-station settlement and duplicate payment.
World tests cover discovery hysteresis, hidden evidence, save/restore and cleanup.
Real CampaignCheckpointStore disk roundtrips preserve both active and published
site coordinates while stripping ship pose. Negative tests verify the exception
does not retain velocity or allow unrelated dictionaries to bypass cleanup.

The final post-fix regression run passed checkpoint storage, campaign schema,
save migration, board lifecycle and investigation runtime suites. Whole-project
parse: **370 scripts, zero failures**. Logs:
`.tmp_godot_user/test_logs/complete_*_01.log` and their console companions.
Earlier in this slice, public-board validation, delivery routing/recipients,
tutorial revisit, fixed-cast souls, system generation and site reveal also passed.
No SCRIPT ERROR appeared in the final logs. Existing environment certificate,
stats-write and shutdown-resource warnings remain.

These are automated mechanics and control tests. No player playthrough, visual
layout approval, model prose qualification or low-end hardware qualification is
claimed. The critic remains diagnostic/unqualified.

## Next work

Continue P3's activity-based faction pressure and durable consequences of completed
jobs, with idempotent effects and save/load coverage. Then connect campaign
resolutions and novelty history. The other two investigation recipes remain
prototypes and must not be exposed as completed gameplay. Broader cause coverage,
human review of the first two recipes, dialogue quality and hardware qualification
remain open; the full campaign uniqueness plan is not complete.
