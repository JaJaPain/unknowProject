"""Render lines with F5-TTS, cloning N.O.V.A. exactly as the approved cast bake did.

This reproduces the original pipeline from C:/CodingProjects/TestTTS on the
old machine (bake_cast.py, run_f5_clone.py, fix_tails.py), which made the
N.O.V.A. Abe approved:
  - reference: pure Kokoro bf_emma saying "Navigation checks complete. ..."
    (tools/voice_refs/nova_original.wav + .txt, the file itself, not a remake)
  - F5 defaults: cfg_strength 2.0, speed 1.0, standard steps, F5's own timing
  - then fix_tails: an 18 ms fade plus 140 ms of silence, ONLY on clips that
    end within 80 ms of their last sound (F5 leaves almost no tail).

Do not "improve" the render itself: extra time, retries, trimming and
re-referencing were all tried on 2026-09-24 and Abe heard every one as worse.

Runs inside the F5 environment (see tools/voice_refs/README.md):

  D:/CodingProjects/f5-tts-env/Scripts/python.exe tools/f5_render.py \
      --ref tools/voice_refs/nova_original.wav --ref-text-file tools/voice_refs/nova_original.txt \
      --text "Damn it, Kaelen!" --out out.wav [--speed 1.0] [--seed N]

Several lines in one call (one model load): --jobs jobs.json, a list of
{"text", "ref", "ref_text_file", "out", "speed"?, "seed"?}.
"""
import argparse
import io
import json
import sys

import numpy as np
import soundfile as sf

# fix_tails.py, unchanged in substance.
FADE_MS = 18.0             # gentle taper so the waveform never stops mid-amplitude
PAD_MS = 140.0             # breathing room after the last sound
NEEDS_FIX_BELOW_MS = 80.0  # only clips that actually end short are touched


def trailing_ms(mono, sr):
    peak = float(np.abs(mono).max())
    if peak <= 0:
        return None
    idx = np.where(np.abs(mono) > peak * 0.02)[0]
    return None if len(idx) == 0 else (len(mono) - idx[-1]) / sr * 1000.0


def fix_tail(data, sr):
    mono = data if data.ndim == 1 else data.mean(1)
    t = trailing_ms(mono, sr)
    if t is None or t >= NEEDS_FIX_BELOW_MS:
        return data
    out = data.astype(np.float32).copy()
    fade_n = int(sr * FADE_MS / 1000.0)
    if fade_n > 0 and len(out) > fade_n:
        ramp = np.linspace(1.0, 0.0, fade_n, dtype=np.float32)
        out[-fade_n:] *= ramp if out.ndim == 1 else ramp[:, None]
    pad = np.zeros((int(sr * PAD_MS / 1000.0),) + out.shape[1:], dtype=np.float32)
    return np.concatenate([out, pad], axis=0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref")
    ap.add_argument("--ref-text-file")
    ap.add_argument("--text")
    ap.add_argument("--out")
    ap.add_argument("--speed", type=float, default=1.0)
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--jobs")
    ap.add_argument("--device", default=None, help="cpu to match the old bake exactly (it ran on CPU only because its GPU could not run that PyTorch); default: GPU if present")
    args = ap.parse_args()

    if args.jobs:
        jobs = json.load(io.open(args.jobs, encoding="utf-8"))
    else:
        jobs = [{"text": args.text, "ref": args.ref, "ref_text_file": args.ref_text_file,
                 "out": args.out, "speed": args.speed, "seed": args.seed}]

    from f5_tts.api import F5TTS  # imported late: slow, and only here
    f5 = F5TTS(device=args.device) if args.device else F5TTS()
    for job in jobs:
        ref_text = io.open(job["ref_text_file"], encoding="utf-8").read().strip()
        wav, sr, _ = f5.infer(ref_file=job["ref"], ref_text=ref_text, gen_text=job["text"],
                              cfg_strength=2.0, speed=float(job.get("speed", 1.0)), seed=job.get("seed"))
        sf.write(job["out"], fix_tail(np.asarray(wav, dtype=np.float32), sr), sr)
        print("rendered", job["out"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
