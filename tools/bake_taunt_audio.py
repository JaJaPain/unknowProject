"""Pre-render every taunt line to OGG so combat never waits on TTS.

data/content/taunt_lines.json stays the SOURCE OF TRUTH. This is a derived
build artifact: nothing here is hand-edited, and swapping in a more expressive
TTS model later means deleting the output and re-running this one command.

Every line is baked once per lead voice, because the game picks a lead at
random and pre-rendering must not quietly remove that variety.

  python tools/bake_taunt_audio.py [--force]

Writes assets/audio/taunts/*.ogg plus manifest.json mapping "voice|text" to a
filename, so the runtime needs no hashing scheme shared across two languages.
"""
import hashlib
import io
import json
import os
import sys
import urllib.request

import soundfile as sf

TTS_URL = "http://localhost:5000/tts"
DATA = "data/content/taunt_lines.json"
OUT = os.path.join("assets", "audio", "taunts")
SPEED = 1.10
STYLE = 1.4
LEADS = ["am_onyx", "am_adam", "am_fenrir", "am_liam", "am_puck", "am_eric", "am_echo"]


def render_wav(text, voice, speed, pause):
    body = {"text": text, "voice": voice, "speed": speed, "style_scale": STYLE}
    if pause >= 0.0:
        body["pause_seconds"] = pause
    req = urllib.request.Request(
        TTS_URL, data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as resp:
        return resp.read()


def to_ogg(wav_bytes, path):
    data, rate = sf.read(io.BytesIO(wav_bytes), dtype="float32")
    sf.write(path, data, rate, format="OGG", subtype="VORBIS")


def main():
    force = "--force" in sys.argv
    doc = json.load(io.open(DATA, encoding="utf-8"))
    os.makedirs(OUT, exist_ok=True)
    manifest = {}
    made = skipped = 0
    for cause in sorted(doc["causes"]):
        for entry in doc["causes"][cause]["lines"]:
            if isinstance(entry, dict):
                text = entry["text"]
                speed = float(entry.get("speed", SPEED))
                pause = float(entry.get("pause", -1.0))
            else:
                text, speed, pause = entry, SPEED, -1.0
            for lead in LEADS:
                voice = "%s[0.7]+am_michael[0.3]" % lead
                # Key on the DELIVERY, matching TTSInterface.baked_stream_for.
                # A bare voice|text key is coarser than the filename hash below,
                # so a re-timed line would be served its old audio.
                key = "%s|%s|%.2f|%.2f" % (voice, text, speed, pause)
                # Name from a hash of the exact delivery, so changing a line's
                # text, speed or pause produces a different file rather than
                # silently reusing a stale one.
                stamp = "%s|%s|%.2f|%.2f" % (voice, text, speed, pause)
                name = hashlib.sha1(stamp.encode("utf-8")).hexdigest()[:20] + ".ogg"
                manifest[key] = name
                path = os.path.join(OUT, name)
                if os.path.exists(path) and not force:
                    skipped += 1
                    continue
                to_ogg(render_wav(text, voice, speed, pause), path)
                made += 1
                if made % 25 == 0:
                    print("  baked %d..." % made, flush=True)
    io.open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8").write(
        json.dumps({"speed_default": SPEED, "style": STYLE, "clips": manifest},
                   indent="\t") + "\n")
    total = sum(os.path.getsize(os.path.join(OUT, f))
                for f in os.listdir(OUT) if f.endswith(".ogg"))
    print("baked %d, skipped %d, %d entries, %.1f MB"
          % (made, skipped, len(manifest), total / 1048576.0))


if __name__ == "__main__":
    main()
