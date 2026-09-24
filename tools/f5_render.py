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
        tts.infer(
            ref_file=job["ref"],
            ref_text=ref_text,
            gen_text=job["text"],
            file_wave=job["out"],
            seed=int(job.get("seed", 7)),
            speed=float(job.get("speed", 1.0)),
            nfe_step=int(job.get("nfe", 64)),
            remove_silence=True,
        )
        print("rendered", job["out"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
