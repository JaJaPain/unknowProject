"""Synthesize a jet-engine spool-up SFX for the jump-tunnel transit.

Layers: a rising turbine whine (harmonic stack, fundamental sweeps up),
a brightening broadband air-rush, and a low combustion rumble. Everything
ramps up over the clip so it reads as an engine winding to full power.

Usage:
    python tools/generate_jet_spool.py [duration_seconds] [rise_seconds] [out_path]

Defaults to a 10.0s clip whose pitch/level climb over the first 3.0s and
then HOLD at full power for the rest (the game fades it out when the ship
arrives). Re-run with different timings to fit a longer/shorter tunnel.
"""
import sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

DUR = float(sys.argv[1]) if len(sys.argv) > 1 else 10.0
RISE = float(sys.argv[2]) if len(sys.argv) > 2 else 3.0
OUT = sys.argv[3] if len(sys.argv) > 3 else "sound/ShipSounds/jet_spool_up.wav"
SR = 44100

START_HZ = 180.0   # idle whine
PEAK_HZ = 640.0    # plateau pitch (kept moderate, not shrill)

t = np.linspace(0.0, DUR, int(SR * DUR), endpoint=False)
n = len(t)

# Wind-up: climbs over the first RISE seconds (ease-in), then holds at 1.0.
rise = np.clip(t / RISE, 0.0, 1.0) ** 1.5


def lowpass(x, cutoff, order=2):
    b, a = butter(order, min(cutoff / (SR / 2), 0.99), btype="low")
    return lfilter(b, a, x)


# --- Turbine whine: fundamental climbs START->PEAK then plateaus ---
f0 = START_HZ + rise * (PEAK_HZ - START_HZ)
phase = 2 * np.pi * np.cumsum(f0) / SR
whine = np.zeros(n)
for h, amp in [(1, 1.0), (2, 0.5), (3, 0.30), (4, 0.16), (5, 0.08), (7, 0.04)]:
    whine += amp * np.sin(phase * h + 0.5 * h)
# Second, slightly detuned spool stage for a richer beating whine
f0b = f0 * 1.006 + 25.0
phaseb = 2 * np.pi * np.cumsum(f0b) / SR
for h, amp in [(1, 0.6), (2, 0.3), (3, 0.16)]:
    whine += amp * np.sin(phaseb * h)
whine /= np.max(np.abs(whine)) + 1e-9

# --- Broadband air rush: crossfade dark->bright as it winds up, then holds ---
noise = np.random.uniform(-1.0, 1.0, n)
air_dark = lowpass(noise, 700.0)
air_bright = lowpass(noise, 6000.0)
air = air_dark * (1.0 - rise) + air_bright * rise
air /= np.max(np.abs(air)) + 1e-9

# --- Low combustion rumble ---
rumble = lowpass(np.random.uniform(-1.0, 1.0, n), 120.0)
rumble /= np.max(np.abs(rumble)) + 1e-9

# --- Mix with per-layer wind-up envelopes ---
sig = (
    whine * (0.15 + rise * 0.85) * 0.5
    + air * (0.40 + rise * 0.60) * 0.45
    + rumble * (0.50 + rise * 0.50) * 0.5
)

# Wind-up level + a gentle sustain flutter so the hold isn't a dead tone.
flutter = 1.0 + 0.05 * np.sin(2 * np.pi * 5.5 * t) * rise
env = 0.3 + rise * 0.7
fade_in = np.clip(t / 0.05, 0.0, 1.0)
fade_out = np.clip((DUR - t) / 0.2, 0.0, 1.0)
sig *= env * flutter * fade_in * fade_out

# Normalize, soft-clip for a little grit, normalize again
sig /= np.max(np.abs(sig)) + 1e-9
sig = np.tanh(sig * 1.3)
sig /= np.max(np.abs(sig)) + 1e-9
sig *= 0.92

wavfile.write(OUT, SR, (sig * 32767).astype(np.int16))
print("wrote %s  (%.2fs, %d samples @ %d Hz)" % (OUT, DUR, n, SR))
