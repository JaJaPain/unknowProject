# Phase 0 Defect And Performance Baseline

Date: 2026-06-13

Commit before measurement: `bf676b5`

## Test Machine

- OS: Windows 10 build 26200, 64-bit
- CPU: Intel Core Ultra 7 265F, 20 logical processors
- RAM: 31.7 GiB
- GPU: NVIDIA GeForce RTX 5060 Ti
- VRAM: 16,311 MiB
- NVIDIA driver: 591.86
- Display: 1920 x 1080
- Godot: 4.6.3 stable
- Renderer: Vulkan Forward+

Limitation:

- This machine establishes the development baseline but cannot certify the
  intended 8 GB VRAM minimum. An 8 GB test remains required before release.

## Method

- Launched the game outside headless mode with `--performance-baseline`.
- Used an isolated Godot user-data directory and disabled startup save loading.
- Waited for the normal LLM/TTS loading screen to finish.
- Allowed each scene two seconds to settle.
- Sampled each scene for three seconds using Godot's `Performance` monitors.
- FPS is capped near 60 by the current display/game configuration.
- Godot static memory is debug-build managed memory, not the complete Windows
  process working set.
- Render and texture memory are Godot renderer allocations, not total GPU use
  by Ollama, TTS, the editor, or other applications.

Godot monitor reference:

- https://docs.godotengine.org/en/stable/classes/class_performance.html
- https://docs.godotengine.org/en/stable/classes/class_os.html

## Startup

| Measurement | Result |
| --- | ---: |
| First system scene ready | 2.53 s |
| Playable after LLM/TTS loading | 24.14 s |
| LLM quest request | 15.00 s timeout, procedural fallback used |
| TTS uncached first response | 1.50 s |
| TTS cached playback | Immediate cache path; exact sub-frame time not recorded |

The 24-second playable time is not primarily scene loading. The largest delay
was the current 15-second LLM timeout before the fallback contract was used.

## Representative Gameplay

| Scene | Average FPS | Minimum FPS | Godot RAM | Render memory | Texture memory | Draw calls | Rendered objects |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Main station | 57.1 | 55 | 92.0 MiB | 367.7 MiB | 237.3 MiB | 192 | 1,208 |
| Asteroid field | 60.0 | 60 | 92.1 MiB | 367.7 MiB | 237.3 MiB | 221 | 1,263 |
| Combat | 59.7 | 59 | 93.5 MiB | 367.8 MiB | 237.3 MiB | 223 | 1,447 |

Additional context:

- The open Godot editor process used approximately 506 MiB of Windows working
  set during inspection. This is editor overhead, not an exported game result.
- The failed external monitor did not produce a trustworthy exported-game
  process working-set measurement. Record that from an export later.
- Gate presentation is configured for 3.2 seconds entry plus 0.9 seconds exit.
  The covered scene swap passed the two-way travel regression, but a separate
  exported-build transition timing is still desirable.

## Storage

| Item | Size |
| --- | ---: |
| Git-tracked project content | 79.98 MiB |
| Current campaign save | 12.07 KiB |
| Curated portrait PNG files | 15.17 MiB |
| Godot imported cache (`.godot`) | 342.3 MiB |
| Ignored ship-builder working folder (`Ships`) | 265.5 MiB |
| Bundled Godot editor binaries | 164.6 MiB |

The current tracked content is a better approximation of game content than the
full development workspace. A final installed size requires an export build.
Blender, Ollama models, TTS model files, and procedural ship-builder working
files must not be silently counted as ordinary game content unless the release
installer actually ships them.

## VRAM Budget Finding

The rendered game currently reports about 368 MiB of renderer memory at 1080p.
That is comfortably small by itself.

A 12B model quantized to roughly 7-8 GB is not automatically safe on an 8 GB
card alongside the game. Model weights are not the entire runtime cost:
context/KV cache, compute buffers, the display compositor, and the game's render
allocations also require VRAM. The architecture should therefore support at
least one of:

- partial CPU/RAM offload;
- a smaller story/vision model for 8 GB cards;
- unloading the large model before returning to rendered gameplay;
- running generation as a user-selected background quality tier.

Do not advertise an 8 GB minimum based only on the model's quantized file size.

## Known Defects And Risks

| Severity | Item | Baseline result |
| --- | --- | --- |
| Medium | LLM timeout delays first playable state | 15-second timeout produced a 24.14-second startup before fallback. |
| Medium | 8 GB combined model/game budget is unverified | Current GPU has 16 GB; 12B 4-bit runtime overhead may exceed an 8 GB card. |
| Low | Headless shutdown reports leaked objects/resources | Reproducible when background LLM/TTS work is active; gameplay assertions pass first. |
| Low | Station area misses the 60 FPS cap | Averaged 57.1 FPS with a 55 FPS minimum on this machine. |
| Low | No exported-build process RAM or install size yet | Debug monitors and tracked content are recorded; export measurement remains. |
| Informational | Save system is one internal autosave | No player-facing save slots or manual save/load menu currently exist. |

## Checkpoint Result

Development baseline: COMPLETE.

Release-target validation remains open for:

- a representative 8 GB GPU;
- exported-build Windows working set;
- exported installation size;
- large-model scheduling/offload behavior;
- exact cached-TTS latency and exported gate transition timing.

