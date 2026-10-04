# Playtest 2026-10-04: findings

Abe is playtesting (first run on the bigger world and the kilometre-scale
stations). Rule for this session: **record and research only; no code
changes until Abe says the playtest has finished.** Each finding: what Abe
saw, what the code says (cause, with file:line), and a proposed fix.

## Findings

### 1. Loading-screen tips change too fast (half the speed)

**Abe:** the tips during the loading screen should cycle at about half the
speed they do now.

**Code:** `UIManager._rotate_loading_tip()` (`scripts/UIManager.gd:~16698`)
shows a new tip every **7 seconds** (hard-coded `create_timer(7.0, ...)`;
the comment above `_build_loading_tips` also says 7).

**Proposed fix:** 14 seconds, as a named constant
(`LOADING_TIP_SECONDS := 14.0`), comment updated. Optionally a short fade
between tips (0.4 s) so the change reads calmly. Nothing else depends on it.

### 2. Docking at a new station loses the mouse (Esc needed to get it back)

**Abe:** when docking at the new stations he loses mouse control; he has to
hit Escape to open a different menu and come back for it to return.

**Cause (from the code):**
- Holding the right mouse button and dragging orbits the camera; that
  captures (hides and locks) the mouse (`PlayerShip._unhandled_input`,
  `PlayerShip.gd:~1040`, `Input.set_mouse_mode(MOUSE_MODE_CAPTURED)`), and
  the **button release** is what frees it again (`:~1024`).
- When the tractor takes the ship the player is docked at once
  (`UIManager.begin_docking_procedure`, `ship.set("is_docked", true)`), and
  `_unhandled_input` returns early for every event while docked
  (`PlayerShip.gd`, top of `_unhandled_input`). So if the right button is
  still held at capture, its release is ignored and the mouse stays captured.
  `begin_docking_camera()` doesn't free it either (only the combat camera and
  `end_docking_camera` call `_release_mouse_capture`).
- Escape works because the pause handler always sets the mouse visible
  (`UIManager._on_pause_changed`, `:~4407`).
- Why now: the approach to a big station is long and looking around while
  flying in is natural; the old station's few-second approach made it rare.

**Proposed fix:**
- `begin_docking_camera()` (and the start of the docking procedure) calls
  `_release_mouse_capture()`.
- In `_unhandled_input`, before the docked early return: a right-button
  release while `rmb_dragging` still frees the mouse.
- Also free it whenever the dock menu opens (`toggle_dock_menu`), as a belt
  and braces.
- Test: in the dock smoke, set the mouse captured and `rmb_dragging` before
  capture; after docking the mouse mode is visible.

### 3. "New route available" on the first dock of the next system, after only the tutorial

**Abe:** Kaelen's new-route offer showed up on his first dock in the new
system, with only the tutorial job done in the last system.

**Cause (confirmed):** Kaelen's route offer needs **3 completed contracts**
(`GateDiscoveryManager._is_kaelen_offer_ready`, `:~189`,
`QuestManager.get_completed_count() < 3`). That count parses
`user://quest_history.md`, which is **one file for every campaign ever
played** (Abe's has 553 lines). So on Abe's machine it is always far past 3,
and the offer only waits for its 15-minute clock. Two other places already
dodge this exact trap with comments (`StoryManager.gd:~93`,
`UIManager.gd:~15008`); `GateDiscoveryAction.gd:~86` (gate actions that
require N missions) has the same bug.

**Proposed fix:**
- A per-campaign count in `story_state` (e.g. `contracts_completed`),
  incremented on `quest_completed`, and `QuestManager.get_completed_count()`
  returns it (the global log file stays a log, never a counter). Both callers
  then work per campaign.
- Check the threshold reads right for the design: 3 contracts before Kaelen
  sells routes. (Also worth a look: should she wait until the ship can use a
  deeper gate, i.e. Shields Mk II for Class II? Ask Abe.)
- Test: a fresh campaign with a non-empty global history: no route offer
  until 3 contracts in this campaign.

### 4. The first agent job was the fallback job again (+ two new details) — FIXED

**Abe (screenshot):** "Vaeshtalil Pilgrim Fleet Juno Calder", system faction
contact: "Hey, Vaes? Got a job for you—Courier: Fact Fallback Chapter 1
Visible Pressure to PYRARI WATCH. Pay's 220 SC, but Contacts need a grounded
job while the authored chapter packet's unavailable. You up for it?"

**Cause:** the same leak as playtest 2026-10-03 b **finding 6** (planned,
not fixed yet): with the legacy chapter planner switched off, every campaign
runs on `ChapterNarrativeDirector.fallback_chapter_packet`, whose developer
notes (stake "Contacts need a grounded job while the authored chapter packet
is unavailable", fact id `fact.fallback_chapter_1_visible_pressure`) become
the job's title and pitch. It hits the very first faction-contact job of
every campaign, so it's high priority. Fix plan as in b-6 (rewrite the
fallback in-world, never title from an id, a banned-words guard).

**Two new details in this screenshot:**
1. **"Hey, Vaes?"**: the contact addresses the player by a fragment of their
   own faction's name (Vaeshtalil). The pitch writer is probably given the
   contact's full name "Vaeshtalil Pilgrim Fleet Juno Calder" and treats the
   first word as a person. Fix: give the writer the person ("Juno Calder")
   and the organisation separately; never let a faction name be used as a
   form of address; the player is "Captain" (or Kaelen's "Shiny").
2. **Juno Calder again:** the same person ran the Mirvekvaru Courier Union
   contact in the last session's screenshot, now the Vaeshtalil Pilgrim
   Fleet. The 2026-09-28 rule "one person, one organisation" is enforced only
   within a campaign's registered contacts (`GlobalState._contact_person_taken`).
   Across systems in one campaign it should hold; across campaigns repeats
   are expected (12 x 12 names). Check whether these were the same campaign;
   if so, the uniqueness check misses contacts created for systems not yet
   loaded. Larger name lists would also help.

### 5. On Fly-to, the ship U-turns, then a few seconds later turns back and carries on

**Abe:** the ship keeps turning around 180 degrees, then after a few
seconds turns back around and starts flying to the location again.

**Cause (from the code; tuned for the old world and normal speed):**
- The autopilot follows a smoothed route and aims **90 units ahead** along
  it (`PlayerShip._PATH_LOOKAHEAD`, `:~1715`; `_path_lookahead_target`,
  `:~1938`). At cruise speed (up to 125/s, world-scale step 2) that's under a
  second ahead. On any bend (around a planet or a station's approach sphere)
  the ship can't turn that tightly at that speed: it overshoots, the nearest
  route point and its 90-unit lookahead fall **behind** it, and it steers
  round 180 degrees.
- Once it has strayed **250 units** off the route (`_PATH_OFFCOURSE`) it
  replans from where it is, and the new route points back the right way: it
  turns back. That's the flip-flop.
- Also: routes are only traced **3,000 units** ahead (`_PATH_MARCH_STEP` 50 x
  `_PATH_MAX_STEPS` 60, `:~1712`); in the stretched world most trips are
  10,000-30,000, so the traced route stops short and replans keep happening.

**Proposed fix:**
- Lookahead grows with speed: `max(90, current_speed * 1.5 s)`, so at cruise
  the nose aims ~190 ahead and the bend is taken wide and smooth.
- Cruise only while lined up: scale the cruise multiplier down when the
  heading is more than ~25 degrees off the aim point (slow, then turn, then
  speed up again), like a real autopilot taking a corner.
- Never steer into a reverse turn on a route: if the aim point is more than
  ~100 degrees off the nose, slow to normal speed and take the next point
  ahead instead of turning round.
- Trace routes to the destination at the stretched scale: march step and max
  steps scaled by `WorldScale.TRAVEL` (or a cap by distance, not step count),
  and the off-course threshold scaled with speed.
- Test: the cruise smoke gains a route that bends around a planet and a big
  station's sphere; check the heading never flips more than ~90 degrees and
  the ship arrives.

### 6. New button (Abe's design): "Scan Composition" for rocks in mining range — DONE as a range scan (see 8)

**Abe:** a new button for mining that only shows up when in mining range,
labelled **Scan Composition**; it tells you what resources are in the rock.
It does not work on red rocks.

**Today:** no such button exists. The target window's mining button is gated
by mining reach (`UIManager._apply_mine_reach`, `:~11014`; 75 to enter, with
hysteresis). What a rock holds is already known to the game: its ore type
(`Asteroid.ore_type`, e.g. silicate, ferrite, cuprite, thorium, water ice),
how much is left (`resources` of `max_resources`), and whether it's a red
rock (`tech_seam`); the overview's type column shows the ore after you've
targeted it ("Asteroid · Ferrite").

**Proposed build:**
- A **Scan Composition** button in the target window beside Mine, visible
  only for an ordinary rock within mining reach (same reach rule and
  hysteresis as Mine), hidden otherwise.
- Pressing it: a short scan (about 2 s, the receiver's sweeping-bar readout
  style), then a readout in the target window and the feed: ore type, how
  much is left (m3), its value per m3 here (depth pay included), and whether
  it's claimed. Remembered per rock, so a rescan is instant.
- **Red rocks:** the button shows but answers "Tech-grade seams: too dense to
  read. Send a survey drone in (G)." That keeps the red-rock material a
  discovery (matches the earlier open question in playtest 2026-10-03
  finding 12: the red rock's material stays unknown until you dive).
- Wiki line under Mining. Test: button only in reach, readout matches the
  rock, red rock refuses.
- Ask Abe: should the scan cost anything (a few seconds only, or fuel/power)?

### 7. Mining "back to the old system"? Not a regression (HUD shows only the total)

**Abe:** mining seemed to just fill cargo instead of separating ore types;
then, checking the inventory screen, it shows them correctly ("Silicate 21"
under the cargo hold bar). Possibly misremembered.

**Code check:** nothing in today's commits touched ore. Each rock's ore still
comes from `Asteroid.ore_type_for(persistent_id, GlobalState.system_ore_mix)`
(`Asteroid.gd:30`, `:125`), the mix is still set before the belts spawn
(`GameRoot._refresh_local_faction_looks`, `:~1566`), and `GlobalState.add_ore`
keeps the per-ore amounts (`cargo_ore_types`). What can make it look like the
old system: the HUD's CARGO row (`UIManager.gd:~4387`) shows only the total
("21 / 100 m3"); the breakdown is in the inventory. The belts are now a
packed field on part of the ring (world scale), so one field might be all
or mostly silicate (silicate is the bulk of every mix).

**Proposed (small, optional):** a hover tooltip on the HUD CARGO row listing
the ores in the hold ("Silicate 21 · Ferrite 4"), so you don't have to open
the inventory to see them. Ask Abe if he wants it.

### 8. Fuel Blocks board job: no way to find the ice (playtest ended here) — FIXED (Scan Composition, C)

**Abe:** he took a board job for Fuel Blocks; without a way to find the ice
rocks "it might take years". That is why he asked for a scan (finding 6).
**Revised design (Abe): the scan works in a range around the ship**, scans
every asteroid within X, and the overview then names each one by its ore,
e.g. "Water ice asteroid".

**Cause:** a rock's ore is shown only after you target it ("Asteroid ·
Ferrite"). Ice can be as little as **6% of a belt**
(`SystemProfile.ICE_FLOOR := 0.06`), and Fuel Blocks need water ice
(`GlobalState` fabricate, `FuelScript.ICE_PER_BLOCK`), so finding it means
clicking rocks one at a time. Also, the job is offered even when ice is rare
in the system; it only warns when there is none at all
(`PublicBoardOfferBuilder.gd:~290`).

**Plan (replaces finding 6's single-rock button):**
- **Scan Composition** (target-window button and a key), with a range pulse
  around the ship: every ordinary rock within the scan range gets its ore
  revealed. Remembered per rock id for the system.
- The overview's name column reads "Water ice asteroid", "Ferrite asteroid"
  and so on for scanned rocks (unscanned: "Asteroid").
- A short cooldown; a feed line sums the result: "Scan: 14 rocks · 2 water
  ice, 5 ferrite, 7 silicate".
- Red rocks: "Tech-grade seam: unreadable; send a drone (G)".
- N.O.V.A.'s Fuel Blocks hint and the job text point at the scan.

**Playtest ended by Abe at this point. Agent quest still bugged (finding 4).**

## Fix log

- **6 + 8 (96b1120):** Scan Composition: C or the target window's button;
  320 m pulse, overview names scanned rocks ("Water ice asteroid"), red rocks
  unread, mining a rock reads it; Fuel Blocks job points at the scan.
- **4:** the fallback chapter packet speaks in-world (rotating stakes like
  "Traffic's been thin and the small runs keep piling up"); job items come
  from an authored pool, never from fact ids; a dev-word guard
  (`StoryAgentOfferBuilder.looks_like_dev_text`) blanks any stake or
  complication that talks about the game's insides; the pitch writer gets
  the contact's own name ("Juno Calder", not "Vaeshtalil Pilgrim Fleet Juno
  Calder") and addresses the player as "you" or "Captain"; contact name
  pools grew from 12 x 12 to 32 x 32 so the same person turns up less.
