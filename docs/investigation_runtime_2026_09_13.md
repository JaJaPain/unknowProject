# Investigation command integration — 2026-09-13

**Later status:** the first two recipes now have board, world and evidence UI
integration. See [current scope](investigation_playable_loop_2026_09_13.md).

## Implemented and tested

The first two investigation recipes can now pass real mission acceptance,
MissionAdapter, MissionState and saved-state validation. Previously the pure
capability was registered but the normal objective schema rejected its type.
The new validator checks site identity/roles/positions/system scope, evidence,
offered branches, phase and saved outcome/payout consistency. New offers cannot
arrive already resolved. The lure/archive recipes remain outside this runtime
slice; their pure prototypes are preserved.

QuestManager now owns `begin_investigation_scan`, `cancel_investigation_scan`
and `dispatch_investigation_command`. Its physics tick drives the existing
three-second hold using the live ship's range, velocity, docking/destruction and
combat state. The UI cannot supply elapsed time, a completed scan, inventory
availability or arbitrary command IDs. Holds reset on restart/restore and cannot
be banked between sites. Commands are scoped to mission/site/revision.

Resolution calls the actual capability on a draft, validates it, then commits
inventory and mission state before publishing signals. Failed commands do not
spend or change the mission. Retries return the stored result without applying
effects again, including after a JSON save/load. Both scans alone never complete
an investigation. Missing drones leave the no-cost report path available.

Turn-in requires docking at the saved station in the mission's system. Payout
is calculated from the chosen branch and saved truth, not a client-supplied
multiplier, and floored once. A 401-credit budget pays 601 for liquidation,
200 for report, and 100 for mistaken certification. Turn-in is guarded against
reentrant credit-change callbacks as well as repeated clicks.

MissionAdapter explicitly carries investigation fields. SaveMigrator maps nested
site system IDs together with their parent mission between runtime and canonical
IDs. It preserves site IDs, evidence, truth and commands. An invalid investigation
restore returns an error before QuestManager clears its current collection.
The existing checkpoint captures mission and inventory together; this change
does not claim every unrelated checkpoint failure is transactional.

## Verification and related corrections

13 suites passed sequentially with unique logs: runtime integration, pure
investigation capability, offer builder, scan hold, mission transitions, public
board, causal lifecycle, delivery recipients, tutorial return, fixed-cast souls,
save migration, system factory and system registry. Whole project: 365 scripts,
zero parse failures. Checked logs for SCRIPT ERROR, not merely PASS messages.

The runtime suite uses actual QuestManager acceptance/commands, live fixture
ship/inventory, and the real SaveMigrator encode/decode path. Negative cases
include forged tokens, hidden verification, missing scans/items, range/speed/
combat blocks, damaged saved positions, premature ready state, wrong station,
double turn-in and a credit-change listener that tries to complete again.

The legacy migration suite needed deferred dependency loading and a workspace
fixture path. Once those setup errors were removed, it exposed a real older
SystemConfig.from_dict bug: a missing faction_identities key passed a default
Dictionary check and was then accessed without that default. The read now uses
the same default. Final migration logs have no SCRIPT ERRORs. Existing headless
certificate-store/stats-write and some shutdown resource warnings remain.

## Still required for a playable P2 loop

Continuation: live acceptance placement checking is now connected. PlayerShip
provides the exact navigation obstacle records without nodes; the new
InvestigationWorldPlacement checks saved positions and live station availability.
Unsafe offers are rejected before effects without rerolling facts. Five relevant
suites pass and 366 scripts compile. Optional offer generation/publication and
the remaining world/UI work below are still open.

This is a command/serialization slice, NOT a claim that investigation missions
now appear on the board or that Phase E is finished.

1. Connect optional offer ownership/selection to real local causes, approved
   budgets, registered stations and navigation obstacle snapshots. Revalidate
   placement at acceptance; do not draw or retire shapes during mere prefetch.
2. Create/reconcile mission-owned world sites from saved positions, with sensor
   discovery, the initial search region, verification reveal and cleanup.
3. Add the evidence/choice panel and wire its controls to these QuestManager
   commands. Keep revealed evidence separate from hidden truth. Explain disabled
   choices and current requirements. A dialogue branch string is still not proof
   that a generic effect handler exists.
4. Record committed investigation outcomes and implement the P3 pressure reducer,
   then campaign resolutions and novelty/exposure history.

No fixed-cast personality, soul, voice or reviewed bank changes. No model calls
were added to commands, item spending or turn-in. The critic remains diagnostic;
player review and hardware qualification remain pending.
