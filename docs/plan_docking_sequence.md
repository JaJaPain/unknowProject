# Docking Sequence — Visual Design Plan

## Overview

Four phases, roughly 3 seconds total. Currently docking is an instant snap; this replaces it with a felt, physical transition that also solves the combat-chase edge case.

---

## The Four Phases

### Phase 1 — Initiation (instant)
Player triggers dock. Input locks immediately. **Safe zone begins here** — before the animation, not after. Enemies in active pursuit drop the player from their target list at this moment (see Combat section).

### Phase 2 — Approach (0 → 1.5s)
Ship decelerates to zero on a short rail — a tween nudging it forward into the dock collar rather than teleporting. Camera slowly pulls back to frame ship + station together, then drifts slightly toward the dock port. Engine exhaust fades out (reuse `EngineExhaust` logic already in the codebase). No new geometry needed — the station mesh already looks fine at close range.

### Phase 3 — Lock (1.5 → 2.0s)
Brief camera hold. Subtle vignette on screen edges warming the color temperature slightly (station lighting vs. space). A soft "clunk" from the dock clamps — one sound effect. This beat sells the physicality.

### Phase 4 — Transition (2.0 → 3.0s)
Cross-fade into the dock UI. The 3D world doesn't disappear — it becomes the background behind the UI panels (already how dock UI works). This is just a fade-in of the panels over the held camera frame. `is_docked = true` fires here, `StoryManager.on_docked()` fires, Kaelen's 1.5s voice delay lands at roughly second 4–5 after initiation — well timed.

---

## What We Reuse

- **`JumpTransitionFX`** — already handles screen-edge effects and fade logic. The dock sequence borrows the same CanvasLayer pattern rather than building a new one.
- **`EngineExhaust`** — existing particle system; fade it out during Phase 2.
- **Camera node** — no new camera; tween the existing one.

---

## Combat — Chase Edge Case

**Safe zone starts at initiation, not arrival.** The moment the player clicks dock, enemies in active pursuit stop targeting. This is the only fair rule — enemies shooting through a 3-second animation the player can't control is a frustrating death.

**Enemies don't despawn.** NPCShips that were in pursuit switch to a holding state: patrol loosely near the station, drop the player from their target list. The threat is visibly still there — this is not a panic button. The enemy held position.

**Open question resolved:** Only enemies **actively in pursuit of the player** receive the hold signal. Ambient NPCs elsewhere in the system are unaffected.

**On undock, the threat is flagged.** Before the undock animation runs, a chatter line fires: "Hostiles detected outside. Watch yourself." (Kaelen or system comms.) Enemies immediately re-engage on the player's exit.

**The strategic layer:** Docking mid-fight is a real option — duck in, repair, reconsider — but the enemy is waiting. Players genuinely outmatched can bail without dying; players who were winning have no reason to dock. Rewards assessment without punishing aggression.

---

## Build Order

1. **Enemy hold signal** — broadcast on dock initiation. NPCShips in pursuit check a flag and drop targeting. Cheapest piece, needed first.
2. **`DockSequence.gd` state machine** — `IDLE → LOCKING → TRANSITIONING → DOCKED`. `GameRoot` calls it instead of the current snap. This is the only new file.
3. **Camera tween** — pulls back then holds on dock port. Reuses the existing camera node.
4. **Screen transition** — borrow from `JumpTransitionFX`, warm vignette + fade.
5. **Undock warning** — single chatter line before undock animation runs.
