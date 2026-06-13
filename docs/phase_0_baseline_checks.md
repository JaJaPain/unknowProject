# Phase 0 Baseline Checks

Run from the project root in Command Prompt or PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_baseline_checks.ps1
```

The execution-policy override applies only to that PowerShell process. It does
not change the machine's saved PowerShell policy.

## Included Checks

1. `git diff --check`
2. Godot headless import and script/scene parse
3. Core startup, pause, movement, camera, targeting, and navigation controls
4. Two-way gate travel and save restoration
5. Docking, dock UI, dock autosave, and undocking

Godot user data is redirected to `.godot/baseline_user_data`, so the suite does
not read, overwrite, or delete the player's normal campaign save.

The runtime checks pass `--baseline-offline`. LLM model discovery, TTS service
discovery, and static voice pre-caching remain dormant, so core gameplay checks
do not require Ollama, Kokoro, Python, or network access.

## Expected Output

```text
[PASS] Static diff check
[PASS] Godot import and parse
[PASS] Core startup and controls
[PASS] Two-way gate and save restoration
[PASS] Docking and dock autosave
Baseline suite passed: 5 of 5 steps.
```

Durations are printed beside each step and vary by machine.

The command returns exit code `1` if any step fails. The failing step prints the
last 80 log lines. Complete failure logs remain under
`.godot/baseline_logs`.

Use `-KeepLogs` to retain logs from successful steps:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_baseline_checks.ps1 -KeepLogs
```

## Verified Result

Date: 2026-06-13

- First consecutive run: PASS, 5 of 5 steps.
- Second consecutive run: PASS, 5 of 5 steps.
- Working copy: development branch with the Checkpoint 5 changes present.
- Godot: 4.6.3 stable.
- LLM/TTS services: not required.

