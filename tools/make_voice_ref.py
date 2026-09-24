"""Make a clean F5-TTS reference clip with Kokoro, in a character's game voice.

F5 copies the reference's delivery as well as its timbre, so the reference
should be steady and clean: no shouting, no clipped starts, silence trimmed
from both ends with a short tail (F5 prefers one), level normalised.

  python tools/make_voice_ref.py voice.nova.v1 nova "Captain, listen to me. ..." [--speed 0.95]

Writes tools/voice_refs/<name>.wav and <name>.txt (the exact transcript F5
needs). Needs the local Kokoro server, like the bake tools.
"""
import io
import json
import sys
import urllib.request

import numpy
import soundfile as sf

TTS_URL = "http://localhost:5000/tts"
VOICES = "data/content/voice_provider_kokoro.json"
SILENCE = 0.003       # amplitude treated as silence when trimming (low: soft final consonants must survive)
TAIL_SECONDS = 0.35   # quiet tail left after the last word
PEAK = 0.89           # about -1 dBFS


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    speed = float(sys.argv[sys.argv.index("--speed") + 1]) if "--speed" in sys.argv else 1.0
    if "--speed" in sys.argv:
        args.remove(sys.argv[sys.argv.index("--speed") + 1])
    profile, name, text = args[0], args[1], args[2]
    voice = json.load(io.open(VOICES, encoding="utf-8"))["mappings"][profile]
    body = {"text": text, "voice": voice["provider_voice"], "speed": speed}
    req = urllib.request.Request(TTS_URL, data=json.dumps(body).encode("utf-8"),
                                 headers={"Content-Type": "application/json"})
    data, rate = sf.read(io.BytesIO(urllib.request.urlopen(req, timeout=180).read()), dtype="float32")
    if data.ndim > 1:
        data = data.mean(axis=1)
    loud = numpy.nonzero(numpy.abs(data) > SILENCE)[0]
    data = data[max(0, loud[0] - int(0.02 * rate)):loud[-1] + 1]
    data = numpy.concatenate([data, numpy.zeros(int(TAIL_SECONDS * rate), dtype="float32")])
    data = data * (PEAK / max(1e-6, float(numpy.abs(data).max())))
    sf.write("tools/voice_refs/%s.wav" % name, data, rate)
    io.open("tools/voice_refs/%s.txt" % name, "w", encoding="utf-8", newline="\n").write(text + "\n")
    print("%s: %.1fs at %d Hz" % (name, len(data) / rate, rate))


if __name__ == "__main__":
    main()
