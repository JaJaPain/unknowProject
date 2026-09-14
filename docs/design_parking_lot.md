# Design Parking Lot
_Sketches and ideas for future work — notes only, no implementation._

---

## 1. Station Lounge — Light Social Sim Affordances

**Concept:** The lounge already shows named contacts as buttons. A light social
layer could give those contacts persistent state without touching mission logic.

**Sketch ideas:**

- **Relationship heat bar** — A subtle colored pip next to each contact name (green/yellow/red)
  that persists in campaign save. Increases when player talks to them or completes
  work they brokered. Decreases over time or if the player ignores a contact too long.

- **Contact moods** — Contacts could show a one-word mood tag: `[Tense]`, `[Chatty]`,
  `[Distracted]`. This is read-only flavor driven by NPC data or a random daily seed.
  Changes the tone of their flavor lines without requiring new content.

- **"Last seen" timestamp** — `"Cassen Vane — 4 cycles ago"` shown in grey below the
  name. Implies the world has been moving while the player was away.

- **Rumor badge** — A small `(!)` indicator when a contact has fresh flavor text
  the player hasn't read this session. Clears on click. Stored in session state only,
  not persisted.

**Implementation notes (for when this gets built):**
- Relationship state would live in `CampaignNPCIdentityStore` (per-campaign, per-NPC)
- Mood system could be seeded off `GlobalState.day_seed` for daily variation
- Avoid anything that requires a new quest type or new objective schema
- Deeper Lounge feature work should stay parked until Codex greenlights it

---

## 2. Discovery Visual Treatments — Boss-Like Moments

**Concept:** Jumping through a gate into a genuinely rare or story-significant system
should feel different from a routine transit. Currently all gate arrivals look identical.

**Sketch ideas:**

- **Ambient color shift** — The skybox/nebula tint could shift slightly to a unique palette
  for story-flagged systems (deep red for hostile territory, gold-green for an ancient
  station, etc.). Driven by a `visual_theme` tag in the system config.

- **Arrival text banner** — A brief 2-3 second fullscreen text overlay on arrival:
  `"ENTERING: COLD MERIDIAN"` with a faction emblem if the system is faction-controlled.
  Fades out, no player input needed.

- **Encounter staging** — For a "boss" gate (guarded passage, legendary derelict), the exit
  shockwave could be slower and the camera could briefly pan to the point of interest before
  returning to the ship. This would be handled inside the gate transition FX, not game logic.

- **Environmental storytelling** — A system with a destroyed station could have ambient
  debris field particles and a distant explosion afterglow (orange haze) already present
  on arrival, set in the system config.

**Implementation notes:**
- All of this lives in the visual/scene layer — zero impact on mission or quest code
- `visual_theme` tag in system config could drive skybox color, debris density, ambient sound
- The camera pan is the most complex piece — defer until gate transition FX is implemented
- Gate arrival staging would plug into `JumpTransitionFX.play_exit()` as an optional callback

---

## 3. Store Presentation Polish — Future Purchase Missions

**Concept:** When a "buy and deliver" mission type exists, the player needs to see
the item in the store before buying it. Current store UI shows items as a list of
buttons — fine for selling ore, but thin for purchase missions.

**Sketch ideas:**

- **Item cards** — Instead of a flat button list, each item gets a small card with:
  name, price, a small icon (from `icons.png` atlas), and a one-line description.
  Cards could be 3 wide in a grid layout.

- **Purchase confirmation** — A brief confirm dialog (like the repair button) before
  deducting credits. Shows: `[Item Name] — [N] SC — Confirm?`. Prevents accidental buys.

- **Inventory integration** — After purchase, the store button shows `[Owned]` and
  disables rather than disappearing. Prevents re-buying the same quest item.

- **Mission highlight** — If the player has an active "fetch X from store" mission,
  the relevant store item gets a quest marker icon (similar to the `→` arrow in
  the inventory special-cargo row).

**Implementation notes:**
- Do NOT add the PURCHASE_FROM_STORE mission type until Codex designs the objective schema
- Store UI changes are safe to prototype in UIManager — they live in `_create_store_panel()`
  and `_redraw_store_items()`
- Icon atlas (`assets/icons.png`) already exists; needs a lookup table for item → icon index
- The mission highlight would need a signal from QuestManager when the active quest is
  the purchase type
