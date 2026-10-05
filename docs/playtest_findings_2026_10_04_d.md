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

### 2. A ship seen flying backwards

**Abe:** saw another ship flying backwards; needs checking again.

**Code:**
- Under its own engines an NPC can't fly backwards. Every movement branch in
  `NPCShip.gd` sets `velocity = -basis.z * speed` (along its nose: lines
  ~720-813), and it turns toward its target with a basis slerp (`~821`).
- So "backwards" is one of:
  1. **A model mounted back to front:** a ship type whose visual nose points
     +Z instead of -Z would *always* look like it flies backwards, in every
     behaviour. Check each NPC model/kitbash design's forward axis against its
     travel.
  2. **The station beam moving it:** while a beam has a ship
     (`TrafficDirector._tractor_in` / `_push_out`) its engines are off and a
     tween moves it. Arrivals are turned to face the *station's centre*
     (`ship.look_at(station.global_position)`), then pulled to their berth
     point (`entry.dest` = `get_docking_position`, the lane entry). With the
     new outposts that point can be above the station (Crown Haven's pads face
     up) or to one side, so the ship is dragged up or sideways while facing
     the centre: it reads as reversing. Departures face the gate and are
     pushed toward it, so they look right.
- Not the cause this time: the player autopilot's hairpin (fixed in c-7; that
  was the player's ship, and it turned rather than slid).

**Proposed fix:**
- Beam moves: turn the ship to face *along its motion* (or the berth's
  inward lane direction) before and during the pull, never the station's
  centre. Departures already do.
- Model check: a quick test spawns one NPC of each faction and role, moves
  it forward, and compares its velocity with its visual model's nose
  (largest-extent axis / engine-glow markers), flagging any that are reversed.
- **Ask Abe:** where was it (near a station or outpost, mid-fight, out in
  space)? Which faction or kind of ship?

### 3. N.O.V.A.'s jealousy line came out garbled — CORRECTED (Abe asked for it mid-playtest)

**Abe (screenshot):** N.O.V.A.: "This is a very long flight. She was just my
main shaft. She didn't have any tools. She had her hands. I nearly vented."
His correction: "This is a very long flight. Have I told you that mechanic
was working on my intake shaft? She didn't use any tools, just her hands. I
nearly vented."

**Source:** not an authored line. The local model writes it from the
quiet-moment "jealousy" template (`data/content/quiet_moment_beats.json`),
which draws a mechanic, a part, a tool and a mishap from lists. It drew "my
main shaft" and "nothing but his hands" for a woman mechanic, and the model
mangled the sentence around the mismatch.

**Done (data only, at Abe's request):** part "my main shaft" → "my intake
shaft"; tool "nothing but his hands" → "no tools at all, just bare hands"
(fits any mechanic).

**Still worth doing after the playtest:** a quality check on these lines
(reject fragments like "She was just my main shaft.": a sentence whose
subject is the mechanic and whose object is a part, or under two clauses).
Abe's corrected line could be an approved example for this beat, or a fixed
fallback when the model's line fails the check.

### 4. First dock in the new system: Kaelen already offers the next route

**Abe (screenshot):** in the new system Kaelen's panel already shows "[ Ask
about new routes — 53 SC ]" on the first dock: a new gate is ready to open
straight away. He ended the playtest for the night here.

**Cause:** `GateDiscoveryManager._is_kaelen_offer_ready` needs 3 completed
contracts *in the campaign* (`QuestManager.get_completed_count()`, per
campaign since c-fix 3), 15 minutes of campaign time, and 60 minutes since
her last sale (`KAELEN_COOLDOWN_MINUTES`). After the first route the
campaign count is already 3 or more, so it never holds her back again: once
an hour has passed she offers the next route on arrival, with no work done
here.

**Proposed fix:** count contracts since her last route sale. Each sale
resets the count, and she offers the next route after 3 more contracts.
That makes every system ask for work before the next way out. Keep the
first route's rule (3 contracts, no ship requirement) and the ship check
for gates beyond Class I.
