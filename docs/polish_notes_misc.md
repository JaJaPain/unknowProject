# Miscellaneous Polish Notes
_Audit date: 2026-06-21 — covers asteroid belts, NPC save compatibility,
and player-facing error messages_

---

## 1. Faction-Owned Asteroid Belt Polish (Design Notes)

No implementation yet — notes only for a future visual/design pass.

### Current state
Asteroid belts in generated systems are visually identical regardless of faction
ownership. If a faction controls a belt, there is no visual indication at the belt
itself — the player only learns faction ownership via the mission dialogue or overview.

### Possible additions (notes only)
- **Warning buoy** — A small static mesh (using the existing hypergate_*.png assets
  or a new beacon) placed at the belt edge with a faction decal. Pulses slowly.
  Would need a `beacon_faction` tag in the system asteroid config.
- **Patrol beacon** — An NPC patrol ship that loops near the belt. Already possible
  via `SystemFactory` NPC spawn points — just needs a patrol behavior flag.
- **Permit sign** — A floating sign using a BillboardMesh or Label3D:
  `"VANGUARD MINING ZONE — LICENSED OPERATORS ONLY"`. Text-only, zero art cost.
- **Subtle scanner ring** — A faint animated ring (see jump gate charge glow for
  reference) at the belt boundary. Purely visual, no hitbox.

### When to implement
Only after the faction territory/permit system is designed. Do not add these
visuals to every belt — only to belts with an explicit `owner_faction` that
the player has context for.

---

## 2. Old Campaign Saves — NPC Presentation Compatibility

**Question:** Do old generated campaign saves carry stale NPC presentation data
after recent fixes?

**Audit result:**

`CampaignNpcIdentityStore` uses strict schema version checking (`DOCUMENT_VERSION = 1`).
If an old save has a different schema version, the store **rejects it and creates a
fresh default document** (empty NPC list) rather than loading stale data.

This means:
- Old saves do NOT silently carry stale presentation data — the version gate prevents it.
- Players resuming a pre-v1 campaign will get **fresh NPC identities generated** on
  next system visit. Their names, portraits, and voice assignments will change from
  what was assigned before. This is a **known behavioral difference** for old saves,
  not a bug.
- There is no migration path — intentional, since NPC identity data is not
  player-meaningful (no bonding/relationship system yet).

**Expected behavior for old vs new saves:**

| Scenario | Result |
|---|---|
| Campaign started after NPC identity v1 | Identities persist correctly |
| Campaign started before v1 (schema mismatch) | Identities regenerated on next visit |
| Campaign at generated station with no faction contact | Loading completes without contract (fixed 2026-06-21) |

---

## 3. Player-Friendly Error Message Audit

Player-visible messages shown via `show_hud_warning()` / `show_hud_info()` in UIManager.

### Already clear — no change needed

| Message | Context | Assessment |
|---|---|---|
| `"No living campaign checkpoint is available."` | Respawn/load | Acceptable |
| `"That contact is unavailable."` | Lounge contact | Clear ✓ |
| `"Only faction contacts can offer contract work right now."` | NPC brokering | Clear ✓ |
| `"That contact cannot broker work right now."` | NPC brokering | Clear ✓ |
| `"Inventory full — no free slots."` | Item pickup | Clear ✓ |
| `"Boost drive is cooling down."` | Boost | Clear ✓ |
| `"Boost engaged. Thrusters running hot."` | Boost activate | Clear ✓ |
| `"No jumpgate selected."` | Jump | Clear ✓ |
| `"Navigation command was not accepted."` | Nav | Clear ✓ |

### Could be more helpful

| Current message | Context | Better version |
|---|---|---|
| `"No ship available for item use."` | Item use | `"Return to your ship before using items."` |
| `"Cannot use that item right now."` | Item use | `"That item can't be used in your current state."` |
| `"%s has nothing to say right now." % npc_name` | NPC chat | Fine — uses NPC name ✓ |
| `"It's quiet. Nobody's around to talk to."` | Empty dock | Fine ✓ |
| `"Jump control is unavailable."` | Jump | `"Jump drive is not ready."` — slightly more thematic |

### Safe to fix now (cosmetic, no logic change)

Two messages could be slightly improved without touching any logic:

1. `"No ship available for item use."` → `"Return to your ship before using items."`
2. `"Jump control is unavailable."` → `"Jump drive not ready."`
