# Session Handoff — 2026-06-21

## Branch

`segment-3/economy-stores-events` — all changes pushed, clean working tree.

## What Was Done This Session

### Commits (oldest to newest)

1. **`0a6ef71` — Polish dock UI, add Kaelen ore sale lines, fix missing explosion VFX**
   - Moved "Sell Ore" button from main dock services into the Agent (Broker Kaelen) panel
   - Sell button shows dynamic cargo/earnings text, disabled when hold is empty
   - Kaelen speaks a unique LLM-generated quip when you sell ore (5 fallback lines + background LLM fetch for fresh ones)
   - New chatter type `kaelen_ore_sale` in `LLMInterface.gd` with prompt + fallbacks
   - Hidden `store_btn` at outposts to match other full-station-only buttons
   - Removed dev-facing "(Rusthawk UI)" from Ship Upgrades button
   - Standardized button capitalization to Title Case
   - Added `ImpactEffect.spawn_explosion()` to `NPCSalvager.die()` and `Asteroid.deplete()`
   - Updated smoke test in `GameRoot.gd` to remove stale `sell_btn.visible` check

2. **`40b4b07` — Fix engine glow lingering on wreckage after NPC death**
   - `NPCShip.die()` used `queue_free()` on engine glow before `visual.duplicate()` — the duplicate captured the still-attached glow
   - Fix: `remove_child()` the glow immediately before `queue_free()`
   - Hardened `Wreckage._apply_wrecked_material()` to strip `MultiMeshInstance3D` and `Light3D` nodes from duplicated hulls

3. **`ea0d69d` — Fix Station Lounge layout overflow and spacing**
   - Wrapped `station_contacts_list` in a `ScrollContainer` so NPC list scrolls instead of overflowing
   - Added 10px inset padding to dock panel vbox
   - Added spacer below dock title label + bumped font to 16
   - Capped `dock_message_line` to 4 visible lines (font 14, clip_text)

4. **`2a5d03b` / `b3b50d5` — Station Lounge social-sim design doc**
   - Full design doc at `docs/design_station_lounge_social.md`
   - Bar layout, bartender, NPC presence/mood, LLM conversation system, intel integration
   - 8-phase build order, all open questions resolved

### Audit Docs Created

- `docs/audit_dock_buttons.md` — button inventory, capitalization, disabled states
- `docs/audit_combat_feedback.md` — hit/death/pickup effect checklist
- `docs/audit_boost_thruster.md` — exhaust/boost polish notes (no code changes, deferred)
- `docs/audit_lingering_vfx.md` — VFX lifecycle audit, found the wreckage glow bug
- `docs/audit_station_lounge_layout.md` — layout overflow findings + fixes

## What's Next on ClaudeWork.md

### Not started yet (good next picks):

**UI Polish:**
- [ ] Review inventory UI labels and empty states (consumables, cargo, special items)
- [ ] Add controller-focus notes for station services, inventory, system map, Lounge
- [ ] Check selected-target panel action buttons for active/queued feedback gaps

**Visual Effects:**
- [ ] Review nebula/starfield visuals in generated systems (clipping, brightness, palettes)
- [ ] Add ambient variation for clear-space systems (no nebula)
- [ ] Boost/thruster polish from audit (camera shake, heat glow — needs design sign-off)

**Audio/TTS Hygiene:**
- [ ] Build TTS mispronunciation list (all-caps faction names, etc.)
- [ ] Display-text vs spoken-text cleanup plan
- [ ] Audit "Indy" usage in mission dialogue
- [ ] Generated faction pronunciation hints

**Assets/Metadata:**
- [ ] Kaelen mood sprite metadata verification
- [ ] Asset naming guide
- [ ] NPC portrait review
- [ ] Badge asset review
- [ ] Generated faction asset checklist

**Docs/Tests:**
- [ ] "How to test generated systems visually" checklist
- [ ] "Known harmless warnings" note
- [ ] Review `docs/whileYouWasSleeping.md`
- [ ] Outdated fallback examples in docs
- [ ] Headless Godot crash investigation
- [ ] Safe-to-run-after-visual-changes test list
- [ ] Tests relying on old agent names
- [ ] Noisy diagnostics messages

## Key Files Modified

- `scripts/UIManager.gd` — dock menu, sell ore, Lounge layout (largest changes)
- `scripts/LLMInterface.gd` — `kaelen_ore_sale` chatter type
- `scripts/NPCShip.gd` — engine glow removal before wreckage duplicate
- `scripts/Wreckage.gd` — strip MultiMesh/Light3D from duplicated hulls
- `scripts/NPCSalvager.gd` — added explosion VFX to die()
- `scripts/Asteroid.gd` — added explosion VFX to deplete()
- `scripts/GameRoot.gd` — removed stale smoke test check

## Guardrails Reminder

From ClaudeWork.md — do NOT edit: procedural story generation, campaign bible,
story-pack persistence, generated-system save/load, event scheduler, mission
generation, quest objective schemas, inventory transaction rules, gate unlock
rules, or generated faction identity rules.
