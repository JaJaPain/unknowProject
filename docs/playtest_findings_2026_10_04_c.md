# Playtest 2026-10-04 (c): findings

Abe's third run today: a fresh campaign after the stinger and 35% fixes.
Rule: **record and research only; no code changes until Abe says the
playtest has finished.**

## Findings

### 1. Mouse and controls work during the intro; they should be off until the "look around" hint — FIXED

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

### 2. Get the ship's drones moving as soon as we're out of the gate — FIXED

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

### 3. Undocking: Dock Control should speak ("hold steady...") — FIXED

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

### 4. Undock: controls come back before the ship is outside the safety zone — FIXED

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

### 5. Scan bubble: looks full-size at once, and its edge can't be seen — FIXED

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

### 6. The docking tractor beam should sound like the asteroid tractor — FIXED

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

### 7. Autopilot still does 180-degree turns ("Obstruction cleared. Resuming direct course") — FIXED

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

### 8. Lag: N.O.V.A. said a tunnel line after we were out of the tunnel — FIXED

**Abe:** with lag, N.O.V.A. used her "stuck in the tunnel" line when we were
already outside it.

**Code (`scripts/story/IntroCinematic.gd`):** the tunnel lines are
NOVA_LINE_1 ("Hold on, Captain!..."), 1A ("I almost got it.") and 1B
("ALMOST!"). Each goes through `_nova_line_after_voice_ready`:
- It waits up to 45 s for TTS to be free (`_speech_ready_for_intro`), then
  calls `SpeechService.play(text)` and waits for playback with
  `_wait_for_nova_playback`.
- That wait isn't tied to *her* clip. It watches TTSInterface's global
  `is_requesting` / `audio_player.playing`, so any other request (a
  background cache job) counts as "her voice" and ends the wait when it
  finishes. If nothing is seen at all, it gives up after 18-36 s.
- Then the timeline moves on to the fling out of the gate. Her clip is still
  queued in SpeechService and plays whenever synthesis catches up: outside
  the tunnel.
- Nothing cancels a pending tunnel line at the fling, and `_finish()` doesn't
  either.
- Today's run had extra load: the Ollama restart and new-game generation
  compete with Kokoro TTS. The intro lines are meant to be pre-cached
  (`cache_nova_voice_lines`), but if the cache wasn't done, each line is
  synthesized live.

**Proposed fix:**
- **A line belongs to its moment:** when the intro moves past a beat (the
  fling ends the tunnel), any of that beat's lines not yet *started* are
  dropped (`SpeechService` cancel/stop for those texts). A late tunnel line
  never plays in open space.
- **Wait for her clip, not any audio:** track the specific request
  (SpeechService play id or a finished signal for that text) instead of
  TTSInterface's global flags.
- **Pre-cache gate:** the loading screen already waits on TTS. Make sure the
  intro's own lines are cached before the cinematic starts (they're few and
  fixed). If not, start the intro and let lines that can't be ready in time
  drop, rather than shift.
- Same rule for arrival lines 2-4 relative to the hand-back: none of them
  may play after `_finish()`.

### 9. First dock in the new system: "No vetted contract is ready yet", and it never would be (SERIOUS) — FIXED

**Abe (screenshot):** first dock in the new system, Kaelen's panel says "No
vetted contract is ready yet. Kaelen is lining up work in the background;
check back in a moment." No missions.

**Cause (confirmed from this session's log):**
- When you open Kaelen, `_refresh_agent_quest_board` → `_request_background_agent_quest()`
  (`UIManager.gd:~8032`). It refuses unless `_campaign_story_ready_for_gameplay()`,
  which needs the campaign bible **and a chapter plan for the current
  chapter** (`GameRoot.is_chapter_plan_ready`: a packet for
  `story_state.chapter`).
- This campaign moved to **chapter 2** before the jump (log: the
  `chapter_2` story screenshot, line ~708). `StoryManager.advance_chapter`
  bumps the number, but nothing commits a chapter-2 packet. With the
  legacy planner off, packets are only committed when someone asks:
  the loading screen at startup (chapter 1), or
  `maybe_queue_next_chapter_plan_generation` once 60% of the current packet
  is used up. The chapter advanced without that happening.
- From then on every contract request logs "Deferring background contract
  generation until campaign story is ready." (three times in the log). So
  **Kaelen's agent work is blocked for the rest of the campaign, in every
  system.** "Check back in a moment" is never true.
- The waiting line itself is developer text: Kaelen speaks about herself in
  the third person ("Kaelen is lining up work"), and says "vetted contract".

**Proposed fix (priority):**
- `advance_chapter` (or GameRoot listening to it) makes sure the new
  chapter has a packet at once. With the legacy planner off that's
  `_commit_fallback_chapter_plan(new_chapter, ...)`, which is instant.
  Also, on load and on arrival in a system, any missing current-chapter
  packet is committed.
- `_request_background_agent_quest` never dead-ends on a missing chapter
  plan mid-session: if the bible is ready and only the plan is missing, ask
  for it (instant) and carry on.
- Prefetch on arrival: start the agent contract when you arrive in a system
  (or set course for the main station), not on dock, so it's usually ready
  when you open her panel.
- Replace the waiting line with Kaelen's own voice, a small authored pool,
  first person and in character ("Give me a minute, Shiny, I'm still
  shaking the trees here."). The board fills itself in when the job lands
  (the `is_waiting_for_agent_board` path already exists).
- Test: a smoke that advances the chapter, jumps, docks and opens Kaelen
  gets a contract (or a real "no work" reason), never a permanent defer.

### 10. Lounge hunt ("talk them out of the item"): janky, broken, buttons run together — FIXED

**Abe (screenshot):** the new mini-game to talk the item out of someone is
very janky and broken. He couldn't get it to work, and the buttons all run
together. It needs a cleaner way of doing it.

**What the screenshot shows / code (`UIManager._add_lounge_card_buttons`,
`~5960`):**
- Each contact card gets a row of **up to six** buttons squeezed into one
  `HBoxContainer` at 78% of the card's width, font size 8: "Ask about it",
  Drink, Faction, Trouble, (Intel), Work. Each button's minimum width is its
  text, so the row is wider than the card and **spills over the neighbouring
  cards**: rows overlap and interleave (the red outline in the screenshot).
  The row also sits over the Talk button.
- **Overlapping rows steal clicks:** where one card's row lies on top of the
  next card's, a click meant for "Ask about it" can land on the neighbour's
  Work or Drink. That would explain "couldn't get it to work" (to confirm:
  the hunt's own logic, `_on_lounge_hunt_ask`, passes its tests).
- **Names overflow too:** the card title is the full "<Faction> <Person>"
  ("ORORRENVA PILGRIM FLEET KESH ORRIN"), cut off at both ends. The person
  alone ("KESH ORRIN") with the faction on the small second line would fit.

**Proposed redesign (cleaner):**
- **Cards stay simple:** portrait, the person's name, faction and mood on
  the small line, and **one** button: Talk. No action row on the card.
  During a hunt, the card holding nothing gets no marker. The whole lounge
  gets one header line: "Someone here has the Heat Sink. Ask around."
- **Talk opens the conversation panel with a clean, vertical action
  list,** full-size buttons, one per row: **Ask about the Heat Sink**
  (highlighted during a hunt), Buy a drink (cost), Faction, Trouble, Intel
  (when they have it), Work, Leave. Their reply shows above the list, so
  you can work on one person turn by turn (deflect → hint → give), which is
  the whole point of the dry-humour hunt.
- The hand-over (they give it) happens in that panel with a clear "They
  hand you the Heat Sink" and the job's next step.
- Test: a UI test that every card's controls stay inside the card's rect,
  and a hunt smoke: Talk → Ask about it → the pool lines progress and the
  holder gives the item.

## Fix log (Abe ended the playtest)

- **9:** `StoryManager.chapter_advanced` → GameRoot commits the new
  chapter's plan at once; `_request_background_agent_quest` makes a missing
  plan on the spot. Kaelen's waiting line is now her own (provisional pool
  of 6). First-session smoke checks a chapter advance.
- **10:** cards show the person's name, with the faction on the small line.
  At most two buttons, which never grow past the card: "Ask about it"
  (during a hunt) or "Drink", plus a "More" menu (drink, their faction, any
  trouble, heard anything, got work). Hunt replies offer "Press them" and
  "Ask someone else". **The reply line was invisible in the lounge**
  (clipped to zero height); it now wraps to its real height. The
  quest-reach smoke checks every card button stays inside its card and the
  reply choices; `--lounge-shot` saves screenshots (reviewed).
- **3:** Dock Control speaks as the beam carries you out, in the station's
  docking voice (6 provisional `DOCK_DEPARTURE_LINES`). On release the HUD
  says "Clear of the safety zone. Controls are yours." N.O.V.A.'s
  first-undock tip waits for the release.
- **4:** while docked (pull, berth, push) the ship takes no orders, from the
  HUD either: `begin_target_navigation` / `double_click_move` refuse,
  physics doesn't steer or move, and HUD orders get "Dock Control has the
  ship until you're clear of the safety zone." The dock smoke issues an
  order mid-push at every station and outpost.
- **6:** every station beam (dock, undock, traffic) loops the mining
  tractor's hum at the ship's end; traffic quieter and only up close. The
  dock smoke checks the hum mid-push.
- Same at main stations and the new outposts: one code path, checked at
  Greywake, Iron Reach and Kova.
- **1:** while the opening cinematic runs, PlayerShip ignores all input
  and the HUD ignores its keys. Control comes back with "Hold RIGHT MOUSE and
  drag to look around". Space still skips; Esc still opens the systems menu
  (ask Abe whether to lock that too).
- **2:** from the fling out of the gate, the cinematic drives the drones
  (`_update_drones`) until control is handed back.
- Also: `run_intro_handhold_tests` had a stale source check since 31a4107;
  updated to the current rule (tip on first undock, repaired or not).
- **5:** Abe's answer on size: "the 10 or so asteroids near the ship, not
  half the belt", then "a rule of thumb, not exact: a reasonable bubble so
  the player has to scan and move". The scan is a fixed 400-unit bubble
  (80 m displayed): about ten rocks of a start belt (one every ~70 units). It
  grows steadily (2 s), carries a faint grid visible from
  inside, draws a ring where it crosses the ship's level, and flashes each
  rock as the front reaches it. Checked from inside with the gameplay
  camera. Wiki updated.
- **8:** when the ship is flung out of the gate, any tunnel line still
  waiting on its voice (or still sounding) is dropped (`SpeechService.stop()`);
  the same at the hand-back, so no intro line ever plays late. Logged as
  `intro_cinematic/late_line_dropped`. Not done: the playback wait still
  watches TTS's global flags rather than her specific clip (the drop covers
  the symptom).
- **7:** reproduced with `--route-tour-smoke-test` (flies every station,
  outpost, gate and belt pairing; `--tour-pairs=A>B` for chosen trips):
  6 of 15 trips U-turned (worst 158 degrees), always while rounding a planet
  or station. Instrumenting showed no replan at all: the ship was following
  its original route, and the route itself had a hairpin. A traced route is
  short steps round the obstacle then one long leg to the target, and a
  uniform Catmull-Rom spline through points that unevenly spaced loops back
  where they meet. Fix: split long legs to the march step before smoothing
  (`PlayerShip._even_spacing`). Also kept: a fresh plan that would demand a
  U-turn while cruising on a plan that still leads ahead is refused (up to
  4 times), and the nose whisker no longer throws the current plan away.
  Result: 0 of 15 trips U-turn, worst swing 97 degrees (the turn to leave
  a station facing away from the target).
