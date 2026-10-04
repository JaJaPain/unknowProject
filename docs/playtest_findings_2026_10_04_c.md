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

### 3. Undocking: Dock Control should speak ("hold steady...")

**Abe:** when undocking, the NPC who docked you should say something like
"Hold steady, ship's control will be returned to you once outside of our
safety zone."

**Code:**
- Docking already has this voice. `_play_dock_clearance` (`UIManager.gd:~4486`)
  picks one of 20 `DOCK_CLEARANCE_LINES` ("{call}, you are cleared for
  docking. Hold steady..."). It speaks it through `SpeechService` in the
  station's own voice (`_dock_clearance_voice_for_station`: stable per
  station, the same voice every time) and posts it to the feed as
  "Dock Control".
- Undocking says nothing. `_push_out_of_berth` (`UIManager.gd:~10661`) runs the
  beam push out past the approach sphere and hands control back silently.
- Timing to watch: on the first undock with the starter contract,
  N.O.V.A.'s target tip (`_maybe_play_intro_repair_target_tip`) also plays
  right after undock. The two must not talk over each other: Dock Control
  first (the push takes ~4-10 s), N.O.V.A. after control is back.

**Proposed fix:**
- `DOCK_DEPARTURE_LINES`: an authored pool like the docking one, ~20 lines
  with {call}, matter-of-fact and a few dry, all saying the same thing:
  hold steady, the beam takes you out, control comes back past the safety
  zone. Spoken in the same station voice when the push starts, posted as
  "Dock Control". In player text the sphere is the station's "safety zone"
  (Abe's word).
- Optional short second line when the beam lets go ("{call}, you're clear.
  Controls are yours."), so the hand-back is heard as well as felt. Ask Abe.
- Lines for Abe's review in short batches (first 6 below, provisional):
  1. "{call}, hold steady. We'll walk you out on the beam; controls come back once you're past our safety zone."
  2. "Dock Control to {call}: releasing clamps. Hands off until you clear the safety zone."
  3. "{call}, you're on the outbound beam. Stay put; the ship is yours again at the edge of our zone."
  4. "Clamps released, {call}. We'll carry you out. Don't fight the pull, it never ends well."
  5. "{call}, departure logged. Hold position while the tractor clears you from the station."
  6. "Dock Control to {call}: outbound lane is clear. Controls return past the safety zone."
- Test: the dock smoke hears one departure line per undock, in the
  station's voice, before control returns. The intro tip waits until
  after it.

### 4. Undock: controls come back before the ship is outside the safety zone

**Abe:** on the same undock change, control should not be returned to the
ship until it's outside the safe zone.

**Code:**
- The undock push is meant to hold control: `_push_out_of_berth`
  (`UIManager.gd:~10661`) keeps `is_docked = true` while the beam carries
  the ship to 250 past the approach sphere (the "safety zone"), and only
  then clears it.
- But `is_docked` only blocks the ship's **own** input
  (`PlayerShip._unhandled_input` returns early: mouse fly-to, RMB, Q/W/E,
  Space).
- **HUD orders aren't blocked.** The target window's Approach / Orbit /
  Mine / Attack / Dock buttons and the overview call
  `_command_selected_target` → `PlayerShip.begin_target_navigation()`. That
  accepts orders while docked, and `_physics_process` steers and
  `move_and_slide()`s whenever `nav_mode != "MANUAL"`, with no docked
  check. So any HUD order during the push flies the ship at once, fighting
  the beam's tween: control is effectively back inside the zone.
- `undock_player` also sets `nav_mode = "MANUAL"` right after starting the
  push, which is fine. The same hole exists during the docking pull-in.
- The HUD (target window, overview) is fully live during the push.

**Proposed fix:**
- One "beam has the ship" rule. While `is_docked` (and during the
  push and pull), `begin_target_navigation`, fly-to and every nav entry
  refuse, with one HUD line: "Dock Control has the ship until you're clear
  of the safety zone." `_physics_process` skips steering and
  `move_and_slide` while docked, so only the beam moves the ship.
- Any order given just before the push is cleared (MANUAL) when the beam
  lets go.
- The hand-back is clear: the beam lets go outside the zone, with Dock
  Control's release line (finding 3) and the HUD hint "Controls returned".
- Test: in the dock smoke, issue an Approach order mid-push. The ship stays
  on the beam's line and ends outside the sphere; after the release, orders
  work.

### 5. Scan bubble: looks full-size at once, and its edge can't be seen

**Abe:** the scan bubble needs to grow more slowly; it looks full size
instantly. The sound is good. It might be too big: he can't see its edge.

**Cause (`scripts/effects/ScanBubble.gd`):**
- **Too fast where it matters:** it grows over 1.6 s with a *cubic ease-out*
  to 1,600 units (`OreScan.RANGE`, 320 m displayed). Ease-out does most of
  its growth at the start: by 0.3 s it's ~750 units across. The camera sits
  6-50 units from the ship (`PlayerShip` zoom), so in well under half a
  second the shell is far past the camera and reads as "instantly full".
- **The edge is invisible from inside:** the shader is a soap-bubble rim
  (alpha from `1 - |N·V|`). The rim shows only where you look along the
  surface, which is from outside. From inside, near its centre (always, for
  a 1,600 sphere and a 50 m camera), every part of the shell faces you
  head-on, so the rim is ~0 and only the 1.2% tint remains. The snapshot I
  checked was taken from outside, which is why it looked right.

**Proposed fix:**
- **Slower, steady growth:** ~3.5 s, linear or gentle ease-in-out, so the
  front visibly travels outward past the camera and across the belt.
- **A front you can see from inside:** a bright band at the expanding edge,
  visible from any angle (in the shader: brightness from where the
  fragment sits on the sphere, not from the view angle). Plus a faint ring
  where the shell cuts the ship's plane, so you watch it sweep across the
  rocks to the scan's edge. Then it holds a moment at full size and fades.
- **Rocks ping as the front reaches them:** each scanned rock flashes
  briefly when the wave passes it, and its overview name changes then, not
  all at once. That shows the scan's reach without seeing the whole sphere.
- **Size:** the bubble shows exactly what's scanned, so making it smaller
  shrinks the scan. **Ask Abe:** keep 320 m with the visible front and
  ring, or a smaller scan (e.g. 200 m)?
- Check from the gameplay camera (inside), not an outside snapshot.

### 6. The docking tractor beam should sound like the asteroid tractor

**Abe:** the tractor beam should use the same sound as when we tractor an
asteroid.

**Code:**
- The asteroid tractor plays `res://sound/Mining/TractorBeam.mp3` (4.8 s) as
  a positioned loop: `AudioManager.start_tractor_loop(pos)` and
  `stop_tractor_loop()`, -4 dB, on the shared 3D `tractor_player`
  (`PlayerShip.gd:~2343`, when the mining tractor engages). It loops by
  restarting from `_on_mining_loop_finished`.
- **Every station beam is silent:** `DockingTractorBeam`
  (`scripts/effects/DockingTractorBeam.gd`) has no audio. It's used for the
  player's dock pull (`UIManager.gd:~4470`), the undock push (`~10668`) and
  NPC traffic docking (`TrafficDirector`). The docking procedure plays no
  sound either.

**Proposed fix:**
- `DockingTractorBeam` owns its own `AudioStreamPlayer3D` with the same
  TractorBeam stream, looping while the beam exists. It sits at the ship end
  and stops (short fade) when the beam is freed. Every station beam then
  sounds the same as the mining one: the player's dock and undock and NPC
  traffic (heard from nearby only, by 3D distance falloff). It needs its
  own player, not the shared mining `tractor_player`, so traffic beams and
  mining never cut each other off.
- Set the stream to loop (or restart on `finished` like the mining loop).
- Player's own dock and undock beam at -4 dB like mining; traffic beams
  quieter (-10 dB) with a short max distance.
- Test: the dock smoke checks that a beam's audio player is playing during
  the pull and push, and stops after.

### 7. Autopilot still does 180-degree turns ("Obstruction cleared. Resuming direct course")

**Abe:** still a lot of 180-degree turns, with "navigation obstruction
cleared, returning to...". It gets the job done, but the 180 looks bad. Can
we stop it?

**What the message means:** `_emit_navigation_obstruction` ("Direct route
obstructed by X. Plotting a safe orbital bypass.") fires when a replan finds
something in the straight line. `_emit_navigation_route_clear` ("Obstruction
cleared. Resuming direct course.") fires when a later replan finds the
straight line clear again (`PlayerShip.gd:~2087-2118`). So each 180 is a
detour that a later replan drops: turn away, then turn back. The fix from
playtest 2026-10-04 finding 5 (full-length routes, speed-scaled lookahead, no
aiming behind) handled the "route ran out" case. These come from replans
that change the plan itself.

**Likely causes (from the code; needs a repro to rank them):**
1. **Inside a keep-out sphere, the exit is radial.** When the ship is
   already inside an obstacle's keep-out (body + margin), TangentNavigator
   steers to an exit waypoint pointing mostly *away from the obstacle's
   centre* (`exit_waypoint`, `EXIT_OUTWARD_BIAS 1.0` vs `EXIT_AROUND_BIAS
   0.55`). With the obstacle ahead, that's a turn of up to 180. Once out,
   the next replan finds a bypass or a clear line and turns back.
2. **Planets' keep-outs are now kilometres wide.** A planet's navigation
   radius includes its ring and belt (`navigation_clearance_radius = ring +
   width/2 + 90`). The rings were stretched ×5 with the world (start gas
   giant ~4.4 km), so routes to anything near a planet (belts, outposts,
   orbital stations, the gate) start or end inside or near these spheres,
   which feeds cause 1. The corridor exception only covers stations and
   rocks orbiting that same planet (`_get_navigation_clearance_for_destination`).
3. **Moving ships count as route obstacles** (`"ship"` is in
   `_TANGENT_OBSTACLE_GROUPS`). Traffic now cruises at up to ×5. A freighter
   crossing the line gets a bypass; it moves on; "cleared"; turn back. The
   nose whisker (55 u) also forces replans near traffic and belt rocks.
4. **No hysteresis:** every replan picks a side or a straight line afresh, so
   alternating plans aren't damped.

**Proposed fix (after the playtest):**
- **Repro first:** a "route tour" smoke in the start system and a generated
  one. Undock at each station, fly to every other station, outpost, gate,
  belt and a few rocks, at cruise. Record the largest heading reversal and
  every obstruction/cleared pair. Rank the causes from that.
- **Never turn more than ~100 degrees from the goal to get around
  something:** inside a keep-out, exit along the tangent on the goal's side
  (slide round), not straight out. If the goal is really behind, make a
  wide banked turn, never a pivot.
- **Hysteresis:** keep the chosen bypass side until clearly past the
  obstacle. Don't drop a detour for "direct" until the direct line has been
  clear for ~2 s and the turn back is under ~45 degrees. The notices follow
  the same rule.
- **Moving ships aren't route obstacles;** they're handled locally (a small
  sidestep from the whisker), never by a full replan.
- **Re-check celestial keep-outs** after the stretch: bound the
  ring-inclusive radius for routing past a planet (the belt is a field on
  an arc now, not a full ring) and widen the corridor exception to
  anything near the planet.
- Test: the route tour asserts no heading change over ~100 degrees between
  consecutive frames-in-a-second windows, and at most one obstruction
  notice per trip.
