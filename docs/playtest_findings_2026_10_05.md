# Playtest 2026-10-05: findings

Abe's run after: freighters on their own berths, station normal maps
(stronger Cinder, plated metal panels), the garbled quiet-moment line screen
(person = ship part), the [BackwardsWatch] log. Rule: **record and research
only; no code changes until Abe says the playtest has finished.**

## Findings

### 1. Opening cinematic: add a slight vignette -- FIXED

**Abe:** add a slight vignette to the opening cinematic.

**Code:**
- The cinematic draws its overlays on its own CanvasLayer (layer 90),
  `IntroCinematic._build_visuals()` (`scripts/story/IntroCinematic.gd:146`):
  the black fade, the glitch rect, then N.O.V.A.'s panel.
- `shaders/damage_vignette.gdshader` is already a soft screen-edge vignette
  (`tint`, `intensity`); with a black tint it does the job. No new shader.

**Fix (after the playtest):** a black vignette ColorRect added after the
glitch rect and before N.O.V.A.'s panel, so her portrait and subtitles stay
clear. Keep it slight (intensity ~0.5, tune by eye in `--intro-snapshot`).
It goes when `_layer` hides in `_finish()`, so gameplay never has it.

### 3. N.O.V.A.'s portrait stays behind when the chat moves (docking; seen over the overview too) -- FIXED

**Abe:** when docking, N.O.V.A. appears where the chat was (now an empty
screen) but the chat has moved up. Keep her in the chat box. I've seen her
in the overview as well before.

**Code:**
- `_show_nova_talk_portrait()` (`UIManager.gd:~12705`) places her ONCE, when
  she starts talking: `global_position = chat_window_panel.global_position`,
  size half the chat's width. Its comment says so: "placed once ... it does
  not follow it".
- But the chat does move under her. The left column (`UILayoutManager`,
  `scripts/ui/UILayoutManager.gd`) stacks hud, overview, chat top to bottom
  and skips hidden panels (`enforce_layout()`, `is_visible_in_tree()`).
  Docking hides the overview (`_set_overview_dock_locked(true)`), so the chat
  slides up into the overview's slot, and she's left at the old spot, over
  empty space. Undocking is the reverse: the overview comes back and pushes
  the chat down, and a portrait shown while docked now sits over the
  overview (the "in the overview" sighting). The arrival lines play right
  around both moments, which is why it shows up there.
- Second, smaller: the column also scales panels to fit
  (`panel.scale`), and her size uses `chat_window_panel.size.x` without
  the scale, so on a squeezed column she's bigger than the chat.

**Fix (after the playtest):** make her follow the chat. While she's visible,
re-place her whenever the chat's rect changes (connect to the chat's
`item_rect_changed`, or update in `_process` while visible): position = the
chat's global position, side = half the chat's *scaled* width. Not as a
child of the chat: it clips its contents and she's often taller than it.
Check: talk during docking and undocking (the arrival line) and she stays on
the chat both times.

### 2. Opening cinematic: no mouse cursor until control comes back -- FIXED

**Abe:** remove the mouse completely until ship controls are released back
to the player.

**Code:**
- Input is already blocked during the intro (playtest 2026-10-04 c finding
  1): `PlayerShip._unhandled_input` returns while
  `GlobalState.intro_cinematic_active` (`PlayerShip.gd:974`), and the HUD's
  keys are blocked except Esc (`UIManager.gd:3771`).
- But nothing hides the cursor: it stays `MOUSE_MODE_VISIBLE` over the
  cinematic.
- Control comes back in `IntroCinematic._finish()` (`IntroCinematic.gd:579`),
  which clears `intro_cinematic_active` and shows "Hold RIGHT MOUSE and drag
  to look around". That's the release point, also on skip (Space) and the
  watchdog.

**Fix (after the playtest):**
- `start()`: `Input.mouse_mode = MOUSE_MODE_HIDDEN`.
- `_finish()`: back to `MOUSE_MODE_VISIBLE` as control returns.
- Esc still opens the systems menu during the intro, which needs a cursor:
  show it while the menu is open and hide it again on resume if the intro is
  still running (UIManager's pause open/close, around the
  `MOUSE_MODE_VISIBLE` calls at `UIManager.gd:3807`).
- Check: the cinematic shows no cursor; the cursor is back the moment the
  "Hold RIGHT MOUSE" hint shows; Esc mid-intro shows it, resuming hides it.

### 4. Tractor beam hum 10% louder -- FIXED

**Abe:** increase the volume of the tractor beam by 10%.

**Code:** `scripts/effects/DockingTractorBeam.gd:17-18`: the hum is
`HUM_PLAYER_DB = -4.0` on your own dock/undock beam and
`HUM_TRAFFIC_DB = -12.0` on freighters' beams.

**Fix (after the playtest):** 10% louder in amplitude is +0.83 dB
(`linear_to_db(1.1)`): player -4.0 -> -3.2, traffic -12.0 -> -11.2, so
the two stay in the same balance. (If it still sounds the same, 10% louder
*to the ear* is closer to +1.4 dB.)

### 5. Feature: idle station tour while docked (AFK 1m30s) -- FIXED

**Abe:** if AFK for over 1m30s at a station, the HUD disappears and the
camera flies slowly around the station, taking a tour. Any mouse or key
brings everything back exactly as it was. A peaceful flight around the
station, maybe taking note of NPCs docking.

**What exists:**
- No idle timer anywhere yet (no AFK/last-input tracking in scripts).
- Docked: `UIManager.toggle_dock_menu()` shows the dock UI over the world;
  `PlayerShip.is_docked` holds the ship at its berth. The ship sits on the
  player berth (`Station.player_berth`), so the station model, its running
  lights and the traffic are all live behind the menu.
- Traffic gives it something to watch: `TrafficDirector` (`_ships` entries
  with `ship`, `station`, `berth`, `on_beam`, `kind` dock/leave) now brings
  freighters down onto their own piers on beams, and pushes leavers out.
- Camera precedent: the `--station-snapshot`, `--traffic-berth-snapshot` and
  `--station-normal-snapshot` runs already place a free Camera3D around a
  station from its AABB and the sun direction.

**Plan (after the playtest):**
- `StationTour` node (new, `scripts/ui/StationTour.gd`), owned by UIManager.
  Starts only while docked, on the plain dock menu (not in the lounge hunt,
  a conversation, the drone maze, a modal, or while a reply/LLM line is
  pending), after 90 s with no mouse or key input. Input resets the timer.
- On start: fade the HUD and dock UI out (remember what was visible), make
  its own Camera3D current, fade the music down a touch.
- The flight: a slow orbit of the station (radius from its AABB, about
  1.3-1.8x, gentle height drift, one lap in ~3 min) looking at the station's
  centre, eased with smooth noise so it never feels robotic. When a freighter
  goes on a beam at this station, the camera eases over to watch it come
  down onto its pier from a quiet three-quarter angle, holds a few seconds,
  then drifts back to the orbit. No text, no HUD; maybe the station's lights
  and the sun as the only drama.
- Any mouse move/click or key: the tour ends at once (a short fade), the
  previous camera is current again, the HUD and dock UI come back exactly as
  they were, and the input is swallowed so it doesn't click a dock button.
- Doesn't save anything; a tour never touches the game state.
- Test: `--station-tour-snapshot` forces it on, shoots a few frames
  including one following a docking freighter, then fakes an input and
  checks the dock menu and camera are back.

**Questions for Abe:**
- Only while docked (the dock menu up), or also floating near a station?
  (Assumed: docked only.)
- Also in the outposts? (Assumed: yes, same tour, smaller orbit.)

### 6. Undocking: the overview stays hidden until the beam lets go -- FIXED

**Abe:** the overview should remain gone until the ship is released from the
tractor beam.

(Changes playtest 2026-10-04 d finding 1, where it came back visible but
unclickable during the push.)

**Code:**
- `undock_player()` unhides it at the start of the push:
  `_set_overview_dock_locked(false)` + `set_overview_collapsed(false)`
  (`UIManager.gd:~10664`), while the beam is still carrying the ship out for
  several seconds.
- The release is the push tween's last callback in `_push_out_of_berth()`
  (`UIManager.gd:~10753`): beam freed, `is_docked = false`, "Clear of the
  safety zone. Controls are yours."
- Stations without berths skip the push (`UIManager.gd:~10718`: a 15 m nudge
  and `is_docked = false` at once).

**Fix (after the playtest):** move the overview unlock + expand out of
`undock_player()` into the release: the push's callback for berthed
stations, right where "Controls are yours." shows; and straight away on the
no-berth path. `_beam_has_ship()`'s click guard then never has anything to
guard on the way out (keep it for the way in).
- Knock-on: with the overview hidden, the chat stays up in its slot and
  drops down at the release. If N.O.V.A. is talking then, finding 3's fix
  (she follows the chat) covers it.
- Question for Abe: on the way IN, the overview still shows (unclickable)
  while the beam pulls you to the berth, and hides when the dock menu opens.
  Hide it the moment the beam takes hold instead, to match?
  **Abe: yes** -- cleaner if it isn't there at all than there and looking
  broken. So: hide it when the beam takes the ship on the way in (start of
  `_run_docking_procedure`, `UIManager.gd:~4552`), keep it hidden while
  docked, show it at the release on the way out. Whenever the beam has the
  ship, no overview. Abe: it also gives the player another visible clue
  that control is back -- the overview appearing goes with "Controls are
  yours." (So bring it back with the same short fade-in as the message, at
  the same moment, not before.)

### 7. Feature: N.O.V.A. comments on about half the missions you accept -- FIXED

**Abe:** N.O.V.A. should find something to comment on for 50% of the
missions you accept, even if it's just a snide comment about how little
you're getting paid for the risk. Different each time, not the same thing
over and over. The cards could even have a comment added when created.

**What exists:**
- On accept she only reacts to **hunt** contracts (`KILL_SHIPS`,
  `RECOVER_COMBAT_DROP`, `TARGET_WITH_COMMS_REVERSAL`): the pacifist /
  reluctant / bloodthirsty pools in `Nova.prepare_mission_hunt_reaction()`
  (`scripts/ai/Nova.gd:472`), and she says it when the targets show up on
  the overview, not at accept. Everything else gets nothing.
- Abe's "comment on the card when created" is already the pattern there:
  the line is picked when the offer is built (`UIManager.gd:13667, 13835,
  14594`), stored on the quest dict (`nova_mission_hunt_reaction`), its
  voice cached in the background, and moved to the front of the voice queue
  on accept (`UIManager._on_quest_accepted`, `UIManager.gd:15036`). So no
  click ever waits on a model.
- `Nova._pick_line(tag, pool)` (`Nova.gd:722`) draws without replacement:
  every line in a pool is heard before any repeats.
- The card has what she'd comment on: `reward_credits` (+ multiplier),
  objective type, cargo, destination and distance, target faction, twist
  shares (fines, tariffs, bounties).

**Plan (after the playtest):**
- When an offer card is built, roll 50% (seeded by the offer, so a card
  keeps its answer); on a yes, give it `nova_accept_comment`, picked from
  what's most notable on that card, in order:
  1. **Pay vs risk** (her favourite): pay per jump or per expected hostile
     well under the going rate -> snide ("Twelve hundred credits to fly into
     a pirate nest. I've seen better rates on organ donation.").
  2. **Pay well over the rate** -> suspicious ("Nobody pays that much for
     ice. Read the small print, Captain.").
  3. **Cargo / objective type**: hauling, mining, salvage, escort, rescue,
     courier, each its own small pool.
  4. **Destination**: far, deep, a system you haven't been, back to a
     place you've had trouble.
  5. **Who's paying**: faction / agent flavour.
  Hunt contracts keep their existing reaction (no double comment).
- Lines: authored pools per category (a few each to start, in Abe's short
  review batches), drawn with `_pick_line` so they rotate. Optionally later:
  the local model writes one per card in the background at offer time, with
  the pay/risk facts in the prompt, screened like the quiet-moment lines,
  falling back to the pools. Start authored: zero risk of garbled lines.
- **When: halfway to the mission location, not at the station** (Abe). Dead
  air on the flight is where a remark belongs; at the station she'd be
  talking over the agent and Dock Control.
  - On undock with the contract active, note the starting distance to the
    mission's first place (the tracker's route target,
    `UIManager._quest_tracker_route_target()` `UIManager.gd:~15366`, or the
    mission's asteroid field / hunt area / destination station, whatever the
    "next step" points at).
  - In-system: she says it when the remaining distance first drops under
    half (checked a couple of times a second, not every frame).
  - Another system: halfway in jumps (arriving in the middle system of the
    route; a one-jump trip: right after the jump, once the tunnel lines are
    done).
  - Never over something more important: not in combat, not while another
    line is playing or queued (low priority; if it can't play within the
    middle stretch, say from 40% to 70% of the way, drop it rather than say
    it on arrival). Not for missions done at the station itself.
  - One remark per mission, even across save/load (a flag on the quest).
  - Voice cached at card creation and moved to the front of the queue on
    accept, so it's ready long before halfway.
- Test: build 40 offers, check about half carry a comment; a flight test
  checks she speaks once, between 40% and 70% of the way, and not in combat; that pay/risk
  cards get pay lines, that no line repeats before its pool is used up, and
  that hunts still get only their hunt line.

**For Abe:** the first batch of lines (short, for review) before wiring.

### 8. Lounge hunt: the holder hands it over but it doesn't show in the inventory -- FIXED

**Abe:** on the board mission (get the lounge person to admit they have it),
they said "here it is", but the item didn't go into the inventory.

**Log (this session, `godot.log`):** the hand-over did happen:
`PICKUP_SPECIAL picked up: 'Audit-Proof Relay' from Dratordraru Salvage
Compact Vale Venn`, right after Vale Venn's "Fine. It's yours. If it starts
ticking, it was always like that." Two earlier pickups this session too
(Large Unmarked Crate, Biometric Lockbox).

**So it's where it shows, not whether it arrives:**
- A pickup goes into the **cargo hold** as special cargo
  (`GlobalState.accept_special()`, `cargo_special`, `CargoType.SPECIAL`),
  not into the item inventory.
- The inventory screen only mentions it in the one-line CARGO HOLD strip at
  the top (`InventoryScreen._fill_hold()`, `InventoryScreen.gd:431`:
  "Audit-Proof Relay (source -> destination)"). The item grid, where you'd
  look, never shows it.
- The HUD cargo bar jumps to full (`UIManager.gd:4445`), with no name.
- No confirmation at the hand-over: `mark_pickup_complete()` succeeds and the
  dock submenu just re-renders (`UIManager.gd:~6169`). No "loaded into your
  hold" line, no chat entry.

**Fix (after the playtest):**
- Show the pickup in the inventory grid as its own card (a "mission cargo"
  slot: name, from whom, deliver to whom/where; not sellable, not
  droppable), as well as the hold strip.
- On the hand-over: a clear line under the holder's reply ("Audit-Proof
  Relay loaded into your hold. Deliver to Kaelen at Greywake.") and the
  same in system chat; the tracker already moves on to the delivery step.
- Check: take a lounge-hunt job, get it handed over, open the inventory: the
  item card is there; the hand-over line shows.

**Side bug seen in the same log line:** the holder's name is printed as
"Dratordraru Salvage Compact Vale Venn": the faction got glued onto the
person's name in `target_npc`. It's also in the pickup's description
("Picked up from Dratordraru Salvage Compact Vale Venn at ...") which the
hold strip and delivery text use. The lounge itself shows "Vale Venn" (via
`QuestNextStep.person_name()`), so it's only the stored name. Fix: use
`person_name()` when building the description, or store the clean name.

### 9. "Checkpoint could not be saved" on undock (Zaren Relay, after the lounge pickup) -- FIXED

**Abe (screenshot):** under Dock Control's "Controls return past the safety
zone.": "SYSTEM WARNING: Checkpoint could not be saved. Your previous save
is still safe."

**Log (`godot.log` ~1227):**
```
WARNING: [GameRoot] Safe checkpoint location is unavailable.
   _request_safe_checkpoint_impl (GameRoot.gd:1062)
   request_safe_checkpoint (GameRoot.gd:1028)
   undock_player (UIManager.gd:10638)
WARNING: [UIManager] Pre-undock safe checkpoint was not created.
```
Right after the Audit-Proof Relay hand-over (finding 8) at ZAREN RELAY.

**Code:**
- `undock_player()` asks for an "undock" checkpoint at the station it's
  leaving: `request_safe_checkpoint("undock", current_station)`
  (`UIManager.gd:10636`).
- `_safe_location_for()` (`GameRoot.gd:6483`) returns nothing, so "location
  unavailable", only when that station is null, freed, or has no
  `get_world_id()`. Every station script has `get_world_id()`
  (`Station.gd:307`, `OutpostStation.gd:116`), so **`current_station` was
  null or freed** at that moment.
- `current_station` is set when the dock menu opens (`UIManager.gd:4489,
  4656`) and cleared to null inside `undock_player()` itself
  (`UIManager.gd:10656`), after the checkpoint request.

**Likely causes (to confirm):**
1. **Undock ran twice.** The first call saves fine (successes aren't logged)
   and nulls `current_station`; a second call (double click / key plus
   button / the N.O.V.A. repair prompt's "undock anyway",
   `_on_nova_repair_prompt_undock()` `UIManager.gd:10918`) finds it null and
   fails. Nothing stops `undock_player()` running when you're already
   leaving.
2. **The dock visit lost its station.** Something in this visit's lounge
   flow (the hunt hand-over re-renders the dock submenu; the ore-trade popup
   path) re-opened the dock UI without `current_station`.

**Fix (after the playtest):**
- Say why in the warning (null / freed / no world id), and log successful
  checkpoints, so the next one is diagnosable.
- Guard `undock_player()`: ignore it if an undock is already under way (the
  beam has the ship, or the dock panel is already closed).
- Fall back to the station the player is berthed at (the beam's station /
  the nearest station within its approach sphere) if `current_station` is
  gone, so the save still happens.
- Repro: lounge-hunt hand-over at an outpost, then undock (click Undock
  twice quickly too); expect no warning.
- No harm done this time: the previous save is kept, as the message says.

**Abe:** it undocked but the UI was still up, so I clicked Undock a second
time. -> **Cause 1 confirmed** (undock ran twice; the second found no
station). The real bug is the dock UI being up after undocking.

**Why the dock UI was up (strong candidate, to confirm with Abe):**
- During the beam push the ship still counts as docked (`is_docked = true`
  until the release callback, `_push_out_of_berth()` `UIManager.gd:~10750`).
- Closing the inventory returns to the dock screen whenever the player is
  docked: `_close_inventory_panel()` and the inventory toggle
  (`UIManager.gd:~8955-8990`): `if inventory_return_to_dock or
  player_is_docked: dock_panel.visible = true; _render_dock_submenu()`.
- Abe was looking for the relay in the inventory (finding 8). Opening and
  closing the inventory during the push (the HUD keys aren't blocked while
  the beam has the ship) brings back the whole dock panel, Undock button
  included, while flying out. Clicking it runs `undock_player()` a second
  time with `current_station` already null -> the failed checkpoint.
- Alternative if he didn't touch the inventory: the first click hit N.O.V.A.'s
  repair prompt (`undock_player` returns early at `_show_nova_repair_undock_prompt()`,
  but only AFTER switching the music to "explore" and ending the docking
  camera, `UIManager.gd:10624-10628`), so it looked undocked while still
  docked. But then the second click would have had its station and saved,
  so the inventory route fits the log better.

**Fix, in addition to the guards above:**
- "Docked" for UI purposes = the dock menu's visit (`current_station` set),
  not `is_docked`: the inventory (and any other panel's back/close) returns
  to the dock screen only if the visit is still open, never during the push.
- Clear `inventory_return_to_dock` (and the other "return to dock" flags) in
  `undock_player()`.
- The repair prompt: switch the music and end the docking camera only once
  undocking really goes ahead, so the prompt never looks like you've left.

### 10. The pickup could be turned in "without the item in the inventory" -- FIXED

**Abe:** that pickup mission let me turn it in even without an item in my
inventory.

**Log:** the relay *was* aboard: `PICKUP_SPECIAL picked up: 'Audit-Proof
Relay'` (line ~1209), then `Quest completed successfully: Sealed Pickup:
Audit-Proof Relay, No Sniffing` (~1280). So the turn-in was legitimate; the
item was in the cargo hold, which the inventory doesn't show (finding 8).
Same root: you can't see the item come in, so you can't see it go out.

**But a real gap behind it:** the hand-in only checks the mission's
`picked_up` flag (`MissionAdapter.gd:~498`), never that the item is still
in the hold. If the hold lost it (jettison, a cargo reset, a save edge),
the job would still pay.

**Fix (after the playtest), with finding 8:**
- The item card in the inventory (finding 8), and at the hand-in a line
  "Audit-Proof Relay handed over to Kaelen." as it leaves the hold.
- Hand-in requires the item actually in the hold
  (`cargo_type == SPECIAL` and `cargo_special.name == part_name`); if it's
  gone, say so ("The relay isn't aboard.") and don't pay.
