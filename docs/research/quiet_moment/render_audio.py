"""Render quiet-moment lines through the project's Kokoro TTS for listening.

Reading a line and hearing it are different tests -- dry delivery lives in the
timing, and N.O.V.A.'s bf_emma is British, which the author expects to sharpen
the double entendres.

Prereq:  python scripts/tts_server.py     (from the repo root)
Usage:   python docs/research/quiet_moment/render_audio.py

Voices come from data/content/voice_provider_kokoro.json so this can't drift
from what the game actually uses.
"""
import json
import os
import re
import urllib.request

SERVER = "http://127.0.0.1:5000/tts"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
VOICE_FILE = os.path.join(ROOT, "data", "content", "voice_provider_kokoro.json")
OUT_DIR = os.path.join(ROOT, ".tmp_godot_user", "quiet_moment_audio")


def voices():
    with open(VOICE_FILE, encoding="utf-8") as f:
        data = json.load(f)
    table = data.get("voices", data)
    while isinstance(table, dict) and "voice.nova.v1" not in table:
        nxt = next((v for v in table.values() if isinstance(v, dict)), None)
        if nxt is None:
            break
        table = nxt
    return (table["voice.nova.v1"]["provider_voice"],
            table["voice.kaelen.v1"]["provider_voice"])


def synth(label, text, voice, speed=1.0):
    body = json.dumps({"text": text, "voice": voice, "speed": speed,
                       "style_scale": 1.0, "style_from": ""}).encode("utf-8")
    req = urllib.request.Request(SERVER, data=body,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            wav = resp.read()
    except Exception as e:
        print(f"  ! {label}: {e}")
        return False
    path = os.path.join(OUT_DIR, f"{label}.wav")
    with open(path, "wb") as f:
        f.write(wav)
    print(f"  ok {label}.wav  ({len(wav)//1024} KB)")
    return True


def slug(s, n=44):
    return re.sub(r"[^a-z0-9]+", "_", s.lower())[:n].strip("_")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    nova_voice, kaelen_voice = voices()
    print(f"N.O.V.A. -> {nova_voice}\nKaelen  -> {kaelen_voice}\nout: {OUT_DIR}\n")

    import approved

    print("N.O.V.A. — approved, post-combat with damage")
    for i, line in enumerate(approved.NOVA_POST_COMBAT_DAMAGED, 1):
        synth(f"nova_approved_{i:02d}_{slug(line)}", line, nova_voice)

    print("\nN.O.V.A. — your own reference lines")
    for i, line in enumerate(approved.NOVA_AUTHOR_CANON, 1):
        synth(f"nova_canon_{i:02d}", line, nova_voice)

    print("\nN.O.V.A. — rejected, for contrast")
    for i, (who, line, _why) in enumerate(
            [r for r in approved.REJECTED if r[0] == "nova"], 1):
        synth(f"nova_rejected_{i:02d}_{slug(line)}", line, nova_voice)

    print("\nKaelen — passed the bar")
    for i, line in enumerate(approved.KAELEN_SAFE_LOW_PAY, 1):
        synth(f"kaelen_ok_{i:02d}_{slug(line)}", line, kaelen_voice)

    print("\nKaelen — your own reference lines")
    for i, line in enumerate(approved.KAELEN_AUTHOR_CANON, 1):
        synth(f"kaelen_canon_{i:02d}", line, kaelen_voice)

    print("\nKaelen — rejected, for contrast")
    for i, (who, line, _why) in enumerate(
            [r for r in approved.REJECTED if r[0] == "kaelen"], 1):
        synth(f"kaelen_rejected_{i:02d}_{slug(line)}", line, kaelen_voice)


if __name__ == "__main__":
    main()
