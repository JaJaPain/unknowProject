# Controller Focus Notes
_Design notes only — no implementation yet. These document intended focus order
for keyboard/controller navigation through each screen._

---

## Station Services (Dock Menu)

**Entry point:** Player docks → dock panel opens on "Services" submenu.

| Action | Element | Notes |
|---|---|---|
| Initial focus | First visible button in the dock panel | Usually "Talk to Agent" or "Public Board" |
| Next (↓ / Tab) | Next button in dock VBox order | Order: Agent → Board → Maintenance Bay → Store → Station Lounge |
| Back / Cancel | Close dock / return to flight | No "Back" button on Services — ESC should return to flight |
| Confirm (Enter/A) | Activates focused button | |

**Focus gap:** The dock panel uses `add_child()` to build buttons dynamically. Godot's default tab order follows tree order, which matches visual order only if buttons are added top-to-bottom. Verify this matches visual layout before wiring controller input.

---

## Maintenance Submenu

**Entry point:** "Maintenance Bay" button on Services → switches to Maintenance submenu.

| Action | Element | Notes |
|---|---|---|
| Initial focus | "Repair Ship" button (or its disabled state) | |
| Next (↓ / Tab) | "Back to Services" button | Only two interactive elements |
| Back / Cancel | "Back to Services" button | Should mirror the button behavior |

---

## Inventory Panel (Overlay HUD)

**Entry point:** "INVENTORY" HUD button (top-right of screen during flight/docked).

| Action | Element | Notes |
|---|---|---|
| Initial focus | First item row in the cargo list | |
| Next (↓ / Tab) | Next item row | |
| Prev (↑ / Shift+Tab) | Previous item row | |
| Confirm | No action on item rows currently | Future: item detail or use action |
| Back / Cancel | Close inventory overlay | ESC or dedicated close button |

**Focus gap:** Item rows are Labels and HBoxContainers, not focusable Controls. Would need to wrap rows in a Button or use `focus_mode = FOCUS_ALL` on the row container to enable keyboard navigation.

---

## System Map (Overview Panel)

**Entry point:** "SYSTEM MAP" HUD button.

| Action | Element | Notes |
|---|---|---|
| Initial focus | First entry in the overview list | |
| Next (↓ / Tab) | Next overview row | |
| Prev (↑ / Shift+Tab) | Previous overview row | |
| Confirm | Select/target the highlighted entry | Should set `GlobalState.active_target` |
| Back / Cancel | Close map overlay | ESC |
| Sort headers (Name/Distance/Type) | Should be Tab-accessible from the list | Low priority |

**Focus gap:** Overview list rows are Buttons (created in `_create_overview_list_item()`). Tab order depends on child order in the scroll container VBox — should work naturally. The sort header buttons (Name, Distance, Type) sit above the list and might steal tab focus unexpectedly.

---

## Station Lounge

**Entry point:** "Station Lounge" button on Services → switches to Lounge submenu.

| Action | Element | Notes |
|---|---|---|
| Initial focus | First contact button in the contacts list | Kaelen if available, otherwise first NPC |
| Next (↓ / Tab) | Next contact button | |
| Confirm | Expands contact actions or shows dialogue | |
| Back / Cancel | "Back to Services" button | |

**Focus gap:** Contact buttons are created dynamically in `_render_station_contacts()`. The action buttons that appear below a selected contact (expanded inline) would also need focus management — they currently get focus only if the player clicks them.

---

## Implementation Notes (for when this gets built)

1. All panels that slide in should call `grab_focus()` on their first interactive element in `_ready()` or on show.
2. ESC everywhere should map to the same "go back one level" action — close overlay → back to services → undock.
3. Controller-style `ui_accept` / `ui_cancel` / `ui_focus_next` / `ui_focus_prev` are the right signals to wire, not raw keyboard events.
4. Gamepad trigger for "Open Inventory" and "Open Map" should work from flight view without clicking the HUD buttons.
5. Focus should return to the HUD button that opened a panel when the panel closes (not reset to the ship).
