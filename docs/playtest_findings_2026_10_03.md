# Playtest 2026-10-03: findings

Abe is playtesting. Rule for this session: **document and research only; no
code changes until Abe says the playtest has finished.** Each finding gets
what Abe saw, what the code says (cause, with file:line), and a proposed fix.

## Findings

### 1. **FIXED 2026-10-03** Landing page: duck the music under the stinger, then bring it back slowly

**Abe:** on the landing page, duck the audio when the stinger plays, then
slowly bring it back up to volume after the stinger finishes.

**What the code does:**
- Pressing Continue / Begin Expedition runs `_play_launch_sequence()`
  (`scripts/ui/LandingScreen.gd:284`), which calls
  `AudioManager.play_stinger("jump")` (`Stinger_Jump.mp3`) while the
  landing tracks (FrontPage01/02) keep playing at full volume.
- `play_stinger()` (`scripts/AudioManager.gd:358`) just plays the one-shot;
  nothing ducks.
- **Catch:** the stinger player is on the **Music** bus
  (`AudioManager.gd:110-111`), same as the music. So the existing
  `duck_audio()` (which lowers the whole Music bus) would duck the stinger
  too. And the music players' own `volume_db` is already used by the track
  crossfade (`AudioManager.gd:278-292`), so a duck tween there would fight it.

**Proposed fix:**
- At startup, add a runtime bus **"MusicBed"** that sends into "Music", and
  put `bgm_player` and `_bgm_alt` on it. The stinger stays on "Music", so
  the music volume slider still controls both.
- In `play_stinger()`: tween MusicBed down (about -12 dB over 0.2 s), wait
  for the stinger's length (`stream.get_length()`), then tween back to 0 dB
  over about 2.5 s ("slowly"). A new stinger mid-duck restarts the timer.
- **Important (Abe): the music must FADE back in, never snap back to full
  volume.** The restore is a slow tween (about 2.5 s, eased so the first
  part is gentle), starting only after the stinger has finished. Nothing
  else may jump the music to full mid-fade: the dialogue duck/unduck
  (`_update_bus_volumes`, Music bus) is a separate bus so it can't, and a
  crossfade starting during the fade-in stays under it. Test: sample the
  MusicBed volume during the restore and check it rises step by step,
  never jumping.
- **Every stinger ducks (Abe confirmed):** jump, victory, mission paid,
  danger. He heard the same problem with the victory stinger when the Reaver
  blew up.
- Victory case detail: `combat_ended` plays the victory stinger **and** calls
  `set_music_state("explore")` in the same moment, so the combat → explore
  crossfade runs under the stinger. With the duck on the MusicBed bus, the
  crossfade happens ducked and the explore music swells back in after the
  stinger, which is the right feel. Same for `combat_started` (danger
  stinger + crossfade to combat).
- Check: the landing flow then switches tracks (`exit_landing_music` →
  `play_next_bgm`) while the duck is restoring; with the duck on its own bus
  that's independent of the crossfade.

### 2. **FIXED 2026-10-03** Music stopped while flying to the Reaver in the tutorial

**Abe:** the music stopped playing during the flight to the Reaver in the
tutorial.

**What the code does:** the game log has no music lines, so this is from
reading the code (not confirmed yet).
- Flying toward the Reaver: once any ship has the player as its `target`,
  `_update_tension()` (`scripts/AudioManager.gd`, checked once a second)
  switches the music to "tension" and crossfades to `Tension.mp3`. When no
  ship targets the player any more, it switches back to "explore" and
  crossfades to the flight list.
- `_crossfade_to()` swaps the two music players and starts a 2 s tween:
  new player up to 0 dB, old player down to -40 dB, **then `old.stop()`**.
  The tween isn't stored, so a second crossfade can't cancel it.
- **Likely bug:** if the state flips twice within 2 s (the Reaver's
  `target` flickering on and off as it acquires, loses or re-picks the
  player), the second crossfade swaps back onto the player that the first
  tween is still fading out. The first tween then drags it to -40 dB and
  calls `stop()` on it: **the music that should be playing is stopped**, and
  the other player is faded out by the second tween. Silence until something
  else starts a track (`finished` never fires after `stop()`).

**Proposed fix:**
- Keep the crossfade tween in a variable; kill it before starting a new
  crossfade, and make the stop callback only stop a player that isn't the
  current one.
- Add hysteresis to tension: enter after the threat has held ~2 s, leave
  only after ~5 s clear, so a flickering target doesn't flip the music.
- Add a music watchdog: if no music player is playing for 3 s outside
  landing/lounge/broken-gate silence, start the right track.
- Add `[Music]` trace lines on state changes and crossfades, so the next
  time it happens the log says why.
- Test: a unit test that calls `set_music_state` explore → tension → explore
  inside 2 s and checks a player is still playing at full volume afterwards.

### 3. **FIXED 2026-10-03** Tutorial: N.O.V.A. should say "back to the station" after the Reaver dies

**Abe:** after blowing up the Reaver in the tutorial, N.O.V.A. could point
out that we should return to the station. A bit more hand-holding in case
the flashing "return to station" isn't enough.

**What the code does now:**
- The quest tracker switches to "Reaver destroyed. Return to the station and
  click Talk to Agent to hand in the contract."
  (`scripts/UIManager.gd:14661`, `_intro_starter_contract_tracker_text`),
  and the tracker shows a "Dock at Station" route button
  (`_update_quest_tracker_route_button`, `UIManager.gd:~14670`).
- N.O.V.A. only says a generic victory line (`Nova.gd` `on_combat_ended`,
  ~line 1200-1300: clean / scuffed / battered pools). Nothing about going
  back or getting paid.

**Proposed fix:**
- When the intro starter contract ("Clean and Easy", `_is_intro_starter_contract`)
  becomes complete and the ship is undocked: about 6 s after her victory
  line, N.O.V.A. says one authored line, e.g.
  - "That's the job done, Captain. Let's head back to the station and get
    paid. The Dock at Station button on the tracker will take us in."
- If the ship still isn't docked 60 s later, one gentler reminder, e.g.
  - "Kaelen's money is still sitting at the station, Captain. Dock and click
    Talk to Agent."
- Only in the tutorial contract, at most these two lines. (Lines for Abe's
  review; short batch.)
- Test: complete the starter contract in the first-session smoke test and
  check the line is queued; not queued for ordinary contracts.

### 4. Normal maps for the planet and asteroid textures (look more 3D)

**Abe:** look into creating normal maps for our planet and asteroid textures
so they feel more 3D.

**What the code does now (no normal maps anywhere on these):**
- **Rocky planets:** `scripts/generation/SystemFactory.gd:196` builds a
  `StandardMaterial3D` with `albedo_texture = assets/planet_rocky.png`
  (1024x1024, one texture for every rocky planet, tinted per planet),
  roughness 0.88, on a `SphereMesh` (48x24). Flat-lit: all the surface
  detail is painted, so it reads like a printed ball.
- **Gas giants:** a shader (`shaders/gas_giant.gdshader`); gas has no
  relief, so they don't need a normal map.
- **Asteroids:** `scripts/visuals/AsteroidModels.gd` uses one atlas,
  `assets/asteroidTextures.png` (1254x1254, a 3x3 grid, so about 418 px per
  rock), cell picked by `uv1_scale`/`uv1_offset`. Ore rocks use their own
  atlases with the same layout (`assets/asteroid_ores/cuprite, ferrite,
  thorium, water_ice.png`).
- Good news for normal maps: the asteroid .glb imports already have
  `ensure_tangents=true`, SphereMesh has tangents, and each system has a
  `DirectionalLight3D` sun (`SystemFactory.gd:77`), which is what makes
  normal maps show (side-lit bumps and craters).

**Proposed approach:**
1. **Bake normal maps from the existing textures** (no new art needed): a
   small tool, `tools/make_normal_maps.py`, treats each texture's
   brightness as height (lightly blurred), takes a Sobel gradient, and
   writes a tangent-space normal map (`*_normal.png`, OpenGL/Godot +Y).
   - Atlases: process **each 3x3 cell separately** so bumps don't bleed
     across cell borders (the cell offset is shared with the albedo, so the
     same `uv1_scale`/`offset` lines it up).
   - Planet: wrap horizontally so the seam at the back has no line.
   - Same for the four ore atlases.
   - Import them as normal maps (`compress/normal_map=1`).
2. **Use them:** `normal_enabled = true`, `normal_texture`, `normal_scale`
   (start ~1.0 for asteroids, ~0.6 for planets; a planet seen from far away
   needs less) in `SystemFactory` and `AsteroidModels` (both plain and ore
   materials).
3. **Optional, for close-up mining:** a tiling **detail normal**
   (`detail_enabled`, a small rock-grain noise normal map tiled ~8x) on
   asteroids, since 418 px per rock goes soft up close. And for planets,
   Godot's `heightmap_enabled` (parallax) can add real-looking crater depth
   at the limb; test the cost first.
4. **Check:** before/after snapshots with the sun to the side (the
   `--gas-giant-snapshot` tool's dedicated-camera pattern, plus one of an
   asteroid belt), and a perf probe in a dense belt (normal maps are cheap,
   parallax less so).
- Caveat: brightness-as-height is a guess (dark paint becomes a dent). It
  usually looks good on rock; if some craters invert, the fix is a
  hand-tuned height (or the image tool) for that texture only.

### 5. NPC ships docking at stations and outposts: bring them in on a tractor beam too

**Abe:** other ships docking at stations and outposts should be brought in
with the tractor beam as well.

**What the code does now:**
- Station traffic is `scripts/world/TrafficDirector.gd`: every 25-50 s a
  Logistics freighter either flies in from a gate to the **main station's**
  berth or leaves for a gate (max 3 at a time).
- Docking today: when the freighter gets within `DOCK_RADIUS` (110 m) of
  the berth, it just **shrinks to 5% over 1.4 s and is freed**
  (`_tick_ship`, ~line 110). No beam, no pull.
- **Outposts get no traffic at all**: `_spawn()` only uses
  `GlobalState.get_primary_station()`.
- The player's dock (`UIManager.begin_docking_procedure`, ~line 4400) uses
  `DockingTractorBeam` (`scripts/effects/DockingTractorBeam.gd`: a glowing
  cyan cylinder from the station's centre to the ship's hull, updated every
  frame, frees itself when either end is gone) and pulls the ship to
  `get_docking_position()` over 4 s (`DOCK_TRACTOR_PULL_SECONDS`, sine
  ease), then clamps for 3 s. Both `Station` and `OutpostStation` have
  `get_docking_position()`.

**Proposed fix:**
- **Tractor capture for traffic:** when an inbound freighter is within about
  350 m of its berth, the director takes it over: stop its own steering
  (NPC physics off, or a "tractored" flag the NPC steering respects), add a
  `DockingTractorBeam` configured (station, ship), turn it to face the
  station, and tween it to the berth over ~4 s (same sine ease as the
  player). At the berth: a short hold (~1.5 s, the "clamps"), then it slides
  into the station and fades/shrinks out; the beam frees itself.
- **Departures mirror it:** a leaving freighter starts on the beam at the
  berth and is pushed out ~150 m over ~3 s before its engines take over.
- **Outposts too:** spawn destinations pick the main station or one of the
  system's outposts (outposts less often, e.g. 1 in 3), using each one's
  `get_docking_position()`.
- Make the beam reusable: it is already standalone (`configure(station,
  ship)`); add it to the scene root like the player's (stations are scaled,
  which once magnified the beam).
- Guards: a tractored freighter can't be shot at by NPCs already
  (`npc_attack_protected`); if the player destroys it mid-pull, the beam
  frees itself (checks `is_instance_valid`). Never tractor two ships into
  the same berth at once (queue the second outside 350 m).
- Test: extend the `--traffic-smoke-test` (GameRoot ~10841 forces an
  arrival): check a beam exists during the pull, the ship reaches the berth,
  then is freed; and an outpost arrival.

### 6. No engine sound in normal flight (only on boost)

**Abe:** if we have an engine noise for regular flight, he can't hear it;
he does hear something during boost.

**What the code does:** there is **no engine sound in normal flight at
all**. Nothing in `PlayerShip.gd`, `EngineExhaust.gd`, `ThrusterBank.gd` or
the player scene plays a loop. What he hears on boost is a one-shot:
`activate_boost()` (`PlayerShip.gd:888`) calls `AudioManager.play_align()`
(`sound/ShipSounds/ShipAlignSound.mp3`). (Combat has `engine_boost.wav` for
evasive burns only.) Ship sounds on disk: ShipAlignSound, jet_spool_up
(synthesized by `tools/generate_jet_spool.py`), warpSound.

**Proposed fix:**
- An **engine loop** on its own player in `AudioManager` (SFX bus, not 3D,
  it's our ship): a low rumble + soft filtered roar, seamless loop.
- Volume and pitch follow the throttle each frame: near-silent hum at a
  stop, fuller as speed rises (`current_speed / max_speed`); boost adds a
  swell and a little pitch (the existing boost one-shot stays on top).
  Smoothed so it never jumps. Fades out when docked, destroyed, during the
  jump tunnel (the jump channel owns that) and in cutscenes.
- Source: synthesize it like the jump spool (a new
  `tools/generate_engine_loop.py`: filtered noise + a low harmonic drone,
  crossfaded end-to-start so it loops cleanly); Abe judges by ear, and a
  bought/recorded loop can replace the file later.
- Keep it subtle under music and voice (it ducks with SFX under dialogue
  already, via the SFX bus).
- Engine tier could later shift its character (Mk II+ slightly deeper);
  not for this pass.

### 7. The wiki button should flash when there are new entries

**Abe:** the wiki button should flash when new items are in it.

**What the code does:**
- The only wiki button is in the **pause menu** (Esc):
  `pause_wiki_button` (`scripts/UIManager.gd:2621`). `refresh_wiki_button()`
  (`:2781`) sets its text to "WIKI  (N new)"; no flash.
- `Wiki.unlock()` (`scripts/ui/Wiki.gd:122`) adds the entry to
  `wiki_unread` and posts a feed line "New entry: X. Esc > Wiki to read it
  any time." There's **no wiki button on the HUD**, so while flying nothing
  shows there's something new except that feed line.
- Unread clears per entry when it's opened (`Wiki.gd:98-106`).

**Proposed fix:**
- Pause menu: while `unread_count() > 0`, the WIKI button pulses (a
  looping `modulate` tween, like the fuel warning's `_set_fuel_flashing`,
  `UIManager.gd:4325`) in the reward gold, with "(N new)". Stops when all
  are read.
- **HUD:** add a small "Wiki (N new)" chip on the HUD that appears only
  while there are unread entries, pulses gently, and opens the wiki on
  click (so the player doesn't have to know about Esc). It hides when
  nothing is unread. (Ask Abe where on the HUD; default near the quest
  tracker, out of the overview's way.)
- Refresh on every unlock (have `Wiki.unlock` emit through a signal or the
  UI poll it once a second) and when the wiki closes.
- Test: unlock an entry → chip visible and pulsing, pause button pulsing;
  read it → both stop.

### Checklist

- Section C (Flight and combat feel) of `docs/playtest_todo.md`: all
  ticked (Abe, 2026-10-03).

### 8. Wiki: N.O.V.A.'s name stands for Neural Operational Virtual Assistant

**Abe:** in the wiki under N.O.V.A., her name means **Neural Operational
Virtual Assistant**.

**What the code has now:** the acronym isn't spelled out anywhere in the
project. The wiki entry `nova` (`data/content/wiki_entries.json:259`) starts
"Your ship's AI. She flies with you, ..."; the soul bible
(`docs/narrative/character_souls/NOVA.md`) doesn't give it either.

**Proposed fix:**
- Wiki body opens with it, e.g. "**N.O.V.A.**: Neural Operational Virtual
  Assistant. Your ship's AI. She flies with you, ..."
- Add it to the soul bible header (canon, so any future line or prompt that
  names it gets it right) and, if `fixed_cast_souls.json` has a
  name/description field, there too.
- Run the secret-leak test after (the acronym is ordinary player-facing
  canon, not the director-only secret, but every N.O.V.A. text change gets
  the check).

### 9. Deeper systems burn more fuel in normal flight

**Abe:** each system past the first uses incrementally more fuel for
regular flight, e.g. system 2 x1.1, system 3 x1.5, system 4 x2, system 5
x2.8.

**What the code does now:**
- Cruising burns `Fuel.CRUISE_SIP_PER_SECOND` (0.01 per second at full
  speed, scaled by speed, up to x1.5) in `PlayerShip.gd:1444-1446`, the same
  in every system. Tank is 100 (`Fuel.gd:10`). So today a full tank lasts
  about 2.8 hours of full-speed cruising.
- Jumps already cost more deeper: `Fuel.jump_cost(depth)` = 8 + 2 per depth,
  max 20 (`Fuel.gd:45`). Boost is a flat 2.
- Depth per system: `DepthScaling.current_depth()` (gate depth from home).
  It walks the whole system graph, so it shouldn't be called every physics
  frame.

**Proposed fix:**
- Read "system N" as **depth N-1** (home = depth 0 = x1.0), i.e. by how far
  out the system is, not the order visited. Table (Abe's numbers):
  depth 0 x1.0, 1 x1.1, 2 x1.5, 3 x2.0, 4 x2.8; past that a formula that
  keeps growing the same way (roughly +1 per depth: 5 x3.8, 6 x4.9...), or
  a cap. **Ask Abe:** cap it, or keep growing?
- New `Fuel.cruise_multiplier(depth)` (pure, tested), used in the cruise
  sip. Cache the depth on arrival (system_changed) rather than computing
  it per frame.
- Show it: the HUD fuel readout's tooltip and the star map tooltip ("Fuel
  burn here: x1.5"), and a line in the wiki's Fuel entry
  (`wiki_entries.json`, id `fuel`), so it's a known rule, not a surprise.
- **Note for Abe:** at today's sip rate even x2.8 is only 0.028 per second
  (a full tank lasts ~1 hour of full-speed cruising at depth 4), so the
  multiplier will barely be felt unless the base rate rises too. Ask
  whether the base sip should go up (and whether the multiplier should
  apply to boost as well, or to cruising only as he said).
- Re-run the economy sim (`--economy-sim`, step 7) after, since fuel runs
  are part of rung times.

### 10. Receiver (T) blocked: "Hostiles close" with nothing hostile around

**Abe (screenshot):** in Calari (a generated frontier system), no ship was
close or targeting him, yet T said "Hostiles close. Can't hold a weak signal
with them around." The overview showed a Generated Logistics ship at 450 m,
salvage and pilgrim-fleet ships and wrecks at 1-1.4 km, nothing red.

**Cause (confirmed in code):**
- `SignalTuningActivity._threat_nearby()`
  (`scripts/story/activities/SignalTuningActivity.gd:317-341`) blocks if any
  ship within `HOSTILE_QUIET_RANGE` (**3000 m**) belongs to a "minor"
  faction (the rule I added on 2026-10-02 so pirates count).
- `GlobalState.is_minor_faction()` (`GlobalState.gd:280`) returns **true for
  every generated faction** (`gen_*` / `faction.generated.*`). In frontier
  systems almost every ship is from a generated faction: haulers, salvage
  crews, pilgrim fleets. So the receiver is blocked nearly everywhere past
  the start system.
- Also: the same check counts `ship.target == player` at **any distance**.

**Related (bigger) issue to flag:** NPC AI uses the same rule:
`NPCShip.gd` ~line 651, "Minor factions are always hostile to the player",
so a generated-faction hauler or pilgrim will attack if the player comes
within its ~130 m notice range. The overview doesn't show them red, and
their names (Salvage Collective, Pilgrim Fleet, Logistics) don't read as
hostile. Is that intended? (Ask Abe.)

**Proposed fix:**
- One shared rule, e.g. `GlobalState.is_hostile_to_player(ship)`, used by
  the receiver, NPC targeting and the overview colour, so "hostile" means
  the same thing everywhere:
  - pirates / raider factions (Reavers and the authored hostile minors):
    hostile;
  - generated factions: hostile only if their record says so (combat roles
    of a hostile-disposition faction, or reputation below the hostile line);
    haulers, salvagers, pilgrims, civilian traffic and `npc_attack_protected`
    ships never;
  - majors: reputation < -10 outside a station safe zone (as now).
- Receiver: block only for a hostile ship within ~1500 m, or a ship that
  is actually targeting us **within range** (drop the any-distance rule).
- Make the block message say which ship ("Reaver Raider 820 m: can't hold a
  weak signal") so it's never a mystery.
- Test: the receiver's unit tests with a generated-faction hauler at 450 m
  (not blocked), a Reaver at 800 m (blocked), a far-off targeting ship
  (not blocked).

#### 10b. Abe's design: two aggression settings, Hostile and Territorial

**Abe:** we should have 2 different settings. **Hostile** = always
aggressive towards you if they see you. **Territorial** = only aggressive if
you get too close. Safeguards (like the receiver block) should **not** guard
against Territorial. Assign each faction according to how it acts.

**Today** there's no such setting: "minor faction" is used as "pirate"
everywhere, and every generated faction counts as minor. Uses to audit (22):
`NPCShip.gd` 296, 530, 634, 652/658 (targeting), 846, 879, 905, 1177, 1194;
`GeneratedSystemNPCManager.gd` 127, 360, 385; `MainScene.gd` 268;
`UIManager.gd` 5147; `CombatManager.gd` 651 / `TauntCause.gd` 181 (taunts);
`SignalTuningActivity.gd` 339 (receiver); `GlobalState.gd` 914, 1043;
`TrafficDirector.gd` 134. Some are only about looks (ship family, colours)
and stay as they are; the hostility ones move to the new setting.
Also today, hostile minors only notice the player within **130 m**
(`NPCShip.gd` ~640, nebula-scaled), which is closer to "territorial" than
"sees you".

**Proposed design:**
- A `disposition` per faction: `hostile`, `territorial` or `peaceful`
  (peaceful = never starts a fight; majors in good standing, civilian
  traffic). One function decides it: `GlobalState.disposition_of(ship)`.
- **Hostile:** engages when it sees you: notice range ~1000 m (nebula and
  sensor scaling as now). Counts for every safeguard (receiver block,
  tension music, N.O.V.A.'s threat warnings). Overview: red.
- **Territorial:** at ~450 m they hail a warning ("Back off, you're inside
  our perimeter") in the comms feed; inside ~250 m, or if you stay inside
  450 m for ~10 s, they attack. They break off once you're ~800 m away.
  **Never counts for safeguards** (receiver, tension music) while you keep
  your distance. Overview: amber, so the player knows to keep clear. Fits
  the claim hails already built for mining claims (step 6b).
- Attacking a territorial or peaceful ship makes it (and its wing) hostile
  to you for that fight, as now.

**Proposed assignment (by how they act; Abe to confirm):**

| Faction | Kind | Setting |
|---|---|---|
| Reavers | Raiders | Hostile |
| Obsidian | Outlaws | Hostile |
| Wraiths | Marauders | Hostile |
| Dustborn | Nomads | Territorial |
| Ironclad | Mercenaries | Territorial |
| Zenith / Aurelia / Vanguard (majors) | by reputation | Peaceful; Territorial below -10; Hostile at -50 or worse (the existing "hostile" band, `GlobalState.gd:329`); stand down in station safe zones as now |
| Generated: Claims Office | guards claims | Territorial |
| Generated: Security Lease | hired security | Territorial |
| Generated: Salvage Compact (and Salvage Collective) | salvagers | Territorial |
| Generated: Pilgrim Fleet | pilgrims | Territorial |
| Generated: Courier Union | couriers | Territorial |
| Any generated faction whose reputation drops to -50 | | Hostile |
| Civilian traffic, Logistics haulers, `npc_attack_protected` | | Peaceful, always |

- Stored: authored factions get a `disposition` field in
  `data/content/factions.json`; generated factions get one in their record,
  set from the descriptor when created (`CampaignGeneratedFactionStore.gd`
  ~403), with the same mapping as a fallback for old saves.
- **Receiver (T) after this (Abe asked):** blocked only by (a) a Hostile
  ship within **1500 m** (its ~1000 m notice range plus a margin, so a
  hostile about to spot you still counts), (b) a Territorial ship that is
  actually attacking you, or (c) any ship targeting you within 1500 m. Today
  it's 3000 m for any "minor" ship. In Calari (the screenshot) nothing
  would block it: every ship there was generated (territorial) or a hauler.
  The block message names the ship and its distance.
- Wiki: a short "Hostile and territorial" entry under Combat.
- Tests: disposition per faction; a territorial ship hails at 450 m and
  attacks inside 250 m; the receiver isn't blocked by a territorial ship at
  450 m but is by a Reaver at 800 m; the overview colours.

### 11. HUD rep row in the 2nd system shows "GEN 0 | GEN 0 | GEN 0"

**Abe (screenshot):** in the second system the REP row reads GEN 0 three
times. A real rep, or an error?

**Cause (confirmed): a display bug.** The system has three generated
factions (in Calari: the Orveknakren salvage crew, the Zeneshdramir pilgrim
fleet, and a third). `_get_current_system_faction_ids()`
(`scripts/UIManager.gd:11751-11762`) shortens each id with
`str(fid).get_slice(".", 1)`. That turns `faction.zenith` into `zenith`
(correct), but every generated id `faction.generated.<name>_NN` into just
**`generated`**. So all three entries become "generated":
`faction_info("generated")` finds no record and falls back to the first
three letters, **"GEN"**, and `reputations["generated"]` doesn't exist, so
**0**. The real names and standings are never looked up.

Same slice in two more places:
- `BranchMapUI.gd:232`: star map system tooltip, rep colours of generated
  factions (names are right, they use the full id; colours read rep 0).
- `BranchMapUI.gd:824`: star map detail panel lists generated factions as
  "Generated".

**Proposed fix:**
- Strip only the leading `faction.` (`trim_prefix("faction.")`), keeping
  `generated.<name>_NN` whole, or better, one helper
  `GlobalState.faction_key(fid)` that every caller uses.
- Check which key reputations are stored under for generated factions:
  `adjust_reputation()` (`GlobalState.gd:2516`) takes whatever name the
  caller passes (an NPC's `faction`, possibly the `gen_..._NN` legacy id or
  the full id). Normalise in `adjust_reputation` and in the readers so one
  faction never has two rep entries.
- Then the row shows each faction's own abbreviation (from its generated
  record, e.g. "ORV -5") with its tooltip (full name, descriptor, standing).
- Test: a generated system's HUD rep row shows three different
  abbreviations with their real reputations; star map detail panel shows
  their names.

### 12. Goal card: tooltips on each row saying how to get it

**Abe:** add tooltips for goals telling how to get that material or what to
do.

**What the code does now:**
- `UpgradeGoal.rows()` (`scripts/domain/UpgradeGoal.gd:103-119`) already has
  one short hint per row (credits: "Take a job from a station board, or sell
  ore."; ore: "Mine any rock, then bank it..."; every material: the same
  "A red rock: target it, fly close, press G..."; power: "upgrade the
  Powerplant first").
- The card (`scripts/ui/UpgradeGoalCard.gd:142-200`) only shows the **first
  unmet** row's hint, as the orange line under the bars. Rows have **no
  tooltips** (and Labels ignore the mouse by default, so a tooltip needs the
  row set to `MOUSE_FILTER_PASS`/`STOP`).
- Materials gap: each red rock carries **one** tech material, picked by the
  rock (`DroneMazeActivity.material_for`, line 246: thermal lattice, rad
  quartz or cryo ferrite), but nothing shows **which** before diving: the
  overview/target label (`UIManager._asteroid_type_label`, :8378) says only
  "Asteroid · tech-grade seams". So the honest tooltip today is "dive red
  rocks until one has it", which is a grind.

**Proposed fix:**
- Every row gets a tooltip on hover (the whole row: name, bar, amount),
  with a fuller how-to than the one-line hint:
  - **Credits:** "Take a job from a station board or from Kaelen, sell ore
    or survey data. You have X, need Y."
  - **Ore:** "Mine any rock (target it, fly close, Mine), then dock and press
    Bank for upgrades. Banked ore is kept for upgrades; ore in the hold can
    still be sold."
  - **Each material (its own text):** what it is, where it's found and how:
    "Rad quartz: a tech-grade crystal in red rocks. Target a red rock, fly
    close, press G and fly the survey drone to the seam. A clean dive brings
    home two. Survey drones: N.O.V.A.'s spare, or buy at a station."
    (same pattern for thermal lattice, cryo ferrite, resonant crystal)
  - **Power:** "Fitting this draws X MW more than your powerplant gives.
    Upgrade the Powerplant first (set it as your goal from the upgrade
    screen)."
  - When a row is met: "Done."
- Wording lives in `UpgradeGoal` (one function per id), so the card and any
  future screen share it; no text in art.
- **Suggest (ask Abe):** show a red rock's material on its overview/target
  label once scanned ("Asteroid · tech-grade seams · rad quartz"), so the
  tooltip can say "look for a red rock marked rad quartz". Otherwise the
  material hunt stays blind.
- Test: rows have tooltips; each material has its own text; power row text
  names the MW.

### 13. The target window should show the distance to the target

**Abe (screenshot):** the target window ("CALARI BEACON [Station]" with
Boost / Fly to / Orbit / Dock at Station) should show the distance.

**What the code does:** `_on_target_changed()` (`scripts/UIManager.gd:4180`)
sets `target_label.text = name + " [" + type + "]"` once, when the target
changes (line ~4232). No distance. The overview already computes it every
frame (`_update_overview_distances`, `"%dm"`, ~line 4064).

**Proposed fix:**
- Show the distance in the target window, updated every frame from
  `_update_target_command_feedback()` (`UIManager.gd:10818`, already per
  frame): either appended to the title ("CALARI BEACON [Station] · 1,014 m")
  or as its own small line under it so the title doesn't jitter. Prefer the
  separate line, right-aligned, dim text.
- Format: metres under 10 km ("1,014 m"), then km with one decimal
  ("12.4 km"); same helper used by the overview so the two always agree.
- Optional: a closing/opening arrow (▼ closing, ▲ opening) from the
  distance change, useful on approach.
- Test: target something, move, and check the label changes; it hides with
  the window.

### 14. **FIXED 2026-10-03** Can't find the "Unlabeled Heat Sink" (all three lounge NPCs talk about it, none offer it)

**Abe:** he couldn't find the heat sink. All 3 lounge NPCs talk about it,
so he thought it was a lounge thing, but none gave an option to get it.

**What it actually is (from the log and his save):** a **public board job**
he accepted: "Sealed Pickup: Unlabeled Heat Sink, No Sniffing"
(`PICKUP_SPECIAL`, log line 1068). Saved objective:
- pick up from **"Zeneshdramir Pilgrim Fleet Rook Rook"**
- at **CALARI BEACON** (`station.system_gen_frontier_first.s2`, an
  outpost in Calari)
- deliver to **"Grease Monkeys"**

How the game expects it to work: dock at **CALARI BEACON** (the outpost,
not the main station or its lounge); the outpost's dock services show
"Ask <contact> for Unlabeled Heat Sink" (`UIManager.gd:4998-5021`). Lounge
NPCs only *gossip* about your active job (the lounge chatter generator
picks it up as a topic; the log shows `lounge_bundle ...
no_relevant_topic_answer`), and they can't hand it over.

**Problems found:**
1. **Not discoverable.** Everyone in the lounge talks about the job, which
   reads as "go talk to them". Nothing on screen says "dock at CALARI
   BEACON (outpost) and ask <contact>". The briefing text is in the board
   job, but the quest tracker should say it plainly, with a "Dock at CALARI
   BEACON" route button, as it does for turn-ins.
2. **The pickup button may not show even at the right outpost.**
   `show_ask_btn` needs the docked outpost's id to match the job's
   `target_outpost`; for generated outposts the id comes from
   `GlobalState.resolve_outpost_id()` (`GlobalState.gd:941`), which only
   works if that outpost's contacts were registered under its `world_id`
   (`assign_generated_outpost_npcs`, `:633`). Unverified: needs a smoke check
   docking at a generated outpost with this job active. (Ask Abe: did he dock
   at CALARI BEACON itself?)
3. **Delivery target is hard-coded "Grease Monkeys"**
   (`PublicBoardOfferBuilder.gd:515` and `:635`), the start system's mechanic
   station, while the job was posted in Calari and the text says "bring it
   back here". Likely wrong for any job outside the start system: it should
   be the station that posted it.
4. **Contact name "Zeneshdramir Pilgrim Fleet Rook Rook":** contacts are
   named "<faction> <first> <last>" (`GlobalState._generated_contact_name`,
   :716), and "Rook" is in **both** the first-name and last-name lists
   (`GlobalState.gd:466` and `:490`), so "Rook Rook" can happen. Remove the
   overlap and never pick last == first. The faction prefix makes names very
   long in buttons ("Ask Zeneshdramir Pilgrim Fleet Rook Rook for
   Unlabeled Heat Sink"); show "Rook Vance (Zeneshdramir Pilgrim Fleet)" in
   text and just the person in buttons.
5. Small: the target window called CALARI BEACON "[Station]" (screenshot in
   finding 13) while the overview says "Outpost". Use the same type label.

**Proposed fix:**
- Quest tracker for pickups: "Dock at CALARI BEACON (outpost). Ask Rook
  Vance for the Unlabeled Heat Sink." plus a route button; after pickup,
  "Bring it to <posting station>".
- Lounge gossip about an active pickup ends with where to go ("...Rook's
  holding it out at Calari Beacon"), never implies the speaker has it.
- Fix 2 (verify + fix the id match for generated outposts), 3 (deliver to
  the posting station), 4 (names), 5 (label).
- Test: a smoke test that takes a public pickup in a generated system, docks
  at the target outpost, sees the Ask button, picks up, and turns in at the
  posting station.

#### 14b. Abe: treat this as a serious bug; it could affect a lot of quests

**More research (corrects two points above):**
- Problem 2 (button at the right outpost): the ids do match. Generated
  outposts get `world_id = "station.<system>.s<N>"` (`SystemFactory.gd:270`),
  their contacts are registered under that id when the system loads
  (`GeneratedSystemNPCManager._assign_outpost_npcs`, :65), and the job's
  `target_outpost` uses the same id. So docking at CALARI BEACON should show
  the Ask button. Still to prove with a test, but the likely story is: the
  game never told him to dock at the **outpost**; outposts have no lounge, and
  the lounge at the main station made it look like a lounge errand.
- Problem 3 ("Grease Monkeys"): for pickups the `destination` is **display
  text only** (`QuestManager.mark_pickup_complete`, :1059, and the
  inventory's special-cargo line). The real hand-in is the main station of
  whatever system you're in (`_quest_tracker_turn_in_target`, `UIManager.gd`
  :14841). So it isn't a blocker, but the text tells the player to go to the
  wrong place: "Deliver to <agent> at Grease Monkeys". Also in
  `MissionAdapter.gd:189` and the debug pickup.
- What the tracker shows today for a pickup: "Pick up Unlabeled Heat Sink"
  (`UIManager.gd:14018`) and a "Set Course: CALARI BEACON" button
  (`:14693-14707`). It never says **who** or that it's an **outpost dock**,
  nor what to press there.

**Why it's systemic (the pattern to fix everywhere):** quest text names
places and people, but whether the player can act on them depends on a
specific dock, button or object the text doesn't point at, and nothing
checks that every quest type's "next step" resolves to something real in
the current system. Same risk in the other types:
- `DELIVERY_COURIER` / `PURCHASE_DELIVERY`: destination by contact id
  (`_find_station_by_contact_id`), "Target Not In System" when it can't
  resolve.
- `INVESTIGATE_SIGNAL`: sites and turn-in station by id.
- `RECOVER_COMBAT_DROP`, `KILL_SHIPS`: target faction ships have to exist in
  the system (Kaelen's ledger job, step 11c, depends on Reavers spawning).
- `DELIVER_ORE`: fine (any station).
- Agent jobs vs board jobs vs premise arcs vs investigations build objectives
  in different places (`PublicBoardOfferBuilder`, `CollectionPostingBuilder`,
  `MissionAdapter`, GameRoot), so the same fields get filled differently.

**Proposed fix (one pass across all quest types):**
1. **One "next step" for every active quest:** a function
   `QuestNextStep.for(quest)` → `{text, target_node, action}` used by the
   tracker, the route button and N.O.V.A.'s "no idea where to go" line:
   e.g. "Dock at CALARI BEACON (outpost) and ask Rook Vance for the
   Unlabeled Heat Sink", then "Bring it to CALARI DEPOT (Talk to Agent)".
2. **At the dock:** when docked where the next step happens, the button that
   does it pulses (the Ask button already has an attention style), and the
   dock message says it.
3. **Delivery text from the real hand-in:** set `destination` to the
   posting station's name at accept time (never a hard-coded name).
4. **Lounge gossip** about an active job points at the next step's place and
   person; never implies the speaker has it.
5. **A quest-reachability smoke test** (`--quest-reach-smoke-test`): in a
   generated system, generate one of every quest type from every source
   (agent, board, premise arc, investigation, Kaelen), accept it, and check
   that its next step resolves to a node in the system (station/outpost/
   site/ships of the target faction) and that its action exists there (Ask
   button at that outpost, Talk to Agent at the hand-in, etc.). Fail loudly
   with the quest's title and the missing piece. This is what catches the
   next one of these before a playtest.
6. Names (problem 4) and the Station/Outpost label (problem 5) as above.

#### 14c. Fixed (2026-10-03)

**Root cause found by the new smoke test:** `QuestManager.get_pickup_special_data()`
only looked in the STATION and AGENT lanes; board jobs live in the BOARD
lane. So for **every public board pickup** the hand-over button never
appeared anywhere: the job could not be completed. (The outpost id matching
was fine.)

**Abe's design (during the fix):** board pickups should be a hunt: work out
who in the lounge has it and coax it out of them, with very dry humour.

What changed:
- `get_pickup_special_data()` / `mark_pickup_complete()` find the pickup in
  any lane, focused or not; the UI reads the pickup job, not whichever job
  is focused.
- Board pickups are lounge hunts (`lounge_hunt` flag, kept by
  MissionAdapter): the board text, templates and tracker name the outpost,
  never the holder (the dialogue validator no longer re-inserts the name).
  At the outpost there's no counter shortcut, a dock notice instead. In its
  lounge every contact has "Ask about it" (`scripts/domain/PickupHunt.gd`):
  bystanders deflect or point (always by the third), the holder denies,
  hedges, hands over on the third ask; a drink counts as an ask. The lounge
  chat context tells the holder to stay cagey and the others who's acting
  cagey.
- Tracker next step (`scripts/domain/QuestNextStep.gd`): where (and, for
  non-hunts, who, without the organisation prefix); after pickup, the real
  hand-in station. Board pickups' destination is this system's main
  station, not "Grease Monkeys"; station ids are never shown. Jenna's parts
  runs keep their shop and direct hand-over (also a "Pick up" on the
  holder's lounge card).
- "Rook" removed from the last-name list (no more "Rook Rook").
- Tests: `run_pickup_hunt_tests`; `--quest-reach-smoke-test` (real jump to a
  generated system, real board pickup, docks at the outpost, hunts in the
  lounge, picks up, checks the hand-in).
- Not done yet (still on the list): the wider every-quest-type reachability
  test (14b item 5), the Station/Outpost label (problem 5).
- Lines for Abe's review (small batch) are in `PickupHunt.gd`.
