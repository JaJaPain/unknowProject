# Next-Level Plan: week of 2026-09-29

Written before the weekly reset so work can start without exploration.
Order: **bug sprint first** (Section 1), then the **AAA push** (Section 2),
run as small committed bites (Section 3). Questions for Abe are in Section 4.
Standing rules still apply: small bites, commit often, push once per session,
headless tests one at a time with unique `--log-file`, windowed runs only
with Abe's OK, no fixed-cast secret anywhere, original art only, no text in art.

---

## 1. Bug sprint (all pre-located)

Each bug: where it is, the cause as far as known, the fix, the test.
Do them in this order; commit each one separately.

### B1. CRASH: undock checkpoint after a board job (stops play)
- Where: `scripts/persistence/SaveMigrator.gd:467` `_map_investigation_board`
  reads `objective["system_id"]`.
- Cause (confirmed): `scripts/domain/InvestigationOfferBuilder.gd:78` builds
  the INVESTIGATE_SIGNAL objective with no `system_id`. Any undock while such
  a posting is on the board crashes the checkpoint.
- Fix: builder sets `system_id` (the posting's system); SaveMigrator uses
  `.get()` and returns `_failure(...)` instead of crashing; same for
  `_map_investigation_sites/_contracts`.
- Test: new `tests/story/run_investigation_save_roundtrip_tests.gd`: post an
  investigation, `prepare_for_save`, restore, compare. Then `--dock` smoke.

### B2. Story model recast Kaelen as creditor/harasser
- Cause (confirmed): the legacy free-form campaign bible + chapter plan
  (qwen3:8b; `scripts/ai/NarrativeDirector.gd` fields incl.
  `opening_situation`, chapter beats with `eligible_entity_ids: npc.kaelen`)
  still run next to the Arc Engine / Premise Deck. Nothing forbids the fixed
  cast as creditor, antagonist or stake subject.
- Fix (small, now): in the bible and chapter-plan validators, reject any
  opening/beat/stake that makes `kaelen` or `nova` a creditor, threat,
  antagonist, victim or harasser (keyword + entity check), and tell the
  prompt so; debts go to invented NPCs. Reject Kaelen lines that say
  "Kaelen" (third person) in `_check_kaelen_intro_speaker`.
- Fix (bigger, see Q1): retire the legacy bible's authority over story
  beats in favour of the Arc Engine, behind a flag.
- Test: validator unit test with the "Toxic Debt" bible as a fixture.

### B3. "Destination Not In System" when it is
- Where: `scripts/UIManager.gd:13642`, target from
  `_quest_tracker_turn_in_target` (13796).
- Likely cause: the ore delivery's settle station ("the main station",
  Naktortalnak Claims Office) in a generated system does not match the
  system-id / contact-id rules there (main stations use the system id,
  outposts contact ids; generated systems may use world ids).
- Fix: resolve through the same lookup the dock/turn-in code uses
  (`get_world_id`, `resolve_outpost_id`) for every objective type, not just
  INVESTIGATE_SIGNAL.
- Test: tracker test in a generated system (headless, `--jump` fixture).

### B4. Offers with no decline; kill targets not present
- Where: the fallback choice sets in `scripts/LLMInterface.gd:~190-215`
  (accept / 50 up front / payout too low), plus LLM choice validation.
- Fix: every offer always gets a plain decline appended by code (not by the
  model); kill offers pick a target faction present in, or adjacent to, the
  current system (generated factions count).
- Test: offer-choice test asserting a decline exists for every template.

### B5. "[Offline Backup]" shown to the player; one contact in two orgs
- Where: `scripts/UIManager.gd:12823` and `12964` append the tag to visible
  text (TTS strips it at `TTSInterface.gd:702`).
- Fix: keep the tag only in logs / GenerationDiagnostics.
- Contact in two orgs: the contact name pool reuses "Juno Calder" across
  organisations; make names unique per campaign (NameForge) or tie a contact
  to one org.

### B6. Generated-faction ships show internal IDs
- Symptoms: `GEN_C4D50C0A4F59_F2 Interceptor 824`, overview type
  "Gen C 4d 50c 0a 4f 59 F 2", wrecks the same.
- Fix: NPC display name, overview type and wreck label go through
  `GlobalState.faction_display_name()` (GlobalState.gd:378), extended to
  generated factions (FactionDNA / generated_factions.json names).
  Same pass: REP row for generated factions, and "Uncharted System 28" /
  "UNCHARTED HAVE..." placeholder names (NameForge).

### B7. Tutorial: two Reavers for a one-kill mission
- Where: "Clean and Easy" special cases in QuestManager.gd:1447,
  CombatManager.gd:809, GameRoot.gd:913, GlobalState.gd:2338,
  LocalPressureDirector.gd:514, MissionOutcome.gd:90.
- Likely cause: a second Reaver from the ambush/raider/pressure spawns
  (this week's `spawn_raiders` / ambush complications) during the tutorial.
- Fix: no complications, ambushes or pressure spawns while the tutorial
  quest is active; mission spawns exactly its count.

### B8. Star map button lit on day 1 (first fix didn't work)
- Fix: gate on a jump having happened (a `visited_systems` count > 1 or a
  `first_jump_done` flag saved in GlobalState), not the registry size.

### B9. N.O.V.A. quiet moment during the load screen (voice + portrait)
- Where: quiet moment director in GameRoot.gd:1627-1760
  (`flush_pending_quiet_moment`).
- Fix: one gate for all of N.O.V.A.'s unprompted speech (portrait, voice,
  comms text): not while the load fade / landing / campaign loading is up;
  reset pending beats on new campaign.

### B10. Target panel active while the station tractor pulls the ship in
- Where: dock pull in `PlayerShip.gd:~2182` (tractor loop).
- Fix: hide the target panel's actions while the tractor/auto-dock is
  active; restore after undock.

---

## 2. The AAA push: what makes it feel like a real game

The inventory restyle proved the point: the same game feels far more
expensive when every screen shares one confident look. The push below
aims at the moments a player feels most, not at new systems. Ranked by
(impact on feel) / (cost), highest first.

### P1. Finish the one-look UI (docked screens) — high impact, low risk
Most play time outside flight is docked. Today those screens still mix
old per-panel styles with HudStyle.
- Agent conversation as a proper dialogue scene: large portrait on the
  left with a subtle frame and name plate, subtitle-style text with a
  typewriter reveal synced to TTS start, replies as full-width choice rows
  with keyboard numbers (1-4), decline always last. Trade grid stays a
  compact tray under it.
- Public board as mission cards: each offer a card with a variant accent
  (life-or-death red, funny amber, personal blue), rarity pips for fetch
  items, client name + org, reward and urgency chips. Hover lifts the card.
- Store and maintenance: reuse InventoryScreen's grid/detail pattern
  (same cells, same detail pane), so buying and owning look identical.
- Station menu as a hub: the station's name and faction banner at the top,
  service tiles with icons, the station exterior render behind glass.
- Verify with `--dock-snapshot` (fix its lounge hang first).

### P2. Game feel ("juice") in flight and combat — high impact, cheap
Small effects players read as quality:
- Hits: shield ripple / hull spark on impact, a short hit-stop (30-50 ms)
  on kills, screen shake scaled by damage (shake exists in PlayerShip and
  JumpTransitionFX: centralise it in one CameraShake helper).
- Weapons: muzzle flash light, tracer glow, distinct per ammo type
  (kinetic/thermal/explosive/energy already exist as items).
- Explosions: debris chunks that tumble and fade, a shockwave ring, a
  brief light flash; wrecks keep a slow burn.
- Speed: speed lines / dust particles that stream past faster at boost;
  subtle FOV widen on boost; engine glow already scales, add a boost flare.
- Damage state: low hull adds sparks, flicker on the HUD edge, N.O.V.A.
  warning cadence.
- All behind a settings toggle for shake intensity (accessibility).

### P3. Adaptive music and a proper sound mix — very high impact
Today: two flight tracks, lounge music, landing music. No combat music.
- Music states: explore / tension (hostile targeting you) / combat /
  docked / jump. Crossfade 1.5-3 s by state; stingers on kill, mission
  complete, jump arrival.
- Mix buses: music ducks under voice (N.O.V.A., Kaelen, radio) by ~6 dB;
  UI sounds on their own bus; a master limiter.
- Needs music assets: see Q3.

### P4. Arrivals and departures as moments — high impact, medium cost
The things players screenshot.
- Jump: charge-up (engine glow brightens, gate ring spins up, audio
  swell), tunnel (exists: scenes/jump_tunnel.tscn), arrival flash with a
  system title card (system name + controlling faction, fades out).
- Docking: when the tractor takes the ship, a short camera move to a
  third-person view of the station with the docking lights, then the
  station hub fades in. Undock: the reverse, with the ship pushed clear.
- First sight of a system: N.O.V.A. one-line read of the system quirk.

### P5. A living space — medium impact, medium cost
- Traffic: freighters flying lanes between station, outposts and gate;
  NPCs dock and undock (reuse NPCShip + existing dock points).
- Stations lit: running lights, blinking beacons, window emission.
- System radio voice per system (todo) and N.O.V.A.'s news lines (todo).
- Distant backdrop: nebula/planet skybox variety per system from the
  system seed (colour grading per star type).

### P6. Wire the content we already have — cheap, visible
- 81 fetch cards into the public board, with rarity and
  "where to find it" hints; then the store stocks rare items only where
  a hint points.
- Drone HUD frame into the drone camera view.
- Ore icons on sell/refine/buy buttons and the ore market.

### P7. Robustness is part of AAA
- A save round-trip test per saved subsystem (B1 shows the gap).
- A "first 20 minutes" scripted playthrough test: new campaign, tutorial
  dock, Kaelen, first kill, first ore sale, first jump; fails on any
  SCRIPT ERROR. Run it after every bite that touches GameRoot/UI.
- Error-proof the checkpoint: a failing subsystem mapper logs and skips,
  never crashes the game.

### P8. Retire the legacy story generator's authority (see Q1)
The free-form campaign bible + chapter plan still steer beats and can
contradict canon (B2). The Arc Engine / Premise Deck are built; let them
own the story, keep the legacy generator for flavour text only, behind a
flag, never deleted.

---

## 3. Execution order (bites)

Each bite: code, headless test(s), commit. Push at least once per session.
Smoke set after GameRoot/UI bites: core, dock, jump, combat (one at a time).

| # | Bite | Verify |
|---|------|--------|
| 1 | B1 crash + save round-trip test | new test, dock smoke |
| 2 | B2 fixed-cast guard in bible/chapter validators + third-person Kaelen reject | validator test (Toxic Debt fixture) |
| 3 | B3 turn-in target resolution | tracker test, jump smoke |
| 4 | B4 decline always + present-faction kill targets | offer-choice test |
| 5 | B5 hide [Offline Backup]; unique contact names | parse check, public-board smoke |
| 6 | B6 generated-faction display names, REP row, system/station names | generation-diagnostics smoke + snapshot |
| 7 | B7 tutorial: one Reaver | combat smoke |
| 8 | B8 star map after first jump | core + jump smoke |
| 9 | B9 one speech gate for N.O.V.A. during loads | core smoke |
| 10 | B10 target panel during tractor | dock smoke |
| 11 | P7 "first 20 minutes" playthrough test | runs green |
| 12 | P2 CameraShake helper + hit feedback + kill hit-stop | combat smoke + snapshot |
| 13 | P2 explosions (debris, shockwave, flash) | combat snapshot |
| 14 | P2 boost speed lines + FOV | snapshot |
| 15 | P1 agent dialogue scene | dock snapshot |
| 16 | P1 board as mission cards + P6 fetch cards on the board | dock snapshot, public-board smoke |
| 17 | P1 store/maintenance on the inventory pattern | dock snapshot |
| 18 | P1 station hub | dock snapshot |
| 19 | P3 music state machine + ducking (with placeholder tracks until assets) | core smoke |
| 20 | P4 jump arrival title card + charge-up | jump smoke + snapshot |
| 21 | P4 docking camera move | dock smoke + snapshot |
| 22 | P5 traffic lanes | core smoke |
| 23 | P5 station lights, per-system radio voice, N.O.V.A. news lines | snapshot |
| 24 | P8 legacy bible behind a flag | premise suite, restart smoke |

Stop-and-show points for Abe (windowed snapshots): after 14, 18, 21, 23.

---

## 4. Questions for Abe (answer before the reset if possible)

- Q1. Story authority: may the Arc Engine / Premise Deck own the story
  beats, with the legacy campaign bible kept only for flavour text behind a
  flag (P8)? Recommended: yes.
- Q2. Windowed snapshots: standing OK this week to open short game windows
  for screenshots (UI, VFX, docking) without asking each time?
- Q3. Music: can you provide combat / tension / exploration tracks (your
  own, a music generator, or licensed packs), or should the state machine
  ship with the existing tracks re-used until then?
- Q4. Art batch: OK to hand you one list of ChatGPT prompts (Section 5) to
  run whenever you have time, in parallel with the code work?

---

## 5. Art batch for ChatGPT (queued in docs/image_needs.json)

All original, no text, no existing-franchise references. Status "pending"
in image_needs.json; mark "done" as each lands.
- Station service icons (one sheet): agent, public board, store,
  maintenance, upgrades, lounge, refinery, storage.
- VFX flipbooks: explosion (8x8), muzzle flash, shield ripple, spark burst,
  shockwave ring, engine boost flare.
- Nebula/sky backdrops: 4 panoramas by star type (warm, cool, dusty, dark).
- Mission-card accents: three subtle background textures (red hazard,
  amber comic, blue personal) with no symbols or text.
