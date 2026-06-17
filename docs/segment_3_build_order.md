# Segment 3 Build Order: Economy, Stores, Random Events, And Interceptors

Date: 2026-06-17

Status: Checkpoint 4 complete, baseline 45/45

Branch: `segment-3/economy-stores-events`

## Design Decisions

- Stores sell consumables (repair kits, shield cells, scanner probes) and
  ammunition types. No crafting system — buy and use.
- Stock is deterministic from system seed + campaign time. No reload farming.
- Prices vary by station reputation tier (existing buyback tiers extended).
- Random events are seeded from campaign time + system ID + event type.
  Reloading a checkpoint replays the same events.
- Interceptors spawn on gate arrival, not departure. The player sees them
  after committing to a jump — no free intel by jumping and jumping back.
- Interceptor eligibility is driven by mission risk tags, not LLM decisions.
- Event pacing uses a cooldown + budget system: at most N events per M
  minutes of campaign time, with per-type cooldowns.

## Current Code Reality

GlobalState tracks credits, ore cargo, special cargo, and 6 upgrade trees.
Ore selling uses reputation-based pricing (2.0–3.0 SC/m³). No shop UI
exists beyond "Sell Ore" and "Ship Upgrades" in the dock menu.

CampaignClock advances on gate jumps (+45 min), dock (+10 min), and undock
(+5 min). QuestManager and UIManager already listen to `time_changed`.

NPC spawning uses `spawn_mission_targets()` and `spawn_reinforcement()` in
GlobalState. NPCs have faction, role (Gunner/Interceptor/Logistics/
MiningHauler), persistent IDs, and combat scaling. The `active_system_
entities` array tracks all live entities per system.

Save/load captures player state, cargo, credits, upgrades, reputations,
and persistent entities. System entity snapshots restore quest targets and
wreckage on revisit.

## Checkpoint 1: Station Store Data Model

### Goal

Define what stations sell, how stock works, and how prices are calculated —
all testable without UI.

### Deliverables

- `scripts/economy/StoreDefinition.gd`:
  - `store_id: String` (e.g. `"store.haven.general"`)
  - `station_id: String`
  - `item_catalog: Array[StoreItemEntry]` — what this store CAN sell.
  - `stock: Dictionary` — `item_id -> { quantity: int, restock_at: int }`.
  - `price_tier: String` — derived from faction reputation.
  - `get_price(item_id, reputation) -> int`
  - `get_stock(item_id) -> int`
  - `purchase(item_id, quantity) -> bool` — deducts stock, returns false
    if insufficient.
  - `restock_check(current_time_minutes: int)` — refills items whose
    `restock_at` has passed.
  - `to_dict() / from_dict()` for save/load.
- `scripts/economy/StoreItemDefinition.gd`:
  - `item_id`, `display_name`, `description`, `category` (consumable,
    ammo, upgrade_material).
  - `base_price: int`, `stack_max: int`.
  - `restock_interval_minutes: int` — how often the store restocks.
  - `restock_quantity: int` — how many units per restock cycle.
  - `max_stock: int` — cap per store.
- `scripts/economy/StoreRegistry.gd`:
  - Static registry of all store definitions.
  - `get_store(store_id) -> StoreDefinition`
  - `get_stores_for_station(station_id) -> Array[StoreDefinition]`
- `data/content/store_items.json` — item catalog (6–10 starter items).
- `data/content/store_layouts.json` — which stations carry which items
  and at what stock levels.

### Verification

- Focused tests: create store, buy item, verify stock decrements, verify
  price tiers, verify restock at correct time.
- Insufficient credits or stock returns false.
- Round-trip save/load preserves stock state.

## Checkpoint 2: Player Inventory And Consumable Use

### Goal

Give the player an inventory for purchased items and wire consumable
effects so buying things has gameplay value.

### Deliverables

- `scripts/economy/PlayerInventory.gd`:
  - `items: Dictionary` — `item_id -> quantity`.
  - `add(item_id, quantity) -> bool`
  - `remove(item_id, quantity) -> bool`
  - `has(item_id, min_quantity) -> bool`
  - `to_dict() / from_dict()`
- GlobalState gains `inventory: PlayerInventory`.
- Consumable effects (activated via hotkey or UI):
  - **Repair Kit**: restores 25 HP. Usable in flight.
  - **Shield Cell**: restores 50% shield. Usable in flight.
  - **Scanner Probe**: reveals all entities in current system for 60s.
- Save/load includes inventory state in checkpoint bundle.

### Verification

- Focused tests: add/remove items, boundary checks, save/load roundtrip.
- Consumable use deducts from inventory and applies effect.
- Cannot use item player doesn't have.

## Checkpoint 3: Store UI And Purchase Flow

### Goal

Wire the store into the dock UI so the player can browse and buy.

### Deliverables

- UIManager dock menu gains a "Station Store" button (full-service
  stations only; outposts get a smaller "Supply Cache" with fewer items).
- Store panel shows:
  - Item list with name, price, stock count.
  - Price color: green (affordable), red (too expensive), grey (out of
    stock).
  - Buy button with quantity selector (1 / 5 / max).
  - Player credits shown at top.
- Purchase flow: click Buy → credits deducted → item added to inventory →
  stock decremented → UI refreshes.
- Inventory panel accessible from dock or pause menu showing owned items
  with Use button for consumables.

### Verification

- Gameplay smoke: dock, open store, buy repair kit, verify credits
  deducted and item in inventory, use repair kit, verify HP restored.
- Store shows correct prices for current reputation tier.
- Out-of-stock items show greyed-out state.
- Full baseline passes.

## Checkpoint 4: Time-Based Stock Refresh

### Goal

Make store stock change over campaign time so the economy feels alive and
waiting has a bounded cost.

### Deliverables

- `StoreDefinition.restock_check(current_time)` — called when
  `CampaignClock.time_changed` fires.
- Each item has an independent restock timer. When `current_time >=
  restock_at`, quantity increases by `restock_quantity` up to `max_stock`,
  and `restock_at` advances by `restock_interval_minutes`.
- Depletion: buying the last unit of an item sets a longer restock delay
  (2x normal interval) to prevent rapid buy-wait-buy loops.
- StoreRegistry listens to `CampaignClock.time_changed` and ticks all
  stores.
- Checkpoint save captures each item's `restock_at` timestamp so loading
  a save replays identical stock state.
- Stock state is per-store, not global — Haven station and Iron Reach
  outpost restock independently.

### Verification

- Focused test: buy all stock, advance time past restock interval, verify
  stock recovers. Advance less time, verify stock stays depleted.
- Depletion penalty test: deplete item, verify 2x restock delay.
- Save/load preserves restock timers exactly.
- Reloading a checkpoint and replaying the same time advances produces
  identical stock.
- Full baseline passes.

## Checkpoint 5: Event Scheduler Core

### Goal

Build the deterministic event scheduler that decides what happens and
when, without yet implementing specific event types.

### Deliverables

- `scripts/events/EventScheduler.gd` (autoload):
  - `_on_campaign_time_changed(total_minutes)` — main tick.
  - `_evaluate_eligible_events(context: EventContext) -> Array[EventCandidate]`
  - `_select_event(candidates) -> EventCandidate or null` — seeded RNG
    pick weighted by priority.
  - `_execute_event(candidate)` — dispatches to registered handler.
  - Pacing budget: at most 1 event per 30 minutes of campaign time.
  - Per-type cooldowns: e.g. interceptor events at most once per 90 min.
  - `event_triggered` signal for UI/chronicle integration.
- `scripts/events/EventContext.gd`:
  - Snapshot of game state for eligibility checks: current system, active
    missions, player rep, campaign time, recent event history.
- `scripts/events/EventType.gd` (base class):
  - `event_type_id() -> String`
  - `is_eligible(context: EventContext) -> bool`
  - `priority(context: EventContext) -> float`
  - `execute(context: EventContext) -> Dictionary` — returns hints for
    UI/chronicle.
  - `save_state() / restore_state()` for in-progress events.
- `scripts/events/EventHistory.gd`:
  - Tracks last N events with timestamps for cooldown checks.
  - `to_dict() / from_dict()` for save/load.
- Seeded RNG: `EventScheduler` derives its seed from
  `campaign_time + system_id.hash()` so identical game states produce
  identical event sequences.

### Verification

- Focused test: register a TestEvent, advance time, verify it fires.
- Pacing test: advance time rapidly, verify at most 1 event per 30 min.
- Cooldown test: fire an event, advance 60 min, verify same type blocked.
  Advance to 90 min, verify eligible again.
- Seed determinism test: same context produces same event selection.
- Save/load preserves event history and cooldown state.

## Checkpoint 6: Interceptor Events

### Goal

Add the first real event type: hostile interceptors that spawn on gate
arrival based on active mission risk.

### Deliverables

- `scripts/events/types/InterceptorEvent.gd` extends EventType:
  - Eligible when: player has active mission with `risk_tag` AND just
    arrived in a system (checked via `context.just_arrived`).
  - Risk tags: `"combat_target"` (kill missions), `"valuable_cargo"`
    (pickup/delivery), `"urgent"` (urgent board postings).
  - Priority scales with mission reward and faction hostility.
  - `execute()`:
    - Picks interceptor faction (target faction for kill missions,
      pirate/reaver for cargo missions).
    - Spawns 1–3 hostile NPCs near the arrival gate using existing
      `spawn_reinforcement()` pattern.
    - Tags them as `is_interceptor = true` for tracking and cleanup.
    - Emits system chatter warning ("Hostile contacts near the gate").
    - Returns chronicle hints.
- `MissionObjectiveDefinition` gains `risk_tags: Array[String]` —
  populated during `build_active_state()` based on objective type.
- GameRoot `_change_system()` sets `EventContext.just_arrived = true`
  before the first time tick in the new system.
- Interceptor cleanup: if player jumps away or docks, surviving
  interceptors despawn (same as mission target cleanup pattern).
- Interceptor defeat: killing all interceptors grants a small credit
  bounty (10–30 SC per ship) and positive system chatter.

### Verification

- Focused test: create context with active kill mission + just_arrived,
  verify InterceptorEvent is eligible. Without mission, verify not
  eligible.
- Spawn test: execute event, verify NPCs spawned near gate with
  `is_interceptor` tag.
- Cleanup test: dock while interceptors alive, verify they despawn.
- Risk scaling test: urgent mission produces higher priority than normal.
- Full baseline passes.

## Checkpoint 7: Segment 3 Regression

### Deliverables

- Add focused tests for:
  - Store data model: pricing, stock, restock, depletion penalty.
  - Player inventory: add/remove/save/load.
  - Event scheduler: eligibility, pacing, cooldowns, seed determinism.
  - Interceptor event: risk tags, spawn, cleanup, bounty.
- Add gameplay smoke tests:
  - Dock, buy items, use consumable, verify effect.
  - Accept mission, jump to new system, verify interceptor eligibility
    evaluated (may or may not spawn depending on RNG seed).
  - Save with store stock depleted, reload, verify stock state preserved.
- Run the full baseline suite.
- Update the Segment 3 checklist in `phase_3_to_7_development_plan.md`.

## Implementation Notes

### Determinism And Anti-Exploit

The key risk in Segment 3 is exploitability. Two rules:

1. **Stock is deterministic from time.** Reloading a save and replaying
   the same actions produces the same stock. No RNG in restock — pure
   time thresholds.
2. **Events are seeded.** The event scheduler's RNG seed is derived from
   campaign time + system hash. Reloading and replaying the same jump
   produces the same interceptor roll. Players can avoid events by
   choosing different routes, not by save-scumming.

### Migration Safety

Existing saves have no store or inventory data. On load:
- Missing `store_stock` key → initialize all stores to default stock.
- Missing `player_inventory` key → empty inventory.
- Missing `event_history` key → empty history (no cooldowns active).

### What Gets Deferred

- Dynamic commodity trading (buy low, sell high between systems).
- Faction-specific contraband or illegal goods.
- Store reputation unlocks (special items at high rep).
- Multi-system supply chain effects.
- Ambient trader convoy events (non-hostile random encounters).
- Weather/hazard events that affect navigation.

These belong in Segments 4+ or Phase 5+ of the architecture doc.
