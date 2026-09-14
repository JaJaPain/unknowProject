# Handoff: Segment 5 Completion + Branch Map Rework

## What's Done (This Session)

### Segment 5: Populate Generated Systems — COMPLETE
All 6 steps done, baseline suite passes (48/48):

1. **SystemConfig expanded** (`scripts/generation/SystemConfig.gd`) — added `difficulty_multiplier` (tier 1→1.0, tier 2→1.15, tier 3→1.30), `faction_weights` (1-2 major factions, seed-derived), `npc_patrol_count` (5+tier), `npc_minor_chance`, `npc_minor_max`

2. **NPCShip difficulty scaling** (`scripts/NPCShip.gd`) — added `@export var difficulty_multiplier: float = 1.0`, applied in `_configure_role()` after reinforcement block, before quest combat multiplier. Start system ships unaffected (default 1.0).

3. **GeneratedSystemNPCManager** (`scripts/generation/GeneratedSystemNPCManager.gd`) — NEW file. Spawns `npc_patrol_count` ships near planets/stations on `_ready()`, 30s respawn timer for destroyed ships + minor faction roamers. Uses runtime `load()` not preload.

4. **Wired into SystemFactory** (`scripts/generation/SystemFactory.gd`) — NPC manager node added to generated system root in `_build()`, after starfield.

5. **Station NPC variety** — `GlobalState.gd` got `generated_outpost_npcs` dict, `assign_generated_outpost_npcs()`, `resolve_outpost_id()`. UIManager updated at 3 sites (gossip button, TTS precache, pickup part check) to resolve generated station world_ids.

6. **Tests** (`tests/generation/run_system_factory_tests.gd`) — added `_test_config_faction_weights`, `_test_config_difficulty_multiplier`, `_test_config_npc_count`. Note: outpost NPC assignment test removed because GlobalState is an autoload unavailable in --script test mode.

### UI Improvements Done
- **System name in overview** — `UIManager.refresh_overview()` updates the overview title to show current system name (e.g., "Halcyon Reach  OVERVIEW")
- **SYSTEM MAP button** moved above overview panel (right side), hidden when only 1 system known
- **Branch map pause** — opens with `get_tree().paused = true` (not `GlobalState.paused` which shows pause menu), BranchMapUI has `process_mode = PROCESS_MODE_ALWAYS`
- **ESC handling** — UIManager._unhandled_input checks `branch_map.visible` first, calls `_close()` instead of toggling pause menu

### Type Inference Fix
- `SystemConfig.gd` line 87-93: changed `:=` inferred types to explicit `Array[String]`, `int`, `String`, `bool`, `float` annotations to avoid "Cannot infer type" parser errors (same pattern as the `min()`/`minf()` fix from Segment 4)

## What's NOT Done — Branch Map Rework

The branch map currently renders as a full-screen overlay behind the HUD. It needs to be a **draggable floating window** with **pan/scroll support**. Three steps:

### Step 1: Rewrite BranchMapUI as a draggable floating window
**File:** `scripts/ui/BranchMapUI.gd`

Current state: extends Control, uses `PRESET_FULL_RECT`, draws directly with `_draw()`, has title label + close button + detail panel as children.

Target: A fixed-size panel (~700x500), centered on screen, with:
- Title bar ("SYSTEM MAP") that supports click-drag to move the window
- Close button [X] in title bar corner
- Dark styled background (like dock panel)
- System node circles + route lines drawn in the content area below title bar
- Detail popup panel for click-to-inspect (already exists, needs repositioning within the window)

The `_draw()` method already handles all the rendering (circles, lines, labels, dashed lines, X marks, exclamation marks). The layout function `_layout_systems()` positions nodes in a circle — it just needs to use the panel's content area center instead of full-screen center.

### Step 2: Add pan/scroll support
- Click-drag on the map canvas (not title bar) pans the view
- Track a `_pan_offset: Vector2` that shifts all node positions
- Apply offset in `_draw()` and click detection
- Optional: mouse wheel zoom (future)

### Step 3: Wire into UIManager
- Update `_toggle_branch_map()` — the window approach may just need show/hide + pause
- ESC handling already works (UIManager checks `branch_map.visible` first)
- `map_btn` visibility logic already works (hidden when 1 system)

### Key existing code to preserve:
- `_rebuild_map()` — walks system registry, builds system_nodes dict + route_data array
- `_draw()` — renders circles, lines (solid/dashed), state colors, labels
- `_gui_input()` — click detection on nodes and routes
- `_show_system_detail()` / `_show_route_detail()` — info popups
- `STATE_COLORS` and `STATE_LABELS` constants
- `_close()` — hides + unpauses via `get_tree().paused = false`

## Files Modified This Session
- `scripts/generation/SystemConfig.gd` — faction weights, difficulty multiplier, NPC counts
- `scripts/NPCShip.gd` — difficulty_multiplier export + application
- `scripts/generation/GeneratedSystemNPCManager.gd` — NEW
- `scripts/generation/SystemFactory.gd` — NPC manager wiring
- `scripts/GlobalState.gd` — generated_outpost_npcs, assign/resolve helpers
- `scripts/UIManager.gd` — overview title, map button, ESC handling, outpost resolution
- `scripts/ui/BranchMapUI.gd` — close button, title, process_mode, _close() method
- `tests/generation/run_system_factory_tests.gd` — new config tests

## Test Command
```
powershell -File C:\CodingProjects\SpaceGame\tools\run_baseline_checks.ps1
```
Last run: 48/48 passed.
