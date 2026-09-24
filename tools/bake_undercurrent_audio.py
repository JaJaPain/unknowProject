"""Bake the undercurrent lines (data/content/undercurrent_lines.json) to OGG.

Only lines marked approved_by_abe: true are rendered. Each uses its speaker's
voice blend from data/content/voice_provider_kokoro.json, so the baked line is
the same voice the game uses at runtime. Needs the local Kokoro server
(http://localhost:5000/tts), like tools/bake_taunt_audio.py.

  python tools/bake_undercurrent_audio.py [--force]
"""
import io
import json
import os
import sys
import urllib.request

import soundfile as sf

TTS_URL = "http://localhost:5000/tts"
LINES = "data/content/undercurrent_lines.json"
VOICES = "data/content/voice_provider_kokoro.json"


def res_to_path(res_path):
    return res_path.replace("res://", "", 1)


def main():
    force = "--force" in sys.argv
    lines = json.load(io.open(LINES, encoding="utf-8"))["lines"]
    mappings = json.load(io.open(VOICES, encoding="utf-8"))["mappings"]
    made = skipped = refused = 0
    for line in lines:
        if not line.get("approved_by_abe", False):
            print("not approved, skipping:", line["id"])
            refused += 1
            continue
        out = res_to_path(line["audio"])
        if os.path.exists(out) and not force:
            skipped += 1
            continue
        voice = mappings[line["voice_profile"]]
        body = {"text": line["text"], "voice": voice["provider_voice"], "speed": float(voice.get("speed", 1.0))}
        req = urllib.request.Request(TTS_URL, data=json.dumps(body).encode("utf-8"),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=180) as resp:
            wav = resp.read()
        data, rate = sf.read(io.BytesIO(wav), dtype="float32")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        sf.write(out, data, rate, format="OGG", subtype="VORBIS")
        print("baked", line["id"], "->", out, "(%.1fs)" % (len(data) / rate))
        made += 1
    print("made %d, skipped %d, not approved %d" % (made, skipped, refused))


if __name__ == "__main__":
    main()
