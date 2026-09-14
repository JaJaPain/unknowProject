# Station Lounge Layout Audit

Reviewed: 2026-06-21  
Source: `scripts/UIManager.gd` — `_create_dock_menu()`, `_render_dock_submenu()`, `_render_station_contacts()`

## Dock Panel Dimensions

The dock panel uses anchor-based sizing: 30%-70% horizontal, 25%-75% vertical.

| Resolution | Panel Size | Available Content Height |
|-----------|-----------|------------------------|
| 1920x1080 | 768 x 540 | ~520px |
| 1600x900 | 640 x 450 | ~430px |
| 1280x720 | 512 x 360 | ~340px |
| 1024x576 | 410 x 288 | ~268px |

## Lounge Submenu Layout Stack

1. Title label ("X LOUNGE")
2. Dock message slot (NPC dialogue — portrait + text)
3. Station contacts panel (NPC buttons + expanded action panels)
4. Back to Services button

## Findings & Fixes Applied

### 1. No scroll on contacts list — Fixed

The contacts panel (`station_contacts_list`) was a plain VBoxContainer with no scroll. With 3+ NPCs each showing expanded action panels (role label + 4 topic buttons), the list pushed the Back button off-screen at 720p and below.

**Fix**: Wrapped `station_contacts_list` in a `ScrollContainer` with horizontal scroll disabled. The contacts panel now fills available vertical space and scrolls when content overflows.

### 2. No padding inside dock panel — Fixed

The main VBox sat flush against the dock panel border (all offsets 0), making content crowd the border especially with the styled panel's own border width.

**Fix**: Added 10px inset on all sides of the main VBox.

### 3. Title label crowded content — Fixed

The "STATION SERVICES" / "X LOUNGE" label had no spacing below it, sitting directly against the first content element.

**Fix**: Added a 6px spacer below the title label and set font size to 16 for better visual hierarchy.

### 4. Dock message text could dominate panel — Fixed

Long NPC dialogue in `dock_message_line` had no height cap — a verbose rumor or gossip line could push the contacts panel off-screen.

**Fix**: Clamped `dock_message_line` to `max_lines_visible = 4` with `clip_text = true`, and reduced font size from 16 to 14 to fit more text per line.

## Not Changed (deeper feature work)

- Contact button styling (no hover/pressed color differentiation)
- NPC portrait chips in the contacts list
- Lounge ambient text or mood description
- Social-sim affordances (parked in ClaudeWork.md)
