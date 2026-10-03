"""Synthesize the ship's engine loop for normal flight.

Playtest 2026-10-03 finding 6 (Abe): there was no engine sound in normal
flight, only the boost one-shot. This is a seamless loop the game plays
under flight; AudioManager rides its volume and pitch with the throttle.

Layers: a low combustion rumble (filtered brown noise), a soft roar
(band-passed noise), and a faint drone (55/110/165 Hz with a slow wobble
whose period divides the loop, so the loop point is seamless). The noise is
made longer than the loop and its tail crossfaded into its head.

Usage:
    python tools/generate_engine_loop.py [seconds] [out_path]
"""
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

DUR = float(sys.argv[1]) if len(sys.argv) > 1 else 6.0
OUT = sys.argv[2] if len(sys.argv) > 2 else "sound/ShipSounds/engine_loop.wav"
SR = 44100
FADE = 0.75  # seconds of tail crossfaded into the head

rng = np.random.default_rng(7)
n = int(SR * DUR)
nf = int(SR * FADE)


def lowpass(x, cutoff, order=2):
    b, a = butter(order, min(cutoff / (SR / 2), 0.99), btype="low")
    return lfilter(b, a, x)


def bandpass(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), hi / (SR / 2)], btype="band")
    return lfilter(b, a, x)


def seamless(x):
    """x has n + nf samples: fold the tail onto the head."""
    head, body, tail = x[:nf], x[nf:n], x[n:n + nf]
    ramp = np.linspace(0.0, 1.0, nf)
    return np.concatenate([tail * (1 - ramp) + head * ramp, body])


# Rumble: brown noise (integrated white), well below 140 Hz.
white = rng.standard_normal(n + nf + SR)
brown = np.cumsum(white)
brown -= lowpass(brown, 8.0)  # remove the drift
rumble = lowpass(brown, 140.0, 4)[SR:]
rumble /= np.max(np.abs(rumble)) + 1e-9

# Roar: band-passed noise, soft.
roar = bandpass(rng.standard_normal(n + nf + SR), 220.0, 1100.0)[SR:]
roar /= np.max(np.abs(roar)) + 1e-9

t = np.arange(n) / SR
# Drone: integer cycles per loop for the wobble so it lines up at the seam.
wobble = 1.0 + 0.015 * np.sin(2 * np.pi * (2.0 / DUR) * t)
drone = (np.sin(2 * np.pi * 55.0 * wobble * t) * 0.6
         + np.sin(2 * np.pi * 110.0 * t) * 0.3
         + np.sin(2 * np.pi * 165.0 * t) * 0.12)

mix = seamless(rumble) * 0.55 + seamless(roar) * 0.22 + drone * 0.18
mix /= np.max(np.abs(mix)) + 1e-9
mix *= 10 ** (-3.0 / 20.0)  # -3 dBFS peak; the game sets the level
wavfile.write(OUT, SR, (mix * 32767).astype(np.int16))
print(f"wrote {OUT}: {DUR:.1f}s seamless loop")
