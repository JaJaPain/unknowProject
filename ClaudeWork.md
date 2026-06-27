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

- [ ] **Manual QA: fallback logs**
  - Trigger any LLM fallback or combat-taunt canned fallback.
  - Confirm `fallback_events.jsonl` and `fallback_summary.json` update.
  - Note whether Godot editor writes them under `user://` or the workspace backup path.

- [ ] **Manual QA: attack drone visibility**
  - Use Attack Drone in combat and confirm the cyan strike is visible enough.
  - Safe fixes only: glow, scale, trail, color, or timing.
  - Avoid combat damage/rules changes.

- [ ] **Manual QA: low-health enemy flee**
  - Fight several enemies down below 30% hull.
  - Confirm fleeing feels occasional, not constant.
  - Confirm the fight ends cleanly and the enemy moves away instead of counting as a kill.
  - Note if mission targets fleeing feels annoying; Codex reduced their chance but did not disable it.

- [ ] **Combat voice line pass**
  - Check that enemy fleeing can say a short flee line.
  - Keep the tone hostile/funny but not too repetitive.
  - Do not add new combat wheel buttons; Abe wants to keep the seven current actions for now.

- [ ] **Known warnings cleanup note**
  - Add any new harmless warnings from headless runs to the existing docs note if they are not already listed.
  - Keep real failures separate from noisy shutdown warnings.

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
