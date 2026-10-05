# Playtest 2026-10-04 (d): findings

Abe's fourth run today: the new planets, the autopilot 180 fix, the
tutorial station pin and the crash fix. Rule: **record and research only;
no code changes until Abe says the playtest has finished.**

## Findings

### 1. Undocking: the overview can be clicked while the beam still has the ship

**Abe:** when undocking, the player should not be able to click on the
overview.

**Code:**
- While docked, the overview is locked: `_set_overview_dock_locked(true)`
  hides it and sets `mouse_filter = IGNORE` (`UIManager.gd:~13372`).
- `undock_player()` unlocks it at the start, as the beam push begins
  (`_set_overview_dock_locked(false)` and `set_overview_collapsed(false)`,
  `UIManager.gd:~10620`). The push (`_push_out_of_berth`) carries the ship
  out past the safety zone for 4-10 s before `is_docked` clears.
- So during the push the overview is live:
  - a left click on a row sets `GlobalState.active_target`
    (row `pressed`, `UIManager.gd:~3843`), which opens the target window
    with Approach / Orbit / Mine...;
  - a right click opens the context menu (`show_context_menu`).
- The orders themselves are refused while docked (playtest c finding 4, "Dock
  Control has the ship..."), but the clicks still land: targets change, menus
  open, and it reads as control.

**Proposed fix:**
- The overview comes back *with* control. Keep it locked through the push,
  and unlock it in the push's release callback (with "Clear of the safety
  zone. Controls are yours."). Or show it during the push but
  unclickable (`mouse_filter = IGNORE` on the panel and rows), so the player
  can read it while being carried out.
- The same for the target window and the context menu: nothing selectable
  until release.
- Check N.O.V.A.'s first-undock tutorial line ("I highlighted that ship in
  red on our overview. Click it...") plays after the release, which it already
  does, so the overview she points at is clickable by then.
- Test: the dock smoke clicks a row mid-push (no target change), then
  after release (target set).
- **Ask Abe:** hidden during the push, or visible but not clickable?
