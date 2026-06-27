# Claude Work Queue

Fresh handoff list for Claude while Codex is on cooldown.

## Current Context

- Codex just finished the sensor/power-budget step.
- Codex usually cannot stage/commit/push in this workspace because its sandbox cannot write `.git`. Claude may not have this limitation. If Git works for Claude, it can use the normal project push flow.
- Do not start a broad refactor. Keep each item small, testable, and easy for Codex to review later.
- Before broad exploration, read `PROJECT_MAP.md`. Before resuming after another assistant, read `docs/whileYouWasSleeping.md`.

## Do Not Touch Unless Abe Explicitly Redirects

- Campaign bible generation and story-state persistence.
- Mission schema/objective contracts.
- Store demand/provenance rules just added by Codex.
- Sensor/power-budget tuning just added by Codex, except for clearly documenting issues found during testing.
- Generated-system save/load or transaction-store behavior.

## Best Tasks For Claude

- [ ] **Manual QA: sensor scan tiers**
  - Start combat with starter sensors and confirm the panel only shows `THREAT LEVEL: HIGH` or `EXTREME`.
  - Upgrade sensors once and confirm it shows hull/weapons/engine tiers.
  - Upgrade sensors twice and confirm it shows full assessment plus warnings when the enemy outclasses the player.
  - Save screenshots or short notes of any confusing wording.

- [ ] **Manual QA: power budget upgrades**
  - In the maintenance bay, confirm starter power draw reads `255 / 300 MW`.
  - Confirm one modest upgrade can fit.
  - Confirm stacked upgrades can hit the power limit.
  - Confirm upgrading the powerplant allows the blocked upgrade.
  - Do not retune numbers unless Abe asks; just document what feels wrong.

- [ ] **Combat UI readability pass**
  - Check the combat sensor panel at 720p, 1080p, and ultrawide.
  - Look for text clipping, unreadably fast typewriter text, or overlap with the combat wheel.
  - Safe fixes: label wrapping, panel width/height, font size, or wording length.

- [ ] **Attack drone visibility**
  - Review the attack drone during combat and make it easier to see if the fix is visual-only.
  - Safe fixes: glow, scale, trail, color, or temporary marker.
  - Avoid combat damage/rules changes.

- [ ] **Damage-number resistance feedback design note**
  - Create a short implementation note for resisted/effective damage numbers.
  - Include suggested colors, scale difference, and where the numbers should appear.
  - Do not implement unless Abe asks during Claude's pass.

- [ ] **Store UI presentation notes**
  - Review the current buy/sell rows after Codex's economy pass.
  - Check whether owned-item sell prices are visible only for items in inventory.
  - Note any places where the UI reveals too much market information.
  - Safe fixes: spacing, labels, button disabled text.

- [ ] **Known warnings cleanup note**
  - Add any new harmless warnings from headless runs to the existing docs note if they are not already listed.
  - Keep real failures separate from noisy shutdown warnings.

## Useful Commands

Run Godot tests sequentially with unique log files:

```powershell
$logPath = Join-Path (Get-Location) ".tmp_godot_user\test_logs\parse_check.log"
.\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/parse_check.gd --log-file $logPath
```

Focused tests that currently matter:

```powershell
$logPath = Join-Path (Get-Location) ".tmp_godot_user\test_logs\upgrade_power.log"
.\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/economy/run_upgrade_power_tests.gd --log-file $logPath
```

## Notes For Codex After Cooldown

- Update `docs/todo.md` after the sensor/power step is pushed.
- If Claude changes anything, check `docs/whileYouWasSleeping.md` and this file before continuing.
- Next likely Codex item after this step: either boss tier override or mixed-profile squads, unless Abe redirects.
