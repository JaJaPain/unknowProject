# UI Presentation Notes
_Audit date: 2026-06-21_

---

## 1. Generated Faction Contact Screen QA

The generated faction contact screen is the "Station Lounge" view rendered by
`_render_station_contacts()` in UIManager.gd. Each contact shows as a Button:

```
[NPC Name] [Role - Faction]
```

### Portrait Fit
Portraits are fetched via `GlobalState.get_minor_npc_portrait()` and displayed
in the agent panel at whatever size the `agent_portrait` TextureRect uses. The
portrait assignment for generated contacts uses `GENERATED_CONTACT_VOICES` pool
(7 named NPC portraits) for portrait+voice pairing — all are 627×627px slices
from 1254×1254 sheets. At agent panel size (typically ~80-100px) these scale
down cleanly.

**Gap:** No portrait randomization from the P001-P006 random pool yet for
generated contacts — they always cycle through the same 7 named NPC portraits.
Visually this means you'll see the same faces in generated systems.

### Role Subtitle
NPC role is set from `npc_data.get("role", "Local contact")`. Known roles seen:
- `"Faction contact"` — enables quest brokering
- `"Station mechanic"` — enables part-request dialogue
- `"Local contact"` — fallback, no special actions

**Gap:** The role label in the button includes the faction display name, but
only if `faction_label` is non-empty. For generated NPCs from minor factions
(`gen_` prefix), the faction name is resolved via `GlobalState.faction_info()`.
This works correctly — the `gen_` ID gets resolved to the display name.

### Button Spacing
Buttons in the contacts VBox use `separation: 4` — fine at standard resolution.
No clipping observed at 1080p from the code audit.

### Portrait/Voice Pairing
Generated contacts use `GENERATED_CONTACT_VOICES` which are the 7 named NPC
voice profiles (not `af_bella`). Portrait is always the matching named NPC face.
This is consistent but gives no variety. See `assets_metadata_notes.md §3` for
the expansion path (P001-P006 role-tagged pool).

---

## 2. Raw Generated ID Audit — Quest UI and Map UI

### Quest UI (Contract Details block, UIManager.gd:6942)

The contract details block shows:
```
--- Contract Details ---
Client: [faction_display_name]
Objective: [human-readable string]
Base Reward: [N] SC
```

**Client field:** Uses `GlobalState.faction_display_name(faction_id)`. This
function resolves `gen_` prefixed IDs to their `display_name` via
`GlobalState.faction_info()`. Raw IDs should not appear here. ✓

**Objective field:** Built from human-readable strings in the code:
- DELIVER_ORE: `"20 m³ Ore"` — safe ✓
- KILL_SHIPS: `"Destroy 3 [Faction Display Name] ships"` — uses
  `faction_display_name()` ✓
- PICKUP_SPECIAL: `"Pick up [part_name]"` — `part_name` comes from LLM, should
  be natural language but could leak weird values if LLM misbehaves ⚠️
- RECOVER_COMBAT_DROP: Uses `item_name` + `faction_display_name()` ✓

**If `objective_summary` is set** (line 6938-6940), it overrides all of the
above with the LLM-generated summary string. This field comes from the LLM and
could contain raw IDs if the LLM is fed a bad faction name. Monitor log for
`⚠ VALIDATE:` entries.

### Map UI (Overview Panel)

System and gate names in the overview come from `GlobalState.current_system_id`
and gate `display_name` fields. Generated system IDs (`system.gen.frontier.*`)
are only used internally — the `display_name` (e.g. "Cold Meridian") is what
shows in the UI.

**Audit result:** No raw IDs found in normal overview rendering code. The
`display_name` is resolved before display.

### Lounge Contact List

Contact buttons use `GlobalState.faction_info(faction).get("name", ...)` for
faction display — falls back to `faction.capitalize()` if missing. For `gen_`
factions this capitalize fallback would produce `"Gen_latch_parish_02"` if the
faction data is missing. This is a potential raw-ID leak if faction data isn't
loaded.

**Risk: Low** — generated faction data is loaded when the system is visited.
Would only appear if a generated faction ID is in NPC data but the faction
record was never loaded. Add a guardrail: use `GlobalState.faction_display_name()`
which has better fallback handling than raw `faction_info().get("name")`.

---

## 3. Contract Detail Panel — Copy Pass

Current labels in the `--- Contract Details ---` block (UIManager.gd:6942):

| Label | Current text | Assessment |
|---|---|---|
| Header | `--- Contract Details ---` | Functional. Could be `CONTRACT DETAILS` for visual consistency with the dock headers style |
| Client | `Client:` | Clear ✓ |
| Objective | `Objective:` | Clear ✓ |
| Base Reward | `Base Reward: N SC` | Clear ✓ |

**DELIVER_ORE objective string:** `"20 m³ Ore"` — a bit terse. Could be `"Deliver 20 m³ of ore"` but the LLM dialogue above it explains the context, so this is fine as a compact summary.

**KILL_SHIPS objective string:** `"Destroy 3 Zenith ships"` — clear ✓

**PICKUP_SPECIAL:** `"Pick up [part_name]"` — fine ✓

**RECOVER_COMBAT_DROP:** `"Recover [item] from [Faction] wreckage"` — clear ✓

**Verdict:** Contract detail labels are already clean and player-friendly. The
only low-effort improvement would be changing `--- Contract Details ---` to
match the dock panel's all-caps header style (`CONTRACT DETAILS`), but this is
cosmetic and low priority.

---

## 4. Agent Subtitle — Known Gap

`agent_subtitle_label` is hard-coded to `"Neutral Fixer & Profit Broker"`
for all agents (UIManager.gd:1341). This was flagged in
`docs/handoff_dialogue_alignment.md §5`. The label should show the agent's
`agent_role` value from the faction definition.

This is a **known gap**, not a new finding. Fix: set
`agent_subtitle_label.text = str(agent_profile.get("role", "Neutral Fixer & Profit Broker"))`
in the function that populates the agent panel. Low risk — purely cosmetic.
