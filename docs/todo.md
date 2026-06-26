# TODO
_Active task list. Update this file at the end of every session._

---

## Combat — Unified System (do in order, blocks everything below)

- [ ] **FactionRegistry.gd autoload** — single source of truth for all faction data: known profiles (aurelia/vanguard/zenith) + unknown faction progression list ordered by tier; `get_profile(key)`, `get_faction_for_danger_level(n)`; runtime override dict so tuning tool can hot-apply changes without touching the const.
- [ ] **Unknown faction progression list** — 4 factions per tier band, each band covers ~4 generated systems; same tier = same damage/HP budget but different combat role, weapon bias, shield vs hull split, and aggression pattern so each feels distinct to fight. Proposed bands:
  - **Band 1** (systems 2–5): Rift Collective (weapon-heavy burst), Hollow Syndicate (engine-heavy hit-and-run), Pale March (hull tank, braces constantly), Cinder Wake (repair-capable attrition)
  - **Band 2** (systems 6–9): Eclipse Legion (balanced), Obsidian Pact (shield-heavy), Ashen Drift (reposition every turn, chip damage), Iron Chorus (disable-focused)
  - **Band 3** (systems 10–13): Void Covenant (all-round high), Shatter Bloc (extreme weapon bias), Null Meridian (drone-specialist), Fracture Syndicate (squad-oriented)
  - **Band 4** (systems 14+): elite tier, reserved for late-game / story systems
- [ ] **Faction tuning tool** — Numpad 7 dev overlay; table showing all factions × tier fields with ↑/↓ per cell; changes hot-apply to future spawns; saves to `user://faction_tuning.json` which overrides const defaults during dev, ignored in release build.



- [ ] **Step 1 — CombatAction.gd: expand enum** — add BRACE, FLANK, SHIELD_ANGLE, DISABLE_ENGINES with AP costs + labels. Single source of truth for all action types.
- [ ] **Step 2 — NPCShip.gd: tier vars + faction profiles** — replace `damage_min/max`, `combat_ap` with `weapon_tier`, `engine_tier`, `powerplant_tier`, `shield_tier`; add `FACTION_PROFILES` const; add `apply_faction_profile(key)`; derive damage + AP from tiers using same formulas as PlayerShip; update `_action_*` helpers to `CombatAction.make()`.
- [ ] **Step 3 — CombatManager.gd: unified execution** — add `_exec_action(action, source, target)`; all handlers read stats from source node by property name; `_run_player_actions` and `_execute_npc_intent` both route through it.
- [ ] **Step 4 — Spawning: apply profiles** — `MainScene._spawn_npc()` and GameRoot debug spawns call `apply_faction_profile()`; boss = tier 3 profile.
- [ ] **Step 5 — Sensor sig table: collapse to one** — remove `SENSOR_SIGS_NAMED`; everything uses the int enum now.

## Combat — Unlocked by unified system

- [ ] **Pre-combat sensor scan** — at `combat_started`, typewriter-decode target's tier loadout in sensor panel. Tier 0 sensor = "THREAT LEVEL: HIGH / EXTREME", Tier 1 = individual stats ("Hull T2 / Weapons T3 / Engine T1"), Tier 2 = full assessment + warning ("Weapon systems exceed your fit by 2 tiers"). Needs sensor_tier on PlayerShip.
- [ ] **Sensor upgrade item** — add sensor_tier (0–2) to PlayerShip upgrades + store; gates how much pre-combat intel the player sees.
- [ ] **Difficulty scaling via profiles** — `GeneratedSystemNPCManager._spawn_ship()` already has `config.difficulty_tier` (1–3). After NPCShip gets `apply_faction_profile()`, add one call per spawn: `npc.apply_faction_profile(FactionRegistry.get_faction_for_danger_level(config.difficulty_tier, system_index))`. `system_index` = GlobalState visited-system counter so each new system picks a different entry within the band. `MainScene._spawn_npc()` should call known profiles (aurelia/vanguard/zenith). **File: `scripts/generation/GeneratedSystemNPCManager.gd`**
- [ ] **Boss as tier override** — story-triggered boss = `apply_faction_profile(faction, tier_override: 3)` instead of hardcoded stats; StoryManager trigger hook becomes trivial.
- [ ] **Mixed-profile squads** — squad fights can mix profiles (e.g. Tier 1 Interceptor + Tier 2 Gunner); makes 2-on-1 fights more varied than two identical ships.
- [ ] **Phase 6 — Enemy kit parity** — BRACE and REPOSITION now in enum; wire them into NPC planners as real actions with camera beats + SFX (same pipeline as player actions).
- [ ] **Damage type resistance** — each faction profile has `weapon_dmg_mult` and `drone_dmg_mult` (e.g. dense-plated faction: weapons 0.4×, drones 1.5×; shielded faction: weapons 1.0×, drones 0.2×). Applied in `_apply_hit()`. No tooltip or warning — player learns by watching damage numbers. Sensor scan shows hull composition ("DENSE PLATE ALLOY", "ENERGY SHIELDING TIER 2") so attentive players can adapt before the fight.
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

## Story / StoryManager

- [ ] **Boss fight trigger tool** — expose `GameRoot.trigger_boss_encounter(faction, stats_override)` so StoryManager can script a boss ambush as a story beat
- [ ] **Squad fight trigger tool** — expose `GameRoot.trigger_squad_encounter(faction, count)` for scripted 2-on-1 ambushes
- [ ] **Anomaly data core delivery** — anomaly drops a named data core; player delivers to NPC for payout via special cargo system
- [ ] **Salvage drone loot prompt** — (also listed under Combat) post-kill Kaelen hook

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

## Polish / Future

- [ ] **NAS asset migration** — move binary assets off git repo to NAS once hardware acquired; binaries-in-repo is accepted interim
- [ ] **Boss cinematic phases** — phase transition should have its own brief camera moment / sting beyond the current chatter line
- [ ] **Multi-boss / 3-on-1** — true squad fights beyond 2 enemies; needs a target picker on the wheel
