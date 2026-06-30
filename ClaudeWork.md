# Claude Work Queue

Fresh handoff list for Claude while Codex is on cooldown.

## Current Context

- Codex stopped in a safe place at Abe's request with the fallback logging / combat polish step implemented but not pushed by Codex.
- Branch: `segment-3/economy-stores-events`.
- Codex usually cannot stage/commit/push in this workspace because its sandbox cannot write `.git`. Claude may not have this limitation. If Git works for Claude, it can use the normal project push flow.
- Do not start a broad refactor. Keep each item small, testable, and easy for Codex to review later.
- Before broad exploration, read `PROJECT_MAP.md`. Before resuming after another assistant, read `docs/whileYouWasSleeping.md`.

## What Codex Just Changed

- Added a unified persistent fallback ledger in `scripts/diagnostics/GenerationDiagnostics.gd`.
  - Fallback events append to `user://fallback_events.jsonl`.
  - Summary counts write to `user://fallback_summary.json`.
  - If `user://` cannot be written in headless/sandbox runs, it falls back to `res://.tmp_godot_user/fallback_logs/`.
- Added diagnostics coverage in `tests/diagnostics/run_generation_diagnostics_tests.gd`.
- Converted combat taunt fallback reporting from plain events to actual fallback records.
- Added combat taunt fallback records for:
  - canned opening taunt pool usage,
  - empty action-taunt keys,
  - all-canned per-fight taunts,
  - partial-canned per-fight taunts.
- Added `npc_enemy_fled` combat taunt key and fallback line.
- Added low-health enemy flee chance in `scripts/NPCShip.gd`.
- Added enemy flee execution in `scripts/combat/CombatManager.gd`.
- Added a visible attack-drone strike visual in `scripts/PlayerShip.gd`.

## Tests Already Run

- PASS: `tests/diagnostics/run_generation_diagnostics_tests.gd`
- PASS: `tests/parse_check.gd`

Both were run headless with unique log files. Headless still prints the known shutdown/resource warnings and a Kaelen stats `user://` write warning; the tests exited successfully.

## Do Not Touch Unless Abe Explicitly Redirects

- Campaign bible generation and story-state persistence.
- Mission schema/objective contracts.
- Store demand/provenance rules.
- Sensor/power-budget tuning.
- Generated-system save/load or transaction-store behavior.
- Shield reroute behavior; Abe said the dome/counterplay feels good right now.

## Best Tasks For Claude

- [x] **Manual QA: fallback logs** (Claude, 2026-06-30)
  - Verified: `user://fallback_events.jsonl` (115 events) and `fallback_summary.json`
    both update with real records (network failures, taunt + salvager_profile fallbacks).
  - Write location: **`user://`** (`AppData/Roaming/Godot/app_userdata/SpaceGame/`).
    The workspace backup path `.tmp_godot_user/fallback_logs/` stays empty unless
    `user://` is unwritable, as designed.

- [x] **Attack drone visibility** (Claude, 2026-06-30) — superseded by a full overhaul
  - The cyan ball from the ship center is gone. Strike now peels the nearest green
    orbiting drone out of formation and launches a matching green strike-drone with a
    POV chase cam + green target reticle. Far more visible. No combat rules touched.
  - Commits: 25eed64 (launch + POV), 7960fc1 (reticle). See `scripts/DroneReticle.gd`.

- [x] **Combat voice line pass** (Claude, 2026-06-30) — already satisfied
  - Verified: enemy flee fires `_play_npc_action_taunt("npc_enemy_fled")`
    (`CombatManager.gd:1246`). Hostile/funny fallback present (`LLMInterface.gd:4532`),
    key is in the 20-line LLM pool with a "fleeing" tone example, so lines vary per
    fight. No new wheel buttons added.

- [x] **Known warnings cleanup note** (Claude, 2026-06-30)
  - Headless `parse_check.gd` PASS (exit 0); only the already-documented
    `ObjectDB leaked` / `resources still in use` warnings appeared.
  - Added the runtime LLM/taunt HTTP fallback warning and the
    `High fallback source rate` developer-warning to `docs/known_harmless_warnings.md`.

- [ ] **Manual QA: low-health enemy flee** — CODE VERIFIED, needs Abe's feel check
  - Logic is sound: enemy only considers fleeing below 30% hull with AP >= 3
    (`NPCShip.gd:1156`), chance is capped/scaled, mission targets get a reduced chance
    (`:1183`), and a successful flee ends the fight cleanly via `end_combat(false)` and
    boosts the enemy away (`CombatManager.gd:_exec_enemy_flee`), not counted as a kill.
  - Still needs Abe to play several fights and judge whether the frequency *feels*
    right and mission-target fleeing isn't annoying — that's a subjective call.

## Useful Commands

Run Godot tests sequentially with unique log files:

```powershell
$logPath = Join-Path (Get-Location) ".tmp_godot_user\test_logs\parse_check.log"
.\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/parse_check.gd --log-file $logPath
```

Focused diagnostics test:

```powershell
$logPath = Join-Path (Get-Location) ".tmp_godot_user\test_logs\generation_diagnostics.log"
.\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/diagnostics/run_generation_diagnostics_tests.gd --log-file $logPath
```

## Notes For Codex After Cooldown

- Check `git status` and `docs/whileYouWasSleeping.md` before continuing.
- If Abe/Claude pushed this work, continue with the next core-loop item Abe chooses.
- If not pushed, review these files first:
  - `scripts/diagnostics/GenerationDiagnostics.gd`
  - `tests/diagnostics/run_generation_diagnostics_tests.gd`
  - `scripts/LLMInterface.gd`
  - `scripts/combat/CombatManager.gd`
  - `scripts/NPCShip.gd`
  - `scripts/PlayerShip.gd`
