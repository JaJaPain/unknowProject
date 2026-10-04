"""Synthesise the Scan Composition ping: the submarine sonar 'ping' (Abe,
2026-10-04). A pure tone with a soft attack and a long ringing decay, a faint
lower partial for body, and a few delayed, darker echoes for the open water
feel. Original audio, no samples.

    python tools/make_sonar_ping.py  ->  sound/ShipSounds/sonar_ping.wav
"""
import wave

import numpy as np

RATE = 44100
LENGTH_S = 3.2
FREQ = 1320.0


def tone(t: np.ndarray, freq: float, decay: float) -> np.ndarray:
    attack = np.clip(t / 0.006, 0.0, 1.0)
    return np.sin(2 * np.pi * freq * t) * attack * np.exp(-t / decay)


def main() -> None:
    t = np.arange(int(RATE * LENGTH_S)) / RATE
    ping = tone(t, FREQ, 0.55) + 0.18 * tone(t, FREQ * 0.5, 0.35) + 0.06 * tone(t, FREQ * 2.01, 0.12)
    out = ping.copy()
    # Echoes: later, quieter and duller (a one-pole low-pass per echo).
    for delay_s, gain in [(0.42, 0.32), (0.86, 0.18), (1.35, 0.09)]:
        shift = int(delay_s * RATE)
        echo = np.zeros_like(ping)
        echo[shift:] = ping[: len(ping) - shift] * gain
        smoothed = np.zeros_like(echo)
        acc = 0.0
        for i, v in enumerate(echo):
            acc += 0.35 * (v - acc)
            smoothed[i] = acc
        out += smoothed
    fade = np.clip((LENGTH_S - t) / 0.4, 0.0, 1.0)
    out *= fade
    out /= np.max(np.abs(out)) * 1.12
    data = (out * 32767).astype(np.int16)
    with wave.open("sound/ShipSounds/sonar_ping.wav", "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data.tobytes())
    print("wrote sound/ShipSounds/sonar_ping.wav")


if __name__ == "__main__":
    main()
