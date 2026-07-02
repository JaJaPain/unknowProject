# TODO
_Active task list. Update this file at the end of every session._

---

## Combat -- Unified System (do in order, blocks everything below)

- [x] **FactionRegistry.gd autoload** -- single source of truth for all faction data: known profiles (aurelia/vanguard/zenith) + unknown faction progression list ordered by tier; `get_profile(key)`, `get_faction_for_danger_level(n)`; runtime override dict so tuning tool can hot-apply changes without touching the const.
- [x] **Unknown faction progression list** -- 4 factions per tier band, each band covers ~4 generated systems; same tier = same damage/HP budget but different combat role, weapon bias, shield vs hull split, and aggression pattern so each feels distinct to fight. Proposed bands:
  - **Band 1** (systems 2-5): Rift Collective (weapon-heavy burst), Hollow Syndicate (engine-heavy hit-and-run), Pale March (hull tank, braces constantly), Cinder Wake (repair-capable attrition)
  - **Band 2** (systems 6-9): Eclipse Legion (balanced), Obsidian Pact (shield-heavy), Ashen Drift (reposition every turn, chip damage), Iron Chorus (disable-focused)
  - **Band 3** (systems 10-13): Void Covenant (all-round high), Shatter Bloc (extreme weapon bias), Null Meridian (drone-specialist), Fracture Syndicate (squad-oriented)
  - **Band 4** (systems 14+): elite tier, reserved for late-game / story systems
- [x] **Faction tuning tool** -- Numpad 7 opens unified DevPanel; faction tuning tab with all factions x tier fields, up/down per cell, hot-apply + save to `user://faction_tuning.json`. DevPanel also has Spawn Boss, Spawn Squad, Restock actions. Extensible via `add_action_button()` / `add_tab()`.



- [x] **Step 1 -- CombatAction.gd: expand enum** -- BRACE, FLANK, SHIELD_ANGLE, DISABLE_ENGINES added with AP costs + labels.
- [x] **Step 2 -- NPCShip.gd: tier vars + faction profiles** -- tier vars added; `apply_faction_profile()` derives all combat stats; `_action_*` helpers use `CombatAction.make()`.
- [x] **Step 3 -- CombatManager.gd: unified execution** -- `_execute_npc_action` on int enum; damage in `params`; `_apply_hit` applies faction resistances.
- [x] **Step 4 -- Spawning: apply profiles** -- `MainScene._spawn_npc()` and `GeneratedSystemNPCManager` all three spawn paths wired.
- [x] **Step 5 -- Sensor sig table: collapse to one** -- `SENSOR_SIGS_NAMED` deleted; single int-keyed table in CombatPanel.

## Combat -- Unlocked by unified system

- [x] **Pre-combat sensor scan** -- at `combat_started`, typewriter-decode target's tier loadout in sensor panel. Tier 0 sensor = "THREAT LEVEL: HIGH / EXTREME", Tier 1 = individual stats ("Hull T2 / Weapons T3 / Engine T1"), Tier 2 = full assessment + warning ("Weapon systems exceed your fit by 2 tiers").
- [x] **Sensor upgrade path** -- adds `sensor_tier` (0-2) through maintenance-bay ship upgrades; gates how much pre-combat intel the player sees. `sensor_cluster` remains a store ship-part/trade item for now rather than a required install component.
- [x] **Difficulty scaling via profiles** -- done; all spawn paths call `apply_faction_profile()` with tier-matched unknown faction or named known faction.
- [x] **Boss as tier override** -- story-triggered boss = `apply_faction_profile(profile, tier_override)` instead of hardcoded stats; `GameRoot.trigger_boss_encounter(faction, tier, role)` now provides the story/dev hook.
- [x] **Mixed-profile squads** -- `GameRoot.trigger_squad_encounter()` can spawn mixed profile squads (e.g. Tier 1 Interceptor + Tier 2 Gunner); makes 2-on-1 fights more varied than two identical ships.
- [x] **Phase 6 -- Enemy kit parity** -- BRACE and REPOSITION now in enum; NPC planners use them as real actions with camera beats, SFX, status floats, chatter, and taunts.
- [x] **Damage type resistance** -- `weapon_dmg_mult` / `drone_dmg_mult` per profile, applied in `_apply_hit()`. Hull composition in sensor scan.
- [x] **Damage number visual feedback for resistance** -- resisted hits show small dim `RESIST` numbers; vulnerable hits show large bright `WEAK` numbers. Player reads the difference in the moment and learns without being told explicitly.
- [ ] **Phase 7 -- Boss (mega)** -- DONE (in-game) but needs StoryManager trigger hook so scripted story beats can spawn the boss fight (see Story section below)
- [ ] **Phase 8 -- Squads** -- DONE (in-game) but needs StoryManager trigger hook (see Story section below)
- [ ] **Shield Reroute sub-picker** -- currently defaults to Front face; needs the face-select sub-wheel
- [ ] **Boost direction toggle** -- currently defaults to "closer to enemy"; needs toggle for Evade/Close
- [x] **Attack drone visual** -- strike now peels the nearest green orbiting drone out of formation (hides it for the run) and launches a matching green strike-drone from that position instead of a blue ball from the ship center. Camera rides a POV chase cam behind the diving drone, with a green drone-cam reticle overlay (corner frame + center crosshair + enemy-tracking bracket) via `scripts/DroneReticle.gd`. Hands back to the impact framing on the hit. (`PlayerShip.gd` `launch_combat_drone` / `_begin_drone_pov` / `_end_drone_pov`)
- [x] **Salvage drone wreck action** -- wreckage targets now expose a disabled/enabled `Salvage` action with tooltip reasons; spending 1 salvage drone starts the existing salvage loop without opening inventory.
- [ ] **Enemy low-health escalation arc** -- enemy dialogue/behavior should escalate when below 30% HP
- [ ] **Impact decals on player ship** -- hull hit marks that persist during a fight
- [ ] **Richer combat taunt flavor** -- taunt bucket system: reason-aware taunts (flanked, shielded, drone hit, etc.)
- [ ] **Execute button flashes when AP fully spent** -- when the player has spent all their AP, pulse/flash the Execute button to signal the turn is ready to commit.

---

## Story / Narrative System
_Full design in `docs/design_narrative_system.md`. Build in order -- each phase depends on the one before._

- [x] **Phase A -- Campaign Spine Generator** -- gemma4 generates the campaign bible at new-campaign start (`NarrativeDirector.gd` + `LLMInterface.request_campaign_bible_generation`). Made reliable 2026-07-01 (`think:false` fixed JSON reliability; deterministic creative lanes + anti-motif guidance fixed motif collapse). `kaelen_angle` (her hidden angle) added to the schema 2026-07-02, protected the same way as hidden truths -- never shown to any prompt, only used to derive a mood descriptor.
- [x] **Phase B -- Story State Document** -- StoryManager gets a live `story_state` dict (chapter, active_tensions, player_knows, hidden_truths, current_foreshadow, kaelen_mood). `get_story_context_block()` returns a short string injected into every LLM prompt. `advance_chapter()` fires on chapter-link mission completion. Persisted via `StoryStateStore` (CampaignTransactionStore pattern). `LLMInterface.story_state_context_text` injected as `### STORY STATE:` block in quest prompts. **2026-07-02: the bible->story_state bridge was actually missing until now** -- `seed_story_state_from_bible()` finally connects Phase A's generated content into this living state (previously it silently stayed empty forever); includes a migration path for pre-existing saves.
- [x] **Phase C -- Mission Causality** -- 2026-07-02: `because` field threads active tension into quest prompts; `story_hook_ref` stamps a quest with the hook it was generated for; completion resolves that hook and checks chapter advancement. Chapters never end the campaign -- hook exhaustion refills from the bible's reserve, then falls back to a `regeneration_trigger` LLM call (retry-once + logged fallback counter, never silent).
- [x] **Kaelen handoff pool** -- Gemma4 pre-generates 16 story-aware Kaelen intro lines per agent during gate travel dead time; stored in `kaelen_handoffs.json` via KaelenHandoffStore; drawn instantly in `request_kaelen_intro` before falling back to small model. Triggers: game start, gate "Fly to", system arrival (top-up), chapter advance (replace). Full design in `docs/plan_kaelen_handoff_pool.md`.
- [x] **Phase D -- Kaelen Integration (partial)** -- 2026-07-02: `kaelen_hidden_angle` seeded into story_state, derives `kaelen_current_mood` (mood-only, angle never reaches any prompt); `request_kaelen_reaction()` now gets mood context (previously got none). Still missing: `kaelen_chapter_comment` / `kaelen_hint` line types (deferred, low-risk to add later).
- [ ] **Phase E -- Ambient NPC Dialogue** -- `AmbientChatGenerator.gd` fires every 3-5 min during open play. Picks topic bucket (story-adjacent / mundane / overheard-intel) from StoryManager, writes 2-4 lines between two NPC archetypes via small model, delivers via `GlobalState.emit_chatter()`. `used_topics` list prevents repeats within a chapter. Target ratio: 50% mundane, 30% story-adjacent, 20% overheard intel. **Next up -- explicitly deferred 2026-07-02 as a new subsystem, not wiring.**
- [ ] **Automatic story screenshots** -- the game silently captures screenshots at key narrative moments and stores them in `user://campaign_screenshots/`. Triggers: first jump to a new system, kill cinematic frame (the moment of death, not the explosion), chapter advance, boss kill, first dock at a new station, mission completion that closes a story hook. One screenshot per trigger, no UI -- capture a clean frame with `get_viewport().get_texture().get_image()` then `image.save_png()`. StoryManager owns the trigger calls. Screenshots are embedded into the campaign PDF at closure, placed alongside the prose for the moment they captured.
- [ ] **Campaign closure -- Story PDF + permanent lock** -- When a player chooses to end a campaign, gemma4 compiles the full story into a readable narrative document: the inciting event, the chapter arc as the player experienced it, key missions and what they meant to the larger story, Kaelen's thread, and the ending. Delivered as a PDF saved to the user's machine. The campaign save is then permanently locked -- marked as `ended`, all missions and travel disabled, the slot shows "ENDED" in the save screen. The story is theirs to keep. The world is closed. This is the equivalent of finishing a book -- you don't go back and replay chapter 3. New campaign for a new story. PDF generation via GDScript writing HTML and converting, or via a simple text layout written to a styled file. Include the campaign name, playtime, systems visited, missions completed, and the narrative prose gemma4 writes from the story state history.
- [x] **Phase F -- Rumors** -- 2026-07-02: rumor trails seed `pending_hooks`; `on_docked()` has a ~40% chance to fire a rumor via the existing `get_lounge_rumor()`/`record_lounge_rumor_heard()` pipeline (already built, was just never triggered). Hook marked "hinted" via dedup list, same as the existing NPC-conversation rumor path.
- [ ] **Story-aware lounge dialogue** -- lounge NPC lines should feed from StoryManager by default, not generic flavor. Even casual lines should reflect current chapter, local faction tension, station/system context, player reputation, Kaelen suspicion thread, or nearby opportunities. Pure throwaway jokes are allowed only as rare texture.
- [ ] **Lounge conversation choices + consequences** -- extend the dock-message response row so LLM lounge lines can return 2-3 player replies. Replies can produce follow-up lines, small faction rep gains/losses, temporary contact cooldowns, or unlock/close rumor leads.
- [ ] **Kaelen suspicion lounge thread** -- Kaelen lounge lines should gradually imply she knows too much and arrives too conveniently at main stations, without revealing her hidden angle. StoryManager owns what can be hinted each chapter.
- [ ] **Faction lounge social checks** -- faction agents in the lounge react to reputation; good conversations can grant a small rep bump or a discounted lead, bad conversations can cause a small rep hit or make that contact cold for a while.
- [x] **Boss fight trigger tool** -- expose `GameRoot.trigger_boss_encounter(faction, tier_override, role)` so StoryManager can script a boss ambush as a story beat
- [x] **Squad fight trigger tool** -- expose `GameRoot.trigger_squad_encounter(faction, count, base_tier, roles)` for scripted 2-on-1 ambushes. Good future callers: anomaly outcomes and public-board combat contracts.
- [x] **Anomaly data core delivery** -- anomaly drops a named data core; player delivers to NPC for payout via special cargo system
- [x] **Salvage drone wreck action** -- (also listed under Combat) targeted wreck action replaces the post-kill prompt idea so salvage is available from `Fly to` / `Orbit` / `Salvage`.

---

## Navigation / Autopilot

- [ ] **Docking sequence** -- replace instant snap with a 3-second felt transition: input lock -> ship tween into collar -> camera hold + clamp SFX -> fade-in dock UI. Enemies in active pursuit hold at dock initiation (not arrival), re-engage on undock with a warning chatter line. One new file: `DockSequence.gd` state machine; everything else reuses JumpTransitionFX, EngineExhaust, and the existing camera node. Full design in `docs/plan_docking_sequence.md`.
- [ ] **Fix autopilot avoidance regression** *(see bugs.md for full root-cause analysis)*
  - Wire `_get_autopilot_avoidance()` back into the autopilot movement block (`PlayerShip.gd:740-754`). It exists and works but is not being called.
  - After `_route_steer_target()` returns a `steer_target`, pass it through `_get_autopilot_avoidance(steer_target, active_target)`. When `is_avoiding` is true, use the avoidance waypoint as the actual steer target.
  - This gives two complementary layers: A* planner handles the macro route, real-time avoidance handles surprises mid-flight.
- [ ] **Forward whisker (nose sensor) for imminent collision**
  - Add a `RayCast3D` pointing forward (`-Z`) on the ship. No new scene node needed -- configure it in `_ready()`.
  - In `_physics_process` during autopilot: if the raycast hits something within ~50u that is not the nav target, call `_clear_planned_route()` immediately to force a fresh A* replan without waiting for the 2.5s stall timer.
  - Godot equivalent of the Unity "empty object on ship nose" pattern. The raycast IS the whisker.
- [ ] **Fishtailing in tight spaces** -- ship wiggles its butt side to side when trying to squeeze into a tight area (e.g. navigating close to a station or between asteroids). The steering overshoots, corrects, overshoots the other way, and oscillates instead of committing to a clean line. Needs dampening on the angular correction when the ship is close to an obstacle and the heading delta is small -- reduce turn aggression proportionally to proximity so it slides in smoothly instead of wagging its tail. **Fix is in `steer_towards()` in `PlayerShip.gd`** -- when proximity to an obstacle is detected AND the heading correction angle is small, scale down the turn rate so the ship commits to the line rather than overcorrecting back and forth.
- [ ] **Route validity re-check while following waypoints**
  - After each waypoint is passed (`planned_route_index` advances), call `NavigationRoutePlanner.route_is_clear()` on the remaining waypoints against current hazards. If it returns false, replan immediately.
  - Catches cases where an obstacle moved into the planned path since the last full replan.

---

## World / Exploration

- [ ] **Map hover tooltips** -- hovering a map node shows stations, ore types, factions present
- [ ] **Route planner** -- click-to-plan route; gates highlight in overview; auto-clears on arrival
- [ ] **Gate portal particles** -- particle effects off the gate portal (portal shader is locked/approved, don't touch it)
- [ ] **Generated systems: NPC ships** -- procedural systems feel empty; need ambient NPC traffic
- [ ] **Generated systems: station variety** -- all proc-gen stations look the same; need visual variants
- [ ] **Generated systems: difficulty scaling** -- enemy stats should scale with system danger level
- [ ] **Discovery visual treatments** -- named/story systems should feel different on arrival: skybox tint, arrival text banner, environmental storytelling (debris, explosion haze). See `docs/design_parking_lot.md section2`
- [ ] **Sensor contacts panel (name TBD)** -- when a ship comes within passive-sensor range (or you're in combat with it), it's added to a contacts list. Open the list to view that ship's 3D model (rotatable) plus the details your sensors picked up: ship class/role, weapon types, power supply/reactor, shields, hull composition, faction, etc. Fidelity of detail could scale with sensor strength / scan time. Data already partially exists on `NPCShip` (weapon_tier, powerplant_tier, hull_composition, shield_tier, archetype) -- surface it here. Kitbash ships make the 3D model view cheap to render. **3D viewer already built:** `scripts/ui/ModelViewer.gd` + `scenes/ui/model_viewer.tscn` (orbit-drag/zoom/auto-spin, `show_ship(faction,role,seed)` / `set_model(node)`) -- just drop it into the panel.
- [ ] **Rumor-instanced anomalies** -- anomalies should not all pre-exist as obvious map loot. A lounge/story rumor can spawn a hidden anomaly in a plausible region of the current system, then system chat records the unverified lead ("Possible anomaly signal added to local sensor memory"). State flow: `rumored` -> `sensor_contact` -> `identified` -> `resolved`.
- [ ] **Rumor-instanced derelict ships** -- same loop for dead ships: lounge/story rumor spawns a hidden derelict, initially invisible to overview. It resolves from "weak metallic signature" to "derelict ship" only after the player gets close enough or scans it.
- [ ] **Overview reveal radius for anomalies/derelicts** -- hidden exploration objects should appear on overview only inside passive sensor range. Reveal distance should scale with scanner quality, object signal strength, and possibly purchased/earned intel quality.
- [ ] **Visual reveal distance matches sensor reveal** -- anomalies and derelicts should not be visibly obvious from across the system before overview can detect them. Their render/fade-in distance should correspond to the same sensor reveal rules.
- [ ] **Search-zone hints instead of exact markers** -- lounge NPCs and system chat should point to regions ("outer belt", "near Kova outbound lane", "past the gas giant") rather than exact object markers unless the player buys high-quality intel.
- [ ] **Discovery outcomes from rumors** -- rumor-spawned finds can resolve into anomaly data cores, hidden caches, derelicts, rare salvage, illegal goods, or ambushes so the lounge becomes an exploration seed source instead of a flavor-only room.

---

## UI / UX

- [ ] **Landing page / campaign select** -- late-process main menu that finally gives the game a real front door. Needs a `Continue` button that loads the most recently played campaign, three visible campaign slots showing what is in each slot, actions to load another campaign, delete a campaign, and create a new one. Use a cool animated backdrop such as a rotating space station / orbital scene instead of a static flat menu. Also use this phase to brainstorm and choose the real game title, since the current title is only a placeholder.
- [x] **Quest tracker panel blue box on second quest** -- `reset_size()` now fires after the tracker content is rebuilt so the panel shrinks back to content on quest changes.
- [ ] **Station lounge UI / social layer** -- give the lounge its own polished interface instead of a plain utility menu: contact cards, relationship heat bar, contact moods, "last seen" timestamp, rumor badge, available conversation/action buttons, and a layout that can support dynamic NPCs and bartering later. See `docs/design_parking_lot.md section1`
- [ ] **Lounge black-market passerby** -- occasionally spawn a temporary traveler in the lounge who offers questionable goods: stolen/illegal ship upgrades, unstable experimental parts, or blueprint/data chips that a shady mechanic can install for a bribe. Offers should be reputation/story/context aware and may be scams.
- [ ] **Unstable dynamic NPCs & Dynamic Bartering** -- Docking at station lounges puts you in contact with unstable dynamic NPCs. Instead of traditional visual menus, trading rare cargo updates into a dynamic bartering sequence.
- [ ] **Store presentation polish** -- item cards, purchase confirm dialog, inventory integration, mission highlight. See `docs/design_parking_lot.md section3`

---

## Shipping / Deployment (Ollama)

The game depends on Ollama for all LLM content (taunts, quests, Kaelen dialogue).
The watchdog in `LLMInterface.gd` already auto-starts Ollama and pulls missing models.
Deployment checklist for a shipped build:

- [ ] **Bundle ollama.exe** -- copy the Ollama binary into `ollama/ollama.exe` next to the game executable. The watchdog checks this path first before LOCALAPPDATA or PATH.
- [ ] **Choose a shippable model** -- `qwen2.5:3b-instruct-q4_K_M` (current small model) is ~2GB. Verify its license permits commercial distribution. Mistral 7B (Apache 2.0) is a clean alternative. `gemma4:12b` (large model) is too big to bundle -- decide if large-model features ship or are skipped.
- [ ] **Bundle the model file** -- Ollama stores models in `%USERPROFILE%\.ollama\models\`. For a fully offline install, pre-populate this folder in the installer OR ship a GGUF file and set `OLLAMA_MODELS` env var to a path inside the game bundle.
- [ ] **First-run model pull fallback** -- if model is not bundled, the watchdog auto-pulls it on first launch. This requires internet and takes 2-5 min. Show a loading screen / progress message to the player during this window (currently silent in-game).
- [ ] **First-run UX** -- add a splash/loading state that shows "Preparing AI systems..." while the watchdog polls and the model pulls. Do not drop the player into the main menu until `_ollama_ready` is true and models are confirmed.
- [ ] **Installer script** -- write a setup script (NSIS / Inno Setup) that: copies `ollama.exe`, sets `OLLAMA_MODELS` to a bundled path, and optionally pre-warms the model on install so first launch is instant.
- [ ] **macOS / Linux path** -- watchdog already checks `/usr/local/bin/ollama` and `ollama` on PATH. Test on those platforms. Mac may need a signed/notarized ollama binary.
- [ ] **Offline mode** -- if Ollama never comes up (no internet, corporate firewall, etc.), the game should surface a clear one-time message: "AI features unavailable -- game will use built-in dialogue." Currently just logs to console.
- [ ] **Maybe: optional cloud AI provider settings** -- long-term possibility: let the player choose to use cloud APIs instead of bundled/local Ollama and local TTS. This should be opt-in, clearly labeled, and never required for offline play. Needs a provider abstraction for LLM + TTS, secure API key storage, cost/privacy warnings, rate-limit handling, fallback to built-in/local dialogue, and separate settings for text generation vs voice generation. Good fit after `llm_model_profiles.json` / provider adapters exist.

---

## Illegal Upgrade Loop (Narrative & Gameplay)

- [ ] **Illegal Blueprint Salvaging & Upgrades**
  - **1. The Trigger: Salvaging the Blueprint** -- Add a rare chance to drop an `Encrypted Data Core` during wreckage salvage (`Wreckage.gd` / `NPCShip.gd`). This item goes into `PlayerInventory.gd` with metadata of an illegal blueprint variant (e.g., "Overclocked Plasma Core"). Inspecting it in the inventory (`UIManager.gd`) uses LLM for rendering a short description, and triggers the AI companion Kaelen (`TTSInterface.gd` / `KokoroSpeechProvider.gd`) to warn the player: *"Warning: This schematic bypasses standard Concord safety protocols. Possession is a class-G sector felony."*
  - **2. The Scavenger Hunt** -- Require specific items: Material A (ore from mining belts with lasers) + Material B (salvaged component from a specific enemy ship archetype like Interceptor/Logistics of a particular faction, hunting them down via `CombatManager.gd`).
  - **3. Finding a Shady Mechanic** -- Tag certain stations/outposts as having a low-ethics mechanic. When docking there, the mechanic's intro (`_render_mechanic_intro` in `UIManager.gd`) adapts to offer illegal installation if the player has the core and materials, demanding a hefty credit bribe (*"but for 15,000 credits, my cameras can go offline..."*) played in a quiet, rough voice profile.
  - **4. Mechanical Payoff & Security Risk** Once installed (`apply_upgrade_stats`), player gets a game-changing unlicensed weapon/part (e.g. purple ionized beam drone, speed-limit breaking booster). However, scans near outposts by patrols (`IllegalMiningEnforcement.gd` logic) will flag "Illegal Modification Detected", triggering alerts, massive bribes, or dogfights.

---

## Electronic Warfare (combat extension)

- [ ] **Electronic warfare capability** -- an EW option that extends the existing turn-based combat ring. Delivery is open (decide later):
  - **As a ship upgrade** -- installed capability that adds an EW action/tab to the combat wheel (parallels shield reroute / drone slots).
  - **As a consumable drone** -- a deployable EW drone (like the attack/salvage drones) for a one-off effect without a permanent install.
  - **Or replacing/adding a combat-ring tab** -- fold EW into the action wheel as its own pick.
  - **Possible effects to flesh out:** sensor jamming (reduce enemy accuracy / delay their turn), disable enemy shields or engines for a turn, spoof targeting, scramble drones, mask the player's signature to break lock. Tie into the existing `DISABLE_ENGINES`/`SHIELD_ANGLE` action vocabulary and faction resistances.
  - **Why it fits:** natural extension of the unified combat system (AP costs, camera beats, status floats already exist); gives a non-damage tactical lane and more build variety. Design the effect set + delivery method before building.

## Intra-System Jump Consumable

- [ ] **Emergency jump beacon (expensive consumable)** -- one-use item that jumps the player directly to any station/outpost **in the current solar system** (not cross-gate). Details:
  - **Warmup:** 5-second charge before the jump fires. If combat starts (or an existing fight interrupts) during warmup, the jump is **canceled AND the consumable is still consumed** — the risk is part of the cost.
  - **Cost/economy:** expensive to buy; a deliberate "get me out of here / skip the haul" luxury, not routine travel.
  - **Acquisition:** buyable at stores, plus a **chance to drop from salvaged wreckage** (ties into the salvage loop).
  - **Visual/FX:** needs a cool jump animation/effect similar to the existing gate-jump sequence (reuse the gate portal shader/transition where possible, but distinct enough to read as a short-range beacon jump, not a gate).
  - **Design notes:** decide targeting UI (pick destination from system map/known outposts only); block use if already in combat; refund vs. no-refund on cancel (current call: consumed, no refund); interaction with autopilot/PlayerInteractionQueue for the warmup timer.

## Ship A.I. Companion (fake AI, LLM-driven)

- [ ] **Onboard ship A.I. ("fake" AI) with personality** -- a persistent voice on the player's own ship that talks to them during play, primarily to fill the long transit stretches between stations/gates. Core jobs:
  - **Threat alerts (priority)** -- TTS warning on severe threats (incoming hostiles, low hull/shield, ambush, high-tier enemy detected on sensors). These pre-empt jokes/idle chatter.
  - **Navigation/status callouts** -- announce when the ship needs to reroute (hazard, blocked route, autopilot avoidance, fuel, gate coords updated), arrival ETA, "approaching X".
  - **Idle transit chatter** -- during long flights with nothing happening, fill the silence: observations, ship-status musings, and deliberately terrible **dad-style jokes / puns** (almost painful, that's the charm). Rate-limited so it stays charming, not annoying.
  - **Personality** -- consistent character and voice (distinct from Kaelen). Dry-but-earnest, over-eager, bad-comedian energy. Give it a name later.
  - _More responsibilities to flesh out later (combat commentary, contract reminders, rumor/lead nudges, reacting to player deeds, mood tied to story state, etc.)._
  - **Tech notes:** LLM-generated lines (small model) with logged fallback bucket per `project_fallbacks_are_failures`; TTS via `SpeechService` with its own voice profile; gate delivery through PlayerInteractionQueue so it never talks over combat/cutscenes; severity tiers so threat alerts always beat idle jokes. Design a short doc before building — decide trigger sources (sensors, autopilot, CampaignClock idle timer) and the anti-annoyance pacing/cooldown rules first.

## Polish / Future

- [ ] **Kitbash ships: extend to other factions** -- only `vanguard` is wired (`ASSEMBLED_FACTIONS` in `NPCShip.gd`). Add Zenith (NavyBlueMetal/ZenithBadge), Aurelia (ForestGreenMetal/AurelliaBadge) to `ShipAssembler.FACTION_STYLE`, then add to `ASSEMBLED_FACTIONS`. Hybrid plan: introduce a few NEW hull designs for new factions and recycle existing ones in by system 4-5.
- [ ] **Kitbash ships: per-faction normal variants** -- wire `hull_normal_var_1..9.png` into `FACTION_STYLE` so factions read distinctly beyond color.
- [ ] **Kitbash ships: mesh-merge + texture atlas (deferred opt)** -- only if hundreds of ships on screen; merge each design's parts into one mesh + atlas. Recipe data already supports baking later.
- [ ] **Kitbash ships: greeble pass** -- designs currently use hull+engines+weapons only; the `greebles/` (64) and `detail/` (13) part folders are exported but unused. Add bridges/antennas/vents for extra silhouette interest.
- [ ] **Thruster nozzle split for ALL engine parts** -- only `5-Engine` has its nozzles split into a `Thruster` material so far (done via Blender MCP: separate the rear nozzle/fan loose parts, assign a 2nd material slot, re-export). Do the same one-time split for every engine in `assets/ship_parts/engines/` so each gets a metal nozzle + proper thrust plume. One-time per piece, then works forever for all future ship builds. Assembler already routes "Thruster"-named surfaces to the thruster material.
- [ ] **NPC exhaust glow rework** -- current `NPCShip._create_engine_glow` draws flat sphere blobs at the engine markers (read as stickers, not thrust). Make them look like proper thruster exhaust -- space-game stylized, not photoreal: tapered plume/cone, hot core + falloff, subtle flicker, speed-scaled length, maybe a short trail. Color per faction (`_get_engine_color`).
- [ ] **Player ship: gunmetal hull.tall (hero ship)** -- replace the old INDYMiner player model (UVs/mesh trashed from Trellis). Plan: (1) bring `hull.tall` back into Blender and **separate the thruster from the engine body** as distinct meshes/material slots so each can take its own UV (crisp exhaust is the priority -- player stares down it for hours). (2) Re-export; keep hull.tall as the body. (3) Cockpit detail = two **emissive white rectangle decal strips**, one in each of the two circled front spots -- that's enough once the exhaust is crisp. (4) Orient fore-aft: hull.tall's long axis is Y (14.5) -- its TALL end is the engine/exhaust cluster (confirmed good-looking), point that at the camera. (5) Wire into `scenes/player_ship.tscn` / `PlayerShip.gd` Visual, refit collision box + camera distance. Gunmetal style already exists in `ShipAssembler.FACTION_STYLE`.
- [ ] **Player ship: try opposite tilt** -- `PLAYER_SHIP_TILT_DEG` in `PlayerShip.gd` is 0 (upright) now. Tried +18 deg (leaned wrong way). Worth trying **-18 deg** (lean the other direction) to show more exhaust/top in the behind-above camera. One-line change to evaluate.
- [ ] **Drones: make fitment parametric** -- drone orbit/size are hardcoded to ship scale (`PlayerShip.gd` `_create_drones` orbit_radius=6.8 :2090, sphere_radius=0.12 :2091; salvage rest 6.8 ~:2311; combat drone scale 1.8 :1917). Derive from player visual AABB in `_ready` so any new ship -- and future ship-upgrade hull swaps -- auto-fit. See memory `project_drone_ship_fitment`.
- [ ] **Kitbash ships: cockpit lights** -- add a warm emissive glow at the cockpit/bridge area (lit windows). Approach: emissive marker/quad near the bow-top, or an emissive sub-material. Player liked the rest of the parts as-is; cockpit lights + thruster rework are the two finishing touches before these "look great."
- [ ] **Badge polish** -- dorsal badge is small/subtle on large hulls; consider cropping to emblem-only (drop wordmark) for hull decals.
- [ ] **NAS asset migration** -- move binary assets off git repo to NAS once hardware acquired; binaries-in-repo is accepted interim
- [ ] **Boss cinematic phases** -- phase transition should have its own brief camera moment / sting beyond the current chatter line
- [ ] **Multi-boss / 3-on-1** -- true squad fights beyond 2 enemies; needs a target picker on the wheel

- [ ] **Player thrusters: tune yellow flame output** - current plume raggedness/motion is acceptable, but the warm/yellow fire replacement is still not visually readable. Revisit later: make warm output appear as sparse white-yellow flame flickers inside the blue exhaust, not solid rods or invisible shader noise. Current best thruster settings are backed up as `scripts/visuals/ThrusterBank.gd.current_best_backup` and `assets/shaders/thruster_plume.gdshader.current_best_backup`.

---

## Agent exploration quests (new objective type)
- [ ] **Exploration / investigate contracts** -- agents (and maybe Kaelen) offer "go look at X" jobs that aren't kill/deliver/pickup: investigate an **anomaly**, a **dead/derelict ship**, or a **strange signal**. Outcome is a reveal on arrival — sometimes loot/data, sometimes a **trap** (ambush spawns, comms flips hostile). Ties into anomaly data-core delivery (see memory `project_anomaly_data_core_delivery`) and the story system. Needs: a new MissionCapability (e.g. INVESTIGATE_SIGNAL) + spawn/arrival trigger + LLM-generated hook/reveal lines (fallback bucket in `llm_dialogue_content.json`). Keep the trap odds tunable.

---

## LLM Dialogue -- kill static/canned lines
_Standing goal (ties to `project_fallbacks_are_failures`): incidental Kaelen/NPC lines that currently cycle a fixed string array should be generated fresh each time so they never repeat and never read as canned. Convert as spotted. Each conversion keeps the existing static lines as the LOGGED fallback bucket (LLM offline/slow), not the default._

- [ ] **Kaelen "no work available" cooldown lines** -- `StoryManager.get_agent_contract_availability()` (`scripts/story/StoryManager.gd`) returns one of 3 hardcoded strings by `agent_cooldown_message_index` (e.g. "No one is asking right now. I will send you a message when I need you to make us some more money." — confirmed canned in-game 2026-07-02, screenshot). Convert to an LLM call (Kaelen voice, "Shiny" allowed, first-person, mentions no contracts + to wait) so it's new each dock. Feed current story/faction context. Keep the 3 existing lines as the fallback bucket in `llm_dialogue_content.json` and log via `record_fallback("kaelen_no_work", reason, ...)` if the model is unavailable.
- [ ] **TTS ping when contracts become available again** -- Kaelen's cooldown line promises "I will send you a message when I need you" but nothing fires when the cooldown actually expires. Add a proactive notification (Kaelen-voice TTS via `SpeechService` + a `GlobalState.emit_chatter` line) at the moment `agent_cooldown_until_minute` passes — needs a per-minute check (CampaignClock tick) that detects the cooldown→available transition and fires once. Line should be LLM-generated (pairs with the entry above), fallback bucket logged. Design the trigger so it only fires when the player is not mid-combat/cutscene (reuse PlayerInteractionQueue pacing).
- [ ] **Kaelen contract-completion lines** -- `LLMInterface.gd` ~line 500 `fallback_completion_lines` (5 hardcoded strings, e.g. "Contract fulfilled. You know, Shiny, you're starting to grow on me. Like a profitable parasite.") are being shown as the DEFAULT on contract fulfillment, not just as an offline fallback. Spotted in-game 2026-07-02 (screenshot). Convert to a fresh LLM call (Kaelen voice, chapter/faction/story-context aware, "Shiny" allowed) each completion; keep the 5 lines as the LOGGED fallback bucket only.
- [ ] **Kaelen abandon lines** -- sibling array `fallback_abandon_lines` (`LLMInterface.gd` ~line 508) has the same problem; convert alongside the completion lines.
- [ ] **Kaelen gate/route reveal line** -- `UIManager._kaelen_gate_reveal()` (`scripts/UIManager.gd` ~line 8905) hardcodes the "I've got a contact who owes me — they mapped a route nobody else has charted..." line for every gate unlock. Spotted in-game 2026-07-02 (screenshot). Generate fresh (Kaelen voice, reflect which route/system was revealed + story context); keep the current string as logged fallback. NOTE: only tutorial lines should ever be canned.
- [ ] **Audit for sibling static-line arrays** -- grep StoryManager / UIManager / QuestManager for other fixed `messages := [...]` / rotating-index NPC lines (abandon, greeting filler, etc.) and queue each for the same LLM-with-logged-fallback treatment.

- [ ] **Station-aware line precaching (BIG — story-coupled, design first)** -- Concept: when the small model finishes loading (or on dock), look at where the player is docked and pre-generate the FIRST line for each NPC at that station so the first interaction is never a fallback. NOT just chatter — these lines are StoryManager-driven, which is the real lift:
  - **What to precache per station:** mechanic intro (already has `UIManager._cache_mechanic_intro()` + `_cached_mechanic_line_is_fallback` — the one clean seam today); lounge bartender/local/agent/Kaelen cards; the agent quest-availability line; optionally the first quest candidate (the 45s cold path).
  - **StoryManager dependencies (why it's not "random talk"):** agent availability = `get_agent_contract_availability()` (cooldown/no-work state); quest gen pulls `story_state_context` + `campaign_bible` + agent memory + system story pack; Kaelen lines are chapter/angle-aware; lounge lines should reflect faction tension/rep. Precache must snapshot this story state, not fire generic prompts.
  - **Cache key + invalidation:** key by `station_id` + a story-state fingerprint; invalidate when quest accepted, rep shifts, or chapter advances so a stale line is never served. Reuse the existing chatter_cache pop/refill pattern where it fits.
  - **Trigger:** on model-ready, refresh any station line currently cached as a FALLBACK (leverage `_cached_mechanic_line_is_fallback`-style flags) so the cold-start fallback gets swapped out before the player clicks in. Every precache miss still logs `record_fallback`.
  - _Partially addressed 2026-07-02:_ startup no longer races the warm-up. `LLMInterface` now emits `small_model_ready` only after the small model passes a real "hello" test generation (not just an empty weight-load), and the loading screen / gameplay entry + salvager backstory gate on it via `when_small_model_ready()`. Remaining precaching work (per-station line snapshots, refresh-fallback-on-ready) still stands, but the first-wave cold-start fallback burst should be gone. **Verify on next real boot:** mechanic/salvager/taunt/chatter should generate, not fall back, at start.
  - **Phase it:** (1) mechanic intro refresh-on-model-ready (smallest, seam exists), (2) lounge cards, (3) agent quest availability line, (4) full quest candidate precache. Write a short design doc before phase 2+.
  - _Do the cold-start warm-up playtest FIRST and in isolation — don't stack this on top or we can't tell which change moved the fallback rate._

---

## Localization / i18n groundwork
_Lay the foundations NOW so we don't retrofit at the very end and hate ourselves. This is not "translate the game" — it's "make the game translatable" so adding a language later is content work, not a rewrite. Do the cheap structural stuff early._

- [ ] **Decide the strategy + write it down** -- one short design doc: which layers are static (UI, menus, tooltips, item names, fixed system/quest-template text) vs dynamic (LLM-generated NPC dialogue). They need different solutions; deciding now prevents a mixed mess later.
- [ ] **Static strings: adopt `tr()` + translation keys from here on** -- stop hardcoding user-facing literals in code/scenes. Route them through Godot's translation system (CSV or PO + `TranslationServer`). Even shipping English-only, wiring `tr("KEY")` now means the day-1 cost of a second language is a spreadsheet, not a code sweep. Add a lint/grep habit: no bare user-facing string literals in UI code.
- [ ] **Externalize the strings we already have** -- audit UIManager / menus / DevPanel-facing player text and pull them into a translation table. Big-bang later = painful; incremental now = trivial.
- [ ] **LLM dialogue is the hard case — design it, don't solve it yet** -- most NPC lines are generated in English at runtime, so they can't be pre-translated. Options to weigh: (a) prompt the model in the target language using per-locale content files (the new `data/content/llm_dialogue_content.json` registry is the right seam for this — examples/tone per locale), (b) post-generation translation pass, (c) locale-gated static fallback lines for unsupported languages. Note tradeoffs; don't build yet. Ties to `project_fallbacks_are_failures` (a translation miss must log, not silently ship English).
- [ ] **Fonts / glyph coverage** -- pick UI fonts that cover intended target scripts (accented Latin at minimum; CJK/Cyrillic if in scope) BEFORE deep UI polish, so layouts are tested against wider/taller glyphs. Reserve layout slack for text expansion (German/Russian run long).
- [ ] **No text baked into textures/images** -- keep rendered text out of art assets (badges, HUD sprites, store signage) so it doesn't need re-arting per language. Flag any existing offenders.
- [ ] **Formatting: numbers / units / dates** -- centralize credit/ore/quantity formatting through a helper now so locale-specific separators and unit strings ("m³", "SC") have one place to change.
