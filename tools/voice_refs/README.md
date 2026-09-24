# N.O.V.A.'s F5-TTS clone

N.O.V.A.'s baked lines are rendered with [F5-TTS](https://github.com/SWivid/F5-TTS), cloned from a reference clip. Kokoro renders everyone else, Kaelen included.

**This reproduces the approved cast bake exactly** (the old machine's `C:\CodingProjects\TestTTS`: `bake_cast.py`, `run_f5_clone.py`, `fix_tails.py`, recovered from Abe's `Nova_Voice_Fixes_And_Clone_Files.zip`):

- Reference: `nova_original.wav` + `.txt`, the original file. It is pure Kokoro `bf_emma` (not her in-game blend) saying "Navigation checks complete. Micro-warp drive primed and aligned for system transit."
- F5 defaults: `cfg_strength` 2.0, speed 1.0, F5's own timing.
- Then the tail fix: an 18 ms fade plus 140 ms of silence, only on clips that end within 80 ms of their last sound.

Don't tune the render itself. On 2026-09-24 extra time, retries, trimmed references, remade references and slower speeds were all tried, and Abe heard every one as worse than the original method.

## Setup (once per machine)

F5 runs in its own environment, so the system Python (Kokoro) is left alone:

```
py -3.10 -m venv D:/CodingProjects/f5-tts-env
D:/CodingProjects/f5-tts-env/Scripts/python.exe -m pip install torch==2.4.1 torchaudio==2.4.1 --index-url https://download.pytorch.org/whl/cu124
D:/CodingProjects/f5-tts-env/Scripts/python.exe -m pip install f5-tts
```

The model weights (SWivid/F5-TTS, about 1.3 GB) download from Hugging Face on first use. If the environment lives elsewhere, change `f5_python` in `clones.json`.

## Use

`tools/bake_undercurrent_audio.py` routes any voice listed under `voices` in `clones.json` through `tools/f5_render.py`.
