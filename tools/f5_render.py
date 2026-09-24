"""Render one line with F5-TTS, cloning the voice in a reference clip.

Runs inside the F5 environment (see tools/voice_refs/README.md), not the
system Python:

  D:/CodingProjects/f5-tts-env/Scripts/python.exe tools/f5_render.py \
      --ref tools/voice_refs/nova.wav --ref-text-file tools/voice_refs/nova.txt \
      --text "Damn it, Kaelen!" --out out.wav [--seed 7] [--speed 0.85] [--nfe 64]

Several lines in one call (one model load): --jobs jobs.json, a list of
{"text", "ref", "ref_text_file", "out", "seed"?, "speed"?, "nfe"?}.
"""
import argparse
import io
import json
import re
import sys

import numpy
import soundfile as sf


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref")
    ap.add_argument("--ref-text-file")
    ap.add_argument("--text")
    ap.add_argument("--out")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--speed", type=float, default=1.0)
    ap.add_argument("--nfe", type=int, default=64, help="sampling steps: F5's default is 32; 64 renders cleaner")
    ap.add_argument("--jobs")
    args = ap.parse_args()

    if args.jobs:
        jobs = json.load(io.open(args.jobs, encoding="utf-8"))
    else:
        jobs = [{"text": args.text, "ref": args.ref, "ref_text_file": args.ref_text_file,
                 "out": args.out, "seed": args.seed, "speed": args.speed, "nfe": args.nfe}]

    from f5_tts.api import F5TTS  # imported late: slow, and only here
    tts = F5TTS()
    asr = None
    for job in jobs:
        ref_text = io.open(job["ref_text_file"], encoding="utf-8").read().strip()
        speed = float(job.get("speed", 1.0))
        best = None
        # F5 fills exactly the time it is given; its own guess often cuts the
        # last word, and too much time drags the line out. Try a few lengths
        # and seeds and keep the first take whose transcript has every word,
        # the last one included (a listener's check, not a loudness guess).
        for suffix, room, seed in CANDIDATES:
            gen_text = job["text"] + suffix
            raw, rate, _ = tts.infer(
                ref_file=job["ref"],
                ref_text=ref_text,
                gen_text=gen_text,
                seed=seed,
                speed=speed,
                nfe_step=int(job.get("nfe", 64)),
                fix_duration=roomy_duration(job["ref"], ref_text, gen_text, speed, room, float(job.get("pad", PAD_SECONDS))),
                remove_silence=False,  # it clips soft endings; trim() handles spare silence
            )
            raw = numpy.asarray(raw, dtype="float32")
            wav = trim(raw, rate)
            if asr is None:
                asr = load_asr()
            heard = transcribe(asr, wav, rate)
            ok, score = complete(job["text"], heard)
            quiet_end = ends_quietly(raw, rate)
            if not quiet_end:
                ok, score = False, score - 0.25
            if best is None or score > best[0]:
                best = (score, wav, rate, room, seed, heard)
            if ok:
                break
        score, wav, rate, room, seed, heard = best
        sf.write(job["out"], wav, rate)
        print("rendered", job["out"], "(room %.2f, seed %d)%s" % (room, seed, "" if score >= 1.0 else " CHECK BY EAR: heard '%s'" % heard))
    return 0


ROOM = 1.15         # a little more time than F5 would guess, or it cuts the last word
# (text suffix, room, seed) tried in order. A trailing " ..." asks F5 for a
# pause after the line, which often lets the last word finish.
CANDIDATES = [(sfx, room, seed) for seed in (7, 11, 23) for sfx in ("", " ...", " ... ...") for room in (1.15, 1.3)]
ASR_MODEL = "openai/whisper-small"
# Names Whisper may spell any way it likes; they don't count for or against a take.
NAMES = {"kaelen", "kaylen", "kayleen", "kaelan", "caelen", "kailin", "kaylin", "nova", "shiny"}
PAD_SECONDS = 0.3   # plus a small margin (much more and F5 drags the line out to fill it)
SILENCE = 0.004     # low: soft final consonants must survive the trim
TAIL_SECONDS = 0.3
FADE_SECONDS = 0.03


def roomy_duration(ref_wav, ref_text, gen_text, speed, room=None, pad=None):
    """Total seconds (reference + new line) for F5's fix_duration."""
    ref_seconds = sf.info(ref_wav).duration
    per_byte = ref_seconds / max(1, len(ref_text.encode("utf-8")))
    room = ROOM if room is None else room
    pad = PAD_SECONDS if pad is None else pad
    return ref_seconds + per_byte * len(gen_text.encode("utf-8")) / speed * room + pad


def ends_quietly(raw, rate):
    """The raw take has fallen silent in its last 60 ms: the last word finished
    rather than being cut off at the end of F5's time."""
    return float(numpy.sqrt(numpy.mean(raw[-int(0.06 * rate):] ** 2))) < 0.012


def load_asr():
    import torch
    from transformers import pipeline
    return pipeline("automatic-speech-recognition", model=ASR_MODEL,
                    device=0 if torch.cuda.is_available() else -1)


def transcribe(asr, data, rate):
    return str(asr({"raw": data, "sampling_rate": rate})["text"]).strip()


def words(text):
    return re.findall(r"[a-z']+", text.lower().replace("kaylen", "kaelen"))


def is_name_like(word):
    """Whisper's spelling of Kaelen (Kaelin, Caelan, Kaylen...), whole, not clipped."""
    return len(word) >= 5 and word[0] in "kc" and word.endswith("n")


def complete(expected, heard):
    """(ok, score): every expected word heard in order-insensitive terms, and
    the last word present. Names are forgiven (Whisper spells them freely)."""
    all_words = words(expected)
    want = [w for w in all_words if w not in NAMES]
    heard_words = words(heard)
    got = set(w for w in heard_words if w not in NAMES)
    score = sum(1 for w in want if w in got) / len(want) if want else 1.0
    # Every name must be said too (a take once dropped a leading "Kaelen!").
    names_wanted = sum(1 for w in all_words if w in NAMES)
    names_heard = sum(1 for w in heard_words if w in NAMES or is_name_like(w))
    if names_heard < names_wanted:
        score -= 0.5
    if all_words and all_words[-1] in NAMES:
        # A line ending on a name: the whole name must be there, not "Kay...".
        last_ok = bool(heard_words) and is_name_like(heard_words[-1])
    else:
        last_ok = bool(want) and want[-1] in got
    return (score >= 1.0 and last_ok), (score if last_ok else score - 0.5)


def trim(data, rate):
    """Trim leading/trailing silence, keep a short tail, fade out gently."""
    loud = numpy.nonzero(numpy.abs(data) > SILENCE)[0]
    if len(loud) == 0:
        return data
    end = min(len(data), loud[-1] + int(TAIL_SECONDS * rate))
    data = data[max(0, loud[0] - int(0.02 * rate)):end].copy()
    fade = min(len(data), int(FADE_SECONDS * rate))
    data[len(data) - fade:] *= numpy.linspace(1.0, 0.0, fade, dtype="float32")
    return data


if __name__ == "__main__":
    sys.exit(main())
