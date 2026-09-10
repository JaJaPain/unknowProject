"""
Style-half A/B test for the local Kokoro TTS server (EXPERIMENT).

Generates the same line several ways so you can listen back-to-back and judge
whether steering Kokoro's "style half" (the second 128 dims of the voice pack)
is worth pursuing for emotion — before we invest in CUDA + the kokoro_hack PSO.

Prereq: the TTS server (scripts/tts_server.py) must be running on :5000.
  python scripts/tts_server.py        # in one terminal
  python scripts/tts_style_test.py    # in another

Output WAVs land in .tmp_godot_user/style_test/ (gitignored). Play them in order.
"""
import json
import os
import urllib.request

SERVER = "http://127.0.0.1:5000/tts"
OUT_DIR = os.path.join(".tmp_godot_user", "style_test")

# Enemy taunt voice (faction blend) + an angry-ish line, and a Kaelen line.
ENEMY_VOICE = "am_michael[0.8]+am_onyx[0.2]"
KAELEN_VOICE = "af_bella"

ENEMY_LINE = "Hold still and die quiet, you scrap-rat."
KAELEN_LINE = "Shiny, don't get sentimental. Just get paid."

# (label, text, voice, style_scale, style_from)
CASES = [
    ("enemy_1.0_baseline", ENEMY_LINE, ENEMY_VOICE, 1.0, ""),
    ("enemy_0.6_flat",     ENEMY_LINE, ENEMY_VOICE, 0.6, ""),
    ("enemy_1.4_exag",     ENEMY_LINE, ENEMY_VOICE, 1.4, ""),
    ("enemy_1.8_exag",     ENEMY_LINE, ENEMY_VOICE, 1.8, ""),
    ("enemy_stylefrom_onyx",  ENEMY_LINE, ENEMY_VOICE, 1.0, "am_onyx"),
    ("enemy_stylefrom_adam14", ENEMY_LINE, ENEMY_VOICE, 1.4, "am_adam"),
    ("kaelen_1.0_baseline", KAELEN_LINE, KAELEN_VOICE, 1.0, ""),
    ("kaelen_1.3_exag",     KAELEN_LINE, KAELEN_VOICE, 1.3, ""),
]


def synth(label, text, voice, style_scale, style_from):
    body = json.dumps({
        "text": text, "voice": voice, "speed": 1.0,
        "style_scale": style_scale, "style_from": style_from,
    }).encode("utf-8")
    req = urllib.request.Request(SERVER, data=body,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            wav = resp.read()
    except Exception as e:
        print(f"  ! {label}: request failed — {e}")
        return
    path = os.path.join(OUT_DIR, f"{label}.wav")
    with open(path, "wb") as f:
        f.write(wav)
    print(f"  ok {label}  ({len(wav)} bytes) -> {path}")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print(f"Writing style-test WAVs to {OUT_DIR}\n")
    for case in CASES:
        synth(*case)
    print("\nDone. Listen in order: baseline -> flat -> exag -> style-transfer.")


if __name__ == "__main__":
    main()
