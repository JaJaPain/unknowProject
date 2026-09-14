# Assets & Metadata Notes
_Audit date: 2026-06-21 — covers portrait_sheets.json, portrait_spritesheet_layout_with_gender.json, UIManager.gd, GameContentRegistry.gd_

---

## 1. Kaelen Mood Sprite Verification

**Sheet:** `res://assets/KaelenMoods.png` — 1254×1254px, 3×3 grid, 418×418px per cell.

| Grid position | Mood ID | Tags | Coordinates |
|---|---|---|---|
| Row 0, Col 0 | `calm` | confident | (0, 0) |
| Row 0, Col 1 | `neutral` | default | (418, 0) |
| Row 0, Col 2 | `angry` | threat | (836, 0) |
| Row 1, Col 0 | `amused` | dry_humor | (0, 418) |
| Row 1, Col 1 | `somber` | regret | (418, 418) |
| Row 1, Col 2 | `suspicious` | watchful | (836, 418) |
| Row 2, Col 0 | `worried` | concerned | (0, 836) |
| Row 2, Col 1 | `intrigued` | mystery | (418, 836) |
| Row 2, Col 2 | `exhausted` | grief | (836, 836) |

**Verified:** `KAELEN_ALLOWED_MOODS` in `UIManager.gd:191` lists all 9 moods and matches the JSON exactly. No off-by-one in coordinates (3 × 418 = 1254 ✓). No missing or orphaned entries.

**"WTF" expression note:** The bottom-right slot (`exhausted`, tagged `grief`) is the closest existing mood to a WTF/dismay expression. If a distinctly shocked/WTF face is needed, it would require a new mood slot — the 3×3 grid is currently full. Could replace `exhausted` or expand to a 3×4 sheet.

---

## 2. Asset Naming Guide

### Portraits

| Asset type | Location | Naming convention | Example |
|---|---|---|---|
| Random generated portrait sheets | `assets/Portraits/` | `P###.png` (3-digit index) | `P001.png` — `P006.png` |
| Portrait layout metadata | `assets/Portraits/` | `portrait_spritesheet_layout_with_gender.json` | — |
| Named NPC portrait sheets | `assets/` (root) | `MinorNPC##.png` | `MinorNPC01.png`, `MinorNPC02.png` |
| Quest giver portraits | `assets/` (root) | `QuestGivers.png` | — |
| Kaelen mood sheet | `assets/` (root) | `KaelenMoods.png` | — |

**Issue:** Named NPC portraits, quest givers, and Kaelen moods live in `assets/` root while random portrait sheets live in `assets/Portraits/`. This inconsistency is low-risk right now but will become confusing when more portrait sets are added. **Recommendation:** move `MinorNPC01.png`, `MinorNPC02.png`, `QuestGivers.png`, and `KaelenMoods.png` to `assets/Portraits/` and update `portrait_sheets.json` paths — but only worth doing as part of a larger art pass, not now.

### Faction Branding

| Asset type | Location | Naming convention | Example |
|---|---|---|---|
| Faction badge sheet | `assets/` | `factionBranding.png` | — |
| Generated ship hull | `assets/ships/generated/` | `ship_{seed}_{variant}_{layer}.png` | `ship_349663091_1_hull_normal.png` |
| Generated ship badge | `assets/ships/generated/` | `ship_{seed}_{variant}_{FactionName}Badge.png` | `ship_349663091_7_VanguardBadge.png` |
| Generated ship material | `assets/ships/generated/` | `ship_{seed}_{variant}_{ColorName}Metal.png` | `ship_349663091_8_NavyBlueMetal.png` |

**Badge naming observation:** `AurelliaBadge` (double-l) appears in the generated ship files — e.g. `ship_171600929_5_AurelliaBadge.png`. The faction is spelled `Aurelia` (single l) everywhere in code/data. This is a cosmetic typo in file names only; it doesn't affect gameplay since the path is assembled at generation time and read back correctly. Flag to fix if re-generating ship assets.

### Other Assets

| Asset type | Location | Convention |
|---|---|---|
| Asteroid models | `assets/asteroids/` | `rock_{index}.glb` |
| Asteroid texture atlas | `assets/` | `asteroidTextures.png` |
| Ship renders | `assets/` | `INDYMiner_render_{angle}.png` |
| UI base images | `assets/` | `UI_BASE.png`, `UI_Background.png` |
| Random icons | `assets/` | `RandomIcon##.png` |

---

## 3. NPC Portrait Metadata Review

### Named NPC sheets (portrait_sheets.json)

All 8 named NPCs across `MinorNPC01` and `MinorNPC02` have complete metadata:
- ✓ Unique portrait IDs (`portrait.minor_npc_01.cassen_vane`, etc.)
- ✓ Pixel-exact bounds matching 2×2 grid in 1254×1254px sheets (627×627 per cell)
- ✓ Role/faction tags present
- ✓ No duplicate IDs

**No issues found in the named NPC portrait metadata.**

### Random portrait pool (P001-P006)

6 sheets × 25 portraits = **150 total random portraits** for generated contacts.

Metadata quality:
- ✓ All portraits have `gender`, `gender_confidence`, `age_group`, `usable_for_story_gender`
- ✓ All tagged `space_future`, `portrait`, `civilian_or_crew`
- ⚠️ **Only one non-binary/ambiguous portrait:** `P002_13` (gender: unknown, confidence: low) — the rest are binary male/female. Not a bug, just a pool characteristic.
- ⚠️ **No role/archetype tags** (e.g. `mercenary`, `corporate`, `mechanic`) — all are generic `civilian_or_crew`. This means generated contacts can't be filtered by role type. Future improvement: role-tag a subset of portraits for better archetype matching.
- ✓ Bounds arithmetic: 5×250 = 1250px; image is 1254px — 4px right-edge padding, no rendering concern.

### Folder placement issue (minor)

`portrait_spritesheet_layout_with_gender.json` is imported via `portrait_sheets.json` `imports` array. The file lives in `assets/Portraits/` which is the right place. But `portrait_sheets.json` itself is in `data/content/` — consistent with all other data files. Clean.

---

## 4. Faction Badge Audit

`factionBranding.png` exists in `assets/` root but has **no entry in `portrait_sheets.json`** and no explicit metadata file. It's referenced directly by faction code paths.
<br/>

Generated ship badge files follow the pattern `{FactionName}Badge.png` embedded in the ship generated folder. Badges seen:
- `ZenithBadge` — used on ship variants 2–8 of seed `349663091`
- `VanguardBadge` — used on variant 7 of seed `349663091`
- `AurelliaBadge` (typo) — used on variants 1, 3, 4, 5 of seed `171600929`

**No badge for Reaver faction** in the generated ship pool inspected — this may be intentional (Reavers are a minor/pirate faction with no corporate livery system).

**Icon assets:** `RandomIcon01.png`, `RandomIcon02.png`, `RandomIcon03.png` exist in `assets/` root with no metadata. Usage unclear from this audit — check if these are used in the UI or are orphaned. Low priority.

---

## 5. Generated Faction Asset Readiness Checklist

When adding a new **generated faction** to the game, the following assets and data entries are needed:

### Required
- [ ] **Faction color** — RGBA value in `GlobalState.faction_info()` or generation config
- [ ] **Display name** — Title Case, space-separated, ≤ 3 words, no hyphens
- [ ] **Faction ID** — `gen_` prefix, snake_case, e.g. `gen_latch_parish`
- [ ] **Voice style** — pick from `GENERATED_CONTACT_VOICES` pool (never `af_bella`)
- [ ] **Portrait pool** — auto-assigned from P001-P006 random pool via `curated_portrait_sheet`; no extra work needed if using the existing pool

### Optional (needed for full-service stations)
- [ ] **Ship badge texture** — `{FactionName}Badge.png` in `assets/ships/generated/` if generating faction ships
- [ ] **Hull material texture** — `{ColorName}Metal.png` to match faction color
- [ ] **Agent portrait** — if the faction gets a quest-giver agent, an `agent_portrait_id` entry in `factions.json`

### Not needed (auto-generated)
- Faction abbreviation (`abbrev`) — auto-derived from first 3 letters of display name
- NPC contact names — generated from `_generated_contact_name()` in GlobalState
- Flavor lines — assigned from `GENERATED_CONTACT_LINES` / faction-specific buckets
- Voice speed — defaults to 1.0; only override for character-specific feel
