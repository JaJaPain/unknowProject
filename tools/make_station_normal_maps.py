"""Bake hull-scale normal maps for ChatGPT's station and outpost skins.

Polish (Abe, 2026-10-04): the skins have colour and roughness maps and only a
faint micro normal, so the panel seams and wear on the hull read flat under
the sun. No new art: each skin's colour texture becomes a height field and a
Sobel gradient of it a normal map (OpenGL / Godot convention, +Y up), the same
route as tools/make_normal_maps.py for the rocks and planets.

The colour textures are tileable hull panels: thin dark seams, grime blotches
and bright scratches on flat grey. Raw brightness would turn the grime into
lumps, so the height is high-passed (only detail smaller than a panel), dark
lines are pressed in at full strength (seams, rivets) and anything brighter
than its surroundings is only lightly raised (scratches). The skin's existing
micro normal is blended on top at its authored strength (whiteout blend), so
nothing it gave is lost.

Writes <colour>_normal.png next to each colour texture; Station.gd swaps it in
for the micro normal when the model loads. Re-run after a skin changes:
    python tools/make_station_normal_maps.py
"""

import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
MODELS = sorted((ROOT / "assets" / "stations").glob("*.glb")) + sorted((ROOT / "assets" / "outposts").glob("*.glb"))
# How steep the bumps are, and how much of the light side is kept.
STRENGTH = 2.2
RAISED = 0.3
# Seams: how much darker than around them (a fraction of the local
# brightness) a line must be, and how deep they go; wear is the faint rest.
SEAM_LO = 0.15
SEAM_HI = 0.40
SEAM_DEPTH = 0.12
WEAR = 0.25
# Detail wider than this (pixels) is shading, not shape.
HIGHPASS = 10.0
BLUR = 1.4


def _gltf(path: Path) -> dict:
    data = path.read_bytes()
    length = struct.unpack("<I", data[12:16])[0]
    return json.loads(data[20:20 + length])


def _skin_textures(path: Path):
    """(colour texture, micro normal texture, micro strength) per textured material."""
    j = _gltf(path)
    images = [img.get("name") or Path(img.get("uri", "")).stem for img in j.get("images", [])]
    textures = j.get("textures", [])

    def file_of(ref):
        if not ref:
            return None
        p = path.with_name("%s_%s.png" % (path.stem, images[textures[ref["index"]]["source"]]))
        return p if p.exists() else None

    seen = set()
    for m in j.get("materials", []):
        colour = file_of(m.get("pbrMetallicRoughness", {}).get("baseColorTexture"))
        if colour is None or colour in seen:
            continue
        seen.add(colour)
        normal = m.get("normalTexture")
        yield colour, file_of(normal), float((normal or {}).get("scale", 1.0))


def _shift(a, dy, dx):
    return np.roll(np.roll(a, dx, axis=1), dy, axis=0)


def _height(img: Image.Image) -> np.ndarray:
    grey = img.convert("L")
    fine = np.asarray(grey.filter(ImageFilter.GaussianBlur(BLUR)), dtype=np.float32) / 255.0
    # Blur with wrap-around so the tile's edges match (pad, blur, crop).
    pad = int(HIGHPASS * 3)
    tiled = np.pad(np.asarray(grey, dtype=np.float32) / 255.0, pad, mode="wrap")
    broad = Image.fromarray((tiled * 255.0).astype(np.uint8)).filter(ImageFilter.GaussianBlur(HIGHPASS))
    broad = np.asarray(broad, dtype=np.float32)[pad:-pad, pad:-pad] / 255.0
    detail = fine - broad
    # Seams: clearly darker than their surroundings, pressed in at full depth.
    # Measured against the local brightness, so a dark skin's faint seams
    # count as much as a light one's.
    rel = detail / np.maximum(broad, 0.04)
    seams = np.clip((-rel - SEAM_LO) / (SEAM_HI - SEAM_LO), 0.0, 1.0)
    seams = seams * seams * (3.0 - 2.0 * seams)
    # Everything else (grime, brushing, scratches) only a faint texture: at
    # full strength it glitters where the sun grazes the hull.
    rest = np.where(detail < 0.0, detail, detail * RAISED) * WEAR
    return rest - seams * SEAM_DEPTH


def _normals(h: np.ndarray) -> np.ndarray:
    tl, t, tr = _shift(h, 1, 1), _shift(h, 1, 0), _shift(h, 1, -1)
    l, r = _shift(h, 0, 1), _shift(h, 0, -1)
    bl, b, br = _shift(h, -1, 1), _shift(h, -1, 0), _shift(h, -1, -1)
    dx = (tr + 2 * r + br) - (tl + 2 * l + bl)
    dy = (bl + 2 * b + br) - (tl + 2 * t + tr)
    n = np.stack([-dx * STRENGTH, dy * STRENGTH, np.ones_like(h)], axis=-1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def _micro(path: Path, size, strength: float) -> np.ndarray:
    img = Image.open(path).convert("RGB").resize(size, Image.BILINEAR)
    n = np.asarray(img, dtype=np.float32) / 255.0 * 2.0 - 1.0
    n[..., :2] *= strength
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def bake(colour: Path, micro: Path, micro_strength: float) -> Path:
    img = Image.open(colour).convert("RGB")
    n = _normals(_height(img))
    if micro is not None:
        m = _micro(micro, img.size, micro_strength)
        # Whiteout blend: add the slopes, multiply the up components.
        n = np.stack([n[..., 0] + m[..., 0], n[..., 1] + m[..., 1], n[..., 2] * m[..., 2]], axis=-1)
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
    out = ((n * 0.5 + 0.5) * 255.0).clip(0, 255).astype(np.uint8)
    dest = colour.with_name(colour.stem + "_normal.png")
    Image.fromarray(out).save(dest)
    return dest


if __name__ == "__main__":
    for model in MODELS:
        for colour, micro, strength in _skin_textures(model):
            print(bake(colour, micro, strength).relative_to(ROOT))
