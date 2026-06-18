# Handoff: Infinite Procedural Universe

## Goal

Replace the 3 hardcoded prototype systems (Crimson Nebula, Obsidian Reach, Aether's Edge) with a true infinite expansion loop. When a player starts a new campaign, only the hand-crafted Frontier System exists. Every new system is generated on-demand as the player discovers gates, and the process repeats endlessly.

## The Loop (Player Experience)

1. Player starts in Frontier System (hand-crafted, the only authored system)
2. After 30+ game-minutes, GateRumorEvent fires — picks an unknown gate, sets it to "rumored", and generates the destination system in the registry
3. Player scans the rumored gate → state becomes "hidden"
4. Kaelen offers to unlock hidden/rumored gates (costs credits) → state becomes "known"
5. Player jumps through the gate into the new system
6. Background thread pre-generates ship models for neighboring systems
7. The new system has 1-2 outbound gates (state: "unknown") leading to not-yet-created systems
8. Repeat from step 2

## What to Remove

### From `data/systems/system_registry.json`
Delete these 3 system entries and all their gates:
- `system.crimson` (Crimson Nebula) — lines ~86-126
- `system.obsidian` (Obsidian Reach) — lines ~128-168  
- `system.aether` (Aether's Edge) — lines ~169-198

### From `system.test` gates array
Delete the gate `gate.test.to_crimson` (the gate TO Crimson from test system)

### From `scenes/systems/system_test.tscn`
Delete the CrimsonGate node that was added at position (800, 0, -400)

### From `system.start` gates
The gate `gate.start.to_test` currently has `"initial_state": "known"`. For the infinite universe, this first outbound gate should start as `"unknown"` so the player discovers it through gameplay. Change it to:
```json
"initial_state": "unknown"
```

## What to Add

### Outbound gates on generated systems
When `GateDiscoveryManager._ensure_destination_generated()` creates a new system, it currently only creates the **return gate** (back to the system you came from). It needs to ALSO create 1-2 **outbound gates** leading to new, not-yet-existing systems. These outbound gates should have `initial_state: "unknown"`.

The number of outbound gates is already in `SystemConfig.outbound_gate_count` (1, or 2 with 40% chance).

---

## Ship Generation Pipeline

### Overview
Ships are generated via Blender 5.1 headless, producing `.glb` files that NPCShip loads at runtime.

### Key Files
- `tools/ship_generator/generate_single.py` — Blender python script. Args: `--seed`, `--class` (fighter/hauler), `--texture`, `--emblem`, `--normal`, `--metallic`, `--output`. Validates that the generated mesh has `Engine_*` and `Weapon_*` empties — exits with code 1 if missing (invalid ship).
- `tools/ship_generator/spaceship_generator.py` — The actual procedural mesh generator (imported by generate_single.py)
- `scripts/generation/ShipGenerator.gd` — GDScript wrapper. Calls `OS.execute()` on Blender. Up to 10 retry attempts with random seeds if validation fails. Caches to `res://assets/ships/generated/{seed}.glb`.
- `scripts/generation/ShipPreGenerator.gd` — Background thread pre-generator. Connected to `system_changed` signal. When player enters a system, queues ship generation jobs for all neighboring generated systems.

### Blender Path (hardcoded)
```
C:/Program Files/Blender Foundation/Blender 5.1/blender.exe
```

### Faction Textures & Emblems
```gdscript
FACTION_TEXTURES = {
    "zenith": "NavyBlueMetal.png",
    "aurelia": "ForestGreenMetal.png", 
    "vanguard": "RedMetal.png",
    "": "metal.png",
}
FACTION_EMBLEMS = {
    "zenith": "ZenithBadge.png",
    "aurelia": "AurelliaBadge.png",
    "vanguard": "VanguardBadge.png",
    "": "none",
}
```

### How NPCShip Loads Custom Models
In `scripts/NPCShip.gd` line 178:
- If `custom_model_path` is set and the file exists, loads it as a PackedScene
- Calls `_fit_major_hull()` to auto-scale the mesh to a role-based target size
- Applies `hull_instance.scale *= 1.5` (generated ships are smaller than hand-made ones)
- Calls `_setup_model_points()` which recursively finds `Engine_*`/`Weapon_*` empties for hardpoints and thrusters
- Falls back to `_ensure_model_points()` which creates fallback markers if none found

### Seed Convention
Ship seeds follow the pattern: `"ship_{system_seed}_{index}"` where index is 1-based per NPC in the system. Example: `ship_482917_3` is the 3rd NPC ship in a system with seed 482917.

### Pre-Generation Threading
`ShipPreGenerator` (wired in `GameRoot._ready()` line 89-94):
1. Listens to `system_changed` signal
2. Looks up all neighboring generated systems via gate definitions
3. For each neighbor, checks if `.glb` files exist for all `npc_patrol_count` ships
4. Queues missing ships as jobs `{seed, faction}`
5. Worker thread pops jobs from mutex-protected queue, calls `ShipGenerator.generate()`
6. Thread auto-restarts if new jobs arrive after completion

---

## Solar System Creation

### Key Files
- `scripts/generation/SystemConfig.gd` — Data class holding all parameters for a system
- `scripts/generation/SystemFactory.gd` — Builds the actual Node3D scene tree from a SystemConfig

### SystemConfig.from_seed(name, id, seed_val)
Deterministically generates all system parameters from a single seed:
- **Star type**: random from [yellow, blue, orange, red, white] — each has unique color, energy, ambient values
- **Planet count**: min=1, max=2-4
- **Station count**: 1-3 (first is always `full_service`, rest are `outpost`)
- **Difficulty tier**: 1-3, controls `difficulty_multiplier` (1.0 / 1.15 / 1.30)
- **NPC patrol count**: 5 + difficulty_tier (so 6-8 patrol ships)
- **Faction weights**: picks 1 primary faction from [zenith, aurelia, vanguard], 60% chance of a second faction with weighted split (55-75% primary)
- **Outbound gate count**: 1 (60%) or 2 (40%)
- **Starfield**: seed and tint derived from star color

### SystemFactory.generate(config) → Dictionary
Returns `{"ok": true, "root": Node3D, "station_ids": Array, "planet_count": int}`

Constants:
- `SYSTEM_RADIUS = 2500` — max distance for placed objects
- `MIN_PLANET_SPACING = 800`
- `MIN_STATION_CLEARANCE = 200`
- `MIN_GATE_CLEARANCE = 350`

Creates (in order):
1. **WorldEnvironment** — background color, ambient light from config
2. **DirectionalLight3D** — shadow-enabled
3. **Planets** (1-4) — 35% gas giant, else rocky. Random radius (150-550). Optional asteroid rings on rocky planets (40% chance, 16-36 asteroids per ring). Collision shapes. Named "Planet_0", "Planet_1", etc.
4. **Stations** (1-3) — 50% chance orbital (positioned near a planet) vs free-floating. First station is `full_service`, rest `outpost`. Uses one of 2 station models at different scales. Named with system prefix + random suffix from [Exchange, Outpost, Depot, Watch, Relay, Haven, Beacon, Anchorage, Port, Hub].
5. **Sun** — via `SystemAmbience.add_sun()`, random angle, star color/energy from config
6. **Starfield** — via `SystemAmbience.add_starfield()`, seed-based
7. **GeneratedSystemNPCManager** — spawns and manages NPC ships (see NPC section)

### Gate Placement (in SystemRegistry._build_generated_root)
Gates are NOT placed by SystemFactory. They're added by `SystemRegistry._build_generated_root()` (line 171-189) AFTER the factory builds the base system:
- For each gate in the system definition, generates position using `seed + gate_id.hash()`
- Places at random angle, distance 500-1200 from center
- Calls `SystemFactory.add_gate_to_system()` which instantiates `scenes/jump_gate.tscn`

### System Names
`CampaignSystemNames` (`scripts/generation/CampaignSystemNames.gd`):
- Pool of 15 curated names persisted to `user://campaign_systems.json`
- `next_name()` consumes one name, persists immediately
- Overflow fallback: `"Uncharted System %d"` when pool is exhausted
- Called by `GateDiscoveryManager._ensure_destination_generated()` when creating a new system

---

## NPC Ships (Patrol & Respawn)

### Key File: `scripts/generation/GeneratedSystemNPCManager.gd`
Added as a child node of every generated system's root. Initialized with the SystemConfig.

**On `_ready()`:**
1. Calls `_assign_outpost_npcs()` — for each outpost station, calls `GlobalState.assign_generated_outpost_npcs(world_id, seed)` which picks 2-3 NPCs from the MINOR_NPCS pool using seeded shuffle
2. Calls `_spawn_initial_patrol()` — spawns `config.npc_patrol_count` (6-8) ships near celestial/station anchors
3. Creates 30-second respawn timer

**Patrol spawning:**
- Each ship gets a faction from `config.faction_weights` (seeded RNG)
- Role randomly picked from: Gunner, Interceptor, Logistics, MiningHauler
- Ship model: checks for cached `.glb` at `res://assets/ships/generated/ship_{seed}_{index}.glb`
- If cached model exists → sets `npc.custom_model_path`
- If not → ship uses default faction model (faction1/zenith/aurelia mesh)

**Respawn:**
- When ships are destroyed, `GlobalState.destroyed_ships_pool` increments
- Every 30s, if pool > 0, spawns a replacement at 1100 units from a random anchor
- Also has a chance to spawn minor-faction roamers (up to `npc_minor_max`, with `npc_minor_chance`)

## Outpost NPC Assignment

### Key Function: `GlobalState.assign_generated_outpost_npcs(world_id, seed_value)`
- Seeded shuffle of all MINOR_NPCS that have an `"outpost"` key
- Picks 2-3 NPCs (40% chance of 3rd)
- Stores in `GlobalState.generated_outpost_npcs[world_id]`
- These NPCs appear at docking screens, give gossip, and can issue quests

### MINOR_NPCS Pool (in GlobalState.gd, line 147+)
Each entry has: image, position, vibe, outpost assignment, voice_id, voice_speed, flavor_color, flavor_lines, pickup_handoff_fallback_lines. Named characters like Cassen Vane, Mariska Vonn, Korvin Shaw, etc.

Portraits come from `GameContentRegistry` atlas sheets — each NPC has a `portrait_id` that maps to a cell in a spritesheet.

## Voice System (TTS)

### Architecture
1. `SpeechService` → `KokoroSpeechProvider` → HTTP to `tts_server.py` → Kokoro KPipeline
2. Voice profiles defined in `data/content/voices.json` — each has an ID like `voice.cassen_vane.v1`
3. Provider mappings in `data/content/voice_provider_kokoro.json` — maps voice profile IDs to Kokoro voice strings

### Kokoro Voice Blend Syntax
```
"am_onyx[0.6]+am_fenrir[0.4]"
```
Format: `base_voice[weight]+base_voice[weight]`. The `tts_server.py:resolve_voice()` function parses this, loads each base voice tensor, and does weighted blending. Results are cached.

### CRITICAL RULE
**Never use `af_bella` in any NPC voice blend.** It is reserved exclusively for Kaelen. This is a hard rule from the user (see memory: `feedback_voice_blends.md`).

### Available Kokoro Base Voices
Male: am_adam, am_michael, am_onyx, am_fenrir, am_liam
Female: af_bella (KAELEN ONLY), af_sarah, af_nicole, af_kore, af_nova, af_aoede

### For New Generated NPCs
Currently, generated systems reuse the existing MINOR_NPCS pool — they don't create brand-new NPC characters. The voice/portrait system doesn't need changes for the infinite universe MVP. New unique NPCs with unique voices is a future enhancement.

---

## Gate Discovery Flow

### State Machine
```
unknown → rumored → hidden → known
           (event)   (scan)   (Kaelen)
```

### Key Files
- `scripts/navigation/GateDiscoveryManager.gd` — Central manager, handles state transitions
- `scripts/events/types/GateRumorEvent.gd` — Timed event that discovers unknown gates
- `scripts/persistence/CampaignCheckpointStore.gd` — Persists gate states in `map_knowledge`
- `scripts/persistence/CampaignSlotRegistry.gd` — Seeds initial gate states from registry definitions

### GateRumorEvent (line: `scripts/events/types/GateRumorEvent.gd`)
- Registered with EventScheduler at 120 game-minute intervals
- `is_eligible()`: requires 30+ campaign minutes AND at least one unknown gate exists anywhere in the registry
- `execute()`: picks a random unknown gate, calls `GateDiscovery.apply_rumor(gate_id, narrative)`
- Shows a chatter message like "Docking crew mentioned a faint hypergate signature..."

### GateDiscoveryManager._ensure_destination_generated() (line 147)
Called when a gate becomes "rumored". This is where new systems are born:
1. Looks up the gate definition to find `destination_system_id`
2. If that system already exists in the registry → returns early
3. If not: calls `CampaignSystemNames.next_name()` for a name
4. Creates `SystemConfig.from_seed(name, id, id.hash())`
5. Creates a return gate definition (initial_state: "known" — so player can get back)
6. Registers the system via `registry.register_generated_system()`
7. Stores the SystemConfig via `registry.set_generated_config()`

**CURRENT GAP**: This function only creates the return gate. It does NOT create outbound gates for the new system. This is the main thing that needs to be added for infinite expansion.

### Kaelen Gate Unlock (line 76-96)
- `kaelen_reveal(gate_id, cost)` — pays credits, sets gate to "known"
- `is_kaelen_gate_eligible()` — requires: 120+ game minutes, 3+ quests completed, 60-minute cooldown since last offer, at least one revealable gate exists
- Cost varies by state: rumored=75, hidden=60, blocked=50, damaged=40
- `get_revealable_gates()` returns gates in states: rumored, hidden, blocked, damaged

### Gate State Persistence
- `CampaignSlotRegistry` seeds gates from registry definitions — respects `initial_state` field
- `CampaignCheckpointStore` stores runtime state in `map_knowledge.known_gate_ids` / `hidden_gate_ids` / `unknown_gate_ids`
- `_initial_known_gates` dict handles migration for gates that should be known but got stuck as hidden in old saves

### JumpGate Visibility
- `JumpGate._ready()` calls `_apply_knowledge_state()` which queries `GameRoot.get_gate_knowledge_state()`
- Known gates: visible + interactive
- Hidden gates: visible but not jumpable (need Kaelen)
- Rumored gates: faintly visible, scannable
- Unknown gates: invisible
- `GameRoot._refresh_gate_states()` re-applies states after save loads (fixes timing issue where gates init before checkpoint loads)

---

*Next section: Implementation Checklist*

## Implementation Checklist

### Phase 1: Clean Up Prototypes
1. [x] Remove Crimson Nebula, Obsidian Reach, Aether's Edge from `data/systems/system_registry.json`
2. [x] Remove `gate.test.to_crimson` from the test system's gates array
3. [x] Remove the CrimsonGate node from `scenes/systems/system_test.tscn`
4. [x] Change `gate.start.to_test` initial_state from `"known"` to `"unknown"`

### Phase 2: Add Outbound Gate Generation
Modify `GateDiscoveryManager._ensure_destination_generated()` to:
1. [x] After creating the return gate, also create `config.outbound_gate_count` (1-2) outbound gates
2. [x] Each outbound gate should:
   - Have a unique ID like `gate.{new_system_id}.out_{index}`
   - Point to a destination system ID that doesn't exist yet (e.g., `system.gen_{hash}`)
   - Have a matching destination gate ID (e.g., `gate.gen_{hash}.return`)
   - Have `initial_state: "unknown"`
3. [x] Use the system's seed + index to generate deterministic gate IDs

Clarified implementation:
- [x] `system.test` remains a test scene/fixture, but is no longer part of the default campaign registry.
- [x] The Frontier gate points at a deterministic first generated route (`system.gen.frontier.first`) and starts locked/unknown.
- [x] Entering or restoring a system prepares generated destinations for that system's outbound gates before the scene is used.
- [x] Live gate nodes refresh their target metadata from the registry after the generated destination is registered, so a fallback/locked gate can safely swap to the prepared route before Kaelen opens it.
- [x] Gate rumor events only choose unknown gates in the current system, preventing future-system gates from being revealed early.

### Phase 3: Verify the Full Loop
Test the complete cycle:
1. [x] Start new campaign - only Frontier System exists
2. [x] Wait 30+ minutes - gate rumor fires for `gate.start.to_test`
3. [x] Scan the rumored gate - becomes hidden
4. [x] Complete 3+ quests, wait 120+ minutes - Kaelen offers gate unlock
5. [x] Pay Kaelen - gate becomes known
6. [x] Jump to new system - system generates with planets, stations, NPCs, sun, starfield
7. [x] Background thread generates ship models
8. [x] New system has 1-2 unknown outbound gates
9. [x] Wait in new system - rumor fires for one of the outbound gates
10. [x] Repeat

Verification notes:
- [x] `--jump-smoke-test --no-save-load --baseline-offline` now creates a fresh campaign, verifies unknown -> rumored -> hidden -> known, jumps to `system.gen.frontier.first`, verifies generated content, verifies prepared outbound destinations, rumors the next outbound gate, and returns through the known return gate.
- [x] Branch map refreshes when gate states or current system change, and smoke verification checks that the first generated route and next rumored outbound route appear in map data.

### Phase 4: Edge Cases to Handle
- [x] **Name pool exhaustion**: After 15 systems, names fall back to advancing "Uncharted System N" values and persist the fallback counter.
- [x] **Ship generation failure**: If Blender fails after 10 attempts, ship uses default faction model (already handled)
- [x] **Gate ID collisions**: Use system_id + hash to ensure unique gate IDs
- [x] **Save/load with generated systems**: Generated systems are exported into save/checkpoint runtime state and imported before save validation, so a fresh restart can load a generated current system. SystemConfigs are recreated from seed via `_init_generated_system_configs()` after import.
- [x] **Map UI**: `BranchMapUI` needs to handle dynamically added systems - verified it reads from the live registry and refreshes on gate/system changes

Verification notes:
- [x] System factory tests cover advancing fallback system names and generated registry export/import.
- [x] Save migration tests cover loading a generated current system into a fresh registry before validation.
- [x] Campaign checkpoint, campaign slot, registry, and jump smoke tests pass with the generated save/checkpoint state.

## Existing Wiring (Already Done)

These things are already connected and working:
- `ShipPreGenerator` connected to `system_changed` signal in `GameRoot._ready()`
- `EventScheduler` registered with `GateRumorEvent` at 120-minute intervals
- `SystemFactory.generate()` creates complete playable systems from a seed
- `SystemRegistry._build_generated_root()` places gates and instantiates generated systems
- `GeneratedSystemNPCManager` spawns patrol ships with custom models
- `CampaignCheckpointStore` handles gate state persistence and migration
- `_init_generated_system_configs()` recreates SystemConfigs for pre-registered generated systems on startup
- TTS voice blending works for all NPCs via `tts_server.py:resolve_voice()`

## File Reference Quick Index

| Purpose | File |
|---------|------|
| System parameters | `scripts/generation/SystemConfig.gd` |
| Scene builder | `scripts/generation/SystemFactory.gd` |
| NPC spawner | `scripts/generation/GeneratedSystemNPCManager.gd` |
| Ship mesh gen | `scripts/generation/ShipGenerator.gd` |
| Background threading | `scripts/generation/ShipPreGenerator.gd` |
| Gate state machine | `scripts/navigation/GateDiscoveryManager.gd` |
| Gate rumor events | `scripts/events/types/GateRumorEvent.gd` |
| System name pool | `scripts/generation/CampaignSystemNames.gd` |
| System registry | `scripts/registry/SystemRegistry.gd` |
| Registry data | `data/systems/system_registry.json` |
| Gate persistence | `scripts/persistence/CampaignCheckpointStore.gd` |
| Initial gate seeding | `scripts/persistence/CampaignSlotRegistry.gd` |
| NPC assignment | `scripts/GlobalState.gd` (line 363) |
| Voice profiles | `data/content/voices.json` |
| Kokoro mappings | `data/content/voice_provider_kokoro.json` |
| TTS server | `scripts/tts_server.py` |
| Ship model loading | `scripts/NPCShip.gd` (line 178) |
| Blender script | `tools/ship_generator/generate_single.py` |
| Game root wiring | `scripts/GameRoot.gd` |
