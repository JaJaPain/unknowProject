"""Render banked enemy taunts to .wav so they can be auditioned without playing.

Uses the SAME voice blend, speed, and style scale CombatManager uses at runtime
(TAUNT_LEAD_VOICES 70/30 with am_michael, speed 1.18, style 1.4), so what you
hear is what the fight would play. Files are named by cause, in play order, so
the reason each line exists is obvious while listening.
"""
import glob
import io
import json
import os
import sys
import urllib.error
import urllib.request

TTS_URL = "http://localhost:5000/tts"
SPEED = 1.18          # CombatManager.TAUNT_SPEED
STYLE = 1.4           # CombatManager.TAUNT_STYLE
LEAD_VOICES = [       # CombatManager.TAUNT_LEAD_VOICES
    "am_onyx", "am_adam", "am_fenrir", "am_liam",
    "bm_george", "am_puck", "am_eric", "am_echo",
]

# Order the causes so the contrast is audible: the two "you started it" cases
# next to each other, then the four "they started it" cases.
CAUSE_ORDER = [
    "contract_hit",
    "unprovoked",
    "preemptive_strike",
    "pirate_predation",
    "code_enforcement",
    "reputation_grudge",
    "reinforcement",
    "opportunist",
]

SITUATION = {
    "contract_hit": "you shot them to fulfil a kill contract",
    "unprovoked": "you shot a neutral for no reason",
    "preemptive_strike": "you shot someone already coming for you",
    "pirate_predation": "pirates jumped you for the cargo",
    "code_enforcement": "a patrol collecting your unpaid mining fine",
    "reputation_grudge": "a faction acting on your bad reputation",
    "reinforcement": "backup called in after an earlier fight",
    "opportunist": "they started it and will not say why",
}


def find_bank():
    root = os.path.expanduser("~/AppData/Roaming/Godot/app_userdata")
    hits = glob.glob(root + "/**/cached_taunts_v2.json", recursive=True)
    if not hits:
        sys.exit("No cached_taunts_v2.json found - run the game or the growth probe first.")
    return hits[0]


def render(text, voice, out_path):
    payload = json.dumps({
        "text": text, "voice": voice, "speed": SPEED, "style_scale": STYLE,
    }).encode("utf-8")
    req = urllib.request.Request(
        TTS_URL, data=payload, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        audio = resp.read()
    with open(out_path, "wb") as f:
        f.write(audio)
    return len(audio)


def main():
    per_cause = int(sys.argv[1]) if len(sys.argv) > 1 else 2
    out_dir = os.path.join("logs", "taunt_audition")
    os.makedirs(out_dir, exist_ok=True)

    bank_path = find_bank()
    bank = json.load(io.open(bank_path, encoding="utf-8"))
    causes = bank.get("causes", {})
    print("Bank: %s" % bank_path)

    manifest = []
    index = 0
    for cause in CAUSE_ORDER:
        record = causes.get(cause, {})
        lines = [str(x) for x in record.get("lines", []) if str(x).strip()]
        if not lines:
            print("  %-18s no lines banked, skipping" % cause)
            continue
        # Prefer MODEL-generated lines over the authored floor: the floor is
        # mine and already known-good, so auditioning it proves nothing about
        # what the game will actually say. The floor is the first 4 entries.
        generated = lines[4:] or lines
        for offset in range(min(per_cause, len(generated))):
            index += 1
            text = generated[offset]
            voice = "%s[0.7]+am_michael[0.3]" % LEAD_VOICES[index % len(LEAD_VOICES)]
            name = "%02d_%s_%d.wav" % (index, cause, offset + 1)
            path = os.path.join(out_dir, name)
            try:
                size = render(text, voice, path)
            except (urllib.error.URLError, TimeoutError) as exc:
                print("  FAILED %s: %s" % (name, exc))
                continue
            manifest.append({
                "file": name,
                "cause": cause,
                "situation": SITUATION.get(cause, ""),
                "line": text,
                "voice": voice,
            })
            print("  %-28s %-18s %s" % (name, cause, text))

    with io.open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump({
            "speed": SPEED, "style_scale": STYLE,
            "note": "Same voice blend/speed/style CombatManager uses at runtime.",
            "clips": manifest,
        }, f, indent="\t")

    # A plain-text running order, so you can read along while listening.
    with io.open(os.path.join(out_dir, "running_order.txt"), "w", encoding="utf-8") as f:
        for clip in manifest:
            f.write("%s\n    WHY: %s\n    LINE: %s\n\n" % (
                clip["file"], clip["situation"], clip["line"]
            ))
    print("\n%d clip(s) in %s" % (len(manifest), out_dir))


if __name__ == "__main__":
    main()
