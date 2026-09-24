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
    for job in jobs:
        ref_text = io.open(job["ref_text_file"], encoding="utf-8").read().strip()
        speed = float(job.get("speed", 1.0))
        wav, rate, _ = tts.infer(
            ref_file=job["ref"],
            ref_text=ref_text,
            gen_text=job["text"],
            seed=int(job.get("seed", 7)),
            speed=speed,
            nfe_step=int(job.get("nfe", 64)),
            # F5's own length guess can cut the last word; give it room and
            # trim the spare silence here instead of with remove_silence,
            # which also clips soft endings.
            fix_duration=roomy_duration(job["ref"], ref_text, job["text"], speed),
            remove_silence=False,
        )
        sf.write(job["out"], trim(numpy.asarray(wav, dtype="float32"), rate), rate)
        print("rendered", job["out"])
    return 0


ROOM = 1.2          # generated speech gets 20% more time than F5 would guess
PAD_SECONDS = 0.4   # plus a little, so a final word always lands
SILENCE = 0.012
TAIL_SECONDS = 0.25
FADE_SECONDS = 0.03


def roomy_duration(ref_wav, ref_text, gen_text, speed):
    """Total seconds (reference + new line) for F5's fix_duration."""
    ref_seconds = sf.info(ref_wav).duration
    per_byte = ref_seconds / max(1, len(ref_text.encode("utf-8")))
    return ref_seconds + per_byte * len(gen_text.encode("utf-8")) / speed * ROOM + PAD_SECONDS


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
