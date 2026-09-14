# Dock / Service Button Audit

Reviewed: 2026-06-21  
Source: `scripts/UIManager.gd` — `_create_dock_menu()` (line 897) and `_render_dock_submenu()` (line 3220)

## Button Inventory

| # | Button | Label text | Submenu | Has disabled state? | Has tooltip? |
|---|--------|-----------|---------|---------------------|-------------|
| 1 | `sell_btn` | "Sell Ore (1 SC per m³)" | Services | **No** — clickable even with 0 ore (silently no-ops) | No |
| 2 | `repair_btn` | Dynamic (see below) | Maintenance | **Yes** — 4 states with cost info | No |
| 3 | `maintenance_bay_btn` | "Maintenance Bay (Grease Monkeys)" or generated name | Services | No (hidden at outposts) | No |
| 4 | `station_lounge_btn` | "Station Lounge" | Services | No (hidden when no contacts) | No |
| 5 | `public_board_btn` | "Public Contract Board" | Services | No (hidden at outposts) | No |
| 6 | `agent_service_btn` | "Talk to Agent" | Services | No (hidden at outposts) | No |
| 7 | `store_btn` | "Station Store" | Services | **No** — never disabled or hidden | No |
| 8 | `inventory_btn` | "Inventory" | Services + always | No | No |
| 9 | `ship_upgrades_btn` | "Ship Upgrades (Rusthawk UI)" | Maintenance | No | No |
| 10 | `hear_gossip_btn` | "Hear Gossip from the Locals" | (unused — always hidden) | No | No |
| 11 | `ask_for_part_btn` | Dynamic ("Ask X for Y" / "Trade Ore for Y") | Services (outpost, conditional) | Explicit `disabled = false` when shown | No |
| 12 | `deliver_part_btn` | "Deliver Part" | Maintenance (conditional) | No | No |
| 13 | `back_to_services_btn` | "Back to Services" | Maintenance / Lounge | No | No |
| 14 | `undock_btn` | "Undock Ship" | Always | No | No |
| 15 | `ore_trade_accept_btn` | "Sell Ore, Take the Part" | Popup | No | No |
| 16 | `ore_trade_decline_btn` | "No, Keep My Ore" | Popup | No | No |
| 17 | `mechanic_pickup_accept_btn` | "I'll grab it" | Mechanic intro | No | No |
| 18 | `mechanic_pickup_decline_btn` | "Not now" | Mechanic intro | No | No |
| 19–21 | `test_pickup_btn` / `test_deliver_btn` / `test_pickup_part_btn` | "Test: ..." | DEBUG only | No | No |

## Findings

### 1. Inconsistent capitalization

- **Title Case**: "Sell Ore", "Repair Ship", "Station Lounge", "Station Store", "Undock Ship", "Deliver Part"
- **Sentence case**: "Talk to Agent", "Hear Gossip from the Locals", "Ask for the Part", "I'll grab it", "Not now"
- **Mixed**: "Sell Ore, Take the Part" (title), "No, Keep My Ore" (title)
- **Internal label**: "Ship Upgrades (Rusthawk UI)" — "(Rusthawk UI)" is a dev-facing label leaking into the player UI
- **Recommendation**: Standardize on Title Case for all action buttons. Remove "(Rusthawk UI)" from the player-facing label.

### 2. Missing disabled states

- **`sell_btn`**: Clickable with 0 ore — silently does nothing. Should be disabled with text like "Sell Ore (No Ore)" or "Sell Ore (Hold is Empty)".
- **`store_btn`**: Always visible, never disabled. If the store has no items or the station has no store, the handler just `return`s silently. Could show "Station Store (Unavailable)" when empty.

### 3. Missing disabled-state feedback messages

`repair_btn` is the gold standard — it shows 4 distinct states:
- "Repair Ship (Fully Repaired)" — disabled
- "Repair Ship (Full Heal: X HP) - Y SC" — enabled
- "Repair Ship (Partial Heal: X HP) - Y SC" — enabled, can't afford full
- "Repair Ship (Insufficient Credits) - Need Y SC" — disabled

Other buttons that could benefit from similar feedback:
- **`sell_btn`**: Should show current cargo amount and expected earnings
- **`store_btn`**: Could indicate item count or "Browse X items"

### 4. Spacing and layout

- No explicit spacing/margins between buttons — relies on VBoxContainer defaults
- The `dock_label` ("STATION SERVICES") has no bottom margin separating it from the first button
- No visual separator between service categories (trade, social, maintenance, navigation)
- Buttons vary in label length from 4 chars ("Boost") to 45+ chars ("Trade Ore for X (100 m³ → 200 SC)")

### 5. Debug buttons visible in DEBUG_TESTS mode

- "Test: Start Pickup Quest", "Test: Deliver Part", "Test: Pickup Part" are gated behind `DEBUG_TESTS` — safe, just noting they exist

### 6. `store_btn` visibility

`store_btn` is not conditionally hidden at outposts even though `sell_btn`, `agent_service_btn`, `public_board_btn`, and `maintenance_bay_btn` all are. If outposts don't have stores, `store_btn` should also be hidden at outposts.

### 7. Dev-facing label in player UI

"Ship Upgrades (Rusthawk UI)" exposes an internal ship name. Should just be "Ship Upgrades" or the dynamic ship name if available.

## Safe Fixes (effect-only, no logic changes)

1. **Move `sell_btn` into the Agent panel** — selling ore now happens through Broker Kaelen, not the main services menu. Button shows cargo amount and earnings when ore is present, disabled with "Hold Empty" otherwise.
2. **Hide `store_btn` at outposts** — match pattern of other service buttons
3. **Remove "(Rusthawk UI)" from ship upgrades label**
4. **Standardize button capitalization to Title Case**
