# Adaptive TTS devices

The TTS server defaults to `SPACEGAME_TTS_DEVICE=auto`. No player configuration
or particular GPU model is required. `cpu` is a troubleshooting override.

CPU initializes first and remains ready. Before speech requests, the selector
checks CUDA devices and global utilization/free VRAM (at most once per two
seconds). Unknown telemetry, unsupported hardware, and CPU-only PyTorch stay on
CPU. CUDA admission requires utilization <=55%, free memory of at least 20% of
the adapter's total (minimum 1 GiB), plus another 1 GiB for synthesis, observed
across requests at least five seconds apart. These are conservative initial
heuristics, not measured guarantees of frame-rate safety or speedup.

Once selected, GPU rendering continues until utilization reaches 85%, memory
falls below the reserve, or telemetry disappears. The GPU model is released and
selection waits 30 seconds before considering GPU again. Initialization/render
failures back off for 120 seconds. A failed GPU render discards partial output
and retries the complete request on CPU. Selection/eviction occurs between
requests, not mid-sentence; idle GPU allocations remain until another request.
Multiple visible CUDA adapters are considered using their PyTorch device indices.

Synthesis is serialized to protect pipeline/model state. It runs outside the
HTTP event loop, so health checks remain responsive. `/health` reports
`device_mode`, `device`, and `device_reason` alongside existing readiness fields.

## Shipping requirements and limits

- Bundle a tested Python runtime, Kokoro and its dependencies; a player's system
  Python is not a deployment strategy. CPU support is the baseline.
- For NVIDIA acceleration, the runtime must contain a compatible CUDA-enabled
  PyTorch build and `nvidia-ml-py` (provides `pynvml` for utilization telemetry).
  Missing telemetry safely disables automatic GPU use. Do not install packages
  or drivers on players' machines at game startup.
- AMD/Intel GPUs and Apple Metal currently use CPU fallback. Supporting those
  accelerators requires separately tested backends and pressure monitoring.
- Ship model weights/config, language assets and all used voice packs in the
  runtime's configured Hugging Face cache, with their required license notices.
  The existing development server still downloads missing assets on first use;
  this change is not an offline installer or an exported-game packaging solution.
- GPU copies load from already-cached weights; switching never downloads assets.
  A CPU and GPU model coexist while GPU is active, increasing system RAM use.
- Cached audio playback is unchanged. This only accelerates synthesis. Validate
  CPU/GPU latency and game frame times together on the release hardware matrix;
  utilization alone cannot establish whether GPU synthesis is beneficial.

Validation: `python -m unittest discover -s tests/speech -p test_tts_device.py`.
Tests simulate missing/overloaded/low-memory/multiple GPUs, driver failure,
recovery cooldown, CPU override, and complete-request retry after GPU failure.
