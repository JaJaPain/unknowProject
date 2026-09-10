# Codex Project Notes

## Repository Map

- Before broad exploration, consult `PROJECT_MAP.md` or `PROJECT_MAP.json` at the repository root. They are generated indexes of the project tree and parsed symbols, intended to help agents orient quickly without repeatedly scanning the whole repo.
- Use the map as navigation aid only. Read the actual source files before editing or making claims about behavior.
- Refresh the map after major file moves or new systems with:

```powershell
python generate_repo_map.py
```

## Session Catch-Up

- Check `docs/whileYouWasSleeping.md` when resuming after another assistant or overnight work. It records recent changes that may not be obvious from the current diff.

## Push Workflow

- When the user says a push is complete, treat that as approval to continue to the next item on the active work list. Do not wait for a separate "go on" message unless the user explicitly asks to pause, stop, review, or plan.

## Godot Headless Tests

- Run Godot headless script tests sequentially, not in parallel. Parallel runs can collide on Godot's timestamped log rotation.
- Always pass a unique `--log-file` path when running headless Godot tests. Without it, Godot 4.6.3 on this machine can fail while rotating `user://logs/godot.log`, print `ERROR: Failed to open 'user://logs/godot....log'`, then crash with signal 11 before test output.
- Prefer a workspace-local absolute log path, for example:

```powershell
$logPath = Join-Path (Get-Location) ".tmp_godot_user\test_logs\mission_contract.log"
.\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/domain/run_mission_contract_tests.gd --log-file $logPath
```

- If the old crash appears, treat it as a Godot log-rotation startup issue unless test output proves otherwise.
