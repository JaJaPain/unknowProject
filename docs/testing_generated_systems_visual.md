# How to Test Generated Systems Visually

Quick checklist for verifying that a generated/procedural system looks and
plays correctly after visual-only changes. Run this before committing any
change that touches shaders, particle systems, ambient effects, or the
visual-layer gate transition.

---

## 1. Enter a Generated System

1. Start from the main menu and load (or create) a campaign.
2. Travel through a gate to a **generated frontier system** — the system name
   will be something like "Cold Meridian" or a randomized two-word name; the
   minimap will show no fixed-icon stations, only outposts.
3. If you have no campaign at a generated system yet, travel through any gate
   from Kova or Iron Reach.

---

## 2. Ambient & Starfield Check

- [ ] Background nebula / starfield renders without flicker or z-fighting
- [ ] No obvious tiling seams at screen edges
- [ ] Ambient particle density matches the system's `nebula_density` setting
      (sparse for frontier, denser near the core)

---

## 3. Asteroid Field Check

- [ ] At least one asteroid ring is visible in the overview
- [ ] Asteroids use varied rock models (not all the same shape)
- [ ] Tumble rotation is active — each rock should slowly spin on a unique axis
- [ ] Vertical bob is visible — rocks should drift up/down slowly
- [ ] Mining laser activates rock-dust particles; they stop when laser stops
- [ ] Drones fly to asteroid and back while mining

---

## 4. NPC Ship Check

- [ ] At least one NPC ship is present (pirate, patrol, or salvager)
- [ ] NPC engine glow is visible while ship is moving
- [ ] NPC engine glow disappears on death (not attached to wreckage)
- [ ] Wreckage does not glow or animate after death

---

## 5. Gate Travel Check (if touching JumpTransitionFX)

- [ ] Approach a gate → "Fly to" and "Initiate Jump" buttons appear correctly
- [ ] Initiating jump triggers the entry sequence (no hard freeze)
- [ ] Transit corridor plays (tunnel swirl and/or flash visible)
- [ ] Exit ripple/shockwave plays on arrival in the new system
- [ ] Camera FOV returns to baseline after exit (no permanent zoom distortion)
- [ ] Player controls re-enable after transition (ship responds to input)
- [ ] No orphaned Tweens or lingering shader effects after arrival

---

## 6. Station/Outpost Check

- [ ] Outpost icon appears in the overview list
- [ ] Docking at the outpost works (dock button enabled within range)
- [ ] Lounge shows the correct contacts (or empty state if no contacts)
- [ ] Loading screen completes without hanging at 35% or 80%

---

## 7. Known Safe-to-Skip (visual-only changes)

If your change is **purely visual** (shader parameters, particle counts, color
values, FOV timing) and does not touch any of the following, you can skip the
full test suite:

- `QuestManager.gd`
- `MissionContract.gd`
- `GlobalState.gd` (persistence functions)
- `GameRoot.gd` (system loading / gate handoff)
- `CampaignSlotStore.gd`

Instead, run a fast visual-only spot-check: items 2–5 above plus a single gate
jump to confirm the transition plays end-to-end.

---

## 8. Headless Tests to Run After Any Change

Even for visual-only changes, run these to catch accidental side effects:

```powershell
# Mission contract tests (fast, ~5s)
$logPath = Join-Path (Get-Location) ".tmp_godot_user\test_logs\mission_contract.log"
.\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/domain/run_mission_contract_tests.gd --log-file $logPath
```

See `CLAUDE.md` for the full headless test invocation pattern and the known
startup crash workaround.
