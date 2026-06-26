# TODO
_Active task list. Update this file at the end of every session._

---

## Combat — Unified System (do in order, blocks everything below)

- [x] **FactionRegistry.gd autoload** — single source of truth for all faction data: known profiles (aurelia/vanguard/zenith) + unknown faction progression list ordered by tier; `get_profile(key)`, `get_faction_for_danger_level(n)`; runtime override dict so tuning tool can hot-apply changes without touching the const.
- [x] **Unknown faction progression list** — 4 factions per tier band, each band covers ~4 generated systems; same tier = same damage/HP budget but different combat role, weapon bias, shield vs hull split, and aggression pattern so each feels distinct to fight. Proposed bands:
  - **Band 1** (systems 2–5): Rift Collective (weapon-heavy burst), Hollow Syndicate (engine-heavy hit-and-run), Pale March (hull tank, braces constantly), Cinder Wake (repair-capable attrition)
  - **Band 2** (systems 6–9): Eclipse Legion (balanced), Obsidian Pact (shield-heavy), Ashen Drift (reposition every turn, chip damage), Iron Chorus (disable-focused)
  - **Band 3** (systems 10–13): Void Covenant (all-round high), Shatter Bloc (extreme weapon bias), Null Meridian (drone-specialist), Fracture Syndicate (squad-oriented)
  - **Band 4** (systems 14+): elite tier, reserved for late-game / story systems
- [x] **Faction tuning tool** — Numpad 7 opens unified DevPanel; faction tuning tab with all factions × tier fields, ↑/↓ per cell, hot-apply + save to `user://faction_tuning.json`. DevPanel also has Spawn Boss, Spawn Squad, Restock actions. Extensible via `add_action_button()` / `add_tab()`.



- [x] **Step 1 — CombatAction.gd: expand enum** — BRACE, FLANK, SHIELD_ANGLE, DISABLE_ENGINES added with AP costs + labels.
- [x] **Step 2 — NPCShip.gd: tier vars + faction profiles** — tier vars added; `apply_faction_profile()` derives all combat stats; `_action_*` helpers use `CombatAction.make()`.
- [x] **Step 3 — CombatManager.gd: unified execution** — `_execute_npc_action` on int enum; damage in `params`; `_apply_hit` applies faction resistances.
- [x] **Step 4 — Spawning: apply profiles** — `MainScene._spawn_npc()` and `GeneratedSystemNPCManager` all three spawn paths wired.
- [x] **Step 5 — Sensor sig table: collapse to one** — `SENSOR_SIGS_NAMED` deleted; single int-keyed table in CombatPanel.

## Combat — Unlocked by unified system

- [ ] **Pre-combat sensor scan** — at `combat_started`, typewriter-decode target's tier loadout in sensor panel. Tier 0 sensor = "THREAT LEVEL: HIGH / EXTREME", Tier 1 = individual stats ("Hull T2 / Weapons T3 / Engine T1"), Tier 2 = full assessment + warning ("Weapon systems exceed your fit by 2 tiers"). Needs sensor_tier on PlayerShip.
- [ ] **Sensor upgrade item** — add sensor_tier (0–2) to PlayerShip upgrades + store; gates how much pre-combat intel the player sees.
- [x] **Difficulty scaling via profiles** — done; all spawn paths call `apply_faction_profile()` with tier-matched unknown faction or named known faction.
- [ ] **Boss as tier override** — story-triggered boss = `apply_faction_profile(faction, tier_override: 3)` instead of hardcoded stats; StoryManager trigger hook becomes trivial.
- [ ] **Mixed-profile squads** — squad fights can mix profiles (e.g. Tier 1 Interceptor + Tier 2 Gunner); makes 2-on-1 fights more varied than two identical ships.
- [ ] **Phase 6 — Enemy kit parity** — BRACE and REPOSITION now in enum; wire them into NPC planners as real actions with camera beats + SFX (same pipeline as player actions).
- [x] **Damage type resistance** — `weapon_dmg_mult` / `drone_dmg_mult` per profile, applied in `_apply_hit()`. Hull composition in sensor scan.
- [ ] **Damage number visual feedback for resistance** — resisted hits show small dim numbers; effective hits show large bright numbers. Player reads the difference in the moment and learns without being told explicitly.
- [ ] **Phase 7 — Boss (mega)** — DONE (in-game) but needs StoryManager trigger hook so scripted story beats can spawn the boss fight (see Story section below)
- [ ] **Phase 8 — Squads** — DONE (in-game) but needs StoryManager trigger hook (see Story section below)
- [ ] **Shield Reroute sub-picker** — currently defaults to Front face; needs the face-select sub-wheel
- [ ] **Boost direction toggle** — currently defaults to "closer to enemy"; needs toggle for Evade/Close
- [ ] **Attack drone visual** — drone is hard to see during combat; needs a more visible model or glow
- [ ] **Salvage drone loot prompt** — rare Kaelen hook after a kill; prompt to deploy salvage drone for bonus loot
- [ ] **Enemy low-health escalation arc** — enemy dialogue/behavior should escalate when below 30% HP
- [ ] **Impact decals on player ship** — hull hit marks that persist during a fight
- [ ] **Richer combat taunt flavor** — taunt bucket system: reason-aware taunts (flanked, shielded, drone hit, etc.)

---

## Story / Narrative System
_Full design in `docs/design_narrative_system.md`. Build in order — each phase depends on the one before._

- [ ] **Phase A — Campaign Spine Generator** — `CampaignBibleGenerator.gd` calls gemma4 at new-campaign start with world lore + faction registry + system map. Generates `user://campaign_bible.json`: inciting event, faction tensions, 5-6 chapter cause/effect chain, secret at the center, Kaelen's angle, ending conditions. StoryManager reads it and seeds chapter 1.
- [ ] **Phase B — Story State Document** — StoryManager gets a live `story_state` dict (chapter, active_tensions, player_knows, hidden_truths, current_foreshadow, kaelen_mood). `get_story_context_block()` returns a short string injected into every LLM prompt. `advance_chapter()` fires on chapter-link mission completion. Persisted to `user://story_state.json`.
- [ ] **Phase C — Mission Causality** — Mission generator receives a `because` field from StoryManager's active tensions. Brief tone, NPC urgency, and reward level all reflect it. `pending_hooks` list tracks open story threads; hook missions close them and trigger connected-agent follow-ups. Story context block prepended to all `request_quest_candidate()` calls.
- [ ] **Phase D — Kaelen Integration** — Kaelen lines get `kaelen_mood` from story state but never her angle (StoryManager holds that). New line types: `kaelen_chapter_comment` (once per chapter advance) and `kaelen_hint` (on hook mission completion). StoryManager fires these on story events, not timers.
- [ ] **Phase E — Ambient NPC Dialogue** — `AmbientChatGenerator.gd` fires every 3-5 min during open play. Picks topic bucket (story-adjacent / mundane / overheard-intel) from StoryManager, writes 2-4 lines between two NPC archetypes via small model, delivers via `GlobalState.emit_chatter()`. `used_topics` list prevents repeats within a chapter. Target ratio: 50% mundane, 30% story-adjacent, 20% overheard intel.
- [ ] **Campaign closure — Story PDF + permanent lock** — When a player chooses to end a campaign, gemma4 compiles the full story into a readable narrative document: the inciting event, the chapter arc as the player experienced it, key missions and what they meant to the larger story, Kaelen's thread, and the ending. Delivered as a PDF saved to the user's machine. The campaign save is then permanently locked — marked as `ended`, all missions and travel disabled, the slot shows "ENDED" in the save screen. The story is theirs to keep. The world is closed. This is the equivalent of finishing a book — you don't go back and replay chapter 3. New campaign for a new story. PDF generation via GDScript writing HTML and converting, or via a simple text layout written to a styled file. Include the campaign name, playtime, systems visited, missions completed, and the narrative prose gemma4 writes from the story state history.
- [ ] **Phase F — Rumors** — Station visits trigger a rumor check against `pending_hooks` (40% chance, not every visit). Single line from unnamed NPC via system chat. StoryManager marks hook as "hinted" after firing. Rumors plant questions, never answer them.
- [ ] **Boss fight trigger tool** — expose `GameRoot.trigger_boss_encounter(faction, stats_override)` so StoryManager can script a boss ambush as a story beat
- [ ] **Squad fight trigger tool** — expose `GameRoot.trigger_squad_encounter(faction, count)` for scripted 2-on-1 ambushes
- [ ] **Anomaly data core delivery** — anomaly drops a named data core; player delivers to NPC for payout via special cargo system
- [ ] **Salvage drone loot prompt** — (also listed under Combat) post-kill Kaelen hook

---

## Navigation / Autopilot

- [ ] **Fix autopilot avoidance regression** *(see bugs.md for full root-cause analysis)*
  - Wire `_get_autopilot_avoidance()` back into the autopilot movement block (`PlayerShip.gd:740–754`). It exists and works but is not being called.
  - After `_route_steer_target()` returns a `steer_target`, pass it through `_get_autopilot_avoidance(steer_target, active_target)`. When `is_avoiding` is true, use the avoidance waypoint as the actual steer target.
  - This gives two complementary layers: A* planner handles the macro route, real-time avoidance handles surprises mid-flight.
- [ ] **Forward whisker (nose sensor) for imminent collision**
  - Add a `RayCast3D` pointing forward (`-Z`) on the ship. No new scene node needed — configure it in `_ready()`.
  - In `_physics_process` during autopilot: if the raycast hits something within ~50u that is not the nav target, call `_clear_planned_route()` immediately to force a fresh A* replan without waiting for the 2.5s stall timer.
  - Godot equivalent of the Unity "empty object on ship nose" pattern. The raycast IS the whisker.
- [ ] **Fishtailing in tight spaces** — ship wiggles its butt side to side when trying to squeeze into a tight area (e.g. navigating close to a station or between asteroids). The steering overshoots, corrects, overshoots the other way, and oscillates instead of committing to a clean line. Needs dampening on the angular correction when the ship is close to an obstacle and the heading delta is small — reduce turn aggression proportionally to proximity so it slides in smoothly instead of wagging its tail. **Fix is in `steer_towards()` in `PlayerShip.gd`** — when proximity to an obstacle is detected AND the heading correction angle is small, scale down the turn rate so the ship commits to the line rather than overcorrecting back and forth.
- [ ] **Route validity re-check while following waypoints**
  - After each waypoint is passed (`planned_route_index` advances), call `NavigationRoutePlanner.route_is_clear()` on the remaining waypoints against current hazards. If it returns false, replan immediately.
  - Catches cases where an obstacle moved into the planned path since the last full replan.

---

## World / Exploration

- [ ] **Map hover tooltips** — hovering a map node shows stations, ore types, factions present
- [ ] **Route planner** — click-to-plan route; gates highlight in overview; auto-clears on arrival
- [ ] **Gate portal particles** — particle effects off the gate portal (portal shader is locked/approved, don't touch it)
- [ ] **Generated systems: NPC ships** — procedural systems feel empty; need ambient NPC traffic
- [ ] **Generated systems: station variety** — all proc-gen stations look the same; need visual variants
- [ ] **Generated systems: difficulty scaling** — enemy stats should scale with system danger level
- [ ] **Discovery visual treatments** — named/story systems should feel different on arrival: skybox tint, arrival text banner, environmental storytelling (debris, explosion haze). See `docs/design_parking_lot.md §2`

---

## UI / UX

- [ ] **Quest tracker panel blue box on second quest** — `reset_size()` fires on first show only; second quest reloading the panel brings back the oversized box (see bugs.md)
- [ ] **Station lounge social layer** — relationship heat bar, contact moods, "last seen" timestamp, rumor badge. See `docs/design_parking_lot.md §1`
- [ ] **Store presentation polish** — item cards, purchase confirm dialog, inventory integration, mission highlight. See `docs/design_parking_lot.md §3`

---

## Shipping / Deployment (Ollama)

The game depends on Ollama for all LLM content (taunts, quests, Kaelen dialogue).
The watchdog in `LLMInterface.gd` already auto-starts Ollama and pulls missing models.
Deployment checklist for a shipped build:

- [ ] **Bundle ollama.exe** — copy the Ollama binary into `ollama/ollama.exe` next to the game executable. The watchdog checks this path first before LOCALAPPDATA or PATH.
- [ ] **Choose a shippable model** — `qwen2.5:3b-instruct-q4_K_M` (current small model) is ~2GB. Verify its license permits commercial distribution. Mistral 7B (Apache 2.0) is a clean alternative. `gemma4:12b` (large model) is too big to bundle — decide if large-model features ship or are skipped.
- [ ] **Bundle the model file** — Ollama stores models in `%USERPROFILE%\.ollama\models\`. For a fully offline install, pre-populate this folder in the installer OR ship a GGUF file and set `OLLAMA_MODELS` env var to a path inside the game bundle.
- [ ] **First-run model pull fallback** — if model is not bundled, the watchdog auto-pulls it on first launch. This requires internet and takes 2–5 min. Show a loading screen / progress message to the player during this window (currently silent in-game).
- [ ] **First-run UX** — add a splash/loading state that shows "Preparing AI systems…" while the watchdog polls and the model pulls. Do not drop the player into the main menu until `_ollama_ready` is true and models are confirmed.
- [ ] **Installer script** — write a setup script (NSIS / Inno Setup) that: copies `ollama.exe`, sets `OLLAMA_MODELS` to a bundled path, and optionally pre-warms the model on install so first launch is instant.
- [ ] **macOS / Linux path** — watchdog already checks `/usr/local/bin/ollama` and `ollama` on PATH. Test on those platforms. Mac may need a signed/notarized ollama binary.
- [ ] **Offline mode** — if Ollama never comes up (no internet, corporate firewall, etc.), the game should surface a clear one-time message: "AI features unavailable — game will use built-in dialogue." Currently just logs to console.

---

## Polish / Future

- [ ] **NAS asset migration** — move binary assets off git repo to NAS once hardware acquired; binaries-in-repo is accepted interim
- [ ] **Boss cinematic phases** — phase transition should have its own brief camera moment / sting beyond the current chatter line
- [ ] **Multi-boss / 3-on-1** — true squad fights beyond 2 enemies; needs a target picker on the wheel
