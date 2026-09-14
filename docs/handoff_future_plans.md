# Handoff: Future Plans

Collected during Segments 4–5 development (2026-06-18). All items below are unstarted.

---

## 1. Map Tooltips — Hover Info on System Nodes

**Priority:** High (quality-of-life for multi-system navigation)

**What:** Hovering over a system node in BranchMapUI shows a tooltip with:
- Number of stations
- Ore types available
- NPC factions present

**Why:** Late-game players need this info to plan routes — which system to visit for specific resources or faction missions.

**Where to implement:**
- `scripts/ui/BranchMapUI.gd` — add hover detection in `_gui_input()` (check `InputEventMouseMotion`, find nearest node within radius)
- Populate from `SystemDefinition` (station_ids, faction_ids) via `system_registry`
- Ore types would need to be added to `SystemConfig` first (new field, seeded selection from an ore catalog)

**Scope:** Small-medium. Hover detection is straightforward since `system_nodes` dict already has positions. Ore types require a new data model.

---

## 2. Route Planner — Click-to-Plan Multi-Jump Navigation

**Priority:** Medium (becomes important once 3+ systems are discoverable)

**What:** Player clicks a destination system on the map → the map highlights the path (colored route lines) from current location to target. When the planner is active and the player enters a system along the route, the relevant jump gates are highlighted in the overview panel. Auto-deactivates on arrival.

**Why:** Multi-jump navigation is disorienting without guidance. Players shouldn't have to re-open the map every system to figure out which gate to use next.

**Where to implement:**
- `scripts/ui/BranchMapUI.gd` — pathfinding across `system_nodes`/`route_data`, highlight planned edges in `_draw()` with a distinct color (e.g., bright green overlay)
- `scripts/GlobalState.gd` or `BranchMapUI` — store `planned_route: Array[String]` (ordered system IDs)
- `scripts/UIManager.gd` — in `refresh_overview()`, check if any gates in the current system match the next hop in the planned route, apply highlight styling
- Auto-clear: when `current_system_id` matches the route destination, clear the planned route

**Scope:** Medium. Pathfinding is simple (BFS over gate connections, all edges weight 1). The overview panel gate highlighting is the trickiest integration point.

---

## 3. Station NPC Faction Variety

**Priority:** Low (functional baseline exists, this is polish)

**What:** Generated stations should have faction-themed NPC rosters instead of pulling from the same global pool. A Zenith-controlled outpost should have Zenith-flavored NPCs with faction-specific gossip lines.

**Current state:** `GlobalState.assign_generated_outpost_npcs()` picks 2–3 NPCs from MINOR_NPCS via seeded shuffle. Works, but every generated station draws from the same pool regardless of faction.

**Where to implement:**
- `scripts/GlobalState.gd` — expand `assign_generated_outpost_npcs()` to accept faction weights from SystemConfig and bias NPC selection toward faction-aligned characters
- Requires new NPC entries in MINOR_NPCS (or a separate faction NPC catalog) with faction tags
- Gossip dialogue lines would need faction-specific variants

**Scope:** Large. Needs new content (NPC definitions + dialogue lines) not just code.

---

## 4. Difficulty Scaling Polish

**Priority:** Low (baseline tier system works, this is tuning)

**What:** Current scaling (tier 1→1.0x, tier 2→1.15x, tier 3→1.30x) affects HP and damage. Future tuning could add:
- Ship role distribution shifts (more Gunners/Interceptors in higher tiers)
- Patrol behavior changes (tighter formations, faster aggro range)
- Loot quality scaling (better drops in harder systems)

**Current state:** `SystemConfig.difficulty_multiplier` applied in `NPCShip._configure_role()`. `GeneratedSystemNPCManager` uses `config.npc_patrol_count = 5 + tier` for quantity scaling.

**Where to implement:**
- Role distribution: `GeneratedSystemNPCManager._spawn_initial_patrol()` — weight the role randomizer by tier
- Loot: wherever drop tables are resolved, multiply quality/quantity by difficulty_multiplier
- Behavior: `NPCShip.gd` AI state machine (if it exists) or patrol parameters

**Scope:** Small per-feature, but needs playtesting to avoid power creep.

---

## 5. Integrate Procedural Ship Generator

**Priority:** Medium (visual variety for NPC ships and player upgrades)

**What:** Copy the headless Blender spaceship generator from `C:\CodingProjects\CreateSpaceShips` into this project. The system generates `.glb` ship models procedurally using Blender's background mode — no GUI required. It supports two ship classes (`fighter`, `hauler`), configurable textures/emblems/normals, and seed-based deterministic output.

**Current external state:** The generator works standalone via either:
- **CLI:** Spawns Blender headless with `generate_single.py`, outputs `.glb` to `webapp/public/models/{seed}.glb`
- **REST API:** Node.js server on port 3000 with `/api/generate` and `/api/assets` endpoints

**Integration plan:**
1. Copy the generator into `tools/ship_generator/` (Blender scripts, textures, `generate_single.py`) — keep it self-contained, no Node.js server needed (use CLI mode only)
2. Create a GDScript wrapper (`scripts/generation/ShipGenerator.gd`) that spawns Blender headless via `OS.execute()` or a background thread, passing seed/class/texture params
3. Wire into `GeneratedSystemNPCManager` — when spawning NPC ships in generated systems, generate unique ship models based on system seed + ship index, cache the `.glb` in `assets/ships/generated/`
4. Add a ship catalog that maps faction → texture/emblem preferences so faction ships look distinct

**API reference:** See `C:\CodingProjects\CreateSpaceShips\spaceship_generator_api_guide.md` for full CLI args and param options. Key params: `--seed`, `--class` (fighter/hauler), `--texture`, `--emblem`, `--normal`, `--metallic` (0.0–1.0).

**Dependencies:** Blender 5.1 installed at `C:\Program Files\Blender Foundation\Blender 5.1\blender.exe`. Generator outputs `.glb` which Godot imports natively.

**Scope:** Large. The generator copy is straightforward, but the integration with NPC spawning, caching, and faction theming is multi-step.

---

## 6. Pre-Cache Public Board Quests

**Priority:** High (eliminates crash and loading hitch when opening the board)

**What:** Pre-generate and cache the 3 public board quest offers ahead of time instead of generating them on-demand when the player clicks "Public Contract Board." Cache once when the player enters a system (gate arrival or game load) and again immediately after a public board quest completes.

**Why:** The current on-demand generation crashes (`.id` bug in `MissionTextGenerator.fallback_offer`, now fixed) and even without the crash, generating offers at click time causes a visible hitch. Pre-caching makes the board open instantly.

**Where to implement:**
- `scripts/UIManager.gd` — trigger pre-cache on system entry and on public board quest completion (after `_on_agent_complete_pressed` for board quests)
- `scripts/domain/PublicBoardTextGenerator.gd` / `MissionTextGenerator.gd` — the generation pipeline already exists; wrap it in a background-callable path that stores results
- `scripts/UIManager.gd:_render_public_board_offers()` — read from cache instead of generating inline
- Cache invalidation: clear on system change, refresh after quest completion

**Scope:** Medium. The generation logic exists; this is plumbing to run it earlier and store the results.

---

## 7. Planet Shadow Occlusion on Nearby Objects

**Priority:** Low (visual polish)

**What:** Large planets (especially gas giants) don't cast shadows onto nearby asteroids or stations. Objects on the dark side of a planet are still fully lit by the directional light, breaking the visual realism.

**Why:** Godot's directional light shadow cascades are designed for camera-scale scenes. At game scale (planet radius 600, asteroid rings at 850+), the shadow map doesn't cover enough area to project a planet-sized shadow onto surrounding objects.

**Options:**
- Increase `directional_shadow_max_distance` — simple but reduces shadow quality globally
- Custom shader on asteroids/stations that checks whether the fragment is occluded by a nearby planet relative to the light direction — precise but more work
- Hybrid: a large invisible shadow-only mesh that approximates the planet's shadow cone

**Scope:** Small-medium. The shader approach is the cleanest long-term solution.

---

## Key Files Reference

| File | Role |
|------|------|
| `scripts/ui/BranchMapUI.gd` | Map UI — tooltips and route planner go here |
| `scripts/UIManager.gd` | HUD — overview panel gate highlighting for route planner |
| `scripts/GlobalState.gd` | Game state — planned route storage, outpost NPC assignment |
| `scripts/generation/SystemConfig.gd` | System params — ore types field needed for tooltips |
| `scripts/generation/GeneratedSystemNPCManager.gd` | NPC spawning — role distribution tuning |
| `scripts/NPCShip.gd` | Ship stats — difficulty multiplier already wired |

## Test Command
```
powershell -File C:\CodingProjects\SpaceGame\tools\run_baseline_checks.ps1
```
