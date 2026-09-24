"""Bake the undercurrent lines (data/content/undercurrent_lines.json) to OGG.

Only lines marked approved_by_abe: true are rendered. Each uses its speaker's
voice blend from data/content/voice_provider_kokoro.json, so the baked line is
the same voice the game uses at runtime. A line with "parts" is an exchange
between speakers: each part in its own voice, joined into one clip. Needs the local Kokoro server
(http://localhost:5000/tts), like tools/bake_taunt_audio.py.

  python tools/bake_undercurrent_audio.py [--force] [--preview]
"""
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request

import numpy
import soundfile as sf

TTS_URL = "http://localhost:5000/tts"
LINES = "data/content/undercurrent_lines.json"
VOICES = "data/content/voice_provider_kokoro.json"


PART_GAP_SECONDS = 0.35
PREVIEW_DIR = ".tmp_godot_user/undercurrent_previews"


def render(text, voice):
    body = {"text": text, "voice": voice["provider_voice"], "speed": float(voice.get("speed", 1.0))}
    req = urllib.request.Request(TTS_URL, data=json.dumps(body).encode("utf-8"),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as resp:
        wav = resp.read()
    return sf.read(io.BytesIO(wav), dtype="float32")


CLONES = "tools/voice_refs/clones.json"


def spoken(text, clones):
    """The text as F5 should say it (clones.json respellings, whole words)."""
    for word, say in clones.get("respell", {}).items():
        text = re.sub(r"\b%s\b" % re.escape(word), say, text)
    return text


def render_part(part, line, mappings, clones):
    """Kokoro, or F5-TTS for voices cloned in tools/voice_refs/clones.json."""
    clone = clones.get("voices", {}).get(part["voice_profile"])
    if not clone:
        return render(part["text"], mappings[part["voice_profile"]])
    ref = clones["refs"][part.get("clone_ref", line.get("clone_ref", clone["ref"]))]
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "part.wav")
        subprocess.run([clones["f5_python"], "tools/f5_render.py", "--ref", ref["wav"], "--ref-text-file", ref["text"],
                        "--text", spoken(part["text"], clones), "--out", out,
                        "--speed", str(clone.get("speed", 1.0))], check=True)
        return sf.read(out, dtype="float32")


def res_to_path(res_path):
    return res_path.replace("res://", "", 1)


def main():
    force = "--force" in sys.argv
    # --preview renders EVERY line (drafts too) into a git-ignored scratch
    # folder so Abe can listen before approving. Nothing lands in the game.
    preview = "--preview" in sys.argv
    lines = json.load(io.open(LINES, encoding="utf-8"))["lines"]
    mappings = json.load(io.open(VOICES, encoding="utf-8"))["mappings"]
    clones = json.load(io.open(CLONES, encoding="utf-8")) if os.path.exists(CLONES) else {"voices": {}}
    made = skipped = refused = 0
    for line in lines:
        if not line.get("approved_by_abe", False) and not preview:
            print("not approved, skipping:", line["id"])
            refused += 1
            continue
        out = res_to_path(line["audio"]) if not preview else os.path.join(PREVIEW_DIR, line["id"] + ".ogg")
        if os.path.exists(out) and not force:
            skipped += 1
            continue
        # An exchange (parts) is rendered part by part, each in its own
        # voice, and joined into one clip with a short gap.
        parts = line.get("parts") or [{"voice_profile": line["voice_profile"], "text": line["text"]}]
        chunks = []
        rate = None
        for part in parts:
            chunk, part_rate = render_part(part, line, mappings, clones)
            if rate is not None and part_rate != rate:
                raise SystemExit("%s: parts render at different sample rates (%d vs %d)" % (line["id"], rate, part_rate))
            rate = part_rate
            if chunks:
                chunks.append(numpy.zeros((int(rate * PART_GAP_SECONDS),) + chunk.shape[1:], dtype="float32"))
            chunks.append(chunk)
        data = numpy.concatenate(chunks)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        sf.write(out, data, rate, format="OGG", subtype="VORBIS")
        print("baked", line["id"], "->", out, "(%.1fs)" % (len(data) / rate))
        made += 1
    print("made %d, skipped %d, not approved %d" % (made, skipped, refused))


if __name__ == "__main__":
    main()
