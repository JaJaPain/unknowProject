# Playtest 2026-10-04 (c): findings

Abe's third run today: a fresh campaign after the stinger and 35% fixes.
Rule: **record and research only; no code changes until Abe says the
playtest has finished.**

## Findings

### 1. Mouse and controls work during the intro; they should be off until the "look around" hint

**Abe:** the mouse and all controls should be disabled until they're handed
back, at the point where the tutorial suggests using the right mouse button
to look around.

**Code:** the hand-back is `IntroCinematic._finish()`
(`scripts/story/IntroCinematic.gd:~569`). It re-enables the ship's physics,
clears `GlobalState.intro_cinematic_active` and shows "Hold RIGHT MOUSE and
drag to look around". Before that point, the intro only:
- hides the HUD (`_ui.visible = false`), and
- stops the ship's physics (`p.set_physics_process(false)`).

Nothing gates input:
- `PlayerShip._unhandled_input` never checks `intro_cinematic_active`.
  Right-drag still orbits and captures the camera (fighting the intro's
  camera shake and settle). Left-click fly-to, Q/W/E, Space (hard stop) and
  zoom are all taken, setting nav orders that run the moment physics comes
  back.
- `UIManager._unhandled_input` still opens Inventory (I) and the star map
  (M), and handles the 1-4 agent replies, mid-intro.
- Other activity keys check their own "flying" tests: the receiver (T)
  checks `intro_cinematic_active`; the drone dive (G) should be checked.
  The scan (C) is blocked by `_can_scan_composition`.

**Proposed fix:**
- One rule: while `GlobalState.intro_cinematic_active`, the ship and HUD
  ignore all input. Add an early return at the top of
  `PlayerShip._unhandled_input` and `UIManager._unhandled_input`, and in the
  drone-maze key handler. Free the mouse if it was captured.
- Keep Space (skip the intro), which IntroCinematic handles itself. **Ask
  Abe:** should Esc (systems menu) work during the intro?
- Test: during the intro, simulated RMB drag, click, Q, I, M and G do
  nothing; after `_finish()` they work.

### 2. Get the ship's drones moving as soon as we're out of the gate

**Abe:** get our drones moving as soon as possible once we're outside the
gate.

**Code:** the two drones orbiting the ship are animated by
`PlayerShip._update_drones()`, called from `_physics_process`
(`PlayerShip.gd:~1182`). The intro turns physics off at the start and on
only at `_finish()`. So the drones hang frozen beside the ship from the
fling out of the broken gate (after the 1.2 s reveal) through the arrival
lines and data stream, until the hand-back: about **18 s** (`HANDOFF_AT`).

**Proposed fix:** from the reveal on (out of the gate), the intro drives the
drones itself: `IntroCinematic._process` calls
`player._update_drones(real_delta)` once the tunnel is gone. Ship physics
and control stay off until the hand-back (finding 1). Check the drones'
health colours (already set by `_apply_consequences`) and that nothing in
`_update_drones` needs movement state. Optional: a beat of N.O.V.A.'s
"drones back online" if Abe wants it called out (ask; no new line without
approval).
