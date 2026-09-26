"""Make a new ore's rock atlas by recolouring an existing one (Abe's idea).

The coloured veins and crusts move to a new hue; the grey rock stays as it
is. The cuprite atlas (green veins) is the usual source.

    python tools/recolor_ore_atlas.py <new_ore_id> purple|orange|red|blue|<hue degrees> [--source cuprite] [--preview]

Writes assets/asteroid_ores/<new_ore_id>.png (or only a small preview into
art_inbox/ with --preview). A new ore also needs an entry in
scripts/economy/OreTypes.gd before the game uses it.
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ATLAS_DIR = os.path.join(ROOT, "assets", "asteroid_ores")
PRESETS = {"purple": 280.0, "orange": 28.0, "red": 2.0, "blue": 215.0, "green": 150.0, "yellow": 58.0}
# Pixels below this saturation are rock and keep their colour; between the
# two thresholds the shift fades in, so vein edges stay soft.
SAT_LOW, SAT_HIGH = 0.12, 0.30


def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(axis=-1)
    mn = rgb.min(axis=-1)
    d = mx - mn
    h = np.zeros_like(mx)
    safe = d > 1e-6
    rm = safe & (mx == r)
    gm = safe & (mx == g) & ~rm
    bm = safe & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6.0
    h[gm] = (b - r)[gm] / d[gm] + 2.0
    h[bm] = (r - g)[bm] / d[bm] + 4.0
    h = h / 6.0
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0)
    return h, s, mx


def hsv_to_rgb(h, s, v):
    i = np.floor(h * 6.0).astype(int) % 6
    f = h * 6.0 - np.floor(h * 6.0)
    p = v * (1 - s)
    q = v * (1 - f * s)
    t = v * (1 - (1 - f) * s)
    out = np.zeros(h.shape + (3,))
    for k, (a, b, c) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        m = i == k
        out[m, 0], out[m, 1], out[m, 2] = a[m], b[m], c[m]
    return out


def recolor(src_path, hue_degrees):
    im = Image.open(src_path).convert("RGB")
    rgb = np.asarray(im).astype(np.float64) / 255.0
    h, s, v = rgb_to_hsv(rgb)
    # Shift every coloured pixel so the source's main vein hue lands on the
    # target (keeps the natural spread of hues within the veins).
    coloured = s > SAT_HIGH
    if not coloured.any():
        raise SystemExit("no coloured pixels in %s" % src_path)
    angles = h[coloured] * 2 * np.pi
    main = (np.arctan2(np.sin(angles).mean(), np.cos(angles).mean()) / (2 * np.pi)) % 1.0
    # Only the vein colour moves (pixels within about 60 degrees of it); other
    # accents, like cuprite's copper specks, keep theirs. The spread around
    # the vein hue is narrowed so the new colour reads clean.
    offset = ((h - main + 0.5) % 1.0) - 0.5
    shifted = (hue_degrees / 360.0 + offset * 0.35) % 1.0
    new = hsv_to_rgb(shifted, s, v)
    near = np.clip(1.0 - (np.abs(offset) * 360.0 - 45.0) / 25.0, 0.0, 1.0)
    weight = (np.clip((s - SAT_LOW) / (SAT_HIGH - SAT_LOW), 0.0, 1.0) * near)[..., None]
    out = rgb * (1 - weight) + new * weight
    return Image.fromarray(np.clip(out * 255.0 + 0.5, 0, 255).astype(np.uint8))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ore_id")
    ap.add_argument("colour")
    ap.add_argument("--source", default="cuprite")
    ap.add_argument("--preview", action="store_true")
    a = ap.parse_args()
    hue = PRESETS.get(a.colour.lower())
    if hue is None:
        try:
            hue = float(a.colour)
        except ValueError:
            sys.exit("colour must be one of %s or a hue in degrees" % ", ".join(PRESETS))
    img = recolor(os.path.join(ATLAS_DIR, a.source + ".png"), hue)
    if a.preview:
        path = os.path.join(ROOT, "art_inbox", "%s_preview.png" % a.ore_id)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        img.resize((420, 420)).save(path)
    else:
        path = os.path.join(ATLAS_DIR, a.ore_id + ".png")
        img.save(path)
    print(path)


if __name__ == "__main__":
    main()
