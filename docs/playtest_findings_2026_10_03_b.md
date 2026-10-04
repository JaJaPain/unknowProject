# Playtest 2026-10-03 (second session): findings

Abe is playtesting. Rule for this session: **record and research only; no
code changes until Abe says the playtest has finished.** Each finding: what
Abe saw, what the code says (cause, with file:line), and a proposed fix.

## Findings

### 1. **FIXED 2026-10-04** The T receiver mini-game triggers inside the gate jump

**Abe:** the T mini game is triggering inside the gate jump (the jump tunnel).

**Cause (from the code):** the receiver decides "are we flying?" with
`SignalTuningActivity._flying()`
(`scripts/story/activities/SignalTuningActivity.gd:165-175`): not in the
intro cinematic, N.O.V.A.'s world not hidden (title screen / loading panel,
`Nova._world_hidden`, `Nova.gd:404`), and the ship not docked or destroyed.
**Nothing checks the jump**: during the gate jump the ship is neither docked
nor destroyed and the loading panel isn't up, so the receiver can offer a
signal (N.O.V.A.'s line + the "T" prompt) and T can open the tuning panel
mid-tunnel. The jump state lives on GameRoot (`transition_in_progress`,
`jump_request_pending`; `can_begin_jump()`, `GameRoot.gd:~428`).

**Same gap elsewhere (likely):**
- Drone dive (G): `DroneMazeActivity.gd:216` checks only docked/destroyed.
- `NowHorizon` and `UndercurrentNudge` "flying" checks, and `LodestarGuide._calm()`:
  same pattern; a N.O.V.A. line could fire mid-tunnel.

**Proposed fix:**
- One shared "in the world, flying, nothing cinematic" check, e.g.
  `GlobalState.player_can_act()` (or a GameRoot helper `is_jumping()`
  exposed through GlobalState), that is false while
  `transition_in_progress or jump_request_pending`, docked, destroyed, the
  intro cinematic, the title or loading screen. Use it in the receiver
  (offer, T, and the tuning panel: close it if a jump starts), the drone dive
  (G), NowHorizon, UndercurrentNudge and the Lodestar guide.
- An offer made just before a jump: hold the T prompt until after arrival
  (or drop it; a signal from the old system shouldn't follow you).
- Test: start a jump in the jump smoke test, try T and G mid-tunnel, check
  nothing opens and no offer is made.

### 2. Where is the Loose ends board? (Abe asked where the player sees it)

**Where it is today:** only inside a docked **main station's Public Board**:
a button at the bottom of the board, under the job list, reading
"Loose ends (N noticed, M pinned) · Lodestar x/5" (`UIManager.gd:2153`,
`loose_ends_btn`, inside the public board panel; text set by
`_refresh_loose_ends_button`). It stays **hidden until** the pilot has
noticed a thread or heard of the Lodestar. It opens the pin board
(`scripts/ui/PinBoardPanel.gd`) with two tabs: Loose ends and the
Lodestar log.
- Not reachable in flight, not at outposts (they have no public board), and
  not from the pause menu or HUD.
- The only pointers to it: the gold "NEW LEAD" banner ("Added to your Loose
  ends board ... Check it on any station's job board", `UIManager.gd`
  `_poll_loose_end_rewards`) and the wiki entry "loose_ends".

**Likely problem:** it's buried; a player who missed the banner won't find
it, and the Lodestar log (the long goal) is hidden in the same place.

**Proposed fix (for Abe to choose):**
- A **LOOSE ENDS** button in the pause menu (next to WIKI) and/or a HUD
  button under Inventory / Star Map (like the new wiki button), visible once
  there's anything on it, opening the same board in flight (read-only
  pinning is fine anywhere).
- The star map's Lodestar wedge tooltip says "Lodestar log: Esc > Loose
  ends", and clicking the wedge opens the log tab.
- Keep the public-board button too.
- Pulse it gold when a new loose end or bearing lands (same treatment as
  the wiki button).

### 3. Is the Loose ends board per system? (Abe asked)

**Answer: no, it's campaign-wide.** `PremiseDirector.main_story_threads()`
(`scripts/story/premise/PremiseDirector.gd:~495`) lists every thread the
pilot has seen anywhere in the campaign (the main story's "seen threads"),
each tagged with where it was noticed; the board shows "Noticed in <system>,
day N" under each one (`PinBoardPanel.gd:223`). The same board opens from any
main station. The Lodestar log tab is campaign-wide too.

**Bug found while checking:** the system name comes from `_system_names`, a
cache filled only when a system is profiled this session
(`PremiseDirector.gd:61`, `:127`) and **not saved** (`to_dict()` saves only
`state`, `:101`). After loading a save, threads noticed in other systems read
**"Noticed in this system"** until you revisit them, which is wrong and
would make it look per-system. Same cache feeds radio lines, history notes
and the Showrunner request (`:240`, `:433`, `:569`).

**Proposed fix:**
- Store the system's display name on the arc/thread when it's created (or
  save `_system_names` in `to_dict()` / `load_from_dict()`), and fall back to
  the registry's display name for the system id, never "this system".
- Board: group or sort threads by system (newest first), with a small
  header per system, so it reads as one campaign board with places on it.
- Test: notice a thread, save, load, open the board elsewhere: it names the
  right system.

#### 2b. Abe's decision: the pause menu, not the board

**Abe:** a pause-menu button for Loose ends makes more sense than the board;
then N.O.V.A. can comment on it at some point.

**Plan:**
- Move it: a **LOOSE ENDS** button in the pause menu (next to WIKI), visible
  once there's anything on it, pulsing gold when a new lead or bearing lands
  (same as the wiki button). It opens the same board (Loose ends + Lodestar
  log tabs) anywhere: flying, docked, at outposts. Pinning works from there.
- Remove the button from the Public Board (one home, as Abe said).
- Repoint every mention: the "NEW LEAD" banner ("Added to your Loose ends
  (Esc > Loose ends)"), the wiki entry "loose_ends", the Lodestar wedge
  tooltip ("Lodestar log: Esc > Loose ends"), and N.O.V.A.'s NowHorizon
  "loose_end" lines (`scripts/story/NowHorizon.gd`), which currently say
  "on the board".
- **N.O.V.A. comments on it** (lines for Abe's review, small batch): e.g.
  - the first time a lead lands: "I've started keeping a list of things
    that don't add up. Esc, Loose ends. It's getting longer."
  - occasionally when idle with unpinned leads (through NowHorizon):
    "Three loose ends and not one of them pinned. I'm not judging. I'm
    filing."
  - when a pinned thread's system is the one we just arrived in: "This is
    where that pinned lead came from. Just saying."
  Rare, once each, cooldowns like the undercurrent nudges.

### 4. Hand-hold the first loose end

**Abe:** we should hand-hold the loose end that comes in (the first one), so
the player understands where to find them and what, in general, they're for.

**Today:** a new lead gets the gold "NEW LEAD" banner ("Added to your Loose
ends board (N noticed). Check it on any station's job board.",
`UIManager._poll_loose_end_rewards`) and unlocks the wiki entry
"loose_ends", which explains it well: odd details from the receiver, flight
recorders or jobs; pin the ones you think connect; pinned notes weigh on who
the story settles on; the board never says which matter until the truth
comes out (`wiki_entries.json:326`). Nobody tells the player any of that at
the moment it happens.

**Proposed (first lead only, once per campaign; with 2b's pause button):**
1. The banner, then the pause menu's **LOOSE ENDS** button pulses gold.
2. A few seconds later N.O.V.A. explains it in two short lines, e.g.:
   - "That one goes on the list. I keep the odd details we pick up: Esc,
     Loose ends."
   - "Pin the ones you think connect. Some will. Some are just noise. We
     won't know which until it all comes out."
   (Lines for Abe's review. Stays clear of the fixed-cast canon: no hint at
   who or why, only that some threads connect.)
3. The first time the board is opened: a short intro strip at the top of
   the board, dismissable: "Things you've noticed that don't add up, and
   where. Pin the ones you think connect: pinned ones weigh most when the
   story settles. Some are dead ends; you'll find out which. Your Lodestar
   log is the other tab."
4. Until the board has been opened once, N.O.V.A. gives one gentle reminder
   (after a few minutes, not in combat): "That loose end is still waiting
   in Esc, Loose ends."
- Test: a first-session-style smoke that adds a thread and checks the
  banner, the pulsing pause button, N.O.V.A.'s queued lines, and the intro
  strip on first open (not on the second).

### 5. Call it the "systems menu" when she talks about it (not "Esc")

**Abe:** N.O.V.A. should call it the **systems menu**. On PC it's Esc, but
with a controller or on a Mac it may be different.

**Today, player-facing text that names the key:**
- `scripts/ui/Wiki.gd:137`: "New entry: X. Esc > Wiki to read it any time."
- `scripts/ui/Screenshots.gd:103`: "Screenshot saved: ... (Esc > Gallery)."
- `scripts/UIManager.gd:1226`: wiki HUD button tooltip "also Esc > Wiki"
  (added today).
- The pause screen's own title says "GAME PAUSED" (`UIManager.gd:2625`); the
  controls list shows "PAUSE / Esc" (`:2670`). The wiki already has a key
  token for it (`wiki_entries.json:49`, control "pause", keyboard "Esc";
  entries use {tokens}, filled per device by `Wiki.gd`).
- Planned lines in findings 2b/4 said "Esc, Loose ends": change before
  building.

**Proposed fix:**
- **Spoken lines (N.O.V.A. and anyone voiced):** always "the systems menu"
  ("It's in the systems menu, under Loose ends."), never a key.
- **Written UI text:** "Systems menu > Wiki", optionally with the device's
  key from the wiki's {pause} token ("Systems menu ({pause}) > Wiki"), so
  controller/Mac labels come for free when controller support lands.
- Retitle the pause screen **SYSTEMS** (subtitle "GAME PAUSED" can stay
  under it) so the name matches what she says. (Ask Abe whether he wants
  the screen title changed too.)
- Update findings 2b and 4's lines to "the systems menu".
- Test: a grep-style test that no player-facing string or N.O.V.A. line
  contains "Esc >" or "Esc," (comments and the controls table excepted).
- **Abe (decided):** yes, retitle the pause screen **SYSTEMS** for
  consistency. Note: Abe will often still say "pause menu" out of habit;
  treat "pause menu" from Abe as the systems menu.

### 6. A faction contact's job shows developer fallback text ("Fact Fallback")

**Abe (screenshot):** a system faction contact (Mirvekvaru Courier Union,
Juno Calder) says: "The 'Fact Fallback' chapter packet is temporarily
unavailable for delivery due to system instability. Contacts need a grounded
job while the authored chapter packet is unavailable." Is this a fallback?

**Yes: internal text leaked to the player. It's systemic, not a one-off.**
- The old ("legacy") chapter planner is switched off, so on every campaign
  start the game commits a **procedural fallback chapter packet** (log:
  `fallback type=chapter_plan reason=legacy_chapter_plan_disabled`, lines
  244 and 859; `GameRoot._commit_fallback_chapter_plan`, `GameRoot.gd:~3973`).
- That packet (`ChapterNarrativeDirector.fallback_chapter_packet`,
  `scripts/ai/ChapterNarrativeDirector.gd:162-224`) is written as notes for
  developers: stake "Contacts need a grounded job while the authored chapter
  packet is unavailable.", thread "A local pressure thread keeps missions
  grounded until the chapter plan refreshes.", premise "...while the larger
  story plan recovers.", and ids like `fact.fallback_chapter_1_visible_pressure`.
- Those fields feed the faction contacts' jobs (the beat's stake reaches the
  quest's causal contract, `QuestCausalContractCompiler.gd:139`, and the
  contact's pitch), and the model turned them into dialogue. An item/title is
  also built from the fact id: the log shows a job accepted earlier as
  **"Courier: Fact Fallback Chapter 1 Visible Pressure"** (log line 957).
  So every campaign's faction-contact jobs can carry this text.

**Proposed fix:**
1. Rewrite the fallback packet as **player-facing, in-world** text (it's
   what every campaign actually runs on now): e.g. stake "The local crews
   are short of pilots and the work is piling up.", thread "Trouble on the
   local lanes", fact "Contacts here are nervous about the routes.", ids
   that never become text.
2. Never build a title or item name from an internal id
   (`fact.*`, `thread.*`, `beat.*`): find where "Fact Fallback Chapter 1
   Visible Pressure" was made and use the beat's public text or a proper
   item name instead.
3. A guard: a validator rejects any player-facing job text containing
   "fallback", "chapter packet", "authored", "fact_", "thread.", "beat.",
   "packet", and falls back to an authored line. Add those to the
   secret-leak-style scan of generated text.
4. Longer term (ask Abe): retire the legacy chapter-packet path, or let the
   premise director (which now drives the main story) supply the contacts'
   stakes instead.
- Test: start a campaign with the planner disabled (as now), generate a
  faction contact's job, and check no field contains the banned words.

### 7. Docking at an outpost: did the main station's beam pull the ship?

**Abe:** not sure, but he thinks the outpost used the main station's tractor
beam to move him; it happened too quickly to see where it came from.

**What the code does (not confirmed either way yet):**
- Docking: `PlayerShip` "DOCK" mode calls `begin_dock_tractor(self)` on the
  **targeted** station (`PlayerShip.gd:~1297-1305`); the outpost's version
  (`OutpostStation.gd:148`) hands itself to
  `UIManager.begin_docking_procedure(station, ship)`, which builds the beam
  with `configure(station, ship)` (`UIManager.gd:~4448`) and pulls to that
  station's `get_docking_position()`. So by the code the beam should come
  from the outpost's own centre.
- New since this morning: station **traffic** also uses beams
  (`TrafficDirector`, finding 5 of the first session). A freighter being
  pulled into the main station, or pushed out, while he docked could have
  put a second cyan beam on screen from the main station.
- The beam starts at the station node's origin. If an outpost model is
  offset from its node, the beam could look like it comes from empty space
  or a different structure.

**Proposed next step (after the playtest):**
- A windowed snapshot mid-pull while docking at an outpost (beam endpoints
  printed), plus one with traffic running, to see which it was.
- Make the source unmistakable either way: a bright emitter flare at the
  station end of the beam, a slightly thicker beam, and the docking panel
  naming the station ("CALARI BEACON // DOCKING CONTROL" already does;
  check it said the outpost).
- If traffic beams cross the player's view near docking, keep them dimmer
  than the player's own beam.

### 8. The green targeting circle draws over the player's ship and the HUD

**Abe (screenshot):** targeting Greywake Station, the green circle passes
over his own ship and over the target window; it should always be behind
those, never in front.

**Cause:**
- The circle is `selection_marker`, a 2D `Control` drawn by
  `UIManager._on_selection_marker_draw()` (`UIManager.gd:~11649`), placed
  each frame at the target's screen position
  (`_update_selection_marker_position`, `:~11607`) with a radius from the
  target's size.
- It's added to the UI **after** the HUD panels (`UIManager.gd:601-605`,
  inside `_ready`, after the HUD/target/overview panels are built), so it
  draws on top of them (the target window in the screenshot).
- Any 2D overlay draws on top of the whole 3D view, so it can never go
  behind the player's ship. A big target (a station) close by makes a big
  circle that crosses the ship.

**Proposed fix:**
1. **HUD:** put the circle (and `target_marker`) in their own CanvasLayer
   **below** the HUD layer (or move them to the first children of the UI
   root), so every HUD panel always covers them.
2. **The ship:** draw the circle in the 3D world instead: a camera-facing
   ring (unshaded, depth-tested, no shadows) placed on the target, nudged
   toward the camera by the target's radius so the target itself doesn't
   hide it, and scaled to the same on-screen size as now. Then anything
   nearer the camera, the player's ship included, naturally covers it.
   The off-screen/behind-camera hiding stays as now.
   - Simpler fallback if the 3D ring has issues: keep it 2D but cut out the
     player ship's screen rectangle (a mask from the ship's projected AABB).
3. Same treatment for the drone-cam reticle and the target marker if they
   show the same overlap.
- Check: a windowed snapshot targeting a nearby station from behind the
  ship (like the screenshot): the ring sits behind the hull and under the
  target window.

### 9. Assessment: wiring ChatGPT's two new stations into the game (Abe asked)

Measured (`.tmp_godot_user/measure_stations.gd`):

| Model | Size (m) | Triangles | Berths |
|---|---|---|---|
| Cinder Anchorage (LOD1) | 2015 x 951 x 2015 | 124k (full: 394k) | 24 `Dock_*` |
| Meridian Exchange (LOD1) | 1808 x 2017 x 1808 | 144k | 24 `Dock_*` |
| Today's station (`space_station1.glb`) | 53 x 53 x 56 (x5 in game = ~270) | 6.5k | 0 |

Player ship collision is 4.8 x 4.5 x 8 m; the berths are built for it, so the
stations can't simply be scaled down to today's size (the berths would be
smaller than the ship).

**Problems, biggest first:**
1. **World scale.** A whole system fits in `SystemFactory.SYSTEM_RADIUS`
   2500 m (5 km across); planets are 150-550 m radius
   (`SystemFactory.gd:172`); stations get 200 m clearance (`:34`) and orbital
   ones sit 150-350 m past a planet's clearance (`:289`). A 2 km station is
   bigger than every planet and 40% of the system's width; orbital placement
   would put it through the planet. Needs a scale decision (below).
2. **Collision cost.** The test scene makes trimesh collision for every mesh
   (124-144k triangles each); two per system plus traffic is heavy for
   physics. Needs a simplified collision (a few convex hulls / boxes per
   section) built once.
3. **Load time and size.** 19-40 MB GLBs loaded at runtime through
   GLTFDocument (no import). Should be imported normally, LOD1 by default,
   the full model only up close (Godot visibility ranges).
4. **Docking code assumes one berth at the centre.** Today: one
   `get_docking_position()`, tractor capture at 72 m
   (`PlayerShip.DOCK_TRACTOR_CAPTURE_RANGE`), beam from the station's centre
   (it would run 1 km through the hull). The test scene's `HarborStation.gd`
   already does it right (berth nodes, reservations, approach point above the
   berth, beam from the berth); that has to move into `Station.gd`, plus
   traffic (`TrafficDirector`) using the berths.
5. **Autopilot / obstacles.** `ObstacleBounds` sizes obstacles from the
   visual AABB: a 1 km+ sphere around a station whose berths are on its
   edge. Approach must route to the berth's approach point, not the centre.
6. **Everything measured to the centre:** overview distances ("2,000 m" with
   the hull beside you), the targeting ring (finding 8), safe zone 250 m
   (`GlobalState.SAFE_ZONES`), station traffic's 350 m tractor range, NPC
   leash/notice ranges near stations. Should measure to the hull (nearest
   point of the simplified collision).
7. Smaller: the rotor animation (the test stops the GLB animation and spins
   `Habitat_Rotor` itself), StationLights tuned for small stations (the test
   rescales its drones), the dock camera framing, outposts (stay small?).

**Scale options (Abe to choose):**
- **A. Grow the world** (recommended if these are the look): systems ~5x
  wider, planets ~5-10x bigger (km-scale), stations placed with km
  clearances. Travel takes longer, so ship speeds/boost and
  fuel-per-distance need retuning (and the Lodestar landmark, anomaly and
  belt placements scale with it). Biggest change, best result.
- **B. Capital stations only:** use them as main stations of deeper / bigger
  systems, keep small stations and outposts elsewhere, enlarge only those
  systems' planets and clearances. Contained, but scale feels inconsistent
  between systems.
- **C. Scale them to ~0.4** (800 m): only if the berths are re-sized for it
  (re-export with berths scaled up); otherwise the ship doesn't fit.
- In all cases: imported LODs, simplified collision, berth-based docking
  from the test scene moved into Station.gd, distances to the hull.

#### 9b. Abe's direction (insight only, no changes yet)
- Abe loves the look; they're for **main stations only, never outposts**
  (explains why mains have repair bays, ore storage, refining, lounges).
- The world feels cramped: consider making systems bigger and speeding up
  travel so trip times stay what they are now.
- **One scale for everything:** whatever factor is chosen (5x was only an
  example) applies to every system equally, never per system. Notes: the
  hand-made start system scene must scale too; (no save conversion needed: Abe deletes saves between playtests;
  was: one-time conversion); ships, asteroids, stations keep their real size and
  close-range numbers (combat 80 m, docking 72 m, mining, weapons) stay;
  planets probably grow with the world; pick the factor by looking at a test
  system at 3x / 5x / 8x; a cruise speed for long hops keeps trip times.
