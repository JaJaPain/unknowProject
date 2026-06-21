# Combat Visual Feedback Audit

Reviewed: 2026-06-21  
Sources: `scripts/Projectile.gd`, `scripts/PlayerShip.gd`, `scripts/NPCShip.gd`, `scripts/NPCSalvager.gd`, `scripts/Asteroid.gd`, `scripts/visuals/ImpactEffect.gd`

## Effect Inventory

| Event | Audio | Visual Effect | Status |
|-------|-------|--------------|--------|
| Projectile hits ship | (via take_damage) | `ImpactEffect.spawn_hit()` — flash + sparks | **Present** |
| Projectile hits asteroid | (none) | `ImpactEffect.spawn_hit()` — grey sparks | **Present** |
| Player ship death | `play_explosion()` | `ImpactEffect.spawn_explosion()` — flash + debris + fireball | **Present** |
| NPC ship death | `play_explosion()` | `ImpactEffect.spawn_explosion()` with engine color | **Present** |
| NPC salvager death | `play_explosion()` | `ImpactEffect.spawn_explosion()` — added | **Fixed** |
| Asteroid depletion | `play_explosion()` | `ImpactEffect.spawn_explosion()` — added | **Fixed** |
| Shield absorbs hit | (none) | **None** — no distinct shield flash | **Missing** |
| Hull takes damage (player) | (none) | **None** — no screen flash, shake, or tint | **Missing** |
| Hull takes damage (NPC) | (none) | **None** — no hull flash or color tint | **Missing** |
| Cargo/ore collected (mining) | (none) | Mine particles (ore chunks) — present | **Present** |
| Wreckage salvaged | (none) | **None** — wreckage just disappears | **Missing** |
| Repair kit used | `play_repair()` | **None** — no heal flash or hull glow | **Missing** |
| Shield cell used | (none) | **None** — no shield recharge visual | **Missing** |

## Findings

### NPC Ship Explosion Visual — Already Present

`NPCShip.die()` already calls `ImpactEffect.spawn_explosion()` with the engine color at line 742.

### Fixed: NPCSalvager Explosion Visual

`NPCSalvager.die()` was missing a visual — added `spawn_explosion()` with warm orange color and 0.8x scale.

### Fixed: Asteroid Depletion Visual

`Asteroid.deplete()` was missing a visual — added `spawn_explosion()` with rock-brown color and 0.6x scale.

### Missing: Shield vs Hull Hit Distinction

`PlayerShip.take_damage()` (line 1823) processes shield absorption vs hull damage but spawns no visual for either. The projectile impact effect fires at the hit point (in `Projectile.gd`), but the *target* shows no reaction. A cyan flash for shield hits and a red/orange flash for hull hits would give immediate feedback.

### Missing: Damage Feedback on Player

No screen shake, red tint, or vignette when the player takes hull damage. Combined with the lack of hull hit flash, the player may not notice they're being hit until health is low.

### Missing: Wreckage Salvage Effect

When a salvager collects wreckage, the wreckage node is freed with no visual transition — it just vanishes. A dissolve, shrink, or particle pull effect would indicate collection.

## Applied Safe Fixes (visual-only, no logic changes)

1. ~~`NPCShip.die()`~~ — already had `spawn_explosion()` at end of function
2. **Added `ImpactEffect.spawn_explosion()` to `NPCSalvager.die()`** — warm orange, 0.8x scale
3. **Added `ImpactEffect.spawn_explosion()` to `Asteroid.deplete()`** — rock brown, 0.6x scale

## Deferred (need more design input)

4. Shield hit flash (cyan tint on shield absorb)
5. Hull hit flash (red tint / screen shake on hull damage)
6. Consumable use effects (heal glow, shield recharge)
7. Wreckage salvage dissolve
