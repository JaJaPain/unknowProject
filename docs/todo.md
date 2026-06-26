# TODO
_Active task list. Update this file at the end of every session._

---

## Combat

- [ ] **Phase 6 — Enemy kit parity** — enemies should be able to Reposition and Brace as readable actions (mirrors player options); add flavor telegraphs for each
- [ ] **Phase 7 — Boss (mega)** — DONE (in-game) but needs StoryManager trigger hook so scripted story beats can spawn the boss fight (see Story section below)
- [ ] **Phase 8 — Squads** — DONE (in-game) but needs StoryManager trigger hook (see Story section below)
- [ ] **Shield Reroute sub-picker** — currently defaults to Front face; needs the face-select sub-wheel
- [ ] **Boost direction toggle** — currently defaults to "closer to enemy"; needs toggle for Evade/Close
- [ ] **Attack drone visual** — drone is hard to see during combat; needs a more visible model or glow
- [ ] **Salvage drone loot prompt** — rare Kaelen hook after a kill; prompt to deploy salvage drone for bonus loot
- [ ] **Enemy low-health escalation arc** — enemy dialogue/behavior should escalate when below 30% HP
- [ ] **Impact decals on player ship** — hull hit marks that persist during a fight
- [ ] **Richer combat taunt flavor** — taunt bucket system: reason-aware taunts (flanked, shielded, drone hit, etc.)

---

## Story / StoryManager

- [ ] **Boss fight trigger tool** — expose `GameRoot.trigger_boss_encounter(faction, stats_override)` so StoryManager can script a boss ambush as a story beat
- [ ] **Squad fight trigger tool** — expose `GameRoot.trigger_squad_encounter(faction, count)` for scripted 2-on-1 ambushes
- [ ] **Anomaly data core delivery** — anomaly drops a named data core; player delivers to NPC for payout via special cargo system
- [ ] **Salvage drone loot prompt** — (also listed under Combat) post-kill Kaelen hook

---

## World / Exploration

- [ ] **Map hover tooltips** — hovering a map node shows stations, ore types, factions present
- [ ] **Route planner** — click-to-plan route; gates highlight in overview; auto-clears on arrival
- [ ] **Gate portal particles** — particle effects off the gate portal (portal shader is locked/approved, don't touch it)
- [ ] **Generated systems: NPC ships** — procedural systems feel empty; need ambient NPC traffic
- [ ] **Generated systems: station variety** — all proc-gen stations look the same; need visual variants
- [ ] **Generated systems: difficulty scaling** — enemy stats should scale with system danger level
- [ ] **Discovery visual treatments** — named/story systems should feel different on arrival: skybox tint, arrival text banner, environmental storytelling (debris, explosion haze). See `docs/design_parking_lot.md §2`

---

## UI / UX

- [ ] **Quest tracker panel blue box on second quest** — `reset_size()` fires on first show only; second quest reloading the panel brings back the oversized box (see bugs.md)
- [ ] **Station lounge social layer** — relationship heat bar, contact moods, "last seen" timestamp, rumor badge. See `docs/design_parking_lot.md §1`
- [ ] **Store presentation polish** — item cards, purchase confirm dialog, inventory integration, mission highlight. See `docs/design_parking_lot.md §3`

---

## Polish / Future

- [ ] **NAS asset migration** — move binary assets off git repo to NAS once hardware acquired; binaries-in-repo is accepted interim
- [ ] **Boss cinematic phases** — phase transition should have its own brief camera moment / sting beyond the current chatter line
- [ ] **Multi-boss / 3-on-1** — true squad fights beyond 2 enemies; needs a target picker on the wheel
