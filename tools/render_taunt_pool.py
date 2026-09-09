"""Render every approved taunt line to .wav for review.

Files are named  <cause>_<NN>_<lead-voice>.wav  inside a folder per cause, so a
report of "reinforcement_07 is bad" identifies both the exact line and the voice
that spoke it. index.txt in each folder, plus a master INDEX.txt, map filenames
back to their text.

Lead voices rotate through CombatManager.TAUNT_LEAD_VOICES rather than sitting
on one default, because the game picks a lead at random per line and the review
should cover that range.
"""
import io
import json
import os
import sys
import urllib.request
import wave

TTS_URL = "http://localhost:5000/tts"
DATA = "data/content/taunt_lines.json"
OUT_ROOT = os.path.join("logs", "taunt_pool_audio")
SPEED = 1.10          # CombatManager.TAUNT_SPEED
STYLE = 1.4           # CombatManager.TAUNT_STYLE
LEADS = ["am_onyx", "am_adam", "am_fenrir", "am_liam", "am_puck", "am_eric", "am_echo"]


def render(text, voice, speed=SPEED, pause=-1.0):
    body = {"text": text, "voice": voice, "speed": speed, "style_scale": STYLE}
    if pause >= 0.0:
        body["pause_seconds"] = pause
    payload = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        TTS_URL, data=payload, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=180) as resp:
        return resp.read()


def main():
    data = json.load(io.open(DATA, encoding="utf-8"))
    os.makedirs(OUT_ROOT, exist_ok=True)
    master = []
    rendered = 0
    failed = []
    # Rotate leads across the WHOLE pool, so no cause is stuck on one voice and
    # each voice is heard in several different situations.
    lead_index = 0
    for cause in sorted(data["causes"].keys()):
        lines = data["causes"][cause]["lines"]
        folder = os.path.join(OUT_ROOT, cause)
        os.makedirs(folder, exist_ok=True)
        index = []
        for n, entry in enumerate(lines, start=1):
            # A line is a plain string, or an object carrying delivery
            # overrides. Render with the values the GAME will use, otherwise the
            # audition lies about the lines that were deliberately re-timed.
            if isinstance(entry, dict):
                text = entry["text"]
                speed = float(entry.get("speed", SPEED))
                pause = float(entry.get("pause", -1.0))
            else:
                text, speed, pause = entry, SPEED, -1.0
            lead = LEADS[lead_index % len(LEADS)]
            lead_index += 1
            voice = "%s[0.7]+am_michael[0.3]" % lead
            name = "%s_%02d_%s.wav" % (cause, n, lead)
            path = os.path.join(folder, name)
            try:
                audio = render(text, voice, speed, pause)
            except Exception as exc:
                failed.append((name, str(exc)))
                print("FAILED %s: %s" % (name, exc), flush=True)
                continue
            with open(path, "wb") as f:
                f.write(audio)
            with wave.open(path) as w:
                secs = w.getnframes() / float(w.getframerate())
            tags = ""
            if isinstance(entry, dict):
                bits = []
                if entry.get("speed") is not None:
                    bits.append("speed %.2f" % speed)
                if pause >= 0.0:
                    bits.append("pause %.2f" % pause)
                tags = "  [%s]" % ", ".join(bits) if bits else ""
            row = "%-42s %5.2fs  %s%s" % (name, secs, text, tags)
            index.append(row)
            master.append(row)
            rendered += 1
            print("[%3d] %s" % (rendered, row), flush=True)
        io.open(os.path.join(folder, "index.txt"), "w", encoding="utf-8").write(
            "\n".join(index) + "\n")
    io.open(os.path.join(OUT_ROOT, "INDEX.txt"), "w", encoding="utf-8").write(
        "Taunt pool audio — speed %.2f, style %.1f, lead[0.7]+am_michael[0.3]\n"
        "Report a bad clip by its filename stem, e.g. 'reinforcement_07'.\n\n"
        % (SPEED, STYLE) + "\n".join(master) + "\n")
    print("\nrendered %d clip(s), %d failure(s) -> %s" % (rendered, len(failed), OUT_ROOT))
    if failed:
        for name, err in failed:
            print("  FAILED %s: %s" % (name, err))
        sys.exit(1)


if __name__ == "__main__":
    main()
