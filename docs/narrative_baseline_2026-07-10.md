# Narrative Baseline Capture - 2026-07-10

This document records the pre-V2 narrative telemetry baseline for
`docs/plan_living_narrative_shining_star.md`.

## Capture Status

- Baseline runner: `res://tests/tools/run_narrative_baseline_capture.gd`
- Output artifact path: `res://logs/narrative_baseline_capture.json`
- Scripted sample sizes:
  - 30 agent offers
  - 12 lounge openers with one reply each
  - 30 N.O.V.A. eligible event fixtures
  - 12 Kaelen turn-in scenarios
- Worst-example buckets retained in the artifact:
  - disconnected cause
  - assumed knowledge
  - irrelevant question
  - persona drift
  - repeated premise
  - repeated phrasing
  - generic turn-in
  - visible wait

## Current Fallback Summary

No current `res://logs/fallback_summary.txt` file was present in the workspace at
baseline-document creation time. That means there was no persisted runtime
fallback summary to copy forward for this checkpoint.

To refresh the baseline artifact and fallback summary on a live model setup:

```powershell
$logPath = Join-Path (Get-Location) ".tmp_godot_user\test_logs\narrative_baseline_capture.log"
.\Godot\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/tools/run_narrative_baseline_capture.gd --log-file $logPath
```

The runner writes the structured batch to
`res://logs/narrative_baseline_capture.json`. Runtime fallback summaries, when
produced by `GenerationDiagnostics`, write to `res://logs/fallback_summary.txt`
with JSON at `res://logs/fallback_summary.json`.

## Model And VRAM Profile

Verified local GPU profile from `nvidia-smi`:

- GPU: NVIDIA GeForce RTX 5060 Ti
- Total VRAM: 16,311 MiB
- VRAM used during this check: 2,327 MiB
- Driver: 610.62

Configured local model policy from `scripts/ai/LocalModelGateway.gd`:

- Ollama endpoint: `http://127.0.0.1:11434/api/generate`
- Default small dialogue model: `qwen3:4b`
- Default large story model: `qwen3:8b`
- Small dialogue context: `8192`
- Large story context: `16384`
- Small model keep-alive: `30m`
- Large model keep-alive: `0`
- Thinking disabled globally through `think: false`

Installed Ollama tags were not available from this shell because `ollama` was
not on PATH.
