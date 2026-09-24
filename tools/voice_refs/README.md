# Voice references for F5-TTS clones

Nova's baked lines are rendered with [F5-TTS](https://github.com/SWivid/F5-TTS), which clones a voice from a short reference clip and follows its delivery. Kokoro still renders everyone else. Kaelen stays on Kokoro for now; her reference is kept so she can switch later.

The reference clips here were rendered by Kokoro in each character's game voice (see `data/content/voice_provider_kokoro.json`), each with its exact transcript in the matching `.txt`. F5 copies the reference's delivery as well as its timbre, so `nova_urgent` is used for emotional lines and `nova_calm` for everyday ones.

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
