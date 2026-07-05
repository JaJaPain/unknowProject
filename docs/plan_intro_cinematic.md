# Intro Cinematic — "Thrown Through" (plan + living checklist, 2026-07-05)

The true cold open, BEFORE Kaelen's intro: the player's ship is hurled through
a malfunctioning gate — violently, glitching — and dumped into the start
system NOT via a gate. N.O.V.A. is met mid-crisis ("Hold on, Captain...
I got one last thing I can try!"), the ship arrives damaged, she explains her
amnesia, an untraceable data stream delivers exactly enough credits to repair,
then the UI returns and the EXISTING Kaelen intro runs unchanged.

Rollback tag: `pre-intro-cinematic`. Mark checkboxes as phases land — this
file is the hand-off list if another model finishes the work.

## Verified seams (2026-07-05)

- **Entry point:** UIManager ~11529: after the loading panel fades, on a NEW
  campaign (`if not startup_save_loaded:`) it schedules `show_kaelen_intro()`
  after 1s. THE hook: start the cinematic here instead; the cinematic calls
  `show_kaelen_intro()` when it finishes. Loads (`startup_save_loaded`) keep
  the existing Nova.welcome_back path — cinematic never replays.
- **UI hide:** UIManager `extends Control` → `visible = false` hides all HUD
  panels. The cinematic draws on its OWN CanvasLayer (layer 90, added as a
  child of UIManager like the combat-tutorial overlay — CanvasLayers ignore
  parent Control visibility, verified pattern at _show_combat_tutorial_popup).
- **Control lock:** no input-lock flag exists in the codebase. Use
  `player.set_physics_process(false)` for the duration + restore after; the
  cinematic tweens `player.rotation` directly for the tumble (camera is on
  the ship, so spinning the ship sells the motion for free).
- **Ship damage / repair economics:** `UIManager._repair_ship()` (~9182):
  cost = missing_hp * 2.0 credits. Cinematic sets health to 40% of max, then
  the data stream grants `int(ceil(missing_hp * 2.0))` — EXACTLY enough, by
  construction, whatever the max_health is.
- **Voice:** `Nova.speak(text, severity, expression)` → chatter (hidden, fine)
  + TTS via emit_npc_flavor (UIManager's audio handler still runs while
  hidden). Cinematic shows its OWN centered subtitle label for the same text.
- **Gate FX reference:** GameRoot `$JumpTransitionFX` (play_entry/hold_covered/
  play_exit) — NOT reused; the cinematic owns its visuals so it can't fight
  the jump system. Glitch look comes from a new canvas shader.
- N.O.V.A. plot armor etc. unaffected; no story_state/schema changes needed.

## Files

- NEW `shaders/intro_glitch.gdshader` — canvas_item shader on a full-rect
  ColorRect: screen-texture UV displacement in noise bands + chromatic
  aberration + scanline flicker + white-out mix, all driven by a single
  `intensity` uniform (0..1) the sequence animates.
- NEW `scripts/story/IntroCinematic.gd` — one-shot Node (NOT autoload);
  UIManager instantiates it on new campaigns. Builds its own CanvasLayer UI
  in code, runs a phase timeline, frees itself, invokes a `finished` callback.
- EDIT `scripts/UIManager.gd` — swap the show_kaelen_intro scheduling for the
  cinematic (which calls show_kaelen_intro itself on finish/skip).

## Beat timeline (IntroCinematic phases)

0. SETUP (instant): UIManager.visible=false; player.set_physics_process(false);
   black overlay alpha 1 + glitch ColorRect (intensity 1.0) + subtitle label.
1. TUMBLE (~0.0-4.5s): glitch intensity oscillates high (tween 0.7<->1.0),
   white-out pulses; ship rotation tweens chaotically (2-3 full-axis spins).
   ~1.0s: NOVA line 1 (subtitle + Nova.speak, "alert"):
   "Hold on, Captain! I'm doing everything I can to stabilize the ship —
   I've got ONE last thing I can try!"
2. FLING (~4.5-6.0s): hard white flash (overlay to white, 0.15s), glitch
   spike to 1.0, then overlay + glitch tween OUT (reveal space, ~1.2s) —
   the ship was thrown INTO the system, no gate: arrival is a violent
   deceleration, rotation tweening from fast spin to a slow drift.
3. ARRIVAL (~6.0-14s): health = 40% of max (feel: battered, alarms in the
   text, not new SFX). Residual glitch flickers (intensity 0.15 pulses).
   ~7s NOVA line 2 ("worried"): "We're... somewhere. That wasn't a gate
   transit, Captain — we were thrown. Hull's a mess, but we're alive."
   ~11s NOVA line 3 ("wondering"): "Here's the part I don't like: my memory
   starts fourteen seconds ago. I know you're my captain. I know I trust
   you. I just can't tell you WHY I know either of those things."
4. DATA STREAM (~14-20s): system-styled subtitle (mono/cyan):
   "INCOMING DATA STREAM // ORIGIN: [UNRESOLVED] // CREDITS RECEIVED: N"
   where N = int(ceil((max_health - health) * 2.0)) -> GlobalState.add_credits(N).
   ~16s NOVA line 4 ("thoughtful"): "Someone just wired us exactly enough to
   fix the hull. No routing data. No sender. I ran the trace twice — it goes
   nowhere. I'd say 'lucky us', but luck doesn't usually know our account number."
5. HANDOFF (~20s): glitch node freed, UIManager.visible=true, physics
   re-enabled, cinematic queue_free(); 1s later -> show_kaelen_intro()
   (the existing popup, unchanged).

SKIP: after 2s a small "[SPACE] skip" hint bottom-right; _unhandled_input on
ui_accept/space -> jump to consequences (health 40%, credits N, restore all,
show_kaelen_intro after 1s). Idempotent guard so finish runs exactly once.
Also a safety: if anything errors, a 30s watchdog timer forces HANDOFF —
the game must never be stuck controllerless.

## Checklist (mark as you land each phase; commit per phase)

- [ ] I1: glitch shader + IntroCinematic scaffold (layer/overlay/subtitle/
      watchdog/skip plumbing + finish/restore path) — parse-checked
- [ ] I2: beat timeline (tumble/fling/arrival/data-stream tweens + NOVA
      lines + damage + credits math) — parse-checked
- [ ] I3: UIManager hook swap (new-campaign path only) + changelog/todo +
      commit. Playtest note for user: feel-tune constants at top of
      IntroCinematic.gd (durations, spin counts, damage pct).

House rules: small edits, save+commit per phase, PS5.1 quoting gotchas in
[[project_lounge_social_layer]] memory apply to commits.
