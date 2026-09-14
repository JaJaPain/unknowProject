# CLAUDE.md — Project Rules

## Output Discipline

When writing large documents, research summaries, or plan files, **save incrementally after each logical section**. Never accumulate a full document in a single write — break it into chunks and write/edit the file after each section completes. This prevents hitting the output limit and losing work.

If a response is likely to be long (multi-section plans, changelogs, research findings), explicitly structure the work as: write section 1 → save → write section 2 → save → etc.

## Project Index

Use `PROJECT_MAP.md` as the first-pass navigation index for this codebase. It is a complete file tree listing every file path, class name, and function signature in the project. Before grepping or globbing for a file or function, check PROJECT_MAP.md first — it often gives you the exact path and line context you need in a single read. Use offset/limit to read specific sections since the file is large (~260KB):

- The file is organized as a nested directory tree with 📂 folders and 📄 files
- Each `.gd` script file lists its class name and all function signatures
- Use Grep on PROJECT_MAP.md with a class or function name to jump straight to the right section, then read surrounding lines for context
- Still use Grep/Glob on actual source files when you need line numbers, implementation details, or content not captured in signatures

## Project Overview

- **Engine:** Godot 4.6 (Forward Plus renderer), GDScript
- **Platform:** Windows 11
- **Genre:** Space trading/combat game with procedural generation

## Godot Headless Tests

- Run headless Godot script tests one at a time. Do not launch multiple test commands in parallel; they can collide on timestamped Godot log files.
- Always include a unique `--log-file` argument. On this machine, Godot 4.6.3 can crash during startup log rotation with:

```text
ERROR: Failed to open 'user://logs/godot....log'.
CrashHandlerException: Program crashed with signal 11
```

- Use a workspace-local absolute log path, for example:

```powershell
$logPath = Join-Path (Get-Location) ".tmp_godot_user\test_logs\mission_contract.log"
.\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/domain/run_mission_contract_tests.gd --log-file $logPath
```

- If this crash happens before any GDScript test output, assume it is the Godot logging startup issue, not necessarily a test failure.
