"""Bake tangent-space normal maps from the planet and asteroid textures.

Playtest 2026-10-03 finding 4 (Abe): the rocks and rocky planets read flat.
No new art: each texture's brightness is treated as height (lightly
blurred), and a Sobel gradient of it becomes a normal map (OpenGL / Godot
convention, +Y up). Writes <name>_normal.png next to each source.

- Atlases (3x3 grids of asteroid skins) are processed one cell at a time,
  wrapping inside the cell, so bumps never bleed across cell borders.
- The rocky planet wraps horizontally (the seam at the back has no line) and
  clamps at the poles.

Re-run after changing a source texture:
    python tools/make_normal_maps.py
Then import (Godot imports *_normal.png as normal maps via their .import).
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ATLASES = [
    ROOT / "assets" / "asteroidTextures.png",
    *sorted(p for p in (ROOT / "assets" / "asteroid_ores").glob("*.png") if not p.stem.endswith("_normal")),
]
PLANETS = [ROOT / "assets" / "planet_rocky.png"]
ATLAS_CELLS = 3
# How steep the bumps are. Rocks are seen up close; planets from far away.
ATLAS_STRENGTH = 3.0
PLANET_STRENGTH = 2.0
BLUR = 1.2


def _height(img: Image.Image) -> np.ndarray:
    grey = img.convert("L").filter(ImageFilter.GaussianBlur(BLUR))
    return np.asarray(grey, dtype=np.float32) / 255.0


def _normals(h: np.ndarray, strength: float, wrap_y: bool) -> np.ndarray:
    """Sobel on a height field; x always wraps, y wraps or clamps."""
    def shift(a, dy, dx):
        a = np.roll(a, dx, axis=1)
        if wrap_y:
            return np.roll(a, dy, axis=0)
        if dy == 0:
            return a
        pad = np.pad(a, ((1, 1), (0, 0)), mode="edge")
        return pad[1 - dy: 1 - dy + a.shape[0], :]

    tl, t, tr = shift(h, 1, 1), shift(h, 1, 0), shift(h, 1, -1)
    l, r = shift(h, 0, 1), shift(h, 0, -1)
    bl, b, br = shift(h, -1, 1), shift(h, -1, 0), shift(h, -1, -1)
    dx = (tr + 2 * r + br) - (tl + 2 * l + bl)
    dy = (bl + 2 * b + br) - (tl + 2 * t + tr)
    # Height rising to the right tilts the normal left; rising downward (+v)
    # tilts it toward +Y in OpenGL convention.
    n = np.stack([-dx * strength, dy * strength, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255.0).clip(0, 255).astype(np.uint8)


def bake_atlas(path: Path) -> Path:
    img = Image.open(path).convert("RGB")
    w, h = img.size
    out = np.zeros((h, w, 3), dtype=np.uint8)
    for cy in range(ATLAS_CELLS):
        for cx in range(ATLAS_CELLS):
            x0, x1 = cx * w // ATLAS_CELLS, (cx + 1) * w // ATLAS_CELLS
            y0, y1 = cy * h // ATLAS_CELLS, (cy + 1) * h // ATLAS_CELLS
            cell = _height(img.crop((x0, y0, x1, y1)))
            out[y0:y1, x0:x1] = _normals(cell, ATLAS_STRENGTH, wrap_y=True)
    dest = path.with_name(path.stem + "_normal.png")
    Image.fromarray(out).save(dest)
    return dest


def bake_planet(path: Path) -> Path:
    img = Image.open(path).convert("RGB")
    out = _normals(_height(img), PLANET_STRENGTH, wrap_y=False)
    dest = path.with_name(path.stem + "_normal.png")
    Image.fromarray(out).save(dest)
    return dest


if __name__ == "__main__":
    for p in ATLASES:
        print("atlas ", bake_atlas(p).relative_to(ROOT))
    for p in PLANETS:
        print("planet", bake_planet(p).relative_to(ROOT))
